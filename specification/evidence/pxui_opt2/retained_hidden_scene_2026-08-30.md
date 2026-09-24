# Retained hidden Scene candidate evidence

Frozen `OPT2.md` SHA-256:
`2c59594e53eb236cd108867f653d61deb30ded2b987ffc9fffee55062fcb383b`.

This candidate advances the workspace/camera/Scene3/native-stage vertical path
needed by OPT2 M5, M8, M11, and M12. It does not claim those milestones are
complete.

## Changes

- workspace panes retain one authoritative geometry snapshot keyed by frame
  dimensions, ratios, and collapse state;
- unchanged 2D and 3D camera setters preserve physical identity;
- `Easy_camera.camera` retains its derived camera behind an exact parameter
  snapshot;
- hidden Environment3 frames retain the exact `Clear + View3d` Scene value;
- texture-free, shadow-free Scene3 lowering retains prepared mesh/state/uniform
  payloads by physical scene, camera, and viewport identity;
- the exact resource-free retained `Clear + View3d` native stage is reused;
- textures, shaders, and shadows are excluded from prepared/stage reuse;
- packed mesh, prepared Scene3, and native-stage caches are bounded to 16
  entries and 256 MiB of conservatively counted payload per cache.

Tests require stable resource-free inputs to reuse the exact prepared/staged
value and resource-bearing inputs not to use that retained stage path.

## Hidden native measurements

All samples used one domain, scale 1, exact 18,278-piece / 278,368-triangle /
835,104-render-vertex shattered geometry, two seconds of warmup, and five
seconds of measurement:

```sh
PRISMEL_RENDERER_BENCH_WARMUP=2 PRISMEL_RENDERER_BENCH_SECONDS=5 \
  dune exec tools/bench_shattered_renderer.exe -- hidden
```

| Candidate | Allocation/frame | FPS | Median | p95 | CPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| M1 no-op controls | 47,720 B | 116.71 | 8.25 ms | 10.08 ms | 15.22% |
| hidden slider sync removed | 46,557 B | 117.90 | 8.25 ms | 10.29 ms | 14.91% |
| workspace geometry retained | 45,139 B | 117.39 | 8.21 ms | 9.83 ms | 15.83% |
| camera setters retain identity | 42,574 B | 117.89 | 8.27 ms | 9.99 ms | 16.62% |
| derived camera retained | 41,108 B | 117.55 | 8.30 ms | 9.98 ms | 16.13% |
| prepared Scene3 retained | 28,559 B | 116.82 | 8.23 ms | 9.76 ms | 14.50% |
| native stage retained | 25,666 B | 117.27 | 8.37 ms | 10.25 ms | 17.66% |

The final row allocated 15,065,784 bytes over 587 frames. Short samples carry
thermal and scheduling noise, so FPS/CPU movements are diagnostic rather than
qualification claims. Allocation is deterministic enough to direct the next
work, but remains above M12's 16 KiB interim and 4 KiB final gates.

## Verification

```sh
dune exec lib/prismel/test_scene3_native_lowering.exe
dune exec test/test_prismel.exe
dune exec test/test_easy_camera2.exe
dune runtest lib/sketch_ui lib/pxui
dune build @all
git diff --check
```

All commands passed before commit.
