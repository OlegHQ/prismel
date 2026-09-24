# Runtime-next prepared rendering benchmark — 2026-08-27

This release-profile run exercises the portable `Scene_execution` path through
the real `ogpu-raster2` backend for representative Basic, PXUI-like, Canvas,
and Scene3 batches. The shattered-cube preparation/batching case uses
`Backend_mock` so it measures OGPU graph preparation and submission rather than
software rasterization. Its cardinality is pinned to 18,278 pieces and 278,368
triangles.

The harness instruments the backend driver boundary. `draw_count`,
`pass_count`, and `ffi_boundary_calls` therefore count observed submissions,
not estimates. Warmup prepares immutable meshes; every measured visible case
then records zero replacement upload bytes. The shattered case submits all
18,278 ordered draws in one pass per frame: 109,668 draws, six passes, and six
backend calls over the six measured frames.

## Local result summary

| Scenario | Median frame | p95 frame | FPS | Prepared upload | Measured upload | Draws / passes / calls |
|---|---:|---:|---:|---:|---:|---:|
| Basic | 0.0318 ms | 0.0319 ms | 31,410 | 1,584 B | 0 B | 30 / 30 / 30 |
| PXUI-like | 0.1179 ms | 0.1197 ms | 8,446 | 4,608 B | 0 B | 1,920 / 30 / 30 |
| Canvas | 0.0572 ms | 0.0578 ms | 17,503 | 3,456 B | 0 B | 240 / 30 / 30 |
| Scene3 | 18.5022 ms | 18.5473 ms | 54.0 | 1,327,680 B | 0 B | 360 / 30 / 30 |
| Shattered batching | 2.8274 s | 3.8995 s | 0.314 | 4,217,760 B | 0 B | 109,668 / 6 / 6 |

Hidden scheduling was also measured for 3,000 iterations. It performed no
draw, pass, backend call, or upload and allocated 1,112 bytes per 1,000-iteration
sample. The nanosecond-scale loop timing is timer-floor dominated, so it is
reported in JSON as scheduler iterations rather than rendering FPS.

## Comparison limits

The local legacy SDL2 headless executable was run for all four representative
scenarios, but SDL initialization failed under the local dummy-video setup.
Consequently this evidence does not present a misleading same-run speedup.
The frozen legacy measurements remain in `phase0_performance.json`; they were
collected under a different protocol and are reference context only.

No native Metal GPU duration or utilization counter was available. The JSON
keeps native GPU counters `null`; CPU time is not relabeled as GPU evidence.
The local machine was an Apple M1 with 16 GiB RAM, Darwin 25.4.0 arm64, and
OCaml 5.3.0. Protocol: release profile, one warmup iteration, three samples,
10 frames per ordinary sample, two frames per shattered sample.

Reproduce the prepared path with:

```sh
opam exec -- dune build --profile release tools/bench_runtime_next_parity.exe
_build/default/tools/bench_runtime_next_parity.exe basic --warmup 1 --samples 3 --frames 10
_build/default/tools/bench_runtime_next_parity.exe shattered --warmup 1 --samples 3 --frames 2
```
