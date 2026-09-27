(* The sole document/PXUI adapter. Document itself owns no presentation state. *)
open Editor_document
let of_view graph graph_view : Document.network = {
  graph;
  layout = Pxui_graph.layout graph_view;
  displayed = Document.displayed_of graph (Some (Pxui_graph.viewed graph_view)) }

(* Read only tiles placed, moved, or deleted by this frame's intents. *)
let edit (network : Document.network) graph graph_view ids ports : Document.network = {
  graph;
  layout = Pxui_graph.edit_layout ~nodes:ids ~ports graph_view network.layout;
  displayed = Document.displayed_of ?previous:network.displayed graph
    (Some (Pxui_graph.viewed graph_view)) }

let to_view (network : Document.network) graph_view =
  Pxui_graph.with_document network.graph graph_view
  |> Pxui_graph.with_layout network.layout
  |> Option.fold ~none:Fun.id ~some:Pxui_graph.view network.displayed
