# OPT2 M2 stable-store candidate evidence

Source state: candidate worktree following `a416568a`.

Frozen `OPT2.md` SHA-256:
`2c59594e53eb236cd108867f653d61deb30ded2b987ffc9fffee55062fcb383b`.

## Implemented slice

- generation-checked 64-bit widget IDs;
- geometrically growing packed generation, occupancy, free-list, and payload
  planes;
- O(1) checked lookup, replacement, deletion, and free-slot reuse;
- payload clearing before a slot enters the free list;
- cold string-name reconciliation into stable IDs behind the source-compatible
  PXUI facade;
- cache invalidation on every widget-structure/value replacement path;
- hidden camera controls retain the identical PXUI presentation value until
  their panel becomes visible again.

## Deterministic storage gate

`dune exec lib/pxui/test_pxui_layout_snapshot.exe`

- 100,000 create/delete/reuse cycles remain at exactly 8 slots;
- every ID from the previous generation rejects get, set, and delete;
- 100,000 simultaneous live values grow to exactly 131,072 slots;
- all 100,000 values round-trip exactly;
- bulk deletion returns live count to zero without capacity growth;
- deleted payload references are absent immediately.

The same run retained the M1 drag allocation gate:
`drag100=82,104 B`, `drag1000=773,304 B`.

## Native hidden diagnostic

Command:

```sh
PRISMEL_RENDERER_BENCH_WARMUP=2 PRISMEL_RENDERER_BENCH_SECONDS=5 \
  dune exec tools/bench_shattered_renderer.exe -- hidden
```

Exact geometry remained 18,278 pieces, 278,368 triangles, and 835,104 render
vertices. The run produced 590 frames in 5.004138 seconds at 117.90 FPS,
8.254 ms median, 10.292 ms p95, and 12.641 ms p99. It allocated 27,468,544
bytes, or 46,557 bytes/frame, at 14.91% process CPU.

This remains above M12's 16 KiB interim hidden gate. Memprof attributes the
remaining work primarily to Scene/renderer byte assembly, array/list
conversion, matrix construction, workspace geometry, and Scene3 flattening;
those are retained-display-list and submission-array work in later milestones,
not evidence that M2 is complete.

## Verification

```sh
dune runtest lib/pxui lib/sop_ui lib/pxui_graph lib/sketch_ui
dune exec test/test_prismel.exe
dune exec test/test_easy_camera2.exe
dune build @all
git diff --check
```

All commands passed. This evidence promotes only the stable-store vertical
slice. M2 remains open until the packed runtime becomes the authoritative node
storage and old linked-list indexed updates are deleted.
