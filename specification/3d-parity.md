# openFrameworks 3D parity

Audit baseline: openFrameworks 0.12.1 core reference, checked 2026-07-31.

“Parity” means equivalent user-visible rendering capability and deterministic
headless coverage. Prismel remains functional and does not reproduce mutable
C++ method names one-for-one. A row is complete only when the public API,
renderer behavior, documentation, and a focused test all exist.

Primary references:

- [openFrameworks 3D overview](https://openframeworks.cc/documentation/3d/)
- [`ofMesh`](https://openframeworks.cc/documentation/3d/ofMesh/)
- [`ofNode`](https://openframeworks.cc/documentation/3d/ofNode/)
- [`ofCamera`](https://openframeworks.cc/documentation/3d/ofCamera/)
- [`ofEasyCam`](https://openframeworks.cc/documentation/3d/ofEasyCam/)
- [`of3dGraphics`](https://openframeworks.cc/documentation/3d/of3dGraphics/)
- [`of3dPrimitive`](https://openframeworks.cc/documentation/3d/of3dPrimitive/)
- [`ofLight`](https://openframeworks.cc/documentation/gl/ofLight/)
- [`ofMaterial`](https://openframeworks.cc/documentation/gl/ofMaterial/)
- [`ofShader`](https://openframeworks.cc/documentation/gl/ofShader/)
- [`ofTexture`](https://openframeworks.cc/documentation/gl/ofTexture/)
- [`ofVboMesh`](https://openframeworks.cc/documentation/gl/ofVboMesh/)

Status meanings: **complete** is covered end-to-end, **partial** has a real
implementation with named gaps, **missing** has no public implementation, and
**syntax difference** means the rendering capability is complete through
Prismel's typed functional API but does not accept the corresponding mutable
C++/runtime-GLSL spelling.

| Capability | Status | Prismel evidence / remaining gap |
|---|---|---|
| 3D vectors and 4×4 transforms | complete | `Vec3`, `Mat4`; inverse/composition tests |
| Indexed vertices | complete | `Mesh.create`, indices, bounds validation |
| Vertex normals and colors | complete | Mesh attributes, recalculation, lit interpolation |
| Texture coordinates | complete | Stored/generated and interpolated perspective-correctly |
| OF primitive modes | complete | Points, lines, line strip/loop, triangles, strip, fan |
| Filled, wireframe, vertex drawing | complete | `Scene3.Faces`, `Wireframe`, `Vertices` |
| Mesh append and transform | complete | Immutable `Mesh.append` and `transformed` |
| Mesh mutation/clear/set helpers | complete | Immutable per-element/full-attribute replacement, safe index/vertex removal, index-range coloring, auto indices, and clear operations |
| Centroid, duplicate merge, smooth/flat normals | complete | Deterministic centroid, seam-preserving duplicate merge, angle-aware smoothing groups, normal recalculation, and flat vertex splitting |
| Face extraction and normal queries | complete | `Mesh.faces`, indexed face/geometric-normal queries, triangle expansion, compact `submesh`, and vertex/face `normal_lines` |
| Plane primitive and resolution | complete | `Mesh.plane` |
| Box primitive, sides, and per-axis resolution | complete | `Mesh.box` plus individually constructible `box_side` geometry |
| UV sphere primitive and resolution | complete | `Mesh.sphere` |
| Icosphere and subdivision | complete | `Mesh.icosphere` |
| Cylinder and cone, caps/resolution | complete | `Mesh.cylinder`, `Mesh.cone`; independent radial, height, and concentric-cap resolution |
| Axis, grid, grid plane, arrow helpers | complete | Colored axis, XY/XZ/YZ grids, rotation rings, solid arrows, and normal diagnostics |
| Primitive UV remapping | complete | `Mesh.remap_tex_coords` maps normalized primitive UVs into arbitrary texture rectangles |
| Hierarchical position/rotation/scale | complete | Immutable scoped `Scene3` transforms |
| Persistent node parenting and global transforms | complete | Immutable `Node3`, maintain-global reparenting, local/global point/direction conversion, position/orientation setters, Euler queries |
| Node look-at, orbit, rotate-around, pan/tilt/roll, dolly/truck/boom | complete | `Node3` and camera functional transform helpers |
| Perspective camera | complete | FOV, near/far, lens offset, viewport/forced aspect, and image-plane distance |
| Orthographic camera | complete | `Camera.orthographic` |
| World/camera/screen conversion | complete | Named world/camera conversion, world/screen conversion, and picking rays |
| Off-axis portal, V-flip, frustum drawing | complete | `Camera.off_axis_portal`, `with_v_flip`, and `frustum_mesh`; projection tests |
| Mouse-controlled easy camera | complete | Remappable button/key interactions, control area, capture, inertia/drag, sensitivities, up/relative-Y behavior, auto-distance, scroll, double-click reset, focus-loss cancellation |
| Per-pixel depth test | complete | CPU Z-buffer; headless overlap test |
| Native fixed-pipeline GPU rendering | partial | OpenGL vertex transforms, depth/stencil, lighting, culling, blending, primitives, and window MSAA for untextured fixed-pipeline scenes; textures, typed shaders, shadows, fog, and separate specular still use an explicit software fallback |
| Homogeneous frustum clipping | complete | Triangles clip against all six clip planes before rasterization |
| Front/back/disabled face culling | complete | `Scene3.cull` |
| Line width and point size | complete | Scoped `Scene3.raster_state`; headless coverage verifies widened line/point rasterization |
| Viewport rendering | complete | Logical `Scene.view3d ?viewport` |
| Ambient, directional, point, spot lights | complete | `Light` plus Blinn-Phong renderer |
| Area lights | complete | Rectangular lights use configurable deterministic 1/4/9/16-point surface sampling |
| Light attenuation and spot controls | complete | Constant/linear/quadratic, cutoff, concentration |
| Diffuse/ambient/specular/emissive material | complete | `Material` |
| Material shininess | complete | Blinn-Phong specular exponent |
| Smooth versus flat lighting toggle | complete | `Scene3.Smooth` and `Flat`, with face-normal vertex splitting |
| Separate specular and global lighting state | complete | Per-scene immutable ambient/lights plus `separate_specular` texture-compositing control |
| 2D texture sampling on meshes | complete | Immutable CPU textures, nearest/bilinear filters, perspective-correct UVs |
| Texture subsection/normalized coordinate controls | complete | Immutable pixel-accurate `Texture.subsection`, normalized/remappable UVs, and clamp/repeat/mirror |
| Texture mipmaps and minification | complete | Immutable mip-chain generation, explicit LOD sampling, and automatic perspective triangle derivatives with trilinear filtering |
| Persistent prepared mesh buffers | complete | Meshes retain immutable vertex/index arrays; weak identity caches reuse normals, flat expansion, triangle/pair topology, and instanced geometry without extending mesh lifetime |
| Instanced drawing | complete | `Scene3.instances` shares one immutable mesh across transform values |
| Programmable vertex/fragment stages and uniforms | complete | `Shader3`; typed scalar/vector/color/matrix/texture uniforms, custom clip position, perspective varyings, discard/depth output; headless raster tests |
| Runtime GLSL source/file spelling | syntax difference | Typed OCaml stages and ordinary OCaml source modules replace runtime GLSL strings, preserving programmable rendering on the no-OpenGL headless reference |
| Geometry stages | complete | `Shader3.geometry` emits mixed point/line/triangle primitives through full clipping/raster state; headless point-to-triangle test |
| Compute dispatch | complete | `Compute3.dispatch` exposes deterministic group/local/global IDs, typed uniforms, ordered arbitrary results, and coarse parallel execution |
| Transform feedback | complete | `Transform_feedback3.capture` retains vertex/geometry primitives, attributes, varyings, and attributed world-space meshes without fragments |
| Scene multisample antialiasing | complete | Deterministic 1×/4×/9×/16× coverage sampling and resolve |
| FBO color/depth/stencil attachments | complete | `Framebuffer3` runs the shared raster core offscreen; readable immutable attachments, depth comparison/write control, masked 8-bit stencil tests and pass/fail operations |
| Alpha-correct translucent 3D sorting | complete | Per-pixel fragments sort back-to-front and respect opaque depth |
| Replace/alpha/add/multiply/screen/subtract blending | complete | Scoped immutable blend state uses the shared per-fragment depth/stencil pipeline; additive headless test |
| Mesh file loading/saving | complete | OBJ and ASCII PLY load/round trips; deterministic ASCII and little-/big-endian binary PLY output |
| Composable post-processing | complete | `Framebuffer3.color` feeds subsequent textured/shader passes; headless two-pass inversion test |
| Built-in shadows | complete | `Framebuffer3.shadow` + `Shadow3`; light-bound normalized depth maps, constant/normal bias, strength, hard/3×3/5×5 PCF, per-fragment sampling; occluder/receiver test |
| Built-in fog | complete | `Fog3` linear, exponential, and exponential-squared distance models run per fragment and are covered headlessly |

## Deliberate API boundary

OpenFrameworks exposes mutable OpenGL resource IDs and accepts runtime GLSL
strings/files. Prismel instead exposes immutable resources and typed OCaml
stage functions. That difference does not remove a rendering stage: vertex,
geometry, fragment, compute, and transform-feedback behavior all execute on
the deterministic software backend. An optional accelerated backend may add
GLSL interop later, but it must not weaken the displayless reference path.
