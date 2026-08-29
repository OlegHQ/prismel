# Prismel sketch API

Status: accepted direction for the public high-level API.

## Goal

Prismel should make the first visual result take minutes and keep larger
sketches understandable. A sketch author should spend their attention on the
idea, not lifecycle plumbing, SDL resources, or synchronizing input state.

The high-level API is functional:

- application state is an ordinary immutable OCaml value;
- `update` returns the next state;
- `view` returns a pure `Scene.t`;
- scenes are data and can be composed, mapped, tested, cached, and rendered;
- effects and mutable renderer state stay behind `Sketch.run` and
  `Scene.render`.

Mutable backend modules live under the explicit `Low` escape hatch. New
sketches start with `Sketch`; direct rendering experiments use `Preview`.

## Design evidence

Productive creative-coding systems converge on a few ideas:

- Processing and p5.js automatically call setup/draw and expose current input,
  time, and canvas dimensions.
- openFrameworks uses a predictable setup/update/draw/event lifecycle.
- Raylib keeps the drawing vocabulary flat and concrete.
- Lisp-family workflows favor small expressions, composable data, and fast
  evaluation over object construction and callback ceremony.

Prismel retains those advantages without importing global mutable user state.
The frame environment is an explicit value and the picture is a pure value.

Primary references used in this design:

- [p5.js reference](https://p5js.org/reference/)
- [Processing `draw()` lifecycle](https://processing.org/reference/draw_)
- [openFrameworks `ofBaseApp`](https://openframeworks.cc/documentation/application/ofBaseApp/)
- [Raylib API cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html)
- [Quil, a Clojure sketch system](https://github.com/quil/quil)
- [thi.ng/geom functional geometry toolkit](https://github.com/thi-ng/geom)
- [The Elm Architecture](https://guide.elm-lang.org/architecture/)
- [OCaml parallel programming](https://ocaml.org/manual/5.3/parallelism.html)
- [Domainslib](https://ocaml.org/p/domainslib/latest)

## Five-minute sketch

```ocaml
open Prismel

let view frame =
  Scene.[
    clear (Color.rgb 18 20 28);
    circle ~at:frame.mouse ~radius:36 ~fill:Color.cyan ();
    text ~at:(12, 12) (Printf.sprintf "frame %d" frame.count);
  ]

let () = Sketch.run view
```

No model, update callback, event callback, renderer, or trailing application
configuration is required.

## Stateful sketch

```ocaml
open Prismel

type model = { x : float }

let update model frame =
  let direction =
    if Frame.key_down Input.ArrowRight frame then 1.
    else if Frame.key_down Input.ArrowLeft frame then -1.
    else 0.
  in
  { x = model.x +. (direction *. 200. *. frame.dt) }

let view model frame =
  Scene.[
    clear Color.black;
    circle ~at:(int_of_float model.x, frame.height / 2)
      ~radius:24 ~fill:Color.yellow ();
  ]

let () =
  Sketch.run_state
    ~init:(fun _frame -> { x = 100. })
    ~update ~view ()
```

## Modules and responsibility

### `Frame`

An immutable snapshot passed to sketch functions:

- logical `width`, `height`, and `size`;
- native-pixel `drawable_width`, `drawable_height`, and `drawable_size`;
- `pixel_scale`, the native pixels per logical point on each axis;
- `time`, `dt`, `fps`, and monotonically increasing `count`;
- `mouse` and `mouse_delta`;
- current `keys` and `mouse_buttons`;
- all ordered `events` received since the previous update.

Helpers such as `Frame.key_down` and `Frame.mouse_down` keep common queries
readable. Events remain available for edge-triggered behavior, including
committed UTF-8 text and in-progress IME composition.

`Event.PointerCancelled` is distinct from `WindowFocusLost`. It releases an
OS-cancelled pointer and stops pointer capture without clearing an
otherwise valid text-field focus.

`Frame.mouse`, all mouse event coordinates, and scene positions use the same
logical-point space as `width` and `height`. `mouse_delta` is the sum of every
pointer motion received during that application frame; it is zero in the next
frame unless new motion arrives. Sketches normally ignore `pixel_scale`.
Framebuffer inspection, native-resolution capture, and deliberately
pixel-density-aware effects use the `drawable_*` fields instead.

### `Rand`

`Rand.t` is immutable and deterministic. Stateful samplers return the next
generator; `Rand.split` creates independent streams before parallel work.
`Rand.float_at generator ~index` is the stateless dense-kernel path: it maps a
native integer identity to a value in `[0, 1)` without advancing the generator
or allocating per sample. Stable element/component indices therefore produce
exact values regardless of domain count or work-stealing order.

### `Scene`

`Scene.t` is a list-like declarative picture. Constructors cover:

- background and clear;
- point, line, thick line;
- rectangle, rounded rectangle, circle, ellipse, triangle;
- polygon and polyline;
- arc, pie, and Bezier curve;
- installed system UI text, fixed bitmap debug text, loaded-font text, and images;
- non-visual `text_input_region` metadata for focused native text entry;
- nested translate, rotate, scale, and general groups.

The installed runtime, OGPU, and Metal libraries do not add a second public
Scene vocabulary. Their lowering, resource snapshots, and orchestration remain
private implementation machinery behind the same immutable `Scene`/`Scene3`
values. Native Metal is the only renderer and is not selected through public
scene data or an environment flag.

`Scene.text_input_region` is pure scene data. At the render boundary its
transformed, clipped logical bounds describe where native text focus may be
activated. Ordinary canvas and control presses do not implicitly start text
input.

`Scene.text ?size` resolves an installed platform UI font and treats `size` as
a logical point size. `PRISMEL_UI_FONT` overrides the platform font search.
`Scene.debug_text` is Prismel's independent fixed 8×8 diagnostic face. System
and loaded fonts rasterize and cache at the active renderer density while
keeping their layout dimensions logical.

Loaded-font text supports explicit newlines, logical-width word wrapping, and
left/center/right alignment directly through `Scene.font_text`. Rasterized
textures are cached per renderer and native raster size using the complete
visual key (font state, content, mode/color, wrap, and alignment). Mutating font
style, hinting, or kerning invalidates its cache. Offscreen renderers receive
separate textures and release those textures before renderer destruction.
The automatic scene renderer retains at most its 256 most-recent text textures
per renderer, keeping dynamic labels bounded. Explicit `Font.cached_text`
borrows remain stable until cache clear or font destruction. Empty scene text
draws nothing.
Each renderer-local cache uses a 256-entry LRU bound, preventing animated
counters and PXUI values from retaining unbounded textures. Empty text is valid
and produces no visible geometry.

Every primitive accepts direct styling (`fill`, `stroke`, `stroke_width`) rather
than relying on hidden user-visible state. Transform nodes scope their changes
to their children. Primitive geometry is transformed before rasterization, so
rotation and non-uniform scale affect complete outlines rather than only anchor
points.
Filled curved and polygonal primitives retain an antialiased boundary around
their tessellated fill, so filled and stroked variants both produce fractional
edge coverage in the native 2D pipeline.

Coordinates are integer logical points in the initial API. The origin is the
logical window's top-left, with positive Y downward. Runtime maps that space to
the native Metal drawable and keeps pointer events in the same logical space,
so Retina backing scale never changes layout or hit testing. Model calculations
should use floats and convert at the scene boundary.

### `Scene3`

`Scene3.t` is an immutable three-dimensional scene embedded with
`Scene.view3d ~camera`. `Mesh` provides indexed points, lines, and triangles
plus plane, box, UV sphere, icosphere, cylinder, and cone generators.
Its immutable editing/query API includes per-element replacement, safe
removal, range coloring, compact submeshes, centroid/duplicate/crease-normal
operations, attributed faces and face normals, spatial diagnostic meshes, UV
remapping, and ASCII/binary PLY plus OBJ output.
`Material` and `Light` provide the fixed native lighting inputs, while `Mat4`
and scoped `Scene3` nodes compose hierarchical transforms. The public model
also retains area-light, fog, separate-specular, `Shader3`, compute, and
transform-feedback values. Constructor presence is not a native-support claim:
the current Scene3 lowering accepts the fixed triangle/material/light path and
returns typed errors for OCaml-function shaders and other unlowered modes.

The renderer uses native Metal color, depth, and stencil attachments, not
projected 2D painter ordering. Perspective and orthographic cameras use
logical-point viewports and offer world/screen conversion and picking rays.
Explicit asymmetric frusta,
off-axis portal cameras, vertical projection flipping, and frustum diagnostic
meshes cover multi-display and projection-mapping use cases.

`Scene3.with_depth`, `with_stencil`, `with_raster`, and `with_blend` provide
immutable scoped intent. Only state explicitly accepted by
`Scene3_native_lowering` counts as implemented by the public native renderer.
Unsupported stencil/raster/programming combinations must fail rather than be
ignored. Capture and offscreen ownership use the native Canvas/resource path;
there is no separate public `Framebuffer3` module in the installed library.

See [`3d.md`](./3d.md) for the rendering contract and
[`3d-parity.md`](./3d-parity.md) for the audited openFrameworks parity matrix.

### `Geom`

Geom is a wrapped sibling library published as `prismel.geom`. It adds
immutable geometry algorithms without enlarging Prismel's five-minute sketch
surface or reversing the dependency direction. Shapes, intersections, curves,
spatial trees, Verlet worlds, sparse voxels, mesh processing, SVG values, and
visualization layouts remain renderer-independent values and transformations.

`Render2` is the explicit adapter into `Scene.node` and `Path.t`. `Mesh3` is
the explicit adapter into native immutable `Mesh.t` values, including
extrusion, lathing, parallel-transport sweeps, four subdivision families,
repair, exchange, and CSG. `Iso3` and `Voxel3` extract the same mesh values
from pure scalar fields or sparse occupancy. The normal
Prismel renderer therefore remains the only effect boundary, and the same
output works in presented, captured, framebuffer, and export paths.

Loop and Catmull-Clark mesh subdivision adapt through the same packed PDK core
used by `Procedural.Sop.subdivide`. The SOP additionally exposes bilinear
refinement, recursive depth, all six OpenSubdiv face-varying interpolation
policies, standard or Smooth Triangles Catmull-Clark masks, groups, and
Uniform or Chaikin semi-sharp `creaseweight` plus uniformly decayed
`cornerweight` behavior. A crease override without a topology input applies to
every edge in the subdivided surface through the first packed plan, matching
Houdini without materializing an input-sized control field. Houdini-compatible `osd_scheme`,
`osd_vtxboundaryinterpolation`, `osd_fvarlinearinterpolation`,
`osd_creasingmethod`, and `osd_trianglesubdiv` detail fields override the
corresponding node options at the PDK cook boundary without adding a second
geometry model.
`Procedural.Sop.crease` is the authoring companion: it adds, sets, or deletes
edge-consistent vertex `creaseweight` values over all edges or a named native
edge group and can add deterministic endpoint visualization colors before the
same Subdivide kernel consumes the snapshot.
`Procedural.Sop.attribute_fade` is the frame-dependent scalar point-field
companion for iterative sketches. It multiplies the input field by an explicit
fade-in/hold/fade-out envelope, defaults missing fade/start/hold-scale values
to one/zero/one, accepts independently cooked equal-point-count start and hold
sources, and exposes affine start retiming plus piecewise-linear in/out ramps.
The node reads `Frame.count` through `Context.Frame`; it does not use wall time,
global state, or a hidden feedback cache. A point group preserves values
outside the selection, and visualization writes opaque grayscale point `Cd`.
`Procedural.Sop.poly_cut` is the curve-breaking companion. A primitive group
restricts source curves and a second name resolves as either a point group or
native edge group according to the typed element mode. Remove and Cut are
distinct topology policies; scalar crossings interpolate exact cut endpoints,
while scalar or tuple change detection emits enough disconnected subsegments
to respect the requested maximum change. The static graph node delegates all
cardinality planning, point/vertex payload interpolation, group ancestry, and
parallel fills to `Pdk.Ops.poly_cut`.
`Procedural.Sop.separate_pieces` packs integer- or text-identified point or
primitive pieces into stable, non-overlapping projection intervals along an
arbitrary axis. A float3 translation field is written on the identity owner's
domain and the Move Back mode subtracts it later. Point identities must remain
uniform within every primitive, while primitive identities must agree at
shared points; ambiguous topology is rejected rather than deformed. The node
is static and delegates all bounds, ownership, overflow, and parallel position
work to `Pdk.Ops.separate_pieces`.
`Procedural.Sop.edge_equalize` targets the initial average, longest, or
shortest length of a named native edge group, or all topology edges when the
group is omitted. Independent edges are solved directly; connected selections
use a bounded deterministic PDK projection controlled by `~iterations` and a
relative `~tolerance`. The node may publish the processed topology-affine
selection with `~output_group`, and never owns mutable solver state.
`Procedural.Sop.edge_relax` is the two-input reference-length companion. The
reference must carry exactly the same packed polygon/curve topology. A typed
point or primitive group selects movable source points, an optional point group
pins them, and individual or source-mean-normalized target policy controls the
reference lengths. Iteration, step, tolerance, and shorten-only controls are
immutable node identity; bounded scratch lives only for the cook.
`Procedural.Sop.blend_shapes` accepts immutable `Sop.blend_shape` target
descriptors. Normalized mode assigns residual weight to the first input and
renormalizes positive target totals above one; differencing mode applies a
stable sum of weighted target-minus-source deltas and permits extrapolation.
Point groups, source/shape scalar masks, integer/text point-ID matching, and
Float/Float2/Float3/Float4 point-attribute patterns are exact node identity.
Missing target IDs and missing blendable target fields contribute the source
value, so partial targets remain deterministic rather than shifting indices.
`Procedural.Sop.attribute_composite` folds ordered immutable inputs across
independent detail, primitive, point, and vertex attribute patterns. Mean,
component-wise Max/Min, and standard ordered Over/Under operations share one
packed PDK kernel. Every input has a finite global weight; an optional
same-owner scalar alpha distributes it per element, with missing alpha equal to
one. Canonical `P` requires explicit `~allow_position:true`, and patterns,
weights, alpha name, input order, and operation all participate in cache
identity. The first input remains the topology and untouched-payload owner.
`Procedural.Sop.attribute_mirror` copies named point, vertex, or primitive
attributes across an explicit correspondence. Mapping mode resolves a named
integer destination-to-source field and destination group at cook time. Plane
mode reflects point positions, or primitive bounding-box centers, into a packed
nearest-neighbor index with an explicit tolerance. Optional source/destination
restriction, copied-name patterns, copy/UV/vector/point transforms, literal
text replacement, pair metadata, and side groups are immutable node identity.
The node never retains a spatial index or correspondence scratch after its
immutable output snapshot is committed.
`Procedural.Sop.rewire_vertices` changes corner-to-point incidence from a
scalar integer point, vertex, or primitive field. A typed point/vertex/
primitive/native-edge selection is promoted first to that field's owner.
Recursive point chains, target deletion, newly-unused-point cleanup, and a
vertex original-point provenance field are immutable node identity. Invalid
targets leave their corners unchanged; cycle members retain their own points.
All topology mutation, payload compaction, and topology-affine edge-group
ancestry remain inside the shared PDK core.
`Procedural.Sop.edge_transport` transports scalar point fields over a stable
shortest-path forest. First/last root selection seeds every selected component;
an explicit named root group performs deterministic multi-source traversal and
leaves unreachable points unchanged. The operation, root value, constant and
edge-length integration, direction, forward split, backward branch merge,
normalization, point group, and root group are all part of immutable cache
identity. `Procedural.Sop.edge_transport_curves` uses primitive order as an
O(vertices) curve traversal, supports scalar point or vertex fields and
forward/backward direction, and rejects cross-curve point aliasing rather than
allowing scheduling-dependent writes. `Procedural.Sop.edge_transport_parent`
uses an integer point-parent forest when topology edges are absent; invalid or
self parents form roots, cycles remain unchanged, and independent trees cook
in parallel with stable numeric child order.
Open and closed polygon curves also adapt through that single PDK Subdivide
core. Catmull-Clark inserts segment midpoints and applies the cubic
`1/8 previous + 3/4 current + 1/8 next` rule at shared-graph degree-two
points, pinning endpoints and branches; bilinear pins every old point. The
typed `treat_curves_as_independent` option duplicates every curve corner before
evaluation, while the default preserves shared curve-point identity. Loop
remains triangle-surface-only. Mixed primitive families are restored to stable
source-primitive order, and numeric point/linear vertex payloads follow the
same curve stencils without introducing a second geometry representation.
Point `N` is an ordinary point-stencil payload by default. The typed
`recompute_point_normals` option instead replaces an existing input point `N`
after the complete surface/curve cook with final area-weighted normalized
normals; it never creates a normal field for an input that lacked point `N`.
`Procedural.Sop.poly_loft` triangulates an authored sequence of selected open
or closed polygon curves or polygon faces through the shared packed PDK core.
It accepts unequal section cardinalities, closest or rest-guided alignment,
two- and three-distance pairing objectives, U/V wrap, source retention,
generated-face grouping, explicit collinearity policy, and existing-normal
regeneration while preserving exact attribute and group ancestry.
`Procedural.Sop.skin` builds the corresponding linear polygon surface through
the same packed core. Equal-cardinality neighbors emit quads in stable section
order; unequal neighbors retain PolyLoft's deterministic triangle zipper.
This polygonal single-input contract deliberately excludes spline surfaces and
bilinear U/V boundary networks.
`Procedural.Sop.poly_bridge` consumes two named native edge groups from one
input. Each must decompose into the same number of simple open paths or closed
loops. Components pair in stable authored or centroid-sorted order; reverse
controls and a closed-loop destination shift refine correspondence. Input
retention defaults on, and equal/unequal boundaries emit shared-core quads or
zipper triangles without duplicating boundary points. Positive `divisions`
adds uniform straight rows to equal-cardinality bridges with linear numeric and
nearest discrete point/vertex interpolation.
`Procedural.Sop.poly_reduce` exposes deterministic adaptive QEM reduction over
the same packed PDK geometry. A ratio or absolute polygon target, primitive
restriction, hard point/native-edge constraints, strict boundary locking,
original-position mode, equal-length weighting, optional normal-deviation
limit, and surviving-face group are immutable cache parameters. Polygon
triangulation, manifold link validation, flip rejection, cancellation, and
payload/group/native-edge remapping stay below the graph boundary. A constrained
surface may stop above its requested target rather than violating topology.
`Procedural.Sop.convex_hull` constructs a lower-dimensional or closed 3D hull
from all points or an explicitly typed point/vertex/primitive/native-edge
selection. Exact predicates own affine and horizon decisions; immutable
parameters control point/detail ancestry, a source-point integer field, and an
all-face group. The output is a free point, endpoint curve, planar polygon, or
outward triangle surface rather than a fake always-solid placeholder.
`Procedural.Sop.extract_centroid` emits one free point for the whole detail,
each primitive, or each stable first-occurrence integer/text point or primitive
piece. Equal-point-mass and bounding-box centers use scale-normalized packed
reductions; convex-hull centers call the same exact hull kernel and reduce its
line, planar area, or closed volume. Optional source primitive numbers and
piece identifiers are point attributes, while source detail attributes remain
structurally shared.
`Procedural.Sop.extract_point_from_curve` discards the selected polygon curves
and emits disconnected points wherever a scalar point field exactly matches or
linearly crosses a constant, per-primitive scalar attribute, or current cook
time. Current-time mode alone declares `Context.Time`; constant and authored
attribute modes remain static cache facts. Compiled point patterns interpolate
numeric payload and transfer discrete/ragged values from the stable nearest
side, optional primitive patterns copy curve payload to point ownership, and
generated point fields expose uniform-edge curve U, per-curve cut count, and
original primitive number. Plateau vertices and closed seams have explicit
once-per-curve behavior, and all topology-changing work stays in the shared
PDK kernel.
`Procedural.Sop.circle_from_edges` transforms each simple path or loop in a
named topology-affine edge group, or every topology boundary component when no
group is named. Best-fit radius is the default; a positive constant radius,
finite component-wise scale, and output native edge group are immutable cache
identity. The static node resolves only the group name and delegates component
planning, normalized covariance/eigensystem fitting, algebraic circle fitting,
projection, cancellation, validation, and stale-normal handling to PDK.
`Procedural.Sop.graph_color` resolves an optional typed group, promotes it to
the point or primitive graph owner, and delegates stable component planning and
greedy coloring to PDK. Point graphs connect all points in each primitive;
primitive graphs connect through any shared point or only a shared closed-
polygon edge. Unselected elements receive `-1`. Optional stable sorting and
detail integer-array workset begin/length fields are part of immutable node
identity and remain byte-identical across domain counts.
`Procedural.Sop.poly_bevel` wraps the single packed PDK bevel kernel. A named
native edge group or all eligible edges produces chamfered or divided rounded
fillets; point-float distance scale, flat-edge exclusion, first-ring collision
limiting, edge/corner primitive groups, and offset native-edge groups are stable
node parameters. Partial networks split the neighboring ring-face boundary,
while connected junctions share continuation profiles or emit deterministic
corner faces. Numeric vertex fields interpolate across profile rows; discrete
fields and groups retain stable nearest ancestry.
`Procedural.Sop.point_split` wraps the shared packed point-fan splitter for
point, vertex, or primitive selections. With no seam pattern, every selected
corner becomes unique. With ordered include/exclude globs, differing vertex or
primitive attribute tuples and named vertex/primitive group membership define
deterministic point clusters under an inclusive per-component tolerance.
Optional promotion moves matched attributes, but not groups, to point
ownership; free points receive the storage type's zero/empty
default. Original point numbers remain a stable prefix and all point payload,
groups, and topology-affine native-edge ancestry follow the explicit source
map.
`Procedural.Sop.ends` changes closure for selected polygon faces and polygon
curves. Open removes the closing segment; straight close creates a polygon and
removes a repeated shared endpoint when round-tripping an unroll. Shared-seam
unroll appends a corner referencing the first point, while new-seam unroll
duplicates that point's position, every fixed/ragged payload row, and ordered
group ancestry. Both unroll modes retain the original closing-edge ancestry;
new straight closing edges remain outside source edge groups. The older
`curve_ends` entry point remains a curve-only compatibility surface over the
same packed kernel.
`Procedural.Sop.duplicate` always retains the complete source as an exact
prefix. Its optional primitive group restricts only the appended copies;
unreferenced source points are not multiplied. Fixed and ragged payload,
ordinary and ordered groups, and native-edge membership follow exact
copy-major ancestry. An optional output-group prefix creates one primitive
group per appended copy using a one-based suffix. Same-name primitive groups
are replaced by default or unioned when `preserve_groups` is enabled; group
count and packed payload have explicit bounds.
`Procedural.Sop.point_generate_origin` is the no-input origin-cloud form.
`Procedural.Sop.point_generate` is the connected form: it emits a total expected
count per selected source point (with an optional point-float scale and
deterministic fractional rounding), or accepts a point-float probability for a
zero/one decision. Output is source-major and local-index-major. Optional input
retention preserves original point numbers as a prefix, shares existing
polygon/curve topology planes, extends only the point domain, and retains
topology-affine edge groups. Ordered copy patterns select every fixed or ragged
point storage and detail fields independently. The optional generated group
and integer `sourcepoint`/`sourceindex` fields make ancestry explicit; retained
points use `-1` when no previous compatible provenance field exists.
`Procedural.Sop.point_replicate` builds spatial clouds on the same emission
contract. Built-in point, box, sphere-volume, disk-area, and line distributions use
normalized local coordinates; an optional second custom-shape graph samples
its points and emits `shapeptnum`. Local center, size, Euler orientation, and
uniform scale are applied before the source point's canonical Copy-to-Points
frame, including `pscale`, `scale`, `orient`, `N`/`v` plus `up`, `rot`,
`pivot`, `trans`, and affine `transform`. Integer `id` controls both fractional
count decisions and spatial samples, keeping clouds stable across deterministic
point reordering. Quasi coordinates, velocity-only or composed stretch,
inherited/radial `v`, and optional allocation-free rest-space vector fBm are
stable node parameters. `transform_attributes` is an ordered copy-style
pattern over point float3 fields: matching values transform as vectors, while
`N` uses a normalized inverse transpose and is removed atomically if a selected
source frame is singular. Canonical `P` always follows the position path once;
the default pattern is `P`, preserving copied vector payload unchanged. The
custom shape remains an ordinary immutable SOP
input rather than an internal file-loader boundary.
`Procedural.Sop.delete` accepts typed point, vertex, or primitive selections;
`blast` resolves an existing typed group; and `split` returns selected and
remainder branches. All three use the same packed destroy/heal/compaction
contract, so graph convenience does not fork topology semantics.

See [`geom.md`](./geom.md) for algorithm contracts, examples, attribution, and
the capability map against thi.ng/geom.

### `PXUI`

PXUI is a sibling library that depends on Prismel and consumes ordinary
logical `Event.t` positions. Its default visual language is a dark translucent
panel with rounded controls, a bright cyan-green accent, subtle highlight
lines, and visible hover/pressed/drag states. `Pxui.create` accepts `?theme`,
`?font`, and logical `?font_size`; the default typography is `Scene.text`.

Pointer behavior is captured and deterministic:

- buttons, toggles, and choices arm on left press and commit only on release
  inside that same control;
- sliders, the selected range handle, and XY pads capture from press through
  release, update on each intervening pointer move even outside their bounds,
  and clamp to the declared ranges;
- `WindowFocusLost` cancels capture, text focus, and composition;
- `Pxui.update_frame` preserves event order when returning named changes and
  uses logical `Frame.time` for deterministic numeric-label double clicks.

`Pxui.int_slider` is a distinct integer control: its range and stored value are
integers, dragging snaps before it emits `Int_slid`, its label never displays a
fraction, and settings persistence uses an integer payload. Float sliders
remain continuous.

Double-clicking either slider label opens an inline numeric field. Enter commits
a finite value, Escape cancels, and pressing elsewhere commits only valid input.
Slider bounds are soft for typed, initial, programmatic, and persisted values;
only pointer dragging clamps to them. Integer sliders reject fractional text
rather than rounding it.

`Pxui.accordion` groups nested controls under a persistent disclosure row.
Collapsed children retain values but leave layout, hit testing, and text-input
metadata. `Pxui.bounds` therefore reports only visible rows.
`Pxui.create ~max_height` and `Pxui.with_max_height` bound the inspector,
clip overflowing rows and text-input regions, and route vertical wheel or
trackpad motion to a clamped scroll offset while the pointer is over the panel.
`Pxui.Camera_control` appends reusable 3D Camera and Render accordions to the same
canvas and automatically limits its height to the resized frame. It owns
resize-aware camera hit bounds, FOV/distance/near/far/inertia,
reset, render factor and PNG output, preserves middle-drag pan, maps `C` to the
camera accordion, and maps `H` to whole-overlay visibility through
`Pxui.Camera_control.overlay`, including labels and status text outside the
panel. Render requests are
explicit values so sketches can save the current render-only scene without
recooking procedural geometry. The controller keeps middle-drag pan and adds a
Mac-trackpad path: right-click drag or Space plus primary drag pans, vertical
two-finger motion zooms, and horizontal two-finger motion is ignored.
`Pxui.Camera2_control` exposes the same C/H/render policy for
`Easy_camera2`, with center, zoom, rotation, inertia, and reset controls.
Middle/right/Space-primary drag pans; vertical trackpad motion performs
pointer-anchored zoom and horizontal motion is ignored.

### `Sop_ui`

`Procedural.Parameter` owns renderer-neutral typed templates and immutable
values. `Node.parameterize` attaches a schema, current values, and a pure
rebuild function to the SOP that owns them. The leaf `prismel.sop_ui` adapter
generates the selected node's PXUI inspector without making either underlying
library depend on the other:

```ocaml
let inspector = Sop_ui.Node_inspector.create selected_node

let ui = Pxui.create ()
  |> Sop_ui.Node_inspector.append ~expanded:["Geometry"] inspector ~graph

let camera_control, ui, camera, changes, requests =
  Pxui.Camera_control.update camera_control ~ui ~camera frame
in
let graph, ui, effects =
  Sop_ui.Node_inspector.update inspector ~graph ~ui changes |> Result.get_ok
```

`effects.cook` requests a deferred/asynchronous graph cook;
`effects.view` updates render-only metadata without invalidating geometry;
`effects.export` marks output-only state. Graph edits preserve logical IDs and
shared subgraphs. `prismel.pxui_graph` supplies deterministic initial layout,
persistent graph-space tile positions, ordered ports/wires, topology-safe node
dragging, independent inspector/display selection through each tile's VIEW
button, selection clearing, captured pan, zoom, and framing. `Sketch_ui.Environment3.run`
and `Environment2.run` compose both in a splitter-resizable, independently
collapsible view/graph/inspector workspace whose default widths are 45/35/20.
The inspector shows camera/render controls with no selection and generated SOP
parameters with a selection. Display selection cooks the flagged node while
retaining the previous successful preview. Overlay callbacks receive a
view-local frame. Both environments retain one shared pause/stop/reset,
dependency-aware cooking, status, selection, inspection, and finite native
lifecycle.

`Easy_camera2` is the immutable 2D view transform. It supplies resize-safe
viewports and gesture areas, world/screen conversion, captured pan, inertia,
rotation, pointer-anchored zoom, and pure `Scene` composition. `Render2.save_png`
preserves the logical camera framing at integer render factors through the
checked Canvas/export boundary. Interactive presentation and capture use the
native renderer.

### Boolean fracture pieces

`Procedural.Sop.boolean_fracture` subtracts zero-volume cutter surfaces from an
oriented solid through the shared exact Boolean arrangement. Its primitive
integer `piece` attribute comes from the oriented Weiler cell bounded by each
output face. Seam points remain shared in the cooked geometry: membership, not
global point disconnection or ordinary polygon connectivity, is the fragment
boundary. This keeps the exterior polygons and paired cut walls of each closed
cell under one stable identity for terminal packing and rigid explosion.

`Pdk.Boolean.run ~piece_attribute:name` exposes the same optional cell
identity for lower-level Boolean products. IDs are dense in first-output-face
order and deterministic across domain counts; cleanup and detriangulation map
the final primitives back through extraction ancestry before the attribute is
written.

### `Sketch`

`Sketch.default_config` uses realtime wall-clock timing and enables resizable
native windows. Set `resizable = false` only for deliberately fixed-size
desktop output. Setting
`clock = Sketch.Fixed dt` makes `Frame.dt`, `Frame.time`, and `Frame.fps`
deterministic functions of the positive timestep and frame count. This mode is
intended for repeatable simulation, tests, and offline frame export.

Expensive procedural sketches use `Procedural.Async_cook`: submit immutable
graph/context/preparation requests after parameter commit, poll once per frame,
keep the previous successful snapshot interactive, and show the reported cook
elapsed time in the overlay. The queue is bounded to the active request plus
one latest pending request; superseded work is cancelled and its result is
never published. Only target-neutral CPU preparation runs in the worker.

- `Sketch.run view` is the zero-state path.
- `Sketch.run_state ~init ~update ~view ()` is the functional model path;
  optional `~max_frames` keeps one runtime alive for a positive finite frame
  bound, including finite native integration runs.
- `Sketch.export` and `Sketch.export_state` render deterministic numbered PNG
  sequences using a fixed clock and no realtime frame limiter.
- width, height, title, FPS and window behavior are optional configuration.
- cleanup is exception-safe.
- `Sketch.quit ()` requests graceful termination.
- `Sketch.resize ~width ~height` resizes the active native runtime and updates
  subsequent logical `Frame` facts without crossing through `Low.Window`.
- `Sketch.render_target ()` returns the sole `Native` target.

The native runtime uses the ordinary `Event.t`, `Input`, and logical `Frame`
contracts for pointer, keyboard, UTF-8/IME, focus, resize, and file-drop facts.
See [the runtime/backend specification](./backend.md).

### `Parallel`

Prismel targets OCaml 5 and may create a reusable Domainslib work-stealing pool
for CPU-heavy pure work. This is parallelism, not a second render loop.

Good parallel work:

- particle and physics updates over independent chunks;
- procedural geometry, noise fields, and generative systems;
- decoding or transforming CPU-side image/audio data;
- spatial indexing and other immutable data transformations.

Main-domain-only work:

- every `Scene.render` and `Graphics` call;
- SDL3 window/input/audio and Metal resource/presentation operations;
- mutation of shared sketch state.

`Parallel.map`, `Parallel.for_`, and `Parallel.both` submit coarse tasks to a
pool owned by `Sketch.run`. Results are joined before `view`, so the functional
`model -> frame -> model` contract stays deterministic. Small inputs should
remain sequential because scheduling can cost more than the work. The pool
defaults to the runtime's recommended domain count and never spawns one domain
per item.

Outside `Sketch.run`, the same operations safely fall back to sequential
execution unless the caller explicitly brackets work with `Parallel.run`.
Cached pools are keyed by their owning domain as well as domain count.
Persistent background coordinators call
`Parallel.release_current_domain_pools` after their final job and before that
domain exits; ordinary sketch code must not manage pool lifetime directly.

## Naming rules

- Prefer nouns for data and verbs for effects.
- Use `at:(x, y)` consistently for positions.
- Use `from_`/`to_` for line endpoints.
- Use radius for circles, never sometimes diameter and sometimes radius.
- Angles are radians throughout.
- Colors are `Color.t`, never polymorphic magic values.
- Constructors return a value and therefore do not require a trailing `()`,
  except when optional arguments would otherwise be unerasable.
- Keep common names short (`rect`, `circle`, `line`, `text`); put advanced
  control behind optional labels.

## Capability roadmap

The API is considered feature-complete for 2D sketching when these layers are
covered:

1. lifecycle, timing, input snapshots, deterministic finite native execution;
2. primitives, scoped styles/transforms, images, fonts, owned canvases/capture;
3. paths/curves, blend modes, clipping, pixels, capture/export;
4. asset caching and asynchronous preload;
5. deterministic random/noise, palettes, interpolation and easing;
6. audio playback and simple synthesis;
7. PXUI controls and parameter persistence;
8. live reload or a documented utop/dune watch feedback loop.
9. coarse-grained multicore helpers and background asset jobs with main-domain
   handoff.

Items 1 and the core of 2 are implemented by `Frame`, `Scene`, and `Sketch`.
Unimplemented roadmap items must not be represented by fake polymorphic
stubs—the API should return useful errors or omit the operation until real.

## Compatibility and evolution

- Existing modules remain available during the high-level API rollout.
- `Scene.render` is public for embedding a declarative scene inside an existing
  `App.run` program.
- Native objects remain absent from high-level `.mli` files and confined to
  checked implementation boundaries.
- Breaking changes should update this document and at least one complete
  example in the same change.

## API acceptance tests

A proposed high-level feature should demonstrate:

1. a minimal complete sketch;
2. a stateful sketch with no user mutation;
3. input use without a separate synchronization layer;
4. matching drawing, event positions, and hit testing at standard and simulated
   high-DPI renderer scales;
5. successful native Metal rendering and capture;
6. no SDL3 or Metal types in the new public signature;
7. a focused test for pure scene/model behavior.
