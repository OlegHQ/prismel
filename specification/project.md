# Project architecture

Prismel is a functional creative-coding framework for interactive native
applications on Apple Silicon. The ordinary user path is `Sketch`, immutable
model updates, `Frame` facts, and pure `Scene` construction.

## Public layers

- `Sketch` owns application configuration and the model lifecycle.
- `Frame` supplies logical size, drawable size, time, ordered events, and input
  facts for one application step.
- `Scene` and `Scene3` are pure descriptions. Rendering is their effect
  boundary, not a side effect of construction.
- `Image`, `Font`, `Canvas`, `Texture`, and `Audio` expose owned or explicitly
  borrowed resources with deterministic teardown.
- `Low.App` and `Low.Graphics` preserve the immediate-mode compatibility path
  while recording into the same native scene execution.
- `Pxui` and the graph/inspector adapters remain sibling libraries above the
  public Prismel API.
- `Pdk` owns packed geometry/topology; `Geom` and `Procedural` adapt it.

## Native foundation

```text
prismel -> runtime -> SDL3 lifecycle and Metal view
prismel -> ogpu -> ogpu_metal -> metal
```

Runtime owns window creation, event translation, drawable acquisition,
presentation, and ordered teardown on the initial OCaml domain. `ogpu` owns the
checked renderer command vocabulary. `ogpu_metal` maps that vocabulary to the
safe `metal` library. Public application code never receives a raw SDL3,
Objective-C, or Metal handle.

SDL3_image decodes image formats, SDL3_ttf rasterizes fonts, and SDL3_mixer
owns playback. Decode/upload and every media-cache mutation join the initial
domain before crossing their native boundaries.

## Functional contract

User state is threaded through `Sketch.run_state`; global mutable application
models are not part of the design. Constructors and transformations return new
values. Local mutation is permitted inside measured kernels and native command
preparation when ownership is exclusive and does not escape.

Coordinates, input positions, layout, and configured window dimensions use
logical points. The runtime exposes physical drawable pixels separately and
performs the native scale conversion once.

## Dependency contract

Foundational libraries do not depend upward:

- `sdl3` imports no Metal, OGPU, Runtime, Prismel, or PXUI module;
- `metal` imports no SDL3, OGPU, Runtime, Prismel, or PXUI module;
- `ogpu` imports no SDL3, Metal, Runtime, Prismel, or PXUI module;
- `ogpu_metal` imports only `ogpu` and `metal`;
- Runtime alone combines SDL3 with `ogpu_metal`;
- Prismel records through `ogpu` without exposing native values.

The release link audit verifies these edges and rejects undeclared native
renderer dependencies.

## Build and generation

Libraries live under `lib/<name>/` with Dune files and public modules with
interfaces. The root package metadata is generated from `dune-project`.
SDL3 dependency probes live under `packaging/`; they are not alternate library
layouts.

Metal binding generation is OCaml/Dune native. It generates mechanical enum,
external, availability, and typed direct-call layers from one declarative plan.
Ownership, validation, safe APIs, complex encoders, and behavior remain
handwritten. Built-in native shaders compile from source at run time, so the
ordinary build has no offline shader-artifact pipeline.

## Completion standard

Architecture claims require dependency-direction, build, focused behavior,
ownership, multi-frame, performance, stability, packaging, and documentation
evidence appropriate to the change. `NEW_GPU_STUFF.md` defines the active GPU
migration gates; evidence records the exact committed source and environment.
