# Rays sketch API

Status: accepted direction for the public high-level API.

## Goal

Rays should make the first visual result take minutes and keep larger
sketches understandable. A sketch author should spend their attention on the
idea, not lifecycle plumbing, SDL resources, or synchronizing input state.

The high-level API is functional:

- application state is an ordinary immutable OCaml value;
- `update` returns the next state;
- `view` returns a pure `Scene.t`;
- scenes are data and can be composed, mapped, tested, cached, and rendered;
- effects and mutable renderer state stay behind `Sketch.run` and
  `Scene.render`.

New sketches start with `Sketch`; finite direct-render experiments can use
`Sketch.export`.

## Design evidence

Productive creative-coding systems converge on a few ideas:

- Processing and p5.js automatically call setup/draw and expose current input,
  time, and canvas dimensions.
- openFrameworks uses a predictable setup/update/draw/event lifecycle.
- Raylib keeps the drawing vocabulary flat and concrete.
- Lisp-family workflows favor small expressions, composable data, and fast
  evaluation over object construction and callback ceremony.

Rays retains those advantages without importing global mutable user state.
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
open Rays

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
open Rays

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
logical-point space as `width` and `height`. Pointer positions and wheel deltas
retain fractional values. `mouse_delta` is the float sum of every pointer
motion received during that application frame; it is zero in the next frame
unless new motion arrives. Sketches normally ignore `pixel_scale`.
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
- installed system UI text, loaded-font text, and images;
- non-visual `text_input_region` metadata for focused native text entry;
- nested translate, rotate, scale, and general groups.

`Ink` packs thousands of small rect/line/outline marks into painter-ordered,
retained Scene segments: adjacent same-color marks share one buffer, and
`Ink.take` returns an ordinary `Scene.node` with stable segment ids and an
optional internal clip. It matches the equivalent Scene nodes pixel for pixel
and is the public route to packed 2D geometry; the underlying display-list
constructor stays in `Scene.Private`.

The installed runtime, OGPU, and Metal libraries do not add a second public
Scene vocabulary. Their lowering, resource snapshots, and orchestration remain
private implementation machinery behind the same immutable `Scene`/`Scene3`
values. Native Metal is the only renderer and is not selected through public
scene data or an environment flag.
The transitional `Rays_api` re-export is gone; native callers use
`Rays` directly.

`Scene.text_input_region` is pure scene data. At the render boundary its
logical bounds describe the native IME candidate area for a focused editor;
its non-negative `cursor` offset locates the caret from the region's left edge.
Ordinary canvas and control presses do not implicitly start text input.

`Sketch.show_file_dialog` opens the system's file dialog (open one or several
files, save, or choose a folder; optional filters and starting location) and
returns an id at once; the outcome is one `Event.FileDialog` with that id in a
later frame, carrying the chosen absolute paths (empty for a cancel) or an
error. At most eight dialogs can be open. See `specification/sdl3.md` for the
native queue behind it.

`Clipboard.set_text` and `Clipboard.get_text` expose native system clipboard
text as explicit results on the initial domain. PXUI text fields, numeric
editors, and picker search support Command/Ctrl-C, X, and V while focused;
each uses UTF-8 caret and selection editing. Copy and cut use the selection
when one exists, retaining whole-value behavior otherwise, and paste inserts
at the caret. Cut clears text only after the clipboard write succeeds. The
picker reserves Delete for its selected row when no text is selected.

`Scene.text ?size` resolves an installed platform UI font and treats `size` as
a logical point size. `RAYS_UI_FONT` overrides the platform font search.
System and loaded fonts rasterize and cache at the active renderer density while
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
counters from retaining unbounded textures. Empty text is valid
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
removal, centroid, recalculated and flat normals, and attributed faces and face
normals. File import/export (OBJ, OFF, STL) belongs to `Rdk.Io` over packed
geometry.
`Material` and `Light` provide the fixed native lighting inputs, while `Mat4`
and scoped `Scene3` nodes compose hierarchical transforms. Scene3 renders
through the fixed native material/light path; inputs it cannot honor (more than
64 lights, malformed meshes, invalid viewports) are typed lowering errors.
`specification/3d-parity.md` tracks the scoped states still partially lowered.

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

### Packed geometry in `Rdk`

The public `Rdk` facade keeps its packed geometry, topology, attribute, mesh,
and Boolean paths while implementations live in one-way `rdk_core`, `rdk_exact`,
`rdk_spatial`, `rdk_attrib`, `rdk_gen`, `rdk_curve`, `rdk_mesh`, and `rdk_boolean`
libraries. `Rdk.Curve_sampling` provides deterministic Bézier and
Catmull–Rom samples, `Rdk.Iso_surface` extracts packed isosurfaces,
`Rdk.Uv_sphere` generates packed latitude/longitude spheres.
`Rdk.Group_ops`, `Rdk.Group_mesh`, `Rdk.Graph_color`,
`Rdk.Blast_by_attribute`, `Rdk.Separate_pieces`, `Rdk.Deletion`,
`Rdk.Blend_shapes`, `Rdk.Attribute_composite`,
`Rdk.Attribute_mirror`, `Rdk.Attribute_fade`, `Rdk.Fuse_reduce`, `Rdk.Fuse_grid`,
`Rdk.Normal_ops`, `Rdk.Curvature`, `Rdk.Laplacian`, `Rdk.Polyframe`, `Rdk.Scatter`, `Rdk.Boolean_detect`, `Rdk.Plane_generators`,
`Rdk.Box_generator`, `Rdk.Parametric_generators`, `Rdk.Spiral`, `Rdk.Point_generate`,
`Rdk.Color_by_height`, `Rdk.Line_geometry`, `Rdk.Mesh_merge`,
`Rdk.Edge_collapse`, `Rdk.Dissolve`, `Rdk.Ordering`, `Rdk.Instance_copy`,
`Rdk.Transform_ops`, `Rdk.Deform`, `Rdk.Subdivide`,
`Rdk.Poly_extrude`, `Rdk.Poly_bevel`, `Rdk.Poly_loft`, `Rdk.Poly_bridge`,
`Rdk.Poly_cut`, `Rdk.Point_replication`, `Rdk.Clean`,
`Rdk.Smooth`, `Rdk.Reverse_faces`, `Rdk.Edge_transport`,
`Rdk.Edge_ops`, `Rdk.Edge_relax`, `Rdk.Facet`, `Rdk.Circle_from_edges`,
`Rdk.Crease`, `Rdk.Rewire_vertices`,
`Rdk.Mirror_geometry`, `Rdk.Convex_hull`, `Rdk.Bound`, `Rdk.Match_size`,
`Rdk.Plane_clip`, `Rdk.Edge_flip`, `Rdk.Compact_points`,
`Rdk.Poly_fill`, and `Rdk.Poly_reduce` expose option and rule types or checked operations used
by procedural SOPs.
`Rdk.Group_ops.groups_from_name_checked` and
`Rdk.Group_ops.name_from_groups_checked` return the same typed validation and
cancellation errors as their compatibility entry points.
The remaining checked `Rdk.Group_ops` selections and `Rdk.Group_mesh` edge/path
selections preserve the same typed errors while keeping group storage in the
attribute core and topology paths in the mesh core.

Loop and Catmull-Clark mesh subdivision use the same packed RDK core
as `Procedural.Sop.subdivide`. The SOP additionally exposes bilinear
refinement, recursive depth, all six OpenSubdiv face-varying interpolation
policies, standard or Smooth Triangles Catmull-Clark masks, groups, and
Uniform or Chaikin semi-sharp `creaseweight` plus uniformly decayed
`cornerweight` behavior. A crease override without a topology input applies to
every edge in the subdivided surface through the first packed plan, matching
Houdini without materializing an input-sized control field. Houdini-compatible `osd_scheme`,
`osd_vtxboundaryinterpolation`, `osd_fvarlinearinterpolation`,
`osd_creasingmethod`, and `osd_trianglesubdiv` detail fields override the
corresponding node options at the RDK cook boundary without adding a second
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
parallel fills to `Rdk.Poly_cut.cut`.
`Procedural.Sop.separate_pieces` packs integer- or text-identified point or
primitive pieces into stable, non-overlapping projection intervals along an
arbitrary axis. A float3 translation field is written on the identity owner's
domain and the Move Back mode subtracts it later. Point identities must remain
uniform within every primitive, while primitive identities must agree at
shared points; ambiguous topology is rejected rather than deformed. The node
is static and delegates all bounds, ownership, overflow, and parallel position
work to `Rdk.Separate_pieces.run_checked`.
`Procedural.Sop.edge_equalize` targets the initial average, longest, or
shortest length of a named native edge group, or all topology edges when the
group is omitted. Independent edges are solved directly; connected selections
use a bounded deterministic RDK projection controlled by `~iterations` and a
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
packed RDK kernel. Every input has a finite global weight; an optional
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
ancestry remain inside the shared RDK core.
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
Open and closed polygon curves also adapt through that single RDK Subdivide
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
or closed polygon curves or polygon faces through the shared packed RDK core.
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
the same packed RDK geometry. A ratio or absolute polygon target, primitive
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
RDK kernel.
`Procedural.Sop.circle_from_edges` transforms each simple path or loop in a
named topology-affine edge group, or every topology boundary component when no
group is named. Best-fit radius is the default; a positive constant radius,
finite component-wise scale, and output native edge group are immutable cache
identity. The static node resolves only the group name and delegates component
planning, normalized covariance/eigensystem fitting, algebraic circle fitting,
projection, cancellation, validation, and stale-normal handling to RDK.
`Procedural.Sop.graph_color` resolves an optional typed group, promotes it to
the point or primitive graph owner, and delegates stable component planning and
greedy coloring to RDK. Point graphs connect all points in each primitive;
primitive graphs connect through any shared point or only a shared closed-
polygon edge. Unselected elements receive `-1`. Optional stable sorting and
detail integer-array workset begin/length fields are part of immutable node
identity and remain byte-identical across domain counts.
`Procedural.Sop.poly_bevel` wraps the single packed RDK bevel kernel. A named
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
`Procedural.Sop.delete_attributes` is the attribute removal entry point. Its
owner-specific patterns can select one literal name or multiple names; the
editor exposes the same operation as `Delete Attributes`.
`Procedural.Sop.rename_attributes` applies ordered owner-scoped pattern rules,
including a single exact name, with an explicit destination conflict policy.
`Procedural.Sop.bound` creates a bounding box with its default shape; use
equal lower and upper padding for symmetric expansion. The editor exposes the
same operation as `Bound`.
The checked packed operations are `Rdk.Bound.run_checked`,
`Rdk.Bound.bounding_box_checked`, `Rdk.Match_size.run_checked`, and
`Rdk.Match_size.match_axis_checked`; their shape and fit constructors live in
those family modules.
Packed curve modeling uses `Rdk.Resample_curves.run`,
`Rdk.Curve_ops.carve_curves` (with its `cut_mode` and
`parameter_attribute_mode`), and `Rdk.Sweep_circle.run`.
Packed queries use `Rdk.Ray.run`, `Rdk.Point_split.run_checked`, and
`Rdk.Intersection_analysis.run_checked`; ray options and constructors live in
`Rdk.Ray`. These entries preserve the typed validation and cancellation
errors of the former compatibility wrappers.
Packed UV projection, transform, seam marking, unitizing, flattening, and
relaxation use the corresponding `Rdk.Uv_ops` entries and option types.
Packed triangulation and remeshing use `Rdk.Triangulate`, `Rdk.Triangulate2d`,
and `Rdk.Remesh`; revolve and
general sweep use `Rdk.Sweep_modeling`. Both modules preserve the checked
validation and cancellation results of the former compatibility entry points.
Curve topology and extraction use `Rdk.Curve_topology` for line conversion,
curve ends, joins, path tracing, centroid extraction, and curve-point cuts.
`Rdk.Fuse_grid.fuse_checked` and `snap_to_grid_checked` preserve the typed
validation and cancellation boundary around the packed Fuse and grid kernels.
`Rdk.Plane_clip.clip_checked` and `clip_transform_checked` preserve the same
typed clipping boundary while exposing only the plane policy and operations.
`Procedural.Sop.group_rename` applies ordered owner-scoped rename rules with
an explicit conflict policy, including the single-group case.
`Procedural.Sop.group_promotions` uses one ordered rule list for single and
multiple group conversions. A rule may emit a group or a named integer mask;
patterns that match no source group leave the geometry unchanged.
`Procedural.Sop.promote_attributes` handles one named attribute or a pattern.
Aligned output and index patterns name promoted values and their contributing
source indices; same-owner renames work without a piece partition.
`Procedural.Sop.blast` deletes an existing typed point, vertex, or primitive
group (build one with `Sop.group` and a typed `Select`) through the packed
destroy/heal/compaction contract.

### `PXUI`

PXUI is a sibling library that depends on Rays and consumes ordinary
logical `Event.t` positions. `Pxui.Ui` is an immediate-mode kit: build the
interface inside `Ui.frame`, keep values in the model, and compose
`Ui.scene` into the view. See [`pxui.md`](./pxui.md) for the architecture and
the pixel-exact design-kit contract.

```ocaml
type model = { ui : Pxui.Ui.t; radius : float; palette : int }

let update model frame =
  Pxui.Ui.frame model.ui frame @@ fun ui ->
  Pxui.Ui.panel ui "Look" @@ fun () ->
  let radius = Pxui.Ui.slider ui "Radius" ~range:(10., 120.) model.radius in
  let palette = Pxui.Ui.choice ui "Palette" ["ocean"; "sunset"] model.palette in
  { model with radius; palette }

let view model _frame = scene_of model @ Pxui.Ui.scene model.ui
let on_stop model = Pxui.Ui.destroy model.ui
```

Kit widgets are `label`, `button`, `toggle`, `slider`, `int_slider`,
`text_field`, `choice`, `range_slider`, `xy`, and `accordion` inside a
`panel`. Buttons, toggles, choices, and accordion headers commit on a press
and release inside the same control; sliders, ranges, and XY pads capture
the pointer and clamp to their drag range. Double-clicking a slider label
opens an inline numeric editor (Enter commits even beyond the soft range,
Escape cancels). `WindowFocusLost` cancels capture, focus, and composition.
Custom widgets are functions over `Ui.box`, `Ui.signal`, and `Ui.draw`;
layout uses `Px`, `Pct`, `Rel`, `Grow`, `Fit`, and `Text` sizes, `row`/`col`
nesting, `splitter`, floating `~at` boxes, and canvas `~xform` transforms.
Splitters request resize pointers on hover or drag, and text fields, text areas
and picker search request the I-beam; `Sketch.set_cursor` accepts default,
horizontal-resize, vertical-resize, and text shapes for native sketches and
returns an error outside an active sketch. A trackpad pinch reaches a box as
`signal.pinch`, the product of the frame's pinch factors for the scrollable box
under the pointer.

`Editor_core.Store.Settings` saves model values in Rays's versioned JSON
envelope and reads existing `PXUI1` files.
`Pxui.Camera_control` builds Camera (FOV, distance, clipping, inertia, reset)
and Render (output name, save) sections through `widgets`. Hosts decide when
to build them using `ui_visible`, `open_camera`, and `toggle_ui`, and call
`navigate` with their viewport control area. Navigation uses middle/right
drag pan and
vertical trackpad zoom (horizontal motion is ignored); render requests are
explicit values.
`Pxui.Ui.popup` owns outside-press and Escape dismissal using the last
laid-out panel bounds. `Ui.modal`, `Ui.picker` (fuzzy windowed list with
Enter/click pick and double-Delete), and `Ui.context_menu` (host-held open state, right click
under 4 points via `Ui.context_clicked`) are the shared overlay widgets.
`Pxui.Camera2_control` does the same for `Easy_camera2` with center, zoom,
rotation, inertia, and reset.

### `Pxui_shell.Inspector`

The dependency-free `param` library (`Editor_core.Param`, also
`Procedural.Parameter`) owns renderer-neutral typed templates and immutable
values. `Node.parameterize` attaches a schema, current values, and a pure
rebuild function to the SOP that owns them. `Pxui_shell.Inspector` builds kit
rows from any schema, so a SOP node and a plain sketch record share one
inspector.

`Pxui.Ui.inspector_row` and `inspector_section` supply the same responsive
layout to those fields and to Camera, Render, Viewport, settings, and compound
interface controls. `inspector_header`, `inspector_toggle`,
`inspector_button`, `inspector_readout`, and `inspector_message` cover their
other content.
The Rays Editor inspector panel has no outer padding; long labels move
above their controls within the row.

Both kinds of caller use the same field adapter:

```ocaml
(* inside Pxui.Ui.frame: a sketch record *)
let settings, effects =
  Pxui.Ui.panel ui "settings" (fun () ->
    Pxui_shell.Inspector.record ui settings_schema settings)
  |> Result.get_ok

(* a selected SOP node *)
let node, effects =
  match Pxui_shell.Inspector.fields ui ~expanded:["Geometry"]
      (Procedural.Node.parameter_fields node) with
  | [] -> node, Procedural.Parameter.no_effects
| changes -> Result.get_ok (Procedural.Node.apply_parameters node changes)
```

In Rays Editor, `Inspector.flow_fields` renders the selected SOP or value
node from its saved Flow network. It shows the node label, qualified kind,
flags, geometry inputs, all parameter folders, card pin toggles, grouped vec3
controls and split state. A driven row shows its source and applied value;
reset removes the drive so its stored literal takes effect. Numeric fields
accept `=…` expressions and reject malformed text without changing the
document. It returns typed
requests that `Doc.apply` commits after `Ui.frame`.

`effects.cook` requests a deferred/asynchronous graph cook;
`effects.view` updates render-only metadata without invalidating geometry;
`effects.export` marks output-only state. Graph edits preserve logical IDs and
shared subgraphs; the sketch host's `Doc` module applies typed graph edit
requests, and selected-node changes go through
`Procedural.Edit_graph.apply_parameters` before compiling the cookable graph.
The host's `Cook` module owns compilation, reactive scheduling, polling, and
framing work; `Core` composes those results with the workspace UI. One
`Environment.Make` functor over a `VIEWPORT` adapter (`Viewport3`, `Viewport2`)
turns that core into the public `Editor3`/`Editor2`, which differ
only in their viewport.
The graph pane is `Pxui_graph.Scope`: a left-to-right canvas over workspace text (polyline wires, zones, editable
literal rows, typed sockets, live drives written as `t` expressions). `Pxui_graph.Node_menu` is its categorised add
menu. `Editor_document.Layout_by_path` is the UI-free saved layout shared by the host and canvas. Graph/list/text
views (the Lisp pane is editable) and `.rays` sketches follow `flow-migration.md`. Value nodes, compounds and
expression drives were deleted in Gap A.
`rays.pxui_graph` supplies deterministic initial layout,
persistent graph-space tile positions, ordered ports/wires, topology-safe node
dragging, independent inspector/display selection through each tile's VIEW
button, selection clearing, captured pan, zoom, and framing. `Rays_editor.Editor3.run`
and `Editor2.run` compose both in a splitter-resizable, independently
collapsible workspace of panels (view, graph, list, lisp, inspector, outline, timeline) whose
default is the view/graph/inspector columns at 45/35/20; a workspace's `(graph editor …)` replaces the
layout (`Editor_core.Panels`, `specification/workspace/plan.md` W10).
The workspace defaults to a light viewport background. Every 3D/SOP editor
shares a Renderer section with Raster, Wireframe and Path traced choices.
`Editor3.renderer` reads it and `set_renderer` queues a choice for the next
update. The choice saves with viewport preferences; switching the common
renderer retains cooked geometry. A sketch's existing renderer setting uses
the same control and custom renderer. Standalone 2D art drawing paths are separate.
The inspector shows camera/render controls with no selection and generated SOP
parameters with a selection. Display selection cooks the flagged node while
retaining the previous successful preview. Overlay callbacks receive a
view-local frame. Both environments retain one shared pause/stop/reset,
dependency-aware cooking, status, selection, inspection, and finite native
lifecycle. Both expose `update_with` for sketch-owned inspector widgets and
`can_undo`/`can_redo` for the shared document history.

One immutable document holds everything a user edits and saves: the scene of
objects (as its own node network), each geometry object's SOP network and
the World's layer stack with their tile positions and display nodes, the
active camera object, and sketch `Settings` (a typed `Editor_core.Param`
record passed as `?settings`). History (128 entries) snapshots that
document, so moving a tile, an object, or changing a sketch setting is one undo
step. Each network saves positions, detail levels, pins, row exposure and
wire bends in its layout record. An edit frame updates only the node ids
and destination ports it touched; a preset load or automatic layout takes
a complete snapshot. Pointer gestures seal on release; detail changes
merge as a one-second burst.
Settings show in the unselected inspector, are saved in presets, and reach
`prepare settings output`; `set_settings` changes them from code. The
viewport camera enters history only while a camera object follows it. The
scene level, list projection, and World are described in `scene.md`.
Entering a scene camera by `i`, double-click or the row menu selects the
render camera and enables look-through; repeated Enter keeps that view.

Settings changes reconcile with the workspace before entering history: a
settings graph owns its values; otherwise they live in workspace metadata.
Opening without an explicit host settings override preserves those values.
A full preset loads omitted fields from schema defaults. In document text,
an absent settings form keeps the supplied fallback, while an explicit
`(settings ...)` starts from defaults. Startup window configuration and the
cook seed currently take effect when the host starts, rather than on an edit.

Both editors autosave document edits and viewport navigation to one atomic
`.rays` recovery file under `~/.rays/<name>/state` (or `<presets>/state`).
The source file's absolute path identifies a file-backed sketch; other sketches
use their workspace name. Writes coalesce at most twice a second, and close
flushes pending edits. An unchanged opening preserves the previous recovery.
`Space b` lists it as **Last edited state**; Enter validates and restores it as
one undo step, and Delete twice removes it. This includes applied Lisp edits,
external source reloads, settings, graph layout and camera navigation. Failed
writes appear in the status and retry. The source file changes only on explicit
Save.

#### Sketch workspace keys

`Space` (with no text field focused) opens a centered which-key panel; the
next key runs a command from the editor keymap, one list of pure-data
`Editor_core.Command.t` entries (`id`, `label`, optional `trigger`, optional
`scope`, `guide` contexts, `action`) that drives dispatch, the guide, the panel, and the `Space /` command
palette. Built-ins carry `Leader.action` payloads the update pipeline handles;
sketch `?commands` are the same entries whose action is a
`'prepared t -> 'prepared t` function run after the frame. Command/Ctrl
chords, Delete/Backspace, Home, and focus-dependent `F` use that same table;
`pxui_graph` exports its graph commands as entries without interpreting keys.
Entries without a trigger appear only in the palette. Global commands always apply; the others
belong to the focused pane (the last one clicked, marked by an accent rule
along its top). Escape, Space, an unknown key, a click, or focus loss cancel it.
Supplied commands validate at `create`: built-in IDs are reserved; aliases
share one action value; overlapping shortcuts and leader prefixes are errors.
Chord case and modifier order normalize once. Scoped commands are available
in the palette under the same focus condition as keyboard dispatch.
`Router.step` returns the exact matched Command entries in event order and
the remaining frame. Hosts dispatch their `action` values and use the
retained trigger and label for key feedback, including aliases.

Parameter schemas also carry presentation metadata: `Param.field ~primary`
marks a default card row, and `~vec3:(group, component)` groups float fields
with component indices 0, 1, 2. Field views preserve these annotations; they
do not change parameter values or cook keys. `[@sop.primary]` and checked
`[@sop.vec3 "center"]` annotations generate this metadata. SOP factories
also expose geometry input names through `Edit_graph.factory_slot_names`:
`[@@sop.node_slots "input, target"]` supplies names; omitted annotations
use `in0`, `in1`, and so on. Slot names must be distinct from parameter
names. Generated factories also expose field views; the editor uses those
views to filter Tab search to kinds whose parameter ports accept a dragged
value output.

The new `flow` library depends only on `param`. Its current value core
provides checked symbols, contexts, port types, scalar/vector coercions,
checked expressions and immutable value graphs;
the PPX uses its shared name validation. Geometry cannot connect to value
ports, and vectors cannot drive scalars. Float-to-int coercion rounds and
saturates the machine range before the caller applies the parameter's hard
bounds. Its six value kinds use typed `Param` schemas: Time, Value, Math,
Combine XYZ, Separate XYZ and Remap. Expression parsing returns errors with
source byte spans; infix and s-expression printers preserve the operation
tree.

`Flow_sop.Network` now keeps geometry, value literals and typed drives in one
immutable overlay. It rejects cycles, incompatible types, missing ports,
duplicate SOP/value ids and overlapping whole/component vector drives.
Copy/paste remaps internal geometry and value connections together. The
environment-owned `Value_lane` resolves reachable values before cooking,
normalizes hard bounds with the same `Param.normalize_value` kernel as
`Param.apply`, and preserves literal records. Unchanged effective values keep
the resolved geometry and cook keys; clearing a drive restores its literal.
`Exposure.shown` is the shared card visibility rule. The editor document,
graph clipboard now carry the overlay. The canvas
connects value outputs to visible or hidden parameter rows, filters typed Tab
results, and shows live wire readouts. The inspector displays drive sources,
applied values and reset controls; the cook adapter resolves dynamic values
before each visible-object submission.

`Flow_sop.Network.fold` converts an unshared tree of Math, Value and Time
nodes feeding one row into an expression, removing those nodes. It refuses
unsupported or shared sources with a diagnostic naming the node. `unfold`
builds Math nodes for operators and one shared Time node; numeric leaves
become input literals. The editor places them to the left of the target.
The row's stored literal remains available while an expression or wire drives
it. Wireless binds change only saved layout visibility, never evaluation.

| Key | Scope | Action |
|---|---|---|
| `s` / `b` | global | save preset (name prompt) / preset browser |
| `t` / `g` / `i` | global | toggle timeline / graph / inspector |
| `h` / `c` | global | hide all UI / camera section |
| `p` / `r` / `x` | global | play-pause / reset / stop |
| `a` | global | add menu of the open level (hover submenus, type to search) |
| `l` / `e` | global | graph → list → text → graph (map view in the World) / open the World |
| `f` | graph | frame displayed tile |
| `k` | global | grouped Flow key sheet |
| `w` / `v` | view (3D) | fly mode / look through render camera |

The table above lists keys after `Space`. With the graph focused:

The list and text projections use `j`/`k` to move between rows or bindings.
Enter opens the selected node in the graph. The text projection is read-only;
clicking a binding selects its node, and its header toggles qualified names.

| Key | Action |
|---|---|
| `h j k l`, arrows | walk through connections or to the nearest node in that direction |
| `Tab` | insert on the selected wire, append to one selected node, or add at the pointer |
| `.` / `c` | repeat the last add / connect by letter hints |
| `o` / `p` | open selected detail / toggle selected points |
| `⇧O` / `⇧P` | open all cards / toggle all points |
| `v` / `m` | display selected geometry / toggle bypass |
| `x`, Delete, Backspace / `⇧X` | delete selection / dissolve and reconnect the primary trunk |
| `/` / `f` / Home | find / frame selection or display / frame all |
| `⌘C/V/X/D`, Ctrl equivalents | copy / paste / cut / duplicate |
| `⌘Z` / `⇧⌘Z`, Ctrl equivalents | undo / redo |
| `b` / `w` | bind by hints or toggle a selected wire's wireless state / show wireless wires |
| `=` / `r` | edit the hovered row's expression / clear its drive or restore its default |

`?` toggles the contextual guide and delayed tooltips globally. The guide
starts on and saves its setting in `~/.rays/preferences.rays` through
`Editor_core.Store` (override with `RAYS_EDITOR_PREFERENCES`). Its strip
uses Command guide membership in table order. `Space k` shows the grouped
key sheet; key feedback lasts 1.5 seconds. Shared UI text focus owns typing
and modal dismissal. `Tab` runs Add in the canvas; `Shift-Tab` remains UI
traversal. World keys are `t`/`n`/`d`, described in `scene.md`.

The Document tab and whole-document Copy Lisp include saved layout and settings
metadata through the workspace codec. An absent layout form retains the current
layout; an explicit `(layout)` clears it. Text applies before the frame's cook
submission, so an awaited update renders the new document immediately. Empty
comparison scenes remain empty when focused or fullscreen; lights follow the
same instance membership as geometry. Common renderer slots use viewport keys,
including floating panels with identical bounds. A failed slot reports its
error while successful siblings remain visible.

The Lisp pane shows and edits the workspace text (`Rays_editor.Text_pane`: Selection, Graph and
Document tabs; Check and apply is atomic and one "Edit text" history entry). A sketch is a `.rays` file
(below); an OCaml host that needs its own code passes a workspace to `Editor3.run ?workspace`, for
example `Rays_editor.Workspace.load text` (see `sketches/flow_workspace/` for a finite
sketch driving every fixture). The catalog manifest `lib/sop_catalog/flow_manifest.sexp` is generated by
`dune exec tools/flow_manifest.exe` and checked for drift by the `sop_catalog` runtest rule; `dune promote`
accepts an intended catalog change. The `[%flow]` PPX, `Flow_sop.Build`, `Flow_sop.Program` and the
`?program` editor argument were deleted in W12; `?graph` was deleted in Gap A: every document is a workspace (`Workspace.load`, `Workspace.open_text`) and saves.
Plain keys: `i` enters the selected object or compound, `u` goes up and selects
the compound instance; in the view `w`/`e`/`r`
pick translate/rotate/scale handles and Escape hides them;
the list's WAI-ARIA keys and the World keys are listed in `scene.md`. Graph
layout is in the graph context menu and the palette only.

Graph-focused `f` frames the selection, or the display node with no selection. Viewport-focused
`F` frames the camera on the displayed node's cooked bounds through the shared
cook worker; in 3D it uses the orbit camera, and in 2D it centers and zooms the
pan/zoom camera. Escape still dismisses UI modes. A right
click (not a drag) opens graph context menus that emit the ordinary typed
graph changes. The timeline bar (hidden by default) has play/pause, stop,
reset, a frame/time readout, and a scrub slider that seeks (`Timeline.seek`)
and recooks. Its widgets return playback intents, and graph camera-framing
requests return in the workspace frame result; the host applies both after
`Ui.frame` completes. Preset prompts likewise return save/load/delete intents;
file I/O runs after the UI frame. The 2D and 3D camera panels return their
edited camera, control state, and render requests in that same frame result;
preset saves use the returned camera state, and navigation and render scheduling
run afterward. PNG render status is held in the environment model and updated
by the model returned from `after_present`.
The leader-key panel is `Pxui_shell.Which_key`; the sketch host supplies its
commands and focused-pane name. `Pxui_shell.Status_bar` paints the common kit
strip from host-provided status text, FPS, and pane bounds.
`Pxui_shell.Layout` gives a tree of panels (`Editor_core.Panels`: a leaf, a split, a tile or a
float) its geometry (a run of splits along one axis is one row of columns, so the default tree
is the standard 45/35/20), and `Pxui_shell.Chrome` builds the panels' headers with their
right-click menu (split, close, retype, dock/undock), disclosure and drag handles,
the drawn gutters, and the focused pane's top rule;
`Chrome.splitters` builds the one-point gutters' seven-point drag targets last, over the
panes. Chrome returns intents, never edits. Editor layout queries return
`Pxui_shell.Layout.panes` (the first view, graph and inspector); tests and other hosts
use Layout and Chrome directly. A host passes a `Layout.t` as `?layout`. `Rays_editor.Private` is explicitly unstable.
`Panels.state` holds saved disclosure and optional floating bounds.
`Layout.geometry ~state` applies them, and Chrome emits intents for the host to save. Floating
panels remain inside the editor. Named editor graphs appear in Shell layouts;
switching, arranging and collapsing panels enter document history and save in Lisp.
`Layout.leaf.floating` identifies both authored Float trees and undocked windows.
Hosts raise their pane roots with `Ui.to_front`; `Ui.scene ~under` inserts native
viewport content at the same body root, keeping paint and hit precedence together.
`Pxui_shell.Timeline_bar` returns playback intents from display values, and
`Pxui_shell.Prompt` builds name and search modals; the host interprets their
results and performs file I/O after the frame.
`Pxui_shell.Shell.frame` is the sketch workspace's `Ui.frame` caller for both
normal chrome and a pending leader overlay while the rest of the UI is hidden.
It also advances an empty frame when hidden, cancelling disappeared controls.
`Ui.input ~owner` returns the viewport root's ordered events after construction;
child widgets and popups consume their own input. Capture persists across pane
crossings until release or cancellation. Popup open and close frames consume
underlying input; overlays build before the body and paint last. Modal height
history retains at most 32 keys. History `Gesture` keys are strings naming the
operation and target; unrelated commands use `Step`, even during a drag.

Shortcuts, traversal, text selection and slider steps use the held keys at
each event. A modifier pressed or released later in the same frame cannot
change an earlier event. `Ui.key_events` exposes these contexts to custom
widgets; `Ui.press_keys` retains the keys at a pointer gesture's press through
release, which graph/tree selection and camera binding selection also use.
The shared Router accepts the previous frame's held keys, retained by the
editor. Fly movement still samples held keys for its continuous frame step.

PXUI's visible controls are keyboard stops. Tab/Shift-Tab traverse them in
presentation order and stay inside an open popup; Enter/Space use the same
click signal as pointer activation. Choices, sliders and XY controls accept
arrow keys. Sliders also support Home/End and Shift for larger steps; Enter
opens numeric entry, which accepts values beyond its soft range, and Escape
cancels. Range controls switch handles with Enter/Space. `Ui.tab_stop` gives
custom buttons the same traversal while retaining host shortcuts after
pointer use; Escape returns keyboard control to the host. Collapse, graph
VIEW/ACTIVE, and menu buttons use it. The Router yields unbound Tab and all
subsequent events in that frame to UI, preventing same-frame Tab/Space from
opening the leader. Existing tree indentation bindings remain available while
the tree owns keys. Wheel camera control uses the event's pointer position,
so a later pane crossing in the same frame cannot discard an owned wheel.

`Editor3` keeps camera objects (operation `camera`) in the scene: a
default one following the viewport is added to a scene without one, exactly
one is ACTIVE (tile button or context menu), and
`render_camera` drives look-through, PNG export, and sketch renderers such as
the voxel wall's path tracer. Follow-viewport writes coalesce into one undo
entry per gesture. The camera object's generated parameter schema is read
into a typed camera and follow flag and written from viewport edits, so the
host has no camera field names or copied defaults. Fly mode captures the pointer with
`Sketch.set_relative_mouse`; Escape exits and Space exits into the leader.
`Editor_core.Router` owns the fly-mode key filter; pointer and focus-loss events
still reach the workspace.
`Rays_pathtracer.render` accepts `Camera.t` directly, including its
`Camera.lens` (thin-lens aperture and focus distance). It currently supports
unshifted perspective cameras and returns an error for other projections,
forced aspect, or vertical flip.
Presets save a workspace document to `~/.rays/<sketch>/<name>.rays`, one
s-expression file: the `(workspace ...)` source with its comments, then
optional `(layout ...)` by path, `(settings ...)` and `(view ...)` forms
(`specification/flow.md` §4.4). Loading checks and lowers the source into one
geometry object per `sop` graph and is one undo entry; there is no older
format. Only a workspace document saves (open one with `?workspace` on
`Editor3`/`Editor2`; `Editor3.edit` applies a `Flow_sop.Flow_edit.op` as one
history entry named by the op). Scene and World edits made through the list, the inspector, the handles or the
World keys are written back to the text in the same frame (`Editor_document.Scene_sync`), so Save round-trips them;
`create ?await` makes each frame block on the cook it submits (a fixed-step run, a test); the crash report writes `document.txt` (a text
of any document) and `document.rays` for a workspace. Empty networks have no
display node and clear their preview. A preset that fails to parse, check or
lower leaves the installed state unchanged. The unstable
`Private.Document.object_network` test hook returns an optional display ID to
represent empty networks.

#### `.rays` sketches

`sketches/<name>/sketch.rays` is a whole sketch: one `(workspace ...)` form, no `main.ml`, no `dune`.
`rays-plisp check|ml|dune|fmt FILE` (`tools/plisp`) checks it with the editor's catalog (a typo fails
`dune build` at the `.rays` line), generates `main.ml` (the text embedded, its SHA-256 as `digest`) and
the stanzas of `sketches/dune.rays.inc` (checked in: `dune build @runtest; dune promote` after adding a
sketch; `dune exec tools/new_example.exe -- --plisp <name>` scaffolds one). The generated program is
`Rays_editor.Workspace.main ~path ~digest ~catalog text`; OCaml hosts call `Workspace.load` (parse and
check) and `Workspace.run ?source doc` (the window from the `settings` graph, the viewport starting at the
scene's first camera, a scene graph is authoritative: it replaces the host's camera and lights, and an empty one means none).

Scene light intensity and color accept expressions of timeline `t`; they are
resolved during composition without recooking static SOPs or rewriting saved
source/history. The gallery's key light demonstrates a sine pulse. Each preview
retains its own overridden light values. A failed live expression keeps that
light's last successful value while healthy siblings advance, and reports
`E_CONTEXT_LIVE` with view/field attribution; successful evaluation clears it.
Other scene/World/panel fields remain static and refuse time expressions with
`E_CONTEXT_TIME`. Window title, size, fps and seed apply on restart.

The running window follows the file. `Rays_editor.Source` finds it (the first `dune-project` not under
`_build`, walking up from the executable and then the working directory, joined with `path`). Command-S
(also Ctrl-S) rewrites it with the canonical text (`Workspace_doc.to_text`; comments kept, `;;` printed as
`;`) through a temporary file and a rename, but only while the file is still the text the document last
came from (its SHA-256 is the remembered digest); any other state falls back to a preset (`Preset.save`,
status "source changed since build; saved as preset ...") and never overwrites. Once a half second the frame
loop reads the source content/digest; a changed digest re-checks the text and replaces the document as one history
entry "Reload sketch.rays", keeping layout, settings, probes and selection by path; text that fails keeps
the last good document, shows the diagnostics in the Lisp panel's Document tab and the status bar, and a
later good text (also the last good one) reloads. The editor's own write updates the digest first, so it
does not reload. There is no three-way merge and no file-system events (`ponytail:` polling).

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

`Rdk.Boolean.run ~piece_attribute:name` exposes the same optional cell
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
- Built-in sketch PNG saves default to `_out/`; `Canvas.save_screen_png` creates
  a missing output directory and honors an explicitly supplied path.
- width, height, title, FPS and window behavior are optional configuration.
- cleanup is exception-safe.
- `Sketch.quit ()` requests graceful termination.
- `Sketch.render_target ()` returns the sole `Native` target.

The native runtime uses the ordinary `Event.t`, `Input`, and logical `Frame`
contracts for pointer, keyboard, UTF-8/IME, focus, resize, and file-drop facts.
See [the runtime/backend specification](./backend.md).

### `Parallel`

Rays targets OCaml 5 and may create a reusable Domainslib work-stealing pool
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
- Scene/UI colors are byte-channel `Color.t`. The path tracer uses
  `Rays_pathtracer.Linear_color.t` for floating-point linear/HDR light and
  material values; conversion to byte colors happens only at image output.
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
8. live reload or a documented Dune watch feedback loop.
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
# Post-present work

Workspace surface assignment is described in [workspace/materials.md](workspace/materials.md).
`Flow.Context.Material` and `Flow.Ty.Material` type reusable material graphs;
`Procedural.Sop.material` assigns them to primitive groups, and the generic
`.rays` host uses `Sketch_support.Surface` for material batches and explosion.

`Sketch.run_state` accepts `?after_present`, called with the current model and
frame after `Scene.render`. It returns the model used on the next frame and
passed to `on_stop`. Use it for framebuffer capture or other work that needs
the completed native frame, such as recording a PNG save result in the model.
The view remains a pure scene description.
