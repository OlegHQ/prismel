# Prismel

> Prismel is under active development. APIs and qualification tooling may
> change while the native GPU migration is completed.

Prismel is a functional creative-coding framework for OCaml. It combines pure
scene construction, immutable sketch state, native Metal rendering, typed
input and media resources, a UI toolkit, and production-oriented procedural
geometry.

Prismel currently supports one platform stack: macOS on Apple Silicon, SDL3
for the window/event/media lifecycle, and Prismel's custom OGPU/Metal renderer.
Metal unavailability is a typed startup error. Applications do not select a
different renderer.

## Highlights

- `Sketch`, `Frame`, and immutable `Scene` values for ordinary applications.
- Native 2D and 3D rendering through typed OGPU commands and Metal resources.
- Logical-point coordinates with explicit Retina drawable dimensions.
- Images, fonts, text, audio, canvases, capture, and asset ownership helpers.
- PXUI controls and graph/inspector adapters for procedural tools.
- Deterministic random, noise, fixed-clock, and multicore preparation APIs.
- PDK packed geometry, functional Geom adapters, and immutable Procedural SOPs.
- Bounded GPU resource, retained-plan, mesh, and text caches.

## Platform requirements

- An Apple Silicon Mac with Metal support.
- OCaml 5.2 or newer and Dune 3.17 or newer.
- opam and, optionally, direnv.
- SDL3, SDL3_image, SDL3_ttf, and SDL3_mixer development packages.
- The macOS SDK and standard Apple frameworks supplied by the operating-system
  developer tools.

The runtime compiles its small built-in MSL sources at run time. Building
Prismel does not require Xcode, the offline Metal compiler, `.air` files, or a
prebuilt `.metallib` pipeline.

With Homebrew:

```sh
brew install opam direnv sdl3 sdl3_image sdl3_ttf sdl3_mixer pkg-config
```

## Build from source

```sh
git clone https://github.com/nexo-tech/prismel.git
cd prismel

opam init
opam switch create . 5.3.0 --no-install
opam pin add --no-action --yes --recursive ./packaging
direnv allow

opam install . --deps-only --with-test --with-doc
dune build @all
dune runtest
dune build @doc
```

Without direnv, activate the local switch in each shell:

```sh
eval "$(opam env --switch=. --set-switch)"
```

The checked-in `.envrc` only activates the repository-local opam switch and
loads non-secret defaults from `.env` when present. It does not choose a
renderer.

## Five-minute sketch

```ocaml
open Prismel

type model = { phase : float }

let init _frame = { phase = 0. }

let update model (frame : Frame.t) =
  { phase = model.phase +. frame.dt }

let view model (frame : Frame.t) =
  let radius = 42 + int_of_float (10. *. sin (2. *. model.phase)) in
  Scene.[
    clear (Color.rgb 20 22 28);
    circle
      ~at:(frame.width / 2, frame.height / 2)
      ~radius
      ~fill:(Color.rgb 90 170 240)
      ();
    text ~at:(12, 12) (Printf.sprintf "frame %d" frame.count);
  ]

let () =
  ignore
    (Sketch.run_state
       ~config:{ Sketch.default_config with
         width = 640;
         height = 360;
         title = "My Prismel sketch";
       }
       ~init ~update ~view ())
```

Give each executable its own Dune stanza:

```lisp
(executable
 (name main)
 (libraries prismel))
```

Then run it natively:

```sh
dune exec ./main.exe
```

Resource-owning models release their images, fonts, canvases, and audio in
`Sketch.run_state ~on_stop`, while SDL3 and Metal are still alive.
`Sketch.run_assets` is the shorter path for ordinary borrowed assets.

## Examples

Every directory under `examples/` is a self-contained executable. Useful
starting points include:

```sh
dune exec examples/basic/main.exe
dune exec examples/drawing/main.exe
dune exec examples/audio/main.exe
dune exec examples/particles/main.exe
dune exec examples/noise/main.exe
dune exec examples/generative/main.exe
dune exec examples/pxui/main.exe
dune exec examples/procedural_modeling/main.exe
dune exec examples/boolean/main.exe
```

Examples and sketches intended for automation must provide an explicit finite
native smoke path; the runtime does not impose an implicit frame limit.

## Architecture

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
```

- `prismel` owns public application semantics, pure scenes, resources, and
  renderer behavior.
- `runtime` owns the initial-domain SDL3 lifecycle, Metal view, drawable
  presentation, and event translation.
- `ogpu` is the checked renderer-facing command vocabulary.
- `ogpu_metal` translates OGPU commands to the safe Metal library.
- `metal` owns typed Objective-C++ calls, native validation, ownership, and
  command-completion retention.
- `pdk` is the sole packed topology/geometry kernel; `geom` and `procedural`
  adapt that core rather than duplicating it.

No public Prismel type exposes an SDL3 or Metal handle. All window, input,
resource, and presentation operations remain on the initial OCaml domain.
Pure CPU work may use the shared Domainslib pool and joins before native
command submission.

## Repository layout

```text
lib/prismel/          public creative-coding API
lib/runtime/          SDL3 + Metal native lifecycle
lib/sdl3*/            SDL3 and media bindings
lib/metal/            safe/raw Metal API and OCaml/Dune generation
lib/ogpu/             renderer command interface
lib/ogpu_metal/       Metal implementation of OGPU
lib/pdk/              packed geometry/topology core
lib/geom/             functional geometry adapters
lib/procedural/       immutable SOP graphs
lib/pxui*/            UI and graph presentation
lib/sketch*/          reusable sketch environments
examples/             self-contained examples
sketches/             experimental native applications
test/                 automated tests
specification/        architecture and behavioral specifications
```

The root `prismel.opam` file is generated from `dune-project`. SDL dependency
probes live as the small local opam packages under `packaging/`; application
libraries remain under `lib/` and build through Dune.

## Coordinates and rendering

`Frame.width`, `Frame.height`, `Scene` geometry, input positions, and PXUI
layout use logical points. `Frame.drawable_size` exposes physical Metal
drawable pixels, and `Frame.pixel_scale` marks the conversion boundary. Do not
manually scale ordinary drawing or input coordinates.

Scenes are pure values. Rendering lowers them to checked native commands only
at `Scene.render`, `Sketch`, or `Low.App`. Image generations upload when their
content changes; immutable mesh and retained command data use bounded native
caches. Submitted resources stay alive until Metal completion.

`Scene3` provides cameras, transforms, depth/stencil, lighting, culling,
blending, MSAA, textures, shadows, and the supported typed shader surface.
Unsupported programmable features return typed errors instead of changing the
rendering path.

## Geometry and procedural modeling

The geometry stack has one authoritative core:

```text
procedural ──> geom ──> pdk ──> prismel
     └────────────────> pdk
```

PDK owns packed topology, reverse incidence, spatial acceleration, attributes,
groups, and high-density modeling algorithms. Geom supplies ergonomic points,
curves, polygons, fields, and adapters. Procedural wraps the same operations in
immutable cookable graphs with bounded caches and explicit cancellation.

See [the PDK specification](specification/pdk.md), [procedural
specification](specification/procedural.md), and [modeling-kernel
requirements](specification/modeling-kernels.md) for production guarantees.

## Development and qualification

Before handing off an ordinary change:

```sh
dune build @all
dune runtest
dune build @doc
```

Native integration tests must arrange their own termination. Performance work
records wall time, allocation, memory, input size, profile, machine, and domain
count; deterministic multicore paths compare ordered results exactly.

`NEW_GPU_STUFF.md` is the active native migration and qualification plan.
Machine-specific evidence lives under
`specification/evidence/gpu_migration/`. A feature is complete only when its
required correctness, ownership, conformance, stability, performance, and
packaging gates pass from a clean committed source tree.

Metal binding expansion uses hybrid OCaml/Dune generation. The generator owns
mechanical declarations and typed direct selector calls; the safe API,
lifetimes, validation, and behavior remain handwritten and tested. GPU binding
generation does not use Python glue.

## Documentation

- [Public API](specification/api.md)
- [Native backend](specification/backend.md)
- [Graphics](specification/graphics.md)
- [3D rendering](specification/3d.md)
- [Resources](specification/assets.md)
- [Input and events](specification/input.md)
- [SDL3 bindings](specification/sdl3.md)
- [Metal bindings](specification/metal.md)
- [Packaging](specification/packaging.md)

Prismel is licensed under the MIT License. External SDL3 libraries and Apple
platform frameworks retain their own licenses and terms; see
[licenses](specification/licenses.md).
