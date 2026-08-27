# R10 cross-target smoke — 2026-08-27

Status: **blocked**, not performance evidence.

The release-profile harness and all five executable boundaries built with the
repository opam switch. A full 16-cell `--smoke` invocation used one process per
cell, 64×64 logical resolution, 0.02-second warmup, and 0.05-second measurement.
Runtime-next native, headless, and web completed all four scenarios (12 cells).

| Target | Basic | PXUI | Canvas | Scene3 |
|---|---:|---:|---:|---:|
| runtime-next native | pass | pass | pass | pass |
| runtime-next headless | pass | pass | pass | pass |
| runtime-next web | pass | pass | pass | pass |
| legacy SDL2 native | failed | failed | failed | failed |

Every legacy child was a separate `bench_renderer.exe` process launched by the
Unix-only adapter. All four exited 2 before measurement with the same precise
diagnostic:

```text
Fatal error: exception Failure("SDL initialization failed: ")
```

The SDL2 error payload itself was empty. The harness continued after each child
failure and wrote a partial report with 12 normalized samples and four
structured failure records to `_build/r10-full-smoke.json`. It exited 2. An
explicit strict validation then exited 2 with:

```text
R10: legacy/basic has 0 samples, expected 1
```

The smoke ran on Darwin 25.4.0, Apple M1 arm64, 8 logical CPUs, 16 GiB RAM,
OCaml 5.3.0. The working tree was dirty and the recorded pre-commit revision was
`59645efeef6f3c09532518cbc462af77043b509a`, so the timings are intentionally
not qualification data. GPU, display, power, and thermal facts unavailable to
the typed boundaries remained explicit `null`.

Do not start the five warmed 30-second qualification samples until the legacy
SDL2 executable initializes in the qualification session. Never replace the
four missing baselines with runtime-next or synthetic results.
