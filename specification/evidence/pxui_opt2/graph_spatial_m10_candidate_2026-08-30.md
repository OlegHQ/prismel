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

The follow-up candidate adds reusable generation marks and geometrically grown
visible node/edge buffers. Viewport node enumeration now visits spatial cells
and preserves painter order with an in-place prefix sort. Wire hit testing and
visibility use a packed structure-of-arrays BVH over eight conservative curve
regions per edge. Each region covers the same 16 line segments used by exact
hit testing across the complete supported zoom range. There is no global
long-wire overflow scan.

The synthetic benchmark command is:

```sh
DUNE_CONFIG__BACKGROUND_ACTIONS=disabled \
  dune exec tools/bench_pxui_graph.exe
```

The benchmark now uses a controlled layered local DAG instead of making its
only qualification case a single 10,000-way fan. On the 10,001-node / 19,950-
edge lane it reported 1.192 microseconds node-query p99, 3.099 microseconds
edge-hit p99, six node candidates, three edge candidates, and 30 visible nodes.
The packed edge BVH contained 319,199 nodes. The same run reported identical
41,241,192-byte query-loop allocation at 100, 1k, and 10k graph sizes, showing
that query allocation did not scale with the loaded document size. Focused
`test_pxui_graph` and `test_sketch_ui` executables passed on the same source.

Node IDs now map directly to stable array slots for selected-node gesture
preparation and clipboard position lookup. Marquee selection enumerates the
covered graph-space grid cells with reusable generation marks, then applies the
exact screen-space rectangle test only to unique candidates. Neither path scans
the complete node table for a local selection gesture.

Catalog ingestion now retains lowercase key, label, and breadcrumb text once.
Menu search reuses those normalized values and retains exactly one row result
keyed by the complete menu state, so update and paint consumers do not repeat
filtering, lowercase conversion, and ranking for an unchanged menu. The
existing nested-category and generated-catalog interaction tests pass.

The former 10,000-way fan remains useful as an adversarial stress topology: its
long diagonal envelopes overlap heavily and are not used as a proxy for the
controlled 2x-edge qualification lane.

The remaining M10 work is explicit: moving nodes still copies the box array and
rebuilds the indexes, node/position stores are not yet packed mutable runtime
planes, large match sets still need an index-backed partial ranking lane, and
graph paint is not yet split into retained layers. No completion claim is made
here.
