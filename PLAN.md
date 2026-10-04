# Editor plan

No code in this pass. Nothing here is a rewrite. The shell already has one
document (the workspace text), one reducer (`Doc.syntax_edit` /
`Doc.layout_edit`), and panes that only return intents. The bugs are places
where a second representation disagrees with that document. Fix each one at
the function every caller already goes through.

What not to build: a new editor framework, a plugin registry, `Ty.Enum`,
auto-inserted conversion nodes, Bézier wires, bend dots, a color-picker
dependency, or a second "ref a node inside a graph" type.

## How a gesture moves

```
pane (Scope, Inspector, Chrome)   returns an intent, mutates nothing
        │
Core.update                       one dispatcher
        │
Doc.syntax_edit / layout_edit     one history entry
        │
Flow.Workspace.check              the text is the document
        │
Flow_sop.Lower                    checked term → Edit_graph
        │
Cook                              nil geometry cooks as "input is not connected"
```

Layout (positions, the VIEW flag, panel collapse) is beside the text, in
`Layout_by_path`. It is not a second graph. Two of the bugs below are layout
keys pretending to be graph results.

## 1. Crash: click with no viewport

Report: `/tmp/rays-crash/Rays_sketch____shattered_cube-20261002-143401-84883`

`Invalid_argument("Camera: viewport dimensions must be positive")` from
`Camera.screen_ray`, called by `Environment.update_with` on a click. The
window is 1200×760. The editor graph in that document is outline, graph, and
inspector. There is no `ui/viewport`. Undo label is "Retype panel".

`Layout.first_view` ignores a body of height 0. `Layout.panes` then uses
`(0,0,0,0)`. `view_bodies` already skips that. The pick fold does not. A click
the graph did not consume (the trace is a press at y≈15, on chrome) calls
`screen_ray` on the zero rect. `Camera.viewport_size` is right to reject it.
The editor is wrong to call it.

Fix: in the pick fold, a non-positive film is not a click. Same guard anywhere
else that passes `panes.view` into `Camera` (`frame_bounds` is the sibling).
Do not soften `Camera`. One test: an editor graph with no viewport, a left
click, no exception.

This is also the mouse-leave symptom in the trace (cursor sat at y=0). That
part is section 8. The crash itself is the zero film.

## 2. Open inputs are `nil`, and the checker rejects that shape

`E_MISSING_INPUT: exploded_view needs its in0 input` is the edit that was
rejected in the same session. The status line is "Graph edit rejected".

Two layers already disagree:

| Layer | Unconnected required geometry |
|---|---|
| Lisp check (`apply_kind`) | Error. The edit is thrown away. |
| Lower + `Edit_graph.instantiate_optional` | Missing slot becomes a placeholder that cooks as `disconnected_input`. |
| Eval of `nil` | `No_geo`. Lower already skips it (`E.No_geo`). |

`nil` is already a geometry value. `default_for Geometry` is already `nil`.
Disconnect of a typed geometry row already writes it. The add path does not:
`Core.scope_add` omits the argument when nothing wireable is selected, so
check refuses the whole add. You cannot place `exploded_view` until a wire
exists. You can write `(sop/exploded_view nil)` by hand, and that cooks as a
failed node, which is what we want.

The document rule is already written down (`document.ml`: disconnected SOPs
are editable; cooking the display is separate) and in the editor guide (the
menu must create a SOP with inputs still open). The checker is the holdout.

Fix, one concept: an open geometry input is the symbol `nil`.

- `scope_add` appends `nil` when it does not wire a selected name or the
  graph result. Do not invent a second "missing" flag.
- A missing required geometry slot in `apply_kind` is that same `nil`, not
  `E_MISSING_INPUT`. Otherwise a hand edit or a paste of `(sop/exploded_view)`
  still bounces, and the pane's empty socket (projection already draws one)
  can never be saved.
- Parameters with no default stay required. This is only geometry slots.
- Cook stays a per-node failure. The document stays. The existing
  placeholder message is the status, not a new error type.

Do not make every SOP input optional in the catalog. `[@sop.node_optional]`
is for inputs that are meaningfully absent (a scene object's parent). An
unwired `exploded_view` is not optional. It is unwired.

## 3. VIEW is a second result

`v` writes `layout.display`. The card paints VIEW from that. The viewport
cooks that node (`Core.display_node` overrides `network.displayed`). The
graph's lisp tail is a different value. `(ref shattered)` evaluates the tail.
In the shattered cube that tail is `exploded_view`. Pressing `v` on `fracture`
changes the picture and does not change what the scene object references.

That split was intentional (peek upstream, `u` restores the result). It is
the bug you are describing. The node marked VIEW is the output. The lisp
result is what `v` should set, because the scene follows the lisp, and you
switch the viewed node on purpose.

Fix: `v` is a syntax edit, not a layout write. The graph body's tail becomes
that binding. The VIEW mark is derived from the tail. `geometry_objects`
stops reading `layout.display`. `ref` and the viewport then name one node.

Refuse `v` on a node that cannot be the tail (inside a loop, not a binding).
The zone rules already say only the yield leaves. Undo is the way back, so
`u` does not need a secret restore. Old files that stored `layout.display`
keep working until the next `v`: honor the key if it is present, and clear
it when `v` rewrites the tail. No migrator.

Do not add a Houdini-style display flag plus an output flag. One result.

Consequence for the scene object: `(scene/geometry (ref shattered))` shows
whatever `v` last made the tail. You do not pick a node from the scene side.

## 4. The inspector cannot see that ref

`scene/geometry`'s geometry input is the positional `(ref shattered)`.
`workspace_inspector` lists catalog parameter fields only (transforms,
visibility, light color). It never lists input slots. On the scene object
named shattered there is no row for the ref and no way to point it at
another SOP graph.

The scene graph card already has the socket (`kind_rows`). The inspector is
the hole.

Fix: the same inspector draws input slots that are refs, as a choice of SOP
graph names that exist in the workspace, and the edit is `Set_arg` of
`(ref name)`. That is the picker. It is not a new reference type.

Do not add `(ref shattered fracture)`. Section 3 makes the node `v`'s job.
A scene-side node picker would be the second result again.

## 5. Custom SOPs and the add menu

The menu is `entries_of_factories` of one list:

- SOP graph → `Core.factories`, the list passed to `Editor3`/`Editor2.create`.
  Empty means `Sop_catalog.Editor.factories`. A non-empty list replaces the
  catalog. It does not append. `voxel_wall` does the prepend itself.
- Scene graph → `Objects.catalog` (geometry, camera, light). A custom SOP
  is not on this menu. You add it inside a SOP graph.
- World graph → `Layers.catalog`.

`[@@sop.register]` collects only inside `sop_catalog`. A module registered
from a sketch does not join the menu. `Workspace.main` (every `.rays`
sketch) calls `load` with no factories, and `declared_camera` hardcodes
`Sop_catalog.Editor.factories`. There is no registry you can push to after
`create`.

So a custom node is missing when any of these is true: it was registered
outside `sop_catalog`, the sketch is a bare `.rays`, `~factories` replaced
the catalog instead of prepending, or the menu is open on the scene graph.

Fix: the list given to `create` is the only catalog, and the three readers
(menu, check, lower) already share it when the host passes it. Thread that
same list through `Workspace.main` and `declared_camera`. Keep the prepend
rule, and say it on `create` in one line. Do not build a dynamic registry.
A sketch that needs its own SOP keeps a `main.ml` and passes
`custom :: Sop_catalog.Editor.factories`, which is what `voxel_wall` does.

## 6. `+` / `-` and conversions

`+`, `-`, `*`, `/`, `mod`, `min`, `max` take numbers. `any_num` already
accepts int, float, and vec3. The result is int only when every argument is
int; otherwise float. Eval coerces (`coerce_to`). Bool participates in
`Ty.fits` but not in `any_num`, so a bool into `+` is still a type error.

There is no string `+`. `str` concatenates, and `show` of a number is how a
number becomes text. `int` and `float` are already unary ops and already
sit in the Value section of the menu.

The conversion you are seeing is that implicit numeric coerce. It is not a
node, and it does not go to string.

Do not auto-insert `int` / `float` / `str` nodes on a wire. Do not add
`float+`, `int+`, `string+`.

Do this instead:

- Leave numeric `+` as it is.
- Text stays `str`. Using `+` for strings would hide `str` and make
  `+` of a number and a string a new ambiguity.
- In `value_entries`, group the existing ops into Math, Compare, Convert
  (`int`, `float`, `floor`, `round`, `ceil`), and Text (`str`). Labels on
  the menu. Same nodes.

## 7. Choices and color

Choice parameters already exist. `@sop.kind` is a `Choice_view`. Check
rejects a string that is not one of the labels (`:kind must be one of …`).
The inspector dropdown for `Choice_view` is already in `flow_fields`. Lisp
for those arguments is a string (`:kind "Dodecahedron"`). That is the lisp.
A `(choice "Dodecahedron")` form would be a second spelling of the same
string. Preferences use `(choice …)` in `Store`. SOP arguments should not
grow a copy.

What is actually missing:

- A graph input cannot be declared as a closed set. Types are
  `int`, `float`, `text`, …. Add that only when a graph input needs it,
  as labels on the existing input declaration, checked by the same
  `Choice_view` path. Not a new `Ty` constructor.
- `Port_type.of_field_kind` maps `Choice_view` to "no port type", so a
  choice is literal-only text. Correct. Do not make choices wirable until
  something needs to drive one.

Color is the same shape of gap, and it is a real missing control. A light's
color is three floats (`color_r/g/b`, 0–1). Lisp already accepts
`:color "#7dd3fc"` (`Ty.Color`, `color_of_text`) and lowers it to those
floats. The inspector then shows Red, Green, and Blue sliders. No swatch.

Fix: one inspector row when a parameter is a color (the existing three-float
color group, or `Ty.Color`). A hex field, a filled swatch, and the three
sliders behind it. Built from `Ui` boxes and the sliders we have. Not a new
panel kind, not a library. SOP colors that are already `#rrggbb` text use
that same row.

## 8. Wires

The product draws one orthogonal polyline per connection (`wire_points`).
Hit rectangles exist so a hover can highlight the wire. Nothing reads a
click on them. There is no selected wire. Delete disconnects the row under
the pointer, or deletes selected nodes. It does not delete a connection you
clicked.

The HTML prototype selects a wire on click, deletes it with `x`, and
Alt-clicks a bend square onto it. You do not want the square.

Fix:

- Click a wire selects that connection and clears node selection. View
  state in `Scope`, same as node selection. Not document data.
- Delete / Backspace on a selected wire is the existing `Disconnect`.
  For a geometry slot the fallback is `nil` (section 2), so the unplug
  saves.
- Option-click does not insert a point. Do not store bend points. The
  spec's Alt-click bends stay unbuilt.

Wire style is a property of the graph panel, which is already a lisp node:

```
(ui/graph)
(ui/graph :graph "shattered")
```

Add one optional keyword, `:wires`, values `rect` (today's polyline, the
default) and `straight` (one segment, port to port). Check it the way
`ui/split` checks `horizontal` / `vertical` (`E_RANGE`). The pane reads it
off the panel binding it is drawing. No new panel-config object.

Bézier stays out. `specification/flow.md` already says no curves, and a
third stroke style is a painter we do not need until `rect` and `straight`
both exist and `straight` is not enough.

Other panel keywords, same way, only when a control is real. `ui/split`
already has axis and ratio. Do not generate a schema framework for panels.
An editor graph is a lisp graph of the `ui/*` ops. New behavior is a
keyword on the op that draws it.

## 9. Exploded View scale

`amount` is the slider labeled "Uniform scale". Soft range is −0.95 to 1.2.
There is no hard max, so a typed number past 1.2 already checks as a
warning (`W_SOFT_RANGE`) and cooks. The slider is what feels stuck.

Raise `@sop.max` on `amount`. 8 is enough to separate pieces without a new
control. Leave the per-axis scale at ±2 unless that slider is the one that
is tight. One attribute, then `dune promote` the flow manifest.

## 10. Drag past the screen edge

Orbit and graph pan use `mouse_delta`. SDL stops delivering motion once the
cursor leaves the window, so a drag dies at the edge. Fly mode already
avoids this with `Sketch.set_relative_mouse` (`viewport3.ml`), which is
SDL relative mouse mode: deltas continue, the cursor is grabbed.

Use that while a viewport orbit/pan button is down, and while the graph
canvas is panning. Turn it off on release, on `WindowFocusLost`, and on
close. The cursor hides for the drag, as it does in fly mode.

Do not write a warp-to-the-other-edge loop. Relative mode is the platform
call already in the tree. A visible cursor that jumps to the opposite edge
is a different behavior. Add it only if hiding the cursor is wrong.

Sliders already track outside their own rectangle and clamp. They do not
need this. The crash in section 1 is not this bug. A drag that ends in a
click on a zero viewport is.

## Order

Each item is one change at the shared function, plus the one test that
fails if it regresses.

1. Section 1. The crash. Guard the pick. No behavior change when a viewport
   exists.
2. Section 2. Open geometry input is `nil`. Menu, checker, disconnect.
   Cook error stays on that node.
3. Section 3. `v` rewrites the graph tail. Delete the layout display as a
   second result. This is the only document-meaning change.
4. Section 4. Inspector shows the ref and lists SOP graphs.
5. Section 8, first half. Select a wire, Delete disconnects it, no dots.
6. Section 5. One factory list through `main` and `declared_camera`.
7. Section 7. Color row in the inspector.
8. Section 9. Exploded View soft max.
9. Section 6. Menu groupings only.
10. Section 8, second half. `:wires rect|straight` on `ui/graph`.
11. Section 10. Relative mouse during orbit and graph pan.

Sections 1–3 are the broken model. The rest are missing controls on models
that already exist. Stop after 3 if the goal is only "the document and the
picture agree."
