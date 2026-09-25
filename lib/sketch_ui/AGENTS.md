# lib/sketch_ui rules

`sketch_ui` composes `pxui`, `pxui_graph`, `sop_ui`, `sketch_support` and
`sop_catalog` into the sketch environment. Nothing imports it.

## Editor layering (target, plan U)

- Foundations (history/undo with explicit merge rules, keymaps, routing,
  focus, one save format) move to a pure `editor` library; chrome (panes,
  splitters, which-key, prompts, status/timeline bars) to `pxui_shell`.
- Panes return intents; one dispatcher applies them. Code inside `Ui.frame`
  never mutates the model or refs.
- Keys become actions only through data keymaps; panes do not match
  `KeyPressed` for commands. `pxui_graph` never matches operation names; the
  host passes predicates such as `~flaggable`.
- Every document change goes through the immutable `Procedural.Edit_graph`
  document and is recorded for undo. Camera math lives in `prismel`
  (`Easy_camera`), not here.
- `Sketch_ui.Private` (`Workspace`, `Leader`) is unstable and test-only.

## Adapters

`pxui_graph` and `sop_ui` are presentation adapters, not graph authorities:
selection lives in returned immutable UI state, topology in
`Procedural.Edit_graph`, and this host applies typed editor commands before
compiling a cookable DAG. Parameter edits replace the selected node in that
same document (or use `Node.apply_parameters` for a standalone node).

## Workspace UX

Prefer `Sketch_ui.Environment3` for 3D SOP scenes and
`Sketch_ui.Environment2` for 2D SOP scenes. Both own leader-key (`Space`)
playback, timeline, visibility, and preset bindings (one leader keymap table),
selected-node inspection, reactive cooking, camera/render
controls, resize handling, status, export, and finite native termination;
sketch source should primarily define its graph and scene preparation.

Keep the standard sketch workspace as three independently collapsible columns:
view, graph, and inspector, with default flexible proportions 45/35/20.
Splitters retain ratios across window resize. An empty graph selection shows
camera/render controls in the inspector; selecting a node shows only that
node's generated SOP parameters. Graph tile dragging is presentation-only and
must preserve connectivity, stable IDs, caches, and cook state. Right/middle
drag pans, wheel/trackpad motion zooms at the pointer, [Home] frames all, and
leader `f` frames the selected tile ([F] frames the viewport camera on it).
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

Keep the standard sketch workspace as three independently collapsible columns:
view, graph, and inspector, with default flexible proportions 45/35/20.
Splitters retain ratios across window resize. An empty graph selection shows
camera/render controls in the inspector; selecting a node shows only that
node's generated SOP parameters. Graph tile dragging is presentation-only and
must preserve connectivity, stable IDs, caches, and cook state. Right/middle
drag pans, wheel/trackpad motion zooms at the pointer, [Home] frames all, and
leader `f` frames the selected tile ([F] frames the viewport camera on it).
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
- Custom procedural nodes may compose public SOP/Geom operations or implement a
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
