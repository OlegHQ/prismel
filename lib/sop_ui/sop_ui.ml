open Procedural
module Ui = Pxui.Ui

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

  (* The field name is the widget key; the label is only displayed. *)
  let field_widget ui (field : Parameter.field_view) =
    let label = field.label ^ "##" ^ field.name in
    let edited value = if value = field.current then None
      else Some (field.name, value) in
    match field.kind, field.current with
    | Parameter.Toggle_view, Parameter.Bool_value value ->
        edited (Parameter.Bool_value (Ui.toggle ui label value))
    | Parameter.Integer_view range, Parameter.Int_value value ->
        edited (Parameter.Int_value
          (Ui.int_slider ui label ~range:(range.soft_min, range.soft_max) value))
    | Parameter.Floating_view range, Parameter.Float_value value ->
        edited (Parameter.Float_value
          (Ui.slider ui label ~range:(range.soft_min, range.soft_max) value))
    | Parameter.Text_view, Parameter.Text_value value ->
        edited (Parameter.Text_value (Ui.text_field ui label value))
    | Parameter.Choice_view options, Parameter.Choice_value value ->
        let selected = Option.value ~default:0
            (Array.find_index (String.equal value) options) in
        let chosen = Ui.choice ui label (Array.to_list options) selected in
        edited (Parameter.Choice_value options.(chosen))
    | _ -> invalid_arg "Sop_ui.Node_inspector: inconsistent field metadata"

  let rows ?(expanded = []) inspector ui node =
    Ui.scope ui inspector.prefix (fun () ->
      Ui.label ui (Node.label node);
      let fields = Node.parameter_fields node in
      if fields = [] then (Ui.label ui "No exposed parameters"; [])
      else
        let rec build path items = List.concat_map (function
          | Parameter field -> Option.to_list (field_widget ui field)
          | Folder (label, children) ->
              let path = path @ [label] in
              let key = String.concat "/" path in
              Option.value ~default:[]
                (Ui.accordion ui ~expanded:(List.mem key expanded)
                   (label ^ "##folder." ^ key) (fun () -> build path children)))
            items in
        build [] (tree fields))

  let missing ui = Ui.label ui "Selected SOP is no longer in the graph"

  let widgets ?expanded inspector ui ~node =
    if Node.id node <> inspector.node_id then (missing ui; Ok (node, Parameter.no_effects))
    else match rows ?expanded inspector ui node with
      | [] -> Ok (node, Parameter.no_effects)
      | changes -> Node.apply_parameters node changes

  let graph_widgets ?expanded inspector ui ~graph =
    match Graph.find graph ~node_id:inspector.node_id with
    | None -> missing ui; Ok (graph, Parameter.no_effects)
    | Some node ->
        match rows ?expanded inspector ui node with
        | [] -> Ok (graph, Parameter.no_effects)
        | changes -> Graph.apply_parameters graph ~node_id:inspector.node_id changes

  let reset inspector ~graph = match Graph.find graph ~node_id:inspector.node_id with
    | None -> Error (Printf.sprintf "procedural graph has no node #%d"
        inspector.node_id)
    | Some node ->
        Graph.apply_parameters graph ~node_id:inspector.node_id
          (Node.parameter_fields node
           |> List.map (fun field -> field.Parameter.name, field.default))
end
