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

The 30-minute gate is documented here but was not run as part of this change.
Its JSON is evidence only after that command completes successfully on the
qualification machine; this commit claims only the deterministic short smoke.
