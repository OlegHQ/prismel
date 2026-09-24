# Native backend

Prismel ships one backend: the native Metal runtime on Apple Silicon. The supported host is
macOS on Apple Silicon with Metal available. Backend initialization either
creates that native stack or returns a typed startup error; applications do
not select an alternate renderer through environment variables or public API.

## Ownership and dependency direction

```text
examples / sketches / pxui / procedural / pdk
                         |
                         v
                      prismel
                         |
                         v
                      runtime_next ------> sdl3
                         |
                         v
                    ogpu_metal --------> ogpu
                         |
                         v
                       metal
```

`runtime_next` owns process setup, initial-domain lifecycle, the SDL3 window, its
Metal view, resize scheduling, and presentation. `ogpu_metal` owns the
translation from the checked high-level GPU interface to typed Metal bindings.
`metal` owns the safe Metal resource and command API. Prismel owns pure scene
values and records rendering through the narrow GPU boundary; it never exposes
native handles in its public API.
OGPU's dormant Frame_graph, Descriptor_arena, Transfer_ring, Instance,
Device_lifecycle, and Acceleration_pass modules have no production callers and
are removed. Query validation stays in `Ogpu.Sync.resolve`; the redundant
Query_pass and scoped Native_pass metadata wrappers are removed. The Metal
queue now owns its bounded submission epochs and reusable command storage,
instead of carrying the separate `Ogpu.Submission` state object. The live
command and resource contracts remain until the G1 virtual-library split
gives the Metal and mock implementations one conformance surface.

Qualification code reads the runtime and Metal counters at their owning
boundaries. Sketch does not retain a process-global diagnostics snapshot after
teardown; its coordinator is destroyed during `on_stop` cleanup.
`Sketch` owns frame time and ordered input events. The execution coordinator
owns GPU submissions and presentation facts; its step result carries no second
event queue, clock, or input snapshot.
SDL3 file-drop events enter `Runtime_next_input` as validated full paths only.
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
retain their existing winding. Scene3 indexed draws use the classic encoder
until the prepared indexed pass supports instance counts and winding.

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

`prismel_pathtracer` is the one ordinary sibling library that consumes the
safe `metal` API directly: it owns its own device, queue, acceleration
structures, and compute pipelines. Its packed-mesh path builds one primitive
structure and a top-level instance structure; unchanged prototypes retain
their GPU buffers and primitive structure across transform edits. It hands
results back to Prismel only as
an ordinary `Image.t` with a stable identity. It never exposes native handles
and nothing below it imports it. See `specification/pathtracer.md`.

## Frame lifecycle

1. Runtime creates an SDL3 Metal view and obtains its `CAMetalLayer`.
2. The layer supplies a drawable for each presented frame; resize updates the
   drawable extent before recording work.
3. Prismel lowers immutable `Scene` data into checked OGPU commands. Native
   implementation code validates device identity, resource lifetime, numeric
   ranges, and command ordering before encoding Metal commands.
4. Scene passes render into one owned RGBA8 texture, which remains the exact
   native capture/readback source.
5. A typed OGPU presentation operation uses the same producer queue to render
   that RGBA8 texture into the acquired BGRA8 `CAMetalDrawable`. Classic final
   passes append conversion and drawable scheduling to their existing command
   buffer. A final pass that requires Command4 completes first and uses the
   ordered same-queue classic presentation fallback until Command4 exposes a
   bounded submission-scoped drawable lifetime. Both paths keep
   completion-owned state alive until Metal reports completion. Production
   drawables remain framebuffer-only; only the focused backend test creates a
   readable layer.

Unchanged portable submissions may reuse an exact immutable command/resource/
pipeline identity tuple. Public commands snapshot every reachable mutable array
once and are abstract; generic drivers receive only a borrowed, read-only view.
The generic queue validates the current resource and pipeline wrappers on every
hit, but caches only the command identity and numeric identity/token maps. It
never retains command graphs, public resource or pipeline wrappers, or arbitrary
driver closures. Destroying a resource or pipeline purges matching numeric
entries. The queue keeps at most 256 entries and 64 MiB of this mapping metadata
per queue by default; the fixed 256-slot array is bounded independently from
the byte ledger, and retained-byte statistics cover entry metadata only.
Oversized maps remain one-shot. OGPU-Metal applies a
separate 256-entry and 64-MiB default per-queue bound to retained classic pass
descriptors and accounts any command graph it deliberately owns. Both byte
limits are configurable, use conservative saturating accounting, mutate only
after native admission, and release their accounting on eviction and queue
teardown.

Scene execution's retained commands borrow the bounded mesh, texture, and
auxiliary caches. Resources evicted while preparing a frame remain alive until
that synchronous submission completes. Before releasing any deferred resource,
execution invalidates both explicit prepared replay and automatic command
replay, including their admission candidate, on success and failure paths.
The next frame rebuilds from the immutable CPU description. A dense scene may
exceed cache capacity without retaining a graph that refers to destroyed GPU
objects or increasing the cache bounds. Regressions cover 257 meshes, 257
textures, 65 auxiliary buffers, replay, resize, native pixels, and teardown.

A prepared-run cache hit does not make local mesh labels globally unique.
The trusted mesh lookup must also match the exact immutable source uploaded
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
O(commands + vertices + indices) work and final-buffer storage. Ordinary small
runs retain independent geometry caching, and immutable display-list/IR caches
retain their existing bounds. The diagnostic environment variable
`PRISMEL_SCENE2_DENSE_RUNS=0` measures the existing per-geometry preparation path.
Retained batch matching includes pipeline family, blend mode, and sample count
as well as mesh contents and render state; identical geometry must not reuse a
batch from a different blend mode. Native regressions compare 63, 64, 65, and
1,024 primitives with identity-barrier reference preparation, alpha/additive
overlap, fractional transforms, clipping, repeated frames, 1×/2× backing sizes,
and zero handle deltas.

Retained OGPU-Metal identity and replay metadata have independent 256-entry
limits and share a configurable 64-MiB default byte capacity per queue. Metal's
retained render-plan cache has its own entry limit and configurable 64-MiB
default capacity, measured from each private-storage indirect command buffer's
native `allocatedSize`. The adapter separately bounds the safe owner graph that
keeps commands, argument encoders and buffers, samplers, prepared resource
sets, pipelines, and dependency tokens alive. Evicted in-flight plans move
their exact ICB bytes and conservative owner bytes to an explicit retired-byte
ledger until completion; teardown drains every ledger to zero.

A prepared Metal pass is an immutable generic snapshot. It roots the typed safe
wrappers needed for revalidation, but owns no command buffer or native encoder
while idle. Execution first revalidates its descriptor graph, resource
lifetimes, device identity, render area, and draw or ICB range. A successful
command buffer then owns one typed aggregate of the referenced resources until
terminal completion. Unexpected native failure closes any opened encoder and
makes that command buffer uncommittable; it never falls back to a CPU or
alternate renderer.

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
`Ui_layer`, like `view3d`: the Render_ir materializer skips it, and enclosing
Scene transforms and clips do not apply. `Prismel_next_execution.Private
.lower_ui` turns each batch into one indexed draw of the `Ui` pipeline family:
vertex pulling reads the instances, a 24-byte affine uniform maps logical
canvas units to clip space, and the logical scissor is scaled to physical
pixels once, with the other draws. `Ui` draws bind their texture directly,
so the executor gives the family its own attachment class; it never shares
an argument-buffer render pass with Scene2 draws. Instance and index bytes
go through the digest-keyed mesh cache, so an unchanged UI re-uploads
nothing. The glyph atlas is an ordinary image resource whose generation
changes only when new glyphs are rasterized.

`Canvas.render` uses the same lowering, pipeline variants, validation, and
completion path against a layerless owned Metal texture. A Canvas creates its
offscreen coordinator lazily, reuses it for all subsequent renders, reads the
completed texture back into the public Canvas snapshot, and destroys the
coordinator with `Canvas.destroy`. Offscreen submission never creates a hidden
window, acquires a drawable, presents, or waits for display pacing.

Windowed runtime configuration selects FIFO presentation when vsync is enabled
and Immediate presentation otherwise. The selected mode is retained across
surface resize and is the mode reported in presentation facts. Layerless
Canvas targets always report `vsync = false` and `presented = 0`.

Drawable dimensions are physical pixels. `Frame.width`, `Frame.height`, scene
coordinates, input positions, and PXUI layout remain logical points; the
backend performs the logical-to-drawable conversion exactly once at the native
viewport boundary. Captures read the owned drawable-sized RGBA8 Metal target;
they do not masquerade as a read of the BGRA window drawable. Exact
presentation tests separately probe the acquired drawable through a GPU blit.

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
Scene rejects malformed, destroyed, and foreign-device GPU image sources.
An independent offscreen Canvas renderer snapshots the image once into its
own device, preserving `Canvas.render` and `Image.pixels` behavior across that
device boundary.

Canvas pixel storage is a compatibility/readback snapshot, not a renderer.
`Canvas.render` replaces it only with completed native Metal output. The
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
requests one. `Runtime_next` creates SDL cursor handles lazily, reuses one per
shape, and destroys them with the window. PXUI never imports SDL3.

# Relative pointer mode

`Sketch.set_relative_mouse` is the only public entry to SDL relative mouse
mode: it runs `Prismel_next_execution.set_relative_mouse` →
`Runtime_next_orchestrator.set_relative_mouse` → `Runtime_next.set_relative_mouse`
(`Sdl3.Window.set_relative_mouse`) and switches the shared
`Runtime_next_input` source to relative accounting, so `Frame.mouse_delta`
sums SDL `xrel`/`yrel` (the event pump reports them through
`Runtime_next_input.add_motion`; `Sdl3.Event.poll_coalesced` sums the relative
motion of the samples it drops) instead of absolute differences that stop at
the window edge. Frame aggregation lives in this shared input source; the SDL3
binding exposes no second mouse-delta reduction helper. No SDL value crosses
into Prismel's public API, the sketch
loop turns it off when it stops, and the library dependency graph is
unchanged (`test/dependency_gate.ml`). Sketch UI fly mode is its only
in-tree user.
The SDL3 boundary exposes single-event polling and the coalescing poller;
the runtime uses the latter to keep input floods bounded.
