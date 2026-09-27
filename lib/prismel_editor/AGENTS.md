# lib/prismel_editor rules

`prismel_editor` is Prismel Editor: it composes `pxui`, `pxui_shell`,
`pxui_graph`, `sketch_support` and `sop_catalog` into the SOP workspace. Nothing imports it.

## Editor layering (plan U, shipped)

- State and routing live in `editor_core`: `History` (undo with
  explicit merge rules), `Command` (one pure-data entry type, `id`, `label`,
  optional `trigger` and `scope`, `guide` contexts, `action`, for dispatch, guide, which-key, and the
  palette), `Router` (text focus, leader, chords, and the fly mode layer)
  and `Store` (JSON file persistence). Chrome lives in `pxui_shell`: layout,
  splitters, pane roots, which-key, prompts, status and timeline bars, and
  `Shell.frame`, the only `Ui.frame` caller.
- Panes return intents; `Core.update` is the one dispatcher. Code inside
  `Ui.frame` never mutates the model or refs.
- Keys become actions only through the one `Editor_core.Command.t` keymap
  (`Leader.keymap` plus `Pxui_graph.bindings` plus sketch commands mapped to
  `Leader.Sketch_command id`); panes do not match `KeyPressed` for commands.
  `pxui_graph` never matches operation names; the host passes predicates such
  as `~flaggable`.
- One immutable `Document` (the scene network, one network per geometry
  object and World, active camera object, sketch `Settings`) is the only
  thing `Editor_core.History` (128 entries) snapshots; `Core.doc` is always
  its present. Each network owns one `Flow_sop.Network` with geometry,
  value nodes and drives; scene and World networks keep empty value overlays.
  Each network's `Editor_core.Network_layout` record stores
  positions, levels, pins, row exposure and wire bends. `Network_view.edit`
  updates only the ids and destination ports `Doc.apply` reports touched;
  never walk every node on an edit frame. UI-free
  Document, Settings, Objects, Layers and Preset live in the private
  `editor_document` library, whose transitive presentation ban is gated.
- Scene objects are nodes of the scene `Edit_graph` (input 0 = parent,
  parameters = transform and kind settings; `Objects`, `Layers`), so graph,
  list, inspector, handles, presets, and undo have one path. Never add a
  parallel object model. Levels (`Document.level`) are view state; `i`,
  double-click, and list activation enter, `u` leaves. Object transforms
  are applied when composing drawings, never inside SOP networks, so scene
  edits never re-cook (`Async_cook.submit_all` cooks every visible
  geometry object in one job). See `specification/scene.md`. Graph intents go through `Doc.apply`; each recorded entry has a
  label (`intent_label`), shown as "Undo <label>". All panes emit stable-ID
  edits during construction; Core reduces and commits after `Ui.frame`.
  Gesture keys name the operation, level, node(s) and fields. Selection, hover, and an
  unlinked viewport camera are view state; a camera node that follows the
  viewport records camera moves as one `Burst` entry. Cooking and framing
  live in `Cook`; `prepare` receives the settings snapshot. Camera math lives
  in `prismel` (`Easy_camera`).
- Sketches extend the editor only through `?settings`, `?commands`
  (`Editor_core.Command` entries whose action is the run function, listed
  in which-key and the `Space /` palette exactly like built-ins),
  `?factories`, and `update_with`. Prismel Editor holds composition, not
  reusable logic: anything a second shell would want lives in `pxui_shell`
  or `editor_core`. See the `extend-prismel-editor` skill.
- `Environment.Make (V : VIEWPORT)` is the one environment. `Viewport3` and
  `Viewport2` are its instances; `Editor3`/`Editor2` only rename the
  draw callback. Add dimensional behavior to a viewport, never a second
  update path.
- `Prismel_editor.Private` is unstable and test-only. Layout and chrome callers
  use `Pxui_shell.Layout` and `Pxui_shell.Chrome` directly.

## Prismel Flow rework (in progress)

`specification/flow.md` replaces the graph-pane behavior below milestone by
milestone; `specification/flow-migration.md` lists what each milestone
changes here and which paragraphs to rewrite when it lands. Until then the
rules in this file are current. Planned changes that touch this directory:

- M1 is implemented: left-to-right canvas, polylines with authored bends,
  point/chip/card/full, editable card literals and saved layout metadata.
  Presets read and write only v3 and preserve saved ids. Pointer gestures
  seal on release; detail changes merge as one-second history bursts.
- M2 is implemented: graph grammar and guide contexts share the Command
  table; `?` toggles the contextual strip and 380 ms PXUI tooltips, persisted
  through Store user preferences. `Space k` opens the grouped key sheet;
  key feedback lasts 1.5 seconds. World keys are `t`/`n`/`d`, and `f` frames
  the selection or display node. Tab adds by context; Shift-Tab traverses UI.
- M3 in progress: documents, clipboard and preset v3 carry `flow_sop` value
  nodes and drives. The canvas shows value tiles, typed sockets and drive wires;
  the inspector and live readouts still need the applied-value table from
  `Value_lane.resolve` in `Cook` before every submission.
- M5: compound levels under instances. M6: `Space l` cycles graph, list, text.

Keep the three-column workspace, `Doc.apply` as the only graph-intent reducer,
the one Command table, and history labels; the rework extends them.

## Adapters

`pxui_graph` and `Pxui_shell.Inspector` are presentation adapters, not graph authorities:
selection lives in returned immutable UI state, geometry topology in
`Procedural.Edit_graph` within `Flow_sop.Network`, and this host applies typed editor commands before
compiling a cookable DAG. Parameter edits replace the selected node in that
same document (or use `Node.apply_parameters` for a standalone node).

## Workspace UX

Prefer `Prismel_editor.Editor3` for 3D SOP scenes and
`Prismel_editor.Editor2` for 2D SOP scenes. Both own leader-key (`Space`)
playback, timeline, visibility, and preset bindings (one leader keymap table),
selected-node inspection, reactive cooking, camera/render
controls, resize handling, status, export, and finite native termination;
sketch source should primarily define its graph and scene preparation.

Keep the standard sketch workspace as three independently collapsible columns:
view, graph, and inspector, with default flexible proportions 45/35/20.
Splitters retain ratios across window resize. An empty graph selection shows
camera/render controls in the inspector; selecting a node shows only that
node's generated SOP parameters. The empty-selection Viewport section toggles
look-through, camera frustums, the axis gizmo, and translate handles on the
selected node's position-like xyz parameters (drawn only while the UI shows);
a collapsed graph or inspector column takes no width. Graph tile dragging is presentation-only and
must preserve connectivity, stable IDs, caches, and cook state. Right/middle
drag pans, wheel/trackpad motion zooms at the pointer, [Home] frames all, and
leader `f` frames the displayed tile and graph-focused [F] frames the selection
or the display node; viewport-focused [F]
focuses the camera on the displayed node.
The node menu (leader `Space a`) must allow every SOP to be
created even when its inputs are not yet connected. Categories are non-empty
paths rendered as nested submenus; typed search remains global and matches the
full breadcrumb. A visual row limit must window the complete result set, never
truncate accessible SOPs. Command/Ctrl-C/V/X and
Command/Ctrl-D copy, paste, cut, and duplicate selected induced subgraphs with
fresh IDs, retained internal wires and relative positions, and disconnected
external inputs. Delete and Backspace remove selected nodes or wires.
Inspection selection and display selection are
independent: every tile exposes a VIEW button, the displayed tile is visibly
flagged, and switching it submits that node through the bounded cook worker
while retaining the prior successful preview.

## PXUI host behavior

- Preserve visual feedback for hover, armed, and actively dragged controls in
  both the default theme and custom themes.
- Buttons, toggles, and choices commit only after a press and release inside
  the same control.
- Sliders, ranges, and XY controls capture the pointer from left-button press
  through release. They update continuously outside their bounds and clamp
  values to their configured ranges.
- `WindowFocusLost` must clear held input and cancel PXUI pointer capture, text
  focus, and IME composition.
- PXUI text uses the kit face (DepartureMono or `PRISMEL_UI_FONT`) through
  a density-aware glyph atlas that reproduces SDL_ttf string rendering;
  `Ui.create ~font` borrows a supplied font and `~font_size` selects the
  logical size of kit text.

## Iterative procedural sketches

- Support real-time creative feedback by letting `Sketch.run_state` own the
  previous immutable PDK geometry and cook the next snapshot each application
  step. This is an iterative sketch facility, not authorization to add a
  general dynamics/VFX solver framework.
- Keep each per-step procedural graph acyclic. Feedback crosses the frame
  boundary explicitly through the sketch model and `Sop.snapshot`; never hide
  mutable feedback or global geometry state inside a SOP node or session cache.
- Custom procedural nodes may compose public SOP/PDK operations or implement a
  typed PDK kernel. Composed nodes retain inspectable subgraphs when useful;
  fused native nodes must declare stable parameter identity, context
  dependencies, input ownership, cancellation behavior, and complexity.
- Retain only current/next snapshots by default, structurally share unchanged
  PDK components, and keep cook/mesh caches bounded. History, trails, and
  checkpoints require explicit capacities and must not grow with frame count.
- Keep render-only packed instances as a terminal prototype-plus-transform
  value outside `Pdk.Geometry.t`. Do not invent fake editable packed primitives;
  use an explicit materialization boundary before feeding per-copy topology
  back into a solver step.
- Iterative sketches expose reset and optional checkpoint hooks. Repeatable
  runs use `Sketch.Fixed dt`, explicit immutable seeds, stable input streams,
  and exact one-domain/multi-domain state and framebuffer regressions.
