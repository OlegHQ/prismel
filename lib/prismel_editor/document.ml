(* Everything the user edits and saves, as one immutable value: the one
   thing [Editor_core.History] snapshots. Selection, hover, and the unlinked
   viewport camera are view state and stay outside. *)
module Layout = Map.Make (Int)

type t = {
  graph : Procedural.Edit_graph.t;
  layout : (float * float) Layout.t;  (* graph-space tile positions by id *)
  displayed : int;
  active_camera : int option;
  settings : Settings.t;
}

(* Whole snapshot: creation, preset load, and automatic layout only. *)
let of_view graph graph_view settings = {
  graph; settings;
  layout = Layout.of_list (List.map (fun (id, x, y) -> id, (x, y))
      (Pxui_graph.node_positions graph_view));
  displayed = Pxui_graph.viewed graph_view;
  active_camera = Pxui_graph.flagged graph_view }

(* An edit frame: re-read only the tiles this frame placed, moved, or
   deleted (a deleted id drops out), so the cost follows the change. *)
let edit value graph graph_view settings ids = {
  graph; settings;
  layout = List.fold_left (fun layout id ->
      match Pxui_graph.node_position graph_view id with
      | Some position -> Layout.add id position layout
      | None -> Layout.remove id layout) value.layout ids;
  displayed = Pxui_graph.viewed graph_view;
  active_camera = Pxui_graph.flagged graph_view }

let to_view value graph_view =
  Pxui_graph.with_document value.graph graph_view
  |> Pxui_graph.place_nodes (Layout.fold (fun id (x, y) placements ->
      (id, x, y) :: placements) value.layout [])
  |> Pxui_graph.view value.displayed
  |> Pxui_graph.with_flagged value.active_camera
