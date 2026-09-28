(* Everything the user edits and saves, as one immutable value: the one
   thing [Editor_core.History] snapshots. Selection, hover, the open level,
   and the unlinked viewport camera are view state and stay outside. *)
open Procedural
module Canvas = Editor_core.Network_layout
module Layout = Canvas.Int_map
module String_map = Map.Make (String)

(* One node network with its graph-space tile positions and display node. *)
type network = {
  context : Flow.Context.t;
  graph : Flow_sop.Network.t;
  layout : Canvas.t;
  displayed : int option;  (* None exactly when geometry is empty *)
}

let of_geometry ~context graph displayed =
  { context; graph = Flow_sop.Network.of_geometry graph; layout = Canvas.empty; displayed }

type definition = {
  spec : Flow_sop.Network.definition;
  layout : Canvas.t;
  displayed : int option;
}

type t = {
  scene : network;  (* objects: input 0 is the parent *)
  networks : network Layout.t;  (* by object id: SOP networks, the World's layers *)
  definitions : definition String_map.t;
  compiled_ids : int Flow_sop.Instance_path.Map.t;
  active_camera : int option;  (* a camera object *)
  settings : Settings.t;
}

let flow_definitions value = String_map.fold (fun name definition definitions ->
  Flow_sop.Network.String_map.add name definition.spec definitions)
  value.definitions Flow_sop.Network.String_map.empty

let allocate_compiled_ids value =
  let definitions = flow_definitions value in
  let ids = Layout.fold (fun _ network state -> Result.bind state (fun ids ->
    if network.context <> Flow.Context.Sop
      || Flow_sop.Network.Int_map.is_empty network.graph.instances then Ok ids
    else
      let geometry = match network.displayed with
        | None -> Ok network.graph.geometry
        | Some displayed -> Result.map_error
            (Flow.Diagnostic.error ~code:"E_GEOMETRY")
            (Edit_graph.set_root displayed network.graph.geometry) in
      Result.bind geometry (fun geometry ->
        Result.bind (Flow_sop.Network.with_geometry geometry network.graph)
          (fun graph -> Result.map snd
            (Flow_sop.Compile.flatten ~definitions ~compiled_ids:ids graph)))))
    value.networks (Ok value.compiled_ids) in
  Result.map (fun compiled_ids -> if compiled_ids = value.compiled_ids then value
    else {value with compiled_ids}) ids

(* The network shown in the graph pane. *)
type level = Scene | Inside of int

let network value = function
  | Scene -> Some value.scene
  | Inside id -> Layout.find_opt id value.networks

let with_network value level network = match level with
  | Scene -> { value with scene = network }
  | Inside id -> { value with networks = Layout.add id network value.networks }

let group value level ~selected ~positions =
  let ( let* ) = Result.bind in
  match network value level with
  | None -> Error (Flow.Diagnostic.error ~code:"E_GROUP" "No network to group")
  | Some network when network.context <> Flow.Context.Sop ->
      Error (Flow.Diagnostic.error ~code:"E_GROUP" "Only SOP nodes can be grouped")
  | Some network ->
      let rec free index =
        let name = "compound_" ^ string_of_int index in
        if String_map.mem name value.definitions then free (index + 1) else name in
      let name = free 1 in
      let at = List.fold_left (fun at (id, x, y) ->
        Layout.add id (Canvas.snap x, Canvas.snap y) at)
        network.layout.at positions in
      let original_layout = {network.layout with at} in
      let network = {network with layout = original_layout} in
      let* parent, spec, instance = Flow_sop.Group.geometry ~name ~selected
        ~displayed:network.displayed ~definitions:(flow_definitions value)
        network.graph in
      let selected_set = Flow_sop.Network.Int_map.of_list
        (List.map (fun id -> id, ()) selected) in
      let inside id = Flow_sop.Network.Int_map.mem id selected_set in
      let selected_positions = List.filter_map (fun id ->
        Option.map (fun (x, y) -> x, y) (Layout.find_opt id at)) selected in
      let min_x, min_y, max_x = match selected_positions with
        | [] -> 0., 0., 0.
        | (x, y) :: rest -> List.fold_left (fun (min_x, min_y, max_x) (x, y) ->
            Float.min min_x x, Float.min min_y y, Float.max max_x x)
            (x, y, x) rest in
      let marker operation = List.find_opt
        (fun (node : Edit_graph.node_info) -> node.operation = operation)
        (Edit_graph.inspect spec.body.geometry)
        |> Option.map (fun node -> node.Edit_graph.id) in
      let inputs = Option.get (marker "flow_inputs")
      and outputs = Option.get (marker "flow_outputs") in
      let internal port =
        let id, path = port in
        inside id && match Flow_sop.Network.geometry_source network.graph
          {node = id; path} with
        | Some source -> inside source.node | None -> false in
      let ports = Canvas.Port_map.fold (fun port _ ports ->
        if internal port then Canvas.Port_set.add port ports else ports)
        original_layout.bends original_layout.wireless
        |> Canvas.Port_set.filter internal |> Canvas.Port_set.elements in
      let body_layout = Canvas.edit ~nodes:selected ~ports
        ~source:original_layout Canvas.empty in
      let body_layout = {body_layout with at = body_layout.at
        |> Layout.add inputs (Canvas.snap (min_x -. 240.), min_y)
        |> Layout.add outputs (Canvas.snap (max_x +. 256.), min_y)} in
      let parent_layout = Canvas.remove_nodes selected original_layout in
      let parent_layout = {parent_layout with at =
        Layout.add instance (min_x, min_y) parent_layout.at} in
      let displayed = if Option.fold ~none:false ~some:inside network.displayed
        then Some instance else network.displayed in
      let network = {network with graph = parent; layout = parent_layout;
        displayed} in
      let definition = {spec; layout = body_layout; displayed = Some outputs} in
      let next = with_network value level network in
      let next = {next with definitions = String_map.add name definition next.definitions} in
      Ok (next, instance)

(* The display node, kept on a node that exists: a deleted display node
   falls back to the previous one, else the last node in the network. *)
let displayed_of ?previous graph viewed =
  let graph = graph.Flow_sop.Network.geometry in
  let exists id = Edit_graph.find graph ~node_id:id <> None in
  if Option.fold ~none:false ~some:exists viewed then viewed
  else match previous with
    | Some id when exists id -> Some id
    | _ -> (match List.rev (Edit_graph.inspect graph) with
      | info :: _ -> Some info.Edit_graph.id | [] -> None)

let wire_exists graph (id, path) =
  let geometry_port = match Edit_graph.inputs graph.Flow_sop.Network.geometry ~node_id:id,
      Option.bind (Edit_graph.node_slot_names graph.geometry ~node_id:id)
        (List.find_index (String.equal path)) with
    | Some inputs, Some slot -> slot < Array.length inputs && inputs.(slot) <> None
    | _ -> false in
  geometry_port || match Flow_sop.Port.Map.find_opt {node = id; path} graph.drives with
    | Some (Flow_sop.Drive.Wire _) -> true | _ -> false

(* Resolve navigation after load, undo, or object removal. The scene is
   always a valid level, including an empty scene. The single-object 2D
   host requires a geometry object with an editable network. *)
let resolve_level ~scene_level value preferred =
  let inside id = Layout.mem id value.networks
    && Edit_graph.find value.scene.graph.geometry ~node_id:id <> None in
  match preferred with
  | Inside id when inside id -> Ok preferred
  | _ when scene_level -> Ok Scene
  | _ ->
      match List.find_opt (fun (info : Edit_graph.node_info) ->
        info.operation = "geometry" && inside info.id) (Edit_graph.inspect value.scene.graph.geometry) with
      | Some info -> Ok (Inside info.id)
      | None -> Error "Editor2 requires a geometry object with a SOP network"

(* The saved/loaded document boundary. Disconnected SOPs are editable and
   valid; compiling their display is a separate cook-time check. *)
let validate value =
  let ( let* ) = Result.bind in
  let compiled = Flow_sop.Instance_path.Map.bindings value.compiled_ids in
  let compiled_values = List.map snd compiled in
  let module Ids = Set.Make (Int) in
  let collect_ids network ids =
    let ids = List.fold_left (fun ids (node : Edit_graph.node_info) ->
      Ids.add node.id ids) ids (Edit_graph.inspect network.Flow_sop.Network.geometry) in
    List.fold_left (fun ids (node : Flow.Graph.node) -> Ids.add node.id ids)
      ids (Flow.Graph.inspect network.values) in
  let original_ids = collect_ids value.scene.graph Ids.empty
    |> fun ids -> Layout.fold (fun _ network ids -> collect_ids network.graph ids)
      value.networks ids
    |> fun ids -> String_map.fold (fun _ definition ids ->
      collect_ids definition.spec.body ids) value.definitions ids in
  let rec compiled_path instance = function
    | [] -> false
    | [inner] ->
        (match String_map.find_opt instance.Flow_sop.Network.definition value.definitions with
         | None -> false
         | Some definition ->
             Edit_graph.find definition.spec.body.geometry ~node_id:inner <> None
             || Flow.Graph.find definition.spec.body.values ~node_id:inner <> None)
    | nested :: rest ->
        (match String_map.find_opt instance.Flow_sop.Network.definition value.definitions with
         | None -> false
         | Some definition ->
             match Flow_sop.Network.Int_map.find_opt nested
               definition.spec.body.instances with
             | None -> false | Some child -> compiled_path child rest) in
  let compiled_path_exists = function
    | [] -> false
    | first :: rest ->
        Layout.exists (fun _ network ->
          match Flow_sop.Network.Int_map.find_opt first network.graph.instances with
          | None -> false | Some instance -> compiled_path instance rest)
          value.networks in
  let compiled_ok = List.for_all (fun (path, id) ->
    List.length path >= 2 && List.for_all (fun part -> part > 0) path
    && compiled_path_exists path && id > 0 && id < max_int
    && not (Ids.mem id original_ids))
    compiled
    && List.length compiled_values = List.length (List.sort_uniq Int.compare compiled_values) in
  let finite_fields fields = List.for_all (fun (field : Parameter.field_view) ->
    match field.current with Float_value x -> Float.is_finite x | _ -> true) fields in
  let geometry_names ports = List.filter_map
    (fun (port : Flow_sop.Network.interface_port) ->
      if port.ty = Flow.Port_type.Geometry then Some port.name else None) ports in
  let validate_network ?(interface_inputs = []) ?interface_outputs
      ?definition_name name network =
    let* () = Result.map_error Flow.Diagnostic.to_string (Flow_sop.Network.validate network.graph) in
    let nodes = Edit_graph.inspect network.graph.geometry in
    let nodes_named operation = List.filter (fun (node : Edit_graph.node_info) ->
      node.operation = operation) nodes in
    let valid_markers = match interface_outputs, definition_name with
      | None, None -> nodes_named "flow_inputs" = [] && nodes_named "flow_outputs" = []
      | Some outputs, Some definition_name ->
          (match nodes_named "flow_inputs", nodes_named "flow_outputs" with
           | [inputs], [outputs_node] ->
               Edit_graph.node_slot_names network.graph.geometry ~node_id:inputs.id = Some []
               && Edit_graph.node_factory_key network.graph.geometry
                    ~node_id:inputs.id = Some (Flow_sop.Compound_node.key
                      ~name:definition_name `Inputs)
               && Edit_graph.node_slot_names network.graph.geometry
                    ~node_id:outputs_node.id = Some (geometry_names outputs)
               && Edit_graph.node_factory_key network.graph.geometry
                    ~node_id:outputs_node.id = Some (Flow_sop.Compound_node.key
                      ~name:definition_name `Outputs)
           | _ -> false)
      | _ -> false in
    let valid_compounds = List.for_all (fun (node : Edit_graph.node_info) ->
      node.operation <> "flow_compound"
      || Flow_sop.Network.Int_map.mem node.id network.graph.instances) nodes in
    let geometry_exists id = Edit_graph.find network.graph.geometry ~node_id:id <> None in
    let exists id = geometry_exists id || Flow.Graph.find network.graph.values ~node_id:id <> None in
    let wire = wire_exists network.graph in
    let parameter id path = Flow_sop.Network.parameter network.graph {node = id; path} in
    let row id path = if network.context = Flow.Context.Sop then Result.is_ok (parameter id path)
      else Option.fold ~none:false ~some:(fun node ->
        List.exists (fun (f : Parameter.field_view) -> f.name = path)
          (Node.parameter_fields node)) (Edit_graph.find network.graph.geometry ~node_id:id) in
    let split id group = network.context = Flow.Context.Sop && match parameter id group with
      | Ok p when p.ty = Some Flow.Port_type.Vec3 ->
          not (Flow_sop.Port.Map.mem {node = id; path = group} network.graph.drives)
      | _ -> false in
    let valid_drives = Flow_sop.Port.Map.for_all (fun (port : Flow_sop.Port.t) _ ->
      match String.rindex_opt port.path '.' with
      | None -> true
      | Some i -> let group = String.sub port.path 0 i in
          Option.fold ~none:false ~some:(Canvas.String_set.mem group)
            (Layout.find_opt port.node network.layout.split)) network.graph.drives in
    let valid_geometry_outputs = Flow_sop.Port.Map.for_all (fun target output ->
      match Flow_sop.Network.geometry_source network.graph target with
      | None -> false
      | Some source ->
          let ports = match Flow_sop.Network.Int_map.find_opt source.node
              network.graph.instances with
            | Some instance -> Option.map (fun definition -> definition.spec.outputs)
                (String_map.find_opt instance.definition value.definitions)
            | None ->
                (match Edit_graph.find network.graph.geometry ~node_id:source.node with
                 | Some node when Node.operation node = "flow_inputs" -> Some interface_inputs
                 | _ -> None) in
          Option.fold ~none:false ~some:(List.exists
            (fun (port : Flow_sop.Network.interface_port) ->
              port.name = output && port.ty = Flow.Port_type.Geometry)) ports)
      network.graph.geometry_outputs in
    let valid_layout =
      Layout.for_all (fun id _ -> exists id) network.layout.level
      && Layout.for_all (fun id _ -> exists id) network.layout.pinned
      && Layout.for_all (fun id rows -> exists id && Canvas.String_map.for_all
        (fun path _ -> row id path) rows) network.layout.rows
      && Layout.for_all (fun id groups -> exists id && Canvas.String_set.for_all (split id) groups)
          network.layout.split
      && Canvas.Port_set.for_all wire network.layout.wireless
      && Canvas.Port_map.for_all (fun key points -> wire key
        && List.for_all (fun (x, y) -> Float.is_finite x && Float.is_finite y) points)
        network.layout.bends in
    if not (Flow.Context.supports_values network.context) &&
        (Flow.Graph.inspect network.graph.values <> [] || not (Flow_sop.Port.Map.is_empty network.graph.drives))
    then Error (name ^ " cannot contain value nodes or drives")
    else if (match network.displayed, nodes with
      | None, [] -> false | Some id, _ -> not (geometry_exists id) | None, _ -> true)
    then Error (name ^ " has an invalid display node")
    else if not (Layout.for_all (fun id (x, y) ->
      exists id && Float.is_finite x && Float.is_finite y) network.layout.at)
    then Error (name ^ " has an invalid tile position")
    else if not (valid_layout && valid_drives && valid_geometry_outputs
      && valid_markers && valid_compounds) then
      Error (name ^ " has invalid canvas or geometry output metadata")
    else if not (List.for_all (fun (info : Edit_graph.node_info) ->
      Array.for_all (Option.fold ~none:true ~some:geometry_exists) info.inputs
      && finite_fields (Node.parameter_fields info.node)) nodes)
    then Error (name ^ " has invalid inputs or nonfinite parameters")
    else Ok () in
  let literal_value = function
    | Parameter.Float_value number when Float.is_finite number ->
        Some (Flow.Port_type.Float_value number)
    | Int_value number -> Some (Flow.Port_type.Int_value number)
    | Bool_value value -> Some (Flow.Port_type.Bool_value value)
    | Float_value _ | Text_value _ | Choice_value _ -> None in
  let valid_literal ty literal = Option.fold ~none:false ~some:(fun source ->
    Flow.Port_type.can_connect ~source:(Flow.Port_type.value_type source) ~target:ty)
    (literal_value literal) in
  let validate_instances network =
    Flow_sop.Network.Int_map.fold (fun id (instance : Flow_sop.Network.instance) state ->
      let* () = state in
      match String_map.find_opt instance.definition value.definitions with
      | None -> Error (Printf.sprintf "instance #%d names missing definition %s"
          id instance.definition)
      | Some definition when definition.spec.context = Flow.Context.Sop
          && network.context <> Flow.Context.Sop ->
          Error (Printf.sprintf "instance #%d has incompatible context" id)
      | Some definition when definition.spec.context = Flow.Context.Value
          && not (Flow.Context.supports_values network.context) ->
          Error (Printf.sprintf "instance #%d has incompatible context" id)
      | Some definition ->
          let geometry_names = geometry_names definition.spec.inputs in
          let* () = match Edit_graph.find network.graph.geometry ~node_id:id with
            | Some node when Node.operation node = "flow_compound"
                && Edit_graph.node_slot_names network.graph.geometry ~node_id:id
                     = Some geometry_names
                && Edit_graph.node_factory_key network.graph.geometry ~node_id:id
                     = Some (Flow_sop.Compound_node.key
                       ~name:instance.definition `Instance) -> Ok ()
            | _ -> Error (Printf.sprintf
                "instance #%d is not a compound node with the definition's input slots" id) in
          Flow_sop.Network.String_map.fold (fun name literal state ->
            let* () = state in
            match List.find_opt (fun (port : Flow_sop.Network.interface_port) ->
              port.name = name) definition.spec.inputs with
            | None -> Error (Printf.sprintf "instance #%d has unknown input %s" id name)
            | Some port ->
                if not (valid_literal port.ty literal) then
                  Error (Printf.sprintf "instance #%d has invalid literal for %s" id name)
                else Ok ()) instance.literals (Ok ())) network.graph.instances (Ok ()) in
  let validate_ports name ports =
    let names = List.map (fun (port : Flow_sop.Network.interface_port) -> port.name) ports in
    if List.length names <> List.length (List.sort_uniq String.compare names) then
      Error (name ^ " has duplicate interface ports")
    else if not (List.for_all (fun (port : Flow_sop.Network.interface_port) ->
      Flow.Symbol.valid_name port.name && String.trim port.label <> ""
      && Option.fold ~none:true ~some:(fun (low, high) ->
        Float.is_finite low && Float.is_finite high && low < high) port.soft
      && Option.fold ~none:true ~some:(valid_literal port.ty) port.default) ports) then
      Error (name ^ " has invalid interface metadata")
    else
      let rec ordered seen_value = function
        | [] -> true
        | (port : Flow_sop.Network.interface_port) :: rest ->
            if port.ty = Flow.Port_type.Geometry then
              not seen_value && port.default = None && ordered seen_value rest
            else ordered true rest in
      if ordered false ports then Ok ()
      else Error (name ^ " places geometry after value ports") in
  let* () = if compiled_ok then Ok () else Error "invalid compiled instance ids" in
  let* () = if value.scene.context = Flow.Context.Scene then Ok () else Error "scene has the wrong context" in
  let* () = validate_network "scene" value.scene in
  let* () = validate_instances value.scene in
  let* () = List.fold_left (fun state (info : Edit_graph.node_info) ->
    let* () = state in
    match info.operation, Layout.mem info.id value.networks with
    | ("geometry" | "world"), true | ("camera" | "light"), false -> Ok ()
    | ("geometry" | "world"), false ->
        Error (Printf.sprintf "object %S (#%d) has no network" info.label info.id)
    | ("camera" | "light"), true ->
        Error (Printf.sprintf "object #%d cannot own a network" info.id)
    | _ -> Error (Printf.sprintf "invalid scene object %S" info.operation))
      (Ok ()) (Edit_graph.inspect value.scene.graph.geometry) in
  let* () = Layout.fold (fun id network state ->
    let* () = state in
    match Edit_graph.find value.scene.graph.geometry ~node_id:id with
    | None -> Error (Printf.sprintf "network has missing owner #%d" id)
    | Some node ->
        let context = if Node.operation node = "world" then Flow.Context.World else Flow.Context.Sop in
        if network.context <> context then Error (Printf.sprintf "network #%d has the wrong context" id)
        else let* () = validate_network (Printf.sprintf "network of object #%d" id) network in
          validate_instances network)
      value.networks (Ok ()) in
  let* () = String_map.fold (fun name definition state ->
    let* () = state in
    if not (Flow.Symbol.valid_name name) || name <> definition.spec.name
      || not (Flow.Context.supports_values definition.spec.context) then
      Error ("invalid compound definition name " ^ name)
    else
      let network = {context = definition.spec.context; graph = definition.spec.body;
        layout = definition.layout; displayed = definition.displayed} in
      let* () = validate_ports ("definition " ^ name ^ " inputs")
        definition.spec.inputs in
      let* () = validate_ports ("definition " ^ name ^ " outputs")
        definition.spec.outputs in
      let* () = validate_network ~interface_inputs:definition.spec.inputs
        ~interface_outputs:definition.spec.outputs
        ~definition_name:name
        ("definition " ^ name) network in
      validate_instances network) value.definitions (Ok ()) in
  let module Names = Set.Make (String) in
  let rec visit stack seen name =
    if Names.mem name stack then Error ("E_RECURSIVE: Compound " ^ name ^ " contains itself")
    else if Names.mem name seen then Ok seen else
    match String_map.find_opt name value.definitions with
    | None -> Error ("missing compound definition " ^ name)
    | Some definition ->
        let stack = Names.add name stack in
        let* seen = Flow_sop.Network.Int_map.fold (fun _
          (instance : Flow_sop.Network.instance) state ->
          let* seen = state in visit stack seen instance.definition)
          definition.spec.body.instances (Ok seen) in
        Ok (Names.add name seen) in
  let* _ = String_map.fold (fun name _ state ->
    let* seen = state in visit Names.empty seen name)
    value.definitions (Ok Names.empty) in
  if not (finite_fields (Settings.fields value.settings))
  then Error "settings contain nonfinite parameters"
  else match value.active_camera with
    | None -> Ok ()
    | Some id -> (match Edit_graph.find value.scene.graph.geometry ~node_id:id with
      | Some node when Node.operation node = "camera" -> Ok ()
      | _ -> Error (Printf.sprintf "active camera #%d is not a camera object" id))

(* Networks follow their objects: a deleted object's network goes, a pasted
   one copies its source's. *)
let prune value =
  let networks = Layout.filter (fun id _ ->
      Edit_graph.find value.scene.graph.geometry ~node_id:id <> None) value.networks in
  let active_camera = Option.bind value.active_camera (fun id ->
    if Edit_graph.find value.scene.graph.geometry ~node_id:id <> None then Some id else None) in
  if Layout.cardinal networks = Layout.cardinal value.networks
      && active_camera = value.active_camera then value
  else { value with networks; active_camera }

let copy_networks value mapping =
  { value with networks = List.fold_left (fun networks (source, copy) ->
      match Layout.find_opt source networks with
      | Some network -> Layout.add copy network networks
      | None -> networks) value.networks mapping }

(* Read-only views for tests and tools. *)
let scene_graph value = value.scene.graph.geometry
let object_network value id = Option.map (fun (network : network) ->
    network.graph, network.displayed) (Layout.find_opt id value.networks)
let positions value id = Option.map (fun (network : network) ->
    Layout.fold (fun node (x, y) list -> (node, x, y) :: list) network.layout.at [])
    (Layout.find_opt id value.networks)
