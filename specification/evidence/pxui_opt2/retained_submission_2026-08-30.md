# Retained native submission candidate evidence

Frozen `OPT2.md` SHA-256:
`2c59594e53eb236cd108867f653d61deb30ded2b987ffc9fffee55062fcb383b`.

The resource-free retained Scene stage now carries a stable identity/version
through `Native_scene_lowering` into the existing checked renderer replay path.
Converted Scene3 draws are retained by physical staged identity, so unchanged
frames do not repeat entry-array conversion. Resource-bearing stages retain no
identity and continue through complete lowering and validation every frame.

The retained draw cache is bounded to 16 entries. The stage it references is
already bounded by the 16-entry/256-MiB native stage cache.

## Hidden diagnostic

```sh
PRISMEL_RENDERER_BENCH_WARMUP=2 PRISMEL_RENDERER_BENCH_SECONDS=5 \
  dune exec tools/bench_shattered_renderer.exe -- hidden
```

The exact 18,278-piece shattered workload produced 587 frames in 5.007150
seconds (117.23 FPS), with 8.333 ms median, 10.105 ms p95, and 11.316 ms p99.
It allocated 14,167,320 bytes, or 24,135 bytes/frame. This improves on the
preceding 25,666 bytes/frame candidate but remains above the 16-KiB interim
whole-frame diagnostic target.

Memprof after retained replay primarily reports per-drawable Metal command
buffer, render-pass descriptor, encoder, attachment, completion-retention, and
runtime fact/event wrappers. These native ownership costs require a separate
scratch/reuse design; they must not be removed by weakening completion-owned
lifetimes.

## Verification

```sh
dune exec lib/prismel/test_scene3_native_lowering.exe
dune exec test/test_prismel.exe
dune exec test/test_easy_camera2.exe
dune runtest lib/pxui lib/sop_ui lib/pxui_graph lib/sketch_ui
dune build @all
git diff --check
```

All commands passed before commit. Tests require exact staging reuse and a
nonempty stable identity/version for resource-free frames, while texture-bearing
frames must produce distinct unretained stages.
