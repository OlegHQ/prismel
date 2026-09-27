(* The sole document/PXUI adapter. Document itself owns no presentation state. *)
open Editor_document
let of_view graph graph_view : Document.network = {
  graph;
  layout = Document.Layout.of_list (List.map (fun (id, x, y) -> id, (x, y))
    (Pxui_graph.node_positions graph_view));
  displayed = Document.displayed_of graph (Some (Pxui_graph.viewed graph_view)) }

(* Read only tiles placed, moved, or deleted by this frame's intents. *)
let edit (network : Document.network) graph graph_view ids : Document.network = {
  graph;
  layout = List.fold_left (fun layout id ->
    match Pxui_graph.node_position graph_view id with
    | Some position -> Document.Layout.add id position layout
    | None -> Document.Layout.remove id layout) network.layout ids;
  displayed = Document.displayed_of ?previous:network.displayed graph
    (Some (Pxui_graph.viewed graph_view)) }

let to_view (network : Document.network) graph_view =
  Pxui_graph.with_document network.graph graph_view
  |> Pxui_graph.place_nodes (Document.Layout.fold (fun id (x, y) placements ->
    (id, x, y) :: placements) network.layout [])
  |> Option.fold ~none:Fun.id ~some:Pxui_graph.view network.displayed
