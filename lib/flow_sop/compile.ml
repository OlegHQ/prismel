type scope = {
  network : Network.t;
  path : int list;
  parent : (scope * int) option;
  definition : Network.definition option;
}

let error code message = Error (Flow.Diagnostic.error ~code message)
let geometry result = Result.map_error (Flow.Diagnostic.error ~code:"E_GEOMETRY") result
let port node path = {Port.node; path}
let geometry_ports ports = List.filter (fun (port : Network.interface_port) ->
  port.ty = Flow.Port_type.Geometry) ports
let special operation network =
  Procedural.Edit_graph.inspect network.Network.geometry
  |> List.filter (fun (node : Procedural.Edit_graph.node_info) ->
    node.operation = operation)

let flatten ~(definitions : Network.definition Network.String_map.t)
    ~compiled_ids (network : Network.t) =
  if Network.Int_map.is_empty network.instances then Ok (network, compiled_ids) else
  let flat = ref Procedural.Edit_graph.empty and ids = ref compiled_ids in
  let built = Hashtbl.create 64 and visiting = Hashtbl.create 64 in
  let compiled path inner =
    if path = [] then inner else
    let key = path @ [inner] in
    match Instance_path.Map.find_opt key !ids with
    | Some id -> id
    | None ->
        let id = Procedural.Node.Private.fresh_id () in
        ids := Instance_path.Map.add key id !ids; id in
  let rec resolve scope (source : Port.t) stack =
    let key = scope.path, source.node, source.path in
    match Hashtbl.find_opt built key with
    | Some id -> Ok id
    | None when Hashtbl.mem visiting key ->
        error "E_RECURSIVE" "Compound geometry contains a cycle"
    | None ->
        Hashtbl.add visiting key ();
        let result = resolve_uncached scope source stack in
        Hashtbl.remove visiting key;
        Result.iter (fun id -> Hashtbl.replace built key id) result;
        result
  and resolve_uncached scope source stack =
    match Network.Int_map.find_opt source.node scope.network.instances with
    | Some instance ->
        (match Network.String_map.find_opt instance.definition definitions with
         | None -> error "E_UNBOUND" ("Missing compound " ^ instance.definition)
         | Some definition when List.mem definition.name stack ->
             error "E_RECURSIVE" ("Compound " ^ definition.name ^ " contains itself")
         | Some definition ->
             let outputs = geometry_ports definition.outputs in
             (match List.find_index (fun (port : Network.interface_port) ->
                 port.name = source.path) outputs with
              | None -> error "E_PORT" ("No geometry output " ^ source.path)
              | Some index ->
                  let body = definition.body in
                  if Flow.Graph.inspect body.values <> []
                    || not (Port.Map.is_empty body.drives)
                    || List.exists (fun (port : Network.interface_port) ->
                      port.ty <> Flow.Port_type.Geometry)
                        (definition.inputs @ definition.outputs) then
                    error "E_COMPOUND" "Value ports inside compounds are not flattened yet"
                  else
                    (match special "flow_outputs" body with
                     | [outputs_node] ->
                         let inputs = Option.get (Procedural.Edit_graph.inputs
                           body.geometry ~node_id:outputs_node.id) in
                         if index >= Array.length inputs then
                           error "E_PORT" "Compound Outputs node has too few ports"
                         else (match inputs.(index) with
                           | None -> error "E_PORT" ("Compound output " ^ source.path ^ " is disconnected")
                           | Some _ ->
                               let slot = Option.get (Procedural.Edit_graph.node_slot_names
                                 body.geometry ~node_id:outputs_node.id)
                                 |> Array.of_list |> fun slots -> slots.(index) in
                               let input = Option.get (Network.geometry_source body
                                 (port outputs_node.id slot)) in
                               let child = {network = body; path = scope.path @ [source.node];
                                 parent = Some (scope, source.node);
                                 definition = Some definition} in
                               resolve child input (definition.name :: stack))
                     | _ -> error "E_INTERFACE" "Compound body needs one Outputs node")))
    | None ->
        (match Procedural.Edit_graph.find scope.network.geometry ~node_id:source.node with
         | None -> error "E_UNBOUND" (Printf.sprintf "No geometry node %d" source.node)
         | Some node when Procedural.Node.operation node = "flow_inputs" ->
             (match scope.parent, scope.definition with
              | Some (parent, instance_id), Some definition ->
                  let inputs = geometry_ports definition.inputs in
                  (match List.find_index (fun (port : Network.interface_port) ->
                    port.name = source.path) inputs with
                   | None -> error "E_PORT" ("No compound input " ^ source.path)
                   | Some index ->
                       let slots = Option.get (Procedural.Edit_graph.node_slot_names
                         parent.network.geometry ~node_id:instance_id) |> Array.of_list in
                       if index >= Array.length slots then error "E_PORT" "Compound has too few input slots"
                       else
                         let target = port instance_id slots.(index) in
                         (match Network.geometry_source parent.network target with
                          | None -> error "E_PORT" ("Compound input " ^ source.path ^ " is disconnected")
                          | Some parent_source -> resolve parent parent_source
                              (match stack with _ :: rest -> rest | [] -> [])))
              | _ -> error "E_INTERFACE" "Inputs node is outside a compound")
         | Some node when Procedural.Node.operation node = "flow_outputs" ->
             error "E_INTERFACE" "Outputs node cannot be a geometry source"
         | Some _ when source.path <> "geo" ->
             error "E_PORT" ("No geometry output " ^ source.path)
         | Some _ ->
             let input_ids = Option.get (Procedural.Edit_graph.inputs
               scope.network.geometry ~node_id:source.node) in
             let slots = Option.get (Procedural.Edit_graph.node_slot_names
               scope.network.geometry ~node_id:source.node) |> Array.of_list in
             let rec resolve_inputs index reversed =
               if index = Array.length input_ids then Ok (List.rev reversed)
               else match input_ids.(index) with
                 | None -> resolve_inputs (index + 1) (None :: reversed)
                 | Some _ ->
                     let target = port source.node slots.(index) in
                     (match Network.geometry_source scope.network target with
                      | None -> error "E_PORT" "Geometry input has no source"
                      | Some input -> Result.bind (resolve scope input stack)
                          (fun id -> resolve_inputs (index + 1) (Some id :: reversed))) in
             Result.bind (resolve_inputs 0 []) (fun inputs ->
               Result.bind (geometry (Procedural.Edit_graph.copy_nodes
                 [source.node] scope.network.geometry)) (fun fragment ->
                 let id = compiled scope.path source.node in
                 Result.bind (geometry (Procedural.Edit_graph.paste
                   ~ids:[source.node, id] fragment !flat)) (fun (graph, _) ->
                   flat := graph;
                   let connected = List.fold_left (fun state (index, input) ->
                     Result.bind state (fun graph -> match input with
                       | None -> Ok graph
                       | Some source -> geometry (Procedural.Edit_graph.connect
                           ~source ~consumer:id ~input_index:index graph)))
                     (Ok !flat) (List.mapi (fun index input -> index, input) inputs) in
                   Result.map (fun graph -> flat := graph; id) connected)))) in
  try
    let root_scope = {network; path = []; parent = None; definition = None} in
    let nodes = Procedural.Edit_graph.inspect network.geometry in
    let checked = List.fold_left (fun state (node : Procedural.Edit_graph.node_info) ->
      Result.bind state (fun () ->
        if Network.Int_map.mem node.id network.instances then Ok ()
        else Result.map (fun _ -> ()) (resolve root_scope (port node.id "geo") [])))
      (Ok ()) nodes in
    Result.bind checked (fun () ->
      let root = Procedural.Edit_graph.root network.geometry in
      let root = match root with None -> Ok None
        | Some id -> Result.map Option.some (resolve root_scope
            (port id (if Network.Int_map.mem id network.instances then
              (match Network.String_map.find_opt
                (Network.Int_map.find id network.instances).definition definitions with
               | Some definition ->
                   (match geometry_ports definition.outputs with
                    | [output] -> output.name | _ -> "geo")
               | None -> "geo") else "geo")) []) in
      Result.bind root (fun root ->
        let graph = match root with
          | None -> Ok !flat
          | Some id -> geometry (Procedural.Edit_graph.set_root id !flat) in
        Result.bind graph (fun geometry ->
          Result.map (fun network -> network, !ids)
            (Network.of_parts ~geometry ~values:network.values
              ~drives:network.drives ~geometry_outputs:Port.Map.empty
              ~instances:Network.Int_map.empty))))
  with Stack_overflow -> error "E_DEPTH" "Compound nesting exceeds the stack capacity"
