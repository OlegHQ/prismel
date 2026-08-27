# Raster2 migration long-run stability gate

The SDL-free `tools/gpu_migration_stability.exe` exercises Raster2 offscreen
rendering, changing mesh uploads through `scene_execution`, resize generations,
image-generation cache invalidation, transient offscreen ownership, and the
bounded Wap frame presenter. It samples process RSS, OCaml heap size, cache
occupancy, and Raster2 live ownership counters into a JSON report.

CI uses the deterministic frame override:

```sh
opam exec -- dune exec tools/gpu_migration_stability/test_gpu_migration_stability.exe
```

The release qualification command is:

```sh
opam exec -- dune exec --profile release tools/gpu_migration_stability/gpu_migration_stability.exe -- \
  --minutes 30 --sample-every 600 --report _build/raster2-stability-30m.json
```

## Qualification result

The command above completed successfully on the M1 qualification machine from
`2026-08-27T13:02:24Z` through `2026-08-27T13:32:25Z`. The uncommitted report
was `_build/raster2-stability-30m.json` (schema 1).

- Frames rendered and presented: `23,464,561`
- Deterministic workload hash: `ef98c79010144e39`
- Image reload generation: `756,921`
- Stable scene upload bytes: `1,020`
- Wap frames submitted: `23,464,561`
- Sample observations / retained ring: `1,781 / 256`
- RSS overall minimum / maximum: `13,904 / 16,016 KiB`
- Final retained-window RSS minimum / maximum: `15,744 / 16,016 KiB`
- Final retained-window heap minimum / maximum: `221,610 / 313,842 words`
- Maximum live target / view / cache entries: `1 / 0 / 1`
- Live targets / views after teardown: `0 / 0`

The flat-memory criterion is: after warmup, the fixed 256-sample final window
must remain within five percent of its minimum RSS; all ownership and cache
counters must remain at their declared bounds and reach zero where teardown
applies. The observed final-window RSS range was 272 KiB, or 1.73 percent of
15,744 KiB, so this run passes. The deterministic short smoke independently
repeated hash `a1adccf67f67ccd9` twice for the exact 600-frame workload.

Two precursor runs were rejected rather than counted as qualifications. The
first exposed an unbounded diagnostic trace in `Ogpu.Backend_mock` and was
stopped after about 78 seconds at roughly 648 MiB RSS. The second ran from
`2026-08-27T12:00:07Z` through `2026-08-27T12:30:07Z`, but retained all 32,880
samples; it ended at 81,952 KiB RSS with 6,443,511 heap words and therefore
failed the instrumentation-memory criterion. A time-throttled follow-up from
`2026-08-27T12:31:04Z` through `2026-08-27T13:01:04Z` still retained 1,754
samples and was also rejected because retention scaled with arbitrary
`--minutes`. The passing implementation uses a fixed 256-entry ring plus the
first sample and aggregate extrema; its 300-observation smoke proves that only
256 entries remain retained.
