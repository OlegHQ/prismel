# Phase 5 R9 qualification — 2026-08-28

Status: **Proven** at clean source commit
`042bc4e8ef18bf98bc1e557457db6907239a1286`.

The real M1 Metal protocol rendered the canonical stable Scene3 workload for
600 camera-only measurement frames after warm-up. Preparation uploaded
10,411,520 bytes. The measurement interval uploaded zero bytes, created or
wrote zero native buffers, and reported 600 draws, 600 passes, and 600 backend
calls. The prepared cache remained at two entries. Native GPU timing supplied
600 measured samples, and the framebuffer digest remained
`feab47385e74a7801905766a3c7d22b5`.

The strict synthesis additionally ran the release Scene execution batching,
automatic text LRU, explicit font LRU, and Raster decoded-image cache proofs.
It checked the committed bounds of 64 prepared native entries, 256 mesh
entries, 256 image entries, and 256 glyph entries. Synthesis rejects a dirty
tree, a noncanonical repository root, unstable source snapshots, or a report
whose commit differs from `HEAD`.

Artifacts:

- `runtime_next_native_r9_qualification_2026-08-28.json`
- `runtime_next_r9_synthesis_2026-08-28.json`

Commands:

```sh
opam exec --switch=. -- dune build --profile release \
  tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  tools/runtime_next_native_benchmark/runtime_next_native_r9_protocol.exe \
  tools/runtime_next_native_benchmark/runtime_next_r9_synthesis.exe \
  lib/scene_execution/test_scene_execution.exe \
  lib/prismel_next_api/test_automatic_text_cache.exe \
  lib/prismel_next_resources/test_prismel_next_font.exe \
  lib/ogpu_raster2/test_ogpu_raster2.exe

_build/default/tools/runtime_next_native_benchmark/runtime_next_native_r9_protocol.exe \
  --benchmark _build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  --output /tmp/prismel-r9.json

_build/default/tools/runtime_next_native_benchmark/runtime_next_r9_synthesis.exe \
  --root "$PWD" --native-report /tmp/prismel-r9.json \
  --scene-batching-test _build/default/lib/scene_execution/test_scene_execution.exe \
  --text-cache-test _build/default/lib/prismel_next_api/test_automatic_text_cache.exe \
  --font-cache-test _build/default/lib/prismel_next_resources/test_prismel_next_font.exe \
  --raster-cache-test _build/default/lib/ogpu_raster2/test_ogpu_raster2.exe
```

This moves the strict frozen-gate ledger from 11 to 12 Proven gates. The
current completion is **12/47 = 25.53%**. The nine External gates remain in the
denominator; the scheduling-only locally reachable view is **12/38 = 31.58%**.
