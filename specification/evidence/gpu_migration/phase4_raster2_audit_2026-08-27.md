# Phase 4 Raster2 audit — 2026-08-27

This audit compares the frozen R1–R12 gates in `NEW_GPU_STUFF.md` with the
current committed Raster2 work. It does not change the frozen plan and does not
count an isolated Raster2 unit fixture as Prismel, Runtime, web, or Metal
integration evidence.

## Gate matrix

| Gate | Implemented and directly exercised | Honest status and missing gate |
| --- | --- | --- |
| R1 Stable API | Private lowering commits (`b9f9f28`, `59ae442`, `e813369`, `132892f`) preserve the public `Scene` interface and leave examples/sketches unchanged. | **Partial.** The atomic renderer migration has not happened. A clean-tree API-manifest gate remains required after the concurrent private renderer test is registered without becoming public, plus the SDL major-version review. |
| R2 Scene2/PXUI parity | Surfaces (`5f88b3f`), compositing (`daf9b6f`, `81fe03d`), path tessellation (`f77acd6`, `286e6cd`), primitives (`f43fb1f`), image sampling (`32bf5a6`), shared IR/consumer (`880e6aa`, `4bcc4b1`), and path consumer (`3d1c2c1`) exist. Private lowering covers pure Scene2 nodes, ordering, transforms, clips, blends and contours (`b9f9f28`, `59ae442`) with frame-600 and one/four-domain fixtures. | **Partial.** PXUI and Runtime do not yet select this lowering; Metal does not consume the same IR. Legacy-vs-Raster2 pixels for every rounded/curve/pie/text/widget fixture remain open. |
| R3 Scene3 parity | Preparation (`a298038`), triangles (`313b8c6`), depth/stencil (`01e658a`), MSAA (`090ffae`), lighting (`51128b0`), textures (`4547b98`), shadows (`787e72c`, `2efa392`), and execution (`ba92d55`) have exact fixtures. Private `Scene.view3d` lowering crosses a typed callback boundary and atomically rejects unresolved SDL-only resources (`e813369`). | **Partial.** The selected renderer, Canvas/capture, functional `Shader3`, and Metal consumer remain unwired. Textured Scene3 needs a real owned Prismel-resource adapter, and authored Boolean normals lack terminal upload evidence. |
| R4 Resource parity | Bounded cache (`31a6cc5`), atlas (`bf9c384`), texture mips (`4547b98`), glyph preparation (`991047a`), offscreen lifecycle (`b8754b5`), and readback (`f9629c7`) have bounded fixtures. Private Image/Text/Font callbacks snapshot Raster2 resources, preserve watched generation and density identity, make empty text a no-op, stop atomically on failure, execute through the real consumer, and remain exact through frame 600/four domains (`132892f`). | **Partial.** Production Image/Font/Assets adapters, failed-decode retention, Canvas ownership, on-stop ordering, audio, and renderer/device teardown remain unintegrated; current proof uses private deterministic callbacks rather than live SDL resources. |
| R5 Target parity | Raster2 is platform-independent and its tests require no SDL, Metal, display, or GPU. | **Missing integration.** Runtime still selects the legacy renderer; native/headless/web do not yet consume a common Scene/Frame/Event stream or authoritative Raster2 framebuffer. |
| R6 Coordinate/DPI parity | Packed pitch, clipping, viewport/scissor, transforms, and readback orientation have exact unit fixtures. | **Partial.** There is no 1x/Retina Prismel-to-Raster2 lowering, physical drawable conversion, pointer mapping, font-density rerasterization, browser mapping, or native capture fixture. |
| R7 Deterministic pixels | Raster2 focused tests compare exact bytes across independently owned one/four-domain preparations. Aligned copies and exact-format readback are covered. | **Partial.** Phase-0 frozen PNG/tolerance fixtures are not driven through Raster2, and native Metal exact/tolerance comparisons have not run. No tolerance has been changed. |
| R8 Multi-frame correctness | Scene3, texture, path, text, readback, offscreen, multisample, and cache fixtures include frame 600 or 100k churn; several include frames 1/2/60/600. | **Partial.** Every frozen application fixture must cover exactly frames 1, 2, 60, 600 and post-resize. Current module tests are not a complete application/target matrix. |
| R9 Upload/batching structure | Stable prepared mesh identity plus zero preparation/upload-intent byte increase for 600 camera-only frames and 100k bounded churn is tested (`392f4cc`). Atlas/resource-cache bounds and stable IR batches are tested. | **Partial.** The cache is not connected to Prismel or OGPU/Metal uploads; zero native vertex/index replacement bytes and UI draw/FFI batch scaling remain unproved. |
| R10 Performance non-regression | Hot loops use packed bytes/fixed loops and bounded containers; deterministic scale tests exist. | **Missing external gate.** No Phase-0 M1 release median/p95 comparison for Basic, PXUI, Canvas, Scene3, hidden/visible UI, headless, or web has been recorded. Functional tests are not performance evidence. |
| R11 Shattered-cube performance | The prepared-mesh cache supplies the intended stable identity/version/layout and upload-intent counters. | **Missing external gate.** The 18,278-piece/278,368-triangle sketch has not run through Raster2/OGPU/Metal; residency, draw count, timing, RSS, allocation, and frame pacing are unmeasured. |
| R12 Long-run stability | Individual caches/arenas/rings use explicit capacities; 100k churn/lifecycle tests cover atlas, resource cache, scratch, offscreen, and prepared mesh state. | **Missing external gate.** There is no 30-minute native/headless/web run with resize, reload, Canvas and audio lifecycle, nor final RSS/live-handle/queue plateau evidence. |

## Commands run for this audit

- At `132892f`, `lib/prismel/prismel.cma`, the focused private resource-lowering
  executable, and the full Raster2 suite were green.
- The dependency-direction executable passed with all 14 supplied libraries,
  including `lib/raster2/dune`, and rejected its injected reverse edge.
- The resource fixture covered callback cardinality, watched generation and
  density identity, empty-text no-op, atomic failure, real Consumer execution,
  frame 600, and independently owned four-domain equality.
- The API-manifest run at that checkpoint was blocked by a concurrent untracked
  private renderer test under `lib/prismel/` being discovered as a public module
  without an `.mli`. That integration issue is not counted as a pass and must be
  resolved and rerun on a clean tree.

## Implemented private comparison pivot

The boundary proposed by the original audit now exists. `Scene_description` is
private; public `Scene.node`/`Scene.t` remain abstract; the legacy renderer stays
selectable; and `Scene_raster2_lowering` returns shared IR plus typed resource
snapshots (`b9f9f28` through `132892f`). Pure Scene2 and representable View3d,
Image, and Text paths lower without raw native pointers. Unsupported SDL-only
resources and unrepresentable image transforms reject explicitly rather than
being skipped.

The next smallest safe integration step is the private renderer comparison
pivot: register its test without expanding the public module manifest, feed the
same immutable Scene to legacy and Raster2 consumers, and record exact command
ordering/pixel differences. Only after those comparisons, Runtime target
fixtures, resource lifecycle tests, and R1-R12 external gates pass may target
selection switch atomically. No public `.mli`, example, or legacy-render path
should be removed during this side-by-side phase.
