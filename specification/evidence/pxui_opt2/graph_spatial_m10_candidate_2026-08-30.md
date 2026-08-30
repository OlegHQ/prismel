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

The graph benchmark now includes ten single-node pointer moves and constructs
the resulting Scene on every move. Before retaining the active drag transform,
the 10k lane rebuilt the complete box store and edge BVH on every event: median
move time was 129.036 milliseconds and ten moves allocated 1,326,080,016 bytes.
The active-drag candidate retains one graph-space offset plus the selected node
and incident-edge slot vectors. On the same lane, move-and-paint median is
108.004 microseconds and ten moves allocate 2,309,784 bytes. State-only pointer
moves allocate 8,096 bytes total for ten events and are below the timer's
microsecond resolution. A split-frame regression verifies press, intermediate
paint/position, release retention, and immutable SOP connectivity.

Release no longer materializes the full box array or rebuilds the base grid and
edge BVH. Immutable position overrides are keyed by node ID, while moved-node
and affected-edge slot sets suppress stale base-index entries and feed exact
delta visibility/hit lanes. On the 10k lane, release plus Scene construction is
189.066 microseconds and 244,768 allocated bytes; the allocation is identical
at 1k and 10k, rather than scaling with the loaded graph. Regressions query the
released node and its moved wire at their retained positions. Explicit layout
optimization and document replacement intentionally materialize/rebase once
and clear the delta sets.

Accumulated moved nodes now have a persistent delta grid. Each release removes
the selected slots from their prior delta cells and inserts them at their new
graph-space bounds. Node/body/port hit tests, marquee, and viewport visibility
query those cells alongside the unchanged base grid while suppressing stale
base entries; they no longer scan every node edited since the last document
replacement. The 10k single-node release-and-paint lane remains 215.054
microseconds with 246,472 allocated bytes, versus 112.057 microseconds and the
same allocation at 1k.

Affected wires now use a deterministic persistent interval treap over the same
eight conservative curve regions as the packed base BVH. Releasing a move
removes prior regions for each affected edge, inserts its new graph-space
regions, and retains an exact entry count; base leaves for changed edges remain
suppressed. Hit testing and viewport visibility query the delta hierarchy and
deduplicate edge IDs with the existing generation plane instead of scanning all
edges edited since document publication. A 100-node move/release/paint lane at
10k nodes takes 1.288 milliseconds and allocates 2,593,800 bytes, compared with
1.215 milliseconds and 3,066,376 bytes at 1k, demonstrating dependence on the
changed/affected set rather than loaded graph cardinality. The single-node 10k
release remains 199.080 microseconds with 259,288 allocated bytes.

The former 10,000-way fan remains useful as an adversarial stress topology: its
long diagonal envelopes overlap heavily and are not used as a proxy for the
controlled 2x-edge qualification lane.

The remaining M10 work is explicit: large menu match sets still need an
index-backed partial ranking lane, and graph paint is not yet split into
retained layers. No completion claim is made here.
