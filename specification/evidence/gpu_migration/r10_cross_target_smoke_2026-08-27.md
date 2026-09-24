# R10 cross-target smoke — 2026-08-27

Status: **16/16 smoke cells pass**, not full R10 performance evidence.

The release-profile harness and all five executable boundaries built with the
repository opam switch. A full 16-cell `--smoke` invocation used one process per
cell, 64×64 logical resolution, 0.02-second warmup, and 0.05-second measurement.
Runtime-next native, headless, web, and legacy SDL2 completed all four
scenarios (16 cells).

| Target | Basic | PXUI | Canvas | Scene3 |
|---|---:|---:|---:|---:|
| runtime-next native | pass | pass | pass | pass |
| runtime-next headless | pass | pass | pass | pass |
| runtime-next web | pass | pass | pass | pass |
| legacy SDL2 native | pass | pass | pass | pass |

The legacy failure was a harness linkage issue rather than an SDL2-compat or
display failure. `otool -L _build/default/tools/bench_renderer.exe` showed both
`libSDL3.0.dylib` and `libSDL2-2.0.0.dylib`, with SDL3 first. The staged Prismel
archive contains dormant runtime-next input code, so Darwin resolved shared SDL
symbol names from SDL3 before SDL2-compat and legacy `SDL_Init` failed with an
empty error.

```text
_build/default/tools/bench_renderer.exe:
  /opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib
  /opt/homebrew/opt/sdl2-compat/lib/libSDL2-2.0.0.dylib
```

The Unix adapter now detects this exact co-link state using `otool` and
preloads the executable's already-linked SDL2 compatibility dylib for the
legacy child only. It does not substitute another renderer or change the
benchmark protocol. A direct legacy Basic probe then initialized and emitted a
normal measurement, and the unchanged 16-cell protocol passed:

```text
opam exec -- dune build --profile release \
  tools/r10_performance/r10_performance_protocol.exe \
  tools/r10_performance/r10_existing_adapter.exe \
  tools/r10_performance/r10_runtime_next_target_benchmark.exe \
  tools/bench_renderer.exe \
  tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe
_build/default/tools/r10_performance/r10_performance_protocol.exe \
  --manifest tools/r10_performance/r10_manifest.json \
  --output _build/r10-full-smoke.json --smoke
_build/default/tools/r10_performance/r10_performance_protocol.exe \
  --validate _build/r10-full-smoke.json
```

The report contains 16 samples, four legacy samples, and zero failures. It ran
on Darwin 25.4.0, Apple M1 arm64, 8 logical CPUs, 16 GiB RAM, OCaml 5.3.0, from
pre-commit revision `bf618584e4e8b3cc6df4becfec0e346fec0b3d19`. The working
tree was dirty, and each cell measured only 0.05 seconds after 0.02 seconds of
warmup, so timings remain intentionally non-qualification data. GPU, display,
power, and thermal facts unavailable to the typed boundaries remain explicit
`null`.

This closes the local smoke/init blocker only. Full R10 still requires five
interleaved warmed 30-second samples per cell under the frozen protocol; this
smoke must not be cited as passing that performance gate.
