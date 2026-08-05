# Procedural SOP graphs

Status: first coherent graph and core-node iteration implemented.

## Product intent

`prismel.procedural` combines Processing-style immediacy with a non-destructive
SOP workflow. A new user should be able to construct, animate, inspect, and
render an interesting model without learning packed storage. The same
`Pdk.Geometry.t` remains available to advanced users who descend to native
kernels; there is no separate easy-but-slow geometry model.

The common path is a functional pipeline:

```ocaml
let terrain =
  Sop.grid ~columns:180 ~rows:180 ~size:12. ()
  |> Sop.noise_displace ~amplitude:0.7 ~frequency:0.18 ~seed:42
  |> Sop.color_by_height ~low:Color.indigo ~high:Color.orange
```

One-input modifiers pipe naturally. Multi-input nodes use descriptive labels,
for example `Sop.copy_to_points ~source:tree ~targets:points ()`. Familiar words
are preferred in this layer (`attribute`, `primitive`, `geometry`); abbreviated
HDK vocabulary remains available in the expert PDK namespace.

## Ownership and dependency boundary

Procedural owns immutable graph nodes, operator contracts, parameter/context
dependencies, validation, diagnostics, cooking, inspection, and bounded
session caches. It may use PDK, Geom, and public Prismel value semantics. It
does not import Runtime, Wap, SDL, or browser policy.

Cooking produces an immutable `Pdk.Geometry.t`. An explicit bridge converts it
to `Prismel.Mesh.t`, which `Scene3` renders through the same native, headless,
and web path. A cook context may copy scalar facts from `Prismel.Frame.t`, but
it must not retain a canvas, renderer, texture, or backend handle.

`Procedural.Instances.t` is a separate packed value: it retains one prototype
node plus a packed array of immutable transforms. It is not itself editable
topology.
`Bridge.cook_to_scene3` cooks/caches the prototype once and constructs the
instance node with one transform-array copy. `Bridge.cook_to_instances` returns
an owned transform copy for callers that need custom scene assembly. Use
`Sop.unpack` is the explicit boundary back to editable topology: it applies
every instance transform into one copy-major `Pdk.Geometry.t`, or can retain
prototype-space coordinates while materializing overlapping copies. Use
materialized `Sop.duplicate` for the simpler regular-transform sequence.

## Nodes and cook contract

A graph is an immutable DAG. Shared OCaml values create shared subgraphs. Each
node has a stable ID, human-readable label, operation/version, immutable
parameters, ordered inputs, cook mode, and declared context dependencies.

Cook modes distinguish generators, input duplication, uniquely owned in-place
opportunities, instances, passthroughs, and generic operations. They describe
optimization opportunities; correctness never depends on a compiled/fused
execution path.

An operator receives a self-contained context, typed parameters, immutable
input snapshots, and operation-local scratch. It cannot reach back into a UI
node. Failures carry the node path and preserve the structured PDK cause.
Warnings such as removed degenerates, recomputed normals, and empty selections
are accumulated deterministically rather than printed from worker domains.

Ordinary graphs are acyclic. Feedback, solvers, and time-history state require
an explicit separate iteration contract; an accidental cycle is always an
error.

`Sop.triangulate` and `Sop.reverse` wrap the corresponding packed PDK kernels.
Triangulate accepts an optional named primitive group, passes unselected
polygon/curve primitives through exactly, and rejects a selected curve.
Reverse accepts an optional named
primitive group and either reverses winding or applies a signed cyclic corner
shift. Missing groups become traced node diagnostics; group resolution,
validation, cancellation, normal policy, exact payload remapping, and
parallelism remain owned by PDK rather than being reimplemented by the graph
layer.

`Sop.normals` exposes the same owner, weighting, cusp, typed component
selection, zero-preservation, reversal, and override-name contract as PDK.
Its cache identity includes every control, and missing groups become traced
diagnostics before the kernel is called. Procedural does not compute or cache a
second set of normals.

`Sop.measure_curvature` wraps the single packed PDK surface-curvature kernel.
Its stable node identity includes boundary policy, smoothing controls, point
group, and every optional output name. Point-group resolution and structured
manifold diagnostics remain graph-boundary concerns; triangulation, incidence,
metric estimation, smoothing, and output preservation are not reimplemented in
the cook closure. The operation is static and topology-preserving.

`Sop.attribute_laplacian` uses the same PDK-owned surface metric and topology
index as curvature. Its identity contains the point group, weighting,
normalization, source, and output names. The cook closure resolves only the
named point group and delegates numeric storage conversion, manifold checks,
stable polygon triangulation, mixed-area normalization, incidence reduction,
and immutable output replacement to PDK. It is static and topology-preserving;
no matrix or solver state is hidden in the procedural session.

## Context, parameters, and determinism

The target-neutral context contains finite time, frame number, immutable seed,
domain/grain settings, and a cancellation token. Fixed-step sketches supply
their deterministic frame/time facts through `Context.of_frame`. Each node
declares exactly which facts affect it. A static box is not invalidated merely
because time advanced.

Constant parameters are ordinary OCaml values. Time/frame expressions, ramps,
easing, remapping, and deterministic noise are opt-in parameter values and mark
their owning nodes with the corresponding dependency. Random operations derive
stable streams from the user seed, stable node identity, and element index.
Domain count and work-stealing order cannot affect geometry or diagnostics.

`Sop.attribute_fade` is the reference frame-dependent attribute node. Its
parameter key contains both ramps, all timing/name controls, and the roles of
its optional second and third graph inputs, while its context projection
contains only `Frame`. Re-cooking the same graph at another wall-time, seed, or
domain count therefore hits the same bounded cache entry; advancing the frame
invalidates it. This makes the node safe inside the explicit previous-snapshot
iteration model without putting mutable feedback inside a SOP cook.

`Sop.poly_cut` is static and encodes the primitive group, owner-specific cut
group, element/strategy/detection variants, threshold field, and closure policy
in canonical cache identity. Group names are resolved only against the cooked
input; PDK owns classification, interpolation, compaction, and ancestry. This
keeps custom iterative curve sketches compositional: a previous snapshot may
feed PolyCut without storing temporal state or mutable fragments in the node.

`Sop.separate_pieces` is also static. Its cache identity contains owner,
integer/text identity field, translation field, normalized-axis input, gap,
and Separate/Move Back mode. PDK computes the reversible per-piece mapping;
the SOP cook owns neither bounding state nor a retained lookup table. This is
particularly useful before per-piece proximity work in an iterative sketch:
separate, query or modify, then move back without introducing graph feedback.

`Sop.edge_equalize` is static as well. Its cache identity includes the input
and output edge-group names, typed initial target policy, iteration ceiling,
and relative tolerance. The graph cook resolves topology-affine selection and
delegates target reduction, selected incidence, projection, convergence, and
normal invalidation to PDK. It retains no iteration buffers in the node or
session, so an iterative sketch may equalize its previous snapshot without
turning the acyclic per-frame SOP graph into a hidden feedback solver.

`Sop.edge_relax` is a static two-input node whose role key distinguishes source
from matching-topology reference. Point/primitive selection, point pins,
individual or scale-independent reference targets, iterations, step size,
shorten-only policy, and tolerance all participate in cache identity. It is a
useful custom-sketch building block: a previous immutable snapshot can be the
source while a stable design shape supplies rest edge lengths, with all
temporary constraint buffers confined to one cook.

`Sop.blend_shapes` is a static multi-input morph node. Input zero remains the
topology and payload owner; subsequent immutable `Sop.blend_shape` descriptors
carry finite weights and optional source/shape mask overrides. The cook builds
integer/text point-ID maps only when requested, allocates every blended plane
once, and applies targets in descriptor order while point ranges execute in
parallel. No delta, ID, mask, or weight plane survives outside the completed
snapshot/session entry, so an iterative sketch can animate weights by building
a new acyclic node without hidden history growth.

`Sop.attribute_composite` is the general static multi-input attribute fold.
Input zero owns topology and unselected payload; additional
`Sop.attribute_composite_input` descriptors retain node role, stable order, and
finite global weight. Independent owner patterns, first-input weight,
Mean/Maximum/Minimum/Over/Under mode, optional alpha name, and explicit `P`
eligibility all participate in node identity. Attribute discovery, packed
planes, alpha distribution, finite/cardinality validation, and normal
invalidation live exclusively in PDK. No intermediate composite or denominator
plane survives outside the completed immutable snapshot/session entry, making
the node safe to rebuild inside an iterative sketch.

`Sop.attribute_mirror` is a static one-input correspondence node. Its graph
value stores owner, method, named groups and mapping field, attribute pattern,
transform policy, text replacement, and optional metadata names. Named groups
are resolved from the current immutable input at cook time; PDK owns the
reflected spatial search, direct-index mapping, packed payload copies, and
atomic validation. Plane point/primitive and explicit point/vertex/primitive
mapping paths write disjoint ranges through the shared pool. No spatial index,
source map, destination bit-plane, or output builder survives outside the
completed snapshot/session entry, so it is safe to reconstruct around
`Sop.snapshot previous` in an iterative sketch.

`Sop.rewire_vertices` is a static one-input topology modifier. The node stores
only typed selection, target owner/name, recursive-chain policy, target-field
deletion, newly-unused-point cleanup, and optional original-point provenance.
Selection names resolve against each immutable input cook. PDK owns target
validation, functional-graph resolution, corner rewiring, point payload/group
compaction, normal invalidation, and native-edge ancestry. Temporary target,
state, stack, incidence, and compaction planes become unreachable after the
new snapshot is committed, so iterative sketches can author changing
connectivity without hidden mutable graph state.

`Sop.edge_transport`, `Sop.edge_transport_curves`, and
`Sop.edge_transport_parent` are static attribute-flow nodes over the same
immutable PDK snapshot. The network node resolves point and explicit-root
groups at cook time, the curve node resolves a primitive group and schedules
independent curves by stable primitive ranges, and the parent node resolves an
integer point-parent field plus an optional point group. Network and Parent
support forward copy/split and backward Add/Maximum/Minimum branch merging.
None retains a parent forest, distance plane, child index, or normalization
table in the graph cache beyond the completed geometry. Iterative sketches may
therefore transport a field from the previous `Sop.snapshot` without hidden
feedback or unbounded per-frame state.

## Sessions and caching

Mutable evaluation state belongs to an explicit `Session.t`, never a global
graph. Its cache has both an entry limit and a retained-byte budget. The key is
the operator/version, canonical parameters, exact input snapshot IDs, declared
context facts, and explicit external-resource fingerprints. Whole geometry
buffers are not rehashed on every frame.

Cache hits return the same immutable snapshot. Results are inserted only after
a complete successful cook; cancellation cannot publish partial geometry.
Eviction drops strong references, `Session.clear` releases all entries, and
`Session.close` provides prompt lifetime control. Session statistics expose
cooks, hits, misses, evictions, retained bytes, and last-node timings.

Independent branches may cook in parallel only when measured work justifies
it. Fine-grained PDK kernel parallelism is the default. Nested evaluation shares
Prismel's one process-wide pool and must not oversubscribe it.

## Selection, attributes, and inspection

The approachable API uses typed, composable selections rather than beginning
with a group-expression language. Named groups can capture a selection for
reuse. Standard typed helpers cover `P`, `N`, `Cd`, `uv`, `v`, `id`, `pscale`,
`scale`, `orient`, and `up`; arbitrary attributes retain explicit owner and
storage types.

Inspection is part of the first release, not debug-only infrastructure:

- graph inspection reports node labels, operations, inputs, parameters, and
  time dependencies;
- cooked inspection reports element counts, memory estimate, attributes,
  groups, cache state, duration, domains, and grain;
- DOT export makes sharing and pipeline structure visible;
- errors identify graph path, input number, actual and expected geometry, and
  a likely corrective operation where possible.

## Implemented core nodes

The first coherent set includes:

- graph: null, merge, lazy switch, bounded session cache, graph/DOT inspection,
  and cooked geometry inspection;
- generators: immutable feedback snapshot, points, finite directed polygon or
  free-point Line, explicit polyline, production Box with triangle/quad,
  surface-point, and volume-lattice output, independent divisions, optional
  boundary welding, point/vertex normal policies, full Euler transform,
  per-face UVs/groups, production UV Sphere with regular/alternating triangles,
  quads, open row/column curves and points, shared/unique pole policies,
  ellipsoid radii, arbitrary pole axes, full Euler transforms, point/vertex
  normals and seam-safe UVs, production Torus with triangle/quad/curve/point
  connectivity, independent signed U/V ranges and wraps, polygon end caps,
  arbitrary hole axes, full Euler transforms, point/vertex normals and
  seam-safe UVs, production Tube with cylinder/frustum/cone geometry,
  triangle/quad/curve/point connectivity, consolidated or independent cap
  rims, hard-cap normals, UVs, cap groups, arbitrary axes and full Euler
  transforms, production Platonic Solids with all five regular convex solids
  plus the truncated-icosahedron soccer ball, natural N-gon faces, radial/hard
  normals, face groups, black/white primitive color and complete transforms,
  production Spiral with Archimedean/logarithmic profiles, turns or pitch
  extent, piecewise-linear height/radius ramps, equal-angle or integrated
  equal-arc sampling, phase-distributed copies, arbitrary axes/full Euler
  transforms, and optional angle/frame/orientation/distance attributes,
  production polygon-curve Revolve with arbitrary axes, full or open arcs,
  point/row/column/combined/quad/triangle connectivity, compact shared poles,
  optional polygon caps, normalized UVs, typed primitive restriction, complete
  payload ancestry, and exact parallel edge-range fills,
  production Circle with
  closed/open/chord/sliced arcs, ellipses, standard/custom planes and complete
  polygon transform controls, and production
  Grid with division/point-count resolution, point/row/column/quad and three
  triangle-connectivity modes, standard/custom plane frames, independent
  dimensions, center/rotation, normals, and optional normalized UVs;
- modifiers: raw-matrix or typed TRS/shear/pivot Transform with six affine and
  Euler orders, inversion, typed point/vertex/primitive/native-edge restriction,
  and explicit inverse-transpose/recomputed normal policy; Soft Transform with
  closest-radius, exact edge-path, or authored point-weight metrics, three
  rolloff profiles, inspectable falloff output, and normal repair; Distance
  Along Geometry with typed start/affected selections, exact geometric
  edge-path distance, unreachable sentinels, fixed or maximum-distance masks,
  and bounded mask-only cooking; Distance From Geometry with independent typed
  source/reference restrictions, closest reference-point or polygon-surface
  metrics, raw distance, fixed/maximum masks, and distance-only packed index
  queries; Distance From Target with spherical point, cylindrical axis, and
  absolute or signed planar analytic projections, typed affected restriction,
  and fixed/maximum masks; stable point/primitive Sort with deterministic
  random permutation, point topology/incident-primitive keys, Morton spatial
  locality, strict reorder-by-index, and composable indirect rank output;
  Blast by Attribute with scalar float/integer point or primitive fields,
  strict threshold and inclusive range/width modes, named base restriction,
  inversion, delete/group output, and primitive unused-point cleanup;
  Crease with all or named native-edge selection, coherent add/set/delete of
  Subdivide-ready vertex sharpness, and optional endpoint color visualization;
  materialized cumulative
  or non-cumulative Duplicate with optional primitive-source restriction,
  exact copy-major ancestry, and bounded per-copy primitive groups, reverse,
  triangulate, normals, production Clean pipeline with
  point consolidation, degeneracy/overlap/NaN repair, winding, compaction, and
  attribute/group cleanup, delete,
  normal-directed Peak, captured Bend/Twist in arbitrary frames, and
  deterministic Perlin-fBm Mountain with typed selection/mask/capture,
  custom-direction, and normal-recompute controls,
  deterministic Point Jitter with a point group, linearly applied float mask,
  stable integer IDs, overall/per-axis scales, and optional point `pscale`,
  topology-affine Edge Divide with an exact resulting segment count, shared or
  per-incidence inserted points, complete packed payload/group interpolation,
  connected-component Edge Collapse with center reduction, exact point-field
  partitions, degenerate cleanup, and optional existing-normal recomputation,
  manifold polygon Edge Flip with general mixed-face cycles, optional
  vertex-payload cycling, validity checks, and exact native-edge ancestry,
  Edge Cusp path-interior fan splitting with endpoint fade behavior, complete
  point payload/group duplication, and optional existing-normal rebuilding,
  Point Split unique-corner or mixed vertex/primitive attribute and named-group
  seam clustering for point/vertex/primitive selections, with inclusive
  tolerance, optional attribute promotion, stable point numbering, and exact
  one-to-many ancestry,
  cardinality-first Point Generate for no-input origin clouds or deterministic
  selected-source emission, with scaled expected counts, probability fields,
  every packed point payload, detail-copy patterns, retained topology,
  generated groups, and source/local provenance,
  Point Replicate local point/box/sphere/disk/line/custom clouds over the same
  emission plan and canonical instancing frames, with stable ID streams,
  quasi coordinates, shape ancestry, source payload, retained input, velocity
  synthesis/stretch, rest-space coherent noise, and optional copied-vector or
  inverse-transpose normal transformation through those same frames,
  connected-component Edge Straighten with stable least-squares line fitting,
  exact collinear identities, branch/cycle support, and output edge groups,
  Circle from Edges over topology boundaries or native edge groups, with
  scale-normalized least-squares plane/circle fitting, explicit radius/scale,
  and output edge groups,
  Graph Color over typed promoted selections with point-clique, primitive-
  shared-point, or primitive-shared-polygon-edge connectivity, optional stable
  color sorting and packed detail workset ranges,
  Triangulate 2D over exact-predicate packed Delaunay topology with named point
  groups, native-edge and primitive-perimeter constraints, opt-in exact
  crossing construction/atomization, exact authored-point-on-constraint
  splitting without synthetic duplication, generated-point groups,
  exact constraint-blocked convex-hull outside flooding,
  exact non-zero winding removal from closed constraint primitives,
  exact projected-face silhouette constraints and outside removal independent
  of global face orientation,
  optional constraint-endpoint-only seeding with ignored source points retained
  as isolated immutable payload,
  optional exact projected-duplicate removal that preserves unrelated unused
  or unselected source points,
  bounded incremental constrained-Delaunay refinement with minimum-angle,
  maximum-area, target-edge-length, minimum-edge-length, constraint-splitting,
  maximum-new-point, and refinement-point-group controls,
  deterministic exact-certified regularization of generated interior points,
  optional movement of original projected interior points, and compact
  provenance-DAG interpolation across repeated relaxation,
  optional shared-kernel unused-point compaction and conditional existing-point
  normal recomputation,
  optional retention of every non-constraint input polygon/curve as a stable
  prefix with exact fixed/ragged vertex and primitive payload, ordered-group,
  and native-edge ancestry plus typed defaults for the generated triangle
  suffix,
  explicit original-position restoration policy, including projected world-
  plane output for PCA/principal/explicit planes and XY output from the first
  two components of a point coordinate attribute,
  PCA/principal/explicit/attribute projection, deterministic insertion seed,
  deterministic split-point payload policy, and output triangle and
  constrained-edge groups,
  Edge Equalize with average/longest/shortest initial targets, a direct
  independent-edge path, bounded deterministic connected projection, and
  explicit convergence diagnostics,
  reference-driven Edge Relax with exact topology matching,
  individual/scale-independent length targets, point/primitive restriction,
  pinning, shorten-only policy, and the shared bounded constraint projector,
  deterministic forward/backward Edge Transport over shortest-path edge
  forests and integer parent forests, plus a linear independently parallelized
  Each Curve point/vertex fast path,
  optional orphan-point compaction, individual-face or connected-region Poly
  Extrude with named primitive selection, split-edge seams, straight divisions,
  independent front/back/side output, and primitive/native-boundary groups,
  deterministic point-group-restricted fuse and per-axis grid snap with
  movement tolerance, moved-point output, and optional exact consolidation;
  Fuse supports a read-only second target and independent target group,
  least-number/closest near targets, specified integer target points,
  point-radius expansion, equal/unequal scalar match filters, snap-only mode,
  and stable snapped-point/destination metadata. Same-input Modify Target,
  complete first/least/greatest, component-statistical and weighted position
  reducers, Keep Fused Points, repeated-vertex/degenerate cleanup, and
  selective or complete unused-point compaction share the packed PDK kernel.
  Ordered attribute/group pattern rules cover numerical, text,
  scalar-to-array/array concatenation, weighted, union/intersection, and
  strict-majority policies; fixed targets copy matching point payload and
  target-only groups while remaining immutable,
  arbitrary-plane mirror, arbitrary-plane clip with numeric point-coordinate
  attributes, normalized-normal distance or transform-derived placement,
  typed point/vertex/primitive/native-edge restriction with selected-boundary
  isolation, split/fill controls, and replace-or-union native clipped edges and
  primitive output groups, including disconnected concave-fragment
  reconstruction and winding-aware nested cap holes/islands,
  Catmull-Clark/Loop/bilinear subdivision with
  semi-sharp creases, a typed second topology input with named primitive
  restriction/override/result controls and point-number edge matching,
  stencil-contributing automatic/named hole faces with final-level removal,
  and
  named primitive-group local Do Not Close, Pull
  Closed/No Edge Division, Pull Closed/Divide Edges or Triangulate with bias,
  and Stitch/No Edge Division, Divide Edges, or Triangulate refinement, with
  optional topology-stable collinearity-independent closure,
  two-input closest/directional Ray projection with bounded seeded multi-ray
  jitter, average/median/shortest/longest combination, exact collision
  provenance, and attribute/group import, typed Convex Hull with exact affine
  and horizon decisions, deterministic lower-dimensional/closed-solid output,
  point/detail ancestry and generated face metadata, Extract Centroid over the
  detail, primitives, or stable integer/text pieces with point-mass, bounds,
  or the same exact hull core, Extract Point from Curve with constant,
  per-primitive, or current-time scalar cuts plus interpolated point/copied
  primitive payload and curve diagnostics, typed divided-box or
  sphere/ovoid Bound with asymmetric padding and detail/group metadata,
  bounding-box convenience, Match Axis, and production Match Size with
  independent typed move/source/target selections, unit/numeric or node
  references, per-axis/cross-anchor alignment, offsets, and bounds/metric fit
  modes;
  typed topology editing: point/vertex/primitive Delete with destroy/heal and
  selected/non-selected policies, named-group Blast, and cache-sharing
  selected/remainder Split branches;
- topology groups: native topology-affine Edge Group with primitive,
  incidence, length, face-dihedral, and pairwise incident-edge angle filters;
  named edge groups remain
  distinct from side-specific outgoing-corner vertex groups; Group from
  Attribute Boundary finds typed point/vertex/primitive discontinuities and
  emits native-edge, point, or primitive selections with tuple tolerance and
  unshared-curve policy; Groups from Name creates stable, explicitly bounded
  point or primitive groups from non-empty text values with replace/union and
  ignore/force-valid naming policy, while Name from Groups converts selected
  point/vertex/primitive groups back to a compact text partition with explicit
  overlap and source-deletion policy; Group Random provides context-seeded or
  explicitly seeded point/vertex/primitive/native-edge chance selection with
  base restriction and packed merge algebra; Group Bounds provides inclusive
  box/sphere selection with full/partial primitive and geometric native-edge
  containment; Group Normal provides geometric or explicit-attribute
  direction/spread selection for points, primitives, and native edges with an
  optional opposite cap, while Group Non-Planar provides stable
  tolerance-based polygon selection and additive union composition; Group
  Backface selects winding-derived polygons relative to a viewpoint and can
  subtract them from another same-name criterion; Group Edge Depth performs
  bounded shortest-edge growth from a point group; Group Unshared selects
  one-sided topology as points, primitives, or native edges, while Group
  Boundary Components emits stable, bounded point groups for each connected
  polygon-surface boundary; Group Promote
  converts among every point/vertex/primitive/native-edge owner using touching,
  complete-containment, or shared-edge rules and can emit an ordinary-owner
  integer mask instead of a group; ordered Group Promotions compile wildcard
  selection/capture rewrites, safely snapshot same-rule sources, allow later
  rules to re-promote earlier outputs, and bound output count/payload; Group
  Promote Boundary retains only the
  converted selection frontier and can union typed attribute seams, controlled
  polygon/curve unshared edges, and point-sharing primitive boundaries, while
  Group Expand performs
  signed topology steps or a connected-component flood over every owner and can
  materialize the first-change/BFS distance as an integer attribute. Point and
  edge-connected primitive growth can additionally stop at an adjacent normal
  spread, typed point/vertex/primitive attribute discontinuities, or an
  independently owned collision boundary; collision membership can contain
  growth and boundary elements can be retained or excluded. Attribute and
  collision seams also define shrink-away boundaries; Group
  Range supplies absolute/relative/partition ranges and periodic filters,
  optionally evaluated independently over stable disconnected point or
  primitive regions with a one-region restriction,
  Group Combine and Invert provide four-owner packed boolean algebra, Group
  Delete/Rename provide ordered wildcard metadata rules, and two-input Group
  Copy maps membership by indices, primitive-local corners, or integer/text
  attributes; two-input Group Transfer maps point, primitive, and native-edge
  membership by accelerated exact geometric proximity and preserves ordinary
  source-group order using source sequence, proximity, and stable index ties;
- topology paths: Group Find Path builds ordered point-edge or manifold
  primitive-dual paths through contiguous ordered bases or start/end pairs,
  with stop/close endings, same-owner shared-element avoidance and collision
  exclusion/containment, and parallel independent routes;
- attributes/groups: typed constant float/int/vector/quaternion/color creation,
  exact-name delete/rename plus atomic owner-pattern Attribute Delete with
  reference-name prepend and keep mode, ordered capture-pattern Attribute
  Rename with skip/error/overwrite conflicts, ordered owner-specific Attribute
  Swap/Move/Copy with paired capture globs, packed payload sharing, missing-side
  copy behavior, and canonical float3 `P` handling, dense integer/prefixed-text
  enumeration within typed groups with integer/text piece-element or stable
  piece-ID modes,
  planar/cylindrical/spherical vertex UV projection with primitive-group,
  seam, pole, and range controls, point/vertex UV transforms, automatic native
  angle/partition/existing-UV seam groups with stable island IDs, and
  per-face/per-island UV unit fitting, seam-aware harmonic UV flattening, and
  boundary-preserving UV relaxation,
  promotion across every geometry owner with deterministic mode/upper-median
  reductions, integer/text destination-piece partitions, and shared-plan
  plural promotion through compiled include/exclude name globs with optional
  aligned multi-term destination/index capture renaming, exclusion terms, and
  last-match precedence; deterministic contributing-source indices for scalar
  reductions and fixed-width float2/3/4 component-source CSR rows; documented
  text/index Average-to-median, Sum-concatenation, and numeric-to-First policy;
  plus packed scalar integer/float Array of All and sorted Unique Values CSR
  output with complete piece-row remapping; direct
  ordered/cyclic Attribute Copy with
  integer/text value or explicit-element matching, owner-independent topology
  projection, wildcard renaming, and structural sharing for identity plans;
  fused multi-input Attribute Combine across all numeric PDK storage with seven
  arithmetic modes, preprocessing, tuple conversion, per-element blending,
  integer/text correspondence, grouped postprocessing, and atomic cleanup;
  primitive/UVW or packed CSR point/vertex/primitive number-and-weight
  Attribute Interpolate from owner-compatible source fields into point,
  vertex, primitive, or detail destinations, with equivalent computed
  point/vertex weight output, signed-sum normalization/threshold influence,
  zero-sum preservation, inclusive group thresholding, opaque greatest-
  coefficient packed array-row transfer, canonical position support, exact
  group-pattern destination restriction, compiled
  owner-specific source-attribute/group expansion, weighted source-group
  membership, one atomic packed cook, and deterministic polygon/curve
  parameter spaces;
  nearest/inverse-distance and compact Links/RenderMan/Hart k-nearest
  point and primitive-barycenter transfer with independent sample count/radius
  and exact or compiled-pattern
  owner-matched groups and shared full-strength/blend-band controls,
  closest-polygon vertex transfer, structurally shared detail transfer, and
  explicit mixed-owner polygon-surface sampling into target points, vertices,
  or primitive barycenters with optional distance output; primitive and
  vertex source groups can intersect the sampled surface, with explicit
  all-corners or any-corner triangle retention; one
  `attribute_transfer_all` node can cook explicit point/vertex/primitive/detail
  patterns while sharing each owner's query plan and committing metadata once; native
  range kernels, typed packed or explicit-order group construction and
  combination, and deterministic
  connectivity-based `attribute_blur` over `P` and multiple point floating
  attributes with edge weighting, masks, pins, and custom iteration steps;
  dedicated topology-preserving `smooth` composition with primitive
  restriction, locked points, unshared/group-boundary constraints, and exact
  parallel alternating low-pass passes over the same packed kernel;
  two-input `ray` projection through the shared packed polygon surface index,
  including source/collision groups, normal/vector/attribute directions,
  deterministic direction/surface policies, bounded seeded cone jitter,
  average/upper-median/shortest/longest successful-hit combination, hit
  outputs, and compiled collision field/group import;
  indexed deterministic `attribute_randomize` across every owner with typed
  cross-owner/native-edge group expansion, seed or fraction attributes,
  arithmetic modes, bounded tails, isotropic multidimensional Cauchy, and
  twelve production distributions including spherical, inverse-CDF ramp, and
  weighted tuple/text sampling; component-wise `attribute_remap` with explicit/automatic
  ranges, clamp/cycle/extrapolate, renaming, and piecewise-linear ramps;
  frame-only `attribute_fade` with a scalar point field, point restriction,
  independent equal-cardinality start/hold inputs, affine start retiming,
  float/integer timing attributes, per-point hold scaling, separate linear
  ramps, and optional grayscale point-color visualization;
  PolyCut with primitive plus point/native-edge restriction, remove or cut
  topology, all-edge/scalar-crossing/tuple-change detection, exact inserted
  endpoints, optional closed fragments, and every-owner payload/group ancestry;
  Separate Pieces with point/primitive integer or text identities, arbitrary
  packing axis and gap, same-owner float3 translations, strict rigid-piece
  validation, deterministic Move Back, and packed multicore position fills;
- analysis: bounds; stable point/primitive `Sop.connectivity` with owner-correct
  point/primitive masks, native edge seams, vertex-UV islands, and integer or
  prefixed-text classes; and generalized `Sop.measure` for
  primitive-group polygon area, curve/polygon perimeter, oriented signed
  volume, per-element/throughout accumulation, and optional detail totals;
- creative workflows: deterministic fixed-count surface Scatter with primitive
  groups, owner-typed density, compiled attribute/group transfer, and exact
  primitive/source-vertex-weight provenance; expanded copy to points
  with the standard `pscale`/`scale`, `orient` or `N`/`v`/`up`, post-`rot`,
  `pivot`, and `trans` stack plus packed affine `transform` overrides, count-
  or length-driven arc-length curve; Copy to Points also resolves named source
  primitive and target point restrictions before its packed expansion and
  supports integer/text source primitive or source point piece attributes,
  integer primitive-number fallback, unmatched-target omission, and stable
  target-major variant ordering; it
  applies last-match-wins point/vertex/primitive target-attribute and
  target-group rules afterward, including explicit `Nothing` overrides,
  resampling with primitive-group/count/length overrides and optional
  U/curve/distance/tangent fields, packed `Sop.polyframe` point or
  seam-preserving vertex coordinate fields, and primitive-group curve carving
  with inside/outside/all-piece cuts, exact unselected topology pass-through,
  seam-aware closed complements, equal-parameter divided cuts, and divided
  free-point extraction,
  Catmull-Clark/bilinear polygon-curve Subdivide with recursive shared-graph
  cubic refinement, local primitive restriction, mixed surface/curve cooks,
  Houdini-compatible independent curve-corner point identity, default
  point-stencil `N`, and opt-in final recomputation only when point `N`
  existed on the input,
  native-edge-group `Sop.edge_divide` for equal-parametric cuts on polygon and
  polygon-curve edges, with shared coincident points by default and an explicit
  unique-points mode,
  native-edge-group `Sop.edge_collapse` using the shared Fuse reducer for
  stable center contraction, topology/payload ancestry, and cleanup,
  adaptive `Sop.poly_reduce` using deterministic QEM-ranked independent
  contraction batches, ratio/absolute targets, primitive restriction, hard
  points/edges, strict boundary locking, original-position and normal-deviation
  controls, topology validity checks, and the same shared Fuse ancestry core,
  isotropic `Sop.remesh` using fused midpoint subdivision, independent
  link-condition contractions, valence-improving flips, constrained relaxation,
  and optional packed-BVH projection, with uniform or point target sizes, hard
  points/native edges, UV-seam preservation, diagnostic outputs, and exact
  one/multi-domain topology and payload ancestry,
  optional one/two-input `Sop.boolean_detect` using deterministic internal triangulation,
  packed two-pass BVH pair discovery, locally normalized crossing/touching and
  optional coplanar tests, independent source/collision primitive restrictions,
  and source-owned AxB intersection group, sorted collision-primitive CSR, and
  row count outputs without changing source topology or payload; its one-input
  AxA mode visits unordered pairs once, suppresses shared-topology-only contact,
  and emits symmetric self-intersection group/CSR/count outputs,
  optional one/two-input `Sop.intersection_analysis`, which emits point-only
  triangle, polygon-curve, and mixed intersection geometry instead of passing
  either input through, welds repeated piece-pair events in stable
  first-incidence order, and attaches aligned point-owned
  input/primitive/parameter/incident-point CSR
  provenance for later attribute interpolation and seam construction,
  native-edge-group `Sop.poly_bevel` for watertight partial or connected
  two-sided polygon fillets, with chamfer/round divisions, point-scale and
  flatness controls, collision-limited ring slides, connected corner handling,
  generated face/boundary groups, packed payload interpolation, and exact
  one/multi-domain output,
  typed-selection `Sop.point_split` for unique selected corners or deterministic
  vertex/primitive attribute and named-group seams, with ordered globs,
  inclusive tolerance, optional attribute promotion, and the shared packed PDK
  point-remap core,
  `Sop.point_generate_origin` and connected `Sop.point_generate` over the same
  packed emission kernel, with point-group selection, context-derived or
  explicit immutable seeds, stable cache identity, copied payload patterns,
  retained input, generated grouping, and exact one/multi-domain order,
  `Sop.point_replicate` for shaped high-density point clouds, with a second
  immutable custom-shape graph when requested and complete cache identity for
  distribution, standard source transforms, count scaling, velocity, and
  noise controls, including the copied-vector transform pattern,
  native-edge-group `Sop.dissolve` for stable manifold face merging,
  disjoint/bridged/deleted hole policy, optional boundary curves, and inline
  plus unused-point cleanup through the shared PDK topology core,
  native-edge-group `Sop.edge_flip` for deterministic general-polygon boundary
  rotation, with explicit sequencing for flips that share a primitive,
  native-edge-group `Sop.edge_cusp` through the shared Facet point-fan kernel,
  preserving selected path endpoints and splitting only effective interiors,
  native-edge-group `Sop.edge_straighten` using independent packed component
  fits and deterministic principal-axis projection,
  boundary/native-edge-group `Sop.circle_from_edges` using the single PDK
  component planner and normalized plane/circle fitter, with no graph-local
  topology or projection implementation,
  typed-selection `Sop.graph_color` using the single PDK union-find/incidence
  coloring core and shared Sort remapper, with no graph-local adjacency or
  topology implementation,
  native-edge-group `Sop.edge_equalize` using the shared PDK target reduction
  and centroid-preserving connected projection rather than a graph-local
  geometry loop,
  two-input `Sop.edge_relax` with role-complete cache identity and PDK-owned
  reference-length planning/iteration,
  multi-target `Sop.blend_shapes` with normalized/differencing weights,
  source/shape masks, point-ID matching, fixed-width point payload blending,
  exact target-order accumulation, and PDK-owned temporary plans,
  ordered `Sop.attribute_composite` with independent owner patterns, weighted
  Mean/Max/Min/Over/Under folds, optional same-owner alpha, opt-in `P`, and
  allocation-once PDK-owned temporary/output planes,
  `Sop.attribute_mirror` with plane-nearest or named explicit correspondence,
  all packed storage kinds, destination-only transformations/replacement,
  cook-time group resolution, complete cache identity, and PDK-owned scratch,
  `Sop.rewire_vertices` with point/vertex/primitive integer targets, typed
  selection promotion, recursive point chains, provenance/cleanup controls,
  and exact packed payload plus native-edge ancestry,
  static `Sop.edge_transport` network, `Sop.edge_transport_curves`, and
  `Sop.edge_transport_parent` wrappers with complete parameter identity,
  cook-time group/parent resolution, and PDK-owned temporary traversal storage,
  ordered, typed point/vertex/primitive/native-edge-selected `Sop.facet`
  normal, point-sharing,
  point/normal consolidation,
  inline-point removal, manifold orientation, dihedral-angle hard-edge cusping,
  degenerate cleanup, and conflict-safe polygon planarization stages,
  ordered `Sop.group_ranges` batches with blank disabled slots and later-rule
  base/collision/merge dependencies,
  manifold-hole `Sop.poly_fill` with native-edge
  auto-completion and shared/unique N-gon, concave-safe triangle, or averaged
  triangle-fan patches,
  selected unique-edge conversion to canonical line primitives or fused
  maximal paths with endpoint-distance/endpoint-only/loop-closure controls
  and optional final path length,
  polygon/curve Ends with open, straight-close, shared-seam unroll, or
  payload-duplicating new-seam unroll, detail-ordered, ordered-group, explicit
  user-picked-end, or global closest-end curve joining with fixed-size
  subgroups, optional original retention, and stable welding/component
  policies, packed `Sop.poly_loft` triangulation across
  unequal open/closed curve or polygon sections with closest/rest-guided
  pairing, U/V wrap, source retention, and exact payload ancestry, packed
  `Sop.skin` construction that retains quads for equal-cardinality linear
  polygon sections and uses the same zipper for unequal sections, direct
  multi-component `Sop.poly_bridge` surfaces between simple native edge paths
  or loops with authored/centroid pairing, reverse/shift controls, input
  retention, uniform equal-cardinality straight divisions, packed payload/group
  interpolation, and exact boundary ancestry, and shared circular
  `sweep_circle`/`polywire` with primitive-group restriction and exact
  unselected pass-through, point-varying radial divisions, point-driven
  endpoint-averaged longitudinal segmentation, deterministic minimal
  triangle/quad ring transitions, point scale, snapped seam, authored
  V/joint-up attributes, constant or outgoing-corner segment placement,
  optional UV generation, constant or outgoing-corner U/V ranges,
  capped constant/point-authored radial joint miters, constant/point-authored
  smoothing and maximum-valence disconnection into real uncapped runs,
  outgoing-corner per-edge snapped texture seams, closed-frame correction, and
  hard-normal caps;
  two-input general-profile `sweep` with typed curve groups, all Grid
  connectivity modes, the five backbone tangent policies, closed-continuous
  roll/twist, standard point transform attributes, caps, UVs, and prefixed
  dual-input attribute/group/native-edge ancestry;
  terminal `Sop.pack`/`Sop.duplicate_packed` transform instancing without
  topology multiplication, plus explicit `Sop.unpack` materialization before
  downstream per-copy topology edits;
- expert extension: `Sop.custom` defines an inspectable node from PDK or
  Geom/Pdk adapter composition with explicit version, parameter identity,
  cook mode, context dependencies, and cancellation responsibility;
- terminal conversion to Prismel mesh, instance, and scene values.

The undocumented Blinn/Wyvill/Elendt transfer kernels and multi-sample vertex
kernel policy, ordered-edge Group Find Path ownership
and its remaining loop/ring/extension,
UV, mixed-owner collision, and boundary constraints, Group from Attribute
Boundary base-group conversion and degenerate-bridge cleanup, reversible
`encodeattrib` naming for Groups from Name, direct assignment/string-edit modes
for Name from Groups,
Group Promote degenerate-bridge cleanup and indexed-capture substitution,
Group Expand constrained vertex/edge targets, shared-point primitive seam
semantics, group patterns/type inference, edge-owned distance output (edge
groups intentionally have no attribute owner), and parallel component
labeling, remaining
distance kernels,
packed-instance attribute-driven transforms, multiple packed prototypes and
packed piece matching, per-instance payloads, Boolean resolved output mode
and source restriction/naming controls (the public exact
`Sop.boolean` already exposes solid/surface products, per-input
self-intersection resolution, full primitive/point/vertex payload and group
transfer, exact native-edge ancestry, point conflict promotion, seam-point
splitting, named solid Shatter pieces, bounded strict/diagnostic tiny-seam
cleanup, safe source-polygon detriangulation, and closed rounding
verification, while `Sop.boolean_seam` exposes named left-self, between-input,
right-self, and coincident-patch products), and the remaining
documented Remesh adaptive/group/boundary controls,
volumes, fracture,
native edge-group seam heuristics,
SCP/ABF flattening constraints, UV unwrap/layout, and a convenience iterative sketch-feedback
wrapper remain later work. A public placeholder is
not used for an operation that lacks a real result contract.

## Iterative creative sketches

Iterative creative sketches keep feedback outside the per-frame DAG. A
`Sketch.run_state` model owns the previous `Pdk.Geometry.t`; each fixed-timestep
update wraps it with `Sop.snapshot`, composes ordinary SOPs or `Sop.custom`
PDK/Geom work, cooks the next immutable value, and replaces the previous one.
The graph for each step remains acyclic and independently inspectable.

Only current/next snapshots are application-live by default. The associated
`Session.t` must have explicit entry and payload-byte limits, so prior cook and
mesh results age out predictably; optional history/checkpoints need a separate
bounded ring. Pure heavy kernels still use the reusable domain pool, then join
before mesh conversion and rendering. Render-only repetition should remain an
`Instances.t` transform payload rather than being fed back as multiplied
topology. This is enough for erosion-like iteration, growth, relaxation,
agent-written trails, reaction fields converted to geometry, and similar
creative feedback without claiming a rigging, dynamics, or VFX solver suite.

Point Jitter makes the minimal random-walk form concrete: each fixed update
wraps the prior snapshot, applies `Sop.point_jitter ~seed:step_seed`, cooks the
new snapshot, and stores only that result. Use an integer ID attribute when
topology edits may renumber points, and derive `step_seed` from the immutable
sketch seed and step number. A point mask or `pscale` can carry persistent
per-point influence without allocating a history plane. The same pattern can
replace Point Jitter with a composed Geom operation or a typed PDK custom
kernel; feedback ownership and memory bounds do not change.

Rest and motion data use the same explicit boundary. `Sop.rest_position`
stores, extracts, or swaps packed reference positions and optional point
normals; a second input can supply the reference snapshot without copying its
numeric planes. `Sop.point_velocity` accepts explicit previous and/or next
snapshot inputs for backward, forward, or central finite differences. Integer
or text IDs preserve correspondence across deterministic topology edits,
central mode can emit acceleration, and a point group restricts writes while
preserving existing values elsewhere. There is no implicit time-shift cook or
retained previous-frame node state: the sketch model owns those snapshots.

A reusable custom procedural node is therefore an ordinary function from
immutable parameters and input `Node.t` values to `Node.t`. Its implementation
composes public SOPs when possible and uses `Sop.custom` only for a missing
PDK/Geom kernel, with an explicit operation/version/parameter key. A sketch
solver may run one iteration per frame or several iterations until a measured
time/work budget is exhausted, but deterministic/export runs use an explicit
iteration count rather than a wall-clock cutoff. It commits only a complete
next snapshot.
It never exposes a half-mutated geometry if cancellation or a deadline fires.
This keeps realtime iteration memory proportional to current/next geometry,
bounded session state, and explicitly bounded optional history.

## Research basis

The design was checked through 2026-08-04 against SideFX's primary documentation:

- [SOP concepts](https://www.sidefx.com/docs/hdk/_h_d_k__data_flow__s_o_p.html)
  for cooking and changed-input duplication;
- [Solver](https://www.sidefx.com/docs/houdini/nodes/sop/solver.html) for the
  explicit previous-frame feedback model, [Rest Position](https://www.sidefx.com/docs/houdini/nodes/sop/rest.html)
  for reference-space storage, and [Point Velocity](https://www.sidefx.com/docs/houdini/nodes/sop/pointvelocity.html)
  for finite-difference motion and ID matching;
- [Dissolve 2.0](https://www.sidefx.com/docs/houdini/nodes/sop/dissolve.html)
  for edge-complement selection, bridge and boundary policies, inline cleanup,
  unused-point policy, and normal regeneration;
- [Blast by Attribute](https://www.sidefx.com/docs/houdini/nodes/sop/blastbyattribute.html)
  for point/primitive run-over ownership, base restriction, threshold/range/
  width selection, inversion, delete/group output, and primitive orphan-point
  cleanup;
- [Crease](https://www.sidefx.com/docs/houdini/nodes/sop/crease.html) for edge
  selection, Add/Set/Delete behavior, `creaseweight` authoring for Subdivide,
  and optional vertex-color visualization;
- [Attribute Fade](https://www.sidefx.com/docs/houdini/nodes/sop/attribfade.html)
  for point restriction, fade/start/hold-scale fields, role-specific reference
  inputs, affine frame retiming, in/hold/out timing, transition ramps, and
  visualization;
- [Attribute Composite](https://www.sidefx.com/docs/houdini/nodes/sop/attribcomposite.html)
  for stable input order, per-owner attribute patterns, global weights,
  same-owner alpha, opt-in P, and the five documented compositing operations;
- [Attribute Mirror](https://www.sidefx.com/docs/houdini/nodes/sop/attribmirror.html)
  for source/destination policy, point/primitive plane correspondence, explicit
  mapping, attribute transforms and literal text replacement, pair output, and
  side groups; topology traversal and plane-based vertex matching remain
  explicitly outside the current subset;
- [Rewire Vertices](https://www.sidefx.com/docs/houdini/nodes/sop/rewire.html)
  for owner-dependent selection expansion, invalid-target preservation,
  recursive point chains/cycles, target deletion, newly-unused cleanup, and
  original-point provenance;
- [PolyCut](https://www.sidefx.com/docs/houdini/nodes/sop/polycut.html) for its
  point/edge modes, remove/cut strategies, threshold crossing and change
  subdivision behavior, group restrictions, and closed-fragment policy;
- [Separate Pieces](https://www.sidefx.com/docs/houdini/nodes/sop/separatepieces.html)
  for integer/text piece identity, reversible translation metadata, and the
  two-input union-bound intent; its undocumented layout remains an explicit
  Prismel axial-packing contract;
- [Edge Equalize](https://www.sidefx.com/docs/houdini/nodes/sop/edgeequalize.html)
  for selected-edge equal-length intent, average/longest/shortest initial
  target policies, and output edge grouping; its unpublished numerical solver
  remains an explicit Prismel convergence contract;
- [Edge Relax](https://www.sidefx.com/docs/houdini/nodes/sop/edgerelax.html)
  for point/primitive restriction, matching-topology reference positions,
  individual/scale-independent targets, iterations, step size, pins,
  shorten-only behavior, and the explicitly deferred surface/anisotropy tabs;
- [Edge Transport](https://www.sidefx.com/docs/houdini/nodes/sop/edgetransport.html)
  for graph/curve methods, scalar operations, direction, roots,
  normalization, split/merge, and the explicitly audited remaining modes;
- [PolyReduce 2.0](https://www.sidefx.com/docs/houdini/nodes/sop/polyreduce.html)
- [Remesh 2.0](https://www.sidefx.com/docs/houdini/nodes/sop/remesh.html)
  for polygon/ratio targets, original positions, quad/boundary/seam/feature
  preservation, density/view/attribute weighting, and rest-geometry behavior;
- [PolyBevel](https://www.sidefx.com/docs/houdini/nodes/sop/polybevel.html)
  for edge eligibility, connected bevel networks, profile and collision
  policy, point scaling, and generated group contracts;
- [Point Split](https://www.sidefx.com/docs/houdini/nodes/sop/splitpoints.html)
  for selected shared-point separation, vertex/primitive seam attributes,
  per-dimension tolerance, group seams, and optional point promotion;
- [Extract Centroid](https://www.sidefx.com/docs/houdini/nodes/sop/extractcentroid.html)
  for whole-detail, primitive, and piece center modes and output metadata;
- [Extract Point from Curve](https://www.sidefx.com/docs/houdini/nodes/sop/extractpointfromcurve.html)
  for constant, primitive-attribute, and current-time cut sources, extracted
  point/primitive payload patterns, and curve diagnostics;
- [Circle from Edges](https://www.sidefx.com/docs/houdini/nodes/sop/circlefromedges.html)
  for selected geometry boundaries, optional radius/scale, and transformed
  edge-group output;
- [Graph Color](https://www.sidefx.com/docs/houdini/nodes/sop/graphcolor.html)
  for point/primitive connectivity, stable sorting, and detail workset arrays;
- [Point Generate](https://www.sidefx.com/docs/houdini/nodes/sop/pointgenerate.html)
  for origin and connected emission modes, count/probability attributes, input
  retention, payload patterns, generated groups, and source metadata;
- [Point Replicate](https://www.sidefx.com/docs/houdini/nodes/sop/pointreplicate.html)
  for input-group cloud replication, count scaling, local shapes, standard
  copy transforms, stable IDs/rest noise, velocity controls, payload,
  provenance, custom-shape ancestry, and generated groups;
- [Labs Measure Curvature](https://www.sidefx.com/docs/houdini/nodes/sop/labs--measure_curvature-3.0.html)
  for the artist-facing mean/Gaussian/principal curvature intent, smoothing,
  visualization, and downstream scatter/reduction use;
- [Measure 2.0](https://www.sidefx.com/docs/houdini/nodes/sop/measure.html)
  for scalar/vector attribute Laplacian intent, integrated versus area-divided
  output, and smoothing/sharpening use;
- [Laplacian](https://www.sidefx.com/docs/houdini/nodes/sop/laplacian.html)
  for cotangent and uniform/Tutte weighting distinctions and the explicitly
  separate sparse-matrix/linear-solver boundary;
- [Garland and Heckbert's QEM paper](https://www.cs.cmu.edu/~garland/Papers/quadrics.pdf)
  for compact ten-coefficient face-plane quadrics and iterative contraction,
  and [Papageorgiou et al.](https://doi.org/10.1371/journal.pone.0255832)
  for independent-region parallel contraction structure;
- [SOP NodeVerb](https://www.sidefx.com/docs/hdk/class_s_o_p___node_verb.html)
  and [CookParms](https://www.sidefx.com/docs/hdk/class_s_o_p___node_verb_1_1_cook_parms.html)
  for UI-independent operators, cook modes, parameters, inputs, and scratch;
- [Groups from Name](https://www.sidefx.com/docs/houdini/nodes/sop/groupsfromname.html)
  for point/primitive text classification, empty values, prefix/conflict/name
  policy, and its explicit high-group-count memory warning;
- [encodeattrib](https://www.sidefx.com/docs/houdini/vex/functions/encodeattrib.html)
  for the reversible `xn__` policy that remains a documented compatibility gap;
- [Name](https://www.sidefx.com/docs/houdini/nodes/sop/name.html) for the
  efficient text-partition representation, group-mask inverse conversion, and
  its explicitly undefined multi-group overlap behavior;
- [Group Create](https://www.sidefx.com/docs/houdini/nodes/sop/groupcreate.html)
  for random-chance, seed-attribute, owner, base, initial-merge,
  direction/spread/opposite-normal, vertex exclusion, and additive non-planar
  semantics, its distinct backface subtraction policy, and pairwise
  shared-point edge-angle selection and point-seeded edge depth;
- [compiled blocks](https://www.sidefx.com/docs/houdini/model/compile.html)
  for static parameter resolution, in-place chains, and piece parallelism;
- [Attribute Wrangle](https://www.sidefx.com/docs/houdini/nodes/sop/attribwrangle.html),
  [Scatter](https://www.sidefx.com/docs/houdini/nodes/sop/scatter.html),
  [Smooth 2.0](https://www.sidefx.com/docs/houdini/nodes/sop/smooth.html),
  [Ray](https://www.sidefx.com/docs/houdini/nodes/sop/ray.html),
  [Fuse 2.0](https://www.sidefx.com/docs/houdini/nodes/sop/fuse.html),
  [Bound](https://www.sidefx.com/docs/houdini/nodes/sop/bound.html),
  [Match Size](https://www.sidefx.com/docs/houdini/nodes/sop/matchsize.html),
  [Copy to Points](https://www.sidefx.com/docs/houdini/nodes/sop/copytopoints-.html),
  and [Sweep](https://www.sidefx.com/docs/houdini/nodes/sop/sweep.html) for the
  initial artist-facing vocabulary;
- [Line](https://www.sidefx.com/docs/houdini/nodes/sop/line.html),
  [Clean](https://www.sidefx.com/docs/houdini/nodes/sop/clean.html),
  [Poly Extrude](https://www.sidefx.com/docs/houdini/nodes/sop/polyextrude.html),
  [Revolve](https://www.sidefx.com/docs/houdini/nodes/sop/revolve.html),
  [PolyFill](https://www.sidefx.com/docs/houdini/nodes/sop/polyfill.html),
  [PolyWire](https://www.sidefx.com/docs/houdini/nodes/sop/polywire.html),
  [Convert Line](https://www.sidefx.com/docs/houdini/nodes/sop/convertline.html),
  [PolyPath](https://www.sidefx.com/docs/houdini/nodes/sop/polypath.html),
  [Carve](https://www.sidefx.com/docs/houdini/nodes/sop/carve.html),
  [Join](https://www.sidefx.com/docs/houdini/nodes/sop/join.html),
  [PolyLoft](https://www.sidefx.com/docs/houdini/nodes/sop/polyloft.html),
  [Skin](https://www.sidefx.com/docs/houdini/nodes/sop/skin.html),
  [PolyBridge](https://www.sidefx.com/docs/houdini/nodes/sop/polybridge.html), and
  [Ends](https://www.sidefx.com/docs/houdini/nodes/sop/ends.html) for the
  polygon-curve subset and its explicit spline/surface boundary;
- [UV Auto Seam](https://www.sidefx.com/docs/houdini/nodes/sop/uvautoseam.html),
  [UV Flatten](https://www.sidefx.com/docs/houdini/nodes/sop/uvflatten.html),
  and [Labs UV Unitize](https://www.sidefx.com/docs/houdini/nodes/sop/labs--uv_unitize.html)
  for seam/island graph vocabulary and unit-fit modes.
- [GA Edge Group](https://www.sidefx.com/docs/hdk/class_g_a___edge_group.html)
  and [Group](https://www.sidefx.com/docs/houdini/nodes/sop/group.html) for
  topology-affine edge identity and artist-facing incidence/angle filters.
- [Group Promote](https://www.sidefx.com/docs/houdini/nodes/sop/grouppromote.html)
  and [Group Expand](https://www.sidefx.com/docs/houdini/nodes/sop/groupexpand.html)
  for four-owner conversion, complete/shared-edge inclusion, signed topology
  steps, flood fill, adjacent-normal limits, attribute-defined connectivity,
  and collision containment/boundary policy.
- [Group Range](https://www.sidefx.com/docs/houdini/nodes/sop/grouprange.html),
  [Group Combine](https://www.sidefx.com/docs/houdini/nodes/sop/groupcombine.html),
  [Group Invert](https://www.sidefx.com/docs/houdini/nodes/sop/groupinvert.html),
  [Group Delete](https://www.sidefx.com/docs/houdini/nodes/sop/groupdelete.html),
  [Group Rename](https://www.sidefx.com/docs/houdini/nodes/sop/grouprename.html),
  and [Group Copy](https://www.sidefx.com/docs/houdini/nodes/sop/groupcopy.html)
  for named-group lifecycle, boolean algebra, range, remapping, and documented
  conflict behavior.

The OCaml API is intentionally smaller and strongly typed. It adopts documented
workflow concepts without copying Houdini source or wire formats.
