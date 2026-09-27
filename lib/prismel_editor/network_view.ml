(* The sole document/PXUI adapter. Document itself owns no presentation state. *)
open Editor_document
let of_view (network : Document.network) graph_view : Document.network = { network with
  layout = Pxui_graph.layout graph_view;
  displayed = Document.displayed_of network.graph (Some (Pxui_graph.viewed graph_view)) }

(* Read only tiles placed, moved, or deleted by this frame's intents. *)
let edit (network : Document.network) graph graph_view ids ports : Document.network = {
  context = network.context; graph;
  layout = (let layout = Pxui_graph.edit_layout ~nodes:ids ~ports graph_view network.layout in
    let removed = List.filter (fun id ->
      Procedural.Edit_graph.find graph.geometry ~node_id:id = None
      && Flow.Graph.find graph.values ~node_id:id = None) ids in
    if removed = [] then layout else
      let layout = Editor_core.Network_layout.remove_nodes removed layout in
      { layout with bends = Editor_core.Network_layout.Port_map.filter
          (fun port _ -> Document.wire_exists graph port) layout.bends;
        wireless = Editor_core.Network_layout.Port_set.filter
          (Document.wire_exists graph) layout.wireless });
  displayed = Document.displayed_of ?previous:network.displayed graph
    (Some (Pxui_graph.viewed graph_view)) }

let to_view (network : Document.network) graph_view =
  Pxui_graph.with_document network.graph graph_view
  |> Pxui_graph.with_layout network.layout
  |> Option.fold ~none:Fun.id ~some:Pxui_graph.view network.displayed
