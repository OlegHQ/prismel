# Native backend

Prismel ships one backend: the native Metal runtime on Apple Silicon. The supported host is
macOS on Apple Silicon with Metal available. Backend initialization either
creates that native stack or returns a typed startup error; applications do
not select an alternate renderer through environment variables or public API.

## Ownership and dependency direction

```text
examples / sketches / pxui / editor / sketch_support / pdk_prismel
                         |                  |                |
                         |                  v                v
                         |              procedural         prismel
                         |                  |
                         |                  v
                         |                 pdk
                         |                  |
                         |                  v
                         |               pdk_boolean
                         |                  |
                         |                  v
                         |               pdk_mesh
                         |                  |
                         |                  v
                         |              pdk_attrib
                         |                  |
                         |                  v
                         |              pdk_spatial
                         |                  |
                         |                  v
                         |               pdk_exact
                         |                  |
                         |                  v
                         |               pdk_core
                         |                  |
                         |                  v
                         |             prismel_math
                         |
                         v
                      prismel ----------------------> runtime_input ---> sdl3
                         |
                         v
                  prismel_execution
                         |
                         v
                      runtime ------> sdl3     runtime_resources ---> sdl3,
                         |                     (used by prismel and      sdl3_image,
                         v                      prismel_execution)       sdl3_ttf, sdl3_mixer
                     ogpu (virtual) ---> ogpu_core ---> native_layer_token

                    ogpu_metal (implementation) ---> ogpu_metal_native ---> metal
                    ogpu_mock  (implementation) ---> ogpu_core
```

The PDK split currently puts packed identity, storage, topology, groups, and
geometry in `pdk_core`; exact predicates, planar constraints, Delaunay, and
Voronoi live in `pdk_exact`. Spatial and surface indices, proximity queries,
and point clustering live in `pdk_spatial`. Attribute and group operations
live in `pdk_attrib`; packed generators and isosurface extraction live in
`pdk_gen`, while curve sampling and topology live in `pdk_curve`. These are
branches above the core/exact/spatial layers. Modeling operations are in
`pdk_mesh`; Boolean stages are in `pdk_boolean`.
`Pdk` keeps the public module paths stable, and
the dependency gate rejects upward edges from lower to higher PDK libraries.

`prismel` never depends directly on an SDL library: window, event, clipboard,
cursor, image, font and audio services sit behind `runtime`,
`runtime_input` and `runtime_resources`, and the dependency gate rejects a
direct `prismel` → `sdl3*` edge. One `Runtime.t` is either a window or an
offscreen target: the same render, replay, readback, resize, stats and
presentation-facts calls serve both, and window-only calls return
`Unsupported` offscreen. It owns the target's lifecycle, its single `stats`
record (frame, presentation, draw, pass and submission counts beside cache,
upload, GPU-timing and retained-plan counters) and the one presentation-facts
cache, requeried from SDL whenever the drawable changes; `Prismel_execution`
is the frame coordinator above it and re-exports both records rather than
defining its own.
`pdk_prismel` is the separate renderer conversion leaf.
`procedural` depends only on `pdk`, `prismel_math` (vectors, matrices,
`Color`, `Parallel`) and `lru`; it never reaches `prismel` or the GPU
runtime, and the dependency gate keeps it so. The Prismel-dependent glue
(`Sketch_support.Bridge`: frame-to-context, bounded mesh cache,
`cook_to_mesh`/`cook_to_scene3`) lives in `sketch_support`.

`runtime` owns process setup, initial-domain lifecycle, the SDL3 window, its
Metal view, resize scheduling, and presentation. It depends on `sdl3` and the
virtual `ogpu` only: it obtains the driver through `Ogpu.Impl.create_driver`,
and the surface configuration carries the window's `Native_layer_token`, which
the Metal adapter adopts as its `CAMetalLayer` and releases with the surface.
`Ogpu.Backend.gpu_timing` reports the queue's accumulated GPU time, so the
runtime reads no Metal counter. `ogpu_metal_native` owns the translation from
the checked high-level GPU interface to typed Metal bindings; `ogpu_metal`
selects it as the default virtual OGPU implementation. `metal` owns the safe
Metal resource and command API. Prismel owns pure scene
values and records rendering through the narrow GPU boundary; it never exposes
native handles in its public API.
The pure `editor_core` library owns bounded undo history with explicit edit merge
rules, key routing, and atomic JSON storage. Sketch hosts use
`Editor_core.History`, `Editor_core.Router`, and `Editor_core.Store`;
the router filters fly-mode keyboard events before leader and chord routing,
while passing Space through to arm the leader after fly exits.
`pxui_graph` exports editor bindings and graph commands without handling key
events. `editor_core` depends on `prismel` for frame and event values, never on UI
or geometry libraries. `pxui_shell` owns editor chrome over the shared PXUI
handle; `Layout` computes pane geometry and `Chrome` handles standard splitters,
headers, and focus outline. Layout geometry is pure and has no mutable cache
inside the PXUI frame. Its which-key panel reads generic editor bindings, while its
timeline and prompt widgets return requests without knowing about SOPs or
presets. `Shell.frame` owns the workspace's PXUI frame calls. `prismel_editor`
supplies bindings, playback state, and preset data. PXUI hit ancestry reports
presses on child controls to their pane roots; the sketch host reads those
signals for pane focus. When a click and scoped key share a frame, the router
reads the same PXUI hit tree before building the frame. `prismel_editor`'s shared
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
exact bytes after padded-row, mip-level, and subregion transfers on mock and
Metal. The Metal adapter gives copy-only textures an explicit native usage bit
because Metal expands an empty usage mask during creation. Ray-query, refit,
and the remaining encoder surface are covered by the G2 conformance below.

OGPU now carries the immediate-mode surface the path tracer needs (plan G2).
`Backend.create_library` compiles one shader artifact into a reusable library;
`create_compute_pipeline_from` makes a pipeline per entry point with typed
function constants and an exact per-entry binding interface checked against
Metal reflection (buffer, texture, and sampler bindings occupy separate index
spaces, and `Acceleration_structure` is a binding kind). `create_accel` builds
bottom-level triangle structures and top-level instance structures from
`pack_instances` records (transform, mask, structure index); `begin_commands`
records one command buffer through compute, acceleration, and blit encoders
(`set_pipeline`, `set_buffer`, `set_bytes`, `set_texture`, `set_accel`,
`dispatch_threads`, `build_accel`, `refit_accel`, `copy_buffer`) and commits
without blocking, so `Command_buffer.status` and `gpu_duration` observe it
through the queue's epochs. Buffers take a `Types.memory` class; device-local
buffers reject host access with `Unsupported`. The Metal adapter retains every
referenced resource until the native command buffer completes; the mock
executes blit copies exactly and answers compute and ray tracing with typed
`Unsupported`. Shared conformance now checks library lifetime and both
function-constant specializations, exact encoded compute and blit output,
abandoned commands, ray-query hits returning primitive id, instance id, and
`t` on both structure kinds, and refit after moving vertices.

Plan G5 completed the ray-tracing surface. Geometry variants are
`Triangles`, `Motion_triangles` (one vertex buffer per keyframe),
`Bounding_boxes`, and `Curves` (linear or higher-order control points, radii,
and segment indices); descriptors are `Blas`, `Motion_blas` (keyframe count,
time range, border modes), `Tlas`, `Tlas_of` with an `instance_kind`
(`Default_instances`, `User_id_instances`, `Motion_instances` plus a keyframe
transform buffer packed by `pack_transforms`), and `Sized` structures that
are only filled by `copy_accel` or `compact_accel` after
`write_compacted_size` reports the size. Instance records pack through the
driver's `instance_layout` (`pack_instances`, `pack_instance_records`,
`pack_motion_instances`; Metal: 64, 68, and 44 bytes) and carry masks, user
ids, and table offsets; TLAS refit is supported. Pipelines link `[[visible]]`
and `[[intersection]]` functions (`create_compute_pipeline_from ~linked`), and
`create_intersection_table`/`create_visible_table` with `table_set_function`,
`table_set_buffer`, and the compute encoder's `set_table` bind them through
the `Intersection_table` and `Visible_table` binding kinds, which share the
buffer index space. `Caps.Function_tables` and `Caps.Ray_tracing_curves`
(Metal: Apple9 and later; the M1 reports curves unsupported and answers with
typed `Unsupported` while the kernels still compile) gate the features.
Conformance on Metal traces bounding boxes through an intersection table,
curves or their rejection, motion primitives and motion instances at three
shutter times, user-id masks, TLAS refit, compaction and copy hit parity, and
visible tables; the mock rejects linked functions and reproduces the record
layouts.

Plan G6 added the memory and synchronization surface. `create_heap` makes a
placement heap in one memory class, tracked or untracked; `create_heap_buffer`
and `create_heap_texture` place resources at explicit offsets,
`make_aliasable` lets a later placement overlap a resource, and
`buffer_placement`/`texture_placement` report the size and alignment a
resource needs; compute and render encoders declare heaps with
`compute_use_heap`/`render_use_heap`. Residency sets (`create_residency_set`,
`residency_add`/`residency_remove`/`residency_commit`, `queue_add_residency`,
`use_residency`) keep allocations resident per queue or per command buffer.
Intra-queue fences (`create_fence`, `update_fence`, `wait_fence` on compute,
blit, and render encoders) order encoders on one queue, which is what makes
untracked heap aliasing safe. Timeline events (`create_event`,
`signal_event`/`wait_event` on the host, `commands_signal_event`/
`commands_wait_event` between encoders) synchronize the host with the GPU and
queues with each other. Timestamps (`create_timestamps`, the `?timestamps`
argument of `compute_encoder`, `blit_encoder`, and `render_encoder`,
`resolve_timestamps` into a buffer, `read_timestamps` on the host, and
`timestamp_reference` for the CPU/GPU clock pair and tick rate) sample GPU
time at encoder stage boundaries, the only sampling point Apple GPUs offer.
`Caps` gained `Heaps`, `Residency_sets`, and `Fences`, and
`Event_synchronization` and `Timestamp_queries` are now real probes (the M1
reports all five). The Metal adapter defers destruction of any of these
objects while a submission still uses it; the mock implements fences and
events (an event wait that is not yet satisfied parks the rest of the command
buffer until the host polls, completes, or waits) and answers heaps,
residency sets, and timestamps with typed `Unsupported`. The safe Metal layer
gained shared-event signal/wait on classic command buffers, a host wait with
timeout, and compute/blit encoders created from pass descriptors, each with a
success and a rejection test.

Plan G7 completed the pipeline and memory surface. Mesh pipelines
(`create_mesh_pipeline` from a library's object, mesh, and fragment entries
with compiled threadgroup sizes; `draw_mesh` on the render encoder) and tile
pipelines (`create_tile_pipeline`; `dispatch_tile` inside a render pass over
the imageblock; `tile_size`) share the render encoder with vertex pipelines,
whose shape the encoder tracks so that a draw of the wrong kind is
`Invalid_state`; `shader_stage` gained `Object`, `Mesh`, and `Tile` for stage
bindings. Dynamic libraries (`create_dynamic_library` from MSL with an install
name; `create_library ~dynamic` links against them and preloads them into
every pipeline of that library) and binary archives (`create_archive`,
`archive_add` of compute, mesh, and tile pipelines, `archive_serialize`,
`?archives`/`?archive_only` on pipeline creation) are gated by
`Caps.Dynamic_libraries`/`Caps.Binary_archives`; vertex/fragment render
pipelines are compiled by the Metal 4 compiler and answer archives with typed
`Unsupported`. Sparse textures live in `create_heap ~sparse:true` heaps
(`create_sparse_texture`, `texture_tile`, and `map_tiles` between encoders,
unmapped tiles reading as zero) behind `Caps.Sparse_memory`, and
`create_upscaler`/`upscale` wrap the MetalFX spatial scaler behind
`Caps.Metal_fx`; both capabilities are real probes now. The Metal adapter
serializes a dynamic library at its install name (or a temporary file for an
`@rpath` name) and loads it back, which is how Metal resolves pipeline
symbols. Safe Metal additions, handwritten in the bridge with success and
rejection tests: classic `draw_mesh_threadgroups` and
`dispatch_threads_per_tile`, mesh/tile descriptor color formats, optional
mesh depth/stencil formats, and `Metal.Fx.Spatial_scaler`, whose MetalFX
framework is linked as its own input. Conformance draws a full-screen
triangle through an object+mesh pipeline, inverts a green pass to magenta
through a tile kernel, calls a dynamic-library function from a kernel,
round-trips a compute pipeline through a serialized archive with
`archive_only`, uploads into a two-tile sparse texture and reads the mapped
tile back and the unmapped one as zero, then remaps, and upscales a constant
2x2 image to a constant 4x4; the mock rejects each with typed
`Unsupported`.
The virtual mock now reports `Compute_pipeline = false`: it validates compute
descriptions but cannot execute MSL. Pipeline creation, adoption, and raw
compute submissions reject with typed `Unsupported`; Metal keeps compute
enabled. The generic mock cache test no longer pretends that a metadata-only
compute pipeline exercises executable GPU work. Compute pipelines come only from libraries
(`Backend.create_library` and `create_compute_pipeline_from`), whose
reflection checks the declared interface; shared conformance dispatches them
through the compute encoder and compares exact output words on Metal, while
requiring typed `Unsupported` on the mock. `Ogpu.Library` now
exposes source and compiled metallib artifacts (currently aliasing `Shader`
for compatibility); compute pipeline identity includes typed function
constants. The Metal adapter loads compiled bytes and specializes the selected
function before reflection validation. The shared conformance runner has a
second exact-output path for both Boolean constant values, compiled from
`exact_compute.metal` by Dune. It lives under `@qualification` with
`PRISMEL_METAL_DEV=1`, because the Command Line Tools installation lacks
`xcrun metal` and `xcrun metallib`. The default headless suite still checks
source MSL and mock compiled-pipeline `Unsupported`; compiled-output validation needs a full
Xcode toolchain. Acceleration/refit and the remaining encoder contract remain
in G2.
The path tracer's MSL now lives in `lib/prismel_pathtracer/pathtrace.metal` and
is embedded by an OCaml/Dune rule and compiled once into one OGPU library;
the `INSTANCED` function constant selects the flat or instanced pipeline. The
M1 fixed-image qualification covers flat and instanced renders after this
source move and after the OGPU migration.
The path-tracer camera input is now `Prismel.Camera.t`; the current ray kernel
accepts only an unshifted perspective view. The M1 fixed-image qualification
also covers this API migration.
Path-tracer materials and environment light use
`Prismel_pathtracer.Linear_color.t`, a floating-point RGB record. It preserves
low-intensity and HDR inputs that byte-channel `Prismel.Color.t` cannot express;
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
Prismel responsibilities. The Metal binding does not contain Prismel vertex
layouts, fixed Scene binding slots, or scene-cache keys. Its private prepared
submission surface snapshots only generic Metal pass state, typed resource
sets, indexed draws or indirect-command ranges, and completion-owned resource
roots. OGPU-Metal is the only layer that maps checked OGPU render values onto
that generic surface.

`Scene3.instances_array` lowers each instance batch to one indexed Metal draw.
Prismel keeps one mesh and one material/light uniform block, then appends 48
float32 values per instance (model-view-projection, world, and normal matrices).
The vertex shader indexes that table with Metal's instance ID. OGPU carries a
checked positive instance count; OGPU-Metal uses an indexed instanced draw and
keeps the transform buffer alive through completion. Scene3 uses
counterclockwise front faces, matching PDK mesh winding. Other scene paths
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
meshes, while callers with polygon topology can pass PDK's unique topology
edges as `Mesh.Lines` to avoid triangulation diagonals. Mesh packing is cached
by mesh identity and render mode with a bounded cache. The catalog Box SOP
defaults to quad faces, matching its inspector parameter default.

The initial domain owns every window, event, layer, drawable, and resource
operation. Pure geometry and scene preparation may use the shared parallel
pool, but all results join before crossing the native boundary.

`prismel_pathtracer` is an ordinary sibling library on the virtual `ogpu`
API: it leases the presenting window's OGPU device through
`Prismel_execution.acquire_gpu` (or a lazily created headless device when
no window exists), owns one queue on it, and builds its acceleration
structures, library, pipelines, and frames through OGPU encoders. Its
packed-mesh path builds one bottom-level structure and a top-level instance
structure; unchanged prototypes retain their GPU buffers and bottom-level
structure across transform edits. It hands results back to Prismel only as
an ordinary `Image.t` with a stable identity. It imports neither `metal` nor
the runtime, and nothing below it imports it. See `specification/pathtracer.md`.

## Frame lifecycle

1. Runtime creates an SDL3 Metal view and obtains its `CAMetalLayer`.
2. The layer supplies a drawable for each presented frame; resize updates the
   drawable extent before recording work.
3. Prismel lowers immutable `Scene` data into checked OGPU commands. Native
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

PXUI paints through a native-only instance layer. `Scene.Private.ui` wraps a
renderer-neutral `Scene_command.Ui_batch` (64-byte rect, textured, Bézier
wire-segment, and dot-grid instances grouped by clip, canvas transform, and
texture) and its bound textures. Staging keeps it as its own
`Ui_layer`. PXUI reaches the batch builder through `Scene.Private.Ui_batch`,
so its library depends on `prismel` without a direct `scene_command` edge.
Like `view3d`, the Render_ir materializer skips it, and enclosing
Scene transforms and clips do not apply. `Prismel_execution.Private
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
text and explicit high-level font caches are bounded by their Prismel owners;
the resource font has no second renderer-keyed cache.
High-level `Font.render_text` consumes that snapshot into an `Image`, transferring
the copied SDL surface pixels without further RGBA copies. Public `Text.pixels`
and `Image.pixels` remain copy-returning; a consumed text snapshot is destroyed.

`Scene`, `Canvas`, `Image`, `Font`, and `Audio` remain high-level Prismel
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

The native window starts SDL3 text input for its lifetime. PXUI emits a focused
text region in logical points; Sketch forwards it to SDL3's IME candidate area
on each render and clears the area when focus leaves. PXUI measures the text
run and sends its caret offset in logical points to SDL3. Text fields, numeric
editors, and picker search share UTF-8 caret and selection editing. PXUI
applies text events only to a focused editor; Sketch UI
suppresses workspace and graph keyboard shortcuts while an editor has focus,
and its leader key (Space) only
arms while no editor is focused. Camera PNG requests capture the
just-presented native framebuffer through `Sketch.run_state`'s `after_present`
hook. The UI offers the supported native 1× export factor. PXUI copy, cut, and
paste go through the public `Prismel.Clipboard` result boundary; failed writes
never clear a text value.

PXUI splitters request horizontal or vertical resize cursors while hovered or
captured. The Sketch UI host sends that request through `Sketch.set_cursor` and
the execution/runtime boundary, restoring the default cursor when no control
requests one. `Runtime` creates SDL cursor handles lazily, reuses one per
shape, and destroys them with the window. PXUI never imports SDL3.

# Relative pointer mode

`Sketch.set_relative_mouse` is the only public entry to SDL relative mouse
mode: it runs `Prismel_execution.set_relative_mouse` →
`Runtime.set_relative_mouse`
(`Sdl3.Window.set_relative_mouse`) and switches the shared
`Runtime_input` source to relative accounting, so `Frame.mouse_delta`
sums SDL `xrel`/`yrel` (the event pump reports them through
`Runtime_input.add_motion`; `Sdl3.Event.poll_coalesced` sums the relative
motion of the samples it drops) instead of absolute differences that stop at
the window edge. Frame aggregation lives in this shared input source; the SDL3
binding exposes no second mouse-delta reduction helper. No SDL value crosses
into Prismel's public API, the sketch
loop turns it off when it stops, and the library dependency graph is
unchanged (`test/dependency_gate.ml`). Sketch UI fly mode is its only
in-tree user.
The SDL3 boundary exposes single-event polling and the coalescing poller;
the runtime uses the latter to keep input floods bounded.
