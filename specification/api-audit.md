# High-level API acceptance audit

This audit tracks the evidence required before calling Prismel's 2D sketch API
feature-complete. “Implemented” means a public signature, real implementation,
representative example or integration test, and headless verification exist.

Verdict: accepted for the initial desktop 2D sketch target. Every in-scope row
below has implementation evidence; optional/specialized exclusions are named
with rationale rather than represented by placeholder APIs.

## Productivity criteria

| Criterion | Status | Evidence / remaining work |
|---|---|---|
| First animated sketch in one short file | Implemented | `Sketch.run`, `examples/basic` |
| Functional immutable state | Implemented | `Sketch.run_state`, `Frame.t`, headless lifecycle test |
| Picture as composable data | Implemented | `Scene.t`, groups, transforms, scoped clip/blend |
| No raw SDL in normal sketch path | Implemented | `Sketch`, `Frame`, `Scene`, `Canvas`, `Assets`, `Audio` signatures |
| Deterministic generative tools | Implemented | `Rand`, `Noise`, color palettes, `examples/noise` |
| Safe multicore acceleration | Implemented | `Parallel`, initial-domain guards, `examples/particles` |
| One-command project scaffold | Implemented | `tools/new_example.exe`, scaffold smoke check |
| Reliable edit/compile/restart | Implemented workflow | `Preview`, watched media, `watchexec --restart`, explicit settings codecs |
| Headless graphics and audio | Implemented | dummy video/software renderer/dummy audio, integration tests |

## Drawing and composition

| Capability | Status | Evidence / remaining work |
|---|---|---|
| Basic 2D primitives | Implemented | point, lines, rectangles, circles, ellipses, triangles, quads, polygons |
| Curves and custom paths | Implemented | immutable multi-contour quadratic/cubic paths with even-odd/non-zero fills |
| Fill and stroke | Implemented | explicit per-node styles |
| Scoped transform, clip, blend | Implemented | translate/rotate/scale, intersecting clip, replace/alpha/add/multiply |
| Images | Implemented | load/cache, position, scale, rotation, center, horizontal flip |
| Text | Implemented | bitmap/debug text plus measured, wrapped, aligned loaded-font text with renderer-local texture cache |
| Offscreen rendering and pixels | Implemented | CPU `Canvas`, read/write/map pixels |
| Capture/export | Implemented | canvas/framebuffer PNG plus deterministic `Sketch.export[_state]`; repeated sequence digests tested |
| GPU offscreen targets | Optional optimization | CPU contract is complete; GPU target can be additive |
| Multi-contour tessellation | Implemented | transformed scanline fill, contour-safe strokes, pixel-level hole tests |
| General masks/compositing | Implemented initial | same-size canvas alpha masks plus scoped blend and rectangular clip |

## Interaction and time

| Capability | Status | Evidence / remaining work |
|---|---|---|
| Current and edge-triggered keyboard/mouse | Implemented | `Frame` snapshots plus ordered `Event.t list` |
| Resize, scroll, close | Implemented | event variants and frame dimensions |
| Timing, FPS, easing, scheduler | Implemented | `Frame`, `Time` |
| Touch and game controllers | Outside initial desktop target | avoid unverified device APIs without hardware-independent semantics/tests |
| Drag/drop and text composition | Implemented | committed UTF-8, IME composition, and owned SDL file-drop paths |
| Fixed timestep mode | Implemented | `Sketch.Fixed`, deterministic headless timing assertions |

## Media and assets

| Capability | Status | Evidence / remaining work |
|---|---|---|
| Image/font/sample/music cache | Implemented | `Assets`, deduplication tests |
| Automatic owned cleanup | Implemented | `Sketch.run_assets`, `on_stop` |
| Preload error aggregation | Implemented | typed requests and integration test |
| Sample/music playback | Implemented | SDL_mixer including headless test |
| No-file tone synthesis | Implemented | sine/square/saw/triangle `Audio.Sample.synth` |
| Parallel preload and hot asset reload | Implemented initial | concurrent image file preparation, main-domain decode/upload, stable-identity watched reload |
| Rich synthesis graph/audio input | Out of initial completeness target | should be a separate pure signal design |

## UI and workflow

| Capability | Status | Evidence / remaining work |
|---|---|---|
| Labels/buttons/toggles/sliders | Implemented initial | functional builders/update/scene, compatibility API, example and interaction test |
| Layout/theme/event values | Implemented initial | configurable vertical density, complete color theme, ordered named changes |
| Text input, dropdown, range/2D controls | Implemented | UTF-8/IME text, choice, dual-handle range, and 2D value controls |
| Parameter save/load | Implemented | pure encode/decode and file save/load with versioned typed format |
| Native hot reload preserving model | Outside initial target | arbitrary typed model/code migration is unsafe; explicit codecs plus REPL/watch/restart workflow documented |
| REPL scene iteration | Implemented | `dune utop lib/prismel`, persistent `Preview.show/step/stop`, headless lifecycle test |

## Low-level API debt

`App`, `Window`, `Graphics`, and `Backend` are private implementation modules
re-exported through the explicit `Low` compatibility namespace. `Image.t` is
abstract; renderer/texture hooks are isolated under `Image.Private`. Generated
API documentation builds through `dune build @doc`.

Remaining backend debt is implementation hardening rather than a missing sketch
capability: several legacy drawing calls still ignore SDL error returns, and
the compatibility namespace remains available for older programs.

## Scope decisions and hardening

Native arbitrary model migration is explicitly excluded from the initial 2D
target: OCaml closures, changed types, and SDL handles cannot be safely
marshalled across a relink. `Preview`, watched images, PXUI settings codecs, and
process restart cover the productive workflow without pretending otherwise.

Ignored error returns remain isolated to the legacy `Low` compatibility layer;
the high-level sketch contract uses contextual errors or controlled exceptions.
They are hardening work, not a missing high-level capability.
