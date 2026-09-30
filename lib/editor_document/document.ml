(* Everything the user edits and saves, as one immutable value: the one
   thing [Editor_core.History] snapshots.  Selection, hover, and the open
   level are view state and stay outside.  The document is a workspace (its
   text is the authored truth); the scene, the networks and the shell are what
   lowering derives from it. *)
open Procedural
module Int_map = Map.Make (Int)

(* One node network with its display node. *)
type network = {
  context : Flow.Context.t;
  graph : Flow_sop.Network.t;
  displayed : int option;  (* None when no node has a geometry output *)
}

let of_geometry ~context graph displayed =
  { context; graph = Flow_sop.Network.of_geometry graph; displayed }

(* Where a panel of the shell tree came from in the editor graph. *)
type origin = Bound of string | Loop of string  (* its binding; the binding holding the loop *)

(* The lowered editor graph (plan W10): the shell tree, the origin of each named or
   looped panel (any other panel is inline), the graph a [(ui/graph "name")] shows
   and, for each viewport over a scene other than the default one, the scene objects
   of that instance (they live in [scene], and no other viewport draws them). *)
type shell = {
  tree : Editor_core.Panels.t;
  origins : (Editor_core.Panels.path * origin) list;
  named : string option;
  views : (string * int list) list;
}

type t = {
  scene : network;  (* objects: input 0 is the parent *)
  networks : network Int_map.t;  (* by object id: SOP networks, the World's layers *)
  active_camera : int option;  (* a camera object *)
  settings : Settings.t;
  shell : shell option;  (* the [editor] graph of the workspace, if it has one *)
  workspace : Workspace_doc.t * Flow_sop.Lower.t;
  (* the authored document and its lowering: [scene] and [networks] are that lowering, one
     geometry object per [sop] graph; the lowering (compiled ids, volatile set) is history
     state so undo restores both *)
}

(* The network shown in the graph pane. *)
type level = Scene | Inside of int

let network value = function
  | Scene -> Some value.scene
  | Inside id -> Int_map.find_opt id value.networks

let with_network value level network = match level with
  | Scene -> { value with scene = network }
  | Inside id -> { value with networks = Int_map.add id network value.networks }

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

(* Resolve navigation after load, undo, or object removal. The scene is
   always a valid level, including an empty scene. The single-object 2D
   host requires a geometry object with an editable network. *)
let resolve_level ~scene_level value preferred =
  let inside id = Int_map.mem id value.networks
    && Edit_graph.find value.scene.graph.geometry ~node_id:id <> None in
  match preferred with
  | Inside id when inside id -> Ok (Inside id)
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
    let exists id = Edit_graph.find network.graph.geometry ~node_id:id <> None in
    if (match network.displayed with Some id -> not (exists id) | None -> false)
    then Error (name ^ " has an invalid display node")
    else if not (List.for_all (fun (info : Edit_graph.node_info) ->
      Array.for_all (Option.fold ~none:true ~some:exists) info.inputs
      && finite_fields (Node.parameter_fields info.node)) nodes)
    then Error (name ^ " has invalid inputs or nonfinite parameters")
    else Ok () in
  let* () = if value.scene.context = Flow.Context.Scene then Ok () else Error "scene has the wrong context" in
  let* () = validate_network "scene" value.scene in
  let* () = List.fold_left (fun state (info : Edit_graph.node_info) ->
    let* () = state in
    match info.operation, Int_map.mem info.id value.networks with
    | ("geometry" | "world"), true | ("camera" | "light"), false -> Ok ()
    | ("geometry" | "world"), false ->
        Error (Printf.sprintf "object %S (#%d) has no network" info.label info.id)
    | ("camera" | "light"), true ->
        Error (Printf.sprintf "object #%d cannot own a network" info.id)
    | _ -> Error (Printf.sprintf "invalid scene object %S" info.operation))
      (Ok ()) (Edit_graph.inspect value.scene.graph.geometry) in
  let* () = Int_map.fold (fun id network state ->
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

(* Networks follow their objects: a deleted object's network goes. *)
let prune value =
  let networks = Int_map.filter (fun id _ ->
      Edit_graph.find value.scene.graph.geometry ~node_id:id <> None) value.networks in
  let active_camera = Option.bind value.active_camera (fun id ->
    if Edit_graph.find value.scene.graph.geometry ~node_id:id <> None then Some id else None) in
  if Int_map.cardinal networks = Int_map.cardinal value.networks
      && active_camera = value.active_camera then value
  else { value with networks; active_camera }

(* Read-only views for tests and tools. *)
let scene_graph value = value.scene.graph.geometry
let object_network value id = Option.map (fun (network : network) ->
    network.graph, network.displayed) (Int_map.find_opt id value.networks)

(* A deterministic text of everything the editor keeps in a document, for
   crash reports and for tests that compare two documents.  Not loadable:
   the workspace text is the saved form ([Preset]). *)
let dump value =
  let b = Buffer.create 4096 in
  let line fmt = Printf.ksprintf (fun s -> Buffer.add_string b s; Buffer.add_char b '\n') fmt in
  let pv : Editor_core.Param.value -> string = function
    | Bool_value x -> string_of_bool x | Int_value x -> string_of_int x
    | Float_value x -> Printf.sprintf "%h" x
    | Text_value x | Choice_value x -> Printf.sprintf "%S" x in
  let fields fs = String.concat " " (List.map (fun (f : Editor_core.Param.field_view) ->
    f.name ^ "=" ^ pv f.current) fs) in
  let graph (n : Flow_sop.Network.t) =
    List.iter (fun (info : Edit_graph.node_info) ->
      line "  node %d %s %S %s slots=%s inputs=%s%s %s" info.id
        (Option.value ~default:info.operation (Edit_graph.node_factory_key n.geometry ~node_id:info.id))
        info.label (if info.bypass then "bypass" else "-")
        (String.concat "," (Option.value ~default:[] (Edit_graph.node_slot_names n.geometry ~node_id:info.id)))
        (String.concat "," (Array.to_list (Array.map (function Some i -> string_of_int i | None -> "_") info.inputs)))
        (match Edit_graph.root n.geometry with Some r when r = info.id -> " root" | _ -> "")
        (fields (Node.parameter_fields info.node))) (Edit_graph.inspect n.geometry);
    Flow_sop.Port.Map.iter (fun (p : Flow_sop.Port.t) _ -> line "  drive %d.%s live" p.node p.path)
      n.drives in
  let net name (n : network) =
    line "%s %s display=%s" name (Flow.Context.name n.context)
      (match n.displayed with Some d -> string_of_int d | None -> "-");
    graph n.graph in
  net "scene" value.scene;
  Int_map.iter (fun id n -> net (Printf.sprintf "object %d" id) n) value.networks;
  line "camera %s" (match value.active_camera with Some c -> string_of_int c | None -> "-");
  line "settings %s" (fields (Settings.fields value.settings));
  Buffer.contents b
