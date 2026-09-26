# openFrameworks 3D capability audit

Reference baseline: openFrameworks 0.12.1 core documentation, audited
2026-07-31.

“Complete” means the public Prismel API, current native Scene3 lowering, Metal
execution, ownership behavior, and focused framebuffer qualification all
exist. A pure constructor, retained compatibility implementation, or isolated
low-level Metal test is not enough.

Primary public references include the openFrameworks documentation for 3D,
mesh, node, camera, easy camera, primitives, light, material, shader, texture,
and VBO mesh. Prismel follows equivalent visible behavior where appropriate;
it does not copy mutable C++ APIs or expose native resource identifiers.

Status meanings:

- **complete** — qualified end to end on the native backend;
- **partial** — real public/native behavior exists, with the named gap;
- **API only** — the public value remains but native lowering rejects or does
  not yet implement it;
- **missing** — no supported public/native behavior.

| Capability group | Status | Current native boundary |
|---|---|---|
| Vectors, quaternions, matrices | complete | Pure `Vec3`, `Quat`, and `Mat4`; exact mathematical tests |
| Indexed mesh storage, attributes, editing and queries | complete | Immutable `Mesh`; native lowering validates index topology and requires per-vertex normals |
| Plane, box, sphere, icosphere, cylinder, cone mesh generators | complete | Produce ordinary immutable meshes; supported triangle faces enter the native path |
| Perspective/orthographic cameras and world/screen conversion | complete | Logical viewports, native drawable conversion, picking and camera fixtures |
| Easy-camera interaction | complete | Ordered Prismel input, capture/focus/resize behavior; camera output feeds the same native path |
| Hierarchical transforms | complete | Scoped scene transforms packed into native matrices |
| Filled triangle drawing | complete | Triangle, strip, and fan input become checked indexed Metal draws |
| Depth compare/write and face culling | complete | Lowered to native render-pass/pipeline state and covered by overlap fixtures |
| Replace/alpha/add/multiply/screen/subtract blending | partial | Supported fixed families lower to Metal; every family/sample combination still follows device capability checks |
| Fixed material, scene ambient color, directional/point/spot/area lights | partial | Uniform packing and native fixed pipeline exist; more than 64 lights is a typed `Too_many_lights` lowering error; parity for every light policy is not yet a blanket claim |
| Sampled mesh texture | partial | One sampled texture with checked resource/sampler ownership; the broader texture API is not all Scene3-qualified |
| Shadow input | partial | `Scene3.create ?shadow` takes one shadow map, which lowers natively; full public policy parity remains open |
| Scene multisampling | partial | Supported sample counts are device-negotiated; exact per-count parity is a qualification matrix |
| Wireframe, vertices, point and line modes | API only | Current public native lowering rejects non-face/non-triangulable drawings |
| Scoped line width and point size | API only | State constructors exist; their drawing modes are not public-native complete |
| Full stencil behavior | API only | Public state exists; current Scene3 preparation does not claim complete stencil lowering |
| Smooth/flat policy parity | partial | Mesh normals reach native lighting; all public splitting/interpolation combinations require end-to-end fixtures |
| Separate-specular policy | partial | Public value and uniform field exist; complete visible-behavior parity remains a qualification item |
| Instanced Scene3 submission | partial | Public immutable batches exist; end-to-end native instancing must be distinguished from repeated retained draws |
| General offscreen color/depth/stencil framebuffer API | missing | The installed public library has Canvas/capture resources, not a public `Framebuffer3` module |
| General post-processing graph | missing | Requires typed native shader/attachment integration |
| Mesh import/export | partial | `Pdk.Io` OBJ/OFF/STL over packed geometry; `Mesh` has no file IO of its own |

## Deliberate API boundary

Prismel favors immutable values, typed errors, and owned resources. Raw Metal
handles and stringly runtime shader dispatch are outside the public API. A
future programmable path must use typed MSL/IR, validate bindings and device
capabilities, retain completion-owned resources, and preserve the same public
scene lifecycle.

The detailed acceptance requirements live in [3d.md](3d.md). Update this table
only with public-native evidence from a committed source tree.
