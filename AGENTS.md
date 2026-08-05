# Prismel repository guide

## Purpose

Prismel is an OCaml creative-coding framework. Keep its public API small,
functional where practical, and suitable for both interactive desktop programs
and deterministic headless execution.

## Repository layout

- `lib/prismel/` is the main `prismel` library.
- `lib/runtime/` owns target selection, SDL lifecycle, and frame presentation.
- `lib/wap/` is the standalone browser transport imported by `runtime`; it
  must not depend on `runtime` or `prismel`.
- `lib/<name>/` contains sibling libraries. A sibling library may depend on
  `prismel`; `prismel` must never depend on a sibling library.
- `lib/pxui/` is the UI toolkit inspired by ofxUI.
- `lib/pdk/` is the single packed geometry/topology compute core.
- `lib/geom/` is the ergonomic functional geometry API and adapter layer; it
  consumes `pdk` for mesh generation and modeling algorithms rather than
  maintaining competing kernels.
- `lib/procedural/` owns immutable SOP graphs and consumes `pdk` operations.
- `examples/<project>/` contains self-contained example executables. Give every
  example its own `dune` file and keep shared framework code out of examples.
- `sketches/<project>/` contains experimental creative-coding executables.
  Give every sketch its own `dune` file, keep experiments out of the public
  library surface, and prefer `Sketch`, `Scene`, and immutable SOP graphs.
  Sketches must remain finite under the headless render target.
- `test/` contains automated tests, including headless integration tests.
- `specification/` contains design notes. Update it when behavior or architecture
  changes materially.
- `tsdl_gfx/` is the low-level SDL2_gfx binding and is not part of the high-level
  API.

## Dependency direction

```text
examples ──> pxui ──> prismel ──> runtime ──> wap
    └────────────────> prismel        │
                         │             └──> tsdl
                         └──> tsdl/tsdl_gfx
```

Never introduce a dependency from `prismel` to `pxui` or to an example.

Geometry libraries follow this additional direction:

```text
procedural ──> geom ──> pdk ──> prismel
     └────────────────> pdk
```

`procedural` may use `geom` for ergonomic curves, polygons, fields, and
representation-neutral preparation, or call `pdk` directly for packed SOPs.
`geom` must never depend on `procedural`; `pdk` must never depend on either.

## Procedural geometry scope

- Target a complete production toolset for procedural geometry modeling:
  mesh and curve construction, topology editing, attributes and groups,
  selections, spatial queries, subdivision, booleans, repair, remeshing,
  reduction, instancing, and deterministic import/export.
- Existing UV projection/flatten/relax utilities remain supported, but UV
  feature-parity expansion is not a modeling priority until requested again.
- Rigging/KineFX, crowds, fluids, pyro, Vellum, MPM, dynamics solvers,
  compositing, terrain/heightfield systems, USD pipelines, and general VFX
  simulation are explicitly out of scope until requested separately.
- Houdini parity claims apply only to the in-scope polygon/curve modeling
  surface. Keep an honest per-node parity matrix; never imply parity with the
  full Houdini product.

## Single geometry core

- `pdk` is the only owner of packed mesh topology, reverse incidence,
  half-edge/edge indexing, spatial acceleration, attribute interpolation and
  promotion, and high-density modeling algorithms.
- `geom` owns user-facing mathematical values such as points, bounds, curves,
  polygons, rays, fields, and friendly functional APIs. For mesh generation or
  topology mutation, it prepares inputs for `pdk`, invokes the shared kernel,
  and converts the result through an explicit adapter.
- `procedural` wraps the same `pdk` operations as immutable SOP nodes. It may
  compose `geom` operations for high-level input preparation, but must not
  reimplement packed geometry algorithms inside graph cooks.
- Do not fix duplication by making `pdk` import `geom`. Move or independently
  implement the representation-neutral algorithm in `pdk`, then adapt the
  existing `geom` entry point to it while preserving the public API.
- Migrate incrementally by operation. Every migrated Geom operation needs a
  compatibility regression comparing its public result before/after where a
  stable result was documented, plus direct PDK correctness, malformed-input,
  cancellation, cardinality, and one-domain/multi-domain exactness tests.
- Retire the old Geom kernel after its adapter is proven; do not leave two
  authoritative implementations behind a permanent fallback.
- Shared topology structures must be packed integer arrays/bytes with explicit
  ownership and O(points + vertices + primitives + edges) storage. Public
  immutable wrappers may expose safe queries; audited kernels may borrow
  read-only planes through a narrow `Private` view.
- Robust operations separate combinatorial decisions from approximate metric
  calculations. Use adaptive/exact predicates for orientation, incircle, and
  intersection signs where floating-point ambiguity can change topology;
  tolerances remain explicit policy, not a substitute for robust predicates.
- External native geometry libraries require an explicit dependency, license,
  portability, determinism, and headless-build review. Prefer a small audited
  native OCaml kernel for core operations; reuse a mature library only when it
  materially improves robustness and the boundary preserves PDK ownership.
- Production mesh Booleans use an exact surface-arrangement/Weiler pipeline,
  not BSP polygon clipping, centroid classification, voxel/SDF resampling, or
  a tolerance-welded triangle soup. Preserve symbolic/implicit intersection
  constructions until output materialization; all predicates involving those
  points must be filtered exact or exact.
- The Boolean kernel is staged and reusable: deterministic broad phase, exact
  intersection classification, implicit seam construction, per-face
  constrained Delaunay refinement, coincident-facet handling, radial ordering,
  patch/cell classification, Boolean-expression extraction, ancestry-aware
  payload transfer, one-time rounding, and bounded seam cleanup/verification.
  Detection and floating intersection-analysis nodes are diagnostics only and
  must never be silently reused for topology-changing decisions.
- Boolean product scope includes variadic expressions, union/intersection/
  subtraction/XOR, seam, shatter, solid/surface treatment, self-intersection
  resolution, coplanar overlap, non-manifold arrangement edges, and stable
  source ancestry. Expose a public SOP only as each advertised mode reaches
  exact one-domain/multi-domain parity, adversarial degeneracy coverage, and a
  measured scale baseline.

## Iterative procedural sketches

- Support real-time creative feedback by letting `Sketch.run_state` own the
  previous immutable PDK geometry and cook the next snapshot each application
  step. This is an iterative sketch facility, not authorization to add a
  general dynamics/VFX solver framework.
- Keep each per-step procedural graph acyclic. Feedback crosses the frame
  boundary explicitly through the sketch model and `Sop.snapshot`; never hide
  mutable feedback or global geometry state inside a SOP node or session cache.
- Custom procedural nodes may compose public SOP/Geom operations or implement a
  typed PDK kernel. Composed nodes retain inspectable subgraphs when useful;
  fused native nodes must declare stable parameter identity, context
  dependencies, input ownership, cancellation behavior, and complexity.
- Retain only current/next snapshots by default, structurally share unchanged
  PDK components, and keep cook/mesh caches bounded. History, trails, and
  checkpoints require explicit capacities and must not grow with frame count.
- Keep render-only packed instances as a terminal prototype-plus-transform
  value outside `Pdk.Geometry.t`. Do not invent fake editable packed primitives;
  use an explicit materialization boundary before feeding per-copy topology
  back into a solver step.
- Iterative sketches expose reset and optional checkpoint hooks. Repeatable
  runs use `Sketch.Fixed dt`, explicit immutable seeds, stable input streams,
  and exact one-domain/multi-domain state and framebuffer regressions.

## Library ownership boundaries

- `prismel` owns target-independent application semantics: `Sketch`, immutable
  `Frame` facts, pure `Scene` data, public `Event`/`Input`, resource APIs, and
  renderer behavior. It may call the narrow `runtime` lifecycle/presentation
  boundary, but it must not implement HTTP, WebSocket, DOM, or browser policy.
- `runtime` owns render-target selection, SDL subsystem lifetime, environment
  setup/restoration, presentation scheduling, and typed translation between
  Prismel-facing facts and Wap-facing transport. It must not own widgets,
  scene constructors, application models, or browser JavaScript.
- `wap` owns only bounded browser transport: HTTP/WebSocket protocol, client
  HTML/JavaScript, framebuffer delivery, browser input encoding, authenticated
  assets, and connection/thread lifetime. It must remain usable without
  importing `runtime`, `prismel`, `pxui`, SDL, or application modules.
- Sibling libraries such as `pxui` depend only on public `prismel` semantics.
  PXUI represents browser text-entry intent as pure `Scene` metadata; it must
  never call Runtime/Wap or inspect render-target environment variables.
- Cross-library communication uses narrow typed functions. Do not pass raw Wap
  protocol strings into PXUI or public sketch code, expose browser internals in
  `Scene`, or move target-neutral behavior downward merely for convenience.
- Browser command variants and JSON/wire encoding belong exclusively to Wap.
  Runtime may translate typed target facts, and Prismel may emit typed audio or
  input-region intent, but neither may construct browser protocol strings.
- A boundary change must include a Dune dependency-direction check, focused
  tests at each affected boundary, and an update to `specification/backend.md`.

## Runtime target contract

- Select `native`, `headless`, or `web` with `PRISMEL_RENDER_TARGET`.
  Accept `PRISMAL_RENDER_TARGET` as an alias and keep legacy `HEADLESS` as a
  final fallback.
- Headless mode must not require a display server, monitor, GPU, or OpenGL.
- Use SDL's dummy video driver and software renderer in headless mode.
- Do not silently turn drawing calls into no-ops: rendering should target the
  software framebuffer so programs exercise the same drawing paths.
- Keep target selection in `runtime` rather than scattering
  environment checks through application code.
- Any automated application-loop test must arrange its own termination.
- Web mode binds to `0.0.0.0`, keeps the SDL software renderer authoritative,
  and presents pooled RGBA frames through Wap's WebGL client. Never fork scene,
  geometry, font, image, Canvas, PXUI, or shader semantics into a second web
  renderer.
- Keep web frame, event, upload, command, asset, connection, and client queues
  explicitly bounded. Slow browsers skip stale complete frames.
- Browser input must enter the same ordered `Event` and `Input` path in logical
  coordinates. Preserve pointer capture, IME, focus-loss cancellation, resize,
  file-drop lifetime, and mirrored browser audio behavior.
- Browser text entry must be opt-in through logical `Scene.text_input_region`
  metadata. Focus the hidden browser editor synchronously only for presses in a
  registered text region; non-text taps must not open a mobile keyboard.
- Treat browser pointer cancellation separately from window focus loss: release
  the held pointer and cancel drag capture without dismissing text focus.
- Keep SDL calls on the initial domain. Wap may use long-lived system threads
  for blocking sockets, but must never create a domain or thread per frame.

## High-DPI and coordinate contract

- Treat `Sketch` configuration sizes, `Frame.width`/`height`, `Scene`
  coordinates, `Input.mouse_pos`, mouse event positions, and PXUI layout as
  logical points in one shared coordinate system.
- Keep SDL renderer logical size synchronized with the actual window size.
  `SDL_WINDOWEVENT_SIZE_CHANGED` is authoritative; ignore the duplicate
  `RESIZED` notification.
- Do not manually scale mouse events for Retina displays. SDL maps pointer
  events through the renderer logical size, which keeps drawing and hit testing
  aligned.
- Query renderer output size for physical backing pixels. Preserve
  `Frame.drawable_width`, `drawable_height`, `drawable_size`, and
  `pixel_scale` as the explicit native-pixel boundary.
- `Canvas.capture` and `Canvas.save_screen_png` read and preserve the full native
  framebuffer. Never allocate their readback from logical window dimensions.
- Keep `Scene.text` on an installed platform UI font and interpret `?size` in
  logical points. Font texture caches must include renderer density and
  rerasterize at native resolution. `PRISMEL_UI_FONT` remains the portable
  override; do not bundle Apple system fonts.
- Keep automatic scene text memory-bounded with the per-renderer 256-entry LRU
  without shortening the documented lifetime of explicit
  `Font.cached_text` images. Preserve empty text as a safe no-op rather than an
  SDL_ttf error.
- Keep renderer-local text caches LRU-bounded to 256 textures, including for
  rapidly changing labels, and preserve empty text as a valid no-op.
- Reserve `Scene.debug_text` for the fixed SDL2_gfx 8×8 diagnostic face.

## Public sketch API

- New user-facing examples should start with `Sketch`, `Frame`, and `Scene`.
  `Low.App` and `Low.Graphics` are the compatibility/escape-hatch layer.
- Thread immutable user models through `Sketch.run_state`; do not add global
  user-state refs to make an API shorter.
- A `view` returns `Scene.t`. Scene constructors must remain pure data
  constructors, and `Scene.render` is the effect boundary.
- Put current canvas, time, input, and ordered event facts in `Frame.t` so
  sketches do not need to synchronize several global modules.
- Keep `Frame.mouse_delta` equal to the sum of all logical pointer motion in one
  application frame, and reset it before polling the next frame.
- Prefer a five-minute-sketch path with sensible defaults, while keeping
  explicit configuration available for larger programs.
- Use `at:(x, y)` for positions, radians for angles, radius for circles, and
  `Color.t` for colors. Keep common constructor names short.
- Update `specification/api.md`, at least one complete example, and public API
  tests when changing the high-level design.
- Resource-owning models must release textures, fonts, and canvases with
  `Sketch.run_state ~on_stop` while SDL is still active.
- Prefer `Sketch.run_assets` for ordinary asset-owning sketches. Values returned
  by `Assets` are borrowed and must not be destroyed individually.
- Watched image reload must preserve the borrowed `Image.t` identity and retain
  the previous valid texture after a failed decode.
- `Scene.font_text` uses renderer-local textures owned by its `Font.t`. Preserve
  cache invalidation on font mutation and release offscreen-renderer entries
  before destroying their renderer.
- Preserve path contour boundaries through flattening, fill, and stroke.
  Even-odd and non-zero behavior must be tested with transparent holes rather
  than simulated background-colored shapes.
- Directly loaded or synthesized `Audio` values are owned resources and belong
  in `on_stop`. Headless audio must exercise SDL_mixer through the dummy device,
  not silently replace playback with a no-op.
- Do not add fake polymorphic placeholders for planned operations. Implement a
  real result-returning boundary or leave the operation out of the public API.

## Multicore and determinism

- SDL window, renderer, event, texture, image, and font operations must execute
  on the initial domain. `Scene.render` enforces this boundary.
- Use the reusable `Parallel` Domainslib pool for coarse CPU work. Never spawn a
  domain per frame or per collection item.
- Functions submitted to `Parallel` must operate on immutable or independently
  owned data. Do not mutate shared refs, arrays, stacks, or SDL objects without
  an explicitly reviewed synchronization design.
- Use immutable `Rand.t` values for new generative APIs. Do not use the global
  `Stdlib.Random` state in parallel-capable code.
- A seed must reproduce the same values, palettes, geometry, and noise across
  runs. Split generators before independent parallel work.
- Use `Sketch.Fixed dt` for repeatable simulation and export. The timestep must
  be finite and positive; time is derived from frame count rather than wall
  time.
- Keep `Sketch.export` artifact-deterministic: fixed inputs must produce
  byte-identical numbered PNG sequences across repeated runs on the same
  backend.
- Keep scheduling grain configurable and retain a sequential path for small
  collections, where parallel overhead costs more than the work.
- Parallel asset preparation may read ordinary bytes only. SDL_image decode,
  texture upload, and cache mutation join back onto the initial domain.

## Production performance contract

Prismel targets interactive procedural graphics and high-density offline mesh
generation. Performance is a correctness property for hot paths, not a later
cleanup step.

- Establish a benchmark and allocation baseline before changing a hot path.
  Report wall time, promoted/major allocations, peak live memory when
  practical, input size, domain count, compiler profile, and machine details.
- Document asymptotic time and auxiliary-memory complexity for public
  geometry algorithms. A green functional test is not evidence that a
  million-element workload is production-ready.
- Keep immutable public values, but use locally owned mutation internally:
  pre-sized arrays, growable buffers, hash tables, bitsets, and disjoint output
  slices are preferred over allocation-heavy persistent rebuilding inside an
  algorithm.
- Use packed numeric storage (`float array`, integer arrays, Bigarray, or
  structure-of-arrays layouts) for high-density geometry. Do not represent a
  million-element hot buffer as boxed lists or repeatedly convert it between
  lists and arrays. Public list conveniences must stay outside inner loops.
- Never use `List.nth`, repeated `List.length`, `@`, `Array.append`, nested
  `List.concat_map`, or per-element `Option` boxes in a measured hot loop.
  Linear builders must be amortized O(1) per append and materialize once.
- Mesh generators must compute output cardinality up front when topology makes
  it knowable, allocate once, and fill by index. For variable output, use a
  geometric-growth builder. Avoid generate-list → reverse → convert-array
  pipelines for dense output.
- Spatial and topology algorithms must use integer/index keys and compact
  adjacency storage where possible. Avoid polymorphic comparison/hash in hot
  paths when a specialized integer key is available. Avoid repeated global
  scans for local queries.
- Reuse the process-wide Domainslib pool. Never create or tear down domains per
  frame, algorithm iteration, collection, or asset. Parallel APIs must expose a
  tunable grain, retain a benchmarked sequential cutoff, and write only to
  disjoint owned output ranges.
- Split deterministic work by stable index ranges. Parallel execution must
  produce byte-identical ordered results to the sequential path for fixed
  inputs; do not let work-stealing order leak into mesh indices, hashes,
  palettes, random streams, exports, or diagnostics.
- Every parallel refactor needs a regression that compares one-domain and
  multi-domain results exactly. For geometry, compare vertex attributes,
  indices, primitive modes, and ordering; for rendering, compare captured
  native-framebuffer pixels or byte-identical exported PNGs.
- Run representative visual scenes in both one-domain and multi-domain modes.
  Treat unexplained pixel drift, missing primitives, changed winding, seams,
  or nondeterministic frame artifacts as correctness failures, not acceptable
  performance tradeoffs.
- Do not parallelize SDL, renderer, texture, image decode/upload, font, audio,
  event, or cache mutation. Parallelize pure sampling, field evaluation,
  transforms, classification, and independently owned geometry preparation,
  then join before the backend boundary.
- Frame hot paths must avoid work proportional to unchanged scene/resource
  size. Cache immutable derived data by stable identity with bounded lifetime;
  invalidate precisely on source mutation or renderer-density changes.
- Rendering inner loops must not allocate per pixel, sample, light, fragment,
  or triangle edge. Reuse scratch storage and precompute invariant material,
  light, transform, clipping, and texture state outside raster loops.
- Long-running workloads must be memory-bounded. Every cache needs an explicit
  capacity/eviction policy; temporary arenas/builders must become unreachable
  after a job; resource destruction remains explicit at the owning boundary.
- Prefer algorithmic wins over micro-optimization: eliminate quadratic scans,
  reduce topology passes, cull early, stream where possible, and avoid storing
  derivable duplicates before tuning arithmetic.
- Add scale tests for regressions in output cardinality and auxiliary storage.
  Add or update `tools/bench_*` for any new high-density path. Timing thresholds
  in CI must be broad and diagnostic; deterministic allocation/cardinality
  ceilings may be strict.
- A performance-sensitive handoff must include the benchmark command and
  before/after evidence. Do not claim “zero allocation”, “linear”, “parallel”,
  or “production-ready” without measurement or code-level proof.

## Houdini reference workflow

Use SideFX Houdini through `hython` as a black-box behavioral and performance
reference for in-scope polygon/curve SOP work. This is a clean-room workflow:
observe documented controls and externally visible results, write an independent
behavioral specification and fixtures, then implement that specification in
Prismel's PDK core without consulting or reproducing Houdini implementation
details.

- Houdini may be used to generate input/output fixtures, geometry summaries,
  attribute and group results, error cases, timings, and screenshots for
  comparison. Public SideFX documentation may clarify user-visible semantics.
- Never decompile, disassemble, trace private implementation internals, extract
  proprietary code or assets, or translate Houdini binaries/scripts into the
  repository. Do not claim knowledge of Houdini's internal algorithm from
  black-box observations.
- Record the exact Houdini build, license category, node type/version, complete
  parameter set, input fixture, frame, seed, and relevant environment settings
  for every comparison. Houdini Apprentice output is non-commercial reference
  material; do not commit `.hipnc` files or other license-restricted artifacts
  unless their redistribution terms have been explicitly reviewed.
- Prefer small deterministic fixtures serialized through an independently
  readable format or summarized as stable JSON/text: point positions, topology,
  primitive kinds and ordering, attributes, groups, bounds, volume, and error
  classification. Normalize only fields explicitly documented as unstable.
- Keep reference capture separate from implementation. A parity test should be
  understandable from its behavioral fixture without requiring Houdini at test
  time. Never make ordinary builds or CI depend on a Houdini installation.
- Test ordinary, boundary, malformed, empty, one-domain, multi-domain, and
  adversarial degeneracy cases. A matching screenshot alone is not exact SOP
  parity; compare topology and payload where the reference exposes them.
- Performance comparisons must use equivalent geometry, parameters, output
  materialization, warm-up, and machine conditions. Report Houdini and Prismel
  timings separately with sample count and dispersion. Houdini UI time, node
  creation, file I/O, and cook time must not be mixed silently. Do not claim an
  algorithmic match or performance parity from timing similarity.

The currently installed macOS reference is Houdini Apprentice 22.0.368. Its
`hython` is not assumed to be on `PATH`; invoke it explicitly:

```sh
PRISMEL_HYTHON='/Applications/Houdini/Houdini22.0.368/Frameworks/Houdini.framework/Versions/22.0/Resources/bin/hython'
"$PRISMEL_HYTHON" -c 'import hou; print(hou.applicationVersionString()); print(hou.licenseCategory().name())'
"$PRISMEL_HYTHON" tools/houdini/<script>.py -- <arguments>
```

For an interactive shell that needs the complete Houdini environment, source
the matching setup script in a disposable shell rather than adding a
version-specific directory permanently to the repository environment:

```sh
source '/Applications/Houdini/Houdini22.0.368/Frameworks/Houdini.framework/Versions/22.0/Resources/houdini_setup'
hython
```

Reference scripts belong under `tools/houdini/`. They must run headlessly,
create their own temporary scene, set every relevant parameter explicitly,
print or write deterministic machine-readable results, destroy temporary state
when practical, and exit nonzero on capture or validation failure. Keep any
machine-local output under ignored temporary/artifact directories, not beside
source fixtures.

Dense Boolean work must run the pig-head/rubber-toy VDB-remesh scale gate in
addition to small degeneracy fixtures. Generate or reuse machine-local operands
and run the complete comparison with:

```sh
python3 tools/houdini/compare_dense_boolean.py /tmp/prismel-dense-boolean
python3 tools/houdini/compare_dense_boolean.py /tmp/prismel-dense-boolean --reuse-existing
```

The default voxel sweep reaches 0.015 and roughly a quarter-million input
triangles on Houdini 22's built-in pig-head/rubber-toy sources. Do not shorten
it to a small-only sweep when making production scaling claims; use `--voxels`
explicitly only for focused iteration and report that reduced range. The
comparison defaults Prismel to Dune's `release` profile and records the profile
in its JSON report; use `--profile dev` only for diagnostic iteration and never
mix profiles in a before/after series.

The reference triangulates both VDB-remeshed operands before serialization and
before either Boolean. Do not compare the engines on slightly non-planar VDB
quads: engine-specific diagonal selection changes the represented surface and
invalidates geometry/parity conclusions. The harness must retain separate
Houdini first-process-cook, median fresh-node, and cached warm-recook timings,
plus Prismel fresh-cook timing, candidate counts, one-domain/multi-domain
exactness, closed two-manifold checks, output cardinality, canonical
triangle-coordinate agreement, volume agreement, and allocated bytes. Compare
Prismel timing to Houdini's median fresh-node cook; never present cached
recooks as an equivalent algorithm execution. A linear-scale claim requires at
least three distinct increasing triangle-count levels and reported log-log
time, candidate, and allocation exponents. The default gate rejects a Prismel
time, candidate, or allocation exponent above 1.2, or a corresponding
surface-coordinate error above 1e-6.

## Development workflow

Bootstrap a checkout with a repository-local OCaml 5 switch:

```sh
opam init
opam switch create . 5.3.0
direnv allow
opam install . --deps-only --with-test --with-doc
```

The checked-in `.envrc` evaluates `opam env --switch=. --set-switch`. If
direnv is unavailable, evaluate that command manually before using Dune.

Run these before handing off a change:

```sh
dune build @all
dune runtest
PRISMEL_RENDER_TARGET=headless dune exec examples/basic/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/particles/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/noise/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/canvas/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/audio/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/pxui/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/generative/main.exe
dune build @doc
```

If a headless example would otherwise run forever, give it an explicit finite
frame count for smoke testing.

## OCaml conventions

- Add an `.mli` for public modules.
- Prefer explicit result/error handling at backend boundaries.
- Avoid exposing additional SDL values in new public APIs.
- Keep sibling libraries wrapped, so their modules remain namespaced.
- Add focused tests for pure behavior and a headless integration test for
  renderer or lifecycle changes.
- High-DPI changes need coverage for renderer logical/output size, native
  capture dimensions, logical mouse alignment, per-frame delta reset, and PXUI
  press/drag/release behavior at simulated backing scales.
- Treat compiler warnings as errors and run `git diff --check`.

## Adding a sibling library

Create `lib/<name>/dune` with a wrapped library named `<name>` and declare
`(libraries prismel ...)`. Add its tests under `test/` or beside the library
only when they are genuinely library-specific. Document the library in the
README.

For `pxui`, prefer the functional builder, `Pxui.update`, and `Pxui.scene` in
new code. UI values belong in the immutable sketch model. Keep `add_*`,
`handle_event`, and `draw` only as compatibility wrappers around the same
widget semantics.

- Preserve visual feedback for hover, armed, and actively dragged controls in
  both the default theme and custom themes.
- Buttons, toggles, and choices commit only after a press and release inside
  the same control.
- Sliders, ranges, and XY controls capture the pointer from left-button press
  through release. They update continuously outside their bounds and clamp
  values to their configured ranges.
- `WindowFocusLost` must clear held input and cancel PXUI pointer capture, text
  focus, and IME composition.
- PXUI defaults to `Scene.text`; `Pxui.create ~font` borrows the supplied font,
  while `~font_size` selects the logical size of default system text.

## Adding an example

Create `examples/<name>/dune` and `examples/<name>/main.ml`. Depend only on the
libraries the example demonstrates. Examples are teaching material: keep them
short, readable, independently runnable, and finite under `HEADLESS`.

Use the repository scaffold for the standard shape:

```sh
dune exec tools/new_example.exe -- <name>
```

## Adding a sketch

Create `sketches/<name>/dune` and `sketches/<name>/main.ml`. Sketches are the
repository's workspace for visual and procedural experiments: they may be more
exploratory than examples, but must respect library dependency direction and
must not hide reusable framework code in the sketch directory. Prefer SOP
graphs for procedural geometry, deterministic seeds for generative work, an
`Easy_camera` for interactive 3D views, and explicit termination when running
headless.
