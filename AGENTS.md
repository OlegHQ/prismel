# Prismel repository guide

## Purpose

Prismel is an OCaml creative-coding framework for interactive native desktop
programs. It ships native Apple-Silicon Metal only, through OGPU, whose API is
backend-agnostic by design. Keep the public API small and functional where
practical. Never add a CPU raster, browser/web, SDL2/Tsdl, or OpenGL fallback;
Metal unavailability is a typed startup error.

Nested `AGENTS.md` files hold subsystem rules: `lib/metal`, `lib/ogpu`
(also for `lib/ogpu_core`),
`lib/runtime`, `lib/pdk`, `lib/prismel_editor`, `lib/sop_catalog`. Read the one for
the directory you change. Design notes live in `specification/`; update them
when behavior or architecture changes materially.

## Libraries

| Library | Owns |
|---|---|
| `sdl3`, `sdl3_image/ttf/mixer` | SDL3 bindings (foundational) |
| `metal` | Metal bindings: safe layer over a handwritten bridge (foundational) |
| `ogpu_core`, `ogpu` | Portable GPU core and virtual public API |
| `ogpu_metal_native`, `ogpu_metal`, `ogpu_mock` | Native Metal detail and the two OGPU implementations |
| `runtime`, `runtime_input`, `runtime_resources` | SDL3 lifecycle, Metal presentation, frame stats, typed event translation, SDL image/ttf/mixer services |
| `prismel_execution` | Private frame coordinator: Scene lowering caches over one window or offscreen `Runtime` |
| `scene_command`, `scene_execution` | Renderer-neutral commands and their GPU execution |
| `prismel` | `Sketch`, `Frame`, pure `Scene`, `Event`/`Input`, resources, renderer behavior |
| `prismel_pathtracer` | Hardware ray-traced path tracer |
| `pdk` | The single packed geometry/topology compute core |
| `procedural` | Immutable SOP graphs over `pdk` operations |
| `sop_catalog` | Inspectable SOP constructors registered by PPX |
| `param` | Typed parameter schemas; no dependencies (`Procedural.Parameter`, `Editor_core.Param`) |
| `editor_core` | Pure editor core: labelled `History`, `Command`, `Keymap`, `Router`, `Store` |
| `pxui` | The one immediate-mode UI engine (`Pxui.Ui`) |
| `pxui_shell` | Editor chrome over PXUI: layout, headers, keys, status, timeline, prompts, frame, `Inspector` |
| `pxui_graph` | SOP-network presentation; emits typed requests, never edits |
| `sketch_support` | Procedural-to-Scene glue (`Bridge`: cooked meshes, instances, frame context) and packed pieces |
| `prismel_editor` | Prismel Editor: the Houdini-like SOP shell (`Editor3`/`2`), composed only from public blocks |

`examples/<name>/` are short teaching programs; `sketches/<name>/` are
experiments. Each has its own `dune`, depends only on what it shows, keeps
framework code out, and runs finitely under `PRISMEL_MAX_FRAMES`. Scaffold an
example with `dune exec tools/new_example.exe -- <name>`. Prefer
`Prismel_editor.Editor3`/`2` for SOP sketches, SOP graphs for geometry, and
deterministic seeds.

## Dependency rules

`test/dependency_gate.ml` reads every `lib/**/dune`, builds the transitive
graph, and enforces "may never reach" rules plus a token scan. Known
violations are listed there with the plan item that removes them.

- Foundational libraries (`sdl3*`, `metal`, `ogpu_core`, `ogpu`, `native_layer_token`,
  `scene_command`) never reach `runtime`, `prismel`, or anything above.
  `ogpu_core` depends only on `native_layer_token` (the opaque presentation
  layer handle); virtual `ogpu` depends only on `ogpu_core`. `ogpu_mock`
  stays portable; native Metal detail depends only on `ogpu_core`, `metal`
  and `lru`.
- `Metal.`/`Ogpu_metal_native.` stay within the Metal backend; the runtime,
  path tracer, and their tests use the virtual `ogpu` only, and the gate lists
  no Metal exception.
- `prismel` never depends on `pxui`, geometry, sketch libraries, or examples.
- `pxui_shell` depends only on `prismel`, `editor_core`, and `pxui`; it never imports
  SOP, graph, geometry, or sketch libraries.
- `pdk` never reaches `procedural`; `procedural` never reaches UI
  libraries; `pxui` never reaches `procedural`; `param` depends on nothing;
  `pxui_graph` never imports `sketch_*`; nothing below imports `prismel_editor`.
- A boundary change updates the gate, adds focused tests at each affected
  boundary, and updates `specification/backend.md`. Do not expose raw SDL,
  Metal, or runtime values in `Scene` or public sketch code.

## Loops

```sh
dune build @check                 # inner loop: typecheck only
dune build @lib/<name>/runtest    # focused tests
dune build @all && dune runtest && dune build @smoke && git diff --check  # pre-commit
dune build @doc
```

`@smoke` launches two finite native examples; use `@smoke-all` for the full
example/sketch sweep. Both open windows sequentially. For a window-free broad
test run, set `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy` on `dune runtest`.

Default `runtest` is green on a clean checkout. Display-dependent tests live in
`@runtest-native`; long, SDK-, driver-, or machine-specific checks in
`@qualification`. A public `.mli` change shows as a diff of
`tools/api_manifest/api_stable.json`; accept an intended change with
`dune promote`. Warnings are errors. Automated application loops arrange
their own termination. Build, generation, and validation glue is OCaml under
Dune, never Python; external-tool comparisons belong in `../prismel-support`.

Bootstrap: `opam switch create . 5.3.0 --no-install`, then `opam pin add
--no-action --yes --recursive ./packaging`, `direnv allow` (or
`eval "$(opam env --switch=. --set-switch)"`), and `opam install . --deps-only
--with-test --with-doc`. `packaging/` only probes native SDL3 dependencies.

## Public API

- User-facing code starts with `Sketch`, `Frame`, and `Scene`; thread an
  immutable model through `Sketch.run_state`; no global user-state refs.
- A `view` returns `Scene.t`. Scene constructors are pure data;
  `Scene.render` is the effect boundary.
- `Frame.t` carries canvas, time, input, and ordered events.
  `Frame.mouse_delta` sums one frame's pointer motion and resets each frame.
- Conventions: `at:(x, y)` positions, radians, radius for circles, `Color.t`
  colors, short constructor names, sensible defaults with explicit config.
- Resources (textures, fonts, canvases, audio) are owned: release them in
  `Sketch.run_state ~on_stop` while SDL is alive. Audio is SDL3_mixer-backed
  and never silently a no-op.
- No fake placeholders: implement a real `result`-returning boundary or leave
  the operation out. Prefer explicit `result` errors at backend boundaries.
- Every public module has an `.mli`; sibling libraries stay wrapped. Changing
  the high-level design updates `specification/api.md`, an example, and tests.

## Coordinates and native runtime

Sketch sizes, `Frame` sizes, Scene coordinates, mouse positions, and PXUI
layout are logical points. `Frame.drawable_*`/`pixel_scale` are the explicit
native-pixel boundary; conversion to drawable pixels happens once, inside the
GPU backend. Details: `lib/runtime/AGENTS.md`.

## Determinism and domains

- SDL, Metal, texture, font, audio, event, and cache operations run on the
  initial domain. Never create a domain or thread per frame or item.
- Use the shared `Parallel` Domainslib pool for coarse pure work on immutable
  or disjointly owned data, with a tunable grain and a sequential cutoff.
- Parallel results are byte-identical to the sequential path; every parallel
  change has an exact one-domain vs multi-domain regression.
- Use immutable `Rand.t`, never global `Stdlib.Random`, in parallel-capable
  code; split generators before independent work. `Sketch.Fixed dt` and
  `Sketch.export` are artifact-deterministic.

## Performance

Performance is correctness on hot paths. Measure before changing one (wall
time, allocations, input size, domains, profile, machine) and hand off with the
benchmark command and before/after numbers. Packed arrays, not lists, for dense
data; no `List.nth`, `@`, or repeated `List.length` in hot loops; pre-size or
grow geometrically; int keys over polymorphic hash. Every cache has an explicit
capacity. Frame work must not scale with unchanged scene size. Never claim
"linear", "zero allocation", or "production-ready" without evidence. Full
contract: `lib/pdk/AGENTS.md`.

## UI

`Pxui.Ui` is the only UI engine: build widgets each frame inside `Ui.frame`,
keep their values in the immutable model, destroy the handle in `on_stop`.
Every host shares its capture, focus, hit list, and renderer; never add a
second hit-test, capture, text-entry, or painting path. New widgets are
functions over `Ui.box`/`Ui.signal`/`Ui.draw`. UI code returns intents and does
not mutate the model during `Ui.frame`. Preserve the design kit (`Pxui.Theme`,
DepartureMono, 24-point rows) pixel for pixel; `lib/pxui/test_ui_parity`
guards it. Host and editor rules: `lib/prismel_editor/AGENTS.md`.
