# Native backend

Rays ships one backend: the native Metal runtime on Apple Silicon. The supported host is
macOS on Apple Silicon with Metal available. Backend initialization either
creates that native stack or returns a typed startup error; applications do
not select an alternate renderer through environment variables or public API.

## Ownership and dependency direction

`flow` depends only on dependency-free `param` and `frame_input`. Its value graphs, expressions,
contexts and coercions have no geometry, editor, UI, renderer or GPU
dependencies; the dependency gate rejects those transitive edges.
`flow_ir` consumes specialized Flow plans and residual captures. It depends
only on `flow`, `param` and `rays_math`; its dataflow passes and packed/scalar
executor cannot reach geometry, presentation, editor or GPU libraries.
`flow` never depends on `flow_ir` and retains an independently callable
reference tree walker. `flow_sop` depends
only on `flow`, `flow_ir`, `param`, `procedural` and the standard-library `unix`
clock; its typed overlay and
value lane cannot reach presentation, the catalog, editor or GPU libraries.
Math-backed value declarations such as `noise3` live in `flow_ir` and are
included in the SOP/editor host's immutable `Flow_sop.Operators.all` list.
Plain Flow checking remains independent of the math library.
Cook-time `sop/attr` and `sop/with_attr` declarations live in `flow_sop`.
Its attribute kernel resolves immutable packed Flow sources against cooked
RDK inputs and writes through `Rdk.Kernel.edit_point_ranges` or point
attributes. The executor receives a resolver callback; neither `flow` nor
`flow_ir` imports geometry. Environment fold snapshots are passed through
the existing frame-node rebuild boundary.
Instantiated SOP topology/elementwise facts supply neutral count-origin proofs
to `flow_ir` for dynamic attribute-map fusion. No geometry types cross that
callback. The workspace owns a bounded atomic execution profile; hosts supply
the clock, and `flow_graph.Probe` receives only neutral tier/group/time metadata.
Neither `flow_ir` nor `flow_graph` gains a platform-clock dependency.

`flow_graph` depends only on `flow` and `param`. It owns `Projection`,
`Flow_edit`, `Exposure` and `Probe` for every domain. `pxui_graph` consumes
that neutral layer and menu entries supplied by the host; it never reaches
`procedural` or `rdk`, even transitively. The gate checks both boundaries.

`Value.Deferred (ty, id)` identifies a typed node in the evaluator plan.
Geometry nodes lower through `flow_sop`; Drawing nodes lower through
`Sketch_support.Drawing` into existing native `Rays.Scene` commands. Canvas
panels use the same PXUI composition and renderer as every other panel.
There is one evaluator, one UI engine and one native Metal renderer.
`sketch_support` may reach `flow_ir` to prepare drawing argument programs;
the editor retains that preparation while the plan is unchanged, and exports
prepare once before playback. Numeric maps inside frame folds dispatch through
the packed tier with current immutable bindings. `flow` owns fold identity and
transactions and receives only a private execution callback; it never imports
`flow_ir`. Reference drawing evaluation remains available for parity checks.

`frame_input` owns immutable logical frame facts (time, step, index, size,
pointer, held keys/buttons and ordered events), with no dependencies. The host
captures these once from `Rays.Frame` through `Sketch_support.Live_frame`.
`procedural.Context` carries the same snapshot for geometry-zone bodies;
its `Input` dependency projects every field into the cook cache key. No SDL,
runtime or renderer value crosses either pure boundary.

Material graph values lower into primitive surface attributes through
`procedural` and `rdk_attrib`. `sketch_support` converts these into shared
render mesh batches; neither the material context nor the assignment kernel
imports rendering code. `rdk_rays` expands primitive colors through the
existing attribute promotion kernel, preserving face boundaries.

```text
examples / sketches / pxui / editor / sketch_support / rdk_rays
                         |                  |                |
                         |                  v                v
                         |              procedural         rays
                         |                  |
                         |                  v
                         |                 rdk
                         |                  |
                         |                  v
                         |               rdk_boolean
                         |                  |
                         |                  v
                         |               rdk_mesh
                         |                  |
                         |                  v
                         |              rdk_attrib
                         |                  |
                         |                  v
                         |              rdk_spatial
                         |                  |
                         |                  v
                         |               rdk_exact
                         |                  |
                         |                  v
                         |               rdk_core
                         |                  |
                         |                  v
                         |             rays_math
                         |
                         v
                      rays ----------------------> runtime_input ---> sdl3
                         |
                         v
                  rays_execution
                         |
                         v
                      runtime ------> sdl3     runtime_resources ---> sdl3,
                         |                     (used by rays and      sdl3_image,
                         v                      rays_execution)       sdl3_ttf, sdl3_mixer
                     ogpu (virtual) ---> ogpu_core ---> native_layer_token

                    ogpu_metal (implementation) ---> ogpu_metal_native ---> metal
                    ogpu_mock  (implementation) ---> ogpu_core
```

The RDK split currently puts packed identity, storage, topology, groups, and
geometry in `rdk_core`; exact predicates, planar constraints, Delaunay, and
Voronoi live in `rdk_exact`. Spatial and surface indices, proximity queries,
and point clustering live in `rdk_spatial`. Attribute and group operations
live in `rdk_attrib`; packed generators and isosurface extraction live in
`rdk_gen`, while curve sampling and topology live in `rdk_curve`. These are
branches above the core/exact/spatial layers. Modeling operations are in
`rdk_mesh`; Boolean stages are in `rdk_boolean`.
`Rdk` keeps the public module paths stable, and
the dependency gate rejects upward edges from lower to higher RDK libraries.

`rays` never depends directly on an SDL library: window, event, clipboard,
cursor, image, font and audio services sit behind `runtime`,
`runtime_input` and `runtime_resources`, and the dependency gate rejects a
direct `rays` → `sdl3*` edge. One `Runtime.t` is either a window or an
offscreen target: the same render, replay, readback, resize, stats and
presentation-facts calls serve both, and window-only calls return
`Unsupported` offscreen. It owns the target's lifecycle, its single `stats`
record (frame, presentation, draw, pass and submission counts beside cache,
upload, GPU-timing and retained-plan counters) and the one presentation-facts
cache, requeried from SDL whenever the drawable changes; `Rays_execution`
is the frame coordinator above it and re-exports both records rather than
defining its own.
`rdk_rays` is the separate renderer conversion leaf.
`rays_editor` also composes `rays_pathtracer` for its shared 3D Renderer
control. It owns bounded per-viewport tracing resources and inserts their images
through the existing Scene presentation path. Raster and wireframe use Scene3;
all three modes run on the native Metal backend. This adds no dependency from
the renderer or foundational libraries back into the editor.
`procedural` depends only on `rdk`, `rays_math` (vectors, matrices,
`Color`, `Parallel`) and `lru`; it never reaches `rays` or the GPU
runtime, and the dependency gate keeps it so. The Rays-dependent glue
(`Sketch_support.Bridge`: frame-to-context, bounded mesh cache,
`cook_to_mesh`/`cook_to_scene3`) lives in `sketch_support`.
`sop_catalog` depends only on `rays_math`, `rdk` and `procedural`: its node
schemas name `Rays_math.Vec3`/`Mat4` directly, and the gate rejects any path
from it to `rays`, the runtime or a GPU library.

`procedural` is preprocessed by `rays.ppx` (which links `ppxlib` and `flow`
at build time only, never into the library): the node declarations that
yield both the editor factory and the typed `Sop` constructor live there, in
private `sop_*.ml` modules, and `Procedural.Nodes` exports their factories to
`sop_catalog`. `Edit_graph` no longer calls `Sop`, so a declaration may use
`Edit_graph.factory` without a cycle.

`runtime` owns process setup, initial-domain lifecycle, the SDL3 window, its
Metal view, resize scheduling, and presentation. It depends on `sdl3` and the
virtual `ogpu` only: it obtains the driver through `Ogpu.Impl.create_driver`,
and the surface configuration carries the window's `Native_layer_token`, which
the Metal adapter adopts as its `CAMetalLayer` and releases with the surface.
`Ogpu.Backend.gpu_timing` reports the queue's accumulated GPU time, so the
runtime reads no Metal counter. `ogpu_metal_native` owns the translation from
the checked high-level GPU interface to typed Metal bindings; `ogpu_metal`
selects it as the default virtual OGPU implementation. `metal` owns the safe
Metal resource and command API. Rays owns pure scene
values and records rendering through the narrow GPU boundary; it never exposes
native handles in its public API.
All raw Metal binding declarations come from `lib/metal/gen/registry.ml`;
typed SDK calls are generated, while custom marshalling/ownership primitives
are explicitly registered as `Native` entries. This does not change the OGPU
boundary or expose the private raw ABI (see `specification/metal.md`).
The dependency-free `param` library owns typed parameter schemas
(`Procedural.Parameter` and `Editor_core.Param` are aliases of it), so
`Pxui_shell.Inspector` renders SOP nodes and plain sketch records alike
without the geometry stack. The `editor_core` library owns bounded,
labelled undo history with explicit edit merge rules, named commands, key
routing, and atomic file storage (user preferences and documents are
s-expressions printed by `Flow.Lisp`). Sketch hosts use
`Editor_core.History`, `Editor_core.Router`, and `Editor_core.Store`;
the router filters fly-mode keyboard events before leader and chord routing,
while passing Space through to arm the leader after fly exits.
`flow` supplies the expression/value model, diagnostics and the workspace language
(reader, checker, evaluator) over `param`. `ppx_rays` depends on `flow` for
declaration checks only.
`flow_sop` depends on `flow`, `param` and `procedural` for the SOP overlay, value
lane, lowering, edits, projection and probes. The editor runs
the value lane on its initial domain before cook submissions and retains
applied values for the graph and inspector. The gate forbids
`flow` from reaching anything but `param` and `frame_input`, and `flow_sop` from reaching UI,
the SOP catalog, editor or GPU libraries.
`editor_document` owns the UI-free saved overlay, while `pxui_graph` and
`pxui_shell` are presentation adapters over it. `rays_editor` applies their
typed requests and schedules cooks; none of these edges points back into
`flow` or `flow_sop`.
`pxui_graph` exports its graph commands as `Editor_core.Command.t` entries without handling key
events. `editor_core` depends on `rays` for frame and event values, never on UI
or geometry libraries. `pxui_shell` owns editor chrome over the shared PXUI
handle; `Layout` computes pane geometry and `Chrome` handles standard splitters,
headers, and focus outline. Layout geometry is pure and has no mutable cache
inside the PXUI frame. Its which-key panel reads generic editor commands, while its
timeline and prompt widgets return requests without knowing about SOPs or
presets. `Shell.frame` owns the workspace's PXUI frame calls. `rays_editor`
supplies commands, playback state, and preset data. The one private
`editor_document` library contains Document, Settings, Objects, Layers and
Preset. Its package-private status and dependency gate enforce a transitive
ban on PXUI, shell, graph presentation, sketch_support and rays_editor.
Loaded documents validate before installation and current levels resolve
after load, undo, and removal. The host reduces stable-ID pane edits after UI
construction and records every edit path through its commit helper.
PXUI hit ancestry reports
presses on child controls to their pane roots; the sketch host reads those
signals for pane focus. When a click and scoped key share a frame, the router
reads the same PXUI hit tree before building the frame. `rays_editor`'s shared
`Environment.scene` path composes both 2D and 3D views: viewport adapters
supply camera and world painting, while visible/hidden composition, the
leader overlay, and the unchanged hidden-scene cache follow one path.
`Viewport3` owns camera-node seeding, active-camera repair, look-through
navigation, and follow-viewport document writes. `Viewport2` owns 2D panel,
navigation, scene, and persistence operations. `Environment` shares scene
composition, render-request completion, and PNG status handling. Presets use
`Editor_core.Store` graph and viewport sections; `Editor_core.Store.Settings` saves the
same envelope and reads legacy `PXUI1` settings files.
OGPU's dormant Frame_graph, Descriptor_arena, Transfer_ring, Instance,
Device_lifecycle, and Acceleration_pass modules have no production callers and
are removed. Query validation stays in `Ogpu.Sync.resolve`; the redundant
Query_pass and scoped Native_pass metadata wrappers are removed. The Metal
queue owns its bounded submission epochs: every command buffer is recorded
through `Backend.begin_commands` and admitted by `commit` or `commit_present`.
Plan G4 removed the description-based paths that preceded the encoders: the
portable `Command`, `Compute_pass`, `Transfer_pass`, `Mock`, and `Cache`
modules, `Backend.submit`/`submit_sync`/`present`/`submit_present`, pipeline
adoption, the per-queue submission cache, the Metal adapter's classic and
retained render-plan caches, its Command4 scoped path, and the description
encoders. `Ogpu.Render_pass` now holds only the render-state enumerations the
encoders share, and `Types.origin`/`extent` describe blit regions.
The native queue can poll completion through an epoch without blocking using
Metal command-buffer status; a terminal poll uses the same ordered cleanup
and epoch accounting as a blocking wait.
The portable `Ogpu.Command_buffer.status` polls a queue receipt and returns
`Pending` or `Completed`; terminal GPU errors remain typed errors. Its
`completed_epoch` query is scoped to that queue. The Metal driver passes the
native poll through the presentation cleanup path;
the mock uses independent clocks per queue and executes blit copies/fills
against its owned byte storage. It now executes texture upload, copy, and
readback through mip-aware RGBA8 storage as well. Shared conformance compares
exact bytes after padded-row and subregion uploads on mock and Metal. The
Metal adapter gives copy-only textures an explicit native usage bit because
Metal expands an empty usage mask during creation.

OGPU carries what the runtime and the path tracer call, and nothing a test
alone used (audit Q2). `Backend.create_library` compiles one MSL artifact into
a reusable library; `create_compute_pipeline_from` makes a pipeline per entry
point with typed function constants and an exact per-entry binding interface
checked against Metal reflection (buffer, texture, and sampler bindings occupy
separate index spaces, and `Acceleration_structure` and `Intersection_table`
are binding kinds). `begin_commands` records one command buffer through
compute, acceleration, blit, and render encoders (`set_pipeline`, `set_buffer`,
`set_bytes`, `set_texture`, `set_accel`, `set_table`, `dispatch_threads`,
`build_accel`, `write_compacted_size`, `compact_accel`, `buffer_to_texture`)
and commits without blocking, so `Command_buffer.status` and `gpu_duration`
observe it through the queue's epochs. Buffers take a `Types.memory` class;
device-local buffers reject host access with `Unsupported`. The Metal adapter
retains every referenced resource until the native command buffer completes;
the mock executes uploads exactly and answers compute, render, and ray tracing
with typed `Unsupported`.

Ray tracing: geometry variants are `Triangles`, `Motion_triangles` (one vertex
buffer per keyframe), `Bounding_boxes`, and `Curves`; descriptors are `Blas`,
`Motion_blas`, `Tlas_of` with an `instance_kind` (user-id or motion
records packed by `pack_instance_records`/`pack_motion_instances` through the
driver's `instance_layout`, plus a keyframe transform buffer packed by
`pack_transforms`), and `Sized` structures that `compact_accel` fills after
`write_compacted_size` reports the size. Pipelines link `[[intersection]]`
functions (`create_compute_pipeline_from ~linked`), and
`create_intersection_table` with `table_set_function`, `table_set_buffer`, and
the compute encoder's `set_table` binds them. `compute_use_accels` declares
the built bottom-level structures an instance structure references as read by
a dispatch (Metal `useResource:usage:`; they are otherwise evicted over time).
`Caps` is the live set: `Compute_pipeline`, `Render_pipeline`, `Ray_tracing`,
`Function_tables`, and `Ray_tracing_curves` (Metal: Apple9 and later; the M1
answers curves with typed `Unsupported`).
A colour attachment's `store` is honoured: `Store` keeps the contents (and
also resolves when a resolve texture is given), `Resolve` writes only the
resolve texture, `Discard` keeps nothing and is rejected with a resolve
texture; conformance resolves a stored multisample pass again from a `Load`
pass. `render_descriptor.depth_format` is portable description only: Metal 4
pipelines are not specialized on the depth format, so the Metal driver does
not read it.

Removed with their Metal bindings, mock arms, conformance cases, and
capability flags, because no product code called them: placement heaps and
aliasing, residency sets, intra-queue fences, timeline events, stage-boundary
timestamps, mesh and tile pipelines, dynamic libraries, binary archives,
sparse textures, the MetalFX upscaler, visible function tables, refit and
structure copy, precompiled metallib shaders, the encoded buffer copy, fill,
texture copy and texture-to-buffer blits, and the portable `Memory`, `Sync`,
and `Diagnostics` modules. A capability returns through the
`add-ogpu-feature` workflow with its first caller. Shared conformance covers
what remains on both drivers: capabilities, buffer round trips, padded and
inset texture uploads read back by the host, the three pixel formats, linear
mip sampling, library lifetime and function-constant specializations, exact
compute output, abandoned commands, ray-query hits (primitive id, instance id,
`t`), bounding boxes through an intersection table, curves or their rejection,
motion primitives and motion instances at three shutter times, user-id masks,
compaction hit parity, the render path, lifetime rejection, and zero leaked
handles; the mock rejects what it cannot execute with typed `Unsupported` and
reproduces the record layouts.
The path tracer's MSL now lives in `lib/rays_pathtracer/pathtrace.metal` and
is embedded by an OCaml/Dune rule and compiled once into one OGPU library;
the `INSTANCED` function constant selects the flat or instanced pipeline. The
M1 fixed-image qualification covers flat and instanced renders after this
source move and after the OGPU migration.
The path-tracer camera input is now `Rays.Camera.t`; the current ray kernel
accepts only an unshifted perspective view. The M1 fixed-image qualification
also covers this API migration.
Path-tracer materials and environment light use
`Rays_pathtracer.Linear_color.t`, a floating-point RGB record. It preserves
low-intensity and HDR inputs that byte-channel `Rays.Color.t` cannot express;
the GPU upload keeps the same float channel order and the fixed M1 image digest.
`Ogpu.Caps` now owns the portable feature matrix and typed `Unsupported`
check. Metal probes populate that profile in `ogpu_metal_native.Device`, which also
translates native Metal errors to typed OGPU errors.
The former `Ogpu.Capabilities` record is folded into `Ogpu.Caps`: limits,
feature availability, and conservative-probe notes travel as one value.
`Ogpu_metal_native.Device` stores that profile once, and the deterministic OGPU mock
uses `Caps.require` for typed unsupported-feature results.
The old Metal `Adapter` module is removed; it no longer duplicates feature
decisions or wraps capability probes.
The shared `test/ogpu_conformance` runner exercises capabilities, encoded
buffer and texture round trips (padded rows, mip levels, inset origins),
libraries and compute, ray tracing, the render path, lifetime rejection, and
teardown on both the mock and Metal drivers. Two executables select
`ogpu_mock` and `ogpu_metal` through Dune's virtual-library implementation
mechanism. The portable types live in `ogpu_core`; the wrapped `ogpu` module
aliases them without changing type identity. Nothing outside `lib/metal` and
`lib/ogpu_metal` references `Metal` or `Ogpu_metal_native`; the dependency
gate lists no Metal exception.

The gate (`test/dependency_gate.ml`) holds three kinds of rule. "May never
reach" rules run over the transitive closure; `rays_pathtracer` (no Metal
backend, mock, geometry graph, catalog, UI or editor library), `rdk_rays`
(the renderer leaf: `rdk_core`, `rdk_attrib`, `rdk_mesh` and `rays`, never the
Boolean stack, `procedural` or anything above) and `scene_execution_fixtures`
(only `scene_execution` and `ogpu`) have theirs. "Depends only on" whitelists
check every direct dependency, external ones included: `param`,
`native_layer_token`, `frame_input` and `lru` list none, `flow` only `param` and `frame_input`, `ogpu_core`
only `native_layer_token`, `ogpu` and `ogpu_mock` only `ogpu_core`, `metal`
only `threads` and `native_layer_token`, `ogpu_metal_native` only `ogpu_core`,
`metal` and `lru`, `ogpu_metal` only `ogpu_metal_native` and `metal`,
`pxui_shell` only `rays`, `editor_core` and `pxui`, `sop_catalog` only
`rays_math`, `rdk` and `procedural`. The Metal token scan covers `lib`,
`examples`, `sketches`, `tools` and `test`; outside the backend it admits
only the binding tooling (`tools/codemod/metal_registry.ml`), the two binding
benches (`tools/bench_metal_ffi.ml`, `tools/bench_metal_registry.ml`), the
Metal conformance driver (`test/ogpu_conformance/test_metal.ml`) and the gate
itself. `lib/metal` takes its source preprocessor from
`ppx/result_bind`, so no foundational library is built by something under
`tools/`; the gate rejects a `tools/` path in `lib/metal/dune`. Each rule has
an injected violation in the gate's own run.

Texture pixel formats (World plan P6): `Types.texture_descriptor.format` is
`Rgba8_unorm`, `Rgba16_float`, or `Rgba32_float` (4, 8, 16 bytes per texel,
`Types.texel_bytes`). Host bytes are little-endian; half floats are IEEE
binary16 (`Types.half_of_float`/`float_of_half`, round to nearest even).
Upload and readback row pitches must cover `width * texel_bytes`; texture
copies require equal formats. All three are sampled with linear filtering
and mip LOD and are storage-capable on Apple7+ (the M1 reports
`supports32BitFloatFiltering`), so no capability gate exists. Float formats
reject `Render_attachment` and multisampling with a typed `Unsupported`:
pipelines target `Rgba8_unorm` only and HDR is tone-mapped in the shader.
Presentation and MetalFX sources must be `Rgba8_unorm`. Depth and stencil
constructors keep their own native format.

`Scene_execution` sampled textures take their format from level 0's byte
count (4, 8 or 16 bytes per texel); `world:` keys are identity keys like
`image:`. The `Scene3_world` family (World plan P7) binds the material
texture or camera map at 1/2, the World block at buffer 3 and the prefiltered
specular mips at 4/5; auxiliary blocks hit on physical identity before a byte
compare and count against a 256 MB byte capacity.

Qualification code reads the runtime and Metal counters at their owning
boundaries. Sketch does not retain a process-global diagnostics snapshot after
teardown; its coordinator is destroyed during `on_stop` cleanup.
`Sketch` owns frame time and ordered input events. The execution coordinator
owns GPU submissions and presentation facts; its step result carries no second
event queue, clock, or input snapshot.
SDL3 file-drop events enter `Runtime_input` as validated full paths only.
The pump never reads file bytes; the sketch receives the same path through
`Event.FileDropped` and decides when to perform I/O. The input queue retains
its event-count bound, with no separate file-size limit or byte payload.

Scene visibility, culling, batch selection, and Scene2/Scene3 lowering remain
Rays responsibilities. The Metal binding does not contain Rays vertex
layouts, fixed Scene binding slots, or scene-cache keys. Its private prepared
submission surface snapshots only generic Metal pass state, typed resource
sets, indexed draws or indirect-command ranges, and completion-owned resource
roots. OGPU-Metal is the only layer that maps checked OGPU render values onto
that generic surface.

`Scene3.instances_array` lowers each instance batch to one indexed Metal draw.
Rays keeps one mesh and one material/light uniform block, then appends 48
float32 values per instance (model-view-projection, world, and normal matrices).
The vertex shader indexes that table with Metal's instance ID. OGPU carries a
checked positive instance count; OGPU-Metal uses an indexed instanced draw and
keeps the transform buffer alive through completion. Scene3 uses
counterclockwise front faces, matching RDK mesh winding. Other scene paths
retain their existing winding.

Scene execution uploads transform blocks into three bounded shared-buffer
pages, with each draw's offset aligned to 256 bytes. A changed transform set
packs into the next page; an unchanged set reuses the previous page without
another upload and permits retained-command replay when other state matches.
Submission is synchronous,
so a page is reused only after its prior GPU work completes. Each page is
capped at 256 MiB. Small uniforms use these pages rather than inline
`set_stage_bytes`, so retained indirect commands can reference them.

Scene3 raster accepts indexed triangles, lines, and points. Lines use native
Metal line draws; points use a point-topology pipeline with an explicit
one-pixel point size. Line strips and loops become indexed line pairs once
per immutable mesh. `Scene3.Wireframe` extracts unique edges from triangle
meshes, while callers with polygon topology can pass RDK's unique topology
edges as `Mesh.Lines` to avoid triangulation diagonals. Mesh packing is cached
by mesh identity and render mode with a bounded cache. The catalog Box SOP
defaults to quad faces, matching its inspector parameter default.

The initial domain owns every window, event, layer, drawable, and resource
operation. Pure geometry and scene preparation may use the shared parallel
pool, but all results join before crossing the native boundary.

`rays_pathtracer` is an ordinary sibling library on the virtual `ogpu`
API: it leases the presenting window's OGPU device through
`Rays_execution.acquire_gpu` (or a lazily created headless device when
no window exists), owns one queue on it, and builds its acceleration
structures, library, pipelines, and frames through OGPU encoders. Its
packed-mesh path builds one bottom-level structure and a top-level instance
structure; unchanged prototypes retain their GPU buffers and bottom-level
structure across transform edits. It hands results back to Rays only as
an ordinary `Image.t` with a stable identity. It imports neither `metal` nor
the runtime, and nothing below it imports it. See `specification/pathtracer.md`.

## Frame lifecycle

1. Runtime creates an SDL3 Metal view and obtains its `CAMetalLayer`.
2. The layer supplies a drawable for each presented frame; resize updates the
   drawable extent before recording work.
3. Rays lowers immutable `Scene` data into checked OGPU commands. Native
   implementation code validates device identity, resource lifetime, numeric
   ranges, and command ordering before encoding Metal commands.
4. Scene passes render into one owned RGBA8 texture, which remains the exact
   native capture/readback source.
5. `Backend.commit_present` appends the presentation pass, which renders that
   RGBA8 texture into the acquired BGRA8 `CAMetalDrawable`, to the frame's own
   command buffer and schedules the drawable. The queue keeps the frame,
   drawable, and source alive until Metal reports completion. Production
   drawables are framebuffer-only; the windowed runtime tests cover
   presentation end to end.

Scene execution records each frame through the render encoder. A frame's
passes become a replay plan of indirect command buffers when two consecutive
frames present identical draws (the automatic plan, admitted through a
fingerprint of the mesh, uniform, texture, and state identities and then an
exact payload comparison); an explicit prepared plan is keyed by identity and
version. Indirect commands cover buffer-only pipelines; textured families are
re-encoded each frame. Every render pass first makes the batch's buffers and
argument-referenced textures resident with `use_resources`, so a texture
reached only through an argument buffer is never sampled from a non-resident
page. Scene execution's plans borrow the bounded mesh, texture, and auxiliary
caches. Resources evicted while preparing a frame remain alive until that
synchronous submission completes. Before releasing any deferred resource,
execution drops both the prepared and automatic plans, including the
admission candidate, on success and failure paths.
The next frame rebuilds from the immutable CPU description. A dense scene may
exceed cache capacity without retaining a graph that refers to destroyed GPU
objects or increasing the cache bounds. Regressions cover 257 meshes, 257
textures, 65 auxiliary buffers, replay, resize, native pixels, and teardown.

A prepared-run cache hit does not make local mesh labels globally unique.
A mesh-cache hit by key must also match the exact immutable source uploaded
into that slot; otherwise it checks the payload hash and uploads as needed.
Each slot remembers at most one source, only when its CPU payload fits within
the slot's already bounded GPU byte budget. Replacing the upload replaces
that source identity. Alternating retained light/dark scenes with identical
local keys is checked pixel-for-pixel at 1× and 2× backing resolution, including
returning to the older prepared scene. This guards against geometry vanishing
or taking another scene's contents when a hover revisits an earlier scene.

Dense Scene2 runs of more than 64 consecutive geometry commands pack directly
into one native vertex/index mesh, including each primitive's RGBA values.
This avoids preparing and caching thousands of temporary draws only to copy
them into a batch afterward. Clip, transform, blend, image, and text commands
end a run; painter order is preserved. Packing takes two passes with
O(commands + vertices + indices) work and final-buffer storage. Shorter runs
keep one draw per geometry. Scene2 lowering caches only by identity: retained
display-list segments by (identity, version), plans by IR identity (or exact
command content), and prepared submissions by (identity, version); per-geometry
content is deduplicated once, by the executor's mesh cache. Native regressions compare 63, 64, 65, and
1,024 primitives with identity-barrier reference preparation, alpha/additive
overlap, fractional transforms, clipping, repeated frames, 1×/2× backing sizes,
and zero handle deltas.
The frame coordinator and runtime use the executor's pipeline
family and OGPU blend types directly, so preparing a draw no longer maps two
duplicate enum sets on the way to the backend.
Sampled draws use the same named record from Scene3 staging through runtime
and scene execution. The runtime passes the list through without a
per-draw tuple conversion; an unchanged 1× runtime frame preserves the list's
identity, while Retina scaling copies only records whose viewport or scissor
changes. Batch coalescing also requires an equal sample count.

Each validated immutable Render IR has a process-local integer identity.
Repeated lowering of that exact IR can reuse a bounded Scene2 plan by identity,
density, extent, and resource generation without hashing its command array.
Separately constructed but equivalent IR still uses content comparison to
preserve cache hits. The identity does not enter serialized IR or rendered
artifacts; the Scene2 plan cache remains capped at 16 entries and 64 MiB.

Private scene staging may split consecutive Scene2 commands into multiple
ordered native layers so independently changing UI regions do not invalidate a
stable retained plan.  A staging boundary emits no rendering command, does not
alter transform, clip, blend, or clear semantics, and is not part of the public
scene-construction API.  Each layer is lowered through the same checked OGPU
path and submitted in original scene order.

Retained 3D views: a window execution keeps up to four prepared 3D layers (`adopt_retained_view`,
keyed by the identity of the immutable prepared layer).  A layer seen on two consecutive frames is
rendered once into an offscreen execution the size of the window and later frames composite that
texture as a Canvas image, so a frame that only changes the UI does not shade the 3D view again.
The window's drawable size is checked on every use; a different layer, a resize or any failure
falls back to drawing the layer directly, and `destroy` releases the views before the device-lease
check.  Scenes the engine does not cache (textured, `Scene3.Private.cacheable` false) never repeat
an identity, so they are never retained.  `Scene` stays pure data; this is invisible to it.
`test_retained_view_native` checks that direct, retained and camera-change frames agree.

PXUI paints through a native-only instance layer. `Scene.Private.ui` wraps a
renderer-neutral `Scene_command.Ui_batch` (64-byte rect, textured, Bézier
wire-segment, and dot-grid instances grouped by clip, canvas transform, and
texture) and its bound textures. Staging keeps it as its own
`Ui_layer`. PXUI reaches the batch builder through `Scene.Private.Ui_batch`,
so its library depends on `rays` without a direct `scene_command` edge.
Like `view3d`, the Render_ir materializer skips it, and enclosing
Scene transforms and clips do not apply. `Rays_execution.Private
.lower_ui` turns each batch into one indexed draw of the `Ui` pipeline family:
vertex pulling reads the instances, a 24-byte affine uniform maps logical
canvas units to clip space, and the logical scissor is scaled to physical
pixels once, with the other draws. `Ui` draws bind their texture directly,
so the executor gives the family its own attachment class; it never shares
an argument-buffer render pass with Scene2 draws. Instance and index bytes
go through the digest-keyed mesh cache, so an unchanged UI re-uploads
nothing. The glyph atlas is an ordinary image resource whose generation
changes only when new glyphs are rasterized.
PXUI publishes the atlas through public `Image.upload_rgba`, preserving the
image identity on replacement and retrying a failed upload on the next frame.

`Canvas.render` uses the same lowering, pipeline variants, validation, and
completion path against a layerless owned texture on the shared device: the
offscreen execution leases the presenting window's OGPU device (or the
lazily created headless device) through the same lease as GPU film
producers, and the scene executor borrows that device without destroying it.
A Canvas creates its offscreen coordinator lazily, reuses it for all
subsequent renders, and after each render publishes the completed target
texture to the Canvas resource. A window scene that draws the canvas samples
that texture directly, keyed by canvas generation, with no readback or
upload; CPU access (`pixel`, `pixels`, `capture`, `to_image`, `save_png`)
reads the texture back lazily, and a CPU mutation makes the CPU pixels
authoritative again. `Canvas.destroy` destroys the coordinator and releases the
lease. Offscreen submission never creates a hidden window, acquires a drawable,
presents, or waits for display pacing.

Windowed runtime configuration selects FIFO presentation when vsync is enabled
and Immediate presentation otherwise. The selected mode is retained across
surface resize and is the mode reported in presentation facts. Layerless
Canvas targets always report `vsync = false` and `presented = 0`.

Drawable dimensions are physical pixels. `Frame.width`, `Frame.height`, scene
coordinates, input positions, and PXUI layout remain logical points; the
backend performs the logical-to-drawable conversion exactly once at the native
viewport boundary. Captures read the owned drawable-sized RGBA8 target;
they do not masquerade as a read of the BGRA window drawable.

## Resource rules

Images, fonts, canvases, meshes, pipelines, and command resources are owned
native resources. Safe APIs make destruction idempotent, reject use after
release, and preserve same-device validation. Sketch-owned resources are
released through `Sketch.run_state ~on_stop` while the SDL3 and Metal runtime
is still live. Command completion retains any referenced resources until their
submitted work completes.
SDL3, TTF, and mixer finalizer tokens queue until the initial domain drains
them; no token is discarded when the queue grows.
Resource-level font rendering returns an owned text snapshot. Automatic scene
text and explicit high-level font caches are bounded by their Rays owners;
the resource font has no second renderer-keyed cache.
High-level `Font.render_text` consumes that snapshot into an `Image`, transferring
the copied SDL surface pixels without further RGBA copies. Public `Text.pixels`
and `Image.pixels` remain copy-returning; a consumed text snapshot is destroyed.

`Scene`, `Canvas`, `Image`, `Font`, and `Audio` remain high-level Rays
interfaces. Their implementation lowers to the native GPU stack without
changing public scene semantics. Native framebuffer capture and export use
the same checked readback path as presentation diagnostics.

An image whose CPU pixels are replaced behind a stable identity (watched
reload or `Image.replace`) carries its generation in the sampled-texture key;
the executor re-uploads a changed generation into same-shape GPU storage.
The path tracer instead publishes one of two borrowed OGPU film textures on
completion. Scene samples that texture directly without image staging or a
per-frame CPU readback. The tracer writes the other texture while rendering;
explicit `Image.pixels` and capture remain checked readback boundaries.
Scene rejects malformed, destroyed, and foreign-device GPU image sources; a
canvas rendered on another device than the window's falls back to its CPU
pixels.

Canvas pixel storage is a compatibility/readback snapshot, not a renderer.
`Canvas.render` replaces it only with completed native GPU output. The
snapshot continues to support `pixels`, `capture`, `to_image`, `save_png`, and
explicit resource destruction; no CPU raster fallback participates in scene
rendering.

## Qualification

A surface is complete when focused correctness, ownership, conformance, and
performance tests pass. The dependency-direction gate and the
native link audit are release requirements: production artifacts may link only
the declared SDL3, Metal, OGPU, and platform frameworks for this backend.

Long-running, SDK-, driver- and machine-specific checks run under
`dune build @qualification`; they are release evidence, not the pre-commit
gate.
# Native UI input and export

The native window runs SDL3 text input only while a text field has focus. PXUI
emits a focused text region in logical points; Sketch forwards it on each
render, which starts text input and places SDL3's IME candidate area, and
stops text input when no region is focused. Text fields, text areas and the
picker search show the I-beam cursor under the pointer. PXUI measures the text
run and sends its caret offset in logical points to SDL3. Text fields, numeric
editors, and picker search share UTF-8 caret and selection editing. PXUI
applies text events only to a focused editor; Sketch UI
suppresses workspace and graph keyboard shortcuts while an editor has focus,
and its leader key (Space) only
arms while no editor is focused. Camera PNG requests capture the
just-presented native framebuffer through `Sketch.run_state`'s `after_present`
hook. The UI offers the supported native 1× export factor. PXUI copy, cut, and
paste go through the public `Rays.Clipboard` result boundary; failed writes
never clear a text value.

PXUI splitters request horizontal or vertical resize cursors while hovered or
captured. The Sketch UI host sends that request through `Sketch.set_cursor` and
the execution/runtime boundary, restoring the default cursor when no control
requests one. `Runtime` creates SDL cursor handles lazily, reuses one per
shape, and destroys them with the window. PXUI never imports SDL3.

# Relative pointer mode

`Sketch.set_relative_mouse` is the only public entry to SDL relative mouse
mode: it runs `Rays_execution.set_relative_mouse` →
`Runtime.set_relative_mouse`
(`Sdl3.Window.set_relative_mouse`) and switches the shared
`Runtime_input` source to relative accounting, so `Frame.mouse_delta`
sums SDL `xrel`/`yrel` (the event pump reports them through
`Runtime_input.add_motion`; `Sdl3.Event.poll_coalesced` sums the relative
motion of the samples it drops) instead of absolute differences that stop at
the window edge. Frame aggregation lives in this shared input source; the SDL3
binding exposes no second mouse-delta reduction helper. No SDL value crosses
into Rays's public API, the sketch
loop turns it off when it stops, and the library dependency graph is
unchanged (`test/dependency_gate.ml`). Sketch UI fly mode is its only
in-tree user.
The SDL3 boundary exposes single-event polling and the coalescing poller;
the runtime uses the latter to keep input floods bounded.
