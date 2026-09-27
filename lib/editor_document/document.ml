(* Everything the user edits and saves, as one immutable value: the one
   thing [Editor_core.History] snapshots. Selection, hover, the open level,
   and the unlinked viewport camera are view state and stay outside. *)
open Procedural
module Canvas = Editor_core.Network_layout
module Layout = Canvas.Int_map

(* One node network with its graph-space tile positions and display node. *)
type network = {
  context : Flow.Context.t;
  graph : Flow_sop.Network.t;
  layout : Canvas.t;
  displayed : int option;  (* None exactly when geometry is empty *)
}

let of_geometry ~context graph displayed =
  { context; graph = Flow_sop.Network.of_geometry graph; layout = Canvas.empty; displayed }

type t = {
  scene : network;  (* objects: input 0 is the parent *)
  networks : network Layout.t;  (* by object id: SOP networks, the World's layers *)
  active_camera : int option;  (* a camera object *)
  settings : Settings.t;
}

(* The network shown in the graph pane. *)
type level = Scene | Inside of int

let network value = function
  | Scene -> Some value.scene
  | Inside id -> Layout.find_opt id value.networks

let with_network value level network = match level with
  | Scene -> { value with scene = network }
  | Inside id -> { value with networks = Layout.add id network value.networks }

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
  let finite_fields fields = List.for_all (fun (field : Parameter.field_view) ->
    match field.current with Float_value x -> Float.is_finite x | _ -> true) fields in
  let validate_network name network =
    let* () = Result.map_error Flow.Diagnostic.to_string (Flow_sop.Network.validate network.graph) in
    let nodes = Edit_graph.inspect network.graph.geometry in
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
    if network.context <> Flow.Context.Sop &&
        (Flow.Graph.inspect network.graph.values <> [] || not (Flow_sop.Port.Map.is_empty network.graph.drives))
    then Error (name ^ " cannot contain value nodes or drives")
    else if (match network.displayed, nodes with
      | None, [] -> false | Some id, _ -> not (geometry_exists id) | None, _ -> true)
    then Error (name ^ " has an invalid display node")
    else if not (Layout.for_all (fun id (x, y) ->
      exists id && Float.is_finite x && Float.is_finite y) network.layout.at)
    then Error (name ^ " has an invalid tile position")
    else if not (valid_layout && valid_drives) then Error (name ^ " has invalid canvas metadata")
    else if not (List.for_all (fun (info : Edit_graph.node_info) ->
      Array.for_all (Option.fold ~none:true ~some:geometry_exists) info.inputs
      && finite_fields (Node.parameter_fields info.node)) nodes)
    then Error (name ^ " has invalid inputs or nonfinite parameters")
    else Ok () in
  let* () = if value.scene.context = Flow.Context.Scene then Ok () else Error "scene has the wrong context" in
  let* () = validate_network "scene" value.scene in
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
        else validate_network (Printf.sprintf "network of object #%d" id) network)
      value.networks (Ok ()) in
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
let object_network value id = Option.map (fun network ->
    network.graph, network.displayed) (Layout.find_opt id value.networks)
let positions value id = Option.map (fun network ->
    Layout.fold (fun node (x, y) list -> (node, x, y) :: list) network.layout.at [])
    (Layout.find_opt id value.networks)
