# Runtime-next native R11 candidate protocol — 2026-08-27

Status: harness-ready, not qualification evidence. The ten 30-second samples
were deliberately not started while the independent native soak was active.

The candidate consumes the committed shattered-cube acceptance artifact rather
than synthesizing its cardinality. Each child warms five frames and then
measures by elapsed duration. Run five visible samples and five hidden samples:

```sh
mkdir -p _build/native-bench-results/r11-candidate
_build/default/tools/runtime_next_native_benchmark/runtime_next_native_r11_protocol.exe \
  --benchmark _build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  --artifact _build/native-bench-results/shattered-acceptance.artifact \
  --output-dir _build/native-bench-results/r11-candidate \
  --visibility visible --seconds 30 --runs 5
_build/default/tools/runtime_next_native_benchmark/runtime_next_native_r11_protocol.exe \
  --benchmark _build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  --artifact _build/native-bench-results/shattered-acceptance.artifact \
  --output-dir _build/native-bench-results/r11-candidate \
  --visibility hidden --seconds 30 --runs 5
```

Every report records wall/user/system time, median/p95/p99 frame time, FPS,
allocated and promoted bytes, RSS, upload/cache counters, draw/pass/backend-call
counts, window visibility, drawable size, pixel density, and display scale.
Refresh rate, power state, thermal state, and native GPU counters are explicitly
`null` because the current typed boundaries do not expose trustworthy values.

Short protocol plumbing smoke (not performance evidence): one 0.02-second run
per visibility mode completed with three measured frames each, zero measurement
upload bytes, and matching three draw/pass/backend calls. Hidden wall time was
0.025371 s and visible wall time was 0.024952 s. Both reports marked
`protocol_r11_requested=false`, so they cannot be mistaken for 30-second R11
samples.
