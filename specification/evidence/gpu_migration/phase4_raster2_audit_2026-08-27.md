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

## R2 public Scene constructor audit after `d199322`

Status is strict: **I/T** means implemented and directly exercised; **I/U**
means implemented by an audited representation mapping without a
constructor-specific parity fixture; **R/T** means explicitly rejected and
tested; **R/U** means an audited explicit rejection without its own focused
fixture; **M** means missing. These are not legacy pixel-parity claims.

| Public Scene surface | Status | Exact implementation / fixture evidence |
| --- | --- | --- |
| `empty`, `one`, `group` | I/T | Empty lists and recursive `Group` preserve ordering; nested group/state execution is covered by `b9f9f28`/`59ae442`. No standalone empty-frame pixel golden exists. |
| `clear` | I/T | `Render_ir.Clear`; private lowerer and Backend-mock frame order (`b9f9f28`, `40bad9a`). |
| `point`, `line` including width | I/T | Point quad and deterministic widened-line geometry in the initial exact-order fixture (`b9f9f28`). |
| `rect` | I/T | Fill quad plus optional Path stroke; fill/stroke exercised (`b9f9f28`). |
| `square` | I/U | Public convenience maps to `Rect`; no dedicated square lowering/pixel fixture. |
| `rounded_rect` | I/T | Rounded Path tessellation is directly included in the constructor fixture (`59ae442`). |
| `circle`, `ellipse` | I/T | Deterministic sampled closed Paths, fill/stroke exercised (`59ae442`). |
| `triangle` | I/T | Path triangle plus OGPU stable prepared-mesh/upload fixture (`b9f9f28`, `40bad9a`). |
| `quad` | I/U | Public convenience maps to `Polygon`; polygon is tested, but no dedicated quad pixel fixture. |
| `polygon`, `polyline` | I/T | Closed fill/stroke and open stroke fixtures (`59ae442`). |
| `arc`, `pie`, `bezier` | I/T | Sampled open/closed Path fixtures (`59ae442`). |
| `path` rules/contours/fill/stroke | I/T | Separate contours, transparent holes, ordering, frame-600 and four-domain fixtures (`59ae442`, `3d1c2c1`). |
| `text`, `debug_text`, `font_text` | I/T | Typed glyph snapshots; generation+density identity, empty no-op, failure, consumer, frame-600/four-domain (`132892f`). Live SDL font adapters remain missing. |
| `image` position/scale | I/T | Typed surface snapshot and watched-generation identity (`132892f`). Live SDL adapter and failed-reload retention remain missing. |
| `image` angle/center/flip | I/T | Private lowering emits one pivoted affine transform around the image command; rotation, scale, explicit center and flip are exact through frame 600/four domains. Live legacy pixel comparison remains open. |
| `view3d` default/explicit viewport | I/T | Typed Scene3 lowering and private OGPU resource/state fixture (`e813369`, `d199322`); see R3 gaps. |
| `text_input_region` | R/U | Explicit `Unsupported Metadata`; no focused rejection fixture, and the Runtime/Wap metadata side channel remains missing. |
| `translate`, `rotate`, `scale` | I/T | Balanced transform stack/order; resource children retain transforms (`b9f9f28`, `132892f`). |
| `clip` | I/T | Balanced clip stack/order (`b9f9f28`); nested legacy pixel parity remains open. |
| `blend` Replace/Alpha/Add/Multiply | I/T | Copy/Source-over/Add/Multiply with scoped restoration (`b9f9f28`, `81fe03d`). |
| Public `Scene.render` selection | M | Still invokes the legacy boundary; private Raster2/OGPU renderers are side-by-side only. |

## R3 public Scene3 constructor/state audit after `d199322`

`Scene3.Private.drawings` supplies flattened immutable draws;
`scene3_raster2_lowering.ml` prepares Raster2 values; and the private OGPU
renderer caches resources and records supported state. **Partial** means public
fields are ignored or not integrated and therefore cannot count as parity.

| Public Scene3 surface | Status | Exact implementation / fixture evidence |
| --- | --- | --- |
| `empty`, `create`, draw ordering | I/T | Flattened order and colored/textured two-draw mock state order (`e813369`, `d199322`). No empty presented-frame golden. |
| `mesh` Faces; triangle list/strip/fan | I/T | Vertices/normals/UV/indices prepare draws; list framebuffer and authored-normal fixtures (`e813369`). Public strip/fan constructors now have exact stable-expansion, framebuffer, winding and one/four-domain goldens. |
| Public Faces/Wireframe/Vertices render modes | I/T | Faces retain the top-left triangle rule; Wireframe emits stable unique shared edges and Vertices emits stable unique projected points for triangle lists, strips and fans. Point sources render as points in all three modes; line list/strip/loop sources render lines for Faces/Wireframe and deduplicated endpoints for Vertices. Public line width/point size, homogeneous/scissor clipping, depth/stencil, cull and blend are exercised through frame 600 and four domains. No public `Mesh.mode` remains rejected. |
| Per-vertex mesh colors | R/U | Explicit `Invalid_mesh`, without a focused rejection fixture; material color is used instead. |
| `instances`, `instances_array` | I/U | Flattened per copied transform; geometry cache ignores transforms. No exact public 600-instance ordering fixture. |
| `group`, `transform`, `translate`, `rotate`, `scale`, `at_node` | I/T | Flattened matrices; camera-only frames 2–600 produce zero replacement upload bytes (`e813369`, `d199322`). Convenience-specific pixels remain open. |
| `box`, `plane`, `sphere`, `icosphere`, `cylinder`, `cone` | I/U | Convenience constructors produce ordinary Mesh values. No per-primitive lowering pixel matrix. |
| Material ambient/diffuse/specular/emissive/shininess | I/T | Copied into prepared lighting (`51128b0`, `e813369`). |
| Ambient/directional/point/spot lights | I/T | Raster2 carries validated spot concentration and applies the public cutoff/exponent rule exactly. Exponents 0/1/high, high cutoff, non-finite rejection, frame 600 and four-domain equality are direct fixtures. |
| Area lights | R/U | Explicit `Unsupported_area_light`; no focused lowerer fixture. |
| Scene ambient and separate specular | I/T | Immutable lighting preparation (`51128b0`, `e813369`). |
| Linear fog | I/T | Deterministic linear fog (`51128b0`, `e813369`). |
| Exponential fog modes | R/U | Explicit `Unsupported_fog`; no focused lowerer fixture. |
| Shadows Hard/PCF3/PCF5 | I/T | Typed prepared-shadow callback and exact PCF/bias/edge fixtures (`787e72c`, `2efa392`); live resource integration missing. |
| Texture filter | I/T | Nearest/bilinear callback plus textured portable resource (`e813369`, `d199322`). |
| Texture wrap U/V | M | Wrap values are not carried into `Raster2.Triangle.texture`. |
| Functional `Shader3` | R/T | Explicit `Unsupported_shader` (`e813369`, `d199322`). |
| Cull none/back/front | I/T | Raster2 mapping and ordered portable state (`e813369`, `d199322`). |
| Smooth/flat shading | I/T | Copied into consumer draws; Smooth authored-normal test direct. Dedicated Flat pixel golden missing. |
| Blend Replace/Alpha/Add/Multiply/Screen/Subtract | I/T | Complete Raster2 mapping; Alpha checked in ordered state (`e813369`, `d199322`). Per-mode pixels incomplete. |
| `depth_clear` | I/T | Scene3 consumer plus private OGPU draw state (`ba92d55`, `d199322`). |
| `with_depth` comparison/write | I/T | Every comparison and write flag maps to per-draw packed Depth_stencil state. Nested override/restore plus pass/fail behavior, frame 600 and four-domain snapshots are exercised. |
| `stencil_clear`, `with_stencil` | I/T | Clear value, comparison, reference/masks and all fail/depth-fail/pass operations map to packed Depth_stencil state; nested restoration and packed pass/fail fixtures are exact. |
| `with_raster` line width/point size | I/T | Nested raster scopes preserve and restore finite public widths/sizes. Wireframe/Vertices apply them in bounded depth/stencil-aware loops; Faces preserve winding/cull/scissor. |
| Samples 1/4/9/16 | Partial | Samples reach preparation and standalone MSAA is tested (`090ffae`), but private consumer/OGPU target integration does not apply every count. |
| Viewport/scissor | I/T | Default/explicit validation, matrix conversion and ordered state (`e813369`, `d199322`); nested Scene2 clips now intersect View3d viewport/scissor and are exercised through frame 600/four domains. |
| Private portable draw submission | I/T | Prepared 2D/Scene3 vertex and index bytes are written once, then submitted as exact Backend render bindings. Consecutive pass-compatible draws batch in order; only incompatible pass-level state splits. A 1,000-primitive fixture proves one render submission per frame, zero replacement uploads through frame 600, exact payload order/cardinality, bounded teardown, and one/four-domain equality. Runtime selection and real Metal pixel parity remain missing. |

The smallest local gaps are dedicated fixtures for already-mapped convenience
constructors. They do not repair the material missing semantics above.
Texture wrapping and sample integration require typed representation
changes and must not be marked complete by expectation-only tests.
