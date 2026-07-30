# Prismel sketch API

Status: accepted direction for the public high-level API.

## Goal

Prismel should make the first visual result take minutes and keep larger
sketches understandable. A sketch author should spend their attention on the
idea, not lifecycle plumbing, SDL resources, or synchronizing input state.

The high-level API is functional:

- application state is an ordinary immutable OCaml value;
- `update` returns the next state;
- `view` returns a pure `Scene.t`;
- scenes are data and can be composed, mapped, tested, cached, and rendered;
- effects and mutable renderer state stay behind `Sketch.run` and
  `Scene.render`.

Mutable backend modules live under the explicit `Low` escape hatch. New
sketches start with `Sketch`; direct rendering experiments use `Preview`.

## Design evidence

Productive creative-coding systems converge on a few ideas:

- Processing and p5.js automatically call setup/draw and expose current input,
  time, and canvas dimensions.
- openFrameworks uses a predictable setup/update/draw/event lifecycle.
- Raylib keeps the drawing vocabulary flat and concrete.
- Lisp-family workflows favor small expressions, composable data, and fast
  evaluation over object construction and callback ceremony.

Prismel retains those advantages without importing global mutable user state.
The frame environment is an explicit value and the picture is a pure value.

Primary references used in this design:

- [p5.js reference](https://p5js.org/reference/)
- [Processing `draw()` lifecycle](https://processing.org/reference/draw_)
- [openFrameworks `ofBaseApp`](https://openframeworks.cc/documentation/application/ofBaseApp/)
- [Raylib API cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html)
- [Quil, a Clojure sketch system](https://github.com/quil/quil)
- [The Elm Architecture](https://guide.elm-lang.org/architecture/)
- [OCaml parallel programming](https://ocaml.org/manual/5.3/parallelism.html)
- [Domainslib](https://ocaml.org/p/domainslib/latest)

## Five-minute sketch

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

No model, update callback, event callback, renderer, or trailing application
configuration is required.

## Stateful sketch

```ocaml
open Prismel

type model = { x : float }

let update model frame =
  let direction =
    if Frame.key_down Input.ArrowRight frame then 1.
    else if Frame.key_down Input.ArrowLeft frame then -1.
    else 0.
  in
  { x = model.x +. (direction *. 200. *. frame.dt) }

let view model frame =
  Scene.[
    clear Color.black;
    circle ~at:(int_of_float model.x, frame.height / 2)
      ~radius:24 ~fill:Color.yellow ();
  ]

let () =
  Sketch.run_state
    ~init:(fun _frame -> { x = 100. })
    ~update ~view ()
```

## Modules and responsibility

### `Frame`

An immutable snapshot passed to sketch functions:

- logical `width`, `height`, and `size`;
- native-pixel `drawable_width`, `drawable_height`, and `drawable_size`;
- `pixel_scale`, the native pixels per logical point on each axis;
- `time`, `dt`, `fps`, and monotonically increasing `count`;
- `mouse` and `mouse_delta`;
- current `keys` and `mouse_buttons`;
- all ordered `events` received since the previous update.

Helpers such as `Frame.key_down` and `Frame.mouse_down` keep common queries
readable. Events remain available for edge-triggered behavior, including
committed UTF-8 text and in-progress IME composition.

`Frame.mouse`, all mouse event coordinates, and scene positions use the same
logical-point space as `width` and `height`. `mouse_delta` is the sum of every
pointer motion received during that application frame; it is zero in the next
frame unless new motion arrives. Sketches normally ignore `pixel_scale`.
Framebuffer inspection, native-resolution capture, and deliberately
pixel-density-aware effects use the `drawable_*` fields instead.

### `Scene`

`Scene.t` is a list-like declarative picture. Constructors cover:

- background and clear;
- point, line, thick line;
- rectangle, rounded rectangle, circle, ellipse, triangle;
- polygon and polyline;
- arc, pie, and Bezier curve;
- installed system UI text, fixed bitmap debug text, loaded-font text, and images;
- nested translate, rotate, scale, and general groups.

`Scene.text ?size` resolves an installed platform UI font and treats `size` as
a logical point size. `PRISMEL_UI_FONT` overrides the platform font search.
`Scene.debug_text` is the explicit fixed 8×8 SDL2_gfx diagnostic face. System
and loaded fonts rasterize and cache at the active renderer density while
keeping their layout dimensions logical.

Loaded-font text supports explicit newlines, logical-width word wrapping, and
left/center/right alignment directly through `Scene.font_text`. Rasterized
textures are cached per renderer and native raster size using the complete
visual key (font state, content, mode/color, wrap, and alignment). Mutating font
style, hinting, or kerning invalidates its cache. Offscreen renderers receive
separate textures and release those textures before renderer destruction.
The automatic scene renderer retains at most its 256 most-recent text textures
per renderer, keeping dynamic labels bounded. Explicit `Font.cached_text`
borrows remain stable until cache clear or font destruction. Empty scene text
draws nothing.
Each renderer-local cache uses a 256-entry LRU bound, preventing animated
counters and PXUI values from retaining unbounded textures. Empty text is valid
and produces no visible geometry.

Every primitive accepts direct styling (`fill`, `stroke`, `stroke_width`) rather
than relying on hidden user-visible state. Transform nodes scope their changes
to their children. Primitive geometry is transformed before rasterization, so
rotation and non-uniform scale affect complete outlines rather than only anchor
points.

Coordinates are integer logical points in the initial API because the current
SDL2_gfx backend rasterizes integer coordinates. The origin is the logical
window's top-left, with positive Y downward. SDL maps that renderer space to
the native framebuffer and maps mouse events back through the same transform,
so Retina backing scale never changes layout or hit testing. Model
calculations should use floats and convert at the scene boundary. A future
renderer-independent geometry pass may promote scene coordinates to floats
without changing the lifecycle model.

### `PXUI`

PXUI is a sibling library that depends on Prismel and consumes ordinary
logical `Event.t` positions. Its default visual language is a dark translucent
panel with rounded controls, a bright cyan-green accent, subtle highlight
lines, and visible hover/pressed/drag states. `Pxui.create` accepts `?theme`,
`?font`, and logical `?font_size`; the default typography is `Scene.text`.

Pointer behavior is captured and deterministic:

- buttons, toggles, and choices arm on left press and commit only on release
  inside that same control;
- sliders, the selected range handle, and XY pads capture from press through
  release, update on each intervening pointer move even outside their bounds,
  and clamp to the declared ranges;
- `WindowFocusLost` cancels capture, text focus, and composition;
- `Pxui.update` preserves event order when returning named changes.

### `Sketch`

`Sketch.default_config` uses realtime wall-clock timing. Setting
`clock = Sketch.Fixed dt` makes `Frame.dt`, `Frame.time`, and `Frame.fps`
deterministic functions of the positive timestep and frame count. This mode is
intended for repeatable simulation, tests, and offline frame export.

- `Sketch.run view` is the zero-state path.
- `Sketch.run_state ~init ~update ~view ()` is the functional model path.
- `Sketch.export` and `Sketch.export_state` render deterministic numbered PNG
  sequences using a fixed clock and no realtime frame limiter.
- width, height, title, FPS and window behavior are optional configuration.
- cleanup is exception-safe.
- `Sketch.quit ()` requests graceful termination.

### `Parallel`

Prismel targets OCaml 5 and may create a reusable Domainslib work-stealing pool
for CPU-heavy pure work. This is parallelism, not a second render loop.

Good parallel work:

- particle and physics updates over independent chunks;
- procedural geometry, noise fields, and generative systems;
- decoding or transforming CPU-side image/audio data;
- spatial indexing and other immutable data transformations.

Main-domain-only work:

- every `Scene.render` and `Graphics` call;
- SDL window, renderer, texture, font, input, and event operations;
- mutation of shared sketch state.

`Parallel.map`, `Parallel.for_`, and `Parallel.both` submit coarse tasks to a
pool owned by `Sketch.run`. Results are joined before `view`, so the functional
`model -> frame -> model` contract stays deterministic. Small inputs should
remain sequential because scheduling can cost more than the work. The pool
defaults to the runtime's recommended domain count and never spawns one domain
per item.

Outside `Sketch.run`, the same operations safely fall back to sequential
execution unless the caller explicitly brackets work with `Parallel.run`.

## Naming rules

- Prefer nouns for data and verbs for effects.
- Use `at:(x, y)` consistently for positions.
- Use `from_`/`to_` for line endpoints.
- Use radius for circles, never sometimes diameter and sometimes radius.
- Angles are radians throughout.
- Colors are `Color.t`, never polymorphic magic values.
- Constructors return a value and therefore do not require a trailing `()`,
  except when optional arguments would otherwise be unerasable.
- Keep common names short (`rect`, `circle`, `line`, `text`); put advanced
  control behind optional labels.

## Capability roadmap

The API is considered feature-complete for 2D sketching when these layers are
covered:

1. lifecycle, timing, input snapshots, deterministic headless execution;
2. primitives, scoped styles/transforms, images, fonts, offscreen canvases;
3. paths/curves, blend modes, clipping, pixels, capture/export;
4. asset caching and asynchronous preload;
5. deterministic random/noise, palettes, interpolation and easing;
6. audio playback and simple synthesis;
7. PXUI controls and parameter persistence;
8. live reload or a documented utop/dune watch feedback loop.
9. coarse-grained multicore helpers and background asset jobs with main-domain
   handoff.

Items 1 and the core of 2 are implemented by `Frame`, `Scene`, and `Sketch`.
Unimplemented roadmap items must not be represented by fake polymorphic
stubs—the API should return useful errors or omit the operation until real.

## Compatibility and evolution

- Existing modules remain available during the high-level API rollout.
- `Scene.render` is public for embedding a declarative scene inside an existing
  `App.run` program.
- SDL objects should be removed from high-level `.mli` files over time and
  moved to an explicitly low-level namespace.
- Breaking changes should update this document and at least one complete
  example in the same change.

## API acceptance tests

A proposed high-level feature should demonstrate:

1. a minimal complete sketch;
2. a stateful sketch with no user mutation;
3. input use without a separate synchronization layer;
4. matching drawing, event positions, and hit testing at standard and simulated
   high-DPI renderer scales;
5. successful headless rendering;
6. no SDL types in the new public signature;
7. a focused test for pure scene/model behavior.
