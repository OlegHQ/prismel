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
  displayed : int option;  (* None when no node has a geometry output *)
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
type level = Scene | Inside of int | Compound of { owner : int; path : int list }

let rec compound_definition value graph = function
  | [] -> None
  | id :: rest ->
      Option.bind (Flow_sop.Network.Int_map.find_opt id graph.Flow_sop.Network.instances)
        (fun instance -> Option.bind
          (String_map.find_opt instance.definition value.definitions)
          (fun definition -> if rest = [] then Some (instance.definition, definition)
            else compound_definition value definition.spec.body rest))

let compound_names value = function
  | Compound {owner; path} ->
      (match Layout.find_opt owner value.networks with
       | None -> []
       | Some network ->
           let rec names graph = function
             | [] -> []
             | id :: rest ->
                 (match compound_definition value graph [id] with
                  | None -> []
                  | Some (name, definition) -> name :: names definition.spec.body rest) in
           names network.graph path)
  | Scene | Inside _ -> []

let network value = function
  | Scene -> Some value.scene
  | Inside id -> Layout.find_opt id value.networks
  | Compound {owner; path} ->
      Option.bind (Layout.find_opt owner value.networks) (fun root ->
        Option.map (fun (_, definition) -> {
          context = definition.spec.context; graph = definition.spec.body;
          layout = definition.layout; displayed = definition.displayed})
          (compound_definition value root.graph path))

let with_network value level network = match level with
  | Scene -> { value with scene = network }
  | Inside id -> { value with networks = Layout.add id network value.networks }
  | Compound {owner; path} ->
      (match Layout.find_opt owner value.networks with
       | None -> value
       | Some root -> match compound_definition value root.graph path with
           | None -> value
           | Some (name, definition) ->
               let spec = {definition.spec with body = network.graph} in
               {value with definitions = String_map.add name
                 {spec; layout = network.layout; displayed = network.displayed}
                 value.definitions})

let enter_compound value level id =
  Option.bind (network value level) (fun current ->
    Option.bind (Flow_sop.Network.Int_map.find_opt id current.graph.instances)
      (fun instance -> if not (String_map.mem instance.definition value.definitions)
        then None else match level with
        | Inside owner -> Some (Compound {owner; path = [id]})
        | Compound {owner; path} -> Some (Compound {owner; path = path @ [id]})
        | Scene -> None))

let parent_level = function
  | Compound {owner; path} ->
      (match List.rev path with
       | [] -> None
       | instance :: parents ->
           Some ((if parents = [] then Inside owner
             else Compound {owner; path = List.rev parents}), instance))
  | Scene | Inside _ -> None

let compiled_path_exists value =
  let rec through instance = function
    | [] -> false
    | [inner] ->
        (match String_map.find_opt instance.Flow_sop.Network.definition
          value.definitions with
         | None -> false
         | Some definition ->
             Edit_graph.find definition.spec.body.geometry ~node_id:inner <> None
             || Flow.Graph.find definition.spec.body.values ~node_id:inner <> None)
    | nested :: rest ->
        (match String_map.find_opt instance.Flow_sop.Network.definition
          value.definitions with
         | None -> false
         | Some definition ->
             match Flow_sop.Network.Int_map.find_opt nested
               definition.spec.body.instances with
             | None -> false | Some child -> through child rest) in
  function
  | [] -> false
  | first :: rest ->
      Layout.exists (fun _ network ->
        match Flow_sop.Network.Int_map.find_opt first network.graph.instances with
        | None -> false | Some instance -> through instance rest)
        value.networks

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

let ungroup value level ~instance_id =
  let ( let* ) = Result.bind in
  match network value level with
  | None -> Error (Flow.Diagnostic.error ~code:"E_UNGROUP" "No network to ungroup")
  | Some current ->
      let* definition = match Flow_sop.Network.Int_map.find_opt instance_id
          current.graph.instances with
        | None -> Error (Flow.Diagnostic.error ~code:"E_UNGROUP"
            "Select one compound instance to ungroup")
        | Some instance ->
            (match String_map.find_opt instance.definition value.definitions with
             | Some definition -> Ok definition
             | None -> Error (Flow.Diagnostic.error ~code:"E_UNBOUND"
                 ("Missing compound " ^ instance.definition))) in
      let* graph, mapping, displayed = Flow_sop.Group.ungroup ~instance_id
        ~displayed:current.displayed ~definition:definition.spec current.graph in
      let displayed = match displayed with
        | Some _ -> displayed
        | None -> List.find_map (fun (node : Edit_graph.node_info) ->
            let has_geometry = match Flow_sop.Network.Int_map.find_opt
                node.id graph.instances with
              | None -> true
              | Some instance ->
                  (match String_map.find_opt instance.definition
                      value.definitions with
                   | None -> false
                   | Some definition -> List.exists
                       (fun (port : Flow_sop.Network.interface_port) ->
                         port.ty = Flow.Port_type.Geometry)
                       definition.spec.outputs) in
            if has_geometry then Some node.id else None)
            (List.rev (Edit_graph.inspect graph.geometry)) in
      let layout = Canvas.remove_nodes [instance_id] current.layout in
      let instance_x, instance_y = Option.value ~default:(0., 0.)
        (Layout.find_opt instance_id current.layout.at) in
      let origin_x, origin_y = List.fold_left (fun (x, y) (old_id, _) ->
        match Layout.find_opt old_id definition.layout.at with
        | None -> x, y
        | Some (px, py) -> Float.min x px, Float.min y py)
        (Float.infinity, Float.infinity) mapping in
      let origin_x, origin_y = if Float.is_finite origin_x then
        origin_x, origin_y else 0., 0. in
      let dx, dy = instance_x -. origin_x, instance_y -. origin_y in
      let copy source target = List.fold_left (fun target (old_id, new_id) ->
        match Layout.find_opt old_id source with
        | None -> target | Some value -> Layout.add new_id value target)
        target mapping in
      let at = List.fold_left (fun at (old_id, new_id) ->
        let x, y = Option.value ~default:(origin_x, origin_y)
          (Layout.find_opt old_id definition.layout.at) in
        Layout.add new_id (Canvas.snap (x +. dx), Canvas.snap (y +. dy)) at)
        layout.at mapping in
      let remap = Flow_sop.Network.Int_map.of_list mapping in
      let bends = Canvas.Port_map.fold (fun (old_id, path) points bends ->
        match Flow_sop.Network.Int_map.find_opt old_id remap with
        | None -> bends
        | Some new_id -> Canvas.Port_map.add (new_id, path)
            (List.map (fun (x, y) -> Canvas.snap (x +. dx),
              Canvas.snap (y +. dy)) points) bends)
        definition.layout.bends layout.bends in
      let wireless = Canvas.Port_set.fold (fun (old_id, path) wireless ->
        match Flow_sop.Network.Int_map.find_opt old_id remap with
        | None -> wireless
        | Some new_id -> Canvas.Port_set.add (new_id, path) wireless)
        definition.layout.wireless layout.wireless in
      let layout : Canvas.t = {at;
        level = copy definition.layout.level layout.level;
        pinned = copy definition.layout.pinned layout.pinned;
        rows = copy definition.layout.rows layout.rows;
        split = copy definition.layout.split layout.split;
        bends; wireless} in
      let next = with_network value level {current with graph; layout; displayed} in
      let compiled_ids = Flow_sop.Instance_path.Map.filter (fun path _ ->
        compiled_path_exists next path) next.compiled_ids in
      Ok ({next with compiled_ids}, mapping)

let make_unique value level ~instance_id =
  let ( let* ) = Result.bind in
  let error message = Error (Flow.Diagnostic.error ~code:"E_COMPOUND" message) in
  match network value level with
  | None -> error "No network at this level"
  | Some current ->
      let* instance = match Flow_sop.Network.Int_map.find_opt instance_id
          current.graph.instances with
        | Some instance -> Ok instance
        | None -> error "Select one compound instance" in
      let* original = match String_map.find_opt instance.definition
          value.definitions with
        | Some definition -> Ok definition
        | None -> error ("Missing compound " ^ instance.definition) in
      let rec free index =
        let name = instance.definition ^ "_" ^ string_of_int index in
        if String_map.mem name value.definitions then free (index + 1)
        else name in
      let name = free 2 in
      let body = original.spec.body in
      let ids = List.map (fun (node : Edit_graph.node_info) -> node.id)
          (Edit_graph.inspect body.geometry)
        @ List.map (fun (node : Flow.Graph.node) -> node.id)
          (Flow.Graph.inspect body.values) in
      let* fragment = Flow_sop.Network.copy_nodes ids body in
      let* copied, mapping = Flow_sop.Network.paste fragment
        (Flow_sop.Network.of_geometry Edit_graph.empty) in
      let remap = Flow_sop.Network.Int_map.of_list mapping in
      let mapped id = Flow_sop.Network.Int_map.find id remap in
      let factories = Flow_sop.Compound_node.factories ~name
        ~inputs:original.spec.inputs ~outputs:original.spec.outputs in
      let* geometry = List.fold_left (fun state (operation, factory) ->
        let* geometry = state in
        match List.find_opt (fun (node : Edit_graph.node_info) ->
            node.operation = operation) (Edit_graph.inspect body.geometry) with
        | None -> error ("Missing compound " ^ operation ^ " marker")
        | Some marker ->
            Result.map_error (Flow.Diagnostic.error ~code:"E_COMPOUND")
              (Edit_graph.rebind_factory ~node_id:(mapped marker.id)
                factory geometry))
        (Ok copied.geometry)
        (List.combine ["flow_inputs"; "flow_outputs"]
          (List.take 2 factories)) in
      let* copied = Flow_sop.Network.with_geometry geometry copied in
      let spec = {original.spec with name; body = copied} in
      let copy source = Layout.fold (fun old_id value result ->
        match Flow_sop.Network.Int_map.find_opt old_id remap with
        | Some new_id -> Layout.add new_id value result
        | None -> result) source Layout.empty in
      let copy_ports source = Canvas.Port_map.fold (fun (old_id, path) points result ->
        match Flow_sop.Network.Int_map.find_opt old_id remap with
        | Some new_id -> Canvas.Port_map.add (new_id, path) points result
        | None -> result) source Canvas.Port_map.empty in
      let layout : Canvas.t = {
        at = copy original.layout.at;
        level = copy original.layout.level;
        pinned = copy original.layout.pinned;
        rows = copy original.layout.rows;
        split = copy original.layout.split;
        bends = copy_ports original.layout.bends;
        wireless = Canvas.Port_set.fold (fun (old_id, path) result ->
          match Flow_sop.Network.Int_map.find_opt old_id remap with
          | Some new_id -> Canvas.Port_set.add (new_id, path) result
          | None -> result) original.layout.wireless Canvas.Port_set.empty} in
      let definition = {spec; layout;
        displayed = Option.map mapped original.displayed} in
      let instance_factory = List.nth factories 2 in
      let* geometry = Result.map_error
          (Flow.Diagnostic.error ~code:"E_COMPOUND")
          (Edit_graph.rebind_factory ~node_id:instance_id instance_factory
            current.graph.geometry) in
      let instances = Flow_sop.Network.Int_map.add instance_id
        {instance with definition = name} current.graph.instances in
      let* graph = Flow_sop.Network.of_parts ~geometry
        ~values:current.graph.values ~drives:current.graph.drives
        ~geometry_outputs:current.graph.geometry_outputs ~instances in
      let next = with_network value level {current with graph} in
      let next = {next with definitions = String_map.add name definition
        next.definitions} in
      let compiled_ids = Flow_sop.Instance_path.Map.filter (fun path _ ->
        compiled_path_exists next path) next.compiled_ids in
      Ok ({next with compiled_ids}, name)

type interface_side = Input | Output

let map_networks value update_network =
  let ( let* ) = Result.bind in
  let* scene = update_network value.scene in
  let* networks = Layout.fold (fun id network result ->
    let* networks = result in
    let* network = update_network network in
    Ok (Layout.add id network networks)) value.networks (Ok Layout.empty) in
  let* definitions = String_map.fold (fun name definition result ->
    let* definitions = result in
    let* network = update_network {context = definition.spec.context;
      graph = definition.spec.body; layout = definition.layout;
      displayed = definition.displayed} in
    Ok (String_map.add name {definition with
      spec = {definition.spec with body = network.graph};
      layout = network.layout} definitions))
      value.definitions (Ok String_map.empty) in
  Ok {value with scene; networks; definitions}

let export_parameter value level ~(target : Flow_sop.Port.t) =
  let ( let* ) = Result.bind in
  let error message = Error (Flow.Diagnostic.error ~code:"E_INTERFACE" message) in
  let* definition_name = match List.rev (compound_names value level) with
    | name :: _ -> Ok name
    | [] -> error "Enter a compound before exporting a row" in
  let definition = String_map.find definition_name value.definitions in
  let body = definition.spec.body in
  let* () = match Edit_graph.find body.geometry ~node_id:target.node with
    | Some node when List.mem (Node.operation node)
        ["flow_inputs"; "flow_outputs"] ->
        error "Select an ordinary row inside the compound"
    | _ -> Ok () in
  let* parameter = Flow_sop.Network.parameter body target in
  let* field, ty = match parameter.fields, parameter.ty with
    | [field], Some (Flow.Port_type.Float | Int | Bool as ty) -> Ok (field, ty)
    | field :: _ :: _, Some Flow.Port_type.Vec3 ->
        Ok (field, Flow.Port_type.Vec3)
    | _ -> error "Export a Float, Int, Bool or Vec3 row" in
  let driven = Flow_sop.Port.Map.mem target body.drives
    || List.exists (fun (part : Flow_sop.Port.parameter) ->
      Flow_sop.Port.Map.mem {target with path = part.path} body.drives)
      (Flow_sop.Port.components parameter)
    || match String.rindex_opt target.path '.' with
       | None -> false
       | Some index -> Flow_sop.Port.Map.mem
           {target with path = String.sub target.path 0 index} body.drives in
  if driven then error "Clear the row's drive before exporting it"
  else if ty = Flow.Port_type.Vec3 && Option.fold ~none:false
      ~some:(Canvas.String_set.mem target.path)
      (Layout.find_opt target.node definition.layout.split) then
    error "Join the vector before exporting it"
  else
  let base = String.lowercase_ascii target.path |> String.map (function
    | 'a' .. 'z' | '0' .. '9' | '_' as character -> character
    | _ -> '_') in
  let base = if Flow.Symbol.valid_name base then base else "input_" ^ base in
  let used = List.map (fun (port : Flow_sop.Network.interface_port) ->
    port.name) definition.spec.inputs in
  let rec fresh index =
    let name = if index = 1 then base else base ^ "_" ^ string_of_int index in
    if List.mem name used then fresh (index + 1) else name in
  let name = fresh 1 in
  let soft = match field.Param.kind with
    | Floating_view range -> Some (range.soft_min, range.soft_max)
    | Integer_view range -> Some (float_of_int range.soft_min,
        float_of_int range.soft_max)
    | Toggle_view -> None
    | _ -> None in
  let port : Flow_sop.Network.interface_port = {
    name; ty; default = Some (Flow_sop.Port.literal parameter);
    label = (if ty = Flow.Port_type.Vec3 then
      String.capitalize_ascii target.path else field.label); soft} in
  let spec = {definition.spec with inputs = definition.spec.inputs @ [port]} in
  let factories = Flow_sop.Compound_node.factories ~name:definition_name
    ~inputs:spec.inputs ~outputs:spec.outputs in
  let marker = Edit_graph.inspect body.geometry
    |> List.find_opt (fun (node : Edit_graph.node_info) ->
      node.operation = "flow_inputs") in
  let* marker = match marker with Some node -> Ok node.id
    | None -> error "Compound Inputs marker is missing" in
  let* geometry = Result.map_error
    (Flow.Diagnostic.error ~code:"E_INTERFACE")
    (Edit_graph.rebind_factory ~node_id:marker (List.hd factories)
      body.geometry) in
  let* body = Flow_sop.Network.with_geometry geometry body in
  let* body = Flow_sop.Network.connect_value
    ~source:Flow_sop.Port.{node = marker; path = name} ~target body in
  let definition = {definition with spec = {spec with body}} in
  let value = {value with definitions = String_map.add definition_name
    definition value.definitions} in
  let* value = map_networks value (fun (current : network) ->
    let matching = Flow_sop.Network.Int_map.bindings current.graph.instances
      |> List.filter_map (fun (id, instance) ->
        if instance.Flow_sop.Network.definition = definition_name
        then Some id else None) in
    if matching = [] then Ok current else
    let* geometry = List.fold_left (fun state id ->
      let* geometry = state in
      Result.map_error (Flow.Diagnostic.error ~code:"E_INTERFACE")
        (Edit_graph.rebind_factory ~node_id:id (List.nth factories 2)
          geometry)) (Ok current.graph.geometry) matching in
    let* graph = Flow_sop.Network.with_geometry geometry current.graph in
    Ok {current with graph}) in
  Ok (value, name)

let unexport_port value ~definition_name ~side ~name =
  let ( let* ) = Result.bind in
  let error message = Error (Flow.Diagnostic.error ~code:"E_INTERFACE" message) in
  let* definition = match String_map.find_opt definition_name value.definitions with
    | Some definition -> Ok definition
    | None -> error ("Missing compound " ^ definition_name) in
  let ports = match side with Input -> definition.spec.inputs
    | Output -> definition.spec.outputs in
  let* port = match List.find_opt (fun
      (port : Flow_sop.Network.interface_port) -> port.name = name) ports with
    | Some port -> Ok port
    | None -> error ("No interface port " ^ name) in
  if port.ty = Flow.Port_type.Geometry then
    let body = definition.spec.body in
    let marker = Edit_graph.inspect body.geometry
      |> List.find_opt (fun (node : Edit_graph.node_info) ->
        node.operation = (if side = Input then "flow_inputs"
          else "flow_outputs")) in
    let* marker = match marker with Some marker -> Ok marker.id
      | None -> error "Compound interface marker is missing" in
    let used_as_source graph ~node =
      List.exists (fun (info : Edit_graph.node_info) ->
        let slots = Option.value ~default:[]
          (Edit_graph.node_slot_names graph.Flow_sop.Network.geometry
            ~node_id:info.id) in
        List.exists (fun path ->
          Flow_sop.Network.geometry_source graph
            Flow_sop.Port.{node = info.id; path}
          = Some Flow_sop.Port.{node; path = name}) slots)
        (Edit_graph.inspect graph.geometry) in
    let body_used = if side = Input then used_as_source body ~node:marker
      else Flow_sop.Network.geometry_source body
        Flow_sop.Port.{node = marker; path = name} <> None in
    if body_used then error "Disconnect the geometry port inside the compound"
    else
    let inputs = if side = Input then List.filter (fun
      (candidate : Flow_sop.Network.interface_port) -> candidate.name <> name)
      definition.spec.inputs else definition.spec.inputs in
    let outputs = if side = Output then List.filter (fun
      (candidate : Flow_sop.Network.interface_port) -> candidate.name <> name)
      definition.spec.outputs else definition.spec.outputs in
    let factories = Flow_sop.Compound_node.factories ~name:definition_name
      ~inputs ~outputs in
    let* geometry = Result.map_error
      (Flow.Diagnostic.error ~code:"E_INTERFACE")
      (Edit_graph.rebind_factory ~preserve_wires_by_name:true
        ~node_id:marker (List.nth factories (if side = Input then 0 else 1))
        body.geometry) in
    let* body = Flow_sop.Network.with_geometry geometry body in
    let definition = {definition with spec = {definition.spec with
      inputs; outputs; body}} in
    let value = {value with definitions = String_map.add definition_name
      definition value.definitions} in
    let first_geometry_output = List.find_opt (fun
      (candidate : Flow_sop.Network.interface_port) ->
        candidate.ty = Flow.Port_type.Geometry) ports in
    map_networks value (fun (current : network) ->
      let matching = Flow_sop.Network.Int_map.bindings current.graph.instances
        |> List.filter_map (fun (id, instance) ->
          if instance.Flow_sop.Network.definition = definition_name
          then Some id else None) in
      if matching = [] then Ok current else
      let in_use = List.exists (fun id -> if side = Input then
        Flow_sop.Network.geometry_source current.graph
          Flow_sop.Port.{node = id; path = name} <> None
        else used_as_source current.graph ~node:id
          || current.displayed = Some id
             && Option.fold ~none:false ~some:(fun
               (candidate : Flow_sop.Network.interface_port) ->
                 candidate.name = name) first_geometry_output) matching in
      if in_use then error "Disconnect every instance geometry wire before unexporting"
      else
      let* geometry = List.fold_left (fun state id ->
        let* geometry = state in
        Result.map_error (Flow.Diagnostic.error ~code:"E_INTERFACE")
          (Edit_graph.rebind_factory ~preserve_wires_by_name:true
            ~node_id:id (List.nth factories 2) geometry))
          (Ok current.graph.geometry) matching in
      let* graph = Flow_sop.Network.with_geometry geometry current.graph in
      Ok {current with graph})
  else
  let matches path = path = name
    || port.ty = Flow.Port_type.Vec3
       && String.starts_with ~prefix:(name ^ ".") path in
  let body = definition.spec.body in
  let marker = Edit_graph.inspect body.geometry
    |> List.find_opt (fun (node : Edit_graph.node_info) ->
      node.operation = (if side = Input then "flow_inputs" else "flow_outputs")) in
  let* marker = match marker with Some marker -> Ok marker.id
    | None -> error "Compound interface marker is missing" in
  let inputs = if side = Input then List.filter (fun
    (candidate : Flow_sop.Network.interface_port) -> candidate.name <> name)
    definition.spec.inputs else definition.spec.inputs in
  let outputs = if side = Output then List.filter (fun
    (candidate : Flow_sop.Network.interface_port) -> candidate.name <> name)
    definition.spec.outputs else definition.spec.outputs in
  let factories = Flow_sop.Compound_node.factories ~name:definition_name
    ~inputs ~outputs in
  let* geometry = Result.map_error (Flow.Diagnostic.error ~code:"E_INTERFACE")
    (Edit_graph.rebind_factory ~node_id:marker
      (List.nth factories (if side = Input then 0 else 1)) body.geometry) in
  let remove_drive target drive =
    if side = Output then target.Flow_sop.Port.node = marker
      && matches target.path
    else match drive with
      | Flow_sop.Drive.Wire source ->
          source.node = marker && matches source.output
      | Flow_sop.Drive.Expr _ -> false in
  let removed_targets = Flow_sop.Port.Map.fold (fun target drive targets ->
    if remove_drive target drive then (target.node, target.path) :: targets
    else targets) body.drives [] in
  let drives = Flow_sop.Port.Map.filter (fun target drive ->
    not (remove_drive target drive)) body.drives in
  let* body = Flow_sop.Network.of_parts ~geometry ~values:body.values
    ~drives ~geometry_outputs:body.geometry_outputs ~instances:body.instances in
  let layout = {definition.layout with
    rows = Canvas.Int_map.mapi (fun id rows -> if side <> Output || id <> marker
      then rows else Canvas.String_map.filter (fun path _ -> not (matches path))
        rows) definition.layout.rows;
    split = Canvas.Int_map.mapi (fun id groups -> if side <> Output || id <> marker
      then groups else Canvas.String_set.filter (fun path -> not (matches path))
        groups) definition.layout.split;
    bends = Canvas.Port_map.filter (fun target _ ->
      not (List.mem target removed_targets)) definition.layout.bends;
    wireless = Canvas.Port_set.filter (fun target ->
      not (List.mem target removed_targets)) definition.layout.wireless} in
  let definition = {definition with spec = {definition.spec with
    inputs; outputs; body}; layout} in
  let value = {value with definitions = String_map.add definition_name
    definition value.definitions} in
  map_networks value (fun (current : network) ->
    let graph = current.graph in
    let matching = Flow_sop.Network.Int_map.bindings graph.instances
      |> List.filter_map (fun (id, instance) ->
        if instance.Flow_sop.Network.definition = definition_name
        then Some id else None) in
    if matching = [] then Ok current else
    let uses_port = Flow_sop.Port.Map.exists (fun target drive ->
      if side = Input then List.mem target.node matching && matches target.path
      else match drive with
        | Flow_sop.Drive.Wire source ->
            List.mem source.node matching && matches source.output
        | Flow_sop.Drive.Expr _ -> false) graph.drives in
    if uses_port then error "Disconnect instance value wires before unexporting"
    else
    let overridden = List.exists (fun id ->
      let instance = Flow_sop.Network.Int_map.find id graph.instances in
      let fields = Edit_graph.node_factory_fields graph.geometry ~node_id:id in
      Flow_sop.Network.String_map.exists (fun key value ->
        let belongs = key = name || port.ty = Flow.Port_type.Vec3
          && List.exists (fun axis -> key = name ^ "_" ^ axis)
            ["x"; "y"; "z"] in
        belongs && match List.find_opt (fun (field : Parameter.field_view) ->
          field.name = key) fields with
          | Some field -> value <> field.default
          | None -> true) instance.literals) matching in
    if overridden then error "Reset instance literals before unexporting"
    else
    let* geometry = List.fold_left (fun state id ->
      let* geometry = state in
      Result.map_error (Flow.Diagnostic.error ~code:"E_INTERFACE")
        (Edit_graph.rebind_factory ~node_id:id (List.nth factories 2)
          geometry)) (Ok graph.geometry) matching in
    let instances = Flow_sop.Network.Int_map.mapi (fun id
        (instance : Flow_sop.Network.instance) ->
      if not (List.mem id matching) || side = Output then instance else
        {instance with literals = Flow_sop.Network.String_map.filter
          (fun key _ -> not (key = name || port.ty = Flow.Port_type.Vec3
            && List.exists (fun axis -> key = name ^ "_" ^ axis)
              ["x"; "y"; "z"])) instance.literals}) graph.instances in
    let* graph = Flow_sop.Network.of_parts ~geometry ~values:graph.values
      ~drives:graph.drives ~geometry_outputs:graph.geometry_outputs
      ~instances in
    let layout = if side = Output then current.layout else
      {current.layout with
        rows = Canvas.Int_map.mapi (fun id rows ->
          if not (List.mem id matching) then rows else
          Canvas.String_map.filter (fun path _ -> not (matches path)) rows)
          current.layout.rows;
        split = Canvas.Int_map.mapi (fun id groups ->
          if not (List.mem id matching) then groups else
          Canvas.String_set.filter (fun path -> not (matches path)) groups)
          current.layout.split} in
    Ok {current with graph; layout})

let rename_interface_port value ~definition_name ~side ~from ~into =
  let ( let* ) = Result.bind in
  let error message = Error (Flow.Diagnostic.error ~code:"E_INTERFACE" message) in
  let* definition = match String_map.find_opt definition_name value.definitions with
    | Some definition -> Ok definition
    | None -> error ("Missing compound " ^ definition_name) in
  let ports = match side with Input -> definition.spec.inputs
    | Output -> definition.spec.outputs in
  let* port = match List.find_opt (fun (port : Flow_sop.Network.interface_port) ->
      port.name = from) ports with
    | Some port -> Ok port
    | None -> error ("No interface port " ^ from) in
  if not (Flow.Symbol.valid_name into) then error "Invalid interface port name"
  else if from = into then Ok value
  else if List.exists (fun (port : Flow_sop.Network.interface_port) ->
      port.name = into) ports then error ("Interface port " ^ into ^ " already exists")
  else
  let ports = List.map (fun (candidate : Flow_sop.Network.interface_port) ->
    if candidate.name = from then {port with name = into;
      label = (if port.label = String.capitalize_ascii from
        then String.capitalize_ascii into else port.label)}
    else candidate) ports in
  let spec = match side with Input -> {definition.spec with inputs = ports}
    | Output -> {definition.spec with outputs = ports} in
  let body = spec.body in
  let marker operation = Edit_graph.inspect body.geometry
    |> List.find_opt (fun (node : Edit_graph.node_info) ->
      node.operation = operation) in
  let* marker = match marker (match side with Input -> "flow_inputs"
      | Output -> "flow_outputs") with
    | Some node -> Ok node.id | None -> error "Compound interface marker is missing" in
  let factories = Flow_sop.Compound_node.factories ~name:definition_name
    ~inputs:spec.inputs ~outputs:spec.outputs in
  let* geometry = Result.map_error (Flow.Diagnostic.error ~code:"E_INTERFACE")
    (Edit_graph.rebind_factory ~node_id:marker
      (List.nth factories (if side = Input then 0 else 1)) body.geometry) in
  let rename_path path = if path = from then into
    else if String.starts_with ~prefix:(from ^ ".") path then
      into ^ String.sub path (String.length from) (String.length path - String.length from)
    else path in
  let rename_key (id, path) = if id = marker then id, rename_path path
    else id, path in
  let drives = Flow_sop.Port.Map.fold (fun target drive result ->
    let target = if side = Output && target.node = marker then
      {target with path = rename_path target.path} else target in
    let drive = match drive with
      | Flow_sop.Drive.Wire source when side = Input
          && source.node = marker ->
          Flow_sop.Drive.Wire {source with output = rename_path source.output}
      | _ -> drive in
    Flow_sop.Port.Map.add target drive result)
    body.drives Flow_sop.Port.Map.empty in
  let geometry_outputs = Flow_sop.Port.Map.fold (fun target output result ->
    let source = Flow_sop.Network.geometry_source body target in
    let target = if side = Output then
      let id, path = rename_key (target.node, target.path) in
      Flow_sop.Port.{node = id; path} else target in
    let output = if side = Input && output = from
        && Option.fold ~none:false ~some:(fun (source : Flow_sop.Port.t) ->
          source.node = marker)
          source then into else output in
    Flow_sop.Port.Map.add target output result)
    body.geometry_outputs Flow_sop.Port.Map.empty in
  let* body = Flow_sop.Network.of_parts ~geometry ~values:body.values
    ~drives ~geometry_outputs ~instances:body.instances in
  let rename_layout rename (layout : Canvas.t) = {layout with
    rows = Canvas.Int_map.mapi (fun id rows ->
      Canvas.String_map.fold (fun path visible result ->
        let _, path = rename (id, path) in
        Canvas.String_map.add path visible result)
        rows Canvas.String_map.empty) layout.rows;
    split = Canvas.Int_map.mapi (fun id groups ->
      Canvas.String_set.fold (fun path result ->
        let _, path = rename (id, path) in
        Canvas.String_set.add path result)
        groups Canvas.String_set.empty) layout.split;
    bends = Canvas.Port_map.fold (fun key points result ->
      Canvas.Port_map.add (rename key) points result)
      layout.bends Canvas.Port_map.empty;
    wireless = Canvas.Port_set.fold (fun key result ->
      Canvas.Port_set.add (rename key) result)
      layout.wireless Canvas.Port_set.empty} in
  let layout = if side = Output then rename_layout rename_key definition.layout
    else definition.layout in
  let definition = {definition with spec = {spec with body}; layout} in
  let value = {value with definitions = String_map.add definition_name
    definition value.definitions} in
  let update_network (current : network) =
    let graph = current.graph in
    let changed id = match Flow_sop.Network.Int_map.find_opt id graph.instances with
      | Some instance -> instance.definition = definition_name
      | None -> false in
    if not (Flow_sop.Network.Int_map.exists (fun _ instance ->
        instance.Flow_sop.Network.definition = definition_name)
        graph.instances) then Ok current else
    let* geometry = Flow_sop.Network.Int_map.fold (fun id
        (instance : Flow_sop.Network.instance) result ->
      let* geometry = result in
      if instance.definition <> definition_name then Ok geometry else
      Result.map_error (Flow.Diagnostic.error ~code:"E_INTERFACE")
        (Edit_graph.rebind_factory ~node_id:id (List.nth factories 2) geometry))
      graph.instances (Ok graph.geometry) in
    let drives = Flow_sop.Port.Map.fold (fun target drive result ->
      let target = if side = Input && changed target.node then
        {target with path = rename_path target.path} else target in
      let drive = match drive with
        | Flow_sop.Drive.Wire source when side = Output
            && changed source.node ->
            Flow_sop.Drive.Wire {source with output = rename_path source.output}
        | _ -> drive in
      Flow_sop.Port.Map.add target drive result)
      graph.drives Flow_sop.Port.Map.empty in
    let instances = if side = Output then graph.instances else
      Flow_sop.Network.Int_map.mapi (fun id
          (instance : Flow_sop.Network.instance) ->
        if not (changed id) then instance else
        let literals = Flow_sop.Network.String_map.fold
          (fun name value result ->
            let name = if name = from then into else
              if port.ty = Flow.Port_type.Vec3
                && List.exists (fun axis -> name = from ^ "_" ^ axis)
                  ["x"; "y"; "z"] then
                into ^ String.sub name (String.length from)
                  (String.length name - String.length from)
              else name in
            Flow_sop.Network.String_map.add name value result)
          instance.literals Flow_sop.Network.String_map.empty in
        {instance with literals}) graph.instances in
    let geometry_outputs = Flow_sop.Port.Map.fold (fun target output result ->
      let source = Flow_sop.Network.geometry_source graph target in
      let target = if side = Input && changed target.node
          && target.path = from then {target with path = into} else target in
      let output = if side = Output && output = from
          && Option.fold ~none:false ~some:(fun (source : Flow_sop.Port.t) ->
            changed source.node)
            source then into else output in
      Flow_sop.Port.Map.add target output result)
      graph.geometry_outputs Flow_sop.Port.Map.empty in
    let* graph = Flow_sop.Network.of_parts ~geometry ~values:graph.values
      ~drives ~geometry_outputs ~instances in
    let layout = if side = Input then rename_layout (fun (id, path) ->
      if changed id then id, rename_path path else id, path)
        current.layout else current.layout in
    Ok {current with graph; layout} in
  map_networks value update_network

let reorder_interface value ~definition_name ~side ~name ~delta =
  let ( let* ) = Result.bind in
  let error message = Error (Flow.Diagnostic.error ~code:"E_INTERFACE" message) in
  if delta <> -1 && delta <> 1 then error "Move an interface port one row"
  else
  let* definition = match String_map.find_opt definition_name value.definitions with
    | Some definition -> Ok definition
    | None -> error ("Missing compound " ^ definition_name) in
  let ports = match side with Input -> definition.spec.inputs
    | Output -> definition.spec.outputs in
  match List.find_index (fun (port : Flow_sop.Network.interface_port) ->
      port.name = name) ports with
  | None -> error ("No interface port " ^ name)
  | Some index ->
      let next = index + delta in
      if next < 0 || next >= List.length ports then Ok value
      else if ((List.nth ports index).ty = Flow.Port_type.Geometry)
          <> ((List.nth ports next).ty = Flow.Port_type.Geometry) then
        error "Move geometry ports before value ports"
      else
        let swapped = Array.of_list ports in
        let held = swapped.(index) in
        swapped.(index) <- swapped.(next);
        swapped.(next) <- held;
        let ports = Array.to_list swapped in
        let spec = match side with
          | Input -> {definition.spec with inputs = ports}
          | Output -> {definition.spec with outputs = ports} in
        let factories = Flow_sop.Compound_node.factories
          ~name:definition_name ~inputs:spec.inputs ~outputs:spec.outputs in
        let* body =
          let marker = Edit_graph.inspect spec.body.geometry
            |> List.find_opt (fun (node : Edit_graph.node_info) ->
              node.operation = (if side = Input then "flow_inputs"
                else "flow_outputs")) in
          match marker with
          | None -> error "Compound interface marker is missing"
          | Some marker ->
              let* geometry = Result.map_error
                  (Flow.Diagnostic.error ~code:"E_INTERFACE")
                  (Edit_graph.rebind_factory ~preserve_wires_by_name:true
                    ~node_id:marker.id
                    (List.nth factories (if side = Input then 0 else 1))
                    spec.body.geometry) in
              Flow_sop.Network.with_geometry geometry spec.body in
        let definition = {definition with spec = {spec with body}} in
        let value = {value with definitions = String_map.add definition_name
          definition value.definitions} in
        map_networks value (fun (current : network) ->
          let matching = Flow_sop.Network.Int_map.bindings current.graph.instances
            |> List.filter_map (fun (id, instance) ->
              if instance.Flow_sop.Network.definition = definition_name
              then Some id else None) in
          if matching = [] then Ok current else
          let* geometry = List.fold_left (fun result id ->
            let* geometry = result in
            Result.map_error (Flow.Diagnostic.error ~code:"E_INTERFACE")
              (Edit_graph.rebind_factory ~preserve_wires_by_name:true
                ~node_id:id (List.nth factories 2) geometry))
              (Ok current.graph.geometry) matching in
          let* graph = Flow_sop.Network.with_geometry geometry current.graph in
          Ok {current with graph})

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
  let rec valid = function
    | Compound {owner; _} as level when inside owner ->
        (match network value level with
         | Some _ -> Ok level
         | None -> (match parent_level level with
             | Some (parent, _) -> valid parent
             | None -> Ok (Inside owner)))
    | Inside id when inside id -> Ok (Inside id)
    | _ when scene_level -> Ok Scene
    | _ ->
        match List.find_opt (fun (info : Edit_graph.node_info) ->
          info.operation = "geometry" && inside info.id) (Edit_graph.inspect value.scene.graph.geometry) with
        | Some info -> Ok (Inside info.id)
        | None -> Error "Editor2 requires a geometry object with a SOP network" in
  valid preferred

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
  let compiled_ok = List.for_all (fun (path, id) ->
    List.length path >= 2 && List.for_all (fun part -> part > 0) path
    && compiled_path_exists value path && id > 0 && id < max_int
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
    let displayable id = geometry_exists id &&
      match Flow_sop.Network.Int_map.find_opt id network.graph.instances with
      | None -> true
      | Some instance ->
          (match String_map.find_opt instance.definition value.definitions with
           | None -> false
           | Some definition -> List.exists
               (fun (port : Flow_sop.Network.interface_port) ->
                 port.ty = Flow.Port_type.Geometry) definition.spec.outputs) in
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
    else if (match network.displayed with
      | Some id -> not (displayable id)
      | None -> List.exists (fun (node : Edit_graph.node_info) ->
          displayable node.id) nodes)
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
  let valid_interface_literal ty = function
    | Flow_sop.Port.Scalar value -> valid_literal ty value
    | Flow_sop.Port.Vector (x,y,z) ->
        ty = Flow.Port_type.Vec3
        && Float.is_finite x && Float.is_finite y && Float.is_finite z in
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
            | None ->
                let component = List.exists (fun (port : Flow_sop.Network.interface_port) ->
                  port.ty = Flow.Port_type.Vec3
                  && List.exists (fun axis -> name = port.name ^ "_" ^ axis)
                    ["x"; "y"; "z"]) definition.spec.inputs in
                (match component, literal with
                 | true, Parameter.Float_value number when Float.is_finite number -> Ok ()
                 | true, _ -> Error (Printf.sprintf
                     "instance #%d has invalid Vec3 component %s" id name)
                 | false, _ -> Error (Printf.sprintf
                     "instance #%d has unknown input %s" id name))
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
      && Option.fold ~none:true ~some:(valid_interface_literal port.ty)
        port.default) ports) then
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
