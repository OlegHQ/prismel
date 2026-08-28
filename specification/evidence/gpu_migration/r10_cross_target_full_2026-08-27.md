# R10 full cross-target run — 2026-08-27

Status: **protocol complete; R10 performance gate failed**.

The exact checked manifest ran from clean commit
`2e013c0bfd0243b865f90fa713ce7551757bbfc8`: release profile, 64×64 logical
resolution, five interleaved rounds, 16 cells per round, three seconds warmup
and 30 seconds measurement per child. All 80 independent child processes
completed and the unchanged structural validator passed. The normalized raw
report remains `_build/r10-full.json`; its SHA-256 is
`3aa19b38dde483225da9fd41a327f4a13ce8654e9c049cd9093516cb6f3d0f71`.
It records `git_dirty=false`, zero failures, Darwin 25.4.0, Apple M1 arm64,
8 logical CPUs, 16 GiB RAM, and OCaml 5.3.0.

Commands:

```text
opam exec -- dune build --profile release \
  tools/r10_performance/r10_performance_protocol.exe \
  tools/r10_performance/r10_existing_adapter.exe \
  tools/r10_performance/r10_runtime_next_target_benchmark.exe \
  tools/bench_renderer.exe \
  tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe
_build/default/tools/r10_performance/r10_performance_protocol.exe \
  --manifest tools/r10_performance/r10_manifest.json \
  --output _build/r10-full.json
_build/default/tools/r10_performance/r10_performance_protocol.exe \
  --validate _build/r10-full.json
shasum -a 256 _build/r10-full.json
```

The table reports the median across each cell's five samples. Times are
milliseconds; CPU is process CPU percent; RSS is KiB.

| Target | Scenario | Median frame | p95 frame | CPU | Peak RSS |
|---|---|---:|---:|---:|---:|
| legacy | Basic | 9.824 | 21.910 | 46.10 | 104720 |
| runtime-next native | Basic | 8.494 | 8.923 | 10.53 | 88672 |
| headless | Basic | 8.434 | 9.129 | 21.57 | 86224 |
| web | Basic | 0.052 | 0.066 | 100.01 | 123584 |
| legacy | PXUI | 13.529 | 19.750 | 67.40 | 111744 |
| runtime-next native | PXUI | 8.493 | 8.951 | 10.81 | 88720 |
| headless | PXUI | 8.552 | 9.103 | 24.51 | 85808 |
| web | PXUI | 0.104 | 0.136 | 100.01 | 69872 |
| legacy | Canvas | 11.709 | 21.755 | 42.54 | 105808 |
| runtime-next native | Canvas | 8.466 | 8.918 | 10.42 | 88656 |
| headless | Canvas | 8.586 | 9.084 | 25.17 | 86496 |
| web | Canvas | 0.102 | 0.133 | 100.01 | 70656 |
| legacy | Scene3 | 11.842 | 22.079 | 42.20 | 124656 |
| runtime-next native | Scene3 | 8.613 | 9.195 | 11.06 | 99552 |
| headless | Scene3 | 30.681 | 31.302 | 100.54 | 104720 |
| web | Scene3 | 30.841 | 31.318 | 100.01 | 33936 |

The native candidate frame-time cells are within the frozen envelope and are
faster than legacy. The overall R10 gate nevertheless fails and cannot average
those wins against other cells:

- The original summary incorrectly compared headless/web Scene3 with the
  native OpenGL legacy cell. Their authoritative Phase 0 SDL2 software
  baselines are target-specific (46.813 ms headless and 47.019 ms web median),
  so the measured 31 ms candidate cells are not Scene3 timing regressions.
  The corrected harness labels the OpenGL comparator `legacy-native` and never
  uses it for headless/web acceptance.
- Web Basic peak RSS is 1.180× legacy, beyond the 10% p95 envelope used for
  peak/steady memory comparison.
- Promoted allocation is above legacy in multiple cells, including native
  Basic (4,618,264 versus 86,768 bytes) and all web cells (107–173 MiB for
  Basic/PXUI/Canvas). Structural timing validation does not waive this metric.
- Typed GPU time/utilization, display, thermal, and power facts remain `null`;
  therefore the run also cannot prove those required R10 dimensions.

This evidence closes the missing full-run question but does **not** mark R10
green. The next work is to profile and remove Scene3 software-target and web
allocation/CPU regressions, then rerun the complete unchanged protocol.
