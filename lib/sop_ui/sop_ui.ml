open Procedural

module Node_inspector = struct
  type t = {
    prefix : string;
    node_id : int;
  }

  let create ?prefix node =
    let node_id = Node.id node in
    let prefix = Option.value ~default:(Printf.sprintf "node.%d" node_id) prefix in
    if String.trim prefix = "" then
      invalid_arg "Sop_ui.Node_inspector prefix must not be blank";
    { prefix; node_id }

  let node_id value = value.node_id
  let widget_name inspector local = inspector.prefix ^ "." ^ local

  type item =
    | Parameter of Parameter.field_view
    | Folder of string * item list

  let rec insert path field items = match path with
    | [] -> items @ [Parameter field]
    | name :: rest ->
        let rec loop reversed = function
          | [] -> List.rev_append reversed [Folder (name, insert rest field [])]
          | Folder (candidate, children) :: tail when candidate = name ->
              List.rev_append reversed
                (Folder (candidate, insert rest field children) :: tail)
          | item :: tail -> loop (item :: reversed) tail
        in
        loop [] items

  let tree fields = List.fold_left (fun items field ->
    insert field.Parameter.folder field items) [] fields

  let append_field inspector field ui =
    let name = widget_name inspector field.Parameter.name in
    match field.kind, field.current with
    | Parameter.Toggle_view, Parameter.Bool_value value ->
        Pxui.toggle ~name ~label:field.label ~value ui
    | Parameter.Integer_view range, Parameter.Int_value value ->
        Pxui.int_slider ~name ~label:field.label ~min:range.soft_min
          ~max:range.soft_max ~value ui
    | Parameter.Floating_view range, Parameter.Float_value value ->
        Pxui.slider ~name ~label:field.label ~min:range.soft_min
          ~max:range.soft_max ~value ui
    | Parameter.Text_view, Parameter.Text_value value ->
        Pxui.text_field ~name ~label:field.label ~value ui
    | Parameter.Choice_view options, Parameter.Choice_value value ->
        let selected = Option.value ~default:0
            (Array.find_index (String.equal value) options) in
        Pxui.choice ~name ~label:field.label ~options:(Array.to_list options)
          ~selected ui
    | _ -> invalid_arg "Sop_ui.Node_inspector: inconsistent field metadata"

  let append_node ?(expanded = []) inspector ~node ui =
    if Node.id node <> inspector.node_id then
      Pxui.label ~text:"Selected SOP is no longer in the graph" ui
    else
        let ui = Pxui.label ~text:(Node.label node) ui in
        let fields = Node.parameter_fields node in
        if fields = [] then Pxui.label ~text:"No exposed parameters" ui
        else
          let rec append_items path items ui =
            List.fold_left (fun ui -> function
              | Parameter field -> append_field inspector field ui
              | Folder (label, children) ->
                  let path = path @ [label] in
                  let key = String.concat "/" path in
                  let name = widget_name inspector ("folder." ^ key) in
                  Pxui.accordion ~name ~label ~expanded:(List.mem key expanded)
                    (append_items path children) ui) ui items
          in
          append_items [] (tree fields) ui

  let append ?expanded inspector ~graph ui =
    match Graph.find graph ~node_id:inspector.node_id with
    | None -> Pxui.label ~text:"Selected SOP is no longer in the graph" ui
    | Some node -> append_node ?expanded inspector ~node ui

  let local_name inspector name =
    let prefix = inspector.prefix ^ "." in
    let length = String.length prefix in
    if String.length name <= length || String.sub name 0 length <> prefix
    then None
    else Some (String.sub name length (String.length name - length))

  let changes inspector changes = List.filter_map (function
    | Pxui.Toggled (name, value) -> Option.map
        (fun name -> name, Parameter.Bool_value value) (local_name inspector name)
    | Pxui.Slid (name, value) -> Option.map
        (fun name -> name, Parameter.Float_value value) (local_name inspector name)
    | Pxui.Int_slid (name, value) -> Option.map
        (fun name -> name, Parameter.Int_value value) (local_name inspector name)
    | Pxui.Text_changed (name, value) -> Option.map
        (fun name -> name, Parameter.Text_value value) (local_name inspector name)
    | Pxui.Selected (name, value) -> Option.map
        (fun name -> name, Parameter.Choice_value value) (local_name inspector name)
    | Pxui.Clicked _ | Pxui.Ranged _ | Pxui.Moved2 _ -> None) changes

  let sync_field inspector ui field =
    let name = widget_name inspector field.Parameter.name in
    match field.kind, field.current with
    | Parameter.Toggle_view, Parameter.Bool_value value ->
        Pxui.set_toggle_value ui name value
    | Parameter.Integer_view _, Parameter.Int_value value ->
        Pxui.set_int_slider_value ui name value
    | Parameter.Floating_view _, Parameter.Float_value value ->
        Pxui.set_slider_value ui name value
    | Parameter.Text_view, Parameter.Text_value value ->
        Pxui.set_text_value ui name value
    | Parameter.Choice_view _, Parameter.Choice_value value ->
        Pxui.set_choice_value ui name value
    | _ -> invalid_arg "Sop_ui.Node_inspector: inconsistent field metadata"

  let sync_node inspector node ui =
    if Node.id node <> inspector.node_id then ui
    else List.fold_left (sync_field inspector) ui (Node.parameter_fields node)

  let sync inspector graph ui = match Graph.find graph ~node_id:inspector.node_id with
    | None -> ui | Some node -> sync_node inspector node ui

  let update_node inspector ~node ~ui pxui_changes =
    if Node.id node <> inspector.node_id then Error
        "selected SOP is no longer in the editable graph"
    else
      let changes = changes inspector pxui_changes in
      if changes = [] then Ok (node, ui, Parameter.no_effects)
      else Result.map (fun (node, effects) ->
        node, sync_node inspector node ui, effects)
        (Node.apply_parameters node changes)

  let update inspector ~graph ~ui pxui_changes =
    let changes = changes inspector pxui_changes in
    if changes = [] then Ok (graph, ui, Parameter.no_effects)
    else Result.map (fun (graph, effects) ->
      graph, sync inspector graph ui, effects)
      (Graph.apply_parameters graph ~node_id:inspector.node_id changes)

  let reset inspector ~graph ~ui = match Graph.find graph ~node_id:inspector.node_id with
    | None -> Error (Printf.sprintf "procedural graph has no node #%d"
        inspector.node_id)
    | Some node ->
        let changes = Node.parameter_fields node
          |> List.map (fun field -> field.Parameter.name, field.default) in
        Result.map (fun (graph, effects) ->
          graph, sync inspector graph ui, effects)
          (Graph.apply_parameters graph ~node_id:inspector.node_id changes)
end
