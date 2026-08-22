# Shattered Cube Optimization Plan

## Scope

This plan covers the native performance of:

```sh
opam exec --switch=. -- dune exec sketches/shattered_cube/main.exe
```

The desired behavior is event-driven: after the Boolean cook finishes and the
frame is presented, an unchanged sketch should block waiting for input or
another invalidation instead of redrawing continuously.

## Benchmark Environment

- Apple M1 with 8 CPU cores
- 16 GiB RAM
- macOS 26.4.1
- 1920 x 1080 display at 60 Hz
- OCaml 5.3.0
- Dune 3.20.2
- Approximately 5.0 GiB of swap was in use during the final check

System memory pressure is a measurement caveat, but it does not explain the
controlled visible-UI, hidden-UI, and reduced-frame-rate differences.

## Baseline Results

| Scenario | Result |
| --- | ---: |
| Initial dev-profile cook | Approximately 10 s wall, 50 CPU-seconds |
| CPU during cook | 600-750%, using several cores |
| Steady native rendering with UI visible | 86-88% CPU |
| Steady native rendering with UI hidden | 40-43% CPU |
| Native rendering with UI visible at 1 FPS | 6.7-7.3% CPU |
| Headless release run, three-run average | 8.70 s wall, 41.16 s user |
| Peak process footprint | Approximately 1.5 GiB |
| Steady native footprint | Approximately 1.0 GiB |

The generated result contains:

- 18,278 shattered pieces
- 278,368 triangles
- 835,104 expanded render vertices

The native steady-state sample showed that asynchronous cooking had completed
and its workers were blocked on condition variables. The steady load is not a
background recook loop.

## Diagnosis

### 1. The Application Redraws Unconditionally at 60 FPS

`lib/prismel/app.ml` processes every iteration by polling events, updating,
clearing, drawing, presenting, and starting the next iteration. The default
configuration in `lib/prismel/sketch.ml` requests 60 FPS.

`Time.limit_frame_rate` only caps the frame rate. With vsync enabled, even that
delay is delegated to presentation. There is no event wait, dirty flag, or
render invalidation boundary.

This is the primary architectural cause. A completed, static sketch still pays
the full UI and 3D rendering cost 60 times per second.

### 2. Visible PXUI Rendering Consumes Roughly Half a CPU Core

The steady main-thread sample attributed approximately:

- 35% of samples to SDL2_gfx antialiased polygons
- 29% to other SDL2_gfx primitives
- 6% to Bezier rendering
- 27% to OpenGL/native calls, presentation, and sleeping

The antialiased PXUI and graph primitives descend into many point and line
operations. With the installed SDL2 compatibility layer, these operations
frequently flush the renderer. Hiding the UI reduced steady CPU consumption
from approximately 88% to approximately 42%.

The graph contains only a small number of nodes, so this cost is an API-call
and batching problem rather than an inherently large UI workload.

### 3. The Dense Mesh Is Submitted from Client Memory Every Frame

`lib/prismel/renderer3d_gpu.ml` caches converted CPU Bigarrays by mesh identity,
but it does not retain the data in GPU vertex or element buffers. Before
drawing, it binds both `GL_ARRAY_BUFFER` and `GL_ELEMENT_ARRAY_BUFFER` to zero,
then supplies client-memory pointers to `glVertexPointer`, `glNormalPointer`,
and `glDrawElements`.

For this mesh, positions, normals, and indices total approximately 41.4 MiB per
draw. At 60 FPS, the driver must consume up to approximately 2.43 GiB/s of
client-array data, excluding state changes and other rendering overhead.

The default native window also requests 4x MSAA. This adds GPU work even though
the framebuffer is unchanged between frames.

### 4. Immutable Graph and UI Work Is Repeated Every Frame

`lib/sketch_ui/sketch_ui.ml` recompiles both the complete editable graph and
the displayed subgraph during every update. `Procedural.Edit_graph.compile`
and `compile_node` allocate hash tables and rebuild the DAG.

The workspace, graph, inspector, overlay, status, and PXUI scenes are also
reconstructed every frame. These costs are smaller than SDL2_gfx and 3D
submission in the current profile, but they cause avoidable allocation and
will matter after the main rendering issues are removed.

### 5. The Initial Boolean Cook Is Expensive but Finite

The startup sample showed useful work in:

- exact Boolean extraction
- exact or filtered intersection predicates
- barycentric payload transfer
- surface-index scanning
- topology and result validation

The graph fractures the source with 50 transformed cutter sheets and produces
18,278 pieces and 278,368 triangles. High multicore utilization during this
one-time cook is expected for the current workload.

There is a configuration mismatch: `domains = Some 1` in the sketch
configuration constrains the outer Prismel parallel context, but it is not
passed to `Sketch_support.Reactive_sop`. Reactive SOP cooking independently
defaults to approximately `hardware cores - 1`, which explains the observed
600-750% startup CPU.

### 6. Memory Is High but No Unbounded Leak Was Observed

The native process settled near 1.0 GiB, with ordinary GC variation. Headless
runs reached approximately 1.5 GiB while cooking and materializing exact
Boolean results and the expanded render mesh.

The measurements did not show continued steady-state growth. The current
issue is a large bounded working set combined with system swap pressure, not
evidence of an unbounded idle leak.

## Optimization Work

### P0: Add On-Demand Application Scheduling

Introduce an explicit scheduling policy rather than treating every sketch as
a continuous animation. The public shape could distinguish modes such as:

```ocaml
type schedule =
  | Continuous of { fps : int option }
  | On_demand
```

The exact API should remain small and follow existing `Sketch.config` patterns.
The implementation must preserve continuous mode for games, simulations,
timeline playback, and time-dependent graphs.

When an on-demand application has no pending work, the initial SDL domain
should block with `SDL_WaitEventTimeout` or an equivalent runtime-owned wait.
It should not poll and sleep repeatedly.

Dirty or wake conditions must include:

- keyboard, pointer, text, drop, focus, and window events
- window expose, resize, drawable-density, and renderer changes
- camera drag, inertia, and programmatic camera changes
- graph topology, parameter, selection, and workspace changes
- asynchronous cook completion or failure
- timeline playback and time-dependent graph context
- watched asset changes
- export or capture requests
- web transport events that affect presentation or input

Asynchronous cook completion needs a reliable wake mechanism. Prefer a bounded
custom SDL event or another runtime-owned notification over frequent idle
polling. A bounded timeout while a cook is in flight is acceptable as an
intermediate implementation, but it is not the final idle design.

Expected result: after a static frame is presented, the process should approach
zero CPU until one of the defined invalidations occurs.

### P1: Make Mesh Caches GPU-Resident

Extend the bounded `Renderer3d_gpu` packed-mesh cache with:

- vertex buffer objects for positions, normals, and optional colors
- an element buffer object for indexed meshes
- buffer sizes and the renderer/context identity
- deterministic deletion on eviction and renderer shutdown

Upload immutable mesh data once per stable mesh identity with `glBufferData`,
then draw using buffer offsets. All creation, upload, draw, eviction, and
destruction operations must remain on the initial SDL domain.

The existing cache capacity and ownership rules must remain bounded. Context
loss or renderer recreation must invalidate every associated GPU object.

For expanded sequential meshes, benchmark `glDrawArrays` against an identity
element buffer. Do not retain an index array when it provides no reuse or
ordering benefit.

Expected result: unchanged camera frames should not resubmit approximately
41.4 MiB of client-array data.

### P1: Batch PXUI and Graph Geometry

Replace per-pixel SDL2_gfx antialias paths in hot UI rendering with batched
triangle and line geometry. Suitable boundaries include SDL renderer geometry
or a Prismel-owned native batch that respects the existing renderer lifecycle.

Batch or cache:

- graph grid lines
- Bezier wire tessellation
- node backgrounds, borders, and selection outlines
- rounded rectangles and circles
- repeated glyph or icon geometry where ownership permits

Static graph presentation should be cached by document, layout, viewport, and
selection identity. Pointer hover and transient interaction should invalidate
only the affected presentation data.

Preserve headless and web semantics through the existing authoritative
software rendering paths. Native batching must not create a second public UI
model or change hit testing.

### P2: Cache Graph Compilation and Scene Construction

Cache `Edit_graph.compile` by immutable document identity. Cache
`compile_node` by document identity and displayed node ID. Recompile only when
the document or viewed node changes.

Separate scene invalidations so that:

- camera changes reuse the GPU mesh
- selection changes reuse compiled geometry graphs
- status changes do not rebuild the graph visualization
- graph layout changes do not rebuild the cooked 3D scene
- completed static UI segments are retained until their inputs change

Retain explicit capacities and renderer-local ownership for every new cache.

### P2: Make Cook Parallelism Explicit

Either propagate `Sketch.config.domains` into reactive cooking or expose a
separate, clearly named `cook_domains` setting. Avoid two unrelated domain
controls whose defaults contradict each other.

Suggested policy:

- fast interactive startup: use the recommended worker count
- lower-temperature mode: use one or two cook domains
- deterministic tests: compare one-domain and multi-domain results exactly

Reducing domains is a power/latency tradeoff, not an algorithmic optimization.
The same cook will take longer with fewer domains.

### P2: Review Native MSAA Policy

Do not request 4x window MSAA by default for a dense viewport unless the
quality improvement is required. Confirm whether `Scene3.create ~samples`
actually controls the native window framebuffer; if it does not, make the
window-level choice explicit in the sketch configuration.

On-demand rendering remains the primary solution. Disabling MSAA only reduces
the cost of frames that still need to be drawn.

### P3: Lazily Initialize Audio for Silent Applications

The application currently initializes SDL audio and related threads even for a
silent geometry sketch. Defer audio initialization until an audio resource or
playback operation is used, while preserving the documented dummy-device
headless behavior.

This is not a primary CPU hotspot, but it reduces idle threads and startup
surface area.

## Verification and Acceptance Criteria

### On-Demand Idle

- Run the completed shattered-cube sketch without input for at least 60 s.
- Average process CPU after cooking must be below 1% on the benchmark machine.
- There must be no periodic full redraw, graph compile, or UI rebuild.
- Worker domains must remain blocked when no cook is pending.
- Resident memory must remain bounded without a monotonic increase.

### Interaction

- Pointer, keyboard, graph edits, camera movement, resize, and expose events
  must wake the loop and present a frame without visible latency.
- Camera inertia and timeline playback must continue scheduling frames until
  they stop.
- Cook completion and failure must wake the UI even with no user input.
- Native, headless, and web targets must retain their termination and
  presentation contracts.

### GPU Mesh Cache

- An unchanged mesh must upload its buffers once per renderer/context.
- Camera-only movement must not upload mesh data again.
- Cache eviction and renderer shutdown must delete all GPU objects.
- The cache must remain bounded under changing procedural meshes.
- More than the first frame must render correctly after SDL/OpenGL state
  restoration.

### UI Batching

- The same graph and PXUI state must produce equivalent pixels within the
  renderer's documented antialias tolerance.
- UI-visible steady rendering should no longer spend most main-thread samples
  in SDL2_gfx point, line, polygon, ellipse, or Bezier calls.
- Hit testing and logical high-DPI coordinates must remain unchanged.

### Determinism

- One-domain and multi-domain cooks must produce byte-identical ordered
  geometry, attributes, primitive modes, and indices.
- Existing fixed-clock and headless tests must remain deterministic.
- No SDL or renderer operation may move off the initial domain.

## Benchmark Procedure

Build the exact development target before native sampling:

```sh
opam exec --switch=. -- dune build sketches/shattered_cube/main.exe
```

Run the built executable directly when a stable PID is required for `top` or
macOS `sample`; it is the same program that `dune exec` launches:

```sh
PRISMEL_RENDER_TARGET=native \
  _build/default/sketches/shattered_cube/main.exe
```

Record native startup and at least 30 s of completed steady state. Capture:

- wall, user, and system time
- process CPU after cooking
- resident and peak memory
- worker-domain state
- main-thread stacks
- GPU upload counts and bytes after VBO instrumentation is added
- redraw and graph-compile counts after invalidation instrumentation is added

Run headless release measurements separately:

```sh
opam exec --switch=. -- dune build --profile release \
  sketches/shattered_cube/main.exe
/usr/bin/time -lp env PRISMEL_RENDER_TARGET=headless \
  _build/default/sketches/shattered_cube/main.exe
```

Do not compare development and release timings as one series. Record the
profile, domain count, display configuration, and machine state with every
before/after result.

## Handoff Order

1. Implement and test on-demand scheduling.
2. Add instrumentation proving redraw and wake behavior.
3. Add bounded GPU-resident mesh buffers.
4. Batch the measured PXUI and graph primitive hotspots.
5. Cache graph compilation and immutable scene fragments.
6. Clarify cook-domain configuration and native MSAA behavior.
7. Re-run the complete benchmark and publish before/after evidence.

The first step is the only change required to make a completed static sketch
truly idle. The remaining work reduces the latency and power cost of frames
that are legitimately invalidated.
