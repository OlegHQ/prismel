# Graph spatial-index candidate, 2026-08-30

This is an incremental M10 candidate, not M10 completion evidence.

`Pxui_graph` now builds a graph-space uniform-grid index when its document or
node positions change. Node-body, view-button, input-port, and output-port hit
tests query the indexed cell's packed candidate array instead of scanning every
node. Candidate arrays retain node-array order, preserving the prior hit and
z-order behavior. Pan and zoom reuse the graph-space index.

The existing graph statistics now report spatial cell count and maximum cell
candidate count. Focused graph and Sketch UI interaction tests pass, including
selection, dragging, connection gestures, pan/zoom, immutable editor requests,
and the `< 128` candidate invariant on the representative graph.

The remaining M10 work is explicit: marquee and visibility queries still scan
all nodes, wire hit testing still scans all edges, moving nodes still copies the
box array and rebuilds the index, and the required 10k-node/20k-edge benchmark
has not yet qualified. No scale or completion claim is made here.
