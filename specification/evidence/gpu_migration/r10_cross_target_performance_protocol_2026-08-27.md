# R10 reproducible cross-target performance protocol — 2026-08-27

Status: harness-ready and 16-cell smoke attempted; full qualification is
blocked on legacy SDL2 initialization. Smoke results are plumbing checks and
are not performance evidence. See `r10_cross_target_smoke_2026-08-27.md`.

## Matrix and process isolation

Measure `basic`, `pxui`, `canvas`, and `scene3` at one fixed 64×64 logical
resolution on runtime-next native, headless, web, and the legacy executable.
Every matrix cell has five independent, warmed, 30-second samples. Each sample
is a new child process. The manifest must point each cell at an already-linked
executable; the harness never loads either SDL version and never co-links SDL2
and SDL3. Runtime-next native uses
`runtime_next_native_benchmark`; target-neutral legacy/headless/web cells use
`bench_renderer`; prepared non-native comparison may use
`bench_runtime_next_parity`. Do not substitute the latter's synthetic workload
for an end-to-end target baseline without labelling the engine distinctly.

Samples are scheduled round-major in manifest order: sample 1 of every cell,
then sample 2 of every cell, and so on. Arrange manifest cases to rotate targets
within each scenario. This interleaves implementations when display/web
automation permits and reduces order and thermal bias. Keep other workloads,
power source, display topology, browser version, visibility, and frame pacing
fixed. Record deviations alongside the artifact.

## Normalized evidence

`r10_performance_protocol` preserves each child's JSON under `raw` and emits
`prismel-r10-performance/v1`. Every sample records median/p95/p99 frame time;
wall, user, system, total CPU and CPU percent; allocated and promoted bytes and
peak sampled RSS; upload bytes, draws, passes, and backend calls. It also records
exact git commit/dirty state, Dune profile, OS/release/architecture/hostname,
CPU, logical CPU count, memory, OCaml version, logical/drawable resolution,
pixel scale, and the manifest's display facts. GPU duration/utilization/counters
and thermal/power state are explicit JSON `null` when trustworthy typed sources
are unavailable; absence is never encoded as zero.

The validator derives measured logical size from the child's explicit size or
its drawable-size/density facts; it does not trust the manifest's claim. It
rejects missing target/scenario baselines, sample counts other than the declared
count, mixed profiles, mixed logical resolutions, or missing
wall/median/p95/p99 timing. Raw tools may expose additional counters; these stay
in `raw` so evidence is lossless.

## Commands

Build only the isolated harness and existing benchmark binaries required by the
chosen manifest:

```sh
dune build --profile release tools/r10_performance/r10_performance_protocol.exe
_build/default/tools/r10_performance/r10_performance_protocol.exe \
  --manifest tools/r10_performance/r10_manifest.json --dry-run
_build/default/tools/r10_performance/r10_performance_protocol.exe \
  --manifest tools/r10_performance/r10_manifest.json --output _build/r10-smoke.json --smoke
_build/default/tools/r10_performance/r10_performance_protocol.exe \
  --validate _build/r10-smoke.json
```

The checked `tools/r10_performance/r10_manifest.json` contains all 16 cells;
the example remains a minimal adapter illustration. Dry-run performs no child
execution. Smoke uses one 0.05-second
sample after a 0.02-second warmup and marks `protocol.smoke=true`. A full run
omits `--smoke`; archive its manifest and normalized report together. Never
merge smoke output with qualification evidence.
