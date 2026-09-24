# Runtime-next headless and web stability — 2026-08-27

Commit `69af680` adds a target-specific release harness around the actual
`Runtime_next_headless` and `Runtime_next_web` compositions. It exercises
bounded stable mesh identities, logical/drawable resize, successful watched
image generation replacement plus failed-reload retention, density/text churn
with a 256-entry ceiling, nested Canvas pixels, SDL3_mixer memory generation
and dummy-device lifetime, bounded OGPU diagnostics, Wap presentation, and
resource-before-target teardown.

Both runs used the same fixed 256-observation ring criterion as the accepted
Raster2 stability gate. The two target processes ran concurrently, without a
Dune lock, and wrote distinct ignored raw reports.

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  _build/default/tools/gpu_migration_stability/runtime_next_target_stability.exe \
  --target headless --minutes 30 --sample-every 600 \
  --report _build/runtime-next-headless-30m.json

SDL_AUDIODRIVER=dummy \
  _build/default/tools/gpu_migration_stability/runtime_next_target_stability.exe \
  --target web --minutes 30 --sample-every 600 \
  --report _build/runtime-next-web-30m.json
```

## Results

| Target | Frames | Wall | Workload hash | Observed / retained | Final-ring RSS | Font / trace maxima | Live after teardown |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |
| Headless | 118,193,229 | 1,800.072 s | `e112181f2b775d99` | 196,988 / 256 | 18,640–18,640 KiB (0%) | 256 / 256 | 0/0/0/0/0 |
| Web | 118,198,468 | 1,800.069 s | `b26b61d9a43dd904` | 196,997 / 256 | 14,864–14,864 KiB (0%) | 256 / 256 | 0/0/0/0/0 |

Headless performed 118,548 successful image-generation changes and 119,147
retained failures; web performed 118,554 changes and 119,152 retained failures.
Before ordered teardown each target had four cached buffers, one target texture,
one pipeline, one queue, and one surface. Audio stopped and destroyed before
the target; afterward every backend count was zero. The last retained web
sample observed 118,198,200 submitted Wap frames. The difference from the final
frame count is only the interval after the last 600-frame sample, not a dropped
or unbounded queue claim.

Raw report SHA-256 hashes:

- headless: `e279880f87ff3a6c4fcc75c4b3799edf978474ce97374149915f27a0aff4b9aa`
- web: `b66775adee2f11792a5ed6c69f2c208621361f96c2ef41af0c179c85bdde2cb7`

These runs close the target-specific local headless and web portions of R12.
They do not claim native qualification, browser-client network endurance, GPU
counters, or the final atomic selected-runtime release matrix; the native lane
remains separate.
