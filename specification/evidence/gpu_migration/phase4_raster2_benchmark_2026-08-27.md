# Phase 4 Raster2 benchmark evidence — 2026-08-27

This is a new Phase 4 measurement. It does not modify or supersede the frozen Phase 0 evidence.

- Timestamp: `2026-08-27T11:00:56Z`
- Benchmark implementation: commit `b0b6adf`
- Machine: Apple M1, 16 GiB, Darwin 25.4.0 arm64
- OCaml: 5.3.0, 64-bit
- Dune profile: `release`
- Workload: 320×180, 2 warmup iterations, 5 measured samples, 60 frames per sample
- Domain metadata runs: 1 and 4. The current fixed workloads execute sequentially; this field records the requested qualification configuration rather than claiming parallel speedup.

Commands:

```sh
opam exec -- dune build --profile release tools/bench_raster2_renderer.exe
_build/default/tools/bench_raster2_renderer.exe SCENARIO \
  --warmup 2 --samples 5 --frames 60 --domains DOMAINS --check
```

| Scenario | Domains | Median wall (s) | Median CPU (s) | Output hash |
|---|---:|---:|---:|---|
| basic2d | 1 | 0.234311104 | 0.234307000 | `df2ec64127736b80` |
| path | 1 | 0.246021032 | 0.246012000 | `79306ba0b301f2fe` |
| text | 1 | 0.134821892 | 0.134822000 | `e0b07070cd197ce4` |
| scene3 | 1 | 0.588083029 | 0.588055000 | `a8bcb319a95e4000` |
| offscreen | 1 | 0.357120991 | 0.357113000 | `9fd38a70cf1aa370` |
| basic2d | 4 | 0.235553980 | 0.235533000 | `df2ec64127736b80` |
| path | 4 | 0.246646881 | 0.246623000 | `79306ba0b301f2fe` |
| text | 4 | 0.135200977 | 0.135188000 | `e0b07070cd197ce4` |
| scene3 | 4 | 0.587723017 | 0.587719000 | `a8bcb319a95e4000` |
| offscreen | 4 | 0.359024048 | 0.359023000 | `9fd38a70cf1aa370` |

The raw evidence JSON records all five wall samples and the promoted, major, and live-word measurements. Within each run, all five measured samples produced the same output hash. The hashes also matched between the domain metadata runs for every scenario. These are measurements only; no comparative performance or production-readiness claim is made.
