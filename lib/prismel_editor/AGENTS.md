# lib/prismel_editor rules

`prismel_editor` is Prismel Editor: it composes `pxui`, `pxui_shell`,
`pxui_graph`, `sketch_support` and `sop_catalog` into the SOP workspace. Nothing imports it.

## Editor layering (plan U, shipped)

- State and routing live in `editor_core`: `History` (undo with
  explicit merge rules), `Command` (one pure-data entry type, `id`, `label`,
  optional `trigger` and `scope`, `guide` contexts, `action`, for dispatch, guide, which-key, and the
  palette), `Router` (text focus, leader, chords, and the fly mode layer)
  and `Store` (atomic file writes, s-expression user preferences and viewport). Chrome lives in `pxui_shell`: layout,
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
  its present. Each network is `{context; graph; displayed}`
  over one lowered `Flow_sop.Network` (geometry plus live drives of `t` expressions); layout lives by path in the
  workspace text's layout (`Editor_document.Layout_by_path`). UI-free `Cook` resolves the live drives before
  submissions and while time advances, without changing the stored text.
- The graph pane is `Pxui_graph.Scope` (the only one); list rows use `Selection` (ids plus a primary). The
  add-menu is `Pxui_graph.Node_menu`. Value nodes, compounds (group, ungroup, make unique), wireless binds,
  expression fields and fold/unfold were deleted with the flat pane (Gap A); a drive is written in the text.
  Scene and World edits (inspector, handles, reparent, rename, delete, World keys, the render camera)
  mutate the derived `Edit_graph` and are written back to the text in the same frame by
  `Doc.reconcile` (`Editor_document.Scene_sync`, see its AGENTS.md): the workspace text is the single
  truth and Save round-trips every such edit.  A geometry object's own nodes are the lowering of its graph:
  their list rows select the node in the pane, whose inspector edits the arguments (`Set_arg`), and its
  handles write the node's arguments too.

Keep `Doc.apply` as the only graph-intent reducer, the one Command table, and
history labels; the rework extends them.  The workspace layout is described in
"Workspace shell (W10)" below.

## Workspace documents (W3)

`Document.workspace` holds the checked `Workspace_doc` and its `Lower.t`;
`Document.of_workspace` lowers it into one geometry object per `sop` graph
(object ids, tile layout and lowering ids survive edits), so the list
and inspector show the lowered top-level networks, and undo restores the source and the lowering together. A gesture is a
`Flow_sop.Flow_edit.op`: `Pxui_graph.Syntax_edit` in a frame or
`Editor3/2.edit` from a host reduce through `Doc.syntax_edit` (rewrite,
re-check, lower; atomic), one history entry named by `Flow_edit.label`, with
`Flow_edit.gesture` as the `Gesture` merge key of a scrub. After each lowering
`Cook.set_volatile` gets `Lower.is_volatile`, so time-driven workspaces
recook each frame and static nodes stay cached. Open one with `?workspace`
(`Editor3`/`Editor2` `create` and `run`; without `?factories` the whole SOP
catalog). Presets save and load only workspace documents (s-expression
`.plisp`: source, layout, settings, view). Every document is a workspace
(`?graph` was deleted); sketches open text through `Workspace.load`/`Workspace.open_text`,
so Command-S writes over their file. Old presets are not read.

## Workspace gestures added in Gap A (details in `specification/workspace/progress.md`)

- Keys (graph pane): Command/Ctrl-D duplicates the selected bindings (`Flow_edit.Duplicate`, copies selected),
  `v` views the selected geometry node (`Layout_by_path.display`, honoured for the open object by
  `Core.display_node`; the pane marks it `VIEW`), `f` frames the selection, dragging a frame by its title carries the
  nodes inside it, `j`/`k` walk the list.  A row of a geometry object's list selects its node in the pane.
- `Space a` offers every kind of the level plus a "Value" category: a number, `t`, a vector, text and every
  built-in operator, each one `Add_node` of a binding.  Adding an object or a World layer attaches it to the scene's
  `scene/merge` or the top of the World stack (`Flow_edit`); a missing scene or World graph is written first.
- The workspace inspector edits an argument as a number or as `=(expression)` (the pane's expression is the same
  text; the cross removes the keyword), renames the node, toggles Bypass, edits a graph input's default and moves list
  items.  The editor graph's panels are editable by `Space o` keys and the header menu even when written in place (the
  call holding them is unfolded) or made by a loop (a retype edits the loop's template).  Scene objects made by a loop are copies of one template: an edit, a rename or `=(expression)` writes the template, a delete rewrites the collection or asks to delete the whole loop.
- Text pane: `Ui.text_area` keeps Tab (two spaces), wraps long lines and reports Command/Ctrl-Enter; the Graph tab is
  editable (`Set_graph`, one "Edit text" entry); Command-Enter applies in every editable tab.
- Each viewport keeps its own orbit (`Environment.follow_focus`, `viewport_camera`); a camera following the viewport
  is written by the focused one only.  A click picks in the focused viewport's scene instance, selects a collapsed
  loop instead of a node inside it, and 2D editors pick the same way (a ray down onto the plane).
- Tests never wait on the clock for a cook: `Editor3/2.create ~await:true` blocks each frame on the cook it
  submits; bounded frame counts replace deadlines; deadlines left are failure bounds only.

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

The default shell is `Pxui_shell.Layout.default`: three independently collapsible
columns, view, graph, and inspector, with default flexible proportions 45/35/20 (the
default editor graph *is* this layout; a workspace's own `(graph editor ...)` replaces
it, see "Workspace shell (W10)").  Splitters retain ratios across window resize. An empty graph selection shows
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
truncate accessible SOPs. Command/Ctrl-D duplicates the selected bindings with fresh names (the copies keep
their wires between each other); copying across graphs is the text pane's copy and paste. Delete and Backspace remove
selected nodes or wires (an object leaves its scene's merge, a layer its World stack). `v` views the selected geometry
node in the viewport (a layout entry, separate from the graph's result) and the card carries a VIEW mark.

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

## Workspace graph pane (W4)

For a geometry object of a workspace document opened as a graph
(`Core.scope_name`), `Core` shows `Pxui_graph.Scope` instead of the flat
pane and routes `Leader.Scope_command` keys (the flat `Graph_command`s are
filtered out except `Add`, whose menu becomes one `Add_node`). `Core.sync_scope`
rebuilds the projection when the workspace document or `Core.probes` changes;
counts come from one recording evaluation per checked source. `probes`
(iteration per zone) is view state: not in `Document`, not in history. Moving
an item and collapsing a zone are layout edits (`Doc.layout_edit`, one
history entry, no lowering, no recook); `Syntax_edit` requests reduce
through `Doc.syntax_edit` as before. `sketches/flow_workspace` opens a case
and, with `FLOW_EXPORT=<dir>`, renders the editor to PNG frames.

Probes and footers (W5): `sync_scope` also keeps the recording evaluation
(`scope_key.evaluated`, one per checked source) and a `Flow_sop.Probe.t`
rebuilt only when the evaluation, the cook's geometry counts
(`Cook.summaries`) or, for a document with live nodes, the time changed; an
idle frame only compares the key. `scope_key.targets` are the geometry nodes at
their probes that `Cook.update ~probes` counts. A selected node drives
`workspace_inspector` (edits are `Set_arg` on the authored argument, iteration
clicks are `Probe_set`); keep that function free of model mutation like every
other Ui.frame builder.

Pane gestures (W13): `Scope.Frames_set` reduces to `Doc.layout_edit` on `frames` (history label "Frame");
`Scope.editing` joins the host's `text_focus`, so leader keys stay out of the pane's name, default and frame-title
fields. Keys: F2 rename or input default, Shift-G frame, Alt-Up/Down move a list item; a drag on empty canvas is a
marquee. `sketches/flow_workspace` scripts them with `FLOW_SCRIPT`.

## Viewport provenance (W6)

`Pick` reads `__flow_src` tags off the displayed geometry, casts a CPU ray
(`Pdk.Surface_index`, built at the first click and kept with the `Cook.piece`)
and tints by a per-corner `Cd`. A click (press and release within 4 points among
the events the UI did not consume) reaches `Core.pick` through
`VIEWPORT.pick_ray`; the highlight is `Core.lit_tags` (selection and probes)
handed to `Cook.update ?lit`, which prepares a piece again from its kept
`output`. Never recook or lower for a highlight.

## Workspace text pane (W7)

`Space l` from the list opens `Text_pane` for a workspace graph object (no
other document has a text projection). `Core.text` is its view state: tab,
Document draft, binding draft and the errors of the last refused apply; the
draft is never in the document. `Text_pane.view` runs inside `Ui.frame` and
only returns intents; `Core.apply_text` folds them after the frame. A Check &
apply goes through `Doc.text_edit` (whole text, layout and settings kept) or
`Doc.syntax_edit` with `Set_arg { key = Whole }` (one binding) and is one
history entry "Edit text" (`Core.install`, shared with `Core.syntax_edit`). The
text itself comes from `Flow.Lisp.print` and its span map; keep new text
features on that map, never on string search. Text entry is `Ui.text_area`
only.

## Workspace shell (W10)

The shell is a tree of panels, `Editor_core.Panels.t` (leaf, split, tile, float), drawn by
`Pxui_shell.Layout` and `Chrome`.  `Core` keys focus, pane roots and command scopes by
`Layout.panel` (`View key`, `Graph`, `List`, `Lisp`, `Inspector`, `Outline`, `Timeline`);
`Leader.scope` maps a panel to the scope of its commands (every viewport is `View ""`, the
list and lisp panels are the graph pane's), and never match a `column` or a fixed pane.

- The tree comes from the document: `Contexts.of_workspace` evaluates the `editor` graph
  into `Document.shell` (`tree`, `origins`, `named`, `views`), so undo restores it with the
  source.  A document without an editor graph uses `Core.shell.tree` (the host's `?layout`,
  resized locally, no history).  Never store layout anywhere else.
- Gestures are `Flow_edit` ops on the editor graph, one history entry each: `Set_layout_ratio`
  (a drag; the split is view state, `Core.shell.live`, until release), `Split_panel`,
  `Close_panel`, `Set_panel_kind` (the header menu).  They address a panel by its binding
  (`Document.origins`).  A panel made by a `for` is `Loop` (its header says so and the status
  names the loop); an inline one is not editable.  Add the op to `Flow_edit`, not to `Core`.
- Panel keys: `Space o` then `h` `v` (split), `x` (close), `g` `l` `t` `i` `u` `m` `w` (retype to graph,
  list, text, inspector, outline, timeline, viewport) act on the focused panel; `Core.update` turns them
  into the same `Chrome` intents as the header menu (`Leader.Panel_*`), so they share its refusals.
- Recovery (register E1): "Restore layout" (`Space z`) is host state outside the tree
  (`Core.shell.restored`: the default tree until the editor graph's tree changes or the key
  is pressed again).  A refused edit keeps the previous document and layout; an editor graph
  that hides everything is valid, so keep this command working with any tree.
- Graph, list and lisp panels are the graph pane's three projections: a `List` or `Lisp`
  panel draws its own, otherwise `Space l` cycles them inside the `Graph` panel
  (`projection` is normalised by which panels exist).  `(ui/graph "name")` names the pane's
  graph (`Document.shell.named`); an `Outline` row picks one; there is no graph cycling key.
  A panel kind draws once (the first leaf); a second says it is shown elsewhere.
- Viewports: every `View` panel draws the scene instance its `(ref scene :k v)` names.  An
  override gets objects of its own in the scene network (`Document.shell.views`, labelled
  `garden (v1.1.1)`), drawn only by that viewport (`Core.placed_pieces ~view`); the default
  instance is the primary scene.  The viewports share one camera, and handles, picking and
  the sketch overlay follow the focused one (`Core.active_view`).  Float is an in-window
  overlay (an inset of its parent); there are no OS windows.
- Build the gutters' drag targets last in `Core.update` (`Chrome.splitters`): a pane root's
  hit rectangle is created after the chrome and would shadow them otherwise.

## Bloom studio shell (W14)

`Navigator` (the Outline panel, titled Navigator) and `Bars` are private modules over the same immutable `Core`
model: both are built inside `Ui.frame`, return intents and never mutate it. `Core.navigator_params` is everything the
Navigator reads (the checked workspace, the open graph's projection, the probe records, the applied panel tree);
`Navigator.Open` sets `pane_graph` (which outranks a `(ui/graph "name")` panel) and selects and frames a node;
`Navigator.Set_default` is `Flow_edit.Set_input_default`. A document with an editor graph has a 28-point host bar:
`Core.bar_height` is the `?top` every `Pxui_shell.Layout.geometry`, `Chrome.update` and `Chrome.splitters` call passes, so
a test computing geometry passes `~top:Bars.height`. A bar or toolbar click that means a command sets `bar_action`, run
next frame like a palette pick; one that means an edit is a `Syntax_edit` change. `Bars.layout_text` writes the editor
graph of each shell layout (the `Set_graph` text), `Bars.top_button_rect` and `tool_rect` are the one source of a
button's place for the draw and for tests. Make defn (`Flow_edit.Make_defn`) is typed by `Core.defn_change`.
