type scope = {
  network : Network.t;
  path : int list;
  parent : (scope * int) option;
  definition : Network.definition option;
}
type lowered = Literal of Port.literal | Driven of Drive.t
  | Components of lowered list

let error code message = Error (Flow.Diagnostic.error ~code message)
let geometry result = Result.map_error (Flow.Diagnostic.error ~code:"E_GEOMETRY") result
let port node path = {Port.node; path}
let geometry_ports ports = List.filter (fun (port : Network.interface_port) ->
  port.ty = Flow.Port_type.Geometry) ports
let special operation network =
  Procedural.Edit_graph.inspect network.Network.geometry
  |> List.filter (fun (node : Procedural.Edit_graph.node_info) ->
    node.operation = operation)

let flatten ?(allocate = true) ~(definitions : Network.definition Network.String_map.t)
    ~compiled_ids (network : Network.t) =
  if Network.Int_map.is_empty network.instances then Ok (network, compiled_ids) else
  let flat = ref Procedural.Edit_graph.empty and ids = ref compiled_ids in
  let values = ref network.values and drives = ref Port.Map.empty in
  let pending = ref [] and scopes = Hashtbl.create 32 in
  let child scope instance_id definition =
    let path = scope.path @ [instance_id] in
    match Hashtbl.find_opt scopes path with
    | Some child -> child
    | None ->
        let child = {network = definition.Network.body; path;
          parent = Some (scope, instance_id); definition = Some definition} in
        Hashtbl.add scopes path child;
        pending := child :: !pending;
        child in
  let built = Hashtbl.create 64 and visiting = Hashtbl.create 64 in
  let compiled path inner =
    if path = [] then Ok inner else
    let key = path @ [inner] in
    match Instance_path.Map.find_opt key !ids with
    | Some id -> Ok id
    | None when not allocate -> error "E_IDS" "Compound node has no saved compiled id"
    | None ->
        let id = Procedural.Node.Private.fresh_id () in
        ids := Instance_path.Map.add key id !ids; Ok id in
  let clone_value scope (node : Flow.Graph.node) =
    Result.bind (compiled scope.path node.id) (fun id ->
      if Flow.Graph.find !values ~node_id:id <> None then Ok id else
        Result.bind (Flow.Graph.clone_node ~id node) (fun node ->
          Result.map (fun next -> values := next; id)
            (Flow.Graph.add_node node !values))) in
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
                               let child = child scope source.node definition in
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
                 Result.bind (compiled scope.path source.node) (fun id ->
                 Result.bind (geometry (Procedural.Edit_graph.paste
                   ~ids:[source.node, id] fragment !flat)) (fun (graph, _) ->
                   flat := graph;
                   let connected = List.fold_left (fun state (index, input) ->
                     Result.bind state (fun graph -> match input with
                       | None -> Ok graph
                       | Some source -> geometry (Procedural.Edit_graph.connect
                           ~source ~consumer:id ~input_index:index graph)))
                     (Ok !flat) (List.mapi (fun index input -> index, input) inputs) in
                   Result.map (fun graph -> flat := graph; id) connected))))) in
  let value_visiting = Hashtbl.create 64 in
  let rec lower_input scope (target : Port.t) =
    match Port.Map.find_opt target scope.network.drives with
    | Some drive -> lower_drive scope drive
    | None ->
        let component = List.find_map (fun axis ->
          let suffix = "." ^ axis in
          if String.ends_with ~suffix target.path then
            Some (String.sub target.path 0
              (String.length target.path - String.length suffix), axis)
          else None) ["x"; "y"; "z"] in
        (match component with
         | Some (group, axis) ->
             (match Port.Map.find_opt {target with path = group}
                 scope.network.drives with
              | Some drive -> project_drive scope drive axis
              | None -> Result.map (fun parameter -> Literal (Port.literal parameter))
                  (Network.parameter scope.network target))
         | None -> Result.bind (Network.parameter scope.network target)
             (fun parameter ->
               let axes = ["x"; "y"; "z"] in
               if parameter.ty = Some Flow.Port_type.Vec3
                 && List.exists (fun axis -> Port.Map.mem
                   {target with path = target.path ^ "." ^ axis}
                   scope.network.drives) axes then
                 Result.map (fun parts -> Components (List.rev parts))
                   (List.fold_left (fun state axis -> Result.bind state (fun parts ->
                     Result.map (fun part -> part :: parts)
                       (lower_input scope {target with path = target.path ^ "." ^ axis})))
                     (Ok []) axes)
               else Ok (Literal (Port.literal parameter))))
  and lower_drive scope = function
    | Drive.(Expr _ | Live _) as drive -> Ok (Driven drive)
    | Drive.Wire source -> lower_source scope source.node source.output
  and project_drive scope drive axis = match drive with
    | Drive.(Expr _ | Live _) as drive -> Ok (Driven drive)
    | Drive.Wire source ->
        Result.bind (Network.output_type scope.network
          (port source.node source.output)) (function
          | Flow.Port_type.Vec3 ->
              (match Flow.Graph.find scope.network.values ~node_id:source.node with
               | Some node when Flow.Value_kind.kind node.parameters
                   = Flow.Value_kind.Combine_xyz ->
                   lower_input scope (port source.node axis)
               | Some _ -> error "E_TYPE" "Vec3 source cannot expose components"
               | None -> lower_source scope source.node
                   (source.output ^ "." ^ axis))
          | _ -> lower_source scope source.node source.output)
  and lower_source scope node output =
    let key = scope.path, node, output in
    if Hashtbl.mem value_visiting key then
      error "E_CYCLE" "Compound value wire contains a cycle"
    else begin
      Hashtbl.add value_visiting key ();
      let result = lower_source_uncached scope node output in
      Hashtbl.remove value_visiting key;
      result
    end
  and lower_source_uncached scope node output =
    match Flow.Graph.find scope.network.values ~node_id:node with
    | Some node -> Result.map (fun id -> Driven
        (Drive.Wire {node = id; output}))
        (clone_value scope node)
    | None -> match Network.Int_map.find_opt node scope.network.instances with
      | Some instance ->
          (match Network.String_map.find_opt instance.definition definitions with
           | None -> error "E_UNBOUND" ("Missing compound " ^ instance.definition)
           | Some definition ->
               let rec ancestor scope = match scope.definition, scope.parent with
                 | Some current, Some (parent, _) ->
                     current.name = definition.name || ancestor parent
                 | _ -> false in
               if ancestor scope then error "E_RECURSIVE"
                 ("Compound " ^ definition.name ^ " contains itself")
               else (match special "flow_outputs" definition.body with
                 | [marker] -> lower_input (child scope node definition)
                     (port marker.id output)
                 | _ -> error "E_INTERFACE" "Compound body needs one Outputs node"))
      | None ->
          (match Procedural.Edit_graph.find scope.network.geometry
              ~node_id:node with
           | Some node when Procedural.Node.operation node = "flow_inputs" ->
               (match scope.parent with
                | Some (parent, instance_id) -> lower_input parent
                    (port instance_id output)
                | None -> error "E_INTERFACE" "Inputs node is outside a compound")
           | _ -> error "E_PORT" ("No value output " ^ output)) in
  let typed = function
    | Port.Scalar (Param.Float_value number) -> Ok (Flow.Port_type.Float_value number)
    | Scalar (Param.Int_value number) -> Ok (Flow.Port_type.Int_value number)
    | Scalar (Param.Bool_value value) -> Ok (Flow.Port_type.Bool_value value)
    | Vector (x,y,z) -> Ok (Flow.Port_type.Vec3_value (x,y,z))
    | Scalar _ -> error "E_TYPE" "Compound value has no numeric or Boolean literal" in
  let apply_literal scope target (mapped : Port.t) literal =
    Result.bind (Network.parameter scope.network target) (fun parameter ->
      Result.bind (typed literal) (fun value ->
        Result.bind (Port.normalize parameter value) (fun (_, changes) ->
          match Flow.Graph.find !values ~node_id:mapped.node with
          | Some _ -> Result.map (fun (next, _) -> values := next)
              (Flow.Graph.apply_parameters !values ~node_id:mapped.node changes)
          | None -> Result.map (fun (next, _) -> flat := next)
              (geometry (Procedural.Edit_graph.apply_parameters !flat
                ~node_id:mapped.node changes))))) in
  let rec apply_lowered scope target mapped = function
    | Literal literal -> apply_literal scope target mapped literal
    | Driven drive -> drives := Port.Map.add mapped drive !drives; Ok ()
    | Components parts ->
        Result.bind (Network.parameter scope.network target) (fun parameter ->
          if parameter.ty <> Some Flow.Port_type.Vec3
            || List.length parts <> 3 then
            error "E_TYPE" "Compound vector has no Vec3 destination"
          else List.fold_left2 (fun state axis part -> Result.bind state
            (fun () -> apply_lowered scope
              {target with path = target.path ^ "." ^ axis}
              {mapped with path = mapped.path ^ "." ^ axis} part))
            (Ok ()) ["x"; "y"; "z"] parts) in
  let process_drive scope (target : Port.t) drive =
    if Network.Int_map.mem target.node scope.network.instances then Ok () else
    match Flow.Graph.find scope.network.values ~node_id:target.node with
    | Some node ->
        Result.bind (clone_value scope node) (fun id ->
          let mapped = {target with node = id} in
          Result.bind (lower_drive scope drive)
            (apply_lowered scope target mapped))
    | None -> match Procedural.Edit_graph.find scope.network.geometry
        ~node_id:target.node with
      | Some node when List.mem (Procedural.Node.operation node)
          ["flow_inputs"; "flow_outputs"] -> Ok ()
      | Some _ ->
          let id = if scope.path = [] then Some target.node else
            Instance_path.Map.find_opt (scope.path @ [target.node]) !ids in
          (match id with
           | None -> Ok ()
           | Some id when Procedural.Edit_graph.find !flat ~node_id:id = None -> Ok ()
           | Some id ->
               let mapped = {target with node = id} in
               Result.bind (lower_drive scope drive)
                 (apply_lowered scope target mapped))
      | None -> error "E_UNBOUND" "Compound drive target is missing" in
  let rec process_scopes () = match !pending with
    | [] -> Ok ()
    | scope :: rest ->
        pending := rest;
        let cloned = List.fold_left (fun state node -> Result.bind state (fun () ->
          Result.map (fun _ -> ()) (clone_value scope node))) (Ok ())
          (Flow.Graph.inspect scope.network.values) in
        Result.bind cloned (fun () ->
          Result.bind (Port.Map.fold (fun target drive state ->
            Result.bind state (fun () -> process_drive scope target drive))
            scope.network.drives (Ok ())) (fun () -> process_scopes ())) in
  (* ponytail: recursion follows compound depth; E_DEPTH reports the stack
     ceiling. Use an explicit work stack if deep compounds become common. *)
  try
    let root_scope = {network; path = []; parent = None; definition = None} in
    pending := [root_scope];
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
                    | output :: _ -> output.name | [] -> "geo")
               | None -> "geo") else "geo")) []) in
      Result.bind root (fun root ->
        let graph = match root with
          | None -> Ok !flat
          | Some id -> geometry (Procedural.Edit_graph.set_root id !flat) in
        Result.bind graph (fun geometry ->
          flat := geometry;
          Result.bind (process_scopes ()) (fun () ->
            Result.map (fun network -> network, !ids)
              (Network.of_parts ~geometry:!flat ~values:!values
                ~drives:!drives ~geometry_outputs:Port.Map.empty
                ~instances:Network.Int_map.empty)))))
  with Stack_overflow -> error "E_DEPTH" "Compound nesting exceeds the stack capacity"
