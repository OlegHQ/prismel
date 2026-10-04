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

`Environment` autosaves changed documents and viewport state through `Preset.save`
to one atomic `<presets>/state/<sha256>.plisp` recovery file per source path (or
workspace name). It coalesces edits at 2 Hz and flushes on close. Opening an
unchanged sketch preserves recovery. `Space b` offers "Last edited state" before
manual presets; loading validates and installs one undo entry. Failed writes
retain the pending state, report the error, and retry. Autosave does not rewrite
the source file.

Source polling reads content and SHA-256 at 2 Hz, regardless of mtime or inode.
The last observed digest suppresses repeated reloads of refused text. Read
failures and recovery use the status notice without changing the document.
Save reports read failures; a differing readable source still saves to a preset.
The digest check precedes atomic rename, so cooperating writers are needed to
exclude an external write in between.
Built-in workspace title, width, height, fps and seed fields apply on restart;
their schema labels and the `settings/config` inspector say so. Source/history
edits still save the requested configuration; the running host is not reconfigured.
Light intensity/color keep residuals and evaluate at timeline time during
composition; only their checked ports/values are retained by object ID. The
Environment keeps one resolved scene, keyed by authored geometry/drives/time,
without altering the history document or SOP/prepared caches. Failed evaluation
keeps that light's last successful values while healthy siblings advance, and
reports `E_CONTEXT_LIVE` with view/field attribution; recovery clears it.
Document installation and startup-window reading refuse other residual time values
in scene, World, settings and editor structs with `E_CONTEXT_TIME`. The diagnostic
names the graph/field. SOP/value drives and their static geometry references remain
supported; source/history are unchanged when an edit is refused.

## Workspace gestures added in Gap A (details in `specification/workspace/progress.md`)

- Command +/-/0 (`Leader.Ui_scale`) set the kit text size of every panel through `Ui.set_font_size`
  (8 to 18 points, rows follow); the graph pane has its own zoom and viewports have no text.
- Keys (graph pane): Command/Ctrl-C copies the selected bindings as `name expr` lines to the
  clipboard (`Scope.Copy_requested`, `Core.copy_bindings`), Command/Ctrl-X copies and deletes,
  Command/Ctrl-V parses the clipboard (pairs, or bare expressions named by their head) into
  `Add_node`s of the selected scope with fresh names, references between them renamed
  (`Core.paste_bindings`).  A node added from the menu is placed where the menu was opened
  (`Scope.scope_point`, one `Moved` in the same "Add node" entry).
  Command/Ctrl-D duplicates the selected bindings (`Flow_edit.Duplicate`, copies selected),
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
  editable (`Set_graph`, one "Edit text" entry); Command-Enter applies in every editable tab.  The text and the
  graph are two views of one edit: `Ui.text_area_submit ~on_click ~on_caret ~chips` report a click (with Command),
  the caret and colour bars; `Text_pane` turns them into `Open_graph` (Command-click a `(ref name)`: `Core.go`, the back
  stack), `Select_binding` (the caret in a Graph-tab binding selects its node, through the span map of the printed
  text; never while a draft is unapplied) and `Picker` (the colour control, a popup whose edits are `*_scrub`
  entries sealed on close).  Completion beyond the text shown comes from `Core.completion_names` (`Lisp_text.names`).
  Never match strings in the text for these: the lexer and the span map are the only readers.
- Each viewport keeps its own orbit (`Environment.follow_focus`, `viewport_camera`); a camera following the viewport
  is written by the focused one only.  A click picks in the focused viewport's scene instance, selects a collapsed
  loop instead of a node inside it, and 2D editors pick the same way (a ray down onto the plane).
- A viewport over another scene instance renders as its instance (`Core.view_root_opt` for the root, `Core.world ~view`
  and `Document.view_worlds` for the World; `Document.view_roots` for its render settings and its
  `:camera`); `Viewport3.film`, `view_camera` and `render` take the viewport's key and read that
  key's root (`Viewport3.look`), and `Environment` threads the key (`look_key` maps the hidden
  scene to the focused viewport).  `Renderer` keeps one slot per traced picture: viewports with the same
  scene, camera, film and setting share a tracer; the film is the root's resolution divided by 1, 2, 4 or 8
  that fits the gate in drawable pixels (`Renderer.film`), so a resize restarts accumulation only
  across a step; the focused slot renders every frame and the others take turns, one per frame
  (`Renderer.update ~focus`, `next_turn`); the sample cap (`max_spp`) is read per frame, never part of
  `Renderer.setting`.  A text edit that leaves the objects alone keeps `Document.scene` physically
  (`Contexts.of_workspace`) and a cook that returns every piece it had reports no change
  (`Cook.same_pieces`), so nothing recomposes and no tracer restarts. Every editor a test
  creates is closed (`E3.close`): each one holds worker domains and the runtime allows 128, so a leak shows as
  "failed to allocate domain" in whichever test runs last.
- Tests never wait on the clock for a cook: `Editor3/2.create ~await:true` blocks each frame on the cook it
  submits; bounded frame counts replace deadlines; deadlines left are failure bounds only.

## Follow and back

`i` follows the reference of the node selected in the graph pane (`Core.follow_target`: a `sop/material`
reads its `:material`, else the first `(ref name)` argument), `I` opens it in a floating graph
(`Layout_window` with kind `graph:name`), `Space j` jumps to any graph, Alt-click in a viewport follows
the surface's `shop_materialpath` (`Cook.pick_material`), a double-click on a node body is
`Scope.Activated`. Every follow goes through `Core.go`, which pushes `(level, pane_graph)` on
`Core.back`; `u` pops it (empty: up to the scene). `Core.route` is the header breadcrumb and the
crash dump's `route:` line. Rename and remove of a graph are `Flow_edit.Rename_graph`/`Remove_graph`.

## Layouts and windows

`(ui/switch panel... :active n)` holds the layouts of one editor graph; `Contexts` lowers it
transparently (the active layout is the tree, `Document.shell.switch` has every layout). Layout names
are `Editor_core.Panels.label`/`labels`, never stored. `Space [` (which-key rows `layout.0`..`layout.9`
are relabelled in `Core.routed`), `Space n` + kind and `Space o f` reduce to `Flow_edit.Set_layout`,
`Layout_new`, `Layout_remove`, `Layout_window` and `Layout_float` on the editor graph at the root of
the workspace; `Set_layout` merges into one `Burst` history entry. See `specification/workspace/iteration.md`.

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
drag pans, wheel, trackpad scroll and pinch zoom at the pointer, [Home] frames all, and
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
`Core.graph_of_object` also matches stable compiled root IDs: a scene/camera edit rebuilds the lowering
while `Contexts` preserves unchanged object networks, so physical network identity alone is insufficient.
Inline `result` geometry cards accept `v` too. Viewport-focused `F` frames the node VIEW shows;
leaving the network with `u` restores its current graph result.
Named SOP handles use the compiled owner's transform and write its source argument,
even with scene navigation open. Scene-level viewport framing uses only focused
instance bounds and works in viewport-only layouts; an empty instance has no target.

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

`Space l t` on the graph panel (or a `Lisp` panel) shows `Text_pane` for a workspace graph object (no
other document has a text projection). `Core.text` is its view state: tab,
Document draft, Selection draft, the errors of the last refused apply, the wrap flag and the
right-click menu; the draft is never in the document.
Each draft retains its base workspace. Apply and scrub refuse a changed source with
`E_DRAFT_CONFLICT`, keeping the draft; Document also checks saved layout/settings. A
successful live scrub advances its base, and discard or successful reload clears it.
`Text_pane.view` runs inside `Ui.frame` and only returns intents;
`Core.apply_text` folds them after the frame. A Check &
apply goes through `Doc.text_edit` (whole text, layout and settings kept), `Set_graph` (the Graph
tab) or, for Selection, patch named root bindings of the shown closure into one candidate graph
(`Text_pane.selection_form`, `Core.binding_edit`), checked/lowered once by `Set_graph`; omitted
bindings stay and changed closure results or duplicate names are refused. Each is one history entry "Edit text" (`Core.install`,
shared with `Core.syntax_edit`). The text itself comes from `Flow.Lisp.print` and its span map;
keep new text features on that map, never on string search. Text entry is `Ui.text_area` only,
with `Lisp_text.language` (an error-tolerant lexer: colours, rainbow brackets, the lit pair at the
caret, Enter indentation, paired brackets, ranked completions for the token at the caret over a
`Lisp_text.vocab` of the catalog, a description of the token under the pointer, and the number a
drag changes, and parinfer's indent mode as the language's `rewrite`, `Lisp_text.parinfer_text`, on by
default and toggled by the pane's right-click menu, `Text_pane.parinfer`); the widget stays
language-free.  Typing opens the completion popup (kinds of the
graph's context, a kind's parameters and choices, forms, operators, bindings in scope; Up/Down,
Tab/Enter, Escape).  A number dragged sideways applies the text on every frame of the drag
(`Text_pane.Doc_scrub`/`Graph_scrub`/`Binding_scrub`, `Core.scrub_merge`, one "Edit text" entry
sealed on release) so the viewport follows the drag; the draft stays until the drag ends.

## Workspace shell (W10)

The shell is a tree of panels, `Editor_core.Panels.t` (leaf, split, tile, float), drawn by
`Pxui_shell.Layout` and `Chrome`.  `Core` keys focus, pane roots and command scopes by
`Layout.panel` (`View key`, `Graph`, `List`, `Lisp`, `Inspector`, `Outline`, `Timeline`);
`Leader.scope` maps a panel to the scope of its commands (every viewport is `View ""`, the
list and lisp panels are the graph pane's), and never match a `column` or a fixed pane.

- The tree comes from the document: `Contexts.of_workspace` evaluates the `editor` graph
  into `Document.shell` (`tree`, `origins`, `named`, `views`), so undo restores it with the
  source. `Workspace_doc.editor_graph` chooses the graph named by `layout.editor`,
  defaulting to the first editor graph. The Shell layouts menu switches these names
  in one undo entry; templates add a new graph. A document without an editor graph
  uses the host's `?layout` until its first panel edit writes the tree into an editor
  graph. Never store layout anywhere else.
- Gestures are `Flow_edit` ops on the editor graph, one history entry each: `Set_layout_ratio`
  (a drag; the split is view state, `Core.shell.live`, until release), `Split_panel`,
  `Close_panel`, `Set_panel_kind`, `Dock_panel` (the header menu and drag targets).
  They address a panel by its binding (`Document.origins`); inline calls are bound
  first. A panel made by a `for` is `Loop`: retyping changes its template; moving
  one copy into another split is refused. Add syntax edits to `Flow_edit`, not to `Core`.
- Disclosure and floating window bounds live in `Layout_by_path.panels`, keyed by
  editor graph and binding (or tree path for a loop copy). `Core.Panel_state` reduces
  Chrome's toggle/window intents in the same document history. Leader visibility
  keys use these intents too. The dotted header handle moves a panel; dropping at
  another docked panel's edge writes a split. The menu's Dock returns an undocked
  panel to its original place. Window mode floats inside the editor.
- Floating roots use `Ui.to_front ~order` for painting and hit precedence together.
  `Ui.scene ~under` inserts each floating viewport's native Scene at its body root;
  every pane still uses the same UI frame, hit tree, capture and renderer.
- Panel keys: `Space o` then `h` `v` (split), `x` (close); `Space l` then `g` `l` `t` `i` `u` `m` `w`
  (retype to graph, list, text, inspector, outline, timeline, viewport).  They act on the focused
  leaf (`Core.focus_path`, the one clicked, so the second panel of a kind closes itself, not the
  first); `Core.update` turns them into the same `Chrome` intents as the header menu
  (`Leader.Panel_*`), so they share its refusals.  Two exceptions: `Space l g` `l` `t` on the
  graph panel only switch its projection (view state, no edit), and a document without an editor
  graph gets one written from the layout it shows (`Bars.tree_text`, every leaf and split a
  binding; the scene graph it views is adopted first, as `Add_node` does) before the edit, in the
  same history entry.  There is no projection cycling key.  `Space m` flips the World's map view.
- Recovery (register E1): "Restore layout" (`Space z`) is host state outside the tree
  (`Core.shell.restored`: the default tree until the editor graph's tree changes or the key
  is pressed again).  A refused edit keeps the previous document and layout; an editor graph
  that hides everything is valid, so keep this command working with any tree.
- Graph, list and lisp panels are the graph pane's three projections: a `List` or `Lisp`
  panel draws its own, otherwise `Space l l` / `t` / `g` pick one inside the `Graph` panel
  (`projection` is normalised by which panels exist; the scene level starts as a list).  `(ui/graph "name")` names the pane's
  graph (`Document.shell.named`); an `Outline` row picks one; there is no graph cycling key.
  A panel kind draws once (the first leaf); a second says it is shown elsewhere.
- Viewports: every `View` panel draws the scene instance its `(ref scene :k v)` names.  An
  override gets objects of its own in the scene network (`Document.shell.views`, labelled
  `garden (v1.1.1)`), drawn only by that viewport (`Core.placed_pieces ~view`); the default
  instance is the primary scene. Each viewport keeps its own orbit; handles, picking and
  the sketch overlay follow the focused one (`Core.active_view`).  Float is an in-window
  overlay (an inset of its parent); there are no OS windows.
  Unique named viewport bindings key transient state by editor graph/name;
  docking preserves both panel bindings and introduces a split wrapper. Inline,
  looped and repeated bindings fall back to placement keys; renaming changes the
  authored key. `Document.shell.preview_sources` retains panel origin, authored
  ref (when available), and evaluated instance. Auxiliary preview objects are
  read-only; their inspector and shared reconciliation explain the source-edit route.

`Viewport3` owns the shared Renderer section (Raster, Wireframe, Path traced),
saved with viewport preferences. A sketch's existing renderer setting feeds the
same picker and retains its custom rendering; other 3D/SOP editors render through
the common adapter without recooking geometry on a mode switch. The adapter keeps
at most 64 converted meshes and 16 viewport tracers, releases them on close or mode
change, and reports unsupported tracing operations in the status strip.
Errors name each failed viewport and identify retained traced output as stale.
Failed mode changes do not retain output from a different renderer mode; recovery
clears the errors. Crash reports include renderer errors.
Standalone 2D art sketches keep their own drawing paths.
- Build the gutters' drag targets last in `Core.update` (`Chrome.splitters`): a pane root's
  hit rectangle is created after the chrome and would shadow them otherwise.

## Bloom studio shell (W14)

`Navigator` (the Outline panel, titled Navigator) and `Bars` are private modules over the same immutable `Core`
model: both are built inside `Ui.frame`, return intents and never mutate it. `Core.navigator_params` is everything the
Navigator reads (the checked workspace, the open graph's projection, the probe records, the applied panel tree);
`Navigator.Open` sets `pane_graph` (which outranks a `(ui/graph "name")` panel) and selects and frames a node;
`Navigator.Set_default` is `Flow_edit.Set_input_default`. There is no host bar: panels fill the window above the
status strip, and every global action is a leader key and a palette row (`Space [` for layouts, `Space k` for the key
sheet). A graph-header toolbar click that means a command runs next frame like a palette pick; one that means an
edit is a `Syntax_edit` change. `Bars.tool_rect` is the one source of a toolbar button's place for the draw and for
tests. Make defn (`Flow_edit.Make_defn`) is typed by `Core.defn_change`. A "Refused · ..." status clears with the
next successful edit.

The viewport reads the renderer, resolution and samples from the scene root (`Document.root`):
`Viewport3` takes the root's renderer when its text has a root (`homes.root`), else the sketch's
`renderer` setting or the viewport preference; the Render section of the empty-selection inspector
edits the root through `Core.set_root` (the first edit writes it).  A composition gesture that
writes several things (a SOP graph and its object) is one `Syntax_batch` and one undo entry.

## Carry (flow.md §7.12)

A payload in flight (`Core.carry`, `carry.ml`). `y` (`Leader.Pick_up`) or a press on a Navigator row
(`Ui.carry ~from`) holds a Flow value (`(ref cobalt)`, kind `material` or `sop`). `Carry.put` is the
only place that knows what a payload does at a place (`Carry.place`: a node, a graph's canvas, an object,
a surface, a viewport): it builds the ops (`Set_arg`, `Add_node` + `Connect`, `Scene_sync.add_geometry`)
and runs them through `Doc.syntax_batch`, so the checker is the target test; do not list what a widget
accepts. `Core.update` is `carry_step` (the carry's turn: its keys, the ends of the gesture, the preview) then
`update_frame`. While a target is hot `value.doc` is the edit applied to a scratch copy and the history
is not touched (`Core.doc` is the history's present again only after the carry); the original is held
in the carry, and cancelling puts it back physically (nothing to undo). The put is
`install ~label:"Put" ~merge:Step`. While carrying `update_frame` keeps only navigation (`carry_allowed`
actions, `Selected`/`Activated` scope changes, outline `Open`, `Go`): every other change is dropped,
and `scene_edit`, `set_settings` and `set_root` ignore the host, and `Environment.autosave` never saves
a preview. Panes report what is under the pointer (the graph pane's `Drop_over`/`Dropped`, the inspector's
`@ref:material` choice through `Inspector.flow_fields ~on_choice`, a viewport root); the report is read
the next frame. A viewport is resolved by the host: `Environment` casts the pointer ray and calls
`Core.carry_over_surface`, which picks on the pieces cooked for the original document (never on the
preview) so the surface's material does not flip with the preview. Preview budget `carry_budget`
(a field of `Core.t`, `?carry_budget` of `create`, default 0.5 s; tests pass 0.): a put whose apply or
whose last cook takes that long is `Held_back` (said, not shown; `test_materials` exercises it). The key
route's letters are `carry_letters`; they and Enter/Escape are removed from the frame the rest of the
editor sees. The strip's line is `carry_line`. Tests: `test/test_materials.ml` (carry_tests).
Kinds are `material`, `sop`, `scene` (a scene graph, from a Navigator row or `y`) and `camera` (a bare
binding name, from `y` with the object selected). `Carry.viewports` lists the panels of the editor
graph's layout (`Doc.panel_node` binds a panel written in place); a scene re-points the panel, a camera
is the `:camera` of the root of the scene the panel shows. `Carry.Text` is a byte of the text pane's
shown text (`Text_pane.Carry_over` from `Ui.text_area_submit ~on_drop`): the pane reads the carry's
original document while carrying so the byte does not move, `Text_pane.graph_op` is the one reading of a
Graph or Selection text (shared with `binding_edit`/`graph_edit`), and a tab with a draft is `Drafted`
(refused). The key route has no text target. The strip's reminder (`hint`) is the carry's own, so it
shows with the prompt. Not built: a Finder file drop (no place takes a path).

## Gesture echo and Copy

`Echo.words` is a gesture's op in the words of the text; `Core.update_frame` sets the notice to
`Wrote <words>` for a `Syntax_edit`/`Syntax_batch` (the same strip slot the carry's preview uses; an
authored note from `Scene_sync` wins). `Leader.Copy_lisp` (palette only) puts `Preset.text` on the
clipboard, the text Command-S writes.
