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
and preserves painter order with an in-place prefix sort. Short wire bounds are
indexed too; long wire bounds enter an explicit overflow lane capped at 256
cells per wire, preventing pathological grid memory growth.

The synthetic benchmark command is:

```sh
DUNE_CONFIG__BACKGROUND_ACTIONS=disabled \
  dune exec tools/bench_pxui_graph.exe
```

On the 10,002-node / 20,000-edge fan fixture it reported 1.192 microseconds
p99 for 10,000 node queries, three node candidates, eight visible nodes, and
about 62 MB maximum process RSS under `/usr/bin/time -l`. The fan deliberately
forces all 20,000 long wires through the bounded overflow lane; this fails the
wire candidate target and prevents an M10 completion claim.

The remaining M10 work is explicit: marquee still scans all nodes, long-wire
queries need a hierarchical segment index, moving nodes still copies the box
array and rebuilds the index, and graph paint is not yet split into retained
layers. No completion claim is made here.
