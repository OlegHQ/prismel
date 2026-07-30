# Prismel repository guide

## Purpose

Prismel is an OCaml creative-coding framework. Keep its public API small,
functional where practical, and suitable for both interactive desktop programs
and deterministic headless execution.

## Repository layout

- `lib/prismel/` is the main `prismel` library.
- `lib/<name>/` contains sibling libraries. A sibling library may depend on
  `prismel`; `prismel` must never depend on a sibling library.
- `lib/pxui/` is the UI toolkit inspired by ofxUI.
- `examples/<project>/` contains self-contained example executables. Give every
  example its own `dune` file and keep shared framework code out of examples.
- `test/` contains automated tests, including headless integration tests.
- `specification/` contains design notes. Update it when behavior or architecture
  changes materially.
- `tsdl_gfx/` is the low-level SDL2_gfx binding and is not part of the high-level
  API.

## Dependency direction

```text
examples ──> pxui ──> prismel ──> tsdl/tsdl_gfx
    └────────────────> prismel
```

Never introduce a dependency from `prismel` to `pxui` or to an example.

## Headless contract

- Treat `HEADLESS=1`, `true`, `yes`, or `on` (case-insensitive) as enabled.
- Headless mode must not require a display server, monitor, GPU, or OpenGL.
- Use SDL's dummy video driver and software renderer in headless mode.
- Do not silently turn drawing calls into no-ops: rendering should target the
  software framebuffer so programs exercise the same drawing paths.
- Keep `HEADLESS` selection in the backend boundary rather than scattering
  environment checks through application code.
- Any automated application-loop test must arrange its own termination.

## High-DPI and coordinate contract

- Treat `Sketch` configuration sizes, `Frame.width`/`height`, `Scene`
  coordinates, `Input.mouse_pos`, mouse event positions, and PXUI layout as
  logical points in one shared coordinate system.
- Keep SDL renderer logical size synchronized with the actual window size.
  `SDL_WINDOWEVENT_SIZE_CHANGED` is authoritative; ignore the duplicate
  `RESIZED` notification.
- Do not manually scale mouse events for Retina displays. SDL maps pointer
  events through the renderer logical size, which keeps drawing and hit testing
  aligned.
- Query renderer output size for physical backing pixels. Preserve
  `Frame.drawable_width`, `drawable_height`, `drawable_size`, and
  `pixel_scale` as the explicit native-pixel boundary.
- `Canvas.capture` and `Canvas.save_screen_png` read and preserve the full native
  framebuffer. Never allocate their readback from logical window dimensions.
- Keep `Scene.text` on an installed platform UI font and interpret `?size` in
  logical points. Font texture caches must include renderer density and
  rerasterize at native resolution. `PRISMEL_UI_FONT` remains the portable
  override; do not bundle Apple system fonts.
- Keep automatic scene text memory-bounded with the per-renderer 256-entry LRU
  without shortening the documented lifetime of explicit
  `Font.cached_text` images. Preserve empty text as a safe no-op rather than an
  SDL_ttf error.
- Keep renderer-local text caches LRU-bounded to 256 textures, including for
  rapidly changing labels, and preserve empty text as a valid no-op.
- Reserve `Scene.debug_text` for the fixed SDL2_gfx 8×8 diagnostic face.

## Public sketch API

- New user-facing examples should start with `Sketch`, `Frame`, and `Scene`.
  `Low.App` and `Low.Graphics` are the compatibility/escape-hatch layer.
- Thread immutable user models through `Sketch.run_state`; do not add global
  user-state refs to make an API shorter.
- A `view` returns `Scene.t`. Scene constructors must remain pure data
  constructors, and `Scene.render` is the effect boundary.
- Put current canvas, time, input, and ordered event facts in `Frame.t` so
  sketches do not need to synchronize several global modules.
- Keep `Frame.mouse_delta` equal to the sum of all logical pointer motion in one
  application frame, and reset it before polling the next frame.
- Prefer a five-minute-sketch path with sensible defaults, while keeping
  explicit configuration available for larger programs.
- Use `at:(x, y)` for positions, radians for angles, radius for circles, and
  `Color.t` for colors. Keep common constructor names short.
- Update `specification/api.md`, at least one complete example, and public API
  tests when changing the high-level design.
- Resource-owning models must release textures, fonts, and canvases with
  `Sketch.run_state ~on_stop` while SDL is still active.
- Prefer `Sketch.run_assets` for ordinary asset-owning sketches. Values returned
  by `Assets` are borrowed and must not be destroyed individually.
- Watched image reload must preserve the borrowed `Image.t` identity and retain
  the previous valid texture after a failed decode.
- `Scene.font_text` uses renderer-local textures owned by its `Font.t`. Preserve
  cache invalidation on font mutation and release offscreen-renderer entries
  before destroying their renderer.
- Preserve path contour boundaries through flattening, fill, and stroke.
  Even-odd and non-zero behavior must be tested with transparent holes rather
  than simulated background-colored shapes.
- Directly loaded or synthesized `Audio` values are owned resources and belong
  in `on_stop`. Headless audio must exercise SDL_mixer through the dummy device,
  not silently replace playback with a no-op.
- Do not add fake polymorphic placeholders for planned operations. Implement a
  real result-returning boundary or leave the operation out of the public API.

## Multicore and determinism

- SDL window, renderer, event, texture, image, and font operations must execute
  on the initial domain. `Scene.render` enforces this boundary.
- Use the reusable `Parallel` Domainslib pool for coarse CPU work. Never spawn a
  domain per frame or per collection item.
- Functions submitted to `Parallel` must operate on immutable or independently
  owned data. Do not mutate shared refs, arrays, stacks, or SDL objects without
  an explicitly reviewed synchronization design.
- Use immutable `Rand.t` values for new generative APIs. Do not use the global
  `Stdlib.Random` state in parallel-capable code.
- A seed must reproduce the same values, palettes, geometry, and noise across
  runs. Split generators before independent parallel work.
- Use `Sketch.Fixed dt` for repeatable simulation and export. The timestep must
  be finite and positive; time is derived from frame count rather than wall
  time.
- Keep `Sketch.export` artifact-deterministic: fixed inputs must produce
  byte-identical numbered PNG sequences across repeated runs on the same
  backend.
- Keep scheduling grain configurable and retain a sequential path for small
  collections, where parallel overhead costs more than the work.
- Parallel asset preparation may read ordinary bytes only. SDL_image decode,
  texture upload, and cache mutation join back onto the initial domain.

## Development workflow

Bootstrap a checkout with a repository-local OCaml 5 switch:

```sh
opam init
opam switch create . 5.3.0
direnv allow
opam install . --deps-only --with-test --with-doc
```

The checked-in `.envrc` evaluates `opam env --switch=. --set-switch`. If
direnv is unavailable, evaluate that command manually before using Dune.

Run these before handing off a change:

```sh
dune build @all
dune runtest
HEADLESS=1 dune exec examples/basic/main.exe
HEADLESS=1 dune exec examples/particles/main.exe
HEADLESS=1 dune exec examples/noise/main.exe
HEADLESS=1 dune exec examples/canvas/main.exe
HEADLESS=1 dune exec examples/audio/main.exe
HEADLESS=1 dune exec examples/pxui/main.exe
HEADLESS=1 dune exec examples/generative/main.exe
dune build @doc
```

If a headless example would otherwise run forever, give it an explicit finite
frame count for smoke testing.

## OCaml conventions

- Add an `.mli` for public modules.
- Prefer explicit result/error handling at backend boundaries.
- Avoid exposing additional SDL values in new public APIs.
- Keep sibling libraries wrapped, so their modules remain namespaced.
- Add focused tests for pure behavior and a headless integration test for
  renderer or lifecycle changes.
- High-DPI changes need coverage for renderer logical/output size, native
  capture dimensions, logical mouse alignment, per-frame delta reset, and PXUI
  press/drag/release behavior at simulated backing scales.
- Treat compiler warnings as errors and run `git diff --check`.

## Adding a sibling library

Create `lib/<name>/dune` with a wrapped library named `<name>` and declare
`(libraries prismel ...)`. Add its tests under `test/` or beside the library
only when they are genuinely library-specific. Document the library in the
README.

For `pxui`, prefer the functional builder, `Pxui.update`, and `Pxui.scene` in
new code. UI values belong in the immutable sketch model. Keep `add_*`,
`handle_event`, and `draw` only as compatibility wrappers around the same
widget semantics.

- Preserve visual feedback for hover, armed, and actively dragged controls in
  both the default theme and custom themes.
- Buttons, toggles, and choices commit only after a press and release inside
  the same control.
- Sliders, ranges, and XY controls capture the pointer from left-button press
  through release. They update continuously outside their bounds and clamp
  values to their configured ranges.
- `WindowFocusLost` must clear held input and cancel PXUI pointer capture, text
  focus, and IME composition.
- PXUI defaults to `Scene.text`; `Pxui.create ~font` borrows the supplied font,
  while `~font_size` selects the logical size of default system text.

## Adding an example

Create `examples/<name>/dune` and `examples/<name>/main.ml`. Depend only on the
libraries the example demonstrates. Examples are teaching material: keep them
short, readable, independently runnable, and finite under `HEADLESS`.

Use the repository scaffold for the standard shape:

```sh
dune exec tools/new_example.exe -- <name>
```
