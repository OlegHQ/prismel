(* Everything the user edits and saves, as one immutable value: the one
   thing [Editor_core.History] snapshots. Selection, hover, and the unlinked
   viewport camera are view state and stay outside. *)
type t = {
  graph : Procedural.Edit_graph.t;
  layout : (int * float * float) list;  (* graph-space tile positions *)
  displayed : int;
  active_camera : int option;
  settings : Settings.t;
}

let of_view graph graph_view settings = {
  graph; layout = Pxui_graph.node_positions graph_view;
  displayed = Pxui_graph.viewed graph_view;
  active_camera = Pxui_graph.flagged graph_view; settings }

let to_view value graph_view =
  List.fold_left (fun view (node_id, x, y) -> Pxui_graph.place_node ~node_id ~x ~y view)
    (Pxui_graph.with_document value.graph graph_view) value.layout
  |> Pxui_graph.view value.displayed
  |> Pxui_graph.with_flagged value.active_camera
