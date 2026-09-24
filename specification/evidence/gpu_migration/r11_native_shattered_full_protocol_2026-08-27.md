# R11 real-M1 shattered-cube full protocol — 2026-08-27

The complete visible/hidden R11 protocol passed on an Apple M1 Mac mini. HEAD
was committed checkpoint `c383bea` when the release binary was built, and the
binary timestamp precedes the next commit. This was a shared multi-agent
worktree and global cleanliness was not captured at build time, so unrelated
uncommitted lanes may have been present; the evidence does not overstate this
as a clean-checkout qualification.

The accepted workload contains 18,278 pieces, 278,368 triangles, and 835,104
render vertices. Its one-domain/four-domain cook is exact and retains topology,
attribute, order, and render hashes recorded in the accompanying JSON.

## Protocol and result

Each visibility lane used five independent native processes. Every process
created a real SDL3 Metal window/view and OGPU Metal renderer, rendered five
warmup frames, then measured for the full 30 seconds.

| Visibility | Total frames | Median run FPS | Median frame | Median run p95 | Median run p99 | Median CPU |
|---|---:|---:|---:|---:|---:|---:|
| Visible | 17,976 | 119.903 | 8.483 ms | 9.520 ms | 10.024 ms | 10.21% |
| Hidden | 17,987 | 119.950 | 8.529 ms | 9.471 ms | 9.725 ms | 9.42% |

Every process uploaded exactly 60,127,488 prepared bytes before measurement
and zero replacement bytes during measurement. Every run retained one bounded
cache entry, observed zero measurement cache misses, and recorded exactly one
draw, render pass, and backend submission per measured frame.

Median per-run OCaml allocation was 75.77 MB visible and 75.81 MB hidden across
the entire 30-second interval (about 21 KB per frame), with 5.46 MB promoted.
Endpoint RSS ranged from 155,760–331,840 KiB visible and 154,160–331,520 KiB
hidden. These are isolated process endpoint observations, not a within-process
plateau, so this protocol does not replace the separate R12 stability gate.

Native GPU duration/counters, refresh rate, power state, and thermal state were
not available and remain `null`; no estimate is substituted.

## Commands

```sh
opam exec -- dune build --profile release \
  tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  tools/runtime_next_native_benchmark/runtime_next_native_r11_protocol.exe

_build/default/tools/runtime_next_native_benchmark/runtime_next_native_r11_protocol.exe \
  --benchmark _build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  --artifact _build/native-bench-results/shattered-acceptance.artifact \
  --output-dir _build/r11-native-protocol-2026-08-27 \
  --visibility visible --seconds 30 --runs 5

_build/default/tools/runtime_next_native_benchmark/runtime_next_native_r11_protocol.exe \
  --benchmark _build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  --artifact _build/native-bench-results/shattered-acceptance.artifact \
  --output-dir _build/r11-native-protocol-2026-08-27 \
  --visibility hidden --seconds 30 --runs 5
```

The evidence JSON contains every per-run metric and SHA-256 of each raw report.
