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
│   └── pxui/              # UI toolkit; depends on prismel
├── examples/
│   ├── basic/             # Minimal Prismel application
│   ├── audio/             # Synthesized keyboard and sample playback
│   ├── canvas/            # Paths, clipping, pixels and PNG capture
│   ├── generative/        # Generative art demo
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
opam switch create . 5.3.0

# Let .envrc activate the local switch whenever you enter the repository
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
dune exec examples/generative/main.exe
dune exec examples/noise/main.exe
dune exec examples/particles/main.exe
dune exec examples/pxui/main.exe
```

If you do not use direnv, activate the switch manually in each new shell:

```bash
eval "$(opam env --switch=. --set-switch)"
```

### Headless mode

Set `HEADLESS=1` (also accepts `true`, `yes`, or `on`) to select SDL's dummy
video driver and software renderer. This executes real drawing code without a
display server, monitor, GPU, or OpenGL:

```bash
HEADLESS=1 dune exec examples/basic/main.exe
```

The bundled examples exit automatically after a few frames when headless, which
makes them useful as CI smoke tests. Applications control their own lifetime;
Prismel does not otherwise impose a headless frame limit.

### PXUI

`pxui` is a separate library that depends on `prismel`. Its normal path is a
declarative value stored in the sketch model:

```ocaml
let ui =
  Pxui.create ()
  |> Pxui.label ~text:"Controls"
  |> Pxui.toggle ~name:"animate" ~label:"Animate" ~value:true
  |> Pxui.slider ~name:"radius" ~label:"Radius"
       ~min:10. ~max:120. ~value:48.
  |> Pxui.text_field ~name:"title" ~label:"Title" ~value:"Orbit"

let update model frame =
  let ui, changes = Pxui.update model.ui frame.events in
  { model with ui }

let view model _frame =
  Scene.[clear Color.black; group (Pxui.scene model.ui)]
```

`Pxui.update` does not mutate its input and returns ordered named changes.
Text fields consume SDL text-input and IME-composition events. `Pxui.encode` /
`decode` provide pure, typed settings round trips; `save` / `load` persist the
same versioned format. Choice, dual-handle range, and 2D controls use the same
builder/update/query pattern.

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
`Canvas.capture` and `Canvas.save_screen_png` preserve the framebuffer's native
pixel dimensions, so an `800 × 600` logical Retina window commonly produces a
`1600 × 1200` capture. Ordinary `Canvas.create` dimensions remain explicit
canvas pixels. Release owned resources with `Sketch.run_state ~on_stop`. See
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

See [`examples/basic`](./examples/basic), [`examples/generative`](./examples/generative),
and [`examples/pxui`](./examples/pxui) for complete projects.

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
