(* Everything the user edits and saves, as one immutable value: the one
   thing [Editor_core.History] snapshots. Selection, hover, the open level,
   and the unlinked viewport camera are view state and stay outside. *)
open Procedural
module Layout = Map.Make (Int)

(* One node network with its graph-space tile positions and display node. *)
type network = {
  graph : Edit_graph.t;
  layout : (float * float) Layout.t;
  displayed : int option;  (* None exactly when the network is empty *)
}

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
  let exists id = Edit_graph.find graph ~node_id:id <> None in
  if Option.fold ~none:false ~some:exists viewed then viewed
  else match previous with
    | Some id when exists id -> Some id
    | _ -> (match List.rev (Edit_graph.inspect graph) with
      | info :: _ -> Some info.Edit_graph.id | [] -> None)

(* Resolve navigation after load, undo, or object removal. The scene is
   always a valid level, including an empty scene. The single-object 2D
   host requires a geometry object with an editable network. *)
let resolve_level ~scene_level value preferred =
  let inside id = Layout.mem id value.networks
    && Edit_graph.find value.scene.graph ~node_id:id <> None in
  match preferred with
  | Inside id when inside id -> Ok preferred
  | _ when scene_level -> Ok Scene
  | _ ->
      match List.find_opt (fun (info : Edit_graph.node_info) ->
        info.operation = "geometry" && inside info.id) (Edit_graph.inspect value.scene.graph) with
      | Some info -> Ok (Inside info.id)
      | None -> Error "Editor2 requires a geometry object with a SOP network"

(* The saved/loaded document boundary. Disconnected SOPs are editable and
   valid; compiling their display is a separate cook-time check. *)
let validate value =
  let ( let* ) = Result.bind in
  let finite_fields fields = List.for_all (fun (field : Parameter.field_view) ->
    match field.current with Float_value x -> Float.is_finite x | _ -> true) fields in
  let validate_network name network =
    let nodes = Edit_graph.inspect network.graph in
    let exists id = Edit_graph.find network.graph ~node_id:id <> None in
    if (match network.displayed, nodes with
      | None, [] -> false | Some id, _ -> not (exists id) | None, _ -> true)
    then Error (name ^ " has an invalid display node")
    else if not (Layout.for_all (fun id (x, y) ->
      exists id && Float.is_finite x && Float.is_finite y) network.layout)
    then Error (name ^ " has an invalid tile position")
    else if not (List.for_all (fun (info : Edit_graph.node_info) ->
      Array.for_all (Option.fold ~none:true ~some:exists) info.inputs
      && finite_fields (Node.parameter_fields info.node)) nodes)
    then Error (name ^ " has invalid inputs or nonfinite parameters")
    else Ok () in
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
      (Ok ()) (Edit_graph.inspect value.scene.graph) in
  let* () = Layout.fold (fun id network state ->
    let* () = state in
    if Edit_graph.find value.scene.graph ~node_id:id = None
    then Error (Printf.sprintf "network has missing owner #%d" id)
    else validate_network (Printf.sprintf "network of object #%d" id) network)
      value.networks (Ok ()) in
  if not (finite_fields (Settings.fields value.settings))
  then Error "settings contain nonfinite parameters"
  else match value.active_camera with
    | None -> Ok ()
    | Some id -> (match Edit_graph.find value.scene.graph ~node_id:id with
      | Some node when Node.operation node = "camera" -> Ok ()
      | _ -> Error (Printf.sprintf "active camera #%d is not a camera object" id))

(* Networks follow their objects: a deleted object's network goes, a pasted
   one copies its source's. *)
let prune value =
  let networks = Layout.filter (fun id _ ->
      Edit_graph.find value.scene.graph ~node_id:id <> None) value.networks in
  let active_camera = Option.bind value.active_camera (fun id ->
    if Edit_graph.find value.scene.graph ~node_id:id <> None then Some id else None) in
  if Layout.cardinal networks = Layout.cardinal value.networks
      && active_camera = value.active_camera then value
  else { value with networks; active_camera }

let copy_networks value mapping =
  { value with networks = List.fold_left (fun networks (source, copy) ->
      match Layout.find_opt source networks with
      | Some network -> Layout.add copy network networks
      | None -> networks) value.networks mapping }

(* Read-only views for tests and tools. *)
let scene_graph value = value.scene.graph
let object_network value id = Option.map (fun network ->
    network.graph, network.displayed) (Layout.find_opt id value.networks)
let positions value id = Option.map (fun network ->
    Layout.fold (fun node (x, y) list -> (node, x, y) :: list) network.layout [])
    (Layout.find_opt id value.networks)
