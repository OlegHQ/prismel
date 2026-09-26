(* Everything the user edits and saves, as one immutable value: the one
   thing [Editor_core.History] snapshots. Selection, hover, the open level,
   and the unlinked viewport camera are view state and stay outside. *)
open Procedural
module Layout = Map.Make (Int)

(* One node network with its graph-space tile positions and display node. *)
type network = {
  graph : Edit_graph.t;
  layout : (float * float) Layout.t;
  displayed : int;
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
let displayed_of ?previous graph graph_view =
  let exists id = Edit_graph.find graph ~node_id:id <> None in
  let viewed = Pxui_graph.viewed graph_view in
  if exists viewed then viewed
  else match previous with
    | Some id when exists id -> id
    | _ -> (match List.rev (Edit_graph.inspect graph) with
      | info :: _ -> info.Edit_graph.id | [] -> viewed)

(* Whole snapshot: creation, preset load, level entry, and automatic layout. *)
let of_view graph graph_view = {
  graph;
  layout = Layout.of_list (List.map (fun (id, x, y) -> id, (x, y))
      (Pxui_graph.node_positions graph_view));
  displayed = displayed_of graph graph_view }

(* An edit frame: re-read only the tiles this frame placed, moved, or
   deleted (a deleted id drops out), so the cost follows the change. *)
let edit network graph graph_view ids = {
  graph;
  layout = List.fold_left (fun layout id ->
      match Pxui_graph.node_position graph_view id with
      | Some position -> Layout.add id position layout
      | None -> Layout.remove id layout) network.layout ids;
  displayed = displayed_of ~previous:network.displayed graph graph_view }

let to_view network graph_view =
  Pxui_graph.with_document network.graph graph_view
  |> Pxui_graph.place_nodes (Layout.fold (fun id (x, y) placements ->
      (id, x, y) :: placements) network.layout [])
  |> (if Edit_graph.find network.graph ~node_id:network.displayed = None then Fun.id
      else Pxui_graph.view network.displayed)

(* Networks follow their objects: a deleted object's network goes, a pasted
   one copies its source's. *)
let prune value =
  let networks = Layout.filter (fun id _ ->
      Edit_graph.find value.scene.graph ~node_id:id <> None) value.networks in
  if Layout.cardinal networks = Layout.cardinal value.networks then value
  else { value with networks }

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
