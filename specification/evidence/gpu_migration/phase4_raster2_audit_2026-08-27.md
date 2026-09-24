# Phase 4 Raster2 audit — 2026-08-27

This audit compares the frozen R1–R12 gates in `NEW_GPU_STUFF.md` with the
current committed Raster2 work. It does not change the frozen plan and does not
count an isolated Raster2 unit fixture as Prismel, Runtime, web, or Metal
integration evidence.

## Gate matrix

| Gate | Implemented and directly exercised | Honest status and missing gate |
| --- | --- | --- |
| R1 Stable API | Private Scene lowering, selected-sketch adapters, resource execution and target orchestration preserve the public API and legacy selection (`4db9d2f`, `a500435`, `ac4e893` through `250cee2`). The reproducible `phase4_r1_freeze` gate pins the frozen-plan/API hashes, baseline ancestry, all eight unchanged acceptance source trees, absence of public migration toggles, and both comparison paths. | **Local freeze facts proven; final selection still partial.** Current-tree manifest and dependency-direction checks pass, but the atomic default switch has deliberately not happened. Rerun the same gate on the final clean selection commit. |
| R2 Scene2/PXUI parity | Pure constructors, affine state, clips/blends, Image/Text/Canvas execution, text-input regions and representative Basic/PXUI-like/Canvas application parity have direct frame 1/2/60/600 fixtures (`a500435`, `a6ea3b5`, `4df9972`, `e0a3340`). | **Partial.** Private runtime-next evidence is green; public/default Runtime still selects legacy. The full frozen native/headless/web application pixel corpus and actual PXUI acceptance executable remain final integration gates. |
| R3 Scene3 parity | Public topology/raster/depth/stencil/sampling/fog/lighting/material/normal/convenience coverage is joined by area lights, per-vertex colors and functional deterministic Shader3 execution (`6e07cd3`, `34facc3`, `4bef806`, `38dc4c9`, `8648d38`). | **Partial.** Functional software Shader3 is no longer a gap. Default selection, frozen native Metal tolerance images, all required MSAA target combinations, live shadow ownership and production Boolean-terminal native upload evidence remain. |
| R4 Resource parity | Runtime-next now executes owned watched Image and density-keyed Text snapshots, offscreen Canvas dependency ordering, Assets borrowing, and SDL3_mixer/dummy Audio lifecycle through on-stop (`ac4e893`, `4df9972`, `e0a3340`, `250cee2`). | **Partial.** Focused lifecycle evidence is real, not snapshot-only. Final selected examples, native extension availability matrix, packaging and cross-target teardown qualification remain. |
| R5 Target parity | A genuine software OGPU backend exists (`390bc92`, `5cee752`); SDL-free headless and web compositions and typed native/headless/web orchestration are committed (`29e1601`, `816e253`, `8916de3`). | **Partial integration.** All three private targets exist, but public/default Runtime is unswitched. Real-M1 native smoke can capability-skip and final web connection/input/audio acceptance is not a release matrix result. |
| R6 Coordinate/DPI parity | Runtime-next input facts/adapters cover logical/drawable sizes, Retina mapping, authoritative resize, clips/scissors and density rerasterization (`8128695`, `1f14e7b`, `a6ea3b5`). | **Partial.** Exact private fixtures are green; final selected native drawable query/capture and real browser/mobile text-focus runs remain external. |
| R7 Deterministic pixels | Raster2 exact one/four-domain fixtures now extend through selected headless/web compositions, resources, application parity and programmable software draws. | **Partial.** Software exactness is broad. Phase-0 native tolerance goldens still require recorded Metal qualification; no tolerance is silently changed. |
| R8 Multi-frame correctness | Representative apps, target compositions, resources, topology/state/sampling/programs and resize/reload paths exercise frames 1/2/60/600 with bounded cleanup. | **Partial.** The private finite matrix is green; the complete unchanged example/sketch matrix on selected native/headless/web remains a final external gate. |
| R9 Upload/batching structure | Stable preparation and compatible batching are measured by the release harness in `62447a5`: all warmed cases have zero replacement upload; the exact shattered graph records 18,278 draws in one pass/backend call per frame. | **Partial.** These are real portable boundary counters, but the shattered lane uses `Backend_mock` and ordinary lanes use `ogpu-raster2`; native Metal upload/encoder/FFI evidence remains external. |
| R10 Performance non-regression | `62447a5` records release median/p95/FPS/CPU/allocation/RSS and structural counters for Basic, PXUI-like, Canvas, Scene3, hidden scheduling and shattered preparation on the M1. | **Not passed.** Legacy SDL2 could not initialize under the local dummy-video environment, so there is no interleaved same-protocol comparison, five warmed 30-second samples, native GPU timing, or independent native/headless/web R10 result. |
| R11 Shattered-cube performance | The prepared OGPU batching harness pins 18,278 pieces/278,368 triangles, prepares 4,217,760 bytes once and measures zero replacement upload, 18,278 draws/one pass/one backend call per frame (`62447a5`). | **Partial structural evidence only.** It is a synthetic prepared graph on `Backend_mock`, not `sketches/shattered_cube/main.exe`; 835,104 render vertices, cook invariants and visible/hidden native Metal timing/residency remain required. |
| R12 Long-run stability | The fixed-ring release harness covers changing meshes, resize, reload, Canvas/offscreen ownership and bounded Wap state. The final 30-minute M1 run passed in `51cc55d`: 23,464,561 rendered/presented frames, deterministic hash `ef98c79010144e39`, final-window RSS 15,744–16,016 KiB (1.73%), bounded live maxima 1/0/1 and target/view teardown 0/0. | **Partial; one qualification lane passed.** The SDL-free combined Raster2/Wap lane is now genuine 30-minute evidence. Separate selected native, headless and web 30-minute lanes including SDL/audio ownership are still required by frozen R12. |

## R1 reproducible freeze evidence

`tools/gpu_migration/phase4_r1_freeze.ml` verifies the local facts directly
from Git and committed evidence rather than relying on a prose assertion:

- `NEW_GPU_STUFF.md` remains byte-identical at SHA-256
  `75cb47632aa2b26199677560c6382b8b94786af5f704867b40d306ccefbe19d3`;
- Phase-0 commit `4622091a65bc9a8816a1f10bcc83c1a625ca7522` is the exact
  merge-base ancestor;
- `examples/basic`, `particles`, `noise`, `canvas`, `audio`, `pxui`,
  `generative`, and `sketches/shattered_cube` have no changed source path
  relative to that baseline;
- the checked stable API manifest is byte-pinned at SHA-256
  `ca6861c5dfbfafd6ea64d1c9837bc218e2af0dfe83a5b9589183384ffefcb7e2`,
  and its generator check passes;
- public Prismel/Runtime interfaces expose none of the private migration-toggle
  spellings checked by the gate; and
- legacy `Sketch` still selects `Scene.render`, while private
  `Scene_raster2_lowering` and `Scene_ogpu_renderer` remain registered for
  side-by-side qualification rather than default selection.

The focused commands passed on 2026-08-27:

```text
opam exec -- dune build --force tools/gpu_migration/phase4_r1_freeze.exe
_build/default/tools/gpu_migration/phase4_r1_freeze.exe --root .
opam exec -- dune exec tools/gpu_migration/api_manifest.exe -- --root . --check
_build/default/test/gpu_dependency_direction.exe lib/prismel/dune lib/runtime/dune \
  lib/wap/dune lib/sdl3/dune lib/sdl3_image/dune lib/sdl3_ttf/dune \
  lib/sdl3_mixer/dune lib/metal/dune lib/ogpu/dune lib/ogpu_metal/dune \
  lib/raster2/dune
```

These facts close the locally reproducible freeze portion only. They do not
authorize the default switch or change any R3/R12 qualification status.

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
- `62447a5` release-built the prepared benchmark and ran exact cardinality/
  batching probes. Its committed JSON and Markdown record the protocol and the
  failed local legacy-SDL2 initialization honestly; they make no native GPU or
  same-run performance claim.
- The exact release stability command in `raster2_long_run_stability.md` ran
  from `2026-08-27T13:02:24Z` to `13:32:25Z` and passed (`51cc55d`). It retained
  256 of 1,781 observations, presented all 23,464,561 frames, held the final
  RSS window to 1.73%, and tore live targets/views down to zero. Two precursor
  failures are preserved and explicitly rejected in that evidence rather than
  averaged into the passing run.

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

## Software `ogpu_raster2` backend status

The earlier read-only draft is obsolete. `390bc92`, `5cee752`, and follow-up
sampler/mip commits implement and test a genuine software `Ogpu.Backend` with
owned resources, transfers, texture sampling and actual Raster2 draw execution.
It now contributes to private headless/web R5/R7 evidence. Remaining release
requirements are:

- own deterministic device/queue/surface/buffer/texture/pipeline/frame state,
  enforce stale and cross-device validation, preserve acquire/configure/
  present/device-loss semantics, and release every partial allocation;
- preserve exact frames 1/2/60/600 plus resize, independent one/four-domain runs,
  device loss, pitch/padding, clipping outside the scissor, overlapping ordered
  draws, and 100,000 create/destroy cycles with flat live counts and bounded
  metadata as the selected integration evolves;
- complete production programmable-pipeline parity and native/software shared
  conformance without substituting fixed colors or label-derived behavior;
- qualify final selected headless/web application and long-run lanes. Unit and
  private integration success does not authorize legacy deletion.

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
| `text`, `debug_text`, `font_text` | I/T | Typed glyph snapshots plus runtime-next density-keyed live execution, empty no-op, failed rerasterization retention and frame-600/four-domain coverage (`132892f`, `e0a3340`). Final selected example parity remains external. |
| `image` position/scale | I/T | Typed surface snapshot plus runtime-next watched-generation execution and failed-reload retention (`132892f`, `e0a3340`). |
| `image` angle/center/flip | I/T | Private lowering emits one pivoted affine transform around the image command; rotation, scale, explicit center and flip are exact through frame 600/four domains. Live legacy pixel comparison remains open. |
| `view3d` default/explicit viewport | I/T | Typed Scene3 lowering and private OGPU resource/state fixture (`e813369`, `d199322`); see R3 gaps. |
| `text_input_region` | I/T | Private lowering carries ordered transformed logical regions into the neutral runtime-next boundary; Wap retains wire ownership. Nested/order/Retina/focus fixtures cover frames 1/2/60/600 (`a6ea3b5`). |
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
| Per-vertex mesh colors | I/T | Public colors lower into packed vertices and modulate material/texture lighting with exact interpolation and frame/domain fixtures (`6e07cd3`). |
| `instances`, `instances_array` | I/T | Public list/array constructors flatten in stable identical transform order, preserve six exact draws, and retain geometry/material state. Prepared values are exact through frame 600 and one/four domains; convenience meshes have separate framebuffer checks. |
| `group`, `transform`, `translate`, `rotate`, `scale`, `at_node` | I/T | Flattened matrices; camera-only frames 2–600 produce zero replacement upload bytes (`e813369`, `d199322`). Convenience-specific pixels remain open. |
| `box`, `plane`, `sphere`, `icosphere`, `cylinder`, `cone` | I/T | One public table checks each against its canonical Mesh vertex/index cardinality, topology, material/raster state and a non-empty deterministic framebuffer. Every constructor has its own exact prepared hash through frame 600 and one/four domains. |
| Material ambient/diffuse/specular/emissive/shininess | I/T | Copied into prepared lighting (`51128b0`, `e813369`). |
| Ambient/directional/point/spot lights | I/T | Raster2 carries validated spot concentration and applies the public cutoff/exponent rule exactly. Exponents 0/1/high, high cutoff, non-finite rejection, frame 600 and four-domain equality are direct fixtures. |
| Area lights | I/T | Public area lights lower to deterministic sampled contributions with validation and exact frame/domain coverage (`34facc3`). |
| Scene ambient and separate specular | I/T | Immutable lighting preparation (`51128b0`, `e813369`). |
| Linear fog | I/T | Deterministic linear fog (`51128b0`, `e813369`). |
| Exponential fog modes | I/T | Public exponential and exponential-squared density map directly to validated Raster2 fog. Exact zero-density, asymptotic color, exponent-policy, non-finite/negative rejection, frame-600 and one/four-domain fixtures are present. |
| Shadows Hard/PCF3/PCF5 | I/T | Typed prepared-shadow callback and exact PCF/bias/edge fixtures (`787e72c`, `2efa392`); live resource integration missing. |
| Texture filter | I/T | Public nearest, bilinear and trilinear state maps to the retained Raster2 texture. Triangle derivatives choose deterministic mip LOD; odd-size mip levels, out-of-range UVs, frame 600 and one/four-domain output are exact. |
| Texture wrap U/V | I/T | Public clamp, repeat and mirror map independently for U/V without replacing the resolved texture identity. Exact outside-range UV fixtures cover every address mode through the triangle consumer. |
| Functional `Shader3` | I/T | Validated deterministic vertex/fragment programs execute for triangles, points and lines; exact program, state and frame/domain fixtures are committed through `4bef806`, `38dc4c9`, and `8648d38`. Native offline Metal shader provenance remains external. |
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

The previously listed local gaps for per-vertex colors, area lights, text-input
metadata and functional software Shader3 are closed. The material remaining
gates are selected/default integration and external native/release evidence;
closing local constructor rows does not repair those gates.
The public Scene3 sampling surface is fully represented. Explicit user-selected
LOD and anisotropic filtering are not public `Scene3.texture` controls and are
therefore not parity gaps; mip LOD is derived deterministically from triangle
UV screen gradients.
