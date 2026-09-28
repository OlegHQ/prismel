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
      | None -> true
      | Some node -> List.mem (Procedural.Node.operation node)
          ["flow_inputs"; "flow_outputs"]) selected then
    error "E_GROUP" "Only ordinary SOP and compound nodes can be grouped"
  else if Port.Map.exists (fun (target : Port.t) drive ->
      Ids.mem target.node selected || match drive with
        | Drive.Expr _ -> false
        | Drive.Wire source -> Ids.mem source.node selected) network.drives then
    error "E_GROUP" "Group driven nodes after exporting their value ports"
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
  let inputs = List.map (fun (_, name) -> geometry_port name) input_sources
  and outputs = List.map (fun (_, name) -> geometry_port name) output_sources in
  let factories = Compound_node.factories ~name ~inputs ~outputs in
  let inputs_factory = List.nth factories 0
  and outputs_factory = List.nth factories 1
  and instance_factory = List.nth factories 2 in
  let* inputs_node = graph (Procedural.Edit_graph.instantiate_optional inputs_factory []) in
  let* outputs_node = graph (Procedural.Edit_graph.instantiate_optional
    outputs_factory (List.map (fun _ -> None) outputs)) in
  let* instance_node = graph (Procedural.Edit_graph.instantiate_optional
    instance_factory (List.map (fun _ -> None) inputs)) in
  let inputs_id = Procedural.Node.id inputs_node
  and outputs_id = Procedural.Node.id outputs_node
  and instance_id = Procedural.Node.id instance_node in
  let body_geometry = Procedural.Edit_graph.subgraph (Ids.elements selected)
    network.geometry in
  let* body_geometry = graph (Procedural.Edit_graph.add_node
    ~factory:inputs_factory inputs_node body_geometry) in
  let* body_geometry = graph (Procedural.Edit_graph.add_node
    ~factory:outputs_factory ~inputs:(Array.make (List.length outputs) None)
    outputs_node body_geometry) in
  let* body_geometry = graph (Procedural.Edit_graph.set_root outputs_id body_geometry) in
  let body_outputs = Port.Map.filter (fun (target : Port.t) _ ->
    Ids.mem target.node selected
    && match Network.geometry_source network target with
       | Some source -> Ids.mem source.node selected | None -> false)
    network.geometry_outputs in
  let body_instances = Network.Int_map.filter (fun id _ -> Ids.mem id selected)
    network.instances in
  let* body = Network.of_parts ~geometry:body_geometry ~values:Flow.Graph.empty
    ~drives:Port.Map.empty ~geometry_outputs:body_outputs
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
  let definition : Network.definition = {
    name; context = Flow.Context.Sop; inputs; outputs; body} in
  let* parent = Network.remove_nodes (Ids.elements selected) network in
  let* geometry = graph (Procedural.Edit_graph.add_node ~factory:instance_factory
    ~inputs:(Array.make (List.length inputs) None) instance_node parent.geometry) in
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
  let* parent = match display_source with
    | None -> Ok parent
    | Some _ ->
        let* geometry = graph (Procedural.Edit_graph.set_root instance_id
          parent.geometry) in
        Network.with_geometry geometry parent in
  Ok (parent, definition, instance_id)

let ungroup ~instance_id ~displayed ~(definition : Network.definition)
    (network : Network.t) =
  let* instance = match Network.Int_map.find_opt instance_id network.instances with
    | Some instance when instance.definition = definition.name -> Ok instance
    | Some _ | None -> error "E_UNGROUP" "Select one compound instance to ungroup" in
  if Flow.Graph.inspect definition.body.values <> []
      || not (Port.Map.is_empty definition.body.drives)
      || not (Network.String_map.is_empty instance.literals)
      || List.exists (fun (port : Network.interface_port) ->
        port.ty <> Flow.Port_type.Geometry) (definition.inputs @ definition.outputs)
      || Port.Map.exists (fun (target : Port.t) drive ->
        target.node = instance_id || match drive with
          | Drive.Expr _ -> false
          | Drive.Wire source -> source.node = instance_id) network.drives
  then error "E_UNGROUP" "Value interfaces are not supported by ungroup yet"
  else
  let marker operation = Procedural.Edit_graph.inspect definition.body.geometry
    |> List.filter (fun (node : Procedural.Edit_graph.node_info) ->
      node.operation = operation) in
  match marker "flow_inputs", marker "flow_outputs" with
  | [inputs_node], [outputs_node] ->
      let body = definition.body in
      let nodes = Procedural.Edit_graph.inspect body.geometry
        |> List.filter (fun (node : Procedural.Edit_graph.node_info) ->
          node.id <> inputs_node.id && node.id <> outputs_node.id)
        |> List.map (fun node -> node.Procedural.Edit_graph.id) in
      let node_ids = Ids.of_list nodes in
      let input_sources = List.map (fun (port : Network.interface_port) ->
        port.name, Network.geometry_source network
          Port.{node = instance_id; path = port.name}) definition.inputs in
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
          Port.{node = outputs_node.id; path = port.name}) definition.outputs in
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
