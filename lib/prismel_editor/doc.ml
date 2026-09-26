open Procedural

let cook_effects = Parameter.add_impact Parameter.Cook Parameter.no_effects

let find_factory factories key = List.find_opt (fun factory ->
  String.equal key (Edit_graph.factory_key factory)) factories

let input_nodes document input_slots =
  let rec loop reversed = function
    | [] -> Ok (List.rev reversed)
    | None :: rest -> loop (None :: reversed) rest
    | Some id :: rest ->
        (match Edit_graph.find document ~node_id:id with
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

(* Folds one graph intent into the document and view; [placed] collects the
   ids whose tile position this frame set, moved, or removed, so the undo
   document re-reads only those. *)
let apply factories (document, graph_view, error, effects, placed) = function
  | Pxui_graph.Connect_requested connection ->
      (match Edit_graph.connect ~source:connection.source
          ~consumer:connection.consumer ~input_index:connection.input_index document with
       | Error message -> document, graph_view, Some message, effects, placed
       | Ok document -> document, Pxui_graph.with_document document graph_view,
           None, Parameter.union_effects effects cook_effects, placed)
  | Disconnect_requested connection ->
      (match Edit_graph.disconnect ~consumer:connection.consumer
          ~input_index:connection.input_index document with
       | Error message -> document, graph_view, Some message, effects, placed
       | Ok document -> document, Pxui_graph.with_document document graph_view,
           None, Parameter.union_effects effects cook_effects, placed)
  | Delete_nodes_requested ids ->
      let document = Edit_graph.remove_nodes ids document in
      document, Pxui_graph.with_document document graph_view, None,
      Parameter.union_effects effects cook_effects, List.rev_append ids placed
  | Add_requested request ->
      (match instantiate factories document request.factory_key request.inputs with
       | Error message -> document, graph_view, Some message, effects, placed
       | Ok (node, slots, factory) ->
           (match Edit_graph.add_node ~inputs:slots ~factory node document with
            | Error message -> document, graph_view, Some message, effects, placed
            | Ok document ->
                let connected = Edit_graph.factory_ready factory
                    (Array.to_list slots |> List.map (function
                      | None -> None
                      | Some node_id ->
                          Edit_graph.find document ~node_id)) in
                let document = if connected then
                    match Edit_graph.set_root (Node.id node) document with
                    | Ok document -> document | Error _ -> document
                  else document in
                let x, y = request.at in
                let graph_view = graph_view
                  |> Pxui_graph.with_document document
                  |> Pxui_graph.place_nodes [Node.id node, x, y]
                  |> Pxui_graph.select (Node.id node) in
                let graph_view = if connected
                  then Pxui_graph.view (Node.id node) graph_view else graph_view in
                document, graph_view, None,
                Parameter.union_effects effects cook_effects, Node.id node :: placed))
  | Insert_requested request ->
      (match instantiate factories document request.factory_key
          [request.connection.source] with
       | Error message -> document, graph_view, Some message, effects, placed
       | Ok (node, _, factory) ->
           (match Edit_graph.insert_on_connection ~factory
               request.connection node document with
            | Error message -> document, graph_view, Some message, effects, placed
            | Ok document ->
                let x, y = request.at in
                let graph_view = graph_view
                  |> Pxui_graph.with_document document
                  |> Pxui_graph.place_nodes [Node.id node, x, y]
                  |> Pxui_graph.select (Node.id node)
                  |> Pxui_graph.view (Node.id node) in
                document, graph_view, None,
                Parameter.union_effects effects cook_effects, Node.id node :: placed))
  | Paste_requested request ->
      (match Edit_graph.paste request.fragment document with
       | Error message -> document, graph_view, Some message, effects, placed
       | Ok (document, mapping) ->
           let pasted = List.map snd mapping in
           let graph_view = Pxui_graph.with_document document graph_view
             |> Pxui_graph.place_nodes (List.filter_map (fun (old_id, new_id) ->
                 List.find_map (fun (id, x, y) ->
                   if id = old_id then Some (new_id, x, y) else None)
                   request.positions) mapping)
             |> Pxui_graph.select_nodes pasted in
           document, graph_view, None,
           Parameter.union_effects effects cook_effects,
           List.rev_append pasted placed)
  | Node_moved id -> document, graph_view, error, effects, id :: placed
  | Nodes_moved ids -> document, graph_view, error, effects, List.rev_append ids placed
  | Selected _ | Viewed _ | View_changed
  | Connection_selected _ | Flag_requested _ | Frame_camera_requested _ ->
      document, graph_view, error, effects, placed
