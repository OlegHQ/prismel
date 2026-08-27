# Phase 4 Raster2 audit — 2026-08-27

This audit compares the frozen R1–R12 gates in `NEW_GPU_STUFF.md` with the
current committed Raster2 work. It does not change the frozen plan and does not
count an isolated Raster2 unit fixture as Prismel, Runtime, web, or Metal
integration evidence.

## Gate matrix

| Gate | Implemented and directly exercised | Honest status and missing gate |
| --- | --- | --- |
| R1 Stable API | The frozen API-manifest checker passes on the current tree. No example or sketch was edited by the Raster2 commits. | **Partial.** The atomic renderer migration has not happened. A final clean-tree manifest comparison and declared SDL major-version review remain required. |
| R2 Scene2/PXUI parity | Packed surfaces (`5f88b3f`), compositing (`daf9b6f`), path fill/stroke tessellation (`f77acd6`, `286e6cd`), primitives (`f43fb1f`), image/mask sampling (`32bf5a6`), shared IR and consumer (`880e6aa`, `4bcc4b1`), path consumer (`3d1c2c1`), and deterministic batching fixtures exist. Even-odd/non-zero holes, clipping, transforms, transparent backgrounds, pitch padding, and one/four-domain equality are exercised. | **Partial.** Prismel `Scene.t` and PXUI do not lower to `Raster2.Render_ir`; Metal does not consume this same IR. Rounded rectangles, all legacy curve/pie/text/widget fixtures, and cross-backend topology/batch equality are not closed. |
| R3 Scene3 parity | Geometry preparation (`a298038`), triangle rasterization (`313b8c6`), depth/stencil (`01e658a`), MSAA (`090ffae`), lighting/fog/specular/oriented normals (`51128b0`), textures (`4547b98`), shadows and PCF (`787e72c`, `2efa392`), and Scene3 execution (`ba92d55`) have exact software fixtures. | **Partial.** Prismel `Scene3`, Canvas, captures, functional `Shader3`, and the Metal consumer are not wired to these modules. The authored-Boolean-normal test is local value evidence, not a terminal packed-piece-to-upload integration fixture. |
| R4 Resource parity | Bounded typed resource cache (`31a6cc5`), atlas (`bf9c384`), texture mip ownership (`4547b98`), glyph preparation (`991047a`), offscreen lifecycle (`b8754b5`), and readback (`f9629c7`) have stale/bounds/lifetime or plateau fixtures. | **Partial.** Prismel Image/Font/Canvas/Assets watched reload, failed-reload identity, on-stop ordering, audio, and renderer/device teardown integration remain missing. |
| R5 Target parity | Raster2 is platform-independent and its tests require no SDL, Metal, display, or GPU. | **Missing integration.** Runtime still selects the legacy renderer; native/headless/web do not yet consume a common Scene/Frame/Event stream or authoritative Raster2 framebuffer. |
| R6 Coordinate/DPI parity | Packed pitch, clipping, viewport/scissor, transforms, and readback orientation have exact unit fixtures. | **Partial.** There is no 1x/Retina Prismel-to-Raster2 lowering, physical drawable conversion, pointer mapping, font-density rerasterization, browser mapping, or native capture fixture. |
| R7 Deterministic pixels | Raster2 focused tests compare exact bytes across independently owned one/four-domain preparations. Aligned copies and exact-format readback are covered. | **Partial.** Phase-0 frozen PNG/tolerance fixtures are not driven through Raster2, and native Metal exact/tolerance comparisons have not run. No tolerance has been changed. |
| R8 Multi-frame correctness | Scene3, texture, path, text, readback, offscreen, multisample, and cache fixtures include frame 600 or 100k churn; several include frames 1/2/60/600. | **Partial.** Every frozen application fixture must cover exactly frames 1, 2, 60, 600 and post-resize. Current module tests are not a complete application/target matrix. |
| R9 Upload/batching structure | Stable prepared mesh identity plus zero preparation/upload-intent byte increase for 600 camera-only frames and 100k bounded churn is tested (`392f4cc`). Atlas/resource-cache bounds and stable IR batches are tested. | **Partial.** The cache is not connected to Prismel or OGPU/Metal uploads; zero native vertex/index replacement bytes and UI draw/FFI batch scaling remain unproved. |
| R10 Performance non-regression | Hot loops use packed bytes/fixed loops and bounded containers; deterministic scale tests exist. | **Missing external gate.** No Phase-0 M1 release median/p95 comparison for Basic, PXUI, Canvas, Scene3, hidden/visible UI, headless, or web has been recorded. Functional tests are not performance evidence. |
| R11 Shattered-cube performance | The prepared-mesh cache supplies the intended stable identity/version/layout and upload-intent counters. | **Missing external gate.** The 18,278-piece/278,368-triangle sketch has not run through Raster2/OGPU/Metal; residency, draw count, timing, RSS, allocation, and frame pacing are unmeasured. |
| R12 Long-run stability | Individual caches/arenas/rings use explicit capacities; 100k churn/lifecycle tests cover atlas, resource cache, scratch, offscreen, and prepared mesh state. | **Missing external gate.** There is no 30-minute native/headless/web run with resize, reload, Canvas and audio lifecycle, nor final RSS/live-handle/queue plateau evidence. |

## Commands run for this audit

- The already-built API manifest checker completed `--check` silently and
  successfully against the current workspace.
- The already-built dependency-direction executable passed for the 12 supplied
  libraries and rejected its injected reverse edge.
- The committed Raster2 suite was green immediately before this audit at
  `392f4cc`; concurrent renderer work was deliberately not swept into this
  evidence commit.

The dependency test currently receives SDL3, Metal, OGPU, OGPU-Metal, Runtime,
Prismel, and Wap Dune files, but not `lib/raster2/dune`. Adding Raster2 to that
real-graph gate is still required before claiming the new dependency boundary
is mechanically complete.

## Smallest safe Scene-to-shared-IR boundary

No lowering code is added in this audit. `Scene.node` is abstract in
`lib/prismel/scene.mli`; another private compilation unit cannot pattern-match
it. Putting a partial lowering inside `Scene.render` would couple recording to
the active legacy renderer, allocate work that is immediately discarded, and
silently omit Image/Font/View3d resource ownership. Adding a public escape hatch
would violate this task's no-public-interface constraint.

The smallest correct follow-up is an internal representation split:

1. Move the concrete node/style/blend representation to a private
   `Scene_description` module inside the `prismel` library. Keep `Scene.node`
   and `Scene.t` abstract and keep every existing constructor signature.
2. Make `Scene` constructors build `Scene_description` values and keep the
   legacy renderer as one private consumer during comparison.
3. Add a private `Scene_raster2_lowering` consumer returning
   `Raster2.Render_ir.t` plus a bounded typed resource table. Lower Clear,
   transform, clip, blend, primitive geometry, and Path first; reject rather
   than skip Image/Text/View3d until their owned-resource adapters exist.
4. Add `raster2` to `lib/prismel/dune` only in that implementation commit and
   extend `gpu_dependency_direction` to include `lib/raster2/dune` and an
   injected `raster2 -> prismel` rejection.
5. Prove constructor-by-constructor legacy/Raster2 command ordering and pixels,
   then let Runtime select the consumer at the existing private effect boundary.

This preserves `prismel -> raster2`, leaves Raster2 independent, avoids raw
native pointers, and keeps the frozen public Scene API byte-identical.
