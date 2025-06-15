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

**In Development:**
- 🔄 Event system completion
- 🔄 Image loading and manipulation
- 🔄 Font rendering and typography
- 🔄 Sound system integration
- 🔄 Advanced graphics features

**Planned:**
- 📋 Comprehensive documentation
- 📋 More drawing primitives and utilities
- 📋 Performance optimizations
- 📋 Extended examples and tutorials
- 📋 Package distribution via OPAM

## 📁 Project Structure

```
├── lib/                    # Core framework modules
│   ├── app.ml             # Application lifecycle and main loop
│   ├── window.ml          # Window management
│   ├── graphics.ml        # 2D drawing primitives
│   ├── color.ml           # Color utilities and constants
│   ├── math.ml            # Mathematical utilities
│   ├── vec2.ml            # 2D vector operations
│   ├── mat3.ml            # 3x3 transformation matrices
│   ├── time.ml            # Timing and frame rate utilities
│   ├── event.ml           # Event handling system
│   ├── input.ml           # Input device management
│   ├── image.ml           # Image loading and manipulation
│   └── font.ml            # Typography and text rendering
├── bin/                   # Example applications
│   └── main.ml            # Generative art demo
├── test/                  # Unit tests
├── specification/         # Detailed module specifications
├── tsdl_gfx/             # SDL2_gfx bindings
└── examples/             # Additional examples (planned)
```

## 🚀 Quick Start

### Prerequisites

- OCaml 4.14+ or 5.x
- Dune 3.17+
- SDL2 development libraries
- SDL2_image, SDL2_ttf, SDL2_mixer (optional, for extended features)

### Installation

```bash
# Clone the repository
git clone https://github.com/nexo-tech/prismel.git
cd prismel

# Install dependencies
opam install --deps-only .

# Build the project
dune build

# Run the demo
dune exec prismel
```

### Basic Usage

```ocaml
(* Define your application state *)
type state = {
  counter: int;
  color_phase: float;
}

(* Initialize state *)
let init () = { counter = 0; color_phase = 0.0 }

(* Update state each frame *)
let update state dt = {
  counter = state.counter + 1;
  color_phase = state.color_phase +. dt;
}

(* Draw your graphics *)
let draw state =
  Graphics.clear Color.black;
  let (w, h) = App.Utils.window_size () in
  let center_x, center_y = w / 2, h / 2 in
  
  (* Animated circle *)
  let radius = int_of_float (50.0 +. 20.0 *. sin state.color_phase) in
  let color = Color.hsv (state.color_phase *. 50.0) 1.0 1.0 in
  Graphics.circle ~center:(center_x, center_y) ~radius ~filled:true ~color ()

(* Handle input events *)
let handle_event state event = state

(* Run the application *)
let () =
  let config = { Window.default_config with 
    width = 800; height = 600; title = "My Graphics App" 
  } in
  App.run ~config ~init ~update ~draw ~on_event:handle_event ()
```

## 📚 Module Documentation

### Core Modules

- **`App`**: Application lifecycle management and main loop coordination
- **`Window`**: Window creation, configuration, and property management  
- **`Graphics`**: 2D drawing primitives and rendering state management
- **`Color`**: Color representation and manipulation utilities
- **`Math`**: Mathematical constants and utility functions
- **`Vec2`**: 2D vector operations for geometric calculations
- **`Mat3`**: 3x3 matrices for 2D transformations

### Input & Events

- **`Event`**: Event type definitions and dispatch system
- **`Input`**: Keyboard and mouse input state management
- **`Time`**: Timing utilities and frame rate management

### Media (In Development)

- **`Image`**: Image loading, manipulation, and rendering
- **`Font`**: Font loading and text rendering
- **`Sound`**: Audio playback and management (planned)

## 🎨 Graphics API Preview

```ocaml
(* Basic shapes *)
Graphics.circle ~center:(100, 100) ~radius:50 ~filled:true ~color:Color.red ();;
Graphics.rect ~pos:(200, 200) ~w:100 ~h:50 ~filled:false ~color:Color.blue ();;
Graphics.line ~x1:0 ~y1:0 ~x2:300 ~y2:300 ~color:Color.green ();;

(* Transformations *)
Graphics.push_matrix ();;
Graphics.translate ~dx:100 ~dy:100;;
Graphics.rotate ~angle:(Float.pi /. 4.0);;
Graphics.circle ~center:(0, 0) ~radius:30 ~filled:true ~color:Color.yellow ();;
Graphics.pop_matrix ();;

(* Color utilities *)
let red = Color.rgb 255 0 0;;
let transparent_blue = Color.rgba 0 0 255 128;;
let bright_green = Color.hsv 120.0 1.0 1.0;;
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
- 🎯 Image loading and manipulation
- 🎯 Font rendering improvements  
- 🎯 Sound system implementation
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
- [Examples](./bin/main.ml) - Working demonstration code
- [API Documentation](https://nexo.sh/prismel) - Generated docs (when available)

## 🐛 Known Issues

- Image loading not yet implemented
- Font rendering incomplete  
- Sound system placeholder only
- Limited error handling in some modules
- Performance not yet optimized

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
