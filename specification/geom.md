# Functional geometry toolkit

Status: broad geometry, mesh, spatial, physics, voxel, SVG, and visualization
release implemented; the namespace audit below remains the completion source of
truth.

## Purpose

`prismel.geom` is a wrapped sibling library. It depends on `pdk` and `prismel`; the core
`prismel` library does not depend on it. The library supplies immutable
geometry values and deterministic algorithms for generative design while
reusing Prismel's `Vec2`, `Vec3`, `Path`, `Scene`, and `Mesh` boundaries.

The design was informed by
[thi.ng/geom](https://github.com/thi-ng/geom), especially its functional
data-transformation philosophy and its separation of platonic geometry from
rendering adapters. thi.ng/geom is licensed under Apache-2.0. Prismel's OCaml
implementations are native implementations of the documented algorithms, not
a source-level translation.

## Dependency and effect boundary

```text
examples ──> prismel.geom ──> pdk ──> prismel ──> tsdl/tsdl_gfx
```

All geometry constructors, queries, transforms, subdivision, triangulation,
and mesh generation are pure. `Render2` creates pure `Scene.node` or `Path.t`
descriptions. Actual drawing still happens only at `Scene.render` inside the
normal Prismel lifecycle.

No geometry function reads `HEADLESS`, touches SDL, uses global random state,
or mutates a caller-owned collection. Inputs used for independent parallel work
can therefore be split safely with immutable `Rand.t` values.

## Single compute core migration

Geom remains the ergonomic functional API for mathematical values, curves,
polygons, fields, and friendly mesh entry points. PDK is the sole packed mesh
generation/topology/modeling core. Geom may adapt to and from
`Prismel.Mesh.t`; PDK never imports Geom. Existing Geom mesh algorithms migrate
one operation at a time with public compatibility tests, direct PDK tests, and
benchmarks, after which the duplicate Geom kernel is removed.

The first migrated operation is `Mesh_repair.weld`: it converts through the
zero-copy-capable PDK mesh bridge and invokes `Pdk.Ops.fuse` with first-position
and attribute-seam matching policies. The 200,000-point benchmark retains the
same 100,000-point result while improving the one-domain median from
64.5 ms/78.9 MB allocated to 50.2 ms/48.2 MB allocated.

`Mesh_topology` now adapts the same `Pdk.Topology_index` for edges, face
incidence, point neighbors, valence, face neighbors, and connected components;
its former tuple-key hash/list topology core has been removed. On the existing
1,280-triangle query fixture this reduces total allocation from 1.11 MB to
0.81 MB while preserving the 1,920-edge result; the small-fixture median is
0.256 ms versus 0.248 ms and is treated as overhead evidence, not a speedup.

## Modules

| Module | Contract |
|---|---|
| `Affine2` | Six-coefficient 2D affine matrices, composition, inversion, point and direction transforms |
| `Bounds2`, `Bounds3` | Axis-aligned bounds, mapping, expansion, union, containment, closest points, and intersection |
| `Ray2`, `Ray3`, `Plane3`, `Sphere3`, `Triangle2`, `Triangle3` | Validated shape values, metrics, transforms, and closest-point/barycentric queries |
| `Segment3`, `Quad3`, `Tetrahedron3`, `Frustum3`, `Curve3` | 3D segments, planar quads, tetrahedra, camera volumes, and sampled spatial curves |
| `Intersect2`, `Intersect3` | Typed ray hits and broad 2D/3D overlap/intersection tests |
| `Segment2` | Finite-segment metrics, closest points, classification, and intersection parameters |
| `Circle2` | Circle metrics, sampling, affine validation, intersections, and three-point construction |
| `Polygon2` | Simple polygons, area/centroid/boundary queries, hull, convex clipping, inset, ear tessellation, and radial generators |
| `Curve2` | Open/closed sampled curves, arc-length evaluation/resampling, transforms, subdivision, interpolating splines, and procedural formulas |
| `Delaunay2` | Bowyer-Watson triangulation, topology edges, and bounded Voronoi cells |
| `Render2` | Explicit pure adapters to `Scene.node` and `Path.t` |
| `Mesh3` | Extrusion, lathe, parallel-transport sweeps, and Loop, Butterfly, Catmull-Clark, and Doo-Sabin subdivision |
| `Mesh_io`, `Mesh_repair`, `Csg3` | STL/OFF I/O, topology diagnostics/repair, and BSP mesh booleans |
| `Mesh_topology`, `Mesh_attrib`, `Transport3`, `Util` | Adjacency/editing, functional UV generation, inspectable transport frames, interpolation/fitting, and aggregate metrics |
| `Iso3` | Scalar-field helpers and marching-tetrahedra isosurface extraction |
| `Quadtree`, `Octree` | Persistent generic spatial indexes with range/radius/nearest queries |
| `Verlet2`, `Verlet3` | Immutable particle worlds, springs, forces, and geometric constraints |
| `Voxel3`, `Svo3` | Persistent sparse occupancy, morphology, depth-addressed octree selection, and two surface extraction paths |
| `Svg_path`, `Svg`, `Svg3`, `Contour2`, `Viz` | Complete SVG path-data parsing, safe 2D/3D SVG output, scales, chart layouts, contours, heatmaps, and interval stacking |
| `Polyhedra3` | PDK-backed indexed regular tetrahedron, cube, octahedron, icosahedron, dodecahedron, and soccer-ball meshes |

Every public module has an `.mli`. Geometry records that benefit from direct
queries expose private fields; callers can read them but construction remains
validated.

## Curve behavior

`Curve2.t` stores a sampled point sequence and explicit open/closed topology.
Consecutive duplicate points and a duplicate closing point are removed at
construction.

- `point_at` uses normalized arc length. Open curves clamp; closed curves wrap.
- `sample_uniform` divides total length into equal spans no larger than the
  requested distance. Open curves include their final endpoint by default;
  closed curves do not duplicate it.
- Chaikin subdivision supports a configurable corner-cut ratio and retains open
  endpoints.
- Cubic subdivision inserts edge midpoints and applies uniform cubic B-spline
  weights to existing interior vertices.
- Bezier constructors sample quadratic or cubic control polygons.
- Catmull-Rom is an interpolating cardinal spline with configurable tension and
  samples per span.
- Spiral, rose, and Gielis superformula constructors are intended for direct
  generative illustration.

## Planar algorithms

`Polygon2.convex_hull` uses a monotonic chain. `clip_convex` uses
Sutherland-Hodgman clipping and accepts either clip winding. `inset` offsets
edge lines toward the polygon interior. It reports collapsed output but, like
the source of inspiration, does not promise a general concave straight
skeleton. `triangulate` uses ear clipping for simple polygons without holes.

`Delaunay2.triangulate` uses deterministic Bowyer-Watson insertion. Points
within the supplied epsilon are deduplicated, degenerate triangles are omitted,
and output triangles are counter-clockwise. Cocircular sets can have more than
one valid Delaunay diagonal; the stable input order determines which valid
triangulation is produced.

Bounded Voronoi cells are computed directly by clipping the requested bounds
rectangle against every pairwise perpendicular-bisector half-plane. This
method is deliberately independent of one chosen cocircular Delaunay diagonal,
keeps all cells finite, and ensures that the returned cells cover the bounds.

## Procedural meshes

All `Mesh3` functions return ordinary immutable `Prismel.Mesh.t` values and can
therefore use existing materials, shaders, instancing, export, framebuffer, and
headless rendering paths.

### Extrusion

`extrude` normalizes polygon winding, creates side quads as indexed triangles,
ear-clips optional caps, and emits hard face normals. Depth can be centered
around Z=0 or start at Z=0.

### Lathe

`lathe` interprets curve X as a non-negative radius and Y as height, then
revolves it around the Y axis. Open profiles can receive fan caps. Generated
UVs use rotation as U and profile progress as V; normals use an angle-aware
smoothing split.

### Parallel-transport sweep

`sweep` computes centered spine tangents, chooses a stable initial frame, and
transports its normal with the minimum rotation between successive tangents.
Each polygon profile is mapped into the transported normal/binormal plane.
This avoids the sudden twisting associated with choosing a fresh global up
vector at every spine point. Caps reuse polygon tessellation.

### Mesh subdivision

`loop_subdivide` adapts indexed triangle input through the shared PDK packed
kernel. Boundary vertices use the one-eighth boundary rule; interior vertices
use Loop's exact valence weights. New interior edge vertices include the two
opposite vertices. Colors and texture coordinates are preserved, and normals
are regenerated after refinement. Existing index connectivity is
authoritative: coincident seam vertices are no longer welded or discarded.

`butterfly_subdivide` retains its narrower compatibility kernel and applies the
interpolating eight-point stencil where full neighborhoods exist.
`catmull_clark` uses the same PDK refinement plan to generate face and edge
points plus valence-weighted vertex points; native PDK quads are tessellated
only at the `Mesh.t` adapter boundary. `doo_sabin` retains its compatibility
kernel and emits face, edge, and closed-vertex faces.

### Mesh exchange, repair, and booleans

`Mesh_io` reads and writes binary or ASCII STL and OFF. Existing core `Mesh`
support remains responsible for OBJ and PLY. `Mesh_repair` diagnoses connected
components, boundary/non-manifold edges, degenerate and duplicate faces. Its
repair pipeline welds compatible vertices, removes invalid faces, repairs
T-junctions, and propagates consistent outward winding. `Csg3` implements BSP
union, intersection, and difference while interpolating present vertex
attributes at split planes.

### Spatial, physics, and voxel data

`Quadtree` and `Octree` are immutable: insertion, deletion, filtering, and
mapping return new trees. Range, circle/sphere, and nearest-neighbor queries do
not touch SDL. `Verlet2` and `Verlet3` likewise return new worlds per step and
support locked or weighted particles, iterative springs, local/world forces,
and bounds or circle/sphere constraints.

`Voxel3` stores only occupied integer cells. It supports six/26-neighbor
queries, boundary selection, thickening, conversion to an `Octree`, exact
exposed-face meshing, and smooth occupancy isosurfaces through `Iso3`.
`Svo3` adds sparse-octree depth addressing: point updates populate immutable
leaf occupancy, `depth_at` reports the deepest populated branch along a query,
and selection can return unique cells or world-space centers at any clamped
tree depth.

### SVG and visualization

`Svg_path.parse` accepts absolute and relative `M/L/H/V/C/S/Q/T/A/Z` SVG path
commands. Smooth controls are reflected according to SVG rules and elliptical
arcs are converted to cubic Beziers. `Svg` builds escaped XML from pure element
values and exposes file output as an explicit result-returning boundary.

`Svg3` projects mesh facets through a core `Camera`, culls optional backfaces,
painter-sorts by normalized depth, and shades via a pure facet function.
`Viz` supplies invertible linear, logarithmic, and lens scales; major/minor
ticks; Cartesian and polar axes/projection; line, area, radar, scatter, bar,
heatmap, and marching-squares contour SVG layouts; and stable interval row
packing.

### Volumetric isosurfaces

`Iso3.extract` samples a finite scalar field on a caller-selected grid and
decomposes each cell into six tetrahedra. Linear edge interpolation places the
surface at the requested isovalue. Field values at or above the isovalue are
inside, and triangle winding plus optional gradient normals point toward lower
field values.

Sampling uses two deterministic passes over bounded XY-plane windows. The
first pass counts triangles per Z slab; the second resamples the pure field,
computes finite-difference gradients from neighboring planes, and fills one
exact output allocation. Auxiliary field memory is therefore O(XY), not
O(XYZ), while slab cells retain stable X/Y/Z output ordering and parallelize
over disjoint cell ranges.

High-density callers use `Iso3.extract_dense` with an `Iso3.Field` value.
Built-in fields are evaluated directly into reusable float-plane buffers;
custom fields receive a borrowed three-float XYZ sample. The legacy
`Vec3.t -> float` extractor remains convenient for small fields but allocates
one boxed point per sample by design.

The extractor returns an error for non-finite samples or an empty surface.
Resolution is explicit, so callers choose the detail/cost tradeoff. Built-in
field helpers cover signed spheres, inverse-square metaballs, and the
triply-periodic gyroid; arbitrary pure field functions work without another
public abstraction.

## Examples

- `examples/geom_curves` layers Chaikin subdivisions, superformula rings, a
  rose curve, and visible control points.
- `examples/geom_voronoi` creates 64 seeded moving sites, bounded colored
  Voronoi cells, and their Delaunay dual.
- `examples/geom_meshes` renders an extruded star, a lathed vessel, a
  parallel-transport helix, and a twice-subdivided icosahedron.
- `examples/geom_isosurface` renders a sphere-clipped gyroid sheet and a
  three-source metaball surface.
- `examples/geom_csg` compares union, intersection, and difference.
- `examples/geom_subdivision` compares all four mesh subdivision families.
- `examples/geom_physics` simulates a deterministic spring cloth.

Each example uses `Sketch.Fixed`, exits after three frames under `HEADLESS`, and
supports a deterministic single-frame export:

```sh
HEADLESS=1 PRISMEL_EXPORT_DIR=frames \
  dune exec examples/geom_voronoi/main.exe
```

## Capability map

The map keeps the original thi.ng/geom scope visible rather than redefining the
port around what currently exists.

| thi.ng/geom capability | Prismel status |
|---|---|
| Immutable 2D/3D shape types, metrics, transforms | Broad set implemented |
| Boundary sampling at resolution/uniform distance | Implemented for circles, polygons, and curves |
| Broad 2D/3D shape intersection matrix | Implemented for rays, segments, bounds, circles/spheres, planes, triangles, polygons, tetrahedra, and camera frusta |
| Convex hull | Implemented |
| Sutherland-Hodgman polygon clipping | Implemented |
| Simple polygon inset and tessellation | Implemented |
| Chaikin/cubic automatic curve generation | Implemented |
| Delaunay triangulation | Implemented |
| Bounded Voronoi cells | Implemented extension |
| Shape-to-scene adapters | Implemented for Prismel `Scene`/`Path` |
| 2D polygon extrusion | Implemented |
| 3D lathe from a 2D curve | Implemented |
| Parallel-transport sweep mesh | Implemented |
| Triangle mesh subdivision | Loop, Catmull-Clark, Doo-Sabin, and Butterfly implemented |
| Mesh repair and OBJ/PLY/STL/OFF export | Implemented, including T-junction repair; core owns OBJ/PLY |
| Mesh CSG booleans | BSP union/intersection/difference implemented |
| Verlet physics | Immutable 2D and 3D worlds implemented |
| Quadtree/octree spatial indexing | Persistent generic trees implemented |
| Sparse voxels and isosurface extraction | Persistent occupancy, depth-addressed SVO queries, octree conversion, exposed faces, and smooth extraction implemented |
| General SVG path parsing/export | Implemented |
| Visualization charts | Scales, Cartesian/polar axes, principal SVG layouts, heatmaps, contours, and interval stacking implemented |
| Mesh attribute generators and topology editing | Implemented through typed UV generators, face expansion, adjacency, immutable editing, repair, and core mesh attributes |
| GL adapters and shaders | Covered by Prismel core typed 3D APIs and the exhaustive `3d-parity.md` audit; platform-specific browser/Jogl adapters are outside the SDL backend scope |

Platform-host adapters are treated as backend-specific rather than geometry
algorithms. All portable upstream namespaces are mapped below to tested native
Prismel equivalents without reversing the sibling dependency direction.

## Namespace audit

This table is intentionally exhaustive over the upstream source namespaces.
“Core equivalent” means Prismel already supplies the capability with a tested,
native API; it does not mean the Clojure API shape was copied.

| Upstream namespace | Prismel mapping | Audit status |
|---|---|---|
| `aabb`, `rect` | `Bounds3`, `Bounds2` | Mapped |
| `attribs` | `Mesh_attrib`, core `Mesh`, and subdivision/CSG interpolation | Mapped |
| `basicmesh`, `indexedmesh`, `meshface` | Indexed immutable core `Mesh` and `Mesh.face` | Mapped |
| `bezier` | `Curve2`, `Curve3`, `Path` | Mapped |
| `circle` | `Circle2`, including tangent points | Mapped |
| `core`, `types` | Per-module immutable OCaml values and explicit functions | Mapped by design |
| `cuboid` | Core `Mesh.box`, `Bounds3` | Mapped |
| `gmesh` | Core `Mesh`, `Mesh_topology`, `Mesh_repair`, `Mesh3.saddle` | Mapped at Prismel's triangle-mesh boundary |
| `line` | `Segment2`, `Segment3`, `Ray2`, `Ray3`, `Curve2`, `Curve3` | Mapped |
| `matrix`, `quaternion` | Core `Affine2`, `Mat4`, `Quat`, `Camera` | Mapped; see `3d-parity.md` |
| `mesh.csg` | `Csg3` | Mapped |
| `mesh.io` | Core OBJ/PLY plus `Mesh_io` STL/OFF | Mapped |
| `mesh.ops` | `Mesh_repair` | Mapped for triangle meshes |
| `mesh.subdivision` | `Mesh3` Loop/Butterfly/Catmull-Clark/Doo-Sabin | Mapped |
| `path` | Core `Path`, `Svg_path`, sampled curves | Mapped |
| `physics.core` | `Verlet2`, `Verlet3` | Mapped |
| `plane` | `Plane3` | Mapped |
| `polygon` | `Polygon2`, `Polygon2.smooth` | Mapped |
| `polyhedra` | `Polyhedra3` | Mapped |
| `ptf` | `Transport3`, `Mesh3.sweep` | Mapped |
| `quad` | `Quad3` | Mapped |
| `spatialtree` | `Quadtree`, `Octree` | Mapped |
| `sphere` | `Sphere3`, core sphere mesh | Mapped |
| `tetrahedron` | `Tetrahedron3` | Mapped |
| `triangle` | `Triangle2`, `Triangle3` | Mapped |
| `utils` | `Util`, shape modules, bounds, sampling, barycentrics, mesh transforms | Mapped |
| `utils.delaunay` | `Delaunay2` | Mapped |
| `utils.intersect` | `Intersect2`, `Intersect3`, `Frustum3` | Mapped |
| `utils.subdiv` | `Curve2`, `Curve3` | Mapped |
| `vector` | Core `Vec2`, `Vec3`, immutable `Rand` | Mapped; global random helpers intentionally replaced |
| `voxel.isosurface` | `Iso3`, `Voxel3.surface_mesh` | Mapped |
| `voxel.svo` | `Svo3`, `Voxel3`, `Octree` | Mapped semantically; `Svo3` uses immutable bitmask/compact-child octree nodes with mutable bulk-build staging |
| `svg.core`, `svg.adapter` | `Svg`, `Svg_path`, `Render2` | Mapped for 2D geometry |
| `svg.renderer`, `svg.shaders` | `Svg3` plus core `Scene3`/`Renderer3d` | Mapped |
| `viz.core` | `Viz`, `Contour2` | Mapped |
| `gl.*` | Core camera/easy-camera, mesh, material, shader, framebuffer/post-processing, shadow, texture, compute, and transform-feedback APIs | Mapped where architectural equivalents exist; browser/Jogl host adapters are outside the SDL backend scope |
