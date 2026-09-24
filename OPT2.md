# PXUI Hyper-Performance Architecture Plan

## Status

This is the implementation plan for re-architecting PXUI and its graph-facing
integration around a retained, explicitly invalidated UI runtime inspired by
GPUI. It is not authorization to import Rust, embed GPUI, add a second window
runtime, or bypass Prismel's native Metal-only renderer.

The target is a small functional public API backed by a highly optimized native
runtime. Application state remains immutable where practical. The runtime may
use locally owned mutation, packed arrays, arenas, generation counters, and
bounded caches behind that API.

The migration is incomplete until the acceptance gates in this document pass
on the final integrated commit. A cached scene query, a high average FPS, or a
single low-allocation frame is not completion evidence.

## Executive decision

Adopt GPUI's useful architectural properties, not its Rust-specific object
model:

- stable retained state and element identity across frames;
- explicit notification and coalesced invalidation;
- distinct reconcile, layout, prepaint, paint, and composition phases;
- transient element construction in resettable frame arenas;
- element-local retained state keyed by stable identity;
- event-driven frame scheduling;
- direct production of compact GPU-oriented paint data.

Combine those properties with lessons from Masonry and Flutter:

- mutations declare whether they dirty structure, layout, hit testing, paint,
  composition, text, or accessibility;
- dirty state propagates only to an appropriate boundary;
- independent repaint/display-list boundaries isolate frequently changing
  regions;
- a persistent runtime tree survives disposable declarative descriptions.

Do not adopt pure immediate mode as the core. Egui demonstrates that it can be
simple and responsive, but full layout and tessellation on every active frame
is the wrong default for Prismel's large inspectors and SOP graphs. Immediate
builders remain acceptable as a convenient way to produce a declarative spec;
they must reconcile into retained runtime nodes before hot-path interaction.

## Evidence baseline

### Host and workload

Measurements below were taken on 2026-08-30 on the current Apple M1 host with
OCaml 5.3.0, Dune 3.20.2, the release profile, one cook domain, and the exact
shattered-cube result:

- 18,278 pieces;
- 278,368 triangles;
- 835,104 expanded render vertices;
- 1200x760 logical and drawable pixels, scale 1.

The native benchmark commands are:

```sh
PRISMEL_RENDERER_BENCH_WARMUP=2 \
PRISMEL_RENDERER_BENCH_SECONDS=8 \
PRISMEL_BENCH_PROFILE=release \
opam exec --switch=. -- dune exec --profile release \
  tools/bench_shattered_renderer.exe -- visible

PRISMEL_RENDERER_BENCH_WARMUP=2 \
PRISMEL_RENDERER_BENCH_SECONDS=8 \
PRISMEL_BENCH_PROFILE=release \
opam exec --switch=. -- dune exec --profile release \
  tools/bench_shattered_renderer.exe -- hidden
```

### Current renderer result

The visible five-run candidate records a median 62.82 FPS, 15.73 ms median
frame, 19.06 ms p95, 24.34 ms p99, and approximately 1.24 MB allocated per
frame. This is materially better than the original 29 FPS screenshot, but the
p95 misses a strict 16.67 ms frame envelope and the allocation rate remains too
high for a stable real-time UI.

The renewed hidden-UI diagnostic produced:

| Metric | Result |
| --- | ---: |
| frames | 942 |
| duration | 8.006 s |
| FPS | 117.66 |
| median | 8.39 ms |
| p95 | 10.17 ms |
| p99 | 11.28 ms |
| allocated | 52,851,640 bytes |
| allocation/frame | 56,104 bytes (54.8 KiB) |
| promoted/frame | 127 bytes |
| CPU | 17.38% |

The previously quoted 166 KiB/frame hidden result is obsolete. The current
54.8 KiB/frame result is reasonable for many managed applications, but it is
not the hyper-optimized target. At 60 FPS it still creates about 3.2 MiB/s of
short-lived allocation, and allocation sampling shows avoidable UI work even
while UI presentation is hidden.

The top sampled hidden-path allocation sites include `Bytes.make`,
`Array.to_list`, `Mat4.of_rows`, `Array.init`, `Pxui.displayed_widgets`,
`Pxui.set_slider_value`, Scene command builders, and Scene3 preparation. Hidden
mode therefore suppresses presentation but does not fully suppress UI model,
layout, and inspector work.

### Dedicated PXUI scale result

`tools/bench_pxui.exe` exposes a more serious interaction defect. A memoized
scene query is cheap, but dragging the last slider scales approximately
quadratically:

| widgets | drag median | drag allocation |
| ---: | ---: | ---: |
| 10 | 0.017 ms | 145,544 B |
| 100 | 1.284 ms | 9,293,864 B |
| 250 | 7.713 ms | 56,221,064 B |
| 500 | 132.388 ms | 222,433,064 B |
| 1,000 | 532.342 ms | 884,857,064 B |

The 1,000-widget cached `Pxui.scene` query itself allocates only 96 bytes. This
means the existing whole-scene memo is effective for one narrow case while the
interaction and derived-layout architecture remains unsuitable for scale.

The immediate cause is repeated derivation. `displayed_widgets` rebuilds an
array, `layout` asks `scrollable`, `scrollable` asks `max_scroll`, and those
paths recalculate displayed widgets. Hit testing and layout call that chain
inside traversal. Updating one widget then uses `List.mapi` over the reversed
widget list. The result combines repeated O(n) work into O(n^2) time and
allocation for a single pointer gesture.

## Research basis

Research was performed against primary project documentation and source on
2026-08-30.

### GPUI

GPUI uses an application-owned entity store and observable `Entity<T>` handles.
Entity contexts can notify observers and windows, which makes invalidation
explicit rather than inferred from whole-value comparison. Its `Element` path
separates `request_layout`, `prepaint`, and `paint`. Dynamically typed elements
are allocated from an element arena and cleared after drawing. Element IDs
allow state to persist across frames even when transient element descriptions
are rebuilt.

Relevant sources:

- <https://github.com/zed-industries/zed/blob/main/crates/gpui/docs/contexts.md>
- <https://github.com/zed-industries/zed/blob/main/crates/gpui/src/element.rs>
- <https://github.com/zed-industries/zed/blob/main/crates/gpui/src/window.rs>

Prismel should adopt explicit invalidation, stable element identity, separated
passes, and frame arenas. It should not adopt GPUI's global application entity
API wholesale: Prismel's immutable sketch model and typed update loop are
valuable public semantics, and SDL/Metal work must remain on the initial domain.

### Masonry and Xilem

Masonry owns a persistent widget tree and performs separate event, animation,
update, layout, compose, paint, and accessibility passes. Mutations go through
a wrapper that propagates the required metadata when mutation ends. Its pass
system is a useful model for making dirty effects explicit and testable.

Relevant sources:

- <https://github.com/linebender/xilem/blob/main/ARCHITECTURE.md>
- <https://github.com/linebender/xilem/blob/main/masonry/ARCHITECTURE.md>
- <https://github.com/linebender/xilem/blob/main/masonry/masonry_core/src/doc/pass_system.md>

Prismel should adopt typed dirty effects and pass-specific traversal. It should
not import a general Rust widget tree, Vello, Winit, or any alternate backend.

### Flutter

Flutter reconciles disposable immutable widgets into a persistent element and
render-object tree. Layout and paint dirtiness propagate separately. Repaint
boundaries retain independent display lists so a changing subtree does not
force unrelated content to repaint.

Relevant sources:

- <https://docs.flutter.dev/resources/architectural-overview>
- <https://api.flutter.dev/flutter/rendering/RenderObject/markNeedsPaint.html>
- <https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html>

Prismel should adopt persistent runtime nodes and explicit layout/paint
boundaries. It should not copy Flutter's object-heavy allocation model or add a
second compositing engine.

### Egui

Egui is immediate-mode and normally performs a full UI pass on every requested
frame. Its own documentation identifies large scroll areas and full per-frame
layout as CPU costs, and recommends virtualization and profiling. It also only
repaints on interaction or animation.

Relevant sources:

- <https://github.com/emilk/egui>
- <https://github.com/emilk/egui/blob/main/ARCHITECTURE.md>
- <https://github.com/emilk/egui/blob/main/crates/egui/src/lib.rs>

Prismel should retain the ergonomic direct builder style where useful, reuse
buffers, virtualize large collections, and schedule on demand. It should not
make full layout and tessellation mandatory on every active frame.

### Slint

Slint's runtime stores component items and properties in compact regions and
uses property dependency tracking and list virtualization. The relevant lesson
is data-oriented storage and generated/compiled structure, not its DSL or its
software/OpenGL renderer options.

Relevant source:

- <https://github.com/slint-ui/slint>

Prismel should consider packed runtime node/property tables. It must not add a
UI DSL requirement, code generator dependency, or alternate renderer.

## Current architecture map

### Public construction

`lib/pxui/pxui.ml` stores widgets in a reversed linked list. Functional
builders copy the `t` record and prepend one widget. Compatibility builders
mutate the same representation. An optional ordered array memoizes one list
reversal. Widget names are strings and also serve as interaction identity.

This is inexpensive while constructing a small panel, but a linked list is the
wrong hot representation for indexed interaction, replacement, visibility,
layout, and repeated traversal.

### Derived layout

Visible accordion filtering, row numbering, content height, scrolling,
per-widget layout, input-region extraction, hit testing, and scene generation
are separate queries without one authoritative cached layout snapshot. Several
queries call one another and rebuild arrays. Layout uses heap-allocated records
for displayed rows and bounds.

### Interaction

Events are folded through a complete immutable `t`. Hit testing often scans
visible widgets, and updates rewrite the entire widget list with `List.mapi`.
Names and emitted changes allocate strings/tuples on hot paths. Hover and drag
state live at panel level, so the whole scene cache invalidates when one control
changes.

### Painting

Every widget creates ordinary `Scene.node` lists. Shapes become separate scene
nodes; nested `@`, `List.concat`, `Array.to_list`, and list reversal assemble
the result. Whole-panel scene caching avoids this only when every compared
field is unchanged. A hover, active state, composition edit, scroll, or widget
list replacement invalidates the complete panel.

### Graph UI

`lib/pxui_graph/pxui_graph.ml` already uses arrays for boxes and edges and
culls drawing by viewport, but it still:

- builds temporary lists and arrays for node views, selection, menus, wires,
  and scene nodes;
- scans all nodes or edges for several hit tests;
- recomputes visibility and edge bounds by full traversal;
- copies the entire box array while moving nodes;
- uses persistent `Set.Make(Int)` for hot selection membership;
- invalidates one whole cached graph scene on pan, zoom, hover, selection,
  dragging, or menu change;
- CPU-transforms graph coordinates into screen coordinates instead of retaining
  graph-space geometry plus one root transform.

### Sketch UI host

`lib/sketch_ui/sketch_ui.ml` composes workspace, graph, inspector, camera, and
status scenes as lists. It has begun isolating the dynamic status strip, but
visibility is not yet a complete work-suppression boundary. Inspector and UI
state can still be derived while presentation is hidden.

### Scene and renderer handoff

`Scene.Private.stage_native` traverses nested scene lists into render commands
and ordered layers. `Prismel_next_execution` fingerprints, resource-scans,
lowers, caches, and eventually flattens layer batches into draw lists.
`Scene_execution` validates and reconstructs resources and render payloads.
Stable results are cached at multiple layers, but each cache uses a different
structural representation, so a frame still pays for intermediate allocation
before discovering that native work can be reused.

## Gap register

### G1: no stable integer widget identity

String names are API labels, state keys, event payloads, and lookup identity.
There is no generation-checked `Widget_id`, no O(1) slot lookup, and no explicit
parent/child identity. This prevents local dirty propagation and safe retained
state.

### G2: no persistent runtime tree

The public widget list is simultaneously declaration, state store, layout
input, interaction database, and paint source. A new value cannot be cheaply
reconciled into stable nodes because no separate runtime representation exists.

### G3: coarse invalidation

Whole-record snapshots infer changes after the fact. There are no dirty flags
for structure, layout, hitboxes, text, paint, composition, or accessibility.
A one-pixel hover change can rebuild an entire inspector scene.

### G4: repeated derived data

Displayed rows and layout are recalculated by multiple queries. The 1,000
widget drag proves quadratic behavior. This is a correctness-level performance
defect, not a tuning opportunity.

### G5: linked-list hot storage

Indexed replacement is O(n) and allocates O(n). Lists are repeatedly converted
to arrays and back. Persistent sets and polymorphic comparisons are used where
packed integer arrays, bitsets, or generation tables are appropriate.

### G6: no frame arena

Bounds, layouts, scene nodes, lists, tuples, strings, command arrays, and draw
payloads become individually managed OCaml allocations. Scratch capacity is
not centrally measured or reused.

### G7: paint output is too high-level for the hot path

PXUI constructs general-purpose Scene trees only for Prismel to flatten them
again. The renderer cannot retain a stable UI display-list segment before the
allocation has already occurred.

### G8: text changes invalidate too much

Formatted slider values, FPS, composition cursors, and graph labels create new
strings and text nodes. Glyph texture caching helps native resources but does
not eliminate string formatting, shaping lookup, scene assembly, or command
allocation.

### G9: graph interaction lacks spatial indexing

Full node/edge scans and copied arrays do not scale to production SOP networks.
Viewport culling during painting does not make pointer hit testing or selection
queries sublinear.

### G10: scheduling and invalidation are not one contract

The runtime can render continuously even when only static retained UI exists.
Conversely, background cook completion, cursor blink, animation, and watched
assets need typed wakeups. Rendering avoidance and render efficiency must be
designed together.

### G11: cache ownership is fragmented

PXUI scene caches, Scene geometry caches, Scene2 lowering caches, retained
plans, text caches, native descriptors, and renderer payload caches do not
share one identity/generation contract. Structural hashing and equality are
paid repeatedly.

### G12: instrumentation is end-to-end but not pass-local

The shattered renderer benchmark reports total allocation and frame time, but
there are no standard counters for reconcile/layout/prepaint/paint/flatten/
lower/submit work, dirty-node counts, arena high-water marks, spatial-query
candidates, or display-list reuse.

### G13: hidden UI does work

The hidden Memprof sample still reports `Pxui.displayed_widgets` and
`Pxui.set_slider_value`. Visibility currently changes scene composition, but it
does not guarantee that all graph, inspector, layout, and paint work is skipped.

### G14: accessibility semantics are not represented as a pass

Focus and text input metadata exist, but a retained UI architecture must reserve
stable identity and dirty propagation for accessibility rather than forcing a
future parallel tree or full rebuild.

## Target architecture

### 1. Declarative spec and retained runtime

Split the current `Pxui.t` responsibilities:

```text
immutable application model
        |
        v
Pxui.Spec.t  -- reconcile -->  Pxui.Runtime.t
                                  |
             events/invalidation | retained stable nodes
                                  v
             layout -> prepaint -> packed display-list segments
                                  |
                                  v
                    Prismel native Scene2 submission
```

`Pxui.Spec.t` is cheap declarative input. Existing builders initially produce
this spec through a compatibility facade. `Pxui.Runtime.t` is an explicitly
owned, initial-domain object with stable node slots, interaction state, caches,
and scratch storage. The runtime is destroyed with its Sketch UI owner before
the native renderer.

The host reconciles only when the spec generation changes. Pointer movement,
dragging, focus, cursor blink, and scrolling update retained runtime state
directly and do not rebuild the declarative spec.

### 2. Stable IDs and generations

Use a compact generation-checked identity:

```ocaml
type widget_id = private { slot : int; generation : int }
```

Externally stable keys map to IDs during reconciliation. Integer IDs are used
after that boundary. String widget names remain compatible public command keys
but are interned or mapped once; they are not repeatedly hashed during layout,
hit testing, or painting.

Every runtime owns monotonically increasing generations for:

- structure;
- style/theme/density;
- layout;
- hitboxes;
- text/glyph runs;
- paint;
- composition/transform;
- accessibility;
- resource bindings.

Generations are checked without polymorphic hashing. Wraparound must either be
proved impossible for the runtime lifetime or trigger a bounded full reset.

### 3. Packed node store

Use integer-indexed, geometrically growing arrays with an explicit live length.
Prefer structure-of-arrays for hot planes:

- `kind : int array` or bytes;
- `parent`, `first_child`, `next_sibling`, `depth`, `z_order : int array`;
- `flags` and dirty bits in bytes/bitsets;
- `x`, `y`, `width`, `height`, clip and baseline in numeric arrays;
- numeric control values in `float array` and `int array`;
- stable text/property handles in arrays;
- generation and free-list planes in integer arrays.

Cold or variable payloads may live in a bounded side table keyed by slot. Do
not force all widget variants into one boxed mega-record, and do not put a
million-element hot buffer in lists. Capacity growth is geometric and measured;
arrays never shrink during ordinary frames. Explicit compaction is a cold,
bounded operation.

### 4. Typed dirty effects

Every mutation returns or applies a bitset such as:

```text
Structure | Layout | Hitboxes | Text | Paint | Compose | Accessibility
```

Rules are explicit and tested:

- hover: paint only for old and new hovered nodes;
- press/release: paint for the active node, command emission on release;
- slider drag: value/text/paint for one node, no structure or global layout;
- scroll: composition plus visible-range/hitbox update, not child repaint;
- panel resize: layout boundary and dependent hitboxes/paint;
- theme/density/font change: style, text, layout where metrics change, paint;
- graph pan/zoom: root composition and spatial visibility, not per-node
  geometry reconstruction;
- accordion toggle: local structure visibility, downstream row layout, hitboxes,
  and affected paint segments;
- hidden UI: no layout, paint, or text work until shown, except explicitly
  required state changes.

Dirty nodes are held in reusable integer queues with membership bitsets. A node
is enqueued at most once per pass. Multiple writes before a frame coalesce.

### 5. Pass pipeline

The initial-domain UI runtime runs these passes only when dirty:

1. **Reconcile** maps a changed spec into existing stable nodes, creates and
   destroys slots, and emits exact dirty effects.
2. **Event dispatch** queries retained hitboxes/spatial indexes and mutates only
   targeted runtime state.
3. **Style resolution** recomputes inherited/derived style for dirty subtrees.
4. **Layout** measures and places dirty layout boundaries.
5. **Prepaint** commits hitboxes, clips, focus/IME regions, visible ranges, and
   repaint-boundary ownership.
6. **Paint** rewrites only dirty display-list segments into reusable buffers.
7. **Compose** applies root/subtree transforms, clips, opacity, and ordered
   segment references.
8. **Submit** passes stable segment identities and generations to Prismel's
   checked native lowering.

Pass ordering is a contract. Re-entrant mutation is queued for the next legal
phase. No callback may mutate arrays while a pass iterates them without an
explicit command queue.

### 6. Layout snapshots and boundaries

One layout pass produces the authoritative snapshot used by painting and hit
testing. `content_height`, visible rows, scrolling limits, row bounds, control
bounds, clips, and baselines are stored, not recomputed by query chains.

For today's vertical inspector, use an arithmetic fixed-row layout with
prefix/range metadata for accordions. Only visible rows need paint and hitbox
records. Variable-height or nested layouts later use packed child ranges and
prefix sums/Fenwick trees when measurements prove the need.

Layout dirtiness propagates to the nearest relayout boundary. Candidate
boundaries are workspace columns, graph viewport, inspector panel, menu/popup,
status strip, and independent scroll containers.

### 7. Hit testing and event routing

Prepaint writes packed hitboxes containing bounds, node ID, z-order, event mask,
cursor, and optional text-input metadata. Small panels may scan the visible
hitbox slice backwards. Large surfaces use a packed uniform grid or bounded
BVH chosen by benchmark; the interface must hide the implementation.

Pointer capture stores a generation-checked widget ID. Move and release events
route directly to the captured node. Hover transitions compare old and new IDs
and dirty at most two nodes. Keyboard and IME events route through the focus ID.
Destroyed IDs are rejected without falling back to string lookup.

### 8. Frame arena and scratch ownership

Introduce a UI frame arena made of reusable typed buffers, not a general unsafe
allocator. Each buffer has capacity, live length, high-water counter, and a
documented maximum. Reset sets lengths to zero; it does not release backing
storage.

Arena candidates include:

- dirty queues;
- visible-node indices;
- hit-test candidates;
- layout work stack;
- paint segment references;
- transient text formatting bytes;
- command/draw staging slots;
- resource-stamp scratch;
- event and emitted-change buffers.

Buffers containing resource-owning values require explicit clearing or scoped
leases before reset. Arena memory must not retain old documents, strings,
textures, fonts, callbacks, or native handles accidentally.

### 9. Packed display lists

PXUI must stop constructing general nested Scene lists for every dirty region.
Add a narrow renderer-neutral 2D display-list boundary owned by Prismel, with
PXUI as a producer and Prismel/OGPU as the sole native consumer.

The representation uses packed arrays or bytes for:

- solid quads and rounded rectangles;
- line/path geometry references;
- image/glyph quads;
- transform and clip stack operations;
- blend changes;
- hit/IME metadata kept outside GPU command bytes;
- stable resource IDs and generations.

Each repaint boundary owns ordered segments with stable IDs and versions. An
unchanged segment reaches native submission by identity/version without
rehashing vertices, rescanning resource IDs, rebuilding Scene nodes, or
flattening lists. Segment caches are bounded by entry count and bytes and use
completion-owned native lifetimes.

This is not a PXUI renderer. It is a compact command/value extraction inside
Prismel's existing native renderer boundary, consistent with the Metal-only
architecture.

### 10. Geometry batching

Batch compatible primitives while preserving exact painter order, clip,
transform, and blend semantics. Pre-size known output cardinality. Variable
paths use geometric-growth buffers and materialize once.

Static widget chrome is retained by segment. Dynamic controls update a small
vertex/color range or a compact per-instance record. Prefer one canonical quad
mesh plus instance/uniform data for rectangles, tracks, fills, and glyphs when
the existing OGPU pipeline can validate it without per-widget draw calls.

No inner loop may use `@`, `List.concat`, `Array.append`, repeated
`Array.to_list`, `List.nth`, or a boxed `Option` per primitive.

### 11. Text system

Separate text value identity, shaping/layout, atlas residency, and paint
placement. Intern stable labels within a runtime with bounded ownership.
Dynamic numeric labels use reusable formatting buffers and only publish a new
text generation when visible bytes change.

Cache shaped glyph runs by font identity/generation, density, size, content,
and shaping options. Keep the existing bounded renderer texture ownership.
Scrolling or root transforms should move retained glyph runs without reshaping.
Empty text remains a no-op.

### 12. Graph specialization

`pxui_graph` remains a presentation adapter over immutable
`Procedural.Edit_graph`; it does not become graph authority. Its runtime uses:

- packed node and edge tables keyed by node ID;
- an ID-to-slot integer hash table rebuilt only on document changes;
- selection bitsets plus a compact selected-ID vector;
- graph-space node bounds retained across pan/zoom;
- one root transform for pan/zoom composition;
- a packed spatial grid/BVH for visible nodes and pointer queries;
- edge bounding boxes and cell membership for candidate rejection;
- visible index buffers reused per frame;
- separate static grid, wires, ordinary nodes, selected nodes, drag overlay,
  and menu display-list segments;
- virtualized menu rows and large inspector collections.

Moving k selected nodes copies or updates O(k) position entries, not the full
node array. Pan/zoom cost is O(visible nodes + visible edge candidates) until a
GPU/root-transform path makes static geometry reuse possible. Hit testing must
not scan all graph edges.

### 13. Scheduling

The UI runtime exposes one typed invalidation result to Sketch UI:

```text
Idle | Needs_frame | Animate_until of time | Awaiting_external_wakeup
```

Input, resize, focus, cook completion, timeline changes, watched assets, text
cursor deadlines, and camera inertia feed this contract. Multiple invalidations
coalesce before the next frame. Static UI must not maintain a polling loop.

Background domains may prepare immutable application data only. Reconciliation,
layout state, hitboxes, text atlas access, paint buffers, renderer resources,
and native submission remain on the initial domain.

### 14. Accessibility and diagnostics

Stable widget IDs also key semantic nodes. Accessibility dirtiness is separate
from paint dirtiness. Focus, labels, values, bounds, enabled state, and actions
must remain consistent with the committed layout snapshot.

Every runtime exposes counters without allocating on the measured frame:

- live/capacity/high-water nodes;
- dirty count per pass;
- nodes visited per pass;
- layout and paint boundary hits/misses;
- visible/culled widgets and graph nodes/edges;
- hit-test candidates;
- display-list builds/reuses/bytes;
- arena capacities/high-water marks/growth events;
- text shape/cache/atlas hits and misses;
- renderer plan hits/misses and uploaded bytes;
- submitted segments, draws, passes, and native descriptors;
- allocation, promoted bytes, RSS, CPU, and frame percentiles.

## Performance budgets

Budgets are release-profile gates on the reference M1 unless a newer committed
baseline explicitly supersedes them. Each timing gate uses at least five
interleaved samples after warmup. Allocation/cardinality gates may be strict;
timing gates include machine context and broad variance limits.

### Idle

- An unchanged, non-animating workspace presents no frames after settling.
- Average process CPU over 60 seconds is below 1%.
- UI passes visit zero nodes without invalidation.
- No UI, Scene, lowering, or submission allocation occurs while blocked.

### Continuous hidden Scene3 workload

- Interim: at most 16 KiB allocated/frame.
- Final: at most 4 KiB allocated/frame attributable to UI + Scene staging.
- Promoted allocation is at most 256 B/frame.
- Hidden UI performs zero reconcile/layout/prepaint/paint work.
- No RSS growth after warmup beyond a documented bounded jitter envelope.

The current 54.8 KiB/frame fails the interim allocation target even though it
is acceptable for many ordinary applications.

### Unchanged visible workspace

- Interim: at most 64 KiB allocated/frame end to end.
- Final: at most 8 KiB allocated/frame end to end.
- UI-specific passes allocate at most 2 KiB/frame after arena warmup.
- No stable display-list segment is rebuilt, rehashed, or rescanned.
- 60 Hz qualification: median and p95 at or below 16.67 ms at scale 2.
- 120 Hz diagnostic: median below 8.33 ms where display pacing permits.

### Interaction

- A slider pointer-move update is O(1) in total panel widget count.
- 1,000-widget three-event drag: below 1 ms median and 64 KiB total allocation
  interim; below 250 microseconds and 8 KiB final after warmup.
- Hover transition dirties at most two nodes and rebuilds at most two paint
  segments.
- Scrolling cost is O(visible rows), with no allocation proportional to total
  rows.
- Accordion toggle is O(affected visible suffix) for fixed rows and performs no
  work for collapsed descendants beyond range metadata.

### Graph

- 10,000 nodes / 20,000 edges can remain loaded with bounded storage.
- Pan/zoom/hit testing is independent of total graph size except spatial-index
  candidate count and visible output.
- Pointer query p99 is below 250 microseconds with fewer than 128 candidates on
  the reference synthetic graph.
- Moving k nodes is O(k + affected edges), not O(total nodes).
- Sequential and multi-domain graph document preparation is exact; UI runtime
  mutation itself remains initial-domain only.

### Memory

- Every cache and arena has entry and byte capacities.
- Warmed capacity is reused for at least 100,000 interaction frames with no
  monotonic RSS, handle, or cache growth.
- Closing the Sketch UI releases fonts, textures, display lists, spatial
  indexes, arenas, and native retained plans before renderer teardown.
- Peak cook memory is reported separately from steady UI memory.

## Milestones

### M0: freeze semantics and improve measurement

Deliverables:

- capture exact screenshots, scene-command order, hit results, focus/IME traces,
  and emitted changes for every widget;
- extend `bench_pxui` with build, reconcile-no-change, scene-hit, hover,
  press/release, drag, scroll, focus, text, accordion, and destruction lanes;
- output JSON with wall time, CPU, allocated/minor/promoted/major bytes, live
  heap, RSS, widget count, visible count, pass counters, and output cardinality;
- add logarithmic scale sweeps (10, 100, 1k, 10k) and an automated exponent
  check that rejects superlinear slider interaction;
- add a graph benchmark with 100, 1k, and 10k nodes and controlled visible
  fractions;
- retain the Memprof mode and record full call-stack attribution by phase;
- measure scale 1 and scale 2 separately.

Exit gates:

- benchmarks reproduce the current 1,000-widget quadratic failure;
- fixtures cover all public widgets and graph gestures;
- counters themselves allocate no more than a fixed documented amount;
- baseline source commit, host, compiler, profile, and raw reports are recorded.

### M1: eliminate accidental quadratic PXUI queries

This is a prerequisite safety fix, not the final architecture.

Deliverables:

- compute `displayed_widgets`, content height, scroll range, and row/control
  bounds once per authoritative layout snapshot;
- make hit testing consume that snapshot;
- stop recursively deriving visible widgets through `layout -> scrollable`;
- replace target-last `List.mapi` update with an indexed compatibility store or
  one cached index-to-list position strategy until M2 lands;
- add complexity and allocation assertions.

Exit gates:

- 1,000-widget drag is demonstrably O(n) or better and below 2 MB allocation;
- no output or interaction semantics change;
- cached scene query remains bounded.

M1 must not become a reason to stop before the retained runtime migration.

### M2: introduce stable IDs and packed runtime storage

Deliverables:

- implement generation-checked widget IDs;
- implement geometrically growing packed node/property arrays;
- add free-slot reuse with stale-ID rejection;
- map existing string names to IDs at reconcile/creation time;
- keep public constructors source-compatible through a facade;
- add exact storage-capacity and 100k create/delete/reuse tests.

Exit gates:

- indexed lookup/update is O(1);
- stale IDs cannot affect reused slots;
- node storage remains bounded and releases cold payloads;
- one-domain behavior matches frozen fixtures.

### M3: declarative spec reconciliation

Deliverables:

- separate immutable `Spec` from owned `Runtime`;
- define stable explicit keys and deterministic positional fallback keys;
- reconcile keyed children without polymorphic whole-tree hashing;
- preserve focus, active drag, scroll, numeric edit, and element-local state
  across compatible spec changes;
- cancel or retarget state safely when keyed nodes disappear;
- coalesce multiple model changes before one reconcile.

Exit gates:

- identical spec performs zero node mutation and bounded near-zero allocation;
- one changed value touches one runtime node;
- insertion/reordering preserves keyed state exactly;
- public compatibility tests pass.

### M4: typed dirty propagation and pass scheduler

Deliverables:

- implement dirty bitsets, integer work queues, and membership bitsets;
- codify mutation-to-dirty-effect rules;
- implement reconcile/style/layout/prepaint/paint/compose phase ordering;
- reject illegal re-entrant mutation or queue it deterministically;
- integrate invalidation output with Sketch UI scheduling.

Exit gates:

- hover visits at most old/new nodes in paint after hit testing;
- slider drag performs no structure/global-layout pass;
- three writes before a frame schedule one pass per affected node;
- hidden runtime schedules no visual passes.

### M5: retained layout engine

Deliverables:

- implement fixed-row inspector layout snapshots first;
- add relayout boundaries and dependency propagation;
- store bounds/baselines/clips/visible ranges in packed planes;
- make scroll composition separate from child paint;
- add virtualization for large panels and menus;
- define extension points for variable-height/flex/grid layout only when needed.

Exit gates:

- layout, paint, and hit testing consume exactly one snapshot generation;
- scrolling visits O(visible rows);
- 10k-row panel remains bounded and interactive;
- resize, density, and font metric changes invalidate exact dependents.

### M6: retained hit testing, focus, and input routing

Deliverables:

- build packed hitboxes in prepaint;
- route pointer capture and focus through stable IDs;
- implement visible-slice scan and graph spatial-query backends;
- keep IME regions synchronized to committed layout;
- eliminate hot string lookup and per-event list construction;
- reuse emitted-change buffers, materializing public lists once at the boundary.

Exit gates:

- pointer move without hover transition allocates zero UI heap after warmup;
- captured drag routes O(1);
- stale/destroyed capture and focus are rejected deterministically;
- event traces and Retina logical coordinates match frozen behavior.

### M7: packed Prismel 2D display-list boundary

Deliverables:

- specify renderer-neutral packed commands and segment identity/version;
- add checked builders with capacity planning and geometric growth;
- preserve exact clip/transform/blend/order semantics;
- keep resource resolution typed and generation-checked;
- adapt ordinary Scene2 and PXUI through one native lowering authority;
- prohibit raw native pointers and backend imports in PXUI.

Exit gates:

- pixel and command-order parity passes for every widget and nested state;
- stable segment bypasses Scene-list reconstruction and structural rehash;
- buffers and resource leases remain bounded through 100k frames;
- dependency-direction and native-only gates pass.

### M8: repaint boundaries and incremental paint

Deliverables:

- define boundaries for workspace, graph layers, inspector, popups, and status;
- retain independent display lists by stable segment ID/generation;
- rewrite only dirty segment ranges;
- collect usefulness counters for symmetric/asymmetric invalidations;
- merge or split boundaries based on measurements rather than intuition.

Exit gates:

- status/FPS change rebuilds only status;
- slider change rebuilds only the control/value segment;
- graph selection does not rebuild grid or unrelated nodes;
- unchanged visible workspace performs zero paint builds.

### M9: text and glyph-run retention

Deliverables:

- add stable text value handles and bounded interning;
- cache shaping/layout independently from atlas textures;
- reuse numeric formatting buffers;
- retain glyph-run geometry across translation/scroll;
- preserve density-aware rerasterization, font mutation invalidation, explicit
  `Font.cached_text` ownership, and empty-text semantics.

Exit gates:

- unchanged labels perform no formatting/shaping/allocation;
- slider values update only when displayed bytes change;
- rapid text edits remain bounded and visually exact at scale 1/2;
- font/cache teardown leaves no live native resources.

### M10: graph runtime and spatial indexes

Deliverables:

- migrate boxes, edges, selection, visible sets, and positions to packed stores;
- add measured uniform-grid/BVH indexing;
- use graph-space retained geometry with root composition transform;
- split display lists into stable graph layers;
- virtualize menu/search results and avoid repeated lowercase/string ranking;
- update only affected edges when nodes move.

Exit gates:

- 10k/20k synthetic graph meets query and memory budgets;
- output order, selection, editor requests, and immutable document authority are
  unchanged;
- pan/zoom work scales with visible/candidate cardinality;
- graph caches have explicit byte and entry bounds.

### M11: renderer submission arrays and retained segments

Deliverables:

- remove per-frame layer flattening through `List.rev_append`;
- replace draw/payload/resource list assembly with reusable arrays and live
  lengths;
- carry stable segment identity/version through Scene execution;
- retain validation results where all validated inputs and generations match;
- update only dynamic uniform/instance ranges;
- keep completion-owned resources and descriptor caches bounded.

Exit gates:

- stable UI submission allocates within final budget;
- changed segment does not invalidate unrelated native payloads;
- device/resource/command validation failures remain atomic;
- R9 upload and R12/O6 lifetime lanes pass on renewed evidence.

### M12: hidden-work elimination and on-demand scheduling

Deliverables:

- stop inspector/graph layout and paint passes when hidden;
- preserve only application state changes required for later reconciliation;
- wake on typed invalidations and block when idle;
- schedule cursor blink/animation deadlines without continuous polling;
- wake on asynchronous cook completion through the runtime-owned bounded path.

Exit gates:

- hidden workload meets 16 KiB interim and 4 KiB final UI/Scene allocation;
- settled static workspace stays below 1% CPU for 60 seconds;
- showing UI reconciles once with no stale focus, layout, or graph state;
- all automated loops terminate explicitly.

### M13: API migration and deletion

Deliverables:

- migrate PXUI widgets, `sop_ui`, `pxui_graph`, and `sketch_ui` by vertical
  slice, retaining source behavior;
- update public API tests and `specification/backend.md` for boundary changes;
- delete the old list-based scene builder, duplicate layout queries, whole-scene
  cache, and compatibility storage after parity is proven;
- do not leave permanent old/new fallback implementations;
- renew the stable API manifest deliberately for reviewed changes.

Exit gates:

- one authoritative runtime and paint path remains;
- no old fallback can be selected;
- examples and sketches use the retained runtime through ordinary public APIs;
- dependency direction remains exact.

### M14: final qualification

Deliverables:

- five interleaved release samples for visible/hidden, scale 1/2, idle,
  interaction, large panel, and large graph scenarios;
- exact one-domain/multi-domain preparation comparisons where parallel work is
  permitted;
- 30-minute changing-content/resize/capture/text/graph stress;
- 100k interaction and create/destroy cycles;
- native handle, descriptor, cache, arena, RSS, allocation, upload, and frame
  percentile evidence;
- twice-clean `@all`, `runtest`, finite native suites, generated drift checks,
  and installation on the final commit.

Exit gates:

- every performance budget in this document is met or replaced by a committed,
  measured, explicitly reviewed budget;
- all visual, interaction, ownership, and architecture gates are green;
- `NEW_GPU_STUFF.md` R9/R10/R12/O6 evidence is renewed on the same source;
- no claim relies on a dirty tree, shortened run, or scale-1 proxy for Retina.

## Vertical implementation order

Avoid a big-bang rewrite. Implement end-to-end slices that each replace an old
authority:

1. label and button through retained node/layout/hit/paint/submission;
2. toggle and slider, including captured drag and dynamic value text;
3. text field, IME, focus, composition, and cursor deadline;
4. accordion and virtualized inspector layout;
5. choice/range/XY and all remaining PXUI controls;
6. graph grid and one node/wire layer;
7. full graph interaction/menu/selection;
8. workspace/status/camera composition;
9. delete old storage and Scene-building path.

Each slice must have pixel, event, allocation, cardinality, ownership, and
teardown evidence before the old implementation is removed for that slice.

## Data-structure decisions

### Required

- geometric-growth arrays with explicit live lengths;
- packed integer IDs and generation planes;
- byte/bitset flags and membership sets;
- integer dirty queues and work stacks;
- compact selected/visible vectors;
- specialized integer hash tables only at cold ID-mapping boundaries;
- packed spatial index nodes/cells;
- pre-sized primitive/instance buffers;
- bounded LRU or clock caches with explicit byte accounting;
- reusable formatting and command buffers.

### Prohibited in measured hot paths

- linked-list indexed updates;
- repeated list/array conversion;
- `List.nth`, repeated `List.length`, `@`, nested `List.concat_map`, or
  `Array.append`;
- polymorphic hash/compare over complete widgets, commands, or geometry;
- fresh `Hashtbl` creation per frame/query;
- boxed options per visible node/primitive;
- string keys after reconciliation;
- full graph scans for local pointer queries;
- unbounded interning, arenas, display lists, spatial indexes, or text caches;
- cache hits that are discovered only after rebuilding the cache input.

### Conditional

Bigarray is appropriate for native-facing packed numeric storage when it avoids
copying or improves FFI layout. Ordinary OCaml arrays are preferable for small
initial-domain runtime tables when they benchmark faster and simpler. A custom
arena must remain typed and auditable; do not introduce unsafe pointer arenas
without measured necessity and ownership proof.

## Correctness invariants

- Public event and change ordering is deterministic.
- Logical points remain the sole UI/layout/input coordinate space.
- Drawable scaling occurs once at the native boundary.
- Paint ordering, clips, transforms, blend, opacity, and text-input regions
  match current semantics exactly.
- Focus and pointer capture never target a stale generation.
- A failed reconcile/paint publication retains the last complete display list;
  partial state is never submitted.
- Every segment resource survives through command completion and is released
  before renderer/device teardown.
- Hidden work suppression never drops application edits or async cook results.
- UI runtime mutation and native work remain on the initial domain.
- Background work consumes immutable snapshots and joins before publication.
- Fixed inputs produce exact ordered results across one/multiple preparation
  domains.
- PXUI and graph layers never import Runtime, Metal, or `ogpu_metal`.
- Prismel never imports PXUI.
- No CPU raster, browser, SDL renderer, OpenGL, or alternate backend appears.

## Benchmark matrix

Every architecture milestone reports at least:

| Scenario | Sizes/variants |
| --- | --- |
| panel build/reconcile | 10, 100, 1k, 10k widgets |
| unchanged query/frame | visible and hidden; scale 1/2 |
| hover | first/middle/last/no-hit |
| slider drag | first/middle/last; 3 and 1,000 move events |
| scroll | small/large panel; cold/warm visible window |
| accordion | shallow/deep; expanded/collapsed |
| text | empty/ASCII/UTF-8/IME; stable/changing |
| graph | 100/1k/10k nodes; 2x edges; 1/10/100% visible |
| graph gestures | hit/pan/zoom/move k/select/menu |
| native workspace | visible/hidden/idle; scale 1/2 |
| lifetime | 100k interactions; 30-minute churn |

For each scenario record:

- median/p95/p99 wall time;
- user/system CPU and CPU percentage;
- allocated, minor, promoted, and major bytes;
- major/minor collections;
- live/peak heap and RSS;
- visited/dirty/visible/candidate nodes;
- arena capacity/high-water/growth;
- display-list and native-plan builds/hits/bytes;
- draw/pass/submission/upload counts;
- live native handles before/after teardown;
- machine, display scale, compiler, profile, domains, source commit, and sample
  count.

## Risks and controls

### Retained-state complexity

Stable identity and dirty propagation can create stale-state bugs. Control this
with generation-checked IDs, mutation APIs that emit typed dirty effects,
phase assertions, randomized reconcile sequences, and exact full-rebuild oracle
tests during migration.

### Cache-induced memory retention

Incremental systems can trade allocation for retained memory. Every cache and
arena needs byte accounting, capacity tests, eviction tests, and teardown
evidence. Peak capacity must be explained by workload cardinality.

### Over-fragmented repaint boundaries

Too many segments increase passes, descriptors, and composition work. Too few
recreate whole panels. Record boundary usefulness and native command counts;
merge/split based on measured asymmetric invalidation.

### Public API expansion

A GPUI-like entity API would unnecessarily enlarge Prismel's surface. Keep the
runtime private initially. Expose only narrow stable keys, owned UI runtime
lifecycle, and typed invalidation/result boundaries proven necessary by real
call sites.

### Text correctness

Text caching is sensitive to font generation, density, shaping, IME, and
renderer ownership. Treat text as its own milestone and preserve all current
font/cache/lifetime tests.

### Renderer coupling

Direct packed paint output can accidentally make PXUI backend-aware. The packed
format belongs to Prismel and remains renderer-neutral; OGPU/Metal lowering is
the only native implementation.

### Premature data-oriented complexity

Structure-of-arrays and spatial indexes add code. Require scale benchmarks and
oracle tests before each specialized structure replaces a simpler array. Do
not add abstractions without measured work they remove.

## Explicit non-goals

- importing or binding GPUI;
- rewriting Prismel or PXUI in Rust;
- adding Winit, Skia, Vello, OpenGL, a CPU rasterizer, or browser runtime;
- moving graph authority out of `Procedural.Edit_graph`;
- moving UI widgets into `procedural`, `pdk`, Runtime, or renderer libraries;
- making every application use a global mutable entity store;
- parallelizing input, layout mutation, text atlas access, or native rendering;
- claiming zero allocation without allocation-counter proof;
- accepting 60 FPS average while p95/p99 exceed the refresh envelope;
- retaining old and new UI engines as permanent fallbacks.

## Completion definition

This plan is complete only when:

1. the old quadratic widget interaction path is deleted;
2. PXUI uses stable retained runtime nodes with explicit invalidation;
3. layout, prepaint, paint, and compose consume authoritative packed snapshots;
4. stable display-list segments reach native submission without rebuilding
   intermediate Scene/list structures;
5. large panels and SOP graphs meet the stated asymptotic and measured gates;
6. idle, hidden, visible, interaction, Retina, memory, and teardown budgets pass;
7. public behavior, dependency direction, native-only rendering, and ownership
   invariants remain exact;
8. final evidence is recorded on one clean integrated commit;
9. the previous list-based runtime and rendering path is removed rather than
   preserved as a fallback.

