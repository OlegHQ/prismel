# Phase 4 Raster2 audit — 2026-08-27

This audit compares the frozen R1–R12 gates in `NEW_GPU_STUFF.md` with the
current committed Raster2 work. It does not change the frozen plan and does not
count an isolated Raster2 unit fixture as Prismel, Runtime, web, or Metal
integration evidence.

## Gate matrix

| Gate | Implemented and directly exercised | Honest status and missing gate |
| --- | --- | --- |
| R1 Stable API | Private lowering and snapshot work through `434cf02` preserve the public `Scene`/`Scene3` interfaces and leave the legacy renderer and examples selectable. `scene_execution` is a separate neutral boundary (`36e0080`, `6827998`). | **Partial.** The atomic selected-renderer migration has not happened. A current clean-tree API-manifest run and the SDL major-version review are still required before selection changes. |
| R2 Scene2/PXUI parity | Surfaces, compositing, paths, primitives, sampling, shared IR/consumer and private lowering cover pure Scene2 state, resources and convenience constructors through frame 600/four domains. Prepared Prismel draws now feed neutral `scene_execution`, and that boundary has both mock and Metal consumers (`36e0080`, `2a29193`, `6827998`). | **Partial.** PXUI and the selected Runtime path still use the legacy renderer. Frozen legacy-vs-Raster2 pixels for every rounded/curve/pie/text/widget fixture remain open; a neutral draw path is not itself full Scene parity. |
| R3 Scene3 parity | Every public point/line/triangle topology and Faces/Wireframe/Vertices mode (`29bb987`, `423fe22`, `663fa4c`), depth/stencil (`1e128a3`), sampling (`4946843`), fog (`a250fc4`), Smooth/Flat authored normals (`b3975f3`) and convenience/instance constructors (`434cf02`) have direct exact fixtures. Portable draws execute through neutral `scene_execution`. | **Partial.** Selected-renderer parity, functional `Shader3`, all-sample-count integration, live owned texture/shadow adapters, frozen native Metal pixels, and terminal Boolean-normal upload evidence remain open. |
| R4 Resource parity | Bounded cache/atlas/mips/offscreen/readback are joined by retained CPU Image (`671a412`), Font (`da05475`), Canvas (`0ac1361`) and Audio (`926ced7`) snapshots. Private callbacks retain generation/density identity, reject atomically and run through real Raster2 consumers. | **Partial.** Production Assets/watched-failure/on-stop integration and selected Runtime ownership ordering remain open. Snapshot availability is not evidence that the legacy resource lifecycle has switched. |
| R5 Target parity | Raster2 remains platform-independent; an SDL-free bounded Wap framebuffer presenter exists (`bd34262`), neutral scene execution reaches Metal (`2a29193`), and opt-in `runtime_next` now composes SDL3 Metal-view ownership with `ogpu_metal` (`6623507`). | **Partial integration.** Runtime still selects the legacy renderer. `runtime_next` is an opt-in composition fixture, may skip without a device, and there is no committed genuine software OGPU backend joining headless/web to the same execution path. |
| R6 Coordinate/DPI parity | Packed pitch, clipping, nested View3d scissor, transforms, readback orientation, and separate logical/drawable Wap presenter dimensions have exact fixtures. `runtime_next` carries logical/physical surface fields and exercises resize. | **Partial.** Runtime-next currently initializes logical and physical sizes from the same requested dimensions; authoritative Retina drawable querying, pointer mapping, font-density rerasterization, selected browser mapping and native capture parity remain open. |
| R7 Deterministic pixels | Raster2 modules compare exact bytes across independently owned one/four-domain work. Wap presentation proves pitch-safe exact packing; runtime-next conditionally checks exact readback bytes on real Metal. | **Partial.** Phase-0 frozen PNG/tolerance fixtures are not driven through every target. The Metal fixture can skip without hardware and is not a recorded native exact/tolerance qualification run. No tolerance has changed. |
| R8 Multi-frame correctness | Topology/state/sampling/fog/shading/convenience fixtures reach frame 600/four domains. Neutral execution covers 1,000 stable frames; Wap covers frames 1/2/60/600 plus resize-like extent change; runtime-next conditionally covers frames 1/2/60/600 and resize. | **Partial.** The complete frozen application matrix, selected native/headless/web paths, post-resize resources, reload, Canvas and audio must all cover the required checkpoints. Module and conditional fixtures do not substitute for it. |
| R9 Upload/batching structure | Prepared mesh caching is connected to Prismel's neutral `scene_execution`; its 1,000-frame fixture holds upload bytes at the first 60-byte upload and drains live objects. Compatible Prismel draws batch (`a654322`), and Metal batches portable draws (`68a6db0`). | **Partial.** Frozen real-scene native upload/FFI/pass counters, especially PXUI and shattered-cube scale, have not been recorded. Mock counters and code structure are not native performance evidence. |
| R10 Performance non-regression | Hot loops use packed bytes/fixed loops and bounded containers; deterministic scale tests exist. | **Missing external gate.** No Phase-0 M1 release median/p95 comparison for Basic, PXUI, Canvas, Scene3, hidden/visible UI, headless, or web has been recorded. Functional tests are not performance evidence. |
| R11 Shattered-cube performance | The prepared-mesh cache supplies the intended stable identity/version/layout and upload-intent counters. | **Missing external gate.** The 18,278-piece/278,368-triangle sketch has not run through Raster2/OGPU/Metal; residency, draw count, timing, RSS, allocation, and frame pacing are unmeasured. |
| R12 Long-run stability | Individual caches/arenas/rings are bounded. The deterministic stability harness (`1b32cf9`, `7285bc5`) combines changing scene uploads, resize, image-generation invalidation, transient offscreen ownership and bounded Wap presentation, sampling RSS/heap/cache/live counters into JSON. | **Partial; external gate missing.** The short deterministic harness is evidence. The documented 30-minute release command has not run, and native/headless/web resize/reload/Canvas/audio final RSS, live-handle and queue plateaus remain unrecorded. |

## Commands run for this audit

- At `132892f`, `lib/prismel/prismel.cma`, the focused private resource-lowering
  executable, and the full Raster2 suite were green.
- The dependency-direction executable passed with all 14 supplied libraries,
  including `lib/raster2/dune`, and rejected its injected reverse edge.
- The resource fixture covered callback cardinality, watched generation and
  density identity, empty-text no-op, atomic failure, real Consumer execution,
  frame 600, and independently owned four-domain equality.
- At `29bb987` and `4946843`, the focused public Scene3 lowering, Scene3
  consumer, texture sampling, `prismel.cma`, full Raster2 suite and dependency
  targets were green. The topology fixtures cover every public `Mesh.mode`;
  the texture fixtures cover every public filter and independent U/V wrap.
- `a250fc4`, `b3975f3`, and `434cf02` add direct exponential-fog,
  shared-vertex Smooth/Flat, public convenience-constructor and instance
  fixtures through frame 600/four domains; focused lowering, `prismel.cma`,
  full Raster2 and dependency targets were green at those checkpoints.
- Neutral `scene_execution` has a 1,000-frame stable-upload/live-delta fixture;
  the Wap presenter has exact pitched packing, frames 1/2/60/600, 100,000
  duplicate submissions and bounded suppression; runtime-next has a conditional
  real-Metal frames/resize/readback/live-handle fixture.
- The deterministic stability smoke and its bounded-diagnostics fix are
  committed. The documented 30-minute release command was not run. A current
  clean-tree API-manifest result was also not recorded in this audit, so neither
  is counted as passed.

## Implemented private comparison pivot

The boundary proposed by the original audit now exists. `Scene_description` is
private; public `Scene.node`/`Scene.t` remain abstract; the legacy renderer stays
selectable; and `Scene_raster2_lowering` returns shared IR plus typed resource
snapshots (`b9f9f28` through `132892f`). Pure Scene2 and representable View3d,
Image, and Text paths lower without raw native pointers. Unsupported SDL-only
resources reject explicitly rather than being skipped; representable image
affine transforms now lower directly.

The private renderer pivot now feeds prepared Scene2/Scene3 draws into neutral
`scene_execution`; mock and Metal implementations share that boundary, and
runtime-next demonstrates the intended SDL3 Metal-view composition. This is
still side-by-side evidence, not authorization to switch `Scene.render`.
Frozen legacy/Raster2 comparisons, selected Runtime target fixtures, resource
lifecycle tests and the remaining R1-R12 external gates must pass before an
atomic selection change. No public `.mli`, example, or legacy-render path
should be removed during qualification.

## Read-only review of the proposed `ogpu_raster2` backend

The current untracked directory contains a Dune declaration, interface and
test, but no `ogpu_raster2.ml`; it is therefore a design draft, not implemented
evidence and is not counted in any gate above. A genuine software
`Ogpu.Backend` must meet these minimum requirements:

- own deterministic device/queue/surface/buffer/texture/pipeline/frame state,
  enforce stale and cross-device validation, preserve acquire/configure/
  present/device-loss semantics, and release every partial allocation;
- implement exact buffer and pitched texture writes/reads, render attachment
  load/store, draw order, vertex/index offsets and index types, viewport,
  scissor, resize and actual presented/readback pixels;
- rasterize the submitted geometry through Raster2. Filling a scissor rectangle
  with a fixed color, keying behavior on a label/pipeline hash, or returning a
  canned readback is not a backend implementation;
- define a typed backend-neutral software pipeline/vertex contract. The draft
  test supplies zeroed, degenerate vertex bytes yet expects `0x4080BFFF`, while
  portable shader artifacts contain provenance bytes rather than executable
  software shader semantics. The fixture must instead encode non-degenerate
  vertices and obtain color from an explicit portable software pipeline or
  shared Render IR contract;
- prove exact frames 1/2/60/600 plus resize, independent one/four-domain runs,
  device loss, pitch/padding, clipping outside the scissor, overlapping ordered
  draws, and 100,000 create/destroy cycles with flat live counts and bounded
  metadata.

Until those conditions are implemented and the test observes real rasterized
geometry, `ogpu_raster2` cannot close headless/web target parity or contribute
R7/R9/R12 evidence.

## R2 public Scene constructor audit after `4946843`

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
| `square` | I/T | The public value is compared directly with canonical `Rect` and remains byte-stable through frame 600/one-four domains; canonical Rect lowering/consumer pixels are covered separately. |
| `rounded_rect` | I/T | Rounded Path tessellation is directly included in the constructor fixture (`59ae442`). |
| `circle`, `ellipse` | I/T | Deterministic sampled closed Paths, fill/stroke exercised (`59ae442`). |
| `triangle` | I/T | Path triangle plus OGPU stable prepared-mesh/upload fixture (`b9f9f28`, `40bad9a`). |
| `quad` | I/T | The public value is compared directly with canonical `Polygon` and remains byte-stable through frame 600/one-four domains; canonical polygon lowering/consumer pixels are covered separately. |
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

## R3 public Scene3 constructor/state audit after `4946843`

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
| `instances`, `instances_array` | I/T | Public list/array constructors flatten in stable identical transform order, preserve six exact draws, and retain geometry/material state. Prepared values are exact through frame 600 and one/four domains; convenience meshes have separate framebuffer checks. |
| `group`, `transform`, `translate`, `rotate`, `scale`, `at_node` | I/T | Flattened matrices; camera-only frames 2–600 produce zero replacement upload bytes (`e813369`, `d199322`). Convenience-specific pixels remain open. |
| `box`, `plane`, `sphere`, `icosphere`, `cylinder`, `cone` | I/T | One public table checks each against its canonical Mesh vertex/index cardinality, topology, material/raster state and a non-empty deterministic framebuffer. Every constructor has its own exact prepared hash through frame 600 and one/four domains. |
| Material ambient/diffuse/specular/emissive/shininess | I/T | Copied into prepared lighting (`51128b0`, `e813369`). |
| Ambient/directional/point/spot lights | I/T | Raster2 carries validated spot concentration and applies the public cutoff/exponent rule exactly. Exponents 0/1/high, high cutoff, non-finite rejection, frame 600 and four-domain equality are direct fixtures. |
| Area lights | R/U | Explicit `Unsupported_area_light`; no focused lowerer fixture. |
| Scene ambient and separate specular | I/T | Immutable lighting preparation (`51128b0`, `e813369`). |
| Linear fog | I/T | Deterministic linear fog (`51128b0`, `e813369`). |
| Exponential fog modes | I/T | Public exponential and exponential-squared density map directly to validated Raster2 fog. Exact zero-density, asymptotic color, exponent-policy, non-finite/negative rejection, frame-600 and one/four-domain fixtures are present. |
| Shadows Hard/PCF3/PCF5 | I/T | Typed prepared-shadow callback and exact PCF/bias/edge fixtures (`787e72c`, `2efa392`); live resource integration missing. |
| Texture filter | I/T | Public nearest, bilinear and trilinear state maps to the retained Raster2 texture. Triangle derivatives choose deterministic mip LOD; odd-size mip levels, out-of-range UVs, frame 600 and one/four-domain output are exact. |
| Texture wrap U/V | I/T | Public clamp, repeat and mirror map independently for U/V without replacing the resolved texture identity. Exact outside-range UV fixtures cover every address mode through the triangle consumer. |
| Functional `Shader3` | R/T | Explicit `Unsupported_shader` (`e813369`, `d199322`). |
| Cull none/back/front | I/T | Raster2 mapping and ordered portable state (`e813369`, `d199322`). |
| Smooth/flat shading | I/T | Public modes lower end to end. Flat performs stable per-triangle expansion so shared vertices retain distinct geometric face normals; Smooth preserves authored per-vertex normals, including orientation-reversed Boolean-style terminal normals. Bent shared-vertex pixel goldens distinguish both modes through frame 600 and one/four domains. |
| Blend Replace/Alpha/Add/Multiply/Screen/Subtract | I/T | Complete Raster2 mapping; Alpha checked in ordered state (`e813369`, `d199322`). Per-mode pixels incomplete. |
| `depth_clear` | I/T | Scene3 consumer plus private OGPU draw state (`ba92d55`, `d199322`). |
| `with_depth` comparison/write | I/T | Every comparison and write flag maps to per-draw packed Depth_stencil state. Nested override/restore plus pass/fail behavior, frame 600 and four-domain snapshots are exercised. |
| `stencil_clear`, `with_stencil` | I/T | Clear value, comparison, reference/masks and all fail/depth-fail/pass operations map to packed Depth_stencil state; nested restoration and packed pass/fail fixtures are exact. |
| `with_raster` line width/point size | I/T | Nested raster scopes preserve and restore finite public widths/sizes. Wireframe/Vertices apply them in bounded depth/stencil-aware loops; Faces preserve winding/cull/scissor. |
| Samples 1/4/9/16 | Partial | Samples reach preparation and standalone MSAA is tested (`090ffae`), but private consumer/OGPU target integration does not apply every count. |
| Viewport/scissor | I/T | Default/explicit validation, matrix conversion and ordered state (`e813369`, `d199322`); nested Scene2 clips now intersect View3d viewport/scissor and are exercised through frame 600/four domains. |
| Private portable draw submission | I/T | Prepared 2D/Scene3 vertex and index bytes are written once, then submitted as exact Backend render bindings. Consecutive pass-compatible draws batch in order; only incompatible pass-level state splits. A 1,000-primitive fixture proves one render submission per frame, zero replacement uploads through frame 600, exact payload order/cardinality, bounded teardown, and one/four-domain equality. Runtime selection and real Metal pixel parity remain missing. |

The remaining local gaps are per-vertex color policy and focused rejection
tests for area lights/metadata. They do not repair the material external gates
above.
The public Scene3 sampling surface is fully represented. Explicit user-selected
LOD and anisotropic filtering are not public `Scene3.texture` controls and are
therefore not parity gaps; mip LOD is derived deterministically from triangle
UV screen gradients.
