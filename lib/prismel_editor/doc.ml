open Procedural

let flow_result result = Result.map_error Flow.Diagnostic.to_string result
let update_geometry edit document =
  Result.bind (edit document.Flow_sop.Network.geometry) (fun geometry ->
    flow_result (Flow_sop.Network.with_geometry geometry document))
let apply_parameters document ~node_id values =
  match Flow.Graph.find document.Flow_sop.Network.values ~node_id with
  | Some _ -> flow_result (Flow_sop.Network.apply_value_parameters document ~node_id values)
  | None -> Result.bind (Edit_graph.apply_parameters document.geometry ~node_id values)
      (fun (geometry, effects) -> Result.map (fun document -> document, effects)
        (update_geometry (fun _ -> Ok geometry) document))

let value_kind key = match String.split_on_char '/' key with
  | ["value"; kind] -> Result.map (fun kind -> kind, None) (flow_result (Flow.Value_kind.of_key kind))
  | ["value"; "math"; op] when List.mem_assoc op Flow.Expr.operators ->
      Ok (Flow.Value_kind.Math, Some op)
  | _ -> Error ("unknown value kind " ^ key)

let cook_effects = Parameter.add_impact Parameter.Cook Parameter.no_effects

let find_factory factories key = List.find_opt (fun factory ->
  String.equal key (Edit_graph.factory_key factory)) factories

let input_nodes document input_slots =
  let rec loop reversed = function
    | [] -> Ok (List.rev reversed)
    | None :: rest -> loop (None :: reversed) rest
    | Some id :: rest ->
        (match Edit_graph.find document.Flow_sop.Network.geometry ~node_id:id with
         | None -> Error (Printf.sprintf "selected input node #%d no longer exists" id)
         | Some node -> loop (Some node :: reversed) rest)
  in
  loop [] input_slots

let instantiate factories document key input_ids =
  match find_factory factories key with
  | None -> Error (Printf.sprintf "unknown SOP type %S" key)
  | Some factory when List.length input_ids > Edit_graph.factory_arity factory ->
      Error (Printf.sprintf "%s accepts at most %d selected input%s"
        (Edit_graph.factory_label factory) (Edit_graph.factory_arity factory)
        (if Edit_graph.factory_arity factory = 1 then "" else "s"))
  | Some factory ->
      let supplied = Array.of_list input_ids in
      let slots = Array.init (Edit_graph.factory_arity factory) (fun index ->
        if index < Array.length supplied then Some supplied.(index) else None) in
      Result.bind (input_nodes document (Array.to_list slots)) (fun nodes ->
        Result.map (fun node -> node, slots, factory)
          (Edit_graph.instantiate_optional factory nodes))

let append_value_source document ~node_id = function
  | None -> Ok document
  | Some source ->
      Result.bind (flow_result (Flow_sop.Network.output_type document source))
        (fun source_type ->
          Result.bind (flow_result (Flow_sop.Network.parameters document ~node_id))
            (fun parameters ->
              match List.find_opt (fun (parameter : Flow_sop.Port.parameter) ->
                Option.fold ~none:false ~some:(fun target ->
                  Flow.Port_type.can_connect ~source:source_type ~target) parameter.ty)
                  parameters with
              | None -> Error "The new node has no compatible value input"
              | Some parameter -> flow_result (Flow_sop.Network.connect_value ~source
                  ~target:{Flow_sop.Port.node = node_id; path = parameter.path}
                  document)))

let set_expression (document : Flow_sop.Network.t) target text =
  let body = if String.starts_with ~prefix:"=" text then
    String.sub text 1 (String.length text - 1) else text in
  Result.bind (flow_result (Flow.Expr.parse body)) (function
    | Flow.Expr.Num number ->
        let was_driven = Flow_sop.Port.Map.mem target document.drives in
        Result.bind (flow_result (Flow_sop.Network.parameter document target))
          (fun parameter -> Result.bind (flow_result (Flow_sop.Port.normalize parameter
            (Flow.Port_type.Float_value number))) (fun (_, changes) ->
            Result.bind (flow_result (Flow_sop.Network.clear_drive ~target document))
              (fun document -> Result.map (fun (document, effects) -> document,
                if was_driven then Parameter.union_effects effects cook_effects
                else effects) (apply_parameters document ~node_id:target.node changes))))
    | expression -> Result.map (fun changed -> changed,
        if changed == document then Parameter.no_effects else cook_effects)
        (flow_result (Flow_sop.Network.set_expr ~target expression document)))

(* Folds one graph intent into the document and view; [placed] collects the
   ids whose tile position this frame set, moved, or removed, so the undo
   document re-reads only those, and [pasted] the (source, copy) id pairs. *)
let apply factories (document, graph_view, error, effects, placed, pasted) = function
  | Pxui_graph.Connect_requested connection ->
      (match update_geometry (Edit_graph.connect ~source:connection.source
          ~consumer:connection.consumer ~input_index:connection.input_index) document with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok document -> document, Pxui_graph.with_document document graph_view,
           None, Parameter.union_effects effects cook_effects, placed, pasted)
  | Disconnect_requested connection ->
      (match update_geometry (Edit_graph.disconnect ~consumer:connection.consumer
          ~input_index:connection.input_index) document with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok document -> document, (graph_view
           |> Pxui_graph.set_bends ~node:connection.consumer ~slot:connection.input_index []
           |> Pxui_graph.with_document document),
           None, Parameter.union_effects effects cook_effects, placed, pasted)
  | Value_connect_requested {source; target} ->
      (match flow_result (Flow_sop.Network.connect_value ~source ~target document) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok document ->
           let graph_view = match String.rindex_opt target.path '.' with
             | None -> graph_view
             | Some dot -> Pxui_graph.set_split ~node:target.node
                 ~group:(String.sub target.path 0 dot) ~split:true graph_view in
           document, Pxui_graph.with_document document graph_view,
           None, Parameter.union_effects effects cook_effects, placed, pasted)
  | Value_bind_requested {source; target} ->
      (match flow_result (Flow_sop.Network.connect_value ~source ~target document) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok document ->
           let graph_view = match String.rindex_opt target.path '.' with
             | None -> graph_view
             | Some dot -> Pxui_graph.set_split ~node:target.node
                 ~group:(String.sub target.path 0 dot) ~split:true graph_view in
           let graph_view = graph_view |> Pxui_graph.with_document document
             |> Pxui_graph.set_wireless ~target ~wireless:true in
           document, graph_view, None,
           Parameter.union_effects effects cook_effects, placed, pasted)
  | Wireless_changed {target; wireless} ->
      if not (Editor_document.Document.wire_exists document
        (target.node, target.path)) then
        document, graph_view, Some "The selected wire no longer exists", effects,
        placed, pasted
      else document, Pxui_graph.set_wireless ~target ~wireless graph_view,
        None, effects, placed, pasted
  | Row_reset_requested target ->
      let reset = if Flow_sop.Port.Map.mem target document.drives then
        Result.map (fun document -> document, cook_effects)
          (flow_result (Flow_sop.Network.clear_drive ~target document))
      else Result.bind (flow_result (Flow_sop.Network.parameter document target))
        (fun parameter -> apply_parameters document ~node_id:target.node
          (List.map (fun (field : Parameter.field_view) ->
            field.name, field.default) parameter.fields)) in
      (match reset with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok (document, changed) ->
           document, Pxui_graph.with_document document graph_view, None,
           Parameter.union_effects effects changed, target.node :: placed, pasted)
  | Expression_requested {target; text} ->
      (match set_expression document target text with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok (document, changed) ->
           document, Pxui_graph.with_document document graph_view, None,
           Parameter.union_effects effects changed, target.node :: placed, pasted)
  | Fold_requested target ->
      (match flow_result (Flow_sop.Network.fold ~target document) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok (document, removed) ->
           document, Pxui_graph.with_document document graph_view, None,
           Parameter.union_effects effects cook_effects,
           List.rev_append removed (target.node :: placed), pasted)
  | Unfold_requested target ->
      (match flow_result (Flow_sop.Network.unfold ~target document) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok (document, nodes) ->
           let x, y = match List.find_opt (fun (id, _, _) -> id = target.node)
             (Pxui_graph.node_positions graph_view) with
             | Some (_, x, y) -> x, y | None -> 0., 0. in
           let positions = List.map (fun (id, column, row) ->
             id, x -. float column *. 220., y +. row *. 48.) nodes in
           let graph_view = graph_view |> Pxui_graph.with_document document
             |> Pxui_graph.place_nodes positions in
           document, graph_view, None, Parameter.union_effects effects cook_effects,
           List.rev_append (List.map (fun (id, _, _) -> id) nodes)
             (target.node :: placed), pasted)
  | Value_disconnect_requested target ->
      (match flow_result (Flow_sop.Network.disconnect ~target document) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok document -> document, Pxui_graph.with_document document graph_view,
           None, Parameter.union_effects effects cook_effects, placed, pasted)
  | Cut_wires_requested connections ->
      let disconnected = List.fold_left (fun state (c : Edit_graph.connection) ->
        Result.bind state (update_geometry (Edit_graph.disconnect ~consumer:c.consumer
          ~input_index:c.input_index))) (Ok document) connections in
      (match disconnected with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok document ->
           let graph_view = List.fold_left (fun view (c : Edit_graph.connection) ->
             Pxui_graph.set_bends ~node:c.consumer ~slot:c.input_index [] view)
               graph_view connections |> Pxui_graph.with_document document in
           document, graph_view, None, Parameter.union_effects effects cook_effects,
           placed, pasted)
  | Set_parameter_requested { node; path; value } ->
      (match apply_parameters document ~node_id:node [path, value] with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok (document, changed) ->
           document, Pxui_graph.with_document document graph_view, None,
           Parameter.union_effects effects changed, node :: placed, pasted)
  | Rename_requested {node; label} ->
      (match flow_result (Flow_sop.Network.relabel ~node_id:node label document) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok document -> document, Pxui_graph.with_document document graph_view,
           None, effects, node :: placed, pasted)
  | Split_requested {node; group; split} ->
      let target = {Flow_sop.Port.node; path = group} in
      (match flow_result (Flow_sop.Network.parameter document target) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok parameter when parameter.ty <> Some Flow.Port_type.Vec3 ->
           document, graph_view, Some (group ^ " is not a vector"), effects, placed, pasted
       | Ok parameter ->
           let driven path = Flow_sop.Port.Map.mem {target with path} document.drives in
           let conflict = if split then driven group else
             List.exists (fun (part : Flow_sop.Port.parameter) -> driven part.path)
               (Flow_sop.Port.components parameter) in
           if conflict then document, graph_view,
             Some ("Clear the " ^ group ^ " drive before changing its split"), effects, placed, pasted
           else document, Pxui_graph.set_split ~node ~group ~split graph_view,
             None, effects, node :: placed, pasted)
  | Row_pinned {node; path; pinned} ->
      (match flow_result (Flow_sop.Network.parameter document {node; path}) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok _ -> document, Pxui_graph.set_row_pin ~node ~path ~pinned graph_view,
           None, effects, node :: placed, pasted)
  | Bend_changed _ -> document, graph_view, error, effects, placed, pasted
  | Level_changed ids -> document, graph_view, error, effects,
      List.rev_append ids placed, pasted
  | Delete_nodes_requested ids ->
      (match flow_result (Flow_sop.Network.remove_nodes ids document) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok document -> document, Pxui_graph.with_document document graph_view, None,
           Parameter.union_effects effects cook_effects, List.rev_append ids placed, pasted)
  | Dissolve_nodes_requested ids ->
      let displayed = Pxui_graph.viewed graph_view in
      let geometry = document.Flow_sop.Network.geometry in
      let geometry = if List.mem displayed ids then
          Result.value ~default:geometry (Edit_graph.set_root displayed geometry) else geometry in
      let dissolved = Result.bind (flow_result (Flow_sop.Network.remove_nodes ids document))
          (update_geometry (fun _ -> Ok (Edit_graph.dissolve_nodes ids geometry))) in
      (match dissolved with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok document -> document, Pxui_graph.with_document document graph_view, None,
           Parameter.union_effects effects cook_effects, List.rev_append ids placed, pasted)
  | Bypass_requested changes ->
      let changed = List.fold_left (fun state (node_id, bypass) ->
        Result.bind state (fun document -> update_geometry (fun geometry -> Edit_graph.set_bypass geometry ~node_id bypass) document))
        (Ok document) changes in
      (match changed with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok changed -> changed, Pxui_graph.with_document changed graph_view, None,
           Parameter.union_effects effects cook_effects, placed, pasted)
  | Notice _ -> document, graph_view, error, effects, placed, pasted
  | Add_requested request ->
      (if String.starts_with ~prefix:"value/" request.factory_key then
         (match value_kind request.factory_key with
          | Error message -> document, graph_view, Some message, effects, placed, pasted
          | Ok (kind, op) ->
              let label = Option.map String.capitalize_ascii op in
              (match flow_result (Flow_sop.Network.add_value_node ?label kind document) with
               | Error message -> document, graph_view, Some message, effects, placed, pasted
               | Ok (added, id) ->
                   let changed = Option.fold ~none:(Ok added)
                     ~some:(fun op -> flow_result (Flow_sop.Network.set_literal
                       ~target:{node = id; path = "op"}
                       (Flow_sop.Port.Scalar (Parameter.Choice_value op)) added)) op in
                   let changed = Result.bind changed (fun document ->
                     append_value_source document ~node_id:id request.source) in
                   (match changed with
                    | Error message -> document, graph_view, Some message, effects, placed, pasted
                    | Ok document ->
                        let x, y = request.at in
                        let graph_view = graph_view
                          |> Pxui_graph.with_document document
                          |> Pxui_graph.place_nodes [id, x, y]
                          |> Pxui_graph.with_last_added request.factory_key
                          |> Pxui_graph.select id in
                        document, graph_view, None, effects, id :: placed, pasted)))
       else match instantiate factories document request.factory_key request.inputs with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok (node, slots, factory) ->
           (match Result.bind
               (update_geometry (Edit_graph.add_node ~inputs:slots ~factory node) document)
               (fun document -> append_value_source document ~node_id:(Node.id node)
                 request.source) with
            | Error message -> document, graph_view, Some message, effects, placed, pasted
            | Ok document ->
                let connected = Edit_graph.factory_ready factory
                    (Array.to_list slots |> List.map (function
                      | None -> None
                      | Some node_id ->
                          Edit_graph.find document.Flow_sop.Network.geometry ~node_id)) in
                let document = if connected then
                    match update_geometry (Edit_graph.set_root (Node.id node)) document with
                    | Ok document -> document | Error _ -> document
                  else document in
                let x, y = request.at in
                let graph_view = graph_view
                  |> Pxui_graph.with_document document
                  |> Pxui_graph.place_nodes [Node.id node, x, y]
                  |> Pxui_graph.with_last_added request.factory_key
                  |> Pxui_graph.select (Node.id node) in
                let graph_view = if connected
                  then Pxui_graph.view (Node.id node) graph_view else graph_view in
                document, graph_view, None,
                Parameter.union_effects effects cook_effects, Node.id node :: placed, pasted))
  | Insert_requested request ->
      (match instantiate factories document request.factory_key
          [request.connection.source] with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok (node, _, factory) ->
           (match update_geometry (Edit_graph.insert_on_connection ~factory
               request.connection node) document with
            | Error message -> document, graph_view, Some message, effects, placed, pasted
            | Ok document ->
                let x, y = request.at in
                let graph_view = graph_view
                  |> Pxui_graph.with_document document
                  |> Pxui_graph.place_nodes [Node.id node, x, y]
                  |> Pxui_graph.place_nodes request.ripple
                  |> Pxui_graph.with_last_added request.factory_key
                  |> Pxui_graph.select (Node.id node)
                  |> Pxui_graph.view (Node.id node) in
                document, graph_view, None,
                Parameter.union_effects effects cook_effects,
                Node.id node :: List.rev_append (List.map (fun (id, _, _) -> id) request.ripple) placed,
                pasted))
  | Paste_requested request ->
      (match flow_result (Flow_sop.Network.paste request.fragment document) with
       | Error message -> document, graph_view, Some message, effects, placed, pasted
       | Ok (document, mapping) ->
           let pasted_mapping = pasted in
           let pasted = List.map snd mapping in
           let graph_view = Pxui_graph.with_document document graph_view
             |> Pxui_graph.place_nodes (List.filter_map (fun (old_id, new_id) ->
                 List.find_map (fun (id, x, y) ->
                   if id = old_id then Some (new_id, x, y) else None)
                   request.positions) mapping)
             |> Pxui_graph.select_nodes pasted in
           document, graph_view, None,
           Parameter.union_effects effects cook_effects,
           List.rev_append pasted placed, mapping @ pasted_mapping)
  | Node_moved id -> document, graph_view, error, effects, id :: placed, pasted
  | Nodes_moved ids -> document, graph_view, error, effects, List.rev_append ids placed,
      pasted
  | Selected _ | Viewed _ | View_changed | Open_requested _
  | Connection_selected _ | Flag_requested _ | Frame_camera_requested _ ->
      document, graph_view, error, effects, placed, pasted
