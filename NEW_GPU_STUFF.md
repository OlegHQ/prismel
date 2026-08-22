# Prismel GPU Infrastructure Plan

## Status and authority

This document defines the GPU and platform migration that must be completed
before the implementation work in `OPTIMIZATION_PLAN.md` begins. It is an
architecture and qualification plan, not a claim that the new stack already
exists.

The completion gates in this document are mandatory. A phase is not complete
because it compiles, draws one frame, or passes a hand-picked example. The
whole migration is complete only when every final gate is green, the legacy
stack has been deleted, and the evidence described below has been recorded.
There are no completion waivers, temporary fallbacks, or deferred `TODO`s.

## Decision

Prismel should replace its SDL2/Tsdl/OpenGL rendering stack with four explicit
layers:

1. A Prismel-owned SDL3 binding for windowing, events, input, high-DPI facts,
   audio, image decode, font rasterization, and the Metal view bridge.
2. A Prismel-owned, audited binding to Apple's Metal and QuartzCore APIs.
3. A small backend-neutral GPU abstraction named `ogpu`, shaped by the useful
   parts of Blade but designed for OCaml ownership and Prismel's needs.
4. A Metal backend for `ogpu`, plus a target-neutral packed software rasterizer
   for authoritative headless and web rendering.

SDL3 GPU is not Prismel's native renderer. It cannot expose every Metal feature
or give Prismel ownership of native synchronization, heaps, argument tables,
acceleration structures, pipeline archives, counters, and Metal 4 commands.
SDL3 remains valuable as a narrow, well-tested platform layer.

The implementation must be developed beside the current renderer and switched
only after parity. Removing Tsdl first and temporarily routing native rendering
through SDL software would conflict with the zero-regression and performance
requirements. The correct order is to build and qualify the replacement in
parallel, switch atomically, and then delete every legacy dependency.

## Supported scope

The first completed release targets Apple Silicon Macs running macOS 14 or
newer. It must be tested on the oldest supported Apple GPU family represented
by an M1 and on an Apple GPU with hardware ray-tracing features represented by
an M3 or newer. Newer Metal 4 functionality remains runtime capability-gated.

The required release matrix has three independent lanes: M1 with the macOS 14
deployment floor, M1 with the current pinned SDK/runtime for availability and
Metal 4 checks, and M3-or-newer with that current runtime for hardware-specific
ray-tracing coverage. Passing only on the development machine is insufficient.

The binding coverage target is:

- the non-deprecated public API of the pinned macOS SDK's `Metal.framework`;
- `QuartzCore.CAMetalLayer` and drawable presentation;
- the Metal debugging, capture, counters, indirect command, resource, render,
  compute, blit, machine-learning, and acceleration-structure APIs exposed by
  that SDK;
- a separately linked optional `MetalFX.framework` binding;
- SDL3 and the SDL3_image, SDL3_ttf, and SDL3_mixer APIs used by Prismel, with
  a complete generated inventory of the rest of their stable public surface.

MetalKit, Metal Performance Shaders, MPSGraph, GameController, iOS, tvOS,
Windows, Linux, Vulkan, and Direct3D are not part of this migration. They may
be added later as sibling libraries without changing `ogpu` ownership.

"Full Metal control" means every in-scope SDK symbol is inventoried, every
supported feature can be reached through the low-level binding, and the Metal
backend offers a checked native extension for features intentionally absent
from the portable `ogpu` core. It does not mean pretending an M1 implements
features that only exist on a newer GPU. Unsupported capabilities must be
reported exactly and rejected explicitly.

## Compatibility contract

Zero regression applies to the stable Prismel API and behavior:

- `Sketch`, `Frame`, `Scene`, `Scene3`, `Canvas`, `Image`, `Font`, `Audio`,
  `Event`, `Input`, and the public geometry/procedural/UI APIs retain their
  source-level behavior;
- all examples and sketches compile without source edits caused by this
  migration;
- native, headless, and web behavior is covered by fixed fixtures;
- deterministic headless/web outputs remain byte-identical where the current
  result is documented;
- native rendering, startup, allocation, and memory do not regress under the
  benchmark policy below.

Exact source compatibility is impossible for SDL2 escape hatches while also
removing Tsdl. The following interfaces currently expose `Tsdl.Sdl` values and
must be classified as legacy low-level API in the release notes:

- `Window` renderer, window, flags, and GL context access;
- `Low.App.get_renderer` and `Low.Graphics` renderer state;
- `Backend.present` arguments and private image/font renderer hooks.

They must be replaced by narrow Prismel platform or `ogpu` handles. They must
not be emulated with fake SDL2 types. This is the only planned source-breaking
surface and requires a major-version migration guide. The high-level API is a
hard no-change gate.

## Current-state inventory

The current checkout has these relevant properties:

- `dune-project` depends on `tsdl`, `tsdl-image`, `tsdl-ttf`, `tsdl-mixer`,
  four SDL2 `conf-*` packages, Ctypes, and Ctypes Foreign.
- There is no checked-in copy of core Tsdl. The repository-local opam switch
  contains the package. The repository does contain the in-tree `tsdl_gfx/`
  SDL2_gfx binding.
- Direct SDL use spans 21 source/interface files in `lib/prismel` and two in
  `lib/runtime` in the current worktree.
- Native 3D uses a compatibility OpenGL context while 2D and PXUI use SDL's
  OpenGL-backed renderer. This requires fragile state save/restore between two
  renderers sharing one context.
- Headless and web use SDL software rendering and SDL2_gfx primitives.
- `runtime` owns target selection, SDL lifecycle, and frame presentation;
  `prismel` owns scene lowering and renderer behavior; `wap` is independent.
- The current dependency guide says that `prismel` cannot depend on sibling
  libraries. The new foundational libraries therefore require an explicit
  dependency-policy amendment rather than an undocumented exception.

`OPTIMIZATION_PLAN.md` records the diagnostic native baseline for the shattered
cube: 18,278 pieces, 278,368 triangles, 835,104 expanded render vertices,
approximately 86-88% steady CPU with UI visible, 40-43% with UI hidden, and
about 41.4 MiB of client-array mesh data consumed on every draw. Those results
motivate the migration, but the formal acceptance baseline must be captured
again from a named Git commit before implementation.

## Research and feasibility

### SDL3

SDL's official language-binding list does not currently list an OCaml SDL3
binding. Three public candidates were inspected:

| Project | Observation | Decision |
| --- | --- | --- |
| `sanette/ocaml-sdl3` at `45a9556571ec105703882a60674b52ebe0a5a04a` | Broad generated Ctypes surface and an acceptable permissive license; its README calls it early-stage, with few tested functions and unstable signatures | Research and signature reference only |
| `bluddy/ocaml-sdl3` at `5afb519d47a3b978a1afbc5c5ce77b8123739dbd` | Typed C stubs and some tests; core library builds locally | No visible license permits vendoring, and GPU coverage is narrow; do not copy |
| `fccm2/ocaml-sdl3` at `1726d7919fdc1f380de01ef0507833cba43b3f70` | Small draft binding with a minimal permissive license notice | Insufficient coverage and build/test structure; research only |

Both the sanette project and the core bluddy library were buildable in the
Prismel OCaml 5.3 switch. That demonstrates ecosystem feasibility, not
production readiness. Prismel should own its ABI, safe wrapper, tests, release
cadence, and error model.

The current machine has stable SDL 3.4.14 installed. SDL's stable-version rule
uses even minor and patch numbers; development releases must not be production
dependencies. The new binding must record both its compile-time SDL version
and `SDL_GetVersion` at runtime, and reject an older linked library with a
clear error. SDL3_image, SDL3_ttf, and SDL3_mixer are not installed on the
current machine and are explicit bootstrap prerequisites.

SDL3 exposes exactly the macOS bridge needed here:
`SDL_Metal_CreateView` creates the native view and `SDL_Metal_GetLayer` returns
its `CAMetalLayer`. SDL documents this as main-thread work and leaves assignment
of the Metal device to the application. This is a clean platform/GPU boundary.

### Metal and OCaml

`lukstafi/ocaml-metal` at
`c782f0c502f38402cec3ba8d977967327067cdee` was inspected and built. Its SAXPY
example executed successfully on the current M1 and verified 1,048,576 output
values. The project is MIT licensed, but it covers selected compute APIs rather
than a complete rendering, surface, texture, synchronization, Metal 4, and
ray-tracing stack. Its own test-coverage notes call out limited review. It is a
useful executable reference, not the foundational binding.

A standalone Objective-C++ probe was compiled with ARC against Foundation,
Metal, and QuartzCore. It created the Apple M1 device and reported unified
memory, compute/render ray tracing, and Metal 4 family support. A second probe
called the same Objective-C++ bridge from an OCaml executable built by Dune.
It passed after adding the required C++ runtime link. This validates the exact
implementation technique proposed for `lib/metal`.

The selected Command Line Tools expose macOS SDK 26.5 and Metal 4 headers, but
do not contain the `metal` or `metallib` offline shader tools. Runtime MSL
compilation works. A full Xcode installation and the matching Metal Toolchain
are therefore a hard release/CI prerequisite for offline shader compilation,
archive generation, validation, and GPU capture.

### Blade

Blade was inspected at commit
`88cdfc1c99abb7cd26da6673965419f3dfe052aa`. The parts worth adopting are:

- a small graphics layer separate from a high-level renderer;
- descriptor-driven resources and pipelines;
- explicit capabilities and limits;
- explicit resource destruction;
- surface/presentation separated from the device;
- transfer, compute, render, and acceleration-structure passes;
- ray tracing represented as a first-class capability and resource family.

The parts that must not be copied literally are Rust lifetime/generic models
and Blade's deliberately coarse global-pass synchronization. OCaml needs
generational handles, explicit device identity, initial-domain checks, and a
bounded deferred-release queue. Prismel should begin with Metal hazard tracking
enabled and per-pass read/write declarations. Untracked heaps and native
barriers are advanced Metal extensions after correctness is established.

## Target dependency graph

The completed graph is:

```text
examples / sketches / pxui / procedural / pdk
                         |
                         v
                      prismel ----------------> ogpu
                         |                        ^
                         |                        |
                         v                        |
                      runtime -----------> ogpu_metal --------> metal
                         |
                         +----> sdl3 / sdl3_image / sdl3_ttf / sdl3_mixer
                         |
                         +----> wap

prismel ----------------> raster2
```

The dependency policy must be updated to name `sdl3`, the SDL3 extension
bindings, `metal`, `ogpu`, `ogpu_metal`, and `raster2` as foundational
libraries below `runtime` and `prismel`. They are not ordinary sibling feature
libraries. The following directions are forbidden:

- `sdl3` importing Metal, OGPU, Runtime, Prismel, PXUI, or Wap;
- `metal` importing SDL3, OGPU, Runtime, Prismel, PXUI, or Wap;
- `ogpu` importing SDL3, Metal, Runtime, Prismel, PXUI, or Wap;
- `ogpu_metal` importing SDL3, Runtime, Prismel, PXUI, or Wap;
- `raster2` importing SDL3, Metal, OGPU, Runtime, Prismel, or PXUI;
- Wap importing any platform or renderer library.

`runtime` is the only adapter that combines an SDL3 window/Metal layer with an
`ogpu_metal` device and surface. `prismel` records rendering through `ogpu` and
does not receive raw SDL or Metal pointers.

## Library design

### `lib/sdl3`

Package name: `prismel.sdl3`.

Responsibilities:

- initialization, errors, properties, IO streams, paths, timing, logging;
- windows, displays, high-DPI facts, clipboard, dialogs, cursors;
- events, keyboard, text input/IME, pointer, touch, pen, gamepad, sensors;
- audio devices and streams needed by the audio extension;
- CPU surfaces and pixel formats;
- the Metal view creation/destruction/layer bridge;
- complete generated symbol and ABI inventories for the pinned stable headers.

The binding has two layers:

1. `Sdl3.Private_raw`, generated from pinned headers and available only inside
   the binding. It mirrors C values closely and is never a Prismel API.
2. Ownership-aware public modules such as `Init`, `Window`, `Event`, `Surface`,
   `Audio_stream`, `Io`, `Properties`, and `Metal_view`.

The hot binding uses compiled C stubs. It does not use dynamic Ctypes calls.
Header generation must use Clang's parsed AST plus compiled layout probes, not
regular-expression parsing. Generated files include the exact header version
and source hash and are reproducible.

Binding rules:

- distinguish owned, borrowed, and interned handles in types and names;
- make destruction explicit and idempotent;
- snapshot `SDL_GetError` immediately before another SDL call can overwrite it;
- copy borrowed C strings unless a lexical borrow prevents escape;
- convert nullable pointers to explicit results/options;
- use a reusable native event union and copy only the active event payload;
- copy file-drop strings before SDL releases their memory;
- never expose the event union or permit a tag/payload mismatch;
- run video, window, event, texture, and text-input work on the initial domain;
- check `SDL_IsMainThread` at the safe boundary in validation builds;
- avoid C-to-OCaml callbacks where polling, streams, or an event is possible;
- enqueue unavoidable callback results in a bounded native queue and drain it
  on the initial OCaml domain, with no OCaml execution on a foreign thread;
- release the OCaml runtime lock only around documented blocking calls whose
  buffers and handles remain pinned and independently owned;
- attach dimensions and overflow checks before allocating OCaml storage.

The generated inventory classifies every stable core SDL3 symbol as `safe`,
`raw-only`, `platform-excluded`, or `not-applicable`. No symbol may be left
`unreviewed`. Production Runtime may use only the safe layer. SDL_GPU is bound
for SDL3 completeness but is not used by Prismel's renderer.

### SDL3 extension libraries

Use separate packages so applications that do not need a codec or mixer do not
inherit every dependency:

- `lib/sdl3_image` -> `prismel.sdl3_image` for CPU image decode;
- `lib/sdl3_ttf` -> `prismel.sdl3_ttf` for metrics and CPU glyph rasterization;
- `lib/sdl3_mixer` -> `prismel.sdl3_mixer` for the redesigned SDL3 mixer API.

SDL_image must return CPU surfaces which Prismel uploads through OGPU. It must
never create an SDL_GPU texture. SDL_ttf must rasterize glyphs into Prismel's
software or Metal glyph atlas and must not use SDL's GPU text engine.
SDL3_mixer uses its mixer/track model internally while preserving Prismel's
existing sound/music lifecycle and browser command behavior.

Discover stanzas must support Homebrew `pkg-config` and explicit override
paths. If stable opam `conf-sdl3*` packages are unavailable when implementation
starts, Prismel must publish and test its own conf packages. A clean checkout
must never rely on an undeclared Homebrew state.

### `lib/metal`

Package name: `prismel.metal`. It is macOS-only and has no SDL dependency.

The implementation is a narrow C ABI backed by Objective-C++ `.mm` code built
with ARC. Dune compiles the bridge as Objective-C++ and links `libc++`,
Foundation, Metal, and QuartzCore explicitly. OCaml sees typed custom blocks or
generational handles, never Objective-C object pointers as ordinary integers.

The public module families include:

- `Device`, GPU families, feature sets, limits, peer groups, and residency;
- `Command_queue`, command buffers, render/compute/blit/parallel encoders;
- Metal 4 command allocators, queues, command buffers, and encoders;
- `Buffer`, `Texture`, texture views, samplers, heaps, sparse resources;
- libraries, functions, linked functions, function constants, dynamic
  libraries, binary archives, pipeline datasets, and compiler tasks;
- render, tile, compute, mesh/object, and machine-learning pipelines;
- render-pass attachments, depth/stencil, rasterization, visibility, and
  programmable blending state;
- fences, shared events, barriers, resource-state encoders, counters, capture,
  labels, logs, and validation results;
- indirect command buffers, argument encoders/tables, function pointers, and
  intersection-function tables;
- BLAS/TLAS descriptors, triangle/bounding-box/curve/motion geometry,
  acceleration-structure sizing, build/refit/copy/compact commands;
- `CAMetalLayer`, drawable acquisition, colorspace, pixel format, drawable
  count, presentation timing, resizing, occlusion, and teardown.

MetalFX is a separate `lib/metal_fx` package that weak-links the framework and
returns `Unsupported` when the OS/device lacks a requested scaler. MetalKit and
MPS remain out of scope as stated above.

Ownership and execution rules:

- every object records its device, generation, ownership, and destroyed state;
- explicit `destroy`/`release` is the primary lifetime mechanism;
- finalizers are a safety net that enqueue a release token into a bounded
  initial-domain queue; they never invoke Metal directly;
- a resource from one device cannot enter another device's descriptor;
- destroying a parent invalidates dependent borrows predictably;
- mapped shared/readback memory uses a lexical borrow or mapped-range handle,
  not an untracked Bigarray that can outlive the buffer;
- uploaded Bytes/Bigarrays have an explicit copy-or-borrow contract;
- completion handlers never call OCaml on a Metal worker thread; native code
  enqueues completion IDs which Runtime drains;
- one frame-level autorelease pool contains ordinary command recording;
  per-draw autorelease pools are forbidden;
- `[@@noalloc]` is used only after generated stubs and measurement prove that
  no OCaml allocation, exception, callback, or boxing can occur;
- validation builds check use-after-destroy, device mismatch, thread/domain,
  range, alignment, pixel format, and encoder-lifetime errors;
- release builds keep the essential memory-safety checks while allowing
  measured redundant validation to be compiled out.

A Clang-based tool must generate `metal_api_inventory.json` from the pinned SDK.
Every non-deprecated public symbol must be marked `bound`,
`availability-gated`, or `scope-excluded` with a written reason. The final
binding gate rejects `missing`, `unreviewed`, or silently omitted entries.

### `lib/ogpu`

Package name: `prismel.ogpu`. It has no SDL or Metal dependency.

OGPU is a rendering hardware interface, not a scene graph, retained-mode UI,
geometry kernel, material system, or renderer. Its stable concepts are:

- `Instance`, `Adapter`, `Device`, `Queue`, `Surface`, and acquired `Frame`;
- buffers, textures, texture views, samplers, heaps, and memory classes;
- shader artifacts, bind layouts/groups, pipeline layouts, and render/compute
  pipelines;
- command buffers with transfer, render, compute, and acceleration passes;
- fences/events, timestamp/counter queries, debug groups, and captures;
- acceleration structures and their build/refit/compact lifecycle;
- explicit capabilities, limits, formats, alignments, and sample-count masks.

Memory classes are semantic rather than Vulkan-shaped:

- `Device_local` for private GPU resources;
- `Shared` for coherent Apple unified-memory access;
- `Upload` for CPU-written staging data;
- `Readback` for GPU-written CPU reads;
- `External` only through a backend extension with explicit ownership.

Resource descriptors always contain a debug label, size/shape, usage flags,
memory class, and initial-data policy. Creation returns a result. Destruction
is explicit. Generational handles make stale and cross-device use detectable.

Command recording rules:

- command encoders are linear state machines and cannot be reused after end;
- pass descriptors declare resource reads, writes, attachment loads/stores,
  and stages;
- safe Metal hazard tracking is the default;
- resource aliasing and untracked heaps require an explicit advanced mode;
- presentation is a surface operation, not hidden inside a render pass;
- frames in flight are bounded to two by default and three at most;
- stable meshes and textures are persistent resources, not frame uploads;
- one draw call may cross the FFI, but no vertex, pixel, glyph, UI primitive,
  or mesh element may cause its own FFI call;
- command and descriptor scratch storage is reused per frame;
- cache capacities and deferred-destruction epochs are explicit.

OGPU exposes capability values and numeric limits, not optimistic booleans. The
Metal backend reports GPU family, Metal language/version support, argument
buffer/table tier, heaps and sparse resources, ICB variants, mesh shaders,
ray tracing in compute/render, motion geometry, counter sets, timestamps,
MetalFX modes, maximum bindings, buffer/texture alignments, formats, and sample
counts. Unsupported creation returns a typed error before encoding.

Shader artifacts carry a backend identifier, source/provenance hash, entry
points, reflected layouts, and bytes. OGPU does not pretend MSL is portable.
Prismel's built-in native shaders use versioned Metal libraries; a future
Vulkan backend can use its own artifacts without weakening Metal access.

### `lib/ogpu_metal`

Package name: `prismel.ogpu_metal`. It depends only on `ogpu` and `metal`.

It maps generic descriptors onto Metal, owns native command submission and
deferred destruction, and implements surface creation from a typed borrowed
`Metal.Layer.t`. It must not know about SDL windows, Prismel scenes, or PXUI.

`Ogpu_metal.Native` is the deliberate full-control extension. It may expose a
typed Metal device/resource borrow or record a native Metal pass only when the
caller supplies:

- the resources read and written;
- the pipeline stages and access modes;
- the lifetime of every native borrow;
- whether OGPU or the native pass owns synchronization;
- the resulting resource state visible to subsequent OGPU passes.

The extension must not return naked `nativeint` pointers or allow an encoder to
escape its command-buffer lifetime. It exists so path tracers and future Metal
features can use the complete `metal` binding without bloating portable OGPU.

A future path-tracing library can therefore remain a leaf: it builds/refits
BLAS/TLAS resources, records ray-query compute or render passes through OGPU or
the checked Metal extension, writes an OGPU texture, and hands that texture to
Prismel for composition. It does not need SDL_GPU, a second window, or changes
to PDK's geometry ownership. The later high-level integration must use a typed
GPU-resource lifecycle analogous to `Sketch.run_assets` and an immutable scene
reference to the output texture; raw Metal callbacks and pointers must not be
stored in `Scene.t`.

### `lib/raster2`

Package name: `prismel.raster2`. It is a target-neutral deterministic software
rasterizer over packed RGBA surfaces.

It replaces SDL2_gfx as the authoritative headless/web renderer and supplies a
native software fallback for features whose public semantics cannot yet be
compiled to Metal. It owns:

- packed color/depth/stencil surfaces with checked row pitch;
- lines, antialiased paths, triangles, curves, circles, and polygons;
- even-odd/non-zero fills, clipping, transforms, and documented blend modes;
- image and glyph compositing;
- reusable tessellation/raster scratch storage with bounded growth;
- deterministic readback and PNG-source pixels.

Representation-neutral path flattening and tessellation should be shared with
Prismel's Metal batch preparation so native and software backends consume the
same geometry. Raster2 itself must remain free of Scene, SDL, Metal, and PXUI.

Headless Runtime still initializes SDL3 with dummy video/audio and a software
renderer as required by the target contract. Prismel draws into Raster2's real
framebuffer and Runtime presents/tests that buffer through an SDL3 streaming
surface or texture. Drawing is never replaced with no-ops.

## Runtime and renderer architecture

### Runtime

Runtime retains target selection and platform lifecycle. For native mode it:

1. initializes SDL3 and the extension libraries on the initial domain;
2. creates an SDL3 high-DPI Metal window and `SDL_MetalView`;
3. obtains the `CAMetalLayer` and constructs `ogpu_metal` device/surface state;
4. exposes only abstract `Ogpu.Device.t`, `Ogpu.Surface.t`, logical/drawable
   size facts, and frame acquire/present operations to Prismel;
5. translates SDL3 events into the unchanged Prismel `Event`/`Input` stream;
6. drains GPU completion and deferred-release queues on the initial domain;
7. tears the GPU stack down before destroying the Metal view/window and SDL.

Runtime owns resize, drawable-scale, occlusion, minimize, expose, display move,
surface recreation, and device-loss policy. Scene construction, UI, material,
camera, and mesh semantics remain in Prismel.

For headless and web, Runtime creates no Metal device. Raster2 remains the
authoritative framebuffer. Wap continues to transport bounded complete RGBA
frames and receives the same logical input stream.

### Prismel renderer

Prismel lowers immutable Scene values into a private backend-neutral render
IR containing:

- clip/transform stacks;
- solid and textured triangle batches;
- line/path tessellation;
- glyph atlas quads;
- `Scene3` mesh draws, materials, lights, depth/stencil/cull/blend state;
- canvas/offscreen pass dependencies;
- explicit software-only shader nodes where necessary.

The render IR is not public API and does not contain SDL or Metal values. The
Metal renderer consumes it through OGPU. Raster2 consumes the same prepared
geometry for headless/web. Immutable source identity keys bounded caches for
tessellation, glyphs, images, pipelines, and GPU meshes.

Native 2D, PXUI, text, and 3D all execute through the same Metal command stream.
There is no SDL renderer/OpenGL context sharing, no per-primitive SDL2_gfx call,
and no CPU framebuffer upload masquerading as GPU 3D rendering.

The current functional `Shader3` values cannot be translated automatically to
MSL. Their deterministic software execution remains explicit until Prismel has
a real typed shader IR/compiler. This is not permission to change their result
or silently ignore them. The normal built-in Scene3 material path must be fully
Metal-native before the migration completes.

### Shaders and pipeline assets

MSL source is authoritative and reviewed. Development builds may compile MSL
at runtime for iteration and produce complete diagnostics. Release builds must:

- compile with the pinned full Xcode/Metal Toolchain;
- produce versioned `.metallib` artifacts;
- validate entry points and reflected bind layouts against generated metadata;
- prewarm or ship Metal binary/pipeline archives where measurement justifies
  them;
- record source, compiler, SDK, flags, and artifact hashes;
- perform no steady-state runtime shader compilation.

Ordinary Command Line Tools builds may consume a checked, reproducible shader
artifact and use runtime source compilation only in an explicitly named
development mode. CI must rebuild the artifact with full Xcode and fail on a
dirty generated diff.

## Migration sequence

Each phase starts only after the previous phase's gates pass. Legacy code may
remain reachable only by the comparison harness until the final switch.

### Phase 0: Freeze contracts and evidence

Work:

- identify and record the baseline Git commit and all local modifications;
- generate stable/high-level and legacy/SDL API surface manifests;
- capture deterministic headless/web PNGs, native reference captures, event
  traces, audio state traces, and resource-lifecycle traces;
- add renderer benchmarks for basic, PXUI, canvas, Scene3, and shattered cube;
- record machine, OS, SDK, compiler, Dune, OCaml, SDL, display, scale, power,
  thermal, domain-count, profile, and sample-count facts;
- freeze native image-difference tolerances before viewing new-renderer output;
- amend `AGENTS.md` and architecture specifications with the foundational
  dependency direction proposed here.

Completion gates:

- every stable public module has a checked API manifest;
- every example/sketch used by acceptance builds at the baseline commit;
- every fixture has a command, expected result/hash, and ownership note;
- the performance suite completes five valid release runs per scenario;
- the shattered-cube fixture records exactly 18,278 pieces, 278,368 triangles,
  and 835,104 expanded render vertices, or the plan records and explains a
  baseline-code change before migration starts;
- dependency-direction tests fail on a deliberately injected reverse edge.

### Phase 1: Build and qualify SDL3 bindings

Work:

- implement Clang-based header/API/layout generation;
- implement safe core and extension modules;
- add clean-machine discovery and opam packaging;
- build event, DPI, IME, drop, surface, image, font, and audio conformance apps;
- create a Runtime-shaped SDL3 platform test harness without switching Prismel.

Completion gates:

- SDL3 binding gates S1-S8 below are all green;
- no production binding call uses Ctypes Foreign;
- no test leaks a handle under Address Sanitizer or Instruments Leaks;
- the harness runs 100,000 create/use/destroy cycles where the API permits;
- callback stress produces no foreign-thread OCaml execution;
- clean bootstrap succeeds on a fresh Apple Silicon macOS runner.

### Phase 2: Build and qualify the Metal binding

Work:

- pin the SDK/Xcode/deployment target and generate the Metal API inventory;
- implement the ARC Objective-C++ bridge and safe OCaml modules;
- implement shader-library, resource, command, surface, capture, counter, Metal
  4, and acceleration-structure coverage;
- build FFI and ownership benchmarks before choosing batching boundaries.

Completion gates:

- Metal binding gates M1-M10 below are all green;
- the inventory has no missing/unreviewed in-scope symbols;
- Xcode validation emits zero API, shader, resource, and synchronization errors;
- runtime and offline shader modes render the same conformance fixtures;
- ray-tracing tests pass on M1 and the hardware-ray-tracing lane;
- unsupported capability simulations return typed errors without crashing.

### Phase 3: Implement OGPU and its Metal backend

Work:

- implement a deterministic mock backend for state-machine tests;
- implement OGPU resources, passes, capabilities, validation, and presentation;
- implement the Metal backend and checked native extension;
- add conformance scenes and fault injection.

Completion gates:

- OGPU gates O1-O9 below are all green;
- mock and Metal backends agree on validation/error classifications;
- all supported resource/pass combinations have conformance coverage;
- stale, cross-device, double-destroy, wrong-pass, and unsupported-feature use
  fail deterministically;
- stable resource workloads have bounded live handles and release queues.

### Phase 4: Implement Raster2 and the Prismel renderers

Work:

- capture/port the documented SDL2_gfx behavior into Raster2;
- add the internal render IR and shared tessellation;
- implement software and Metal consumers;
- migrate images, fonts, canvases, audio, native capture, Scene3, PXUI, and web;
- keep the current stack only as an independently selectable comparison build.

Completion gates:

- rendering gates R1-R12 below are all green;
- high-level API manifests are unchanged;
- acceptance examples/sketches have no migration edits;
- deterministic targets are byte-identical where frozen as exact;
- native differences stay within the pre-frozen per-fixture tolerances;
- no stable mesh data is re-uploaded after its first successful upload;
- all renderer and resource caches are bounded and destroy cleanly.

### Phase 5: Atomic switch and legacy deletion

Work:

- switch Runtime and Prismel to SDL3/OGPU/Metal/Raster2;
- remove migration flags and the legacy comparison target;
- delete `tsdl_gfx`, Tsdl compatibility code, OpenGL code, and SDL2 discover
  logic;
- remove SDL2/Tsdl/Ctypes-Foreign dependencies that have no other owner;
- update documentation, packaging, licenses, and release notes.

Completion gates:

- deletion gates D1-D8 and every final gate below are green;
- `rg`, Dune dependency inspection, and `otool -L` find no legacy linkage;
- a fresh opam switch installs and runs without SDL2 present;
- the complete repository validation suite passes twice from a clean build;
- no compatibility flag can select the old backend;
- raw traces may remain ignored, but committed evidence summaries and hashes
  are complete and refer to the final commit.

### Phase 6: Optimization-plan handoff

`OPTIMIZATION_PLAN.md` begins only after Phase 5. The new stack must expose the
measurements and invalidation hooks it needs: CPU frame time, GPU timestamps,
upload bytes, cache hits/misses, draw/pass counts, pending frames, presentation
state, and a Runtime wake mechanism. On-demand scheduling is not smuggled into
this migration, but the new Runtime must not make it harder or require polling.

## Detailed completion gates

These IDs are authoritative. Phase summaries above do not replace them.

### S: SDL3 binding gates

**S1 - Version and provenance**

- Generated code records stable SDL/extension versions, header hashes, generator
  version, compiler, and target triple.
- Runtime rejects a linked SDL library older than the headers used to compile.
- Development/prerelease SDL versions are rejected in release packaging.

**S2 - API and ABI completeness**

- Clang inventory has no `unreviewed` core or used extension symbol.
- Compiled tests compare `sizeof`, alignment, offsets, enum values, bit masks,
  callback calling conventions, and event-union size with the active headers.
- arm64 release and sanitizer builds use the same generated layout manifest.

**S3 - Ownership and error safety**

- Owned/borrowed/interned/null contracts are represented and tested.
- Destroy is idempotent; stale access is rejected in validation builds.
- SDL error text is captured before any subsequent SDL call.
- Failure injection covers every production constructor and decoder.

**S4 - Event fidelity**

- Recorded traces cover ordered key press/release, UTF-8, IME composition,
  mouse/touch/pen motion, button capture, wheel, focus loss, pointer cancel,
  resize, expose, display move, controller, and file drop.
- SDL3 translation produces the frozen Prismel events in logical coordinates.
- `mouse_delta` remains the sum of all logical motion in one application frame.

**S5 - Main-domain and callback safety**

- Every SDL API used by Runtime has a documented thread classification.
- Wrong-domain calls fail under the validation test harness.
- Blocking waits release the runtime lock only when memory remains safe.
- No callback executes OCaml on an SDL/audio/Metal foreign thread.

**S6 - High-DPI and window lifecycle**

- Tests cover Retina and 1x displays, resize, fullscreen, minimize/restore,
  monitor move, drawable-scale change, hidden/headless, and repeated recreation.
- Logical event coordinates and physical drawable sizes match the frozen
  contract with no manual double scaling.

**S7 - Extension parity**

- Image fixtures cover all currently supported formats, alpha, orientation,
  malformed input, failed watched reload, and retained old texture identity.
- Font fixtures cover installed font discovery, empty text, UTF-8, metrics,
  density change, cache mutation, and 256-entry bounded LRU behavior.
- Audio fixtures cover sound/music load, play, loop, volume, fades,
  pause/resume, stop, device failure, dummy headless device, and web mirroring.

**S8 - Packaging**

- Fresh-machine install works through declared opam/conf dependencies.
- Debug/release/static/dynamic discovery paths are tested.
- `dune build @all`, `@doc`, and consumer tests work without local source paths.

### M: Metal binding gates

**M1 - SDK inventory coverage**

- The pinned SDK inventory covers all non-deprecated public Metal.framework and
  required CAMetalLayer symbols.
- Every item is `bound`, `availability-gated`, or explicitly `scope-excluded`.
- Scope exclusions are limited to the frameworks listed out of scope above;
  inconvenience or engineering effort is not an acceptable reason.

**M2 - Objective-C ownership**

- ARC retain/release behavior is verified with deallocation counters and Leaks.
- Autorelease pools remain frame/coarse-operation scoped.
- 100,000 resource create/destroy cycles do not grow live objects or RSS after
  settling.
- Parent teardown, double destroy, stale generation, and cross-device use are
  deterministic.

**M3 - Resource coverage**

- Buffer storage modes, mapped ranges, textures/views, samplers, heaps, sparse
  resources, aliasing, purgeability, residency, and external ownership are
  covered where the device reports support.
- Bounds, offset, stride, row pitch, alignment, format, and overflow failures
  are tested before reaching Objective-C.

**M4 - Pipeline and shader coverage**

- Runtime source, `.metallib`, dynamic library, binary archive/pipeline dataset,
  function constant, linked function, mesh/object, render, compute, and Metal 4
  compiler paths are tested when available.
- Reflected layouts match generated OCaml bind metadata.
- Compile/link errors preserve full diagnostics and labels.

**M5 - Command and synchronization coverage**

- Render, compute, blit, parallel, resource-state, acceleration-structure, ICB,
  and Metal 4 command paths execute conformance work.
- Fence/event/barrier/hazard tests intentionally create and then correct data
  dependencies; validation must catch the broken variants.
- Completion ordering and deferred release remain correct under three frames in
  flight, resize, occlusion, and injected command-buffer errors.

**M6 - Surface and presentation**

- CAMetalLayer acquisition, drawable loss, timeout, pixel format, colorspace,
  HDR capability, resize, scale, occlusion, minimize, restore, and destruction
  are tested for the first frame and at least 10,000 subsequent frames.
- No drawable, command buffer, or texture survives device/window teardown.

**M7 - Ray tracing and advanced shaders**

- BLAS and TLAS build, refit, copy, compact, instancing, triangle, bounding-box,
  curve, motion, function-table, and intersection-query paths run when reported.
- A deterministic compute path tracer/ray-query conformance image executes on
  M1; render-pipeline and hardware-specific cases execute on the M3+ lane.
- Unsupported simulated families reject each path with a typed capability
  error and allocate no partial resource graph.

**M8 - Metal 4 and optional MetalFX**

- Metal 4 argument tables, command allocators/buffers/encoders, compilation,
  pipeline datasets, counters, machine-learning passes, barriers, and relevant
  sparse/resource features are bound and exercised where M1/M3+ report support.
- MetalFX remains weak-linked and every scaler reports exact support/limits.
- Absence of either feature family never prevents basic rendering.

**M9 - Foreign-function performance**

- `tools/bench_metal_ffi` records direct-call and batched-call time,
  minor/major/promoted allocation, and call count in release mode.
- Descriptor conversion and command recording allocate no object per vertex,
  pixel, glyph, UI primitive, or mesh element.
- The selected boundary is based on the benchmark and is no slower than direct
  Objective-C++ by more than the frozen 5% measurement tolerance for equivalent
  work.

**M10 - Tooling and diagnostics**

- Full Xcode CI compiles shaders offline, rebuilds generated assets, runs API
  and shader validation, captures a GPU frame, and exports a counter trace.
- Address Sanitizer, Undefined Behavior Sanitizer, Guard Malloc/Leaks, and
  Thread Sanitizer run on the subsets each tool supports.
- Zero unexplained validation message is allowed in the evidence report.

### O: OGPU gates

**O1 - Backend independence**

- `ogpu` has no SDL, Metal, Runtime, Prismel, Wap, or UI dependency.
- A mock backend implements the public contract without Apple frameworks.
- Dependency-direction CI rejects forbidden imports and links.

**O2 - Handle and state safety**

- Generational, device-owned handles reject stale/cross-device access.
- Command encoders enforce begin/end/pass/present state transitions.
- Destroy while submitted defers release to the correct completion epoch.

**O3 - Descriptor validation**

- Format/usage/sample/storage/alignment/layout combinations have table-driven
  valid and invalid tests.
- Numeric overflow and impossible cardinality fail before backend allocation.
- Labels survive into backend diagnostics and captured frames.

**O4 - Capability truthfulness**

- Capabilities are derived from actual adapter/device queries.
- Mock profiles cover minimum M1, M3+, missing RT, missing MetalFX, and future
  unknown capabilities.
- No API silently falls back to a semantically different feature.

**O5 - Synchronization**

- Every pass declares read/write/stage access and the Metal mapping is tested.
- Safe hazard tracking is the default.
- Native untracked mode requires explicit barriers and has failing negative
  tests for missing declarations.

**O6 - Resource lifetime and bounds**

- Frames in flight, upload/readback rings, release queues, descriptor arenas,
  pipeline caches, and resource caches have explicit capacities.
- Long runs demonstrate a flat live-object/RSS envelope after warm-up.
- Device/surface loss drains or abandons resources in a documented order.

**O7 - Surface contract**

- Acquire/present handles success, timeout, occlusion, stale frame, resize, and
  device loss without hiding state changes.
- Presentation scheduling remains a Runtime concern.

**O8 - Native Metal extension**

- Native passes cannot escape encoder lifetimes or use undeclared resources.
- A custom Metal compute pass and a custom acceleration-structure pass compose
  with ordinary OGPU render passes and validate cleanly.
- The generic OGPU module never exposes a raw pointer.

**O9 - Determinism**

- Command/resource ordering and IDs are stable for a fixed input.
- One-domain and multi-domain preparation emits byte-identical buffer contents
  and ordered command descriptions.
- Work-stealing order cannot affect caches, draw order, shader bindings, or
  capture hashes.

### R: Renderer and application gates

**R1 - Stable API**

- The frozen high-level `.mli`/odoc manifest is byte-identical except for
  approved additive documentation.
- Every example/sketch source is unchanged for migration purposes.
- Low-level SDL breakage is confined to the declared major-version migration.

**R2 - Scene2/PXUI parity**

- All primitives, paths, curves, fills, holes, strokes, clips, transforms,
  blend modes, graph wires, widgets, icons, hover, focus, and selection fixtures
  pass on software and Metal.
- Shared tessellation produces the same topology and stable batch ordering.

**R3 - Scene3 parity**

- Triangles/strips/fans, flat/smooth normals, lights, depth/stencil, culling,
  blending, MSAA, textures, fog, shadows, separate specular, viewports, clipping,
  Canvas/offscreen paths, and captures have frozen fixtures.
- Orientation-aware authored Boolean normals survive terminal packed-piece
  expansion and GPU upload.
- Software-only functional `Shader3` behavior remains explicit and exact.

**R4 - Resource parity**

- Images, fonts, text caches, watched reload, canvases, textures, audio, and
  asset bundles preserve ownership, mutation, on-stop destruction, and failed
  reload semantics.
- Offscreen renderer entries are released before their device/surface.

**R5 - Target parity**

- Native, headless, and web run the same Scene/Frame/Event semantics.
- Headless needs no monitor/GPU/display server and exercises real drawing.
- Web remains bounded and sends the authoritative Raster2 framebuffer.

**R6 - Coordinate and DPI parity**

- Logical points, physical drawable pixels, pointer coordinates, captures,
  view3d scissor/viewport, font point sizes, and browser mapping meet the
  existing high-DPI contract at 1x and Retina scale.

**R7 - Deterministic pixels**

- Headless/web exact fixtures remain byte-identical.
- Native clears, aligned image copies, and exact-format readbacks are exact.
- Rasterized-edge fixtures remain inside tolerances frozen in Phase 0; those
  tolerances cannot be loosened after new output is viewed.

**R8 - Multi-frame correctness**

- Every fixture validates the first, second, 60th, 600th, and post-resize frame.
- No state inheritance, missing primitive, stale drawable, stale cache, or
  first-frame-only success is accepted.

**R9 - Upload and batching structure**

- A stable mesh uploads once and reports zero vertex/index upload bytes for 600
  later frames, including camera-only changes.
- UI draw/FFI call count scales with material/clip batches rather than pixels or
  primitive count.
- Glyph/image atlases and mesh/pipeline caches remain capacity-bounded.

**R10 - Performance non-regression**

- On the same M1 baseline machine, release-profile median wall time, CPU time,
  GPU time, frame time, promoted allocation, and steady/peak RSS are no worse
  than the Phase 0 baseline beyond the 5% median/10% p95 noise envelope.
- A result outside the envelope fails; it cannot be averaged away with an
  unrelated faster scenario.
- Basic, PXUI, Canvas, Scene3, hidden UI, visible UI, and headless/web each have
  independent comparisons.

**R11 - Shattered-cube performance**

- The main benchmark remains `sketches/shattered_cube/main.exe` with 18,278
  pieces, 278,368 triangles, and 835,104 render vertices.
- Cook topology, attributes, ordering, one/multi-domain equality, and cook time
  are unaffected by renderer work.
- The stable native mesh is GPU-resident after one upload; validation reports
  zero client-array or replacement upload on subsequent frames.
- Steady visible/hidden CPU, GPU time, RSS, allocation, draw count, upload bytes,
  cache residency, and frame pacing meet R10.

**R12 - Long-run stability**

- Native, headless, and web run for at least 30 minutes under changing meshes,
  resize, asset reload, canvas creation/destruction, and audio lifecycle.
- Live GPU/SDL/resource/cache counts return to the expected bounded plateau.
- Leaks, validation errors, unbounded queue growth, and increasing RSS fail.

### D: Deletion and release gates

**D1 - Source deletion**

- `tsdl_gfx/`, SDL2 compatibility modules, OpenGL renderer code, SDL2 discover
  scripts, and migration-only comparison code are deleted.

**D2 - Textual absence**

The following finds no production source/build/package reference, excluding
historical migration documents and fixture labels:

```sh
rg -n 'Tsdl|tsdl|SDL2|SDL2_gfx|conf-sdl2|OpenGL|gl[A-Z]' \
  dune-project prismel.opam lib test examples sketches tools
```

Every remaining match must be listed and justified in the evidence report.

**D3 - Link absence**

- `dune describe external-lib-deps` lists no Tsdl/SDL2/OpenGL package.
- `otool -L` on every native executable/library lists no SDL2, SDL2_image,
  SDL2_ttf, SDL2_mixer, SDL2_gfx, or OpenGL framework.
- SDL3, Metal, QuartzCore, and used extension linkage matches the package map.

**D4 - Clean dependency install**

- A fresh local switch installs with no SDL2 formula/library present.
- `opam install . --deps-only --with-test --with-doc` declares every needed
  SDL3/Metal build prerequisite.

**D5 - License and provenance**

- Every copied/generated file has origin, license, generator, and modification
  provenance.
- No code from an unlicensed candidate binding is copied.
- MIT/zlib/ISC and Apple tool/artifact obligations are documented.

**D6 - Documentation**

- `AGENTS.md`, `specification/backend.md`, `specification/api.md`, relevant 3D,
  shader, performance, and packaging specifications reflect the final stack.
- Public low-level migration and full-control Metal extension are documented.
- No document still describes OpenGL or SDL2 as the active backend.

**D7 - Full validation**

From a clean build, all commands below pass twice with no generated diff:

```sh
dune build @all
dune runtest
PRISMEL_RENDER_TARGET=headless dune exec examples/basic/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/particles/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/noise/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/canvas/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/audio/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/pxui/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/generative/main.exe
dune build @doc
```

The release evidence also includes finite native runs of the same examples,
web protocol/integration tests, all GPU conformance executables, the shattered
cube benchmark, sanitizer jobs, and all three required OS/GPU matrix lanes.

**D8 - No legacy fallback**

- No environment variable, hidden flag, dynamically loaded module, or build
  profile can select Tsdl, SDL2, SDL2_gfx, or OpenGL.
- A Metal capability failure is handled by an explicit supported software path
  or a typed startup error; it never resurrects legacy code.

## Performance measurement policy

Performance is a completion property, not an informal observation.

Every reported run records:

- Git commit and dirty status;
- exact command, profile, environment, and frame/sample count;
- machine model, CPU/GPU family, RAM, OS, SDK/Xcode, display mode/scale/refresh,
  power source, thermal state, and domain count;
- wall, user, system, main-thread CPU, GPU duration/utilization, frame-time
  median/p95/p99, minor/major/promoted allocation, peak/steady RSS;
- draw/pass/encoder counts, FFI calls, uploaded/readback bytes, cache hit/miss,
  live resources, release-queue depth, and frames in flight.

Use at least five warmed 30-second samples per interactive scenario and report
median plus dispersion. Run baseline and candidate interleaved when possible.
Do not compare dev and release profiles, different display resolutions, changed
MSAA, different geometry cardinality, or a cached cook against a fresh cook.

The 5% median and 10% p95 allowances account only for measured run noise. They
are not performance budget increases. Any workload whose confidence intervals
still show a regression fails. Structural gates such as upload count, cache
capacity, handle count, and byte identity have no tolerance.

Required tools/artifacts include:

- `tools/bench_sdl3` for event/window/surface/audio FFI and allocation;
- `tools/bench_metal_ffi` for direct/batched native calls;
- `tools/bench_ogpu` for resource/command/pass overhead;
- `tools/bench_renderer` for 2D, text, PXUI, Canvas, and Scene3;
- the existing Boolean/dense geometry tools and shattered-cube executable;
- Instruments Time Profiler, Allocations/Leaks, Metal System Trace, GPU capture,
  and the Xcode Metal validation layers.

## Evidence and sign-off

Each gate produces a row in `specification/evidence/gpu_migration.md` with:

| Field | Required value |
| --- | --- |
| Gate | Stable ID such as `M7` or `R11` |
| Commit | Full Git SHA and dirty status |
| Command | Reproducible invocation |
| Environment | Machine/toolchain/profile facts |
| Result | Pass/fail and measured values |
| Artifacts | Hashes and paths for reports/images/traces |
| Reviewer | Human sign-off and date |

Large Instruments traces stay under an ignored artifact directory, but their
hashes, tool versions, summaries, and reproduction commands are committed.
Golden images and compact machine-readable conformance fixtures belong in the
test tree when redistribution permits.

Final sign-off requires all of the following people/roles to approve the same
commit:

- binding/FFI ownership reviewer;
- renderer/OGPU synchronization reviewer;
- public API and target-parity reviewer;
- performance reviewer who reruns the baseline comparison.

The author of a subsystem may not be its only final reviewer.

## Risks and limitations

### A complete binding is a maintenance commitment

Apple and SDL add APIs over time. The inventory generators and CI diff are
mandatory so coverage drift becomes visible. Supporting a new SDK requires an
intentional inventory review; generated compilation alone is insufficient.

### Full Metal access is not full hardware availability

M1 currently reports Metal 4 and ray tracing in the local probe, but hardware
acceleration and newer motion/sparse/mesh features vary by Apple GPU family.
Capabilities must drive paths. A path tracer can use Metal acceleration
structures on supported devices, but performance and supported shader stages
will differ materially between M1 and M3+.

### OCaml GC does not own GPU completion

Finalizers cannot safely decide when a submitted Metal resource is dead. OGPU
must use explicit destruction plus submission epochs and bounded deferred
release. Letting GC be the primary owner would create nondeterministic memory
spikes and use-after-free risk.

### Runtime shader compilation is not a release pipeline

It is a useful development fallback and is proven feasible on the current
Command Line Tools installation. Release builds still require full Xcode,
offline `.metallib` generation, validation, and artifact provenance.

### Native and deterministic rasterization have different authorities

Metal is authoritative for native performance. Raster2 is authoritative for
headless/web determinism. Shared tessellation and fixed fixtures prevent them
from becoming unrelated renderers, but edge antialiasing cannot be assumed
bit-identical across GPU families. Native tolerances must be frozen before the
new output is seen.

### This does not itself fix idle scheduling

The migration removes per-frame client-array submission and SDL2_gfx overhead,
and it creates the right instrumentation and wake boundaries. Static sketches
will still redraw according to the current scheduler until the on-demand work
in `OPTIMIZATION_PLAN.md` is implemented. The GPU migration must not claim the
near-zero idle target by itself.

## Research references

- Blade: <https://github.com/kvark/blade>
- SDL3 language bindings: <https://wiki.libsdl.org/SDL3/LanguageBindings>
- SDL3 versioning: <https://wiki.libsdl.org/SDL3/README-versions>
- SDL3 Metal view: <https://wiki.libsdl.org/SDL3/SDL_Metal_CreateView>
- SDL3 main-thread query: <https://wiki.libsdl.org/SDL3/SDL_IsMainThread>
- Apple Metal documentation: <https://developer.apple.com/documentation/metal>
- Apple Metal feature tables: <https://developer.apple.com/metal/feature-sets/>
- Apple ray tracing: <https://developer.apple.com/documentation/metal/ray-tracing-with-acceleration-structures>
- Apple shader libraries: <https://developer.apple.com/documentation/metal/shader-libraries>
- OCaml Metal reference: <https://github.com/lukstafi/ocaml-metal>
- SDL3 OCaml research candidate: <https://github.com/sanette/ocaml-sdl3>
- SDL3 OCaml research candidate: <https://github.com/bluddy/ocaml-sdl3>
- SDL3 OCaml research candidate: <https://github.com/fccm2/ocaml-sdl3>

## Final definition of done

The GPU infrastructure is complete only when:

1. Gates S1-S8, M1-M10, O1-O9, R1-R12, and D1-D8 all pass on one final commit.
2. The final evidence file contains no failure, waiver, skipped supported
   capability, unexplained validation message, missing artifact, or `TODO`.
3. The high-level API manifest and unchanged example/sketch build gate pass.
4. Headless/web deterministic fixtures and native frozen-tolerance fixtures
   pass across the required hardware matrix.
5. The performance suite proves no per-scenario regression and the stable
   shattered-cube mesh uploads exactly once.
6. Fresh-machine packaging, full Xcode shaders, sanitizers, leaks, 30-minute
   stability, and ray-tracing lanes pass.
7. Tsdl, SDL2, SDL2_gfx, OpenGL, compatibility flags, and legacy code are absent
   from source, dependencies, and linked binaries.
8. Architecture, API, backend, shader, performance, packaging, license, and
   migration documentation describe the code actually shipped.
9. The same final commit receives all four independent sign-offs.

Only then may the project mark this plan complete and begin the implementation
stages in `OPTIMIZATION_PLAN.md`.
