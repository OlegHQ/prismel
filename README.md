# Prismel

> ⚠️ **WORK IN PROGRESS** ⚠️
> This project is currently under active development. APIs may change, documentation may be incomplete, and some features are not yet implemented. Contributions and feedback are welcome!

A modern, functional graphics framework for OCaml, inspired by creative coding libraries like openFrameworks and p5.js. Prismel provides a clean, type-safe API for creating interactive graphics applications, games, and generative art.

## 🎯 Project Overview

Prismel aims to make graphics programming in OCaml accessible and enjoyable by providing:

- **High-level API**: Easy-to-use functions for drawing shapes, handling input, and managing application lifecycle
- **Functional Design**: Immutable data structures and pure functions where possible
- **Modular Architecture**: Clean separation of concerns across different subsystems
- **SDL2 Backend**: Built on top of proven SDL2 libraries via Tsdl bindings
- **Headless Backend**: Software rendering without a monitor, GPU, or OpenGL
- **Retina-Ready Coordinates**: Logical drawing and input with native-pixel output
- **PXUI Toolkit**: A reactive, neon-accented widget library inspired by ofxUI
- **Functional Sketches**: Immutable model updates and composable scenes
- **Multicore OCaml**: Reusable Domainslib workers for CPU-heavy sketch updates
- **Creative Focus**: Optimized for rapid prototyping and creative applications

## 🚧 Current Status

**What's Working:**
- ✅ Basic application lifecycle management
- ✅ Window creation and management
- ✅ 2D graphics primitives (circles, rectangles, lines, etc.)
- ✅ Color system with RGBA support
- ✅ Matrix transformations (push/pop matrix, translate, rotate)
- ✅ Input handling foundation
- ✅ Time utilities and frame timing
- ✅ Mathematical utilities (Vec2, Mat3, basic math functions)
- ✅ Functional `Frame`/`Scene`/`Sketch` lifecycle
- ✅ Deterministic random, coherent noise, and palette tools
- ✅ Multicore collection updates through Domainslib
- ✅ Full-geometry transforms, multi-contour paths, masks, and scoped blending
- ✅ Offscreen canvases, pixels, deterministic PNG sequences, and headless CI
- ✅ Cached images/fonts/audio with automatic ownership
- ✅ Watched images and parallel file preparation
- ✅ Cached wrapped/aligned text and UTF-8/IME input
- ✅ Density-aware system UI text and high-DPI mouse/render alignment
- ✅ Sample/music playback and built-in waveform synthesis
- ✅ Headless-safe software 3D with cameras, depth/stencil targets, lights, and programmable shaders
- ✅ Functional geometry toolkit with subdivision curves, Delaunay/Voronoi,
  spatial trees, physics, voxels, mesh repair/CSG, four subdivision families,
  SVG export, and visualization layouts
- ✅ Packed PDK geometry with CSR topology, typed attributes, bitset groups
  with an optional immutable order plane,
  deterministic multicore kernels, native unshared-edge selection, bounded
  surface-boundary components, and fidelity-preserving mesh conversion
- ✅ Immutable procedural SOP graphs with precise context dependencies,
  bounded incremental cooks, diagnostics, inspection, and render-mesh caching
- ✅ Functional PXUI controls, themes, and settings persistence
- ✅ Persistent `dune utop` scene preview

**In Development:**
- 🔄 Cross-platform backend hardening
- 🔄 Additional specialized input devices
- 🔄 Optional GPU offscreen acceleration

**Planned:**
- 📋 More tutorials and specialized examples
- 📋 Additional profiling-driven optimizations
- 📋 Package distribution via OPAM

## 📁 Project Structure

```
├── lib/
│   ├── prismel/           # Main graphics framework
│   ├── runtime/           # Native/headless/web target lifecycle
│   ├── wap/               # Standalone browser transport and WebGL client
│   ├── geom/              # Functional geometry toolkit; depends on prismel
│   ├── pdk/               # Packed parallel compute geometry; depends on prismel
│   ├── procedural/        # Immutable SOP graphs; depends on pdk
│   └── pxui/              # UI toolkit; depends on prismel
├── examples/
│   ├── basic/             # Minimal Prismel application
│   ├── audio/             # Synthesized keyboard and sample playback
│   ├── canvas/            # Paths, clipping, pixels and PNG capture
│   ├── drawing/           # Mouse/touch freehand drawing with brush controls
│   ├── geom_curves/       # Subdivision and procedural curve poster
│   ├── geom_voronoi/      # Delaunay/Voronoi illustration
│   ├── geom_meshes/       # Extrusion, lathe, sweep, subdivision
│   ├── geom_isosurface/   # Gyroid and metaball isosurfaces
│   ├── geom_csg/          # BSP mesh union, intersection, difference
│   ├── geom_subdivision/  # Loop, Butterfly, Catmull-Clark, Doo-Sabin
│   ├── geom_physics/      # Immutable Verlet spring cloth
│   ├── generative/        # Generative art demo
│   ├── procedural_terrain/# SOP terrain, caching, and packed mesh bridge
│   ├── procedural_modeling/# Sweep, extrusion, attributes, and copy to points
│   ├── remesh/            # Isotropic packed remeshing and diagnostics
│   ├── convex_hull/       # Exact-predicate packed convex hull
│   ├── extract_centroid/  # Detail, primitive, and piece centers
│   ├── extract_point_curve/# Scalar-value points extracted from polygon curves
│   ├── circle_from_edges/ # Best-fit circles from boundary/selected edge loops
│   ├── graph_color/       # Conflict-free point/primitive work schedules
│   ├── triangulate_2d/    # Exact-predicate point-cloud Delaunay triangles
│   ├── boolean/           # Exact solid/surface polygon Boolean products
│   ├── boolean_detect/    # Surface-intersection groups and collision lists
│   ├── intersection_analysis/ # Editable intersection points and provenance
│   ├── three_d/           # Depth-tested software 3D demo
│   ├── web/               # Browser target and bridged input demo
│   ├── noise/             # Seeded noise and palette example
│   ├── particles/         # Multicore functional particle sketch
│   └── pxui/              # UI widget demo
├── test/                  # Unit tests
├── specification/         # Detailed module specifications
└── tsdl_gfx/              # SDL2_gfx bindings
```

## 🚀 Quick Start

### Prerequisites

- OCaml 5.2+
- Dune 3.17+
- opam and direnv
- SDL2, SDL2_image, SDL2_ttf, SDL2_mixer, and SDL2_gfx development libraries

On macOS with Homebrew:

```bash
brew install opam direnv sdl2 sdl2_image sdl2_ttf sdl2_mixer sdl2_gfx
```

On Debian or Ubuntu:

```bash
sudo apt install opam direnv libsdl2-dev libsdl2-image-dev \
  libsdl2-ttf-dev libsdl2-mixer-dev libsdl2-gfx-dev pkg-config
```

### Installation

```bash
# Clone the repository
git clone https://github.com/nexo-tech/prismel.git
cd prismel

# Initialize opam once per computer, then create this repository's local switch
opam init
opam switch create . 5.3.0 --no-install

# Register the checkout-local native SDL3 dependency probes
opam pin add --no-action --yes --recursive ./packaging

# Let .envrc activate the local switch and load the headless Linux defaults
direnv allow

# Install OCaml dependencies and build everything
opam install . --deps-only --with-test --with-doc
dune build @all

# Run all automated tests
dune runtest

# Run the examples
dune exec examples/basic/main.exe
dune exec examples/audio/main.exe
dune exec examples/canvas/main.exe
dune exec examples/drawing/main.exe
dune exec examples/geom_curves/main.exe
dune exec examples/geom_voronoi/main.exe
dune exec examples/geom_meshes/main.exe
dune exec examples/geom_isosurface/main.exe
dune exec examples/geom_csg/main.exe
dune exec examples/geom_subdivision/main.exe
dune exec examples/geom_physics/main.exe
dune exec examples/generative/main.exe
dune exec examples/procedural_terrain/main.exe
dune exec examples/three_d/main.exe
dune exec examples/web/main.exe
dune exec examples/noise/main.exe
dune exec examples/particles/main.exe
dune exec examples/pxui/main.exe
```

If you do not use direnv, activate the switch manually in each new shell:

```bash
eval "$(opam env --switch=. --set-switch)"
set -a; . ./.env; set +a
```

### Rendering targets

Select the runtime with `PRISMEL_RENDER_TARGET=native`, `headless`, or `web`.
The `PRISMAL_RENDER_TARGET` spelling is also accepted for deployment
compatibility. Legacy `HEADLESS=1` remains supported.

The checked-in `.env` selects headless mode by default. Headless uses SDL's
dummy video/audio drivers and software renderer, exercising real drawing and
audio paths without a display server, monitor, GPU, or OpenGL:

```bash
PRISMEL_RENDER_TARGET=headless dune exec examples/basic/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/three_d/main.exe
```

The bundled examples exit automatically after a few frames when headless, which
makes them useful as CI smoke tests. Applications control their own lifetime;
Prismel does not otherwise impose a headless frame limit.

Web mode starts a server on `0.0.0.0:8080` and prints its URL. Open that URL
from a browser on the same machine or network:

```bash
PRISMEL_RENDER_TARGET=web dune exec examples/basic/main.exe
PRISMEL_RENDER_TARGET=web dune exec examples/web/main.exe
# Custom port, presentation ceiling, payload budget, and backing-pixel cap:
PRISMEL_RENDER_TARGET=web PRISMEL_WEB_PORT=9000 \
  PRISMEL_WEB_MAX_FPS=30 PRISMEL_WEB_MAX_MBIT=2 \
  PRISMEL_WEB_MAX_PIXELS=921600 \
  dune exec examples/three_d/main.exe
```

The browser viewport is authoritative in web mode: the canvas and
`Frame.width`/`height` adopt the full available browser window even when the
desktop sketch configuration explicitly has `resizable = false`. The initial configured
size is used only until the first browser connects. Large viewports keep their
full logical coordinate space while the server backing framebuffer is fitted
within `PRISMEL_WEB_MAX_PIXELS` (1280×720 at the default 921600-pixel budget).

The existing SDL renderer remains authoritative, so paths, images, native
fonts, Canvas, software 3D/shaders, and PXUI appear through the same rendering
implementation. Wap suppresses duplicate frames, losslessly compresses full
frames and dirty rectangles, and keeps only one acknowledged frame in flight
per browser. The client updates a persistent, linearly filtered WebGL texture
(with Canvas 2D fallback).
Pointer capture, mouse, wheel, keyboard, UTF-8/IME text, focus, resizing, file
drops, samples, and music are bridged back to the ordinary Prismel APIs. See
the [runtime/backend contract](./specification/backend.md) for protocol,
security, performance, and resource limits.

On mobile, the on-screen keyboard opens only when a declared text-input region
is tapped. The browser positions a transparent real editor over that region,
keeps the full canvas dimensions stable while the keyboard is visible, and
retains composition/autocorrect context across input events. PXUI text fields
provide these regions automatically; ordinary canvas, button, slider, range,
and XY-control taps keep the keyboard closed.
Custom canvas text controls can use `Scene.text_input_region` alongside their
visual scene nodes.

### PXUI

`pxui` is a separate library that depends on `prismel`. Its normal path is a
declarative value stored in the sketch model:

```ocaml
let ui =
  Pxui.create ~max_height:520 ()
  |> Pxui.label ~text:"Controls"
  |> Pxui.toggle ~name:"animate" ~label:"Animate" ~value:true
  |> Pxui.slider ~name:"radius" ~label:"Radius"
       ~min:10. ~max:120. ~value:48.
  |> Pxui.int_slider ~name:"segments" ~label:"Segments"
       ~min:3 ~max:128 ~value:24
  |> Pxui.text_field ~name:"title" ~label:"Title" ~value:"Orbit"

let update model frame =
  let ui, changes = Pxui.update_frame model.ui frame in
  { model with ui }

let view model _frame =
  Scene.[clear Color.black; group (Pxui.scene model.ui)]
```

`Pxui.update_frame` does not mutate its input and returns ordered named changes.
Double-click a float or integer slider label to type an exact value; Enter
commits it and Escape cancels it. Slider bounds are a soft drag range, so typed
values may extend beyond them without being clamped.
Text fields consume SDL text-input and IME-composition events. `Pxui.encode` /
`decode` provide pure, typed settings round trips; `save` / `load` persist the
same versioned format. Choice, dual-handle range, and 2D controls use the same
builder/update/query pattern.

Use `Pxui.int_slider` for counts, seeds, segments, and other discrete values;
it emits and persists integers without sketch-side rounding. `~max_height`
clips a long inspector and enables vertical wheel/trackpad scrolling with a
visible scrollbar.

The default theme uses a dark glass-like panel, cyan-green accent, subtle glow,
rounded controls, and distinct hover/pressed states. Pass `~theme`, `~font`,
`~font_size`, row height, or padding to `Pxui.create` to customize the panel.
Without `~font`, PXUI uses Prismel's installed system UI font at the requested
logical size.

Pointer controls capture a left-button drag after it starts. Sliders, range
handles, and XY pads update continuously on every `MouseMoved`, even after the
pointer leaves the control, clamp to their configured bounds, and emit ordered
`Slid`, `Ranged`, or `Moved2` changes. Buttons, toggles, and choices are armed
on press and commit only when released inside the same control. Losing window
focus cancels pointer capture, text focus, and IME composition so stale input
cannot activate a widget. The older `add_*`, `handle_event`, and `draw`
functions remain available for low-level compatibility. See the
[PXUI interaction specification](./specification/pxui.md) for the complete
pointer and visual contract.

SOP sketches generate each selected node's inspector from typed parameter
metadata instead of duplicating fields as custom widgets. Add `(preprocess
(pps prismel.ppx))`, derive a schema beside the SOP definition, and attach it
to that node:

```ocaml
type controls = {
  planes : int
    [@sop.default 24] [@sop.folder "Geometry"]
    [@sop.min 1] [@sop.max 50] [@sop.hard_min 1];
  noise : float
    [@sop.default 0.3] [@sop.folder "Noise"]
    [@sop.min 0.] [@sop.max 1.];
}
[@@deriving sop_params]

let cutters =
  Custom.node ~label:"cutters" ~operation:"cutter-points"
    ~schema:controls_schema ~values:controls_default []
    (fun ~label ~inputs:_ ~parameters ->
      Sop.point_generate_origin ~label ~points:parameters.planes ())
```

The generated `controls_default`/`controls_schema` retain defaults, labels,
folder paths, soft slider ranges, optional strict bounds, and cook/view/export
impact. `Sop_ui.Node_inspector` maps ordinary PXUI changes through
`Graph.apply_parameters`; stable IDs preserve graph selection and unaffected
caches. `Pxui_graph` presents an immutable `Edit_graph` document and emits
typed add/delete/connect/disconnect/insert commands, while
`Sketch_ui.Environment3.run` and `Environment2.run` share a resizable
45/35/20 view/graph/inspector workspace, camera/render controls, `P/S/R`
playback, `G/I/C/H` UI shortcuts, bounded background cooking, and status/export
UI. See the roughly 70-line
`sketches/shattered_cube/main.ml` for the full graph-first path.
Slider min/max metadata defines the normal drag range, not a validity limit:
typed values may exceed it. Add `[@sop.hard_min]` or `[@sop.hard_max]` only
where the operation has an actual strict bound. Persist parameter state at the
graph/node layer; the inspector is a view of the selected node, not a second
parameter authority.

### Basic Usage

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

`Scene.t` is ordinary immutable data. Build scenes with lists and functions,
while `Sketch` handles the window, timing, events, rendering, and cleanup.

### 3D rendering

`Scene.view3d` embeds an immutable depth-tested scene. The same CPU rasterizer
runs with a visible window and under `HEADLESS`:

```ocaml
let camera =
  Camera.perspective
    ~at:(Vec3.create 0. 1. 6.) ~target:Vec3.zero ()

let view _frame =
  let lights =
    [Light.directional ~direction:(Vec3.create 1. (-1.) (-1.)) ()]
  in
  let world =
    Scene3.create ~lights [
      Scene3.box
        ~material:(Material.matte Color.cyan)
        ~width:2. ~height:2. ~depth:2. ();
    ]
  in
  Scene.[clear Color.black; view3d ~camera world]
```

Meshes support indexed points, lines, triangles, strips, and fans. Built-in
geometry includes planes, boxes, UV spheres, icospheres, cylinders, and cones.
`Shader3` adds typed CPU vertex/geometry/fragment stages and immutable
uniforms, with perspective-correct varyings, discard, and depth output on the
identical visible/headless rendering path. `Transform_feedback3` captures
staged geometry and `Compute3` provides deterministic functional workgroup
dispatch. Scoped raster state includes line/point sizing and standard blend
modes; immutable textures support generated mipmaps and automatic trilinear
minification.
`Framebuffer3` provides readable offscreen color/depth/stencil attachments;
its color texture can feed another shader pass for deterministic
post-processing.
Captured depth can also become a light-bound `Shadow3` map with hard or PCF
filtering, constant/normal bias, and per-fragment receiver sampling.
See the [3D contract](./specification/3d.md), the audited
[openFrameworks parity matrix](./specification/3d-parity.md), and the complete
[`examples/three_d`](./examples/three_d) sketch.

### Functional geometry

The wrapped `prismel.geom` sibling library keeps geometry construction pure and
turns values into Prismel scenes only through explicit adapters:

```ocaml
open Prismel
open Geom

let control =
  Polygon2.star ~center:(Vec2.create 320. 200.)
    ~inner_radius:70. ~outer_radius:150. ~points:8 ()
  |> Polygon2.vertices
  |> Curve2.create_exn ~closed:true

let smooth = Curve2.chaikin ~iterations:3 control

let view _frame =
  Scene.[
    clear (Color.hex_exn "#050816");
    Render2.curve ~width:3 ~color:Color.cyan smooth;
  ]
```

`Affine2`, 2D/3D bounds, rays, planes, spheres, segments, triangles, circles,
and polygons provide immutable queries, transformations, and typed
intersections. `Curve2` adds uniform arc-length sampling,
Chaikin/cubic subdivision, Bezier and Catmull–Rom curves, spirals, rose curves,
and the superformula. `Delaunay2` produces triangulations and bounded Voronoi
cells. `Mesh3` turns 2D profiles into native `Mesh.t` values by extrusion,
lathing, and parallel-transport sweeps, and applies Loop, Butterfly,
Catmull-Clark, or Doo-Sabin subdivision. `Mesh_io`, `Mesh_repair`, and `Csg3`
provide STL/OFF exchange, topology repair, and BSP booleans.
`Iso3` extracts smooth or faceted meshes from scalar fields and includes
signed spheres, inverse-square metaballs, and gyroid fields.
Persistent quadtrees/octrees and sparse voxels cover spatial workloads;
immutable `Verlet2`/`Verlet3` worlds cover spring physics. `Svg_path`, `Svg`,
and `Viz` provide standards-complete SVG path parsing, safe vector export,
scales, and common chart layouts.

Run the complete
[`geom_curves`](./examples/geom_curves),
[`geom_voronoi`](./examples/geom_voronoi), and
[`geom_meshes`](./examples/geom_meshes), and
[`geom_isosurface`](./examples/geom_isosurface),
[`geom_csg`](./examples/geom_csg),
[`geom_subdivision`](./examples/geom_subdivision), and
[`geom_physics`](./examples/geom_physics) examples. Set
`PRISMEL_EXPORT_DIR=frames` to export one deterministic PNG from any of them.
The [geometry specification](./specification/geom.md) documents the API,
algorithm contracts, and the capability map used for the thi.ng/geom study.

### Packed and procedural geometry

`prismel.pdk` is the compute-grade geometry layer: positions and numeric
attributes use packed structure-of-arrays storage, polygon/curve topology keeps
the point–vertex distinction, point/vertex/primitive groups are compact
bitsets, native edge groups are topology-affine, and stable disjoint ranges run
through Prismel's reusable Domainslib pool. Conversion to
`Prismel.Mesh.t` preserves point and vertex `N`, `Cd`, and `uv`; arbitrary
simple polygons are triangulated only at that terminal rendering boundary.

`prismel.procedural` builds immutable SOP graphs over the same PDK geometry:

```ocaml
open Prismel
open Procedural

let terrain =
  Sop.grid ~connectivity:Pdk.Ops.Grid_alternating_triangles
    ~uv_attribute:"uv" ~columns:180 ~rows:180 ~size:12. ()
  |> Sop.noise_displace ~seed:42 ~amplitude:1.25 ~frequency:0.22
  |> Sop.color_by_height
       ~low:(Color.hex_exn "#172554") ~high:(Color.hex_exn "#fbbf24")

let session =
  Session.create ~max_entries:64 ~max_payload_bytes:(128 * 1024 * 1024)
  |> Result.get_ok

let mesh frame =
  let context = Context.of_frame ~seed:42L frame |> Result.get_ok in
  Bridge.cook_to_mesh session ~context terrain
```

Static nodes ignore unrelated frame changes, random nodes declare their seed
dependency, and a session bounds both cooked geometry and converted render
meshes. `Graph.format` and `Graph.to_dot` expose graph structure; structured
errors retain the complete root-to-failure node path. Use
`Sop.native_point_ranges` to descend to allocation-tight packed OCaml loops
without changing geometry formats.

Interactive inspectors should use `Async_cook` instead of calling
`Session.cook` inside `Sketch.update`. Its persistent worker owns the session,
keeps only the latest pending request, cancels superseded contexts, and exposes
non-blocking `poll`/`status` functions. Keep the previous successful mesh on
screen with a visible cooking-time status; adopt immutable results and perform
all SDL/GPU work on the initial domain. Close the worker from `~on_stop`.

Generator nodes use the same production packed kernels directly. For example,
`Sop.circle` supports closed circles, open or chord-closed arcs, center-sliced
arcs, ellipses, arbitrary robust plane axes, center/rotation/scale, and reverse
traversal without introducing a separate procedural geometry representation.
`Sop.box` emits divided triangle or quad surfaces, welded or face-local surface
points, or a complete volume lattice, with explicit point/vertex normals,
six-order Euler transforms, per-face UVs, and stable face groups from the same
allocation-tight PDK kernel. `Sop.poly_path` cleans arbitrary polygon/curve edge networks into
maximal paths, removes duplicate/self edges, optionally welds nearby endpoints,
and can turn isolated loops into closed polygon surfaces without an
edge-per-primitive intermediate.
`Sop.uv_sphere` covers regular or alternating triangles, quads, open row/
column curves, and point lattices; ellipsoid radii, shared or unique poles,
arbitrary pole axes, full Euler transforms, point/vertex normals, and seam-safe
UVs remain one immutable cache-aware generator rather than modifier chains.
`Sop.torus` adds full or partial toroidal patches with triangle, alternating-
triangle, quad, row/column-curve, or point output; U/V ranges and wrapping,
polygon caps, arbitrary hole axes, transforms, smooth or hard-cap normals, and
seam-safe UVs all cook through one exact-sized PDK kernel.
`Sop.tube` generates cylinders, frusta, cones, and pyramids as triangle,
alternating-triangle, quad, row/column-curve, or point output. A zero end radius
uses one shared apex and triangle tip cells instead of degenerate polygons;
optional consolidated or independent caps, analytic side normals, hard vertex
cap normals, UVs, cap groups, arbitrary axes, and complete Euler transforms all
remain in the same cardinality-first packed kernel.
`Sop.platonic` adds the five regular convex polyhedra and the soccer-ball
truncated icosahedron with their natural face arities, smooth or hard normals,
face groups, black/white primitive color, arbitrary up axes, and full Euler
transforms. `Geom.Polyhedra3` now adapts this same PDK source instead of owning
duplicate vertex and face tables.
`Sop.spiral` generates Archimedean or logarithmic polygon spirals and helices
from turns or height/pitch, height/radius ramps, equal-angle or integrated
equal-arc divisions, and phase-distributed copies. Arbitrary axes, complete
Euler transforms, and optional angle, orthonormal frame, quaternion `orient`,
and cumulative-distance attributes make the result directly composable with
Sweep and PolyWire while retaining one packed PDK representation.
`Sop.transform_trs` provides six explicit transform and Euler-radian orders,
non-uniform/uniform scale, shear, translated/rotated pivots, and inversion.
It can transform points referenced by typed point, vertex, primitive, or
native-edge groups while applying inverse-transpose, preserved-length, or
recomputed normal policy through the same packed PDK kernel. `Sop.transform`
remains the direct matrix form.
`Sop.soft_transform_trs` adds controlled modeling falloff around typed source
groups. It supports parallel straight-radius distance, exact shortest
geometric edge paths, or authored point-float weights; linear, quadratic, and
cubic profiles; optional inspectable weight output; and automatic normal
repair without placing mutable deformation state in the procedural graph.
`Sop.distance_along_geometry` exposes that exact edge-path field as a reusable
analysis node. Typed start and affected groups, raw unreachable-aware distance,
fixed or maximum-distance masks, and a bounded mask-only traversal make it
suitable for interactive growth, propagation, and iterative sketch controls
without duplicating the topology kernel inside a custom node.
`Sop.distance_from_geometry` measures affected points against typed reference
point sets or selected polygon surfaces. It shares the packed point k-d tree
and polygon BVH with the rest of PDK, emits raw distance and fixed/maximum
falloff masks, and uses distance-only batch traversal so field generation does
not allocate unused nearest-feature provenance.
`Sop.distance_from_target` provides the allocation-light analytic counterpart:
spherical distance from a point, cylindrical distance from an infinite axis,
or absolute/signed planar distance. Origin and direction are immutable node
parameters; fixed or maximum-radius masks reuse the same falloff contract, and
typed affected groups preserve values outside the procedural edit.
`Sop.sort` supports stable point and primitive ordering, deterministic seeded
random permutations, strict reorder-by-index fields, and indirect destination-
rank output. Indirect ranks can be combined across successive stable keys, so
multi-key ordering stays inspectable without repeatedly rebuilding topology.
Point topology order, lowest incident primitive, and point/primitive Morton
spatial-locality keys cover the remaining packed modeling workflows.
`Sop.revolve` turns one or more polygon profiles around any finite axis as a
full revolution or an exact-ended open arc. It emits points, angular/profile
curves, quads, or regular/reverse/alternating triangles; compacts exact axis
contacts into real poles, preserves packed payload and native profile-edge
groups, produces normalized seam-safe UVs, and optionally caps open profile
ends without generating coincident pole rings.
`Sop.poly_loft` stitches an authored sequence of unequal polygon curves or
faces into triangles without duplicating their points. It supports closest or
rest-guided seam/orientation pairing, two distance objectives, U/V wrapping,
source retention, generated-face grouping, exact packed payload ancestry, and
deterministic pair-parallel construction.
`Sop.skin` uses that same alignment, ancestry, and parallel packed core for a
linear polygon skin. Equal-cardinality section pairs retain ordered quads,
while unequal pairs use the PolyLoft zipper; no competing surface kernel or
duplicated point plane is introduced.
`Sop.poly_bridge` constructs one or many direct surfaces between named simple
edge paths or loops. Components pair by authored order or deterministic
centroid rank, reverse and closed-loop shift controls correct correspondence,
equal boundaries retain quads, and unequal boundaries reuse the same zipper.
Equal-cardinality bridges can add uniformly spaced straight division rows;
numeric point/vertex payload interpolates while discrete payload and groups use
the nearest boundary. Input topology, packed payload, ordinary groups, and
native boundary-edge ancestry remain in the shared PDK representation.
`Sop.poly_reduce` performs adaptive quadric-error simplification in
deterministic, topology-safe contraction batches. It accepts a ratio or output
polygon target, a primitive restriction, hard point and native-edge groups,
strict unshared-boundary preservation, original-point-only contraction,
triangle-quality weighting, an optional normal-deviation limit, and a
surviving-face group. Polygon inputs are triangulated through the existing PDK
kernel; manifold link tests and surviving-face flip checks run before every
batch, while the shared Fuse reducer remains the only owner of packed payload,
group, and native-edge ancestry.
`Sop.remesh` triangulates a polygon surface and iteratively applies the shared
PDK split, collapse, flip, relax, and projection kernels toward an isotropic
triangle field. Uniform or point-authored target sizes, hard points, native
hard edges, UV seams, input-points-only operation, point mesh-size output,
triangle quality, and output hard-edge groups are immutable node parameters.
Packed payload and group ancestry is preserved through fused midpoint
subdivision and a direct source-to-final collapse remap; deterministic one-
domain and multi-domain cooks produce identical ordered geometry.
`Sop.boolean_detect` retains its source surface while marking primitives that
touch a second polygon surface or self-intersect. The collision input is
optional: a one-input node defaults to AxA self-intersection output, while a
two-input node defaults to AxB output. Independent primitive groups can
restrict both inputs; outputs include primitive groups, packed integer-arrays
of sorted unique intersecting primitive numbers, and row counts. AxA lists are
symmetric and ordinary contacts through shared topology are suppressed while
duplicate or genuinely overlapping faces remain detected. Deterministic
triangulation feeds a packed two-pass BVH broad phase and a locally normalized
crossing/touching/coplanar narrow phase. This is the production Detect subset
and reusable first stage of future corefinement; it does not claim robust solid
union, intersection, or subtraction.
`Sop.boolean` evaluates union, intersection, both subtraction directions, or
XOR, and emits named A-only/overlap/B-only Shatter pieces through PDK's exact
build-once arrangement. Each input is explicitly an
oriented solid or a zero-volume surface; payload conflicts, seam-point
splitting, bounded tiny-seam cleanup, source-polygon detriangulation,
self-intersection resolution, and closed-output validation are typed node
policies.
`Sop.boolean_fracture` is the solid-by-surface specialization used by fracture
sketches. It keeps exact seam points shared and writes a dense primitive
`piece` attribute from the oriented Weiler cell behind each output face, so a
packed transform moves a complete closed shard instead of individual patches.
`Sop.boolean_seam` exposes the corresponding exact left-self, between-input,
right-self curve products or coincident triangle patches with optional named
primitive groups.
The generated and external-OBJ stability runner is available as
`dune exec tools/boolean_stress.exe -- --level quick --domains 4`; the licensed
Houdini differential protocol and the strict meaning of comparative claims are
documented in [`specification/boolean-stability.md`](specification/boolean-stability.md).
`Sop.intersection_analysis` uses a packed mixed-piece BVH and the same shared
triangle narrow-phase decisions but emits point-only geometry at triangle,
curve, and mixed intersections. One input performs AxA self-analysis and an
optional collision input performs AxB analysis. Each welded point can carry aligned ragged
`sourceinput`, `sourceprim`, `sourceprimuv`, and `sourcepoint` provenance; the
UVW row stores triangle barycentrics or a complete-curve `(u, 0, 0)` triplet
per incident primitive, and non-vertex events use `-1` for their incident
point. Polygon inputs remain deliberately triangle-only; polygon curves are
indexed directly without surface triangulation.
`Sop.poly_bevel` cuts eligible two-sided polygon edges back within their first
face ring, splits neighboring ring polygons so partial selections stay
watertight, builds connected edge strips and corner junctions, and preserves
packed payload ancestry. It supports chamfer and divided rational-circular
round profiles, convexity, point `pscale`-style distance scaling, flat-edge
exclusion, local overlap limiting, generated edge/corner face groups, and
native offset-edge groups. Omit `~group` to bevel all eligible edges.
`Sop.point_split` separates selected shared point incidences uniquely or at
vertex/primitive attribute or named-group seams. It accepts ordered
include/exclude globs, an explicit per-component tolerance, and optional seam-attribute
promotion to points while preserving stable point ancestry and every packed
attribute/group storage through the single PDK topology core.
`Sop.point_generate_origin` creates a no-input origin cloud, while
`Sop.point_generate` emits points from every or selected input point. Connected
mode supports a constant/scaled expected count or a per-point probability,
deterministic stochastic rounding, input retention, point/detail attribute
patterns, a generated group, and stable `sourcepoint`/`sourceindex` metadata.
Both entry points use the same cardinality-first PDK kernel; generated order is
stable across domain counts and retained polygon/curve topology is shared.
`Sop.point_replicate` turns that emission plan into shaped clouds around input
points. Point, box, volume-uniform sphere, area-uniform disk, line, and custom point
clouds pass through the same standard instancing transform rules as
Copy-to-Points. Stable `id` values preserve counts and placement through point
renumbering; quasi sampling, source payload/provenance, velocity stretch and
inheritance, radial velocity, and optional rest-space vector fBm are explicit
immutable parameters. An ordered attribute pattern can additionally transform
copied point float3 vectors; `N` follows inverse-transpose normal semantics.
Custom clouds emit `shapeptnum` ancestry.
`Sop.sweep` is the separate two-input general-profile operator: selected open
or closed polygon cross sections are placed along selected open or closed
backbones with point/row/column/quad or triangle connectivity. It supports all
five audited tangent policies, closed-continuous parallel transport,
distance-weighted roll/twist, `orient`/`N`/`up`/`pscale`/`scale`, single-polygon
end caps, normalized UVs, multiple curve pairs, and prefixed ancestry from the
profile input without introducing another geometry representation.

`Sop.custom` creates inspectable custom nodes from PDK operations or Geom/Pdk
adapter compositions. Callers declare a stable operation/version/parameter
identity and any frame/time/seed/domain dependencies, so custom creative nodes
participate in the same bounded cache and diagnostics as built-ins.

`Sop.reverse` reverses winding or cyclically shifts polygon/curve corners for
the whole input or a named primitive group. Vertex attributes and groups and
native edge groups follow the exact corner permutation; reversal invalidates
stale normals while a pure shift preserves them.

`Sop.triangulate` deterministically ear-clips all simple polygons or a named
primitive group. Unselected polygons and curves pass through unchanged, while
all vertex/primitive payload and source edge ancestry follows the generated
triangles through the same packed PDK kernel.

`Sop.normals` computes point, vertex, primitive, or detail normals with
face-area, equal-corner, or vertex-angle weighting. Typed component selections,
vertex cusp angles, zero preservation, reversal, and custom normal names all
remain deterministic packed PDK operations; cusped vertex normals use the
shared lightweight point-incidence cache rather than paying for unused edge
topology.

`Sop.measure_curvature` estimates signed mean and Gaussian curvature on a
consistently wound polygon manifold, with optional principal-curvature,
curvedness, and shape-index fields. The scale-normalized mixed-area/cotangent
kernel supports explicit boundary policy, synchronous smoothing, point-group
output restriction, and exact one-/multi-domain results without changing mesh
topology.

`Sop.attribute_laplacian` applies signed cotangent, non-negative cotangent, or
uniform topology weights to point scalar and fixed-width vector fields, with
canonical `P` available as a read-only source. It exposes pointwise or
integrated output under the smoothing-friendly neighbor-minus-center sign
convention and preserves existing values outside an optional point group.

For iterative creative coding, keep feedback in `Sketch.run_state`: wrap the
previous immutable geometry with `Sop.snapshot`, build/cook the next acyclic
step from ordinary SOPs or `Sop.custom`, then replace the model snapshot. A
byte- and entry-bounded `Session` keeps history from growing accidentally.
This supports solver-like growth, relaxation, erosion, and trail sketches
without adding a global solver or hidden mutable geometry state.

`Sop.rest_position` stores, extracts, or swaps a structurally shared reference
pose. `Sop.point_velocity` can derive deterministic `v` and central-difference
acceleration from explicit previous/next snapshots, optionally matching
changing point order by integer or text ID. Together they make solver-like
sketch steps inspectable and replayable while the application retains only the
current and next immutable geometry.

For render-only repetition, `Sop.pack` and `Sop.duplicate_packed` retain one
prototype graph and a compact transform array. `Bridge.cook_to_scene3` cooks
the prototype mesh once and creates the batched `Scene3` node with one array
copy. `Sop.unpack` is the explicit editing boundary: it materializes arbitrary
instance transforms in stable copy-major order through one exact-sized packed
kernel, after which ordinary SOPs can edit every copy. Keep instances packed
until that edit is actually needed; `Sop.duplicate` remains the concise path
for regular cumulative copies. Materialized Duplicate can restrict the copied
source primitives without trimming the retained original, copies only the
points referenced by that subset, and can emit bounded one-based primitive
groups for each appended copy with an explicit collision-preservation policy.

The modeling surface also includes typed constant attributes, selections and
groups, dense integer/text enumeration within typed groups, including local
element numbering per integer/text piece and stable first-occurrence piece IDs,
stable point/primitive sorting with complete payload remapping,
shared-plan wildcard Attribute Promote with aligned multi-term destination and
source-index renaming, fixed-width float2/3/4 component-source index rows,
SideFX-compatible text median/concatenation/fallback behavior, and packed
scalar integer/float Array of All and Unique Values promotion into CSR rows,
materialized cumulative/non-cumulative duplication, area analysis, and
point/primitive connectivity with include masks, native seams, UV islands, and
integer or prefixed-text classes,
production Clean with point consolidation, robust degeneracy/overlap and NaN
repair, winding/compaction, and attribute/group cleanup, typed delete, and
Blast by Attribute over scalar point/primitive fields with strict threshold,
inclusive range/width, restricted inversion, group output, and optional
primitive-orphan compaction,
typed all/named-edge Crease authoring with coherent add/set/delete sharpness
for Subdivide and optional endpoint visualization,
frame-dependent Attribute Fade over scalar point fields, with typed point
restriction, independent start/hold reference inputs, affine start retiming,
per-point hold scaling, shaped in/out ramps, and grayscale visualization,
ordered Attribute Composite across detail, primitive, point, and vertex
Float/Float2/Float3/Float4 fields, with independent patterns, finite global and
same-owner alpha weights, Mean/Max/Min/Over/Under operations, and opt-in `P`,
production PolyCut over polygon curves, with point/edge restrictions,
remove/cut strategies, scalar crossings, tuple-length change subdivision,
closed-fragment policy, and complete interpolated payload/group ancestry,
reversible Separate Pieces packing for integer/text point or primitive piece
identities, with arbitrary axes, explicit gaps, and stored rigid translations,
point-group-restricted Fuse and per-axis Grid Snap with deterministic rounding,
movement tolerance, packed moved-point output, and optional exact consolidation;
Fuse also accepts an immutable second target with an independent target group,
least-number or closest near-point policy, specified integer destinations,
per-point radius expansion, equal/unequal scalar match filters, snap-only
topology preservation, and snapped-point/destination outputs. Same-input
Modify Target supports deterministic component reduction; Fuse also provides
the full position-reducer family (including mode, median, RMS and weighted
policies), Keep Fused Points, and stable repeated-vertex, degenerate-primitive,
and selective/all-unused-point cleanup. Ordered Houdini-style attribute and
group patterns select numerical, string, scalar-to-array/array concatenation,
weighted, union/intersection, and strict-majority propagation; fixed targets
copy matching payload without modifying their geometry,
fixed-count surface scatter with primitive restriction, owner-typed linear
density, arbitrary attribute/group transfer, and exact reusable source
provenance, two-input closest/directional `ray` projection with source and
collision restriction, bounded deterministic multi-ray jitter,
average/median/shortest/longest combination, hit provenance, attribute/group
import, and exact parallel BVH traversal, dedicated topology-preserving `smooth` with primitive and locked-
point selection, unshared/group-boundary constraints, and shrink-resistant
alternating passes, planar/cylindrical/spherical vertex UV
projection with seam and pole correction, point/vertex UV transforms,
automatic angle/partition/existing-UV seam detection with stable islands,
per-face/per-island UV unit fitting, seam-aware harmonic UV flattening, and
boundary-preserving UV relaxation,
native topology-affine edge groups with incidence/length, face-dihedral, and
pairwise shared-point edge-angle selection,
typed point/vertex/primitive Group from Attribute Boundary detection with
native-edge, point, or primitive output and explicit unshared-curve policy,
bounded Groups from Name conversion from point/primitive text values with
stable first-seen naming, conflict policy, and exact packed-memory preflight,
and its Name from Groups inverse with deterministic overlap policy and optional
source-group removal,
deterministic packed Group Random selection for all four topology owners with
base, seed-attribute, and merge controls,
overflow-safe packed Group Bounds selection with full/partial box and sphere
containment for points, vertices, primitives, and native edges,
packed Group Normal selection for geometric or authored point, primitive, and
native-edge directions with opposite-cap support, plus stable tolerance-based
Group Non-Planar polygon selection and viewpoint-relative packed Group Backface
selection with subtractive composition, plus bounded point-seeded Group Edge
Depth growth,
four-owner Group Promote with touching/contained/shared-edge rules, optional
integer-mask output, ordered bounded wildcard/rewrite batches, and boundary
rules with typed attribute seams and polygon/curve unshared-edge policy, signed
topology-step Group Expand and connected-component flood fill with optional
step-distance output, adjacent-normal limits, typed attribute seams, and
collision containment/boundary policy for points and edge-connected
primitives, absolute/relative/partition Group Range with periodic
filters, stable per-disconnected-region evaluation, multi-attribute float-
tolerant region cuts, independently typed collision boundaries, boundary
retention, preserve/remove-other-region policy, and ordered multi-range batches
with disabled blank-name slots, four-owner Group
Combine/Invert boolean algebra, wildcard Group
Delete/Rename lifecycle rules, and two-input Group Copy with index,
primitive-local-corner, or integer/text attribute matching. Two-input Group
Transfer uses packed point and feature AABB indexes to map point, primitive,
and native-edge groups by exact proximity rather than centroids; ordinary
ordered groups retain source sequence with proximity-stable destination order,
and Group Find Path constructs ordered point-edge or manifold primitive-dual
topology paths through waypoint sequences or start/end pairs with same-owner
collision regions and optional closure,
directed packed `line` sources, `copy_to_points` with the standard
`orient`/`N`/`v`/`up`, `rot`, `pivot`, `trans`, and scale stack,
plus packed affine `transform` overrides,
typed source-primitive and target-point restriction,
integer/text source-point or source-primitive piece matching with stable
target-major variant output and primitive-number fallback,
last-match-wins point/vertex/primitive Attributes-from-Target rules with
`Nothing` overrides and target-group boolean algebra,
individual-face or connected
region `poly_extrude` with split edges, straight divisions, geometry switches,
and front/back/side and boundary groups, manifold-boundary `poly_fill` with
all-hole or partial-edge auto-completion, shared/unique Single Polygon,
concave-safe Triangles, or averaged Triangle Fan patches, winding, normal, and
patch-group controls, count- or length-driven arc-length
`resample` with primitive group/count/length overrides and optional
U/curve/distance/tangent fields, packed `polyframe` coordinate fields with
first-edge, two-edge, centroid, point-UV, and seam-preserving vertex-gradient
styles, typed selection, and optional right-/left-handed orthogonalization, and
unique-edge `convert_line` with optional fused maximal-path connection,
endpoint-distance/loop controls, final path length, and point compaction,
primitive-group relative-arc `carve` with per-primitive endpoint controls,
inside/outside pieces, equal-parameter divided cuts, vertex-breakpoint cutting,
and divided free-point extraction,
detail-ordered, ordered-group, explicit user-picked-end, or global closest-end
`join_curves` with deterministic endpoint orientation, fixed-size subgroups,
original retention, and welding,
polygon/curve `ends` with open, straight-close, shared-seam unroll, and
payload-duplicating new-seam unroll (`curve_ends` remains the curve-only
compatibility name),
packed arbitrary-axis `revolve` with full/open arcs, point/row/column/surface
connectivity, compact poles, caps, UVs, and complete ancestry,
two-input general-profile `sweep` with multiple selected curve pairs,
point/curve/surface connectivity, modern tangent and transform-attribute
frames, closed-continuous roll/twist, caps, UVs, and dual-source ancestry,
shared `sweep_circle`/`polywire` with primitive scoping, point-varying radial
divisions, endpoint-averaged longitudinal segmentation, deterministic
triangle/quad transition zippers, point-scaled radii, snapped seam and authored
V/joint-up controls, constant or per-edge segment placement, optional UV
generation, constant or per-edge U/V ranges, capped radial joint miters that
prevent sharp-bend collapse, point-authored smoothing and maximum-valence
disconnection into real uncapped runs, outgoing-corner per-edge snapped texture
seams, closed-frame correction, and hard-normal caps,
deterministic attribute-aware `fuse`, including packed two-input fixed-target
snapping with independent query/target groups, least/closest or specified
destinations, radius and scalar match controls, and optional post-snap
consolidation, and
ordered, typed component-selected `facet` preparation with normals, Unique Points, consolidation,
point/vertex-normal averaging, shape-preserving inline-point removal, manifold
orientation, dihedral-angle
hard-edge cusping, degenerate cleanup, and conflict-safe Make Planar, plus arbitrary-plane `mirror`
and `clip`. Clip can retain either/both sides, use canonical `P` or the first
three zero-extended components of a numeric point attribute, translate its
plane along the normalized normal, or derive the plane from a transform. Typed
point, vertex, primitive, and native-edge selections are promoted to incident
primitives; selected free points remain independently clip-able, and shared
selected/unselected boundaries are isolated without rewriting the unselected
corner order or payload ancestry. Clip can snap near-plane points, split
connectivity, fill manifold cuts watertightly, and materialize clipped native
edges plus cap/clipped/side primitive groups with replace-or-union behavior.
Disconnected concave half-plane intersections become independent fragments,
including through filled closed meshes. Directed nested cap contours preserve
holes, multiple cavities, and alternating-depth solid islands through
deterministic visibility bridging and triangulation; same-winding nested solids
remain independent. Polygon-only unfilled cooks use an exact parallel
count/prefix/fill plan; curves, caps, and the uncommon concave multi-fragment
reconstruction retain the general packed builder. `subdivide` provides packed
Catmull-Clark, Loop, and bilinear refinement with face-varying seams,
semi-sharp creases/corners with selectable Uniform or endpoint-dependent
Chaikin decay, point-number-matched second-input creases,
an allocation-tight no-input override for every subdivided edge,
stencil-contributing `subdivision_hole` faces, typed OpenSubdiv None, Edge Only,
and Edge and Corner point-boundary interpolation, plus all six OpenSubdiv
face-varying modes (None, Corners Only, Corners Plus 1, Corners Plus 2,
Boundaries, and Linear All), standard or OpenSubdiv Smooth Triangles
Catmull-Clark edge masks, and Houdini-compatible detail-attribute overrides
for scheme, point/face-varying interpolation, creasing, and triangle policy.
Open and closed polygon curves use the same node: Catmull-Clark applies the
cubic 1/8-3/4-1/8 curve rule across shared degree-two topology, bilinear keeps
old points fixed, and `~treat_curves_as_independent:true` gives every curve
corner its own point as Houdini's viewport/Mantra compatibility option does.
Mixed surface/curve inputs, local curve groups, recursive refinement, all
ordinary payload owners, native edge groups, and free points retain exact
deterministic ancestry. Existing point `N` follows the same stencil as `P` by
default; `~recompute_point_normals:true` instead replaces it after the final
cook with normalized area-weighted point normals and does not invent normals
for inputs without point `N`.
`edge_divide` inserts an exact number of equal-parametric segments on selected
native edges. Shared mode reuses one inserted point chain across every
coincident polygon or curve incidence; unique mode gives each incidence a
private chain. Both modes preserve packed point, vertex, primitive, detail,
ordinary-group, ordered-group, and native-edge ancestry.
`edge_collapse` contracts every connected selected-edge component to the
arithmetic center of its unique points by default; its typed Fuse position
policy can instead retain a stable endpoint or use another documented
component reducer. Optional exact point-attribute
boundaries partition components; the shared Fuse reduction/cleanup kernel
preserves packed payload and group ancestry, removes degenerates, invalidates
stale normals, and optionally rebuilds an existing point-normal field.
`poly_reduce` builds on that same contraction/remap boundary rather than
maintaining a second mesh payload kernel. Per-round face quadrics and edge
costs use packed reusable scratch, pure scoring runs in stable parallel ranges,
and deterministic cost ordering selects a one-ring-independent batch. Hard
features, non-manifold neighborhoods, selected/unselected interfaces, and
optionally all open boundaries are locked. Link-condition and scale-normalized
normal checks reject topology changes and foldovers before committing a new
immutable snapshot. Constraints may legitimately stop above the requested
count.
`edge_flip` rotates selected manifold polygon diagonals through the joined
boundary without changing point, vertex, or primitive cardinality. Cycles are
deterministic for mixed polygon sizes; vertex payload may follow each cycle,
and native edge groups transfer membership from the old diagonal to the new
one. Simultaneous flips must be primitive-disjoint, so order-dependent edits
remain explicit as successive immutable nodes.
`edge_cusp` splits polygon point fans only at interior vertices of selected
edge paths: a single selected edge is a no-op, while two connected edges split
their shared point. Point payload/groups duplicate through one shared Facet
fan kernel, native edges retain exact ancestry, and existing point normals are
optionally rebuilt.
`edge_straighten` fits a least-squares line independently to every connected
selected-edge component and projects its points orthogonally. It supports open
paths, cycles, and branches without inventing an edge order, preserves exact
collinear and one-edge identities, and can record the processed native edges.
`circle_from_edges` converts each simple selected-edge path or loop into a
least-squares best-fit circle. With no explicit group it uses topology boundary
edges; an optional positive radius overrides the fitted radius, component-wise
scale is applied about each fitted center, and a native output edge group can
record the transformed selection. Packed topology and unrelated payload remain
shared while stale point/vertex normals are removed.
`graph_color` assigns deterministic integer schedules to selected points or
primitives. Primitive graphs may connect through shared points or shared closed
polygon edges; point graphs treat every primitive's points as a clique. Optional
stable sorting places equal-color worksets contiguously and emits detail begin/
length arrays, while unselected elements retain `-1`.
`triangulate_2d` connects a point cloud with the shared packed Delaunay kernel.
It supports best-fit, principal, explicit-plane, and point-attribute projection,
then emits triangles referencing the original 3D points by default. Disabling
original-position restoration places participating points and every generated
point on the selected world projection plane; point float2/float3 coordinates
instead map to `(x, y, 0)` and ignore components beyond the first two. Exact
predicates own topology decisions across ordinary, subnormal, and maximum
finite coordinates;
native edge and primitive groups use a packed-BVH exact arrangement, opt-in
line-line crossing construction, exact inserted-point splitting, authored
point-on-constraint atomization, and the shared strip-cavity recovery kernel.
Generated positions and point payload follow a
documented deterministic constraint-source policy. Exact constraint-blocked
convex-hull flooding, exact non-zero closed-constraint winding removal, and
orientation-independent projected silhouettes are available. Quality
refinement adds stable batches of exact-predicate Steiner points under minimum
angle, maximum area, target edge length, minimum edge length, constraint-
splitting, and maximum-new-point policies. Deterministic regularization relaxes
generated interior points through exact-predicate-certified simultaneous moves;
an explicit policy may also move original projected interior points while
constraint and hull points remain fixed. A compact provenance DAG preserves
recursive 3D and point-payload interpolation across repeated relaxation.
Constraint-only seed mode can
exclude non-constraint points from topology while preserving their source
payload as isolated points; optional stable compaction removes them afterward,
exact projected-duplicate removal preserves unrelated unused points, and
existing point normals can be recomputed through the shared Normals kernel.
`keep_primitives:true` retains every source polygon or curve except explicitly
selected constraint primitives before the generated triangle suffix. Retained
vertex/primitive attributes, ordinary and ordered groups, and native edge
groups keep exact source ancestry; triangle entries receive typed zero/empty
defaults and the requested triangle group selects only that suffix.
`edge_equalize` moves selected endpoints to the initial average, longest, or
shortest selected length. Independent edges take a direct parallel path;
connected selections use a bounded deterministic projection with an explicit
relative tolerance and preserve their centroid. Zero-length direction,
non-finite input, and non-convergence are reported rather than partially
committing a snapshot.
`edge_relax` takes an immutable matching-topology reference and relaxes source
edges toward its individual length field or its scale-independent length
distribution. Point/primitive restriction, pinned points, shorten-only policy,
step size, iteration ceiling, and residual tolerance are typed parameters.
Disjoint constraints use a closed-form parallel path; connected constraints
share the bounded edge-projection core used by Edge Equalize.
`blend_shapes` morphs the first immutable snapshot toward any number of target
point shapes. Residual-normalized weights or additive target-minus-source
differencing, finite first-input/target masks, integer/text point-ID matching,
point restrictions, and Float/Float2/Float3/Float4 point-attribute patterns are
typed policies. Target-major packed passes preserve stable accumulation order
while filling disjoint point ranges through the reusable pool.
`attribute_composite` retains the first input topology while folding any number
of ordered immutable inputs over independent detail/primitive/point/vertex
patterns. Mean, component-wise Max/Min, and standard Over/Under use finite
global weights plus optional same-owner scalar alpha; missing alpha is one and
missing selected fields are numeric zero. `P` is eligible only when explicitly
enabled. Output planes allocate once, accumulation order is stable, and
parallel ranges remain byte-identical to one-domain cooking.
`edge_transport` propagates scalar point fields over a deterministic
shortest-path edge forest with first, last, or explicit multi-source roots.
Transport/from-root, ancestor total, path minimum/maximum, branch copy/split,
constant edge count/distance integration, and component/global normalization
are typed policies. Forward traversal copies or splits branches; backward
traversal starts at leaves and merges branches by addition, maximum, or
minimum. `edge_transport_curves` is the linear fast path for independent
polygon curves, adds point or vertex fields and forward/backward direction,
and parallelizes disjoint curves without routing them through a general graph
heap. `edge_transport_parent` applies the same scalar policies to an integer
point-parent forest without requiring topology edges.
It also covers the complete local
crack-policy matrix, and exact multicore output. Attributes can be promoted between point, vertex,
primitive, and detail ownership with explicit deterministic reductions,
component-wise mode/upper median, and integer/text piece partitions that
deduplicate and order contributing elements. Compiled include/exclude globs can
promote several stable-order attributes through one shared incidence plan and
rewrite their destination/index names from captured wildcard spans. Scalar
first/last/minimum/maximum/mode promotion can also record the exact stable
contributing source element. Attributes can alternatively be selected for
direct `Sop.attribute_copy` between ordered point, vertex, or primitive
selections. Copy supports cyclic pairing, integer/text value matching, explicit
source-element indices, owner-independent topology projection, wildcard
renaming, and opt-in canonical `P`; same-size ungrouped copies structurally
share unchanged packed planes instead of materializing them.
`Sop.attribute_combine` layers numeric fields into one destination with copy,
add, subtract, multiply, divide, minimum, and maximum operations; source
scale/add/process controls; scalar/tuple conversion; constant or attribute
blending; cross-input index or integer/text matching; grouped postprocessing;
and optional temporary-source cleanup. All layers execute in one packed
parallel traversal rather than materializing an attribute after every layer.
`Sop.attribute_interpolate` reuses persistent source primitive numbers and UVW
coordinates, or packed CSR point/vertex/primitive number-and-weight rows, to
sample mixed fields into point, vertex, primitive, or detail destinations.
Primitive coordinates can emit equivalent point or vertex weight rows for
later cooks. Its triangle, bilinear quad, n-gon fan, and polygon-curve spaces
follow Houdini; canonical `P`, normalized `N`, typed groups/group patterns,
owner-specific source patterns, matched source groups, normalization/threshold
influence, misses, and destination blending stay in deterministic packed
traversals with one atomic output commit. Variable-length integer/float array
attributes transfer as opaque greatest-coefficient CSR rows with stable ties,
exact cardinality, and disjoint parallel copies.
Attributes can also be selected for
spatial transfer between geometry using stable nearest/k-nearest point or
primitive-barycenter plans, closest-polygon vertex interpolation, or a packed
mixed-owner surface plan. Detail payloads share immutably without copying. The
surface path deterministically ear-clips simple N-gons, barycentrically samples
point/vertex payloads, copies primitive payloads into point, vertex, or
primitive destinations, and can emit closest distance without introducing a
second geometry representation. Primitive groups select complete source faces;
vertex groups can further retain emitted triangles by explicit all-corners or
any-corner rules. Exact group names or compiled group patterns restrict both
transfer paths; matching groups union directly as packed bytes.
Linear, smoothstep, or fixed uniform-bias blend bands taper point, primitive,
vertex, and surface influence outside the full-strength distance threshold.
Point and primitive source combination additionally supports bounded
inverse-distance and exact published Links, RenderMan, or Hart compact kernels;
kernel radius is independent of the distance threshold and all numeric fields
reuse the same in-place normalized coefficient table.
`Sop.attribute_transfer_all` transfers explicit point/vertex/primitive/detail
patterns in one graph node, sharing one query plan per spatial owner and
committing the resulting attribute table once.
Attribute metadata can be deleted with independent owner-specific compiled
patterns, keep-only inversion, and optional reference-geometry name prepend.
Ordered capture-pattern rename rules support all owners and explicit
skip/error/overwrite conflicts. Both batch operations are atomic, preserve
canonical `P` and stable source order, structurally share packed payloads, and
rebuild metadata once.
Typed point/vertex/primitive `delete`, named-group `blast`, and complementary
`split` branches share one packed planner with destroy-touched or polygon/curve
healing policies and optional orphan-point compaction.
`blast_by_attribute` classifies scalar float or integer point/primitive fields
directly into that planner, or replaces a same-owner output group without
touching topology. Its optional base group bounds inversion as well as ordinary
selection, and malformed/non-finite operated values fail before publication.
`crease` authors the vertex `creaseweight` field expected by `subdivide` from
all topology edges or one named native edge group. Add first reduces existing
incident corner values to the unique edge maximum, then writes one coherent
result to every incident corner; Set and Delete use the same edge-consistent
boundary. Optional vertex `Cd` colors both endpoints of every positive crease
without changing unrelated colors.
`attribute_fade` scales a scalar point field through a frame-domain fade-in,
hold, and fade-out envelope. Missing fade/start/hold-scale fields default to
one/zero/one, and the start and hold controls may come from independent
equal-point-count graph inputs. Point groups preserve unselected fade values,
piecewise-linear ramps shape both transitions, and optional visualization
replaces point `Cd` with the faded grayscale value. The graph node declares
only `Context.Frame`, so bounded sessions invalidate on frame changes without
discarding a valid result for irrelevant time, seed, or domain-count changes.
`poly_cut` breaks selected polygon curves without leaving the packed geometry
core. It can remove marked point endpoints or native edges, duplicate point
boundaries, insert exact scalar-threshold crossings, or split tuple changes
into bounded-threshold segments. Numeric point/vertex payload is interpolated,
discrete and ragged payload follows the nearest endpoint, and primitive,
ordinary-group, ordered-group, and native-edge ancestry stays deterministic.
`separate_pieces` gives per-piece spatial queries an inexpensive isolation
step. Integer or text identities may live on points or primitives; disconnected
components with one identity move together. Pieces are packed into disjoint
projection intervals along a normalized axis in stable first-occurrence order,
and a same-owner float3 field records the applied rigid translation for the
Move Back mode. Mixed-piece primitives and shared points with conflicting
primitive identities fail instead of being silently deformed.
Optional orphan-point compaction, exact-predicate `convex_hull` with typed
component restriction, deterministic point/line/planar/closed-solid output,
source-point payload ancestry, and generated face groups, `extract_centroid`
over the detail, primitives, or integer/text pieces using point-mass, AABB, or
the same exact hull core, typed `bound` with
divided boxes or polygon sphere/ovoids, asymmetric padding, output groups and center/radii metadata,
the compact `bounding_box` wrapper, and production `match_size` with independent
typed move/source/target selections, unit/numeric or geometry references,
per-axis and cross-anchor alignment, offsets, axis/contain/cover fits, and
perimeter/area/volume scaling, plus robust whole-geometry `match_axis`, round out
the current packed utility surface. Generalized `measure` writes polygon area,
curve/polygon perimeter, or oriented signed volume per primitive or throughout
a primitive group, with an optional detail total; `measure_area` remains the
short compatibility form. `connectivity` writes stable compact point or
primitive classes, can treat excluded group elements as removed topology, and
can split primitive islands at native edge seams or exact vertex UV
discontinuities. `attribute_blur` smooths `P` and matching point
floating attributes through deterministic shared-edge iterations with uniform
or edge-length weights, masks, border pins, and bounded packed double buffers.
`smooth` adds modeling-oriented primitive restriction, explicit locked points,
unshared or selected-group-boundary constraints, and optional normal
recomputation without introducing a second numeric smoothing kernel.
`attribute_randomize` adds stable indexed scalar/tuple variation on every
attribute owner with arithmetic controls, component tail limits,
rotationally-symmetric multidimensional Cauchy, biased/constrained unit
direction/orientation and uniform sphere-volume sampling, inverse-CDF ramps,
weighted tuple or text choices, optional explicit fraction attributes, and
typed point/vertex/primitive/native-edge group expansion;
`attribute_noise` adds coherent scalar or vector Perlin/fBm fields with typed
location, range, operation, blend, frequency, offset, and fractal controls;
its normalized Float4 `orient` mode is a documented Prismel extension rather
than a Houdini parity claim;
`attribute_remap` normalizes or reshapes those values through explicit or
automatic component ranges, cycling/clamping/extrapolation, and a linear ramp.
Topology-preserving `normals`, selection-aware `peak`, captured `bend`/twist,
seeded 3D-fBm `mountain`, and stable-ID `point_jitter` share packed deformation
storage and deterministic range scheduling, including
arbitrary capture frames, custom directions, point masks, optional diagnostic
attributes, and explicit normal recomputation.
Topology-changing `edge_divide` uses the same PDK kernel from direct code and
immutable procedural graphs; `~group` names a native edge group,
`~divisions` is the resulting segment count, and `~share_points:false` isolates
the new points per incident primitive.
`edge_collapse` uses native edge groups too; omitting its group deliberately
selects every edge, while `~connectivity_attribute` keeps exact-value regions
from collapsing together.
`dissolve` removes a named native polygon-edge group (or its complement),
merges manifold face components, and exposes explicit disjoint/bridged/deleted
hole, boundary-curve, inline-point, unused-point, and existing-normal policies.
`poly_bevel` bevels a named native edge group—or all eligible two-sided polygon
edges when omitted—with chamfer/round profiles, divisions, point-scale and
flatness controls, collision-limited ring slides, connected corner handling,
and explicit fillet/offset output groups.
`point_split` accepts point, vertex, or primitive selections and either makes
every selected corner unique or clusters it by matching vertex/primitive seam
attributes and group membership. `~promote_attributes:true` moves matched
attributes—but not groups—onto the new
points, which is useful for turning face-varying normals or UV islands into
editable point data.
`point_generate_origin ~points:n ()` emits `n` origin points without an input.
The connected `point_generate ~mode` form emits in stable source/local order;
`Generate_per_point` optionally multiplies its count by a point-float field and
`Generate_probability` reads a point-float probability. Attribute-copy
patterns, generated grouping, provenance names, seed, and input retention are
all immutable node parameters.
`point_replicate ~points_per_point` is the spatial-cloud counterpart. Supply a
named point group, optional count-scale attribute, shape/size/center/local
orientation, and an explicit seed for deterministic emission. A second
`~custom_shape` SOP supplies reusable shape points when
`~shape:Replicate_custom`; all generated points can then feed Copy-to-Points or
another packed SOP without materializing intermediate polygon topology.
`~transform_attributes:"flow N"` applies each source instancing frame to
matching copied point vectors while keeping `P` on its single position path.
`edge_flip` rotates a named manifold polygon-edge group by `~cycles`; omitting
the group is an intentional no-op, and `~cycle_vertex_attributes:false` keeps
corner payload in its original slots.
`edge_cusp` uniques point fans at the interior of a named edge path and leaves
its two endpoints shared, matching the useful fade behavior of Houdini's Edge
Cusp; an omitted group remains an identity.
`edge_straighten` accepts a named native edge group—or all topology edges when
omitted—and optionally writes the processed selection under `~output_group`.
`circle_from_edges` accepts a named native edge group—or topology boundary
edges when omitted—plus optional `~radius`, `~scale`, and `~output_group`.
Every selected component must be one non-collinear simple path or loop with at
least three points.
`graph_color` accepts a typed point/vertex/primitive/native-edge group and
promotes it to the requested graph owner. `Graph_primitives_by_point`,
`Graph_primitives_by_edge`, and `Graph_points_by_primitive` are explicit
connectivity policies; `~sort_output:true` may additionally produce packed
detail workset ranges.
`edge_equalize` uses the same selection convention and adds typed
`Equalize_average`, `Equalize_longest`, and `Equalize_shortest` target policies
plus explicit iteration/tolerance controls for connected selections.
`edge_relax ~reference` is the two-input companion. Its optional `Point_group`
or `Primitive_group` identifies movable points, `~pin_group` fixes source
points, and `Scale_independent_distribution` adopts reference proportions
without importing its overall scale.
`blend_shapes ~shapes:[blend_shape ~weight target; ...]` keeps source topology
and blends positions plus selected fixed-width floating point fields. Use
`Blend_differencing` for extrapolation, or the default normalized mode for
residual source weighting. Optional point IDs permit reordered and partial
targets; unmatched IDs contribute the source value.
`attribute_composite ~inputs:[attribute_composite_input ~weight target; ...]`
performs a general ordered attribute fold. Choose separate owner patterns,
Mean/Maximum/Minimum/Over/Under, an optional alpha field, and explicit
`~allow_position:true`; the first graph remains the topology and untouched
payload owner.
`attribute_mirror ~owner ~method_` mirrors named packed fields without changing
topology. Use `Attribute_mirror_plane` for reflected point or primitive-center
nearest correspondence, or `Attribute_mirror_mapping` with a named integer map
and destination group for point, vertex, or primitive data. Copy, UV, vector,
point, literal text-replacement, pair-output, and side-group policies remain
immutable SOP parameters; all correspondence scratch stays inside PDK cooking.
`rewire_vertices ~owner ~target_attribute` is the low-level custom-connectivity
node. Point, vertex, or primitive integer targets can be restricted by any
typed component group; recursive point chains, target deletion, newly-unused
cleanup, and original-corner provenance are explicit options. Packed payload,
groups, and topology-affine native edges remain owned and remapped by PDK.
`edge_transport` handles branched topology and optional named point/root groups;
`edge_transport_curves` handles a named primitive subset and deliberately
rejects point fields shared by multiple selected curves. Use vertex ownership
when curves share points. `edge_transport_parent` consumes an integer point
attribute, treats invalid/self parents as roots, preserves cycles as
unreachable, and schedules independent trees through the reusable pool. All
variants preserve topology and commit the resulting scalar field atomically.
`swap_attributes` supplies ordered typed-owner Copy, Move, and Swap rules with
paired wildcard captures. Packed values are shared rather than copied,
missing-side swaps copy the existing field, and point `P` can be stashed,
restored, or exchanged with a float3 attribute without leaving the common PDK
geometry core.
`Inspect.format_output` reports cooked
counts, bounds, attributes, groups, and packed payload size.

Run [`procedural_terrain`](./examples/procedural_terrain) unchanged in native,
headless, or web mode. [`procedural_modeling`](./examples/procedural_modeling)
adds directed lines, curve resampling/sweep, capped unique-edge PolyWire,
normal-directed Peak/Mountain, captured Bend/Twist deformation, ray-draped
attribute-transferred surfaces, a frame-driven Attribute Fade relief,
attribute-crossing PolyCut fragments,
reversibly separated integer-identified pieces,
an iteratively equalized PolyWire path,
a reference-relaxed PolyWire path,
an Edge-Transport-driven distance relief,
an Attribute-Composite position/color panel,
grid-quantized surfaces, asymmetric bounding
ovoids, topology
group growth/promotion,
individual-face extrusion, typed attributes, and copy to points. The
[remesh example](./examples/remesh) shows the coarse input and isotropically
rebuilt surface side by side with an orbit camera. The
[convex-hull example](./examples/convex_hull) builds an exact-predicate packed
surface around 6,000 authored points and exposes source-point ancestry. The
[Extract Centroid example](./examples/extract_centroid) computes one packed
center per box face and copies visible marker geometry to those targets. The
[Extract Point from Curve example](./examples/extract_point_curve) finds
constant or per-curve scalar-field cuts, exposes curve diagnostics, and copies
visible markers to the resulting disconnected points. The
[Circle from Edges example](./examples/circle_from_edges) overlays distorted
3D loops with their packed least-squares fitted circles. The
[Graph Color example](./examples/graph_color) contrasts conflict-free primitive
schedules for shared-edge and shared-point adjacency. The
[Measure Curvature example](./examples/measure_curvature) visualizes signed mean
and Gaussian curvature over the parameter domain of the same packed torus. The
[Attribute Laplacian example](./examples/attribute_laplacian) compares
pointwise cotangent and uniform position-field responses on a torus. The
[Triangulate 2D example](./examples/triangulate_2d) projects a tilted point
cloud to its PCA best-fit plane, exactly splits two crossing constraints, and
displays the resulting constrained-Delaunay triangles
that retain the authored 3D point positions. The
[exact Boolean example](./examples/boolean) shows a payload-preserving solid
difference cooked by the public treatment-aware SOP. The
[Boolean Detect example](./examples/boolean_detect) highlights source faces
that intersect a second surface while retaining collision primitive lists. The
[Intersection Analysis example](./examples/intersection_analysis) turns the
surface crossings and an explicit pair of crossing polygon curves into orange
editable points with packed primitive/UVW provenance. See the
[PDK](./specification/pdk.md) and
[procedural graph](./specification/procedural.md) specifications for ownership,
cache, determinism, complexity, and HDK/SOP research sources. The
[SOP parity audit](./specification/sop-audit.md) records exactly which Houdini
modes are complete, intentionally narrower, partial, or still missing.
The [modeling-kernel guide](./specification/modeling-kernels.md) defines the
single-core Geom migration and the robustness requirements for advanced
subdivision, Boolean, repair, remesh, transfer, and reduction algorithms.
The dedicated [exact Boolean specification](./specification/boolean.md) records
the paper/OSS evidence, licensing boundary, kernel invariants, adversarial
corpus, and public-promotion gates.

### Coordinates and Retina displays

Sketch sizes, `Frame.width`/`height`, every `Scene` coordinate, mouse events,
`frame.mouse`, and PXUI layout all use the same logical-point coordinate
system. A `Sketch` configured as `800 × 600` therefore stays `800 × 600` for
layout and hit testing on both standard and Retina displays. SDL maps drawing
and pointer events between logical points and the native framebuffer
automatically, so application code must not multiply mouse positions by a
Retina scale.

When native backing pixels matter, use the per-frame values:

```ocaml
let backing_w, backing_h = frame.drawable_size
let scale_x, scale_y = frame.pixel_scale
```

`drawable_width`, `drawable_height`, and `drawable_size` report the current
renderer output in physical pixels. `pixel_scale` reports physical pixels per
logical point and is commonly `(2., 2.)` on a Retina display. A
`WindowResized` event and the next frame use the new logical size; Prismel uses
SDL's authoritative size-changed notification to keep the renderer and input
mapping synchronized.

Realtime timing is the default. For deterministic simulation, tests, and frame
export, select a positive fixed timestep:

```ocaml
let config =
  { Sketch.default_config with clock = Sketch.Fixed (1. /. 60.) }
```

With a fixed clock, `frame.dt`, `frame.time`, and `frame.fps` are derived only
from the configured step and `frame.count`, independent of rendering speed.

Export a reproducible PNG sequence with the same scene function:

```ocaml
let () =
  Sketch.export ~directory:"frames" ~prefix:"orbit" ~frames:240 ~fps:60
    (fun frame ->
      Scene.[
        clear Color.black;
        circle
          ~at:(400 + int_of_float (cos frame.time *. 180.),
               300 + int_of_float (sin frame.time *. 180.))
          ~radius:18 ~fill:Color.cyan ();
      ])
```

`Sketch.export_state` is the stateful equivalent. Both create the output
directory, disable realtime frame limiting, and derive every frame from a fixed
clock. Run with `HEADLESS=1` to export without opening a display.

For stateful work, use a normal immutable OCaml model:

```ocaml
open Prismel

let update x (frame : Frame.t) =
  let speed =
    if Frame.key_down Input.ArrowRight frame then 180.
    else if Frame.key_down Input.ArrowLeft frame then -180.
    else 0.
  in
  x +. (speed *. frame.dt)

let view x (frame : Frame.t) =
  Scene.[
    clear Color.black;
    circle ~at:(int_of_float x, frame.height / 2)
      ~radius:24 ~fill:Color.yellow ();
  ]

let () =
  ignore
    (Sketch.run_state
      ~init:(fun _frame -> 100.)
      ~update ~view ())
```

### Fonts and text

`Scene.text` draws antialiased text with the installed platform UI font:
San Francisco/Helvetica on macOS, Segoe UI on Windows, and Noto Sans or a
compatible sans-serif fallback on Linux. Its optional `~size` is a logical
point size and defaults to 14:

```ocaml
Scene.text ~at:(24, 24) ~size:18 "System text"
```

Set `PRISMEL_UI_FONT` to a readable TrueType/OpenType font path to override the
platform search. Prismel does not bundle proprietary system fonts. If no
supported installed font can be resolved, `Scene.text` falls back to the fixed
bitmap diagnostic face. Use `Scene.debug_text` explicitly when that compact
8×8 SDL2_gfx text is what you want.

Load a project font through `Assets` for explicit typography, wrapping, and
alignment:

```ocaml
let view assets _model _frame =
  let font = Assets.font_exn assets ~size:24 "assets/Inter-Regular.ttf" in
  Scene.[
    clear Color.black;
    font_text font ~at:(24, 24) ~wrap:360 ~align:Font.Center
      "Scenes are data, including this wrapped label.";
  ]
```

Rendered text textures are cached by font, renderer, content, color, wrapping,
alignment, and native raster size. Fonts keep their public dimensions in
logical points while rasterizing separate sharp glyph textures for the active
renderer density. Repeating a label every frame does not rerasterize it, and
moving between display densities selects the appropriate cached font handle.
The automatic scene-drawing cache keeps each renderer's 256 most-recent text
textures, so counters, edited fields, and dragged numeric values remain
memory-bounded. Explicit images borrowed from `Font.cached_text` keep their
documented lifetime until `Font.clear_cache` or `Font.destroy`. Empty text is a
safe no-op at the scene boundary.
Font style, hinting, or kerning changes invalidate the cache automatically;
each renderer-local cache is LRU-bounded to 256 entries so dynamic counters do
not grow textures forever. Empty `Scene.text` and `Scene.font_text` values are
safe no-op text. Values loaded through `Assets` remain borrowed and are cleaned
up by `Sketch.run_assets`.

### Multicore updates

`Sketch` owns a reusable Domainslib worker pool. Use it for sufficiently large,
independent CPU computations:

```ocaml
let update particles frame =
  Parallel.map ~grain:256 (step_particle frame) particles
```

`Parallel.map` preserves list order, and `Parallel.both` runs two independent
computations together. Keep all `Graphics`, `Scene.render`, SDL resource, input,
font, and texture calls on the main domain. Parallel functions should operate
on immutable or independently owned data.

The worker count defaults to OCaml's recommended domain count. Override it in
the sketch configuration, including `Some 1` to run sequentially:

```ocaml
{ Sketch.default_config with domains = Some 4 }
```

See [`examples/particles`](./examples/particles) for a complete multicore
sketch.

### Assets

`Sketch.run_assets` owns and deduplicates images, fonts, samples, and music
automatically:

```ocaml
let init assets _frame =
  Assets.image_exn assets "images/character.png"

let view _assets character _frame =
  Scene.[clear Color.black; image character ~at:(40, 40) ()]

let () =
  ignore
    (Sketch.run_assets ~root:"assets"
      ~init
      ~update:(fun _assets model _frame -> model)
      ~view ())
```

Resources returned by `Assets` are borrowed; the cache releases them before SDL
shuts down. `Assets.preload` attempts all requested files and returns every
error. During visual iteration, add `~watch:true` to `Sketch.run_assets`.
Changed image files are reloaded between update and view while preserving the
borrowed `Image.t` identity already stored in your model. Decode failures keep
the previous valid texture and print a warning. See the
[asset specification](./specification/assets.md).

For a larger startup batch, `Assets.preload_parallel` reads image files through
the active Domainslib pool, then performs SDL decode/upload in request order on
the initial domain. This overlaps safe filesystem work without moving renderer
objects or SDL calls onto workers.

### Audio

Load cached samples through `Assets`, or synthesize a tone immediately:

```ocaml
let tone =
  Result.get_ok
    (Audio.Sample.synth
      ~waveform:Audio.Sample.Sine
      ~frequency:440.
      ~duration:0.2
      ())

let () = ignore (Audio.Sample.play tone)
```

`Audio.Sample` supports polyphonic channels; `Audio.Music` supports streamed
playback and fades. Normalized volumes use `0.0`–`1.0`. In headless mode the
real decoder and mixer run against SDL's dummy device, so audio paths remain
testable without speakers. See [`examples/audio`](./examples/audio) and the
[audio specification](./specification/audio.md).

### Deterministic generative tools

Use immutable `Rand.t` generators instead of global random state:

```ocaml
let radius, random = Rand.int_range ~min:8 ~max:64 random
let hue, random = Rand.range ~min:0. ~max:360. random
let color = Color.hsv hue 0.8 0.95
```

Seeded coherent noise and palette gradients make reproducible organic fields:

```ocaml
let noise = Noise.create 2026
let value = Noise.fbm3 ~octaves:5 noise ~x ~y ~z:time
let color =
  Color.gradient
    (List.map Color.hex_exn ["#101426"; "#3ca6a6"; "#f2d16b"])
    value
```

Generators and noise values can be safely shared or split for multicore work.
See [`examples/noise`](./examples/noise) and the
[generative API specification](./specification/generative.md).

### Paths, clipping, pixels, and capture

Paths are immutable and pipeline-friendly:

```ocaml
let leaf =
  Path.empty
  |> Path.move_to 128. 24.
  |> Path.cubic_to
       ~control1:(232., 54.) ~control2:(220., 196.) ~to_:(128., 232.)
  |> Path.cubic_to
       ~control1:(36., 196.) ~control2:(24., 54.) ~to_:(128., 24.)
  |> Path.close

let picture =
  Scene.[
    path ~fill:(Color.hex_exn "#34d399") ~stroke:Color.white leaf;
    clip ~at:(64, 64) ~w:128 ~h:128 [
      circle ~at:(128, 128) ~radius:100 ~fill:Color.cyan ();
    ];
  ]
```

`Canvas` provides CPU-backed offscreen rendering that also works headlessly:

```ocaml
let canvas = Canvas.create_exn ~width:256 ~height:256
let () = Canvas.render canvas picture
let center = Canvas.pixel canvas ~x:128 ~y:128
let () = Result.get_ok (Canvas.save_png canvas "picture.png")
```

Use `Canvas.map_pixels` for explicit pixel effects, `Canvas.to_image` to upload
a snapshot, and `Canvas.save_screen_png` to capture the current framebuffer.
On native/headless targets it writes to the filesystem and preserves the
framebuffer's native pixel dimensions, so an `800 × 600` logical Retina window
commonly produces a `1600 × 1200` capture. On the web target it downloads the
presented canvas as a PNG in the browser. Ordinary `Canvas.create` dimensions
remain explicit canvas pixels. Release owned resources with
`Sketch.run_state ~on_stop`. See
[`examples/canvas`](./examples/canvas) and the
[composition specification](./specification/composition.md).

## Creating and running examples

Every example is an independent dune executable under `examples/<name>/`.
Create the standard project shape with:

```bash
dune exec tools/new_example.exe -- my_sketch
```

The command adds these two files:

```text
examples/
└── my_sketch/
    ├── dune
    └── main.ml
```

`examples/my_sketch/dune`:

```lisp
(executable
 (name main)
 (libraries prismel))
```

`examples/my_sketch/main.ml`:

```ocaml
open Prismel

let view (frame : Frame.t) =
  Scene.[
    clear (Color.hex_exn "#111827");
    circle ~at:frame.mouse ~radius:36 ~fill:(Color.hex_exn "#22d3ee") ();
    text ~at:(12, 12) "my_sketch";
  ]

let () =
  Sketch.run
    ~config:{ Sketch.default_config with title = "my_sketch" }
    view
```

Build or run only that example:

```bash
dune build examples/my_sketch/main.exe
dune exec examples/my_sketch/main.exe
```

For a fast edit–compile–restart loop, install
[watchexec](https://watchexec.github.io/) and run:

```bash
watchexec --restart --exts ml,mli,dune -- \
  dune exec examples/my_sketch/main.exe
```

`dune exec --watch examples/my_sketch/main.exe` is sufficient for programs that
terminate between rebuilds. Interactive sketches are long-running, so
`watchexec --restart` is the reliable workflow: it stops the old process before
starting the newly built executable.

For expression-by-expression scene iteration, launch the library toplevel:

```bash
dune utop lib/prismel
```

Then keep one preview window alive while evaluating new scene expressions:

```ocaml
open Prismel;;

Preview.show Scene.[
  clear (Color.hex_exn "#111827");
  circle ~at:(240, 180) ~radius:80 ~fill:Color.cyan ();
];;

Preview.show Scene.[
  clear Color.black;
  rotate 0.4 [
    square ~at:(180, 120) ~size:120 ~fill:Color.magenta ();
  ];
];;

Preview.stop ();;
```

`Preview.step` returns the events polled before drawing when interactive
experiments need input. `Preview.show` starts the session automatically; an
explicit `start` is only needed to choose the initial window size/title.

To make an example useful in headless CI, arrange for it to terminate on its
own. The framework intentionally does not choose an arbitrary frame limit:

```ocaml
let frames = ref 0

let update state (_frame : Frame.t) =
  incr frames;
  if Sketch.is_headless () && !frames >= 3 then Sketch.quit ();
  state
```

Then run it without a display:

```bash
HEADLESS=1 dune exec examples/my_sketch/main.exe
```

If the example uses PXUI, add `pxui` to its libraries:

```lisp
(executable
 (name main)
 (libraries prismel pxui))
```

See [`examples/basic`](./examples/basic),
[`examples/generative`](./examples/generative),
[`examples/three_d`](./examples/three_d), and
[`examples/pxui`](./examples/pxui) for complete projects.

## Adding another library

The main framework lives in `lib/prismel`. Add-on libraries live beside it at
`lib/<library-name>` and depend inward on `prismel`. For example:

```text
lib/my_addon/
├── dune
├── my_addon.ml
└── my_addon.mli
```

```lisp
(library
 (name my_addon)
 (libraries prismel))
```

Keep Prismel independent of add-ons. The full repository conventions and
dependency direction are documented in [`AGENTS.md`](./AGENTS.md).

## 📚 Module Documentation

### Core Modules

- **`Sketch`**: Functional application lifecycle and owned cleanup
- **`Frame`**: Immutable per-frame time, size, input, and event snapshot
- **`Scene`**: Pure composable drawing descriptions
- **`Path`**: Immutable custom line and curve geometry
- **`Canvas`**: Offscreen rendering, pixels, capture, and export
- **`Parallel`**: Safe ordered multicore computations
- **`Rand` / `Noise`**: Reproducible generative tools
- **`Assets`**: Deduplicated borrowed media resources
- **`Preview`**: Persistent scene renderer for REPL iteration
- **`Low`**: Explicit mutable backend escape hatch (`App`, `Window`,
  `Graphics`, and `Backend`)
- **`Color`**: Color representation and manipulation utilities
- **`Math`**: Mathematical constants and utility functions
- **`Vec2`**: 2D vector operations for geometric calculations
- **`Mat3`**: 3x3 matrices for 2D transformations

### Sibling Libraries

- **`Geom`** (`prismel.geom`): Immutable 2D geometry, sampling, triangulation,
  Voronoi cells, scene adapters, procedural 3D mesh generation, and scalar
  field isosurfaces
- **`Pdk`** (`prismel.pdk`): Packed topology, typed attributes, groups,
  multicore geometry kernels, eager operations, and Prismel mesh conversion
- **`Procedural`** (`prismel.procedural`): Human-first immutable SOP graphs,
  bounded evaluation sessions, inspection, diagnostics, PPX-parameterized
  custom/wrangle-like nodes, and render bridging
- **`Pxui`** (`prismel.pxui`): Functional controls, layout, themes, and
  settings persistence
- **`Sop_catalog`** (`prismel.sop_catalog`): Inspectable catalog SOPs with
  node-owned parameter metadata and a deterministic PPX-generated editor
  manifest, including a labeled standard SOP Switch
- **`Sop_ui`** (`prismel.sop_ui`): Generated selected-node inspectors
- **`Pxui_graph`** (`prismel.pxui_graph`): Command-emitting SOP graph editor
  with multi-selection, persistent tile layout, selectable wires, ordered ports,
  disconnected node creation, hierarchical category submenus, global
  breadcrumb search, subgraph clipboard shortcuts,
  captured navigation, independent inspection/display selection, and VIEW flags
- **`Sketch_support`** (`prismel.sketch_support`): Timeline, bounded reactive
  cooking, and terminal packed-piece render transforms
- **`Sketch_ui`** (`prismel.sketch_ui`): Reusable responsive three-column 2D
  and 3D SOP sketch environments over one shared lifecycle

### Foundational Migration Libraries

- **SDL3** (`prismel.sdl3`, `prismel.sdl3_image`, `prismel.sdl3_ttf`, and
  `prismel.sdl3_mixer`): Audited platform and media bindings under `lib/sdl3*`
- **Metal** (`prismel.metal`): Ownership-aware ARC binding under `lib/metal`,
  generated and tested with OCaml/Dune; it is being qualified beside the active
  renderer until the atomic GPU migration switch

### Input & Events

- **`Event`**: Event type definitions and dispatch system
- **`Input`**: Keyboard and mouse input state management
- **`Time`**: Timing utilities and frame rate management

### Media

- **`Image`**: Image loading and texture rendering
- **`Font`**: Font loading and text rendering
- **`Audio`**: Samples, music, playback control, and simple synthesis

## 🎨 Scene API Preview

```ocaml
open Prismel

let picture =
  Scene.[
    clear (Color.rgb 18 20 28);
    circle ~at:(100, 100) ~radius:50 ~fill:Color.red ();
    rect ~at:(200, 200) ~w:100 ~h:50 ~stroke:Color.blue ();
    rotate (Float.pi /. 4.) [
      circle ~at:(0, 0) ~radius:30 ~fill:Color.yellow ();
    ];
  ]

(* Color utilities *)
let red = Color.rgb 255 0 0
let transparent_blue = Color.rgba 0 0 255 128
let brighter_red = Color.lighten red 0.2
```

## 🔧 Development

### Building from Source

```bash
# Development build with watch mode
dune build --watch

# Run tests
dune runtest

# Build documentation
dune build @doc
```

### Contributing

We welcome contributions! Please see our [specification documents](./specification/) for detailed module requirements and design decisions.

**Areas needing help:**
- 🎯 Background asset decoding
- 🎯 Live code reload with model migration
- 🎯 Broader renderer/backend testing
- 🎯 Performance optimizations
- 🎯 Documentation and examples
- 🎯 Cross-platform testing

### Architecture Notes

Prismel follows a functional design philosophy:
- Immutable data structures for application state
- Pure functions for mathematical operations
- Explicit state threading through update/draw cycles
- Minimal mutable state confined to SDL2 backend

## 📖 Learning Resources

- [Specification Documents](./specification/) - Detailed module designs
- [Examples](./examples/) - Working demonstration projects
- [API Documentation](https://nexo.sh/prismel) - Generated docs (when available)

## 🐛 Known Issues

- Asset decoding is synchronous on the main domain
- Native code restart does not automatically migrate arbitrary model values
- Hardware-accelerated offscreen render targets are not yet exposed

## 📄 License

[LICENSE](./LICENSE)

## 🤝 Acknowledgments

- Built on [Tsdl](https://github.com/dbuenzli/tsdl) OCaml SDL2 bindings
- Inspired by [openFrameworks](https://openframeworks.cc/) and [p5.js](https://p5js.org/)
- Part of the [Nexo Tech](https://nexo.sh) ecosystem

---

**Author**: Oleg Pustovit <oleg@nexo.sh>
**Repository**: [nexo-tech/prismel](https://github.com/nexo-tech/prismel)
**Documentation**: [nexo.sh/prismel](https://nexo.sh/prismel)

> 💡 **Tip**: Prismel is perfect for creative coding, data visualization, game prototypes, and educational graphics programming in OCaml!
