module Ids = Set.Make (Int)
type edge = { source : Port.t; consumer : int; index : int; slot : string }

let error code message = Error (Flow.Diagnostic.error ~code message)
let graph result = Result.map_error (Flow.Diagnostic.error ~code:"E_GEOMETRY") result
let ( let* ) = Result.bind

let clean_name name =
  let name = String.lowercase_ascii name |> String.map (function
    | 'a' .. 'z' | '0' .. '9' | '_' as c -> c | _ -> '_') in
  if Flow.Symbol.valid_name name then name else "input_" ^ name

let fresh_name base used =
  let rec loop index =
    let name = if index = 1 then base else base ^ "_" ^ string_of_int index in
    if List.mem name used then loop (index + 1) else name in
  loop 1

let geometry_port name : Network.interface_port =
  {name; ty = Flow.Port_type.Geometry; default = None;
   label = String.capitalize_ascii name; soft = None}

let edges (network : Network.t) =
  let nodes = Procedural.Edit_graph.inspect network.geometry in
  List.fold_left (fun state (node : Procedural.Edit_graph.node_info) ->
    let* reversed = state in
    let slots = Procedural.Edit_graph.node_slot_names network.geometry
      ~node_id:node.id |> Option.get |> Array.of_list in
    if Array.length slots <> Array.length node.inputs then
      error "E_GROUP" "Geometry slots changed during grouping"
    else
      Array.fold_left (fun state (index, input) ->
        let* reversed = state in
        match input with
        | None -> Ok reversed
        | Some _ ->
            let target = Port.{node = node.id; path = slots.(index)} in
            (match Network.geometry_source network target with
             | None -> error "E_GROUP" "Geometry source changed during grouping"
             | Some source -> Ok ({source; consumer = node.id;
                 index; slot = slots.(index)} :: reversed)))
        (Ok reversed) (Array.mapi (fun index input -> index, input) node.inputs))
    (Ok []) nodes |> Result.map List.rev

let geometry ~name ~selected ~displayed ~definitions (network : Network.t) =
  let selected = Ids.of_list selected in
  if not (Flow.Symbol.valid_name name) then error "E_SYMBOL" "Invalid compound name"
  else if Network.String_map.mem name definitions then
    error "E_DUPLICATE" ("Compound " ^ name ^ " already exists")
  else if Ids.is_empty selected then error "E_GROUP" "Select nodes to group"
  else if Ids.exists (fun id -> match Procedural.Edit_graph.find network.geometry ~node_id:id with
      | Some node -> List.mem (Procedural.Node.operation node)
          ["flow_inputs"; "flow_outputs"]
      | None -> Flow.Graph.find network.values ~node_id:id = None) selected then
    error "E_GROUP" "Only SOP, value and compound nodes can be grouped"
  else
  let* edges = edges network in
  let incoming = List.filter (fun edge ->
    Ids.mem edge.consumer selected && not (Ids.mem edge.source.node selected)) edges in
  let outgoing = List.filter (fun edge ->
    Ids.mem edge.source.node selected && not (Ids.mem edge.consumer selected)) edges in
  let input_sources_rev, input_names = List.fold_left (fun (sources, names) edge ->
    if Port.Map.mem edge.source names then sources, names else
    let used = List.map snd sources in
    let port_name = fresh_name (clean_name edge.slot) used in
    (edge.source, port_name) :: sources, Port.Map.add edge.source port_name names)
    ([], Port.Map.empty) incoming in
  let input_sources = List.rev input_sources_rev in
  let display_source = match displayed with
    | Some id when Ids.mem id selected ->
        (match Network.Int_map.find_opt id network.instances with
         | None -> Ok (Some Port.{node = id; path = "geo"})
         | Some instance ->
             (match Network.String_map.find_opt instance.definition definitions with
              | None -> error "E_UNBOUND" ("Missing compound " ^ instance.definition)
              | Some (definition : Network.definition) ->
                  (match List.find_opt (fun (port : Network.interface_port) ->
                    port.ty = Flow.Port_type.Geometry) definition.outputs with
                   | None -> error "E_GROUP" "Displayed compound has no geometry output"
                   | Some output -> Ok (Some Port.{node = id; path = output.name}))))
    | _ -> Ok None in
  let* display_source = display_source in
  let output_sources = List.map (fun edge -> edge.source) outgoing
    @ Option.to_list display_source in
  let output_sources_rev, output_names = List.fold_left (fun (sources, names) source ->
    if Port.Map.mem source names then sources, names else
    let port_name = fresh_name "result" (List.map snd sources) in
    (source, port_name) :: sources, Port.Map.add source port_name names)
    ([], Port.Map.empty) output_sources in
  let output_sources = List.rev output_sources_rev in
  let value_edges = Port.Map.bindings network.drives |> List.filter_map
    (fun (target, drive) -> match drive with
      | Drive.Expr _ -> None
      | Drive.Wire source ->
          Some (Port.{node = source.node; path = source.output}, target)) in
  let incoming_values = List.filter (fun ((source : Port.t), (target : Port.t)) ->
    Ids.mem target.node selected && not (Ids.mem source.node selected))
    value_edges in
  let outgoing_values = List.filter (fun ((source : Port.t), (target : Port.t)) ->
    Ids.mem source.node selected && not (Ids.mem target.node selected))
    value_edges in
  let geometry_inputs = List.map (fun (_, name) -> geometry_port name) input_sources
  and geometry_outputs = List.map (fun (_, name) -> geometry_port name) output_sources in
  let* input_value_sources, input_value_names =
    List.fold_left (fun state (source, target) ->
      let* reversed, names = state in
      if Port.Map.mem source names then Ok (reversed, names) else
      let* parameter = Network.parameter network target in
      let* ty = match parameter.ty with
        | Some ty -> Ok ty
        | None -> error "E_GROUP" "Literal-only row cannot become a value input" in
      let field = List.hd parameter.fields in
      let soft = match field.Param.kind with
        | Floating_view range -> Some (range.soft_min, range.soft_max)
        | Integer_view range -> Some (float_of_int range.soft_min,
            float_of_int range.soft_max)
        | _ -> None in
      let default = Some (Port.literal parameter) in
      let used = List.map (fun (port : Network.interface_port) -> port.name)
        geometry_inputs @ List.map (fun (_, name, _) -> name) reversed in
      let name = fresh_name (clean_name target.path) used in
      let port : Network.interface_port = {name; ty; default;
        label = field.label; soft} in
      Ok ((source, name, port) :: reversed, Port.Map.add source name names))
      (Ok ([], Port.Map.empty)) incoming_values
    |> Result.map (fun (reversed, names) -> List.rev reversed, names) in
  let* output_value_sources, output_value_names =
    List.fold_left (fun state (source, _) ->
      let* reversed, names = state in
      if Port.Map.mem source names then Ok (reversed, names) else
      let* ty = Network.output_type network source in
      let used = List.map (fun (port : Network.interface_port) -> port.name)
        geometry_outputs @ List.map (fun (_, name, _) -> name) reversed in
      let name = fresh_name (clean_name source.path) used in
      let port : Network.interface_port = {name; ty; default = None;
        label = String.capitalize_ascii name; soft = None} in
      Ok ((source, name, port) :: reversed, Port.Map.add source name names))
      (Ok ([], Port.Map.empty)) outgoing_values
    |> Result.map (fun (reversed, names) -> List.rev reversed, names) in
  let inputs = geometry_inputs @ List.map (fun (_, _, port) -> port) input_value_sources
  and outputs = geometry_outputs @ List.map (fun (_, _, port) -> port) output_value_sources in
  let factories = Compound_node.factories ~name ~inputs ~outputs in
  let inputs_factory = List.nth factories 0
  and outputs_factory = List.nth factories 1
  and instance_factory = List.nth factories 2 in
  let* inputs_node = graph (Procedural.Edit_graph.instantiate_optional inputs_factory []) in
  let* outputs_node = graph (Procedural.Edit_graph.instantiate_optional
    outputs_factory (List.map (fun _ -> None) geometry_outputs)) in
  let* instance_node = graph (Procedural.Edit_graph.instantiate_optional
    instance_factory (List.map (fun _ -> None) geometry_inputs)) in
  let inputs_id = Procedural.Node.id inputs_node
  and outputs_id = Procedural.Node.id outputs_node
  and instance_id = Procedural.Node.id instance_node in
  let body_geometry = Procedural.Edit_graph.subgraph (Ids.elements selected)
    network.geometry in
  let* body_geometry = graph (Procedural.Edit_graph.add_node
    ~factory:inputs_factory inputs_node body_geometry) in
  let* body_geometry = graph (Procedural.Edit_graph.add_node
    ~factory:outputs_factory ~inputs:(Array.make (List.length geometry_outputs) None)
    outputs_node body_geometry) in
  let* body_geometry = graph (Procedural.Edit_graph.set_root outputs_id body_geometry) in
  let body_outputs = Port.Map.filter (fun (target : Port.t) _ ->
    Ids.mem target.node selected
    && match Network.geometry_source network target with
       | Some source -> Ids.mem source.node selected | None -> false)
    network.geometry_outputs in
  let body_instances = Network.Int_map.filter (fun id _ -> Ids.mem id selected)
    network.instances in
  let* body_values = List.fold_left (fun state (node : Flow.Graph.node) ->
    let* values = state in
    if Ids.mem node.id selected then Flow.Graph.add_node node values
    else Ok values) (Ok Flow.Graph.empty) (Flow.Graph.inspect network.values) in
  let body_drives = Port.Map.filter (fun (target : Port.t) drive ->
    Ids.mem target.node selected && match drive with
      | Drive.Expr _ -> true
      | Drive.Wire source -> Ids.mem source.node selected) network.drives in
  let* body = Network.of_parts ~geometry:body_geometry ~values:body_values
    ~drives:body_drives ~geometry_outputs:body_outputs
    ~instances:body_instances in
  let* body = List.fold_left (fun state edge ->
    let* body = state in
    let source = Port.{node = inputs_id;
      path = Port.Map.find edge.source input_names} in
    Network.connect_geometry ~source ~consumer:edge.consumer
      ~input_index:edge.index body) (Ok body) incoming in
  let* body = List.fold_left (fun state (index, (source, _)) ->
    let* body = state in
    Network.connect_geometry ~source ~consumer:outputs_id ~input_index:index body)
    (Ok body) (List.mapi (fun index item -> index, item) output_sources) in
  let* body = List.fold_left (fun state (source, target) ->
    let* body = state in
    Network.connect_value
      ~source:Port.{node = inputs_id;
        path = Port.Map.find source input_value_names}
      ~target body) (Ok body) incoming_values in
  let* body = List.fold_left (fun state (source, name, _) ->
    let* body = state in
    Network.connect_value ~source
      ~target:Port.{node = outputs_id; path = name} body)
    (Ok body) output_value_sources in
  let definition : Network.definition = {
    name; context = Flow.Context.Sop; inputs; outputs; body} in
  let* parent = Network.remove_nodes (Ids.elements selected) network in
  let* geometry = graph (Procedural.Edit_graph.add_node ~factory:instance_factory
    ~inputs:(Array.make (List.length geometry_inputs) None) instance_node parent.geometry) in
  let instance : Network.instance = {definition = name;
    literals = Network.String_map.empty} in
  let* parent = Network.of_parts ~geometry ~values:parent.values
    ~drives:parent.drives ~geometry_outputs:parent.geometry_outputs
    ~instances:(Network.Int_map.add instance_id instance parent.instances) in
  let* parent = List.fold_left (fun state (index, (source, _)) ->
    let* parent = state in
    Network.connect_geometry ~source ~consumer:instance_id ~input_index:index parent)
    (Ok parent) (List.mapi (fun index item -> index, item) input_sources) in
  let* parent = List.fold_left (fun state edge ->
    let* parent = state in
    let source = Port.{node = instance_id;
      path = Port.Map.find edge.source output_names} in
    Network.connect_geometry ~source ~consumer:edge.consumer
      ~input_index:edge.index parent) (Ok parent) outgoing in
  let* parent = List.fold_left (fun state (source, _, _) ->
    let* parent = state in
    Network.connect_value ~source
      ~target:Port.{node = instance_id;
        path = Port.Map.find source input_value_names} parent)
    (Ok parent) input_value_sources in
  let* parent = List.fold_left (fun state (source, target) ->
    let* parent = state in
    Network.connect_value
      ~source:Port.{node = instance_id;
        path = Port.Map.find source output_value_names}
      ~target parent) (Ok parent) outgoing_values in
  let* parent = match display_source with
    | None -> Ok parent
    | Some _ ->
        let* geometry = graph (Procedural.Edit_graph.set_root instance_id
          parent.geometry) in
        Network.with_geometry geometry parent in
  Ok (parent, definition, instance_id)

let ungroup ~instance_id ~displayed ~(definition : Network.definition)
    (network : Network.t) =
  let* () = match Network.Int_map.find_opt instance_id network.instances with
    | Some instance when instance.definition = definition.name -> Ok ()
    | Some _ | None -> error "E_UNGROUP" "Select one compound instance to ungroup" in
  let marker operation = Procedural.Edit_graph.inspect definition.body.geometry
    |> List.filter (fun (node : Procedural.Edit_graph.node_info) ->
      node.operation = operation) in
  match marker "flow_inputs", marker "flow_outputs" with
  | [inputs_node], [outputs_node] ->
      let body = definition.body in
      let nodes = Procedural.Edit_graph.inspect body.geometry
        |> List.filter (fun (node : Procedural.Edit_graph.node_info) ->
          node.id <> inputs_node.id && node.id <> outputs_node.id)
        |> List.map (fun node -> node.Procedural.Edit_graph.id)
        |> fun ids -> ids @ List.map (fun (node : Flow.Graph.node) -> node.id)
          (Flow.Graph.inspect body.values) in
      let node_ids = Ids.of_list nodes in
      let input_sources = List.map (fun (port : Network.interface_port) ->
        port.name, Network.geometry_source network
          Port.{node = instance_id; path = port.name})
        (List.filter (fun (port : Network.interface_port) ->
          port.ty = Flow.Port_type.Geometry) definition.inputs) in
      let* body_edges = edges body in
      let incoming = List.filter (fun edge ->
        edge.source.node = inputs_node.id && Ids.mem edge.consumer node_ids) body_edges in
      let* parent_edges = edges network in
      let outgoing = List.filter (fun edge ->
        edge.source.node = instance_id) parent_edges in
      let* parent = Network.remove_nodes [instance_id] network in
      let* parent, mapping = match nodes with
        | [] -> Ok (parent, [])
        | _ -> let* fragment = Network.copy_nodes nodes body in
            Network.paste fragment parent in
      let ids = Network.Int_map.of_list mapping in
      let mapped id = match Network.Int_map.find_opt id ids with
        | Some id -> Ok id
        | None -> error "E_UNGROUP" "Compound body refers to an ungrouped node" in
      let input name = match List.assoc_opt name input_sources with
        | Some source -> Ok source
        | None -> error "E_UNGROUP" ("Unknown compound input " ^ name) in
      let source (port : Port.t) =
        if port.node = inputs_node.id then input port.path
        else let* node = mapped port.node in Ok (Some {port with node}) in
      let* parent = List.fold_left (fun state edge ->
        let* parent = state in
        let* input = input edge.source.path in
        match input with
        | None -> Ok parent
        | Some source ->
            let* consumer = mapped edge.consumer in
            Network.connect_geometry ~source ~consumer
              ~input_index:edge.index parent)
        (Ok parent) incoming in
      let outputs = List.map (fun (port : Network.interface_port) ->
        port.name, Network.geometry_source body
          Port.{node = outputs_node.id; path = port.name})
        (List.filter (fun (port : Network.interface_port) ->
          port.ty = Flow.Port_type.Geometry) definition.outputs) in
      let* outputs = List.fold_left (fun state (name, original) ->
        let* reversed = state in
        let* source = match original with None -> Ok None
          | Some port -> source port in
        Ok ((name, source) :: reversed)) (Ok []) outputs
        |> Result.map List.rev in
      let* parent = List.fold_left (fun state edge ->
        let* parent = state in
        match List.assoc_opt edge.source.path outputs with
        | Some (Some source) -> Network.connect_geometry ~source
            ~consumer:edge.consumer ~input_index:edge.index parent
        | Some None -> Ok parent
        | None -> error "E_UNGROUP"
            ("Unknown compound output " ^ edge.source.path))
        (Ok parent) outgoing in
      let component path = match String.rindex_opt path '.' with
        | None -> None
        | Some index ->
            let axis = String.sub path (index + 1)
              (String.length path - index - 1) in
            if List.mem axis ["x"; "y"; "z"] then
              Some (String.sub path 0 index, axis) else None in
      let splitters = ref Port.Map.empty in
      let project_value parent axis = function
        | `Literal (Port.Vector (x,y,z)) ->
            let number = match axis with "x" -> x | "y" -> y | _ -> z in
            Ok (parent, `Literal (Port.Scalar (Param.Float_value number)))
        | `Components parts ->
            let index = match axis with "x" -> 0 | "y" -> 1 | _ -> 2 in
            Ok (parent, List.nth parts index)
        | `Drive (Drive.Wire source) ->
            let source_port = Port.{node = source.node; path = source.output} in
            let* parent, splitter = match Port.Map.find_opt source_port !splitters with
              | Some id -> Ok (parent, id)
              | None ->
                  let* parent, id = Network.add_value_node
                    Flow.Value_kind.Separate_xyz parent in
                  let* parent = Network.connect_value ~source:source_port
                    ~target:Port.{node = id; path = "v"} parent in
                  splitters := Port.Map.add source_port id !splitters;
                  Ok (parent, id) in
            Ok (parent, `Drive (Drive.Wire {node = splitter; output = axis}))
        | _ -> error "E_UNGROUP" "Cannot project a non-vector compound value" in
      let rec input_value parent path =
        let target = Port.{node = instance_id; path} in
        match Port.Map.find_opt target network.drives with
        | Some drive -> Ok (parent, `Drive drive)
        | None ->
            (match component path with
             | Some (group, axis) ->
                 (match Port.Map.find_opt {target with path = group}
                     network.drives with
                  | Some drive -> project_value parent axis (`Drive drive)
                  | None -> Result.map (fun parameter ->
                      parent, `Literal (Port.literal parameter))
                      (Network.parameter network target))
             | None ->
                 let* parameter = Network.parameter network target in
                 if parameter.ty = Some Flow.Port_type.Vec3
                   && List.exists (fun axis -> Port.Map.mem
                     {target with path = path ^ "." ^ axis} network.drives)
                     ["x"; "y"; "z"] then
                   let* parent, parts = List.fold_left (fun state axis ->
                     let* parent, parts = state in
                     let* parent, part = input_value parent
                       (path ^ "." ^ axis) in
                     Ok (parent, part :: parts)) (Ok (parent, []))
                     ["x"; "y"; "z"] in
                   Ok (parent, `Components (List.rev parts))
                 else Ok (parent, `Literal (Port.literal parameter))) in
      let rec apply_value parent target = function
        | `Literal literal -> Network.set_literal ~target literal parent
        | `Drive (Drive.Expr expression) ->
            Network.set_expr ~target expression parent
        | `Drive (Drive.Wire source) -> Network.connect_value
            ~source:Port.{node = source.node; path = source.output}
            ~target parent
        | `Components parts ->
            List.fold_left2 (fun state axis part ->
              let* parent = state in
              apply_value parent {target with path = target.path ^ "." ^ axis}
                part) (Ok parent) ["x"; "y"; "z"] parts in
      let internal_value_drive parent = function
        | Drive.Expr expression -> Ok (parent, `Drive (Drive.Expr expression))
        | Drive.Wire source when source.node = inputs_node.id ->
            input_value parent source.output
        | Drive.Wire source ->
            let* node = mapped source.node in
            Ok (parent, `Drive (Drive.Wire {source with node})) in
      let rec output_value parent path =
        let output = Port.{node = outputs_node.id; path} in
        match Port.Map.find_opt output body.drives with
        | Some drive -> internal_value_drive parent drive
        | None ->
            (match component path with
             | Some (group, axis) ->
                 (match Port.Map.find_opt {output with path = group}
                     body.drives with
                  | Some drive ->
                      let* parent, value = internal_value_drive parent drive in
                      project_value parent axis value
                  | None -> Result.map (fun parameter ->
                      parent, `Literal (Port.literal parameter))
                      (Network.parameter body output))
             | None ->
                 let* parameter = Network.parameter body output in
                 if parameter.ty = Some Flow.Port_type.Vec3
                   && List.exists (fun axis -> Port.Map.mem
                     {output with path = path ^ "." ^ axis} body.drives)
                     ["x"; "y"; "z"] then
                   let* parent, parts = List.fold_left (fun state axis ->
                     let* parent, parts = state in
                     let* parent, part = output_value parent
                       (path ^ "." ^ axis) in
                     Ok (parent, part :: parts)) (Ok (parent, []))
                     ["x"; "y"; "z"] in
                   Ok (parent, `Components (List.rev parts))
                 else Ok (parent, `Literal (Port.literal parameter))) in
      let* parent = Port.Map.fold (fun (target : Port.t) drive state ->
        let* parent = state in
        match drive with
        | Drive.Wire source when source.node = inputs_node.id
            && Ids.mem target.node node_ids ->
            let* node = mapped target.node in
            let* parent, value = input_value parent source.output in
            apply_value parent {target with node} value
        | _ -> Ok parent) body.drives (Ok parent) in
      let* parent = Port.Map.fold (fun (target : Port.t) drive state ->
        let* parent = state in
        match drive with
        | Drive.Wire source when source.node = instance_id ->
            let* parent, value = output_value parent source.output in
            apply_value parent target value
        | _ -> Ok parent) network.drives (Ok parent) in
      let displayed = if displayed = Some instance_id then
        List.find_map (fun (_, source) -> Option.map (fun (port : Port.t) ->
          port.node) source) outputs else displayed in
      let* parent = match displayed with
        | Some id -> let* geometry = graph
            (Procedural.Edit_graph.set_root id parent.geometry) in
            Network.with_geometry geometry parent
        | None -> Ok parent in
      Ok (parent, mapping, displayed)
  | _ -> error "E_UNGROUP" "Compound is missing its Inputs or Outputs marker"
