# Shattered Cube Native Optimization Plan

## Scope

This plan covers the Apple-Silicon Metal execution of:

```sh
opam exec --switch=. -- dune exec sketches/shattered_cube/main.exe
```

The desired steady state is event-driven. After the Boolean cook completes and
the resulting frame is presented, an unchanged sketch blocks for input or a
declared invalidation. Legitimately invalidated frames reuse bounded native
mesh, pipeline, retained-plan, font, and image resources.

This document describes the current SDL3 + OGPU/Metal architecture. Old
profiles remain useful only as historical baselines; implementation decisions
must be justified by measurements from the current native executable.

## Representative workload

The reference shattered result contains:

- 18,278 pieces;
- 278,368 triangles;
- 835,104 expanded render vertices.

Record the exact commit, release/development profile, display scale and refresh
rate, window visibility, OCaml/Dune versions, domain count, CPU/GPU model,
resident-memory pressure, and run duration with every new measurement. Never
compare results from different profiles as one series.

## Current optimization priorities

### P0: on-demand scheduling

The application lifecycle must distinguish continuous animation from static
presentation. An on-demand application should wait through the runtime-owned
SDL3 event path when it has no pending work.

Invalidations include:

- keyboard, pointer, text, drop, focus, expose, and resize events;
- drawable density or availability changes;
- camera movement and inertia;
- graph edits, parameter changes, selection, and workspace changes;
- asynchronous cook completion or failure;
- timeline playback and time-dependent cook context;
- watched-asset generations;
- explicit capture and export requests.

Asynchronous completion must wake the initial-domain loop through a bounded
runtime notification. Repeated idle polling is not the completed design.

Acceptance: after cooking and one final presentation, average process CPU over
60 seconds is below 1% on the reference machine, worker domains are blocked,
and no full scene rebuild or graph compilation occurs without invalidation.

### P1: bounded GPU-resident geometry

Stable packed meshes should produce Metal vertex/index buffers once per mesh
identity and device. Camera-only frames reuse those buffers. Cache eviction,
device loss, and runtime teardown release every associated resource after its
last completion-owned use.

Instrumentation must report:

- mesh-cache entries, hits, misses, builds, and evictions;
- uploaded bytes per frame and cumulatively;
- live Metal objects before and after teardown;
- retained-plan builds and hits;
- draw and primitive cardinality.

Acceptance: an unchanged mesh causes no repeated upload, the cache never
exceeds its declared capacity, and resize/attachment churn does not rebuild a
retained draw plan whose draw-bound resources are unchanged.

### P1: batch PXUI and graph geometry

Lower graph grids, wires, rounded widgets, outlines, paths, and icons to
batched OGPU geometry. Cache immutable presentation segments by document,
layout, viewport, theme, density, and selection identity. Hover and transient
interaction invalidate only affected segments.

Batching must preserve command order, nested clip/blend behavior, logical
coordinates, hit testing, text density, and documented antialias tolerances.
No second UI model or alternate renderer is introduced.

### P2: cache graph compilation and scene preparation

Cache `Procedural.Edit_graph.compile` by immutable document identity and
displayed-node compilation by document plus node ID. Keep 3D geometry, graph
presentation, inspector data, overlays, and transient status under separate
invalidation keys.

Every cache has an explicit capacity and ownership boundary. An optimization
must not turn immutable graph history into unbounded retention.

### P2: make cook parallelism explicit

The sketch and reactive cook must not expose contradictory domain controls.
Either propagate one documented setting or expose a clearly named
`cook_domains` override. Fixed inputs must produce byte-identical points,
vertices, primitives, attributes, groups, indices, and ordering with one and
multiple domains.

Domain count is a latency/power policy. Reducing it is not an algorithmic
speedup and must be reported separately from kernel improvements.

### P2: choose MSAA deliberately

Measure the dense viewport at supported sample counts. The scene's requested
sample count, render attachments, resolve path, and pipeline key must agree.
Static scheduling remains the primary idle optimization; a cheaper invalidated
frame is not a substitute for avoiding an unnecessary frame.

### P3: lazy media initialization

Silent applications should not initialize audio resources until an audio
operation requires them. Initialization and teardown remain inside the native
SDL3 lifecycle and return typed device errors.

## Correctness requirements

### Scheduling and interaction

- Pointer, keyboard, text, graph edits, camera changes, resize, and expose wake
  the loop without visible latency.
- Camera inertia and timeline playback schedule frames only while active.
- Cook completion and failure wake the UI without user input.
- Automated native runs arrange their own finite termination.

### GPU ownership

- All SDL3, Metal, texture, font, audio, event, and cache operations remain on
  the initial domain.
- Submitted resources remain alive until command completion.
- Replacement drawables and attachments do not become retained-plan owners.
- Cache eviction and runtime shutdown release every native object exactly once.
- More than the first presented frame is covered, including resize and capture.

### Determinism

- One-domain and multi-domain cooks have byte-identical ordered output.
- Fixed-clock native framebuffer captures remain exact where the specification
  promises exact pixels and within named tolerance elsewhere.
- Scheduling and cache-hit behavior do not change scene semantics.

### Memory and complexity

- Resident memory reaches a plateau in the release stability qualification.
- Mesh, plan, image, font, and pipeline caches remain within stated capacities.
- Hot geometry uses packed storage and amortized-linear builders.
- No render inner loop allocates per vertex, primitive, sample, or fragment.

## Benchmark procedure

Build the exact executable before sampling:

```sh
opam exec --switch=. -- dune build --profile release \
  sketches/shattered_cube/main.exe
```

Run the built artifact directly when a stable process identifier is needed:

```sh
_build/default/sketches/shattered_cube/main.exe
```

Capture at least the initial cook plus 60 seconds of settled behavior:

- cook wall/user/system time and domain utilization;
- frame median and p95 CPU/wall time;
- promoted/major allocations per frame;
- resident and peak memory;
- redraw, graph-compile, scene-build, upload, retained-plan, and cache counters;
- GPU command-buffer duration when supported by the device;
- native framebuffer hashes at fixed checkpoints.

For a performance-sensitive change, run at least five independent warmed
release samples and report the median of candidate medians plus the defined p95
aggregation. Interleave baseline and candidate executions when both artifacts
can be run under the same current native protocol.

The long-run native stability harness must include changing meshes, drawable
resize, image-generation churn, captures, completion draining, and full
teardown. Its report records source commit/profile, sample telemetry, bounded
cache state, native create/release deltas, final handle counts, and artifact
hash. Validate the report with its independent validator.

## Handoff order

1. Establish or refresh the current release benchmark and allocation baseline.
2. Implement on-demand scheduling and prove wake behavior.
3. Prove bounded GPU-resident mesh and retained-plan reuse.
4. Batch measured PXUI/graph hotspots.
5. Cache graph compilation and immutable scene fragments.
6. Clarify cook-domain and MSAA policy.
7. Run the focused native tests, complete release benchmark, long-run stability
   gate, full test suite, and documentation build.

Each significant implementation or evidence update is committed separately.
Claims such as “zero upload,” “linear,” “bounded,” or “production-ready” need
counter evidence, measurement, or code-level proof.
