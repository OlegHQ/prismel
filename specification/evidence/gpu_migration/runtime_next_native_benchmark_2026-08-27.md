# Runtime-next native M1 benchmark — 2026-08-27

This standalone release executable links SDL3, Metal, OGPU Metal, and
`Scene_execution`; it does not link Prismel, Tsdl, SDL2, or the legacy renderer.
It constructs real Metal pipeline variants and submits prepared Scene2 and
double68 Scene3 payloads through the current backend.

| Scenario | Median | p95 / p99 | FPS | CPU | Allocated | RSS | Upload after warmup | Draws / passes / backend calls |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Basic | 8.089 ms | 9.407 / 9.431 ms | 120.16 | 2.38% | 374 KB | 81,392 KiB | 0 B | 20 / 20 / 20 |
| PXUI-like | 8.223 ms | 9.545 / 9.650 ms | 120.33 | 5.54% | 6.18 MB | 83,056 KiB | 0 B | 1,280 / 20 / 20 |
| Canvas-like | 8.201 ms | 9.188 / 9.624 ms | 120.14 | 2.87% | 1.08 MB | 81,952 KiB | 0 B | 160 / 20 / 20 |
| Scene3 double68 | 8.320 ms | 9.298 / 9.508 ms | 120.13 | 38.28% | 54.48 MB | 92,224 KiB | 0 B | 240 / 20 / 20 |

The 8.1–8.3 ms cluster reflects FIFO presentation pacing, so it is steady-frame
evidence rather than an unthrottled GPU throughput result. Every ordinary case
has zero observed cache misses and zero replacement upload after three warmup
frames. One compatible render pass and one backend submission are emitted per
frame; draw order remains explicit inside that pass. The committed JSON records
the SHA-256 of each raw result file.

## Full shattered-cube result: blocked, not measured

The exact 18,278-piece/278,368-triangle native workload exposed a correctness
blocker before timing could begin:

```text
Backend.submit: submitted graph contains a destroyed object
```

`Scene_execution` prepares the complete draw list before submission but keeps
only 64 mesh-cache entries. Preparing item 65 evicts an earlier buffer that the
same pending submission still references. Thus the full workload cannot be
honestly timed on the current native path. Chunking it in the benchmark would
hide the required one-graph ownership/caching defect, so this evidence leaves
R11 open and reports no fabricated latency, cache-hit rate, or upload count.

## Reproduction and limits

```text
opam exec -- dune build --profile release \
  tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe
_build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  basic --warmup 3 --samples 20 --report _build/native-basic.json
_build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  shattered --warmup 1 --samples 3
```

Host: Macmini9,1, Apple M1, 16 GiB, macOS 26.4.1 (25E253), OCaml 5.3.0.
CPU time is process user+system time; allocations are OCaml allocated bytes;
RSS is a post-sample process observation. Backend calls are instrumented driver
submissions, not Metal FFI selector counts. Native GPU duration/utilization and
legacy speedup are intentionally absent. The protocol is shorter than the
frozen five warmed 30-second R10 protocol, so this is local diagnostic evidence,
not an R10 pass.
