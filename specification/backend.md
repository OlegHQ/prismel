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
                      runtime ----------> sdl3
                         |
                         v
                    ogpu_metal --------> ogpu
                         |
                         v
                       metal
```

`runtime` owns process setup, initial-domain lifecycle, the SDL3 window, its
Metal view, resize scheduling, and presentation. `ogpu_metal` owns the
translation from the checked high-level GPU interface to typed Metal bindings.
`metal` owns the safe Metal resource and command API. Prismel owns pure scene
values and records rendering through the narrow GPU boundary; it never exposes
native handles in its public API.

Scene visibility, culling, batch selection, and Scene2/Scene3 lowering remain
Prismel responsibilities. The Metal binding does not contain Prismel vertex
layouts, fixed Scene binding slots, or scene-cache keys. Its private prepared
submission surface snapshots only generic Metal pass state, typed resource
sets, indexed draws or indirect-command ranges, and completion-owned resource
roots. OGPU-Metal is the only layer that maps checked OGPU render values onto
that generic surface.

The initial domain owns every window, event, layer, drawable, and resource
operation. Pure geometry and scene preparation may use the shared parallel
pool, but all results join before crossing the native boundary.

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

`Scene`, `Canvas`, `Image`, `Font`, and `Audio` remain high-level Prismel
interfaces. Their implementation lowers to the native GPU stack without
changing public scene semantics. Native framebuffer capture and export use
the same checked readback path as presentation diagnostics.

Canvas pixel storage is a compatibility/readback snapshot, not a renderer.
`Canvas.render` replaces it only with completed native Metal output. The
snapshot continues to support `pixels`, `capture`, `to_image`, `save_png`, and
explicit resource destruction; no CPU raster fallback participates in scene
rendering.

## Qualification

`NEW_GPU_STUFF.md` is the active migration plan. Its S, M, O, R, and D gates
require focused correctness, ownership, conformance, and performance evidence
before a surface is declared complete. The dependency-direction gate and the
native link audit are release requirements: production artifacts may link only
the declared SDL3, Metal, OGPU, and platform frameworks for this backend.

Evidence is recorded under `specification/evidence/gpu_migration/`. A record
names the exact commit, command, profile, machine context, and artifact hash;
historical records are qualification evidence rather than a substitute for the
final clean-tree gate run.
