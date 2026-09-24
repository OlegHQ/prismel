# Sketch UX plan: leader key, presets, cameras, fly mode

Tracking doc for a multi-session implementation. Tick boxes as you land work;
append to the **Log** at the bottom (date, commit, what changed, surprises).
Rules of the road: `AGENTS.md` (Metal-only, dependency direction, PXUI single
engine, immutable models, finite smokes) and the ponytail ladder — reuse what
exists, smallest diff that is correct, one runnable check per non-trivial
piece, `ponytail:` comments on deliberate corners.

**UI kit is mandatory.** Every new surface is built from `Pxui.Ui` boxes inside
the one `Ui.frame`: `Pxui.Theme` palette only, DepartureMono/`PRISMEL_UI_FONT`,
24-pt rows (`Ui.row_height`), `Ui.panel_padding`, existing label column and
control geometry, hover/armed/drag feedback. No second hit-test, capture,
text-entry, or paint path. New widgets are functions over `Ui.box`/`signal`/
`draw`, not variant cases. Add `lib/pxui/fixtures` + `test_ui_parity` coverage
for each new widget.

## Decisions (agreed with user, 2026-09-24)

| Topic | Decision |
|---|---|
| Leader | `Space` when no text field is focused. Helix-style which-key panel centered on screen. Esc / Space / focus-loss cancels. |
| Old keys | Leader-only: remove bare `G I C H O`, graph `Space` menu, viewport `Space`-drag pan. Keep `Home`, `Delete/Backspace`, `Cmd-C/V/X/D/Z`, `Esc`. |
| Focus | Last-clicked pane (View / Graph / Inspector / Timeline), Theme-accent border. Leader shows global keys + focused-pane keys. |
| Presets | Full document: topology, per-node params, tile positions, display node, active camera, camera/render settings. File `~/.prismel/<sketch>/<name>.json`. Save prompts a name (prefilled timestamp) in the center panel. |
| Load | `Space b` picker (fuzzy, name + date, delete). Enter replaces document as **one undo step**. |
| Custom nodes | Non-catalog nodes (e.g. `wall_depth`) rebind by stable node id to the sketch's code graph; missing → typed error, document untouched. |
| Timeline | Bottom bar: play/pause/stop/reset, frame+time readout, scrub bar (seek → recook). P/S/R become leader keys. |
| Render camera | Drives path tracer, PNG export/smoke, and raster/wire view when *look-through* is on. |
| Camera nodes | Multiple allowed; default `camera` node always present (unwired); one ACTIVE flag (like VIEW); per-node *follow viewport*. |
| `F` (graph focused) | Frame the **viewport camera** on the selected node's cooked bounds. Graph-tile framing moves to `Space f`; `Home` frames all tiles. |
| Fly mode | `Space w` (view focused). WASD, **Q up / E down**, Shift faster, wheel = speed, mouse-look always (relative mouse). `Esc` exits; `Space` exits and opens the leader. |
| Context menu | Right-click without drag (threshold). Right-drag still pans. |
| Scope | 3D (`Environment3`) only for cameras/fly; leader/timeline/presets for both environments. |

### Keymap (single data table drives dispatch AND the which-key panel)

| Key | Scope | Action |
|---|---|---|
| `s` | global | save preset (name prompt) |
| `b` | global | preset picker |
| `t` / `g` / `i` | global | toggle timeline / graph / inspector |
| `h` / `c` | global | hide all UI / open Camera section |
| `p` / `r` / `x` | global | play-pause / reset / stop |
| `a` | graph | add-node menu at pointer |
| `l` | graph | layout (existing `Layout_optimized` path, today's `O`) |
| `f` | graph | frame selected tile |
| `w` | view | fly mode |
| `v` | view | look through render camera |

Fly-mode exits (decided 2026-09-24): **both** — `Esc` exits fly mode, and
`Space` exits fly mode, releases mouse capture, and opens the leader panel.

## Codebase map (verified 2026-09-24)

- `lib/sketch_ui/sketch_ui.ml` (963 lines): `Workspace` (l.63, bare `g`/`i` at
  l.266–267, geometry/panes), `Core` (l.~318: `workspace`, `timeline`, graph,
  undo, worker; `update` l.540 handles `c` at l.555 and a key match at l.618),
  `Environment3` (l.~680, `CC.widgets`/`CC.navigate`, `rerender` l.729),
  `Environment2` (l.~830). Its `key_pressed` helper is l.30.
- `lib/pxui/camera_controls.ml`: bare `h`/`c` in `shortcuts` (l.20), `Space`
  translation key at l.97 (3D) and l.153 (2D).
- `lib/pxui_graph/pxui_graph.ml` (1880 lines): key match at l.~1541–1599 —
  `Space` → `open_menu` (l.1550), `o` → layout (l.1551), `Home` (l.1563),
  `f` → `frame_selected` (l.1564), `Escape` (l.1599). Menu state/type l.71,
  `menu_row` l.103, geometry constants l.233–236. `positions` per node id.
- `lib/sketch/timeline.ml{,i}` (library `sketch_support`): `P/S/R` shortcuts
  record, `mode`, `time`, `frame`, `changed_context`. No seek, no UI.
- `lib/procedural/edit_graph.mli`: `root`/`set_root` = display node;
  `inspect` → `node_info` (id, label, operation, inputs); entries store an
  optional `factory` **privately** (`edit_graph.ml:24`) — needs an accessor.
- `lib/procedural/node.mli`: `parameter_fields` → `Parameter.field_view list`
  with `current : Parameter.value` (Bool/Int/Float/Text/Choice). Restore via
  `Edit_graph.apply_parameters doc ~node_id [(name, value)]`.
- `lib/prismel/easy_camera.mli`: orbit cam (target, distance, azimuth,
  elevation via `create`); **no azimuth/elevation getters/setters**.
  `lib/prismel/camera.mli` has `position/target/up`, `truck/boom/dolly/pan/tilt`.
- `lib/sdl3/sdl3.mli:137` has `set_relative_mouse`; Runtime does not expose it.
  `runtime_next_input.ml:80` computes `mouse_delta` from absolute positions —
  wrong under relative mode (must use SDL `xrel/yrel`).
- `yojson` is already a package dependency (`dune-project:35`) → use it for
  presets, no new dep.
- `examples/voxel_wall/main.ml`: renderer switch via global `renderer_ref`
  Atomic + `Environment3.rerender`; `scene3` selects `prepared.raster/wire`.

## Phases

Estimates are new/changed lines of OCaml (excluding tests) and are for
sizing, not promises. Order: 0 → 1 → 2 → 3 → 4 → 5 → 7 → 6 → 8.

### Phase 0 — Bug: voxel_wall raster/wireframe blank  (~10–40 LOC, S)
- [x] Reproduce: `PRISMEL_VOXEL_RENDERER=raster PRISMEL_PATHTRACER_FRAMES=90
      PRISMEL_PATHTRACER_PNG=$TMPDIR/r.png dune exec examples/voxel_wall/main.exe`
      (and `wireframe`); also switch live from the inspector.
- [x] Root-cause before editing. Suspects, in order:
  1. `prepare` reads `renderer_ref` at cook time but `rerender` may not
     re-run `prepare` (cached cook reused) → `raster`/`wire` stay `None`.
  2. Packed path: `split_packed` loose points + `Scene3.instances_array`
     transforms; check instances actually reach Metal (compare with
     `test_runtime_next_scene3_instances.ml`).
  3. Wireframe `Mesh.Lines` with `instances_array` unsupported by native path.
  4. Camera near/far vs 59-unit wall.
- [x] Fix in the shared function (`rerender`/prepare invalidation or Scene3
      lowering), not only in the example. Prefer making the render mode part
      of what `prepare` is keyed on over a global Atomic if that's the cause.
- [x] Check: finite native test asserting non-background pixels in captured
      framebuffer for raster and wireframe modes.

### Phase 1 — Focus + leader + keymap  (~250 LOC, M)
Where: `sketch_ui.ml` (new small `Leader` module inside it; no new library).
- [x] `type pane = View | Graph | Inspector | Timeline`; focus = last
      left-press inside a pane's bounds (from `Workspace.geometry`). Paint a
      1-px `Theme` accent border on the focused pane via `Ui.draw`.
- [x] Keymap: `{ key : char; label : string; scope : pane option; action }`
      list. `action` is a plain variant (`Save | Browse | Toggle_timeline | …`)
      handled in `Core.update` — one `match`, no closures registry.
- [x] Leader state in `Core`: `Idle | Pending`. `Space` pressed with
      `not (Ui.text_input_focused ui)` and no picker open → `Pending`. Next
      `KeyChar` → lookup (global + focused scope) → action → `Idle`. Unknown
      key, `Esc`, `Space`, `WindowFocusLost` → `Idle`.
- [x] Which-key panel: centered `Ui.panel` (blocking flag, so the view/graph
      don't receive the key/pointer), title "Leader", two-column rows
      `key  label` using `Paint.text` + Theme muted/accent colors, rows at
      `Ui.row_height`. Scope sections: "Global", then focused pane name.
- [x] Remove bare keys: `Workspace.update` `g`/`i` (l.266–267), Core `c`
      (l.555–557), `Camera_controls.shortcuts` `h`/`c` → expose
      `Camera_controls.toggle_ui`/`open_camera` functions instead; graph
      `Space`/`o`/`f` in `pxui_graph.ml` → expose `Pxui_graph.open_menu_at`,
      `optimize_layout`, `frame_selected` in the `.mli`.
- [x] Viewport pan: drop `with_translation_key (Some Input.Space)`
      (`camera_controls.ml:97,153`); right/middle drag already pans.
- [x] Timeline `P/S/R`: `Timeline.create ~shortcuts` — make shortcuts
      optional (`?shortcuts:None` disables) and drive `pause/stop/reset`
      through new `Timeline.toggle_pause / stop / reset` functions (they exist
      internally; export them).
- [x] Check: pure test feeding synthetic `Frame.t` events: `Space g` toggles
      graph; `Space` then `Esc` does nothing; `Space w` ignored unless View
      focused; `Space` while a text field is focused types a space.
- [x] Update `specification/api.md` + README shortcut table; `pxui_graph.mli`
      doc comment (l.113–120) for removed keys.

### Phase 2 — PXUI widgets: modal, picker, context menu  (~300 LOC, M)
Where: `lib/pxui/ui.ml{,i}` (+ move menu row painting out of pxui_graph).
- [x] `Ui.modal : t -> ?width:float -> string -> (unit -> 'a) -> 'a option`
      — centered, blocking, Esc closes (returns `None`). Reused by leader
      panel, save-name prompt, preset picker, add-node menu.
- [x] `Ui.picker : t -> string -> query:string -> (string * string) array ->
      (string * [`Pick of int | `Delete of int | `None])` — text field +
      windowed list (keyboard up/down/enter, mouse), rows = label + dim
      right-aligned detail. Fuzzy = case-insensitive subsequence (10 lines,
      no dep). `ponytail:` note: subsequence score, swap for fzf-style
      scoring if lists get long.
- [x] Port the graph Space-menu (`pxui_graph.ml` menu, l.71–236 constants)
      to render through `Ui.picker` with its breadcrumb/category rows, so
      there's one menu path. Keep the existing catalog-search tests green
      (every stable key still findable; row limit windows, never truncates).
- [x] `Ui.context_menu : t -> string -> (string * bool) list -> int option`
      opened at the pointer after right press+release under a 4-pt drag
      threshold; press outside/Esc closes.
- [x] Graph context menu entries: empty → Add node…, Layout, Frame all;
      tile → View, Set active camera (camera nodes only), Duplicate, Delete,
      Frame camera; wire → Insert node…, Delete. Emit the existing typed
      `change`/request values — no new edit path.
- [x] Check: `test_ui.ml` cases for picker keyboard nav, context-menu
      press/release commit rule, drag-threshold vs pan; parity fixtures.

### Phase 3 — Layout via leader  (~5 LOC, XS)
- [x] `Space l` calls the exported `Pxui_graph.optimize_layout` (existing
      `Layout_optimized` path). Nothing else.

### Phase 4 — Timeline bar  (~180 LOC, M)
Where: `lib/sketch/timeline.ml{,i}`, `Workspace` in `sketch_ui.ml`.
- [x] `Timeline.seek : t -> frame:int64 -> t` (+ a `Seeked` change that sets
      `changed_context`).
- [x] `Workspace`: add a bottom `timeline` bounds row (one row height +
      padding) spanning the window, collapsible, hidden by default; `Space t`
      toggles. Existing splitter ratios unaffected.
- [x] Bar contents built with existing widgets: `Ui.button` ×3 (play/pause,
      stop, reset), `Ui.label` readout `f 120  2.00s`, scrub = `Ui.slider`
      (captures press→release, clamps) over `0..max(frame, range_end)`.
      Range end: `?timeline_frames` config, default 240.
- [x] Seek → existing `Reactive_sop.submit_timeline` recook. `ponytail:`
      stateful/iterative sketches (`run_state` feedback) just reset+replay up
      to the target; cap replay, document it.
- [x] Check: pure test for `seek` + `changed_context`; UI test drag-scrub.

### Phase 5 — Camera nodes, active camera, look-through, follow  (~300 LOC, L)
Where: `lib/sop_catalog` (node), `sketch_ui.ml` (state/rendering),
`examples/voxel_wall` (path tracer uses render camera).
- [x] `Sop_catalog.Camera`: `[@@deriving sop_params, sop_node]` record
      `{ position; target; up; fov_y; near; far; follow_viewport : bool }`
      (vec3 as 3 floats if the PPX lacks vec3), zero inputs, category
      `["Scene"]`, `[@@sop.register]`. Cook = empty geometry. `ponytail:` no
      frustum gizmo; add a wireframe frustum overlay if users ask.
- [x] Active camera id lives in `Core` (UI state, like display selection),
      **not** in `Edit_graph` (which owns topology only). Default:
      `Environment3.create` adds a `camera` node if the document has none and
      marks it active. Deleting the active camera → next camera, or re-add
      default.
- [x] Graph tile: ACTIVE button next to VIEW on nodes whose operation is
      `camera`; flagged visually like VIEW. Needs `Pxui_graph` to accept an
      `?active_camera:int` and emit `Active_camera_changed id`.
- [x] Easy_camera ↔ Camera conversion: add
      `Easy_camera.of_view : eye:Vec3.t -> target:Vec3.t -> t -> t`
      (derive distance/azimuth/elevation; verify axis convention against
      `Easy_camera.camera`). One function; no setter zoo.
- [x] `Environment3.render_camera : 'p t -> Camera.t` = active node params.
      Look-through (`Space v`, toggle in Camera section): viewport draws with
      `render_camera`; orbit input disabled unless the node follows viewport.
- [x] Follow viewport: when on, write viewport eye/target/fov into the node
      via `Edit_graph.apply_parameters` — coalesce: one undo entry per drag
      (commit on pointer release), not per frame. Mark view-only impact so it
      doesn't invalidate cooks.
- [x] Wire consumers: `Camera_controls` PNG export + finite smoke use
      `render_camera`; voxel_wall `P.render` uses `render_camera`.
- [x] Check: test default camera injection, one-active invariant after
      delete/paste, follow-viewport undo coalescing; native smoke: look-through
      framebuffer equals render-camera framebuffer.

### Phase 7 — `F` frames viewport camera on node  (~80 LOC, S)
- [x] With Graph focused, `F` (direct key, not leader): selected node id →
      cook via `Edit_graph.compile_node` on the existing bounded worker
      (don't block the frame) → `Pdk` positions bounds → set Easy_camera
      target = center, distance = radius / tan(fov/2) × 1.2.
- [x] If the node is the displayed node and its cook is cached, use it.
      Empty geometry → status message, no camera change.
- [x] Check: pure test of bounds→(target, distance) math.

### Phase 6 — WASD fly mode  (~220 LOC, L — crosses Runtime boundary)
- [x] Runtime: expose `Runtime.set_relative_mouse : bool -> (unit, error) result`
      over `Sdl3...set_relative_mouse`; in relative mode accumulate SDL
      `xrel/yrel` into `mouse_delta` (`runtime_next_input.ml:80`).
- [x] Prismel: `Input.set_relative_mouse : bool -> (unit, string) result`
      (or `Sketch`-level; pick the narrowest). No SDL values in the API.
- [x] Fly controller in `Pxui.Camera_control` (camera policy lives there):
      state `{ flying; speed }`; per frame: `Input.is_key_down` WASD/QE →
      `Camera.truck/boom/dolly` × speed × dt (Shift ×4); `Frame.mouse_delta`
      → yaw about `up_axis`, pitch clamped ±89°; wheel scales speed.
      Convert back with `Easy_camera.of_view` so orbit resumes seamlessly.
- [x] Exit on `Esc`, `WindowFocusLost`, or `Space` (exits, releases capture,
      and opens the leader in the same frame). Always restore relative mode off.
- [x] Check: pure test of one frame of movement/rotation math; runtime input
      test for relative delta accumulation; finite native smoke toggling fly.
- [x] Boundary change duties: dependency-direction check, focused tests at
      each boundary, `specification/backend.md` update.

### Phase 8 — Presets  (~350 LOC, L)
Where: new `lib/sketch_ui/preset.ml{,i}` (only new file in the plan),
`Edit_graph` one accessor, `sketch_ui.ml` wiring.
- [x] `Edit_graph.factory_key : t -> node_id:int -> string option` (entries
      already store `factory`, `edit_graph.ml:24`).
- [x] JSON via `yojson` (already a dependency):
      `{ version: 1, sketch, nodes: [{ id, factory_key?, label, inputs:[id|null],
         params: [[name, {bool|int|float|text|choice}]], x, y }],
         display, active_camera, camera: {eye, target, fov}, render: {...} }`.
- [x] Save: `Space s` → `Ui.modal` with `Ui.text_field` prefilled
      `YYYY-MM-DD_HH-MM-SS`; sanitize name (`[A-Za-z0-9_-]`), write
      `~/.prismel/<sketch>/<name>.json` via temp file + `Sys.rename`; mkdir -p.
      `<sketch>` = new `?name` on `Environment{2,3}.create`, default = window
      title slug. Status message on success/error.
- [x] Load: build a new `Edit_graph` from the code graph
      (`Edit_graph.of_graph`) as the node source: code-defined ids rebind
      directly; nodes with `factory_key` instantiate from catalog factories
      (disconnected placeholders), then `connect` inputs, then
      `apply_parameters`, `set_root display`, positions via
      `Pxui_graph.place_node`. Any failure → `Error`, current doc untouched.
      Success → push through the existing undo stack as one step.
- [x] `Space b` → `Ui.picker` over `Sys.readdir` (name, mtime), `Delete`
      key removes file (confirm row turns red, second press deletes).
- [x] Check: `test/` round trip: voxel_wall-like graph with a custom node +
      an added catalog node + moved tile + edited param → save → load →
      `Edit_graph.inspect` equal; missing custom id → `Error`; corrupt JSON →
      `Error`. Uses a temp dir, never real `~/.prismel`.

## Verification (every phase, before ticking it)
```sh
dune build @all && dune runtest && git diff --check
dune exec examples/voxel_wall/main.exe   # with PRISMEL_PATHTRACER_FRAMES=90
dune exec examples/pxui/main.exe
```
Plus the full AGENTS.md handoff list at the end, `dune build @doc`, and
`specification/api.md` / `backend.md` updates where noted.

## Deliberately skipped (add when asked)
- Configurable/user keymaps file — the table is data; expose it later.
- Leader sequences deeper than one key (`Space x y`).
- Camera frustum gizmo in the viewport.
- Cameras/fly for `Environment2`.
- Preset migration beyond `version` check (reject unknown versions).

## Estimate summary
| Phase | Size | LOC | Risk |
|---|---|---|---|
| 0 bug | S | 10–40 | unknown root cause |
| 1 leader | M | 250 | touching many shortcut call sites |
| 2 widgets | M | 300 | porting graph menu without breaking catalog tests |
| 3 layout | XS | 5 | — |
| 4 timeline | M | 180 | seek for iterative sketches |
| 5 cameras | L | 300 | Easy_camera axis convention, undo coalescing |
| 7 F-frame | S | 80 | async cook of non-displayed node |
| 6 fly | L | 220 | Runtime relative-mouse boundary |
| 8 presets | L | 350 | rebinding custom nodes, factory accessor |
| **total** | | **~1.7k** | |

## Log
- 2026-09-24 — plan written; codebase map verified against `cae67594`.
- 2026-09-24 — all phases landed (uncommitted working tree on `dev`).
  - **0**: root cause = `Environment3.rerender` re-ran `scene3` on a
    `prepared` built by the previous mode. Fix in the shared function:
    `rerender` now forces a recook so `prepare` re-runs (`Core.force_cook`).
    Check: `test_sketch_ui` mode-atomic test; voxel_wall gained
    `PRISMEL_VOXEL_SWITCH=raster|wireframe` (switches at frames/2) for the
    native smoke.
  - **1–3**: `Sketch_ui.Leader` (one keymap table + pure `step`), focus
    outline, which-key `Ui.modal`; bare G/I/C/H/O/F/Space and viewport
    Space-pan removed; `Camera_control.toggle_ui/open_camera`,
    `Pxui_graph.open_menu_at/optimize_layout/frame_selected`,
    `Timeline.create ~shortcuts:None` + `toggle_pause/stop/reset`.
    `Layout_optimized` change deleted (nothing emitted it any more).
  - **2**: `Ui.modal`, `Ui.picker` (takes `query -> rows`, not an array, so
    same-frame typing + Enter picks from the filtered rows; also returns
    `Submit/Back/Cancel`), `Ui.context_menu` (host-held open state) +
    `Ui.context_clicked`; graph menu ported onto the picker (Enter descends one
    level per frame); golden `fixtures/kit_overlays_2x.png`.
  - **4**: `Timeline.seek` (pauses; time = frame × mean observed step),
    `Workspace.Timeline` bottom bar, `?timeline_frames`.
  - **5**: `Sop_catalog.Camera` (operation `camera`; catalog count 159→160),
    ACTIVE flag lives in `Pxui_graph` (like VIEW), `Easy_camera.of_view`,
    `Environment3.render_camera/look_through`, follow-viewport coalesced by
    `Core.environment_edit (`View t)` (0.25 s window). Surprise: sketch_ui may
    not depend on sop_catalog (dependency test), so cameras are found by
    operation name and the default comes from the passed `factories`, seeded
    before the graph view is laid out.
  - **7**: `Easy_camera.frame_bounds`; the one worker now returns
    `Displayed (prepared, bounds) | Framed bounds`, so F on the displayed node
    is immediate and other nodes cook on the same worker (display resubmitted
    only if a framing job pre-empted it). Context menu gained "Frame camera".
  - **6**: `Sketch.set_relative_mouse` → execution → orchestrator →
    `Runtime.set_relative_mouse`; `Runtime_next_input.add_motion` +
    relative accounting; `Sdl3.Event.poll_coalesced` now sums dropped
    samples' dx/dy (it silently lost relative motion before).
    `Camera_control.fly` pure step. Prismel's live `mouse_delta` comes from
    `Input`, not `runtime_next_input` as the codebase map assumed.
  - **8**: `Sketch_ui.Preset` (yojson + unix added to sketch_ui; dependency
    test updated), `Edit_graph.node_factory_key` (the planned `factory_key`
    name was taken), `Pxui_graph.node_positions`; save prompt is a row-less
    picker (keyboard-first) instead of `Ui.text_field`. Native look-through
    framebuffer check lives here (it needs a loaded non-following camera).
  - Gates: `dune build @all @doc`, `git diff --check` clean; `dune runtest`
    failure set identical to a clean `HEAD` worktree (Metal macOS-26.4 guard,
    OGPU readback, SDL3 generator staleness, qualification evidence) except
    the API manifest, now regenerated. `examples/particles` and `audio` fail
    identically at `HEAD`.
