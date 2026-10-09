# Rays Flow: the workspace editor

## 1. Status and authority

This file describes the code as it is. A workspace is one text, the `.rays` Lisp; every
graph, card, wire and panel is derived from it, and every gesture is a checked rewrite of
it. Nothing is stored beside the text except layout.

What is normative, and where:

| Subject | Specified in | Implemented by |
|---|---|---|
| The language's forms, types, loops, functions, macros, time rules | `workspace/iteration.md` §2 and §7, with the rule register `workspace/ambiguities.md` | `Flow.Syntax`, `Flow.Macro`, `Flow.Workspace`, `Flow.Eval` |
| The reader, the printer, argument rules, metadata, the editor graph's layout forms | this file, §11 | `Flow.Syntax`, `Flow.Lisp`, `Flow.Workspace`, `Editor_document.Contexts` |
| The document, layout, exposure, the graph pane, its gestures and keys, carry, the views | this file, §3 to §10 | `Editor_document`, `Flow_graph.Flow_edit`, `Flow_graph.Projection`, `Pxui_graph.Scope`, `Rays_editor` |
| Lowering and live values | this file, §13 | `Flow_sop.Lower`, `Flow_sop.Value_lane` |
| Materials | `workspace/materials.md` | |
| The kit the pane is drawn with | `pxui.md` | `Pxui.Theme`, `Pxui.Ui` |

Section numbers are stable because code comments cite them (§5.1, §6.4, §7.5, §7.7, §7.12,
§11.11); a number whose section was removed is not reused.

Two HTML studies are behavioural references and never product code or a web fallback:
`specification/flow/prototype/` (the first canvas study, older than the workspace: its value
nodes and grouped definitions were never kept) and `specification/workspace/prototype/` (the language
and zones). When a study and this file disagree, the code and this file win.

If an implementation shows that this file is wrong, change it in the same change as the code
and record a decision in §18.

## 2. Scope and vocabulary

In scope: the workspace document; the graph pane and its keys; the list and text views; the
inspector's role; exposure; carry; the reader and printer; the layout forms; lowering and the
live value lane.

Not built (do not add without a spec change): Bézier wires; authored wire bends and wireless
wires; per-element fields; zoom-driven detail; any Python or JavaScript in the build.

| Term | Meaning |
|---|---|
| workspace | The one `(workspace name ...)` form of a `.rays` text: graphs, `defn`s and `defmacro`s |
| graph | `(graph name :context c [inputs] body)`; a `defn` is a function with the same body shape |
| context | What a graph is about: `sop`, `value`, `scene`, `world`, `settings`, `editor`, `material` (`Flow.Context`) |
| kind | A catalog node type, `namespace/key`: a SOP factory (`sop/box`) or a kind `Editor_document.Contexts` generates from the scene, World and settings schemas |
| operator | A built-in call the checker types itself (`+`, `range`, `value/rand`, `scene/object`, `ui/split`); `Flow.Workspace.op_signature` |
| path | The lexical identity of a binding, `["flower"; "ring"; "u"]` (§3.4) |
| node | A call of a kind or operator drawn as a card: bound in a `let*`, or written in an input (a nested node) |
| zone | A bound `for`, `fold`, `scan`, `sum`, `let*` or `fn`, drawn as a region with its own scope |
| row | One input of a node as the pane draws it: a slot, a keyword, a list item, a record field |
| chip | What a row shows for what is written in it: nothing, a constant, a name (a wire), or inline text |
| layout | Per-path view data saved after the workspace: positions, levels, pins, collapsed zones, frames, panel state (§4.1) |
| level | `point`, `chip`, `card` or `full` (§6.4) |
| probe | The iteration of a zone that footers and the viewport highlight show |

Catalog inputs may have a fixed required/optional prefix and a final repeated
slot. An optional repeated slot permits zero extras. Repeated geometry inputs
accept individual nodes or a list with a fixed length, including through `map`.
The graph draws each positional extra, a named list row when present, and an
add row after the fixed prefix. Connecting that add row fills missing fixed
positions with `nil`; disconnecting extras preserves the fixed slot identities.

## 3. Document model

### 3.1 Contexts

`Flow.Context.t` is an abstract registered ID. Descriptors supply each context's
result type, value support, label, color, group and catalog prefix. A graph
declares its context; a kind belongs to one (the namespace of its qualified name) and a call
of a kind from another context is `E_WRONG_CONTEXT`. No kind is an `Editor` kind: an editor
graph sees the value operators and its own `ui/` operators (§11.11). `(ref name ...)` reads
another graph, with input overrides.

### 3.2 Port types and coercions

The structural types of `Flow.Ty.t` are `Float`, `Int`, `Bool`, `Vec2`, `Vec3`, `Vec4`, `Text`,
`Color` (text or vec3; only catalog parameters ask for it), `List`, `Array`, `Record`, `Fn`
and `Any`. Domain types use `Named of string`; registered names include geometry,
drawing, scene, world, settings, panel, editor and material. `Ty.fits`
decides whether a value may be used where a type is expected: numbers and Bool interconvert,
numbers widen to a vector, a record fits when it has every wanted field.
Vector literals have two, three or four numeric components; widths remain
distinct. Vector arithmetic broadcasts a scalar and rejects mixed widths with
`E_TYPE`. Components are `.x`, `.y`, `.z`, `.w` up to the vector's width.
The reference evaluator and packed CPU programs execute all three widths;
packed arrays store interleaved xy, xyz or xyzw components. Maps and loops can
produce these arrays from existing array sources, and `(array vec2)` / `(array
vec4)` annotations accept them. The Metal emitter uses the same scalar register
instructions for each component. There are no new array constructors or kernel
instructions; GPU eligibility remains governed by the checker.

A catalog parameter's port type is `Flow.Port_type.t` (`Geometry | Float | Int | Bool |
Vec3 | Image | Fn of Ty.fn_signature`); text and choice fields have none and take literals only.
A function signature declares parameter and result types, including records and arrays.
The checker retypes the function body for that port and retains each call's checked body
with the original callable's lexical captures. A bare `fn` annotation stays uninstantiated;
function values stored inside records or returned from functions still raise `E_FN_ESCAPES`.
Generated Fn/Image keyword inputs remain physical SOP slots; they have no scalar
Param fields or drives. Their default function body projects as an editable Fn
zone. Function resources carry captured geometry dependencies and an owned bulk
runner; packed float/vec3 arguments compile when the consumer supplies its columns.
Unsupported packed signatures or bodies return `E_KERNEL_FORM` at preparation.
Images and functions cannot be driven by scalar values. A scalar value reaching a
parameter is coerced by `Port_type.coerce`, then normalised to the field's hard bounds
(`Flow_sop.Port.normalize`):

| From → to | Rule |
|---|---|
| Int → Float | IEEE double conversion |
| Float → Int | finite values round half up (`floor (x + 0.5)`) and saturate the machine int range; a non-finite value is `E_TYPE` |
| Float or Int → Bool | nonzero is `true` |
| Bool → Float or Int | `true` is 1 |
| Float, Int or Bool → Vec3 | broadcast to all three components |
| Vec3 → scalar, Geometry ↔ anything else | rejected (`E_TYPE`) |

### 3.3 Kinds

- **SOP kinds** are the registered factories (`Sop_catalog.Editor.factories`), symbol
  `sop/<key>` where `<key>` is the factory's stable key verbatim (`uv_sphere`,
  `noise_displace`). The PPX rejects a key or slot name that does not match
  `[a-z][a-z0-9_]*`. `Flow_sop.Catalog.of_factories` turns them into the checker's
  `Flow.Check.catalog`.
- **Scene, World and settings kinds** are descriptors `Editor_document.Contexts`
  builds from the editor's own schemas and passes as `~extra`.
- **Operators** are built into the checker and the evaluator. The value operators any graph
  may call are `Flow.Workspace.value_ops` (arithmetic, comparisons, `range`, `linspace`,
  list operations, `value/rand`, `value/hsv`, `value/lerp`, `value/polar`, ...); they are the
  value part of the add menu. `material/standard`, `scene/merge` and the `ui/`
  forms are operators of their contexts.
- A short name resolves within the graph's context (`Flow.Check.resolve_kind`); a kind's
  aliases, when the manifest lists any, resolve to it. A catalog kind may be passed as a
  function value: `(map sop/facet xs)`.

### 3.4 Identity

A node is identified by its `Flow.Workspace.path`: the graph name (or `def:name`), the zones
down to it, then the binding name. Reserved segments: `:x` a loop variable or parameter,
`@result` a body result, `~for` / `~let` / `~fn` an unbound inline form (a second one under
the same binding is `~for~1`, then `~for~2`). A nested node has no binding: its leaf is the
holder's leaf, `#`, and the input (`result#0`, `result#0#:cutters`;
`Flow_edit.nested_leaf`). Inline higher-order calls and their function inputs use
these same leaves: `result#2#0` is the function in input 0 of the map in input 2,
and `result#2#0/shift` is a binding in its body. Selection, probes and layout are keyed by path, so they survive
every edit that keeps the path; `Flow_edit.remap` says where a key goes after a rename or a
hoist.

### 3.5 Edits

Every gesture is one `Flow_graph.Flow_edit.op`. `Flow_edit.apply` rewrites the syntax tree,
prints it canonically, parses it again and checks it with `Flow.Workspace.check`; an edit
that does not check is refused whole and nothing changes. `Editor_document.Workspace_doc.edit`
does this for a document and moves layout keys in the same transaction. Comments travel
with the binding they precede.

The ops are the list in `flow_edit.mli`: `Set_arg`, `Connect`, `Disconnect`,
`Set_input_default`, `Unfold`, `Fold_into`, `Wrap` (Repeat, Iterate), `Hoist`, `Rename`,
`Make_local_fn`, `Make_defn`, `Make_macro`, `Inline_macro`, `Toggle_bypass`, `Set_note`,
`Add_item`, `Move_item`, `Add_field`, `Add_node`, `Delete_nodes`, `Duplicate`, `Set_graph`,
`Remove_graph`, `Rename_graph`, `Group_merge`, and the layout ops of §11.11.

`^:bypass` on a call passes its first input through; the checker refuses it on a call whose
first input does not fit its result (`E_BYPASS`). It never reaches lowering.

## 4. Layout, view state and history

### 4.1 Layout (saved with the document, undoable)

`Editor_document.Layout_by_path.t`, written as one `(layout ...)` form after the workspace:

```lisp
(layout
  (editor "studio")
  (panel ["studio" "network"] :collapsed false :window [500 80 620 450])
  (node ["g" "ring"] :at [120 48] :level "full" :pinned true :collapsed true :rows {:radius false})
  (frame ["g"] "Legs" :at [0 0] :size [200 100]))
```

| Field | Meaning |
|---|---|
| `editor` | the selected editor graph, for an older file with several (§11.11); the first by default |
| `panels` | disclosure and floating-window bounds of a panel, by editor graph and binding |
| `at` | a node's position inside its scope, on the 24-point lattice |
| `level`, `pinned` | a node's detail level (absent: a card) and whether `o` pinned it |
| `rows` | per node, a row pinned onto its card or off it, by label |
| `collapsed` | a zone folded to its card |
| `frames` | titled rectangles of a scope |

There are no bend, wireless or display entries. A file that still has `bends`, `wireless` or
`display` entries reads, and the entries are dropped. An entry whose path is not in the
checked workspace is dropped on load and after every structural edit, and so is an
`(editor "x")` that names no editor graph; neither is an error.

### 4.2 View state (not saved in the document, not undoable)

Selection, hover, pan and zoom, the selected wire, a drag in progress, the open macro lens
and its step, letter hints, probes, and each panel's own state (§11.11 "Panels are
instances"). Guide on or off is a user preference (`Editor_core.Store`). Viewport navigation
is view state too, including when the camera object has `follow_viewport` set: the motion
writes the camera node without a history entry.

### 4.3 History

Each gesture is one `Editor_core.History` entry whose label reads "Undo <label>". The label
of a syntax edit is `Flow_edit.label` (`Edit value`, `Connect`, `Disconnect`, `Unfold`,
`Fold`, `Repeat`, `Iterate`, `Move out`, `Rename`, `Make function`, `Make macro`, `Bypass`,
`Add node`, `Delete`, `Duplicate`, `Resize panel`, ...). Merging:

| Gesture | Merge |
|---|---|
| Scrubbing an argument or an input default, typing a note | `Gesture` keyed by node and input (`Flow_edit.gesture`): one entry until the drag seals |
| Dragging a number in the text pane | one `Gesture` for the drag |
| Switching layouts by key | `Burst`, 1.5 seconds |
| Everything else (connect, delete, wrap, level, pin, frame, move) | `Step` |

A layout edit made by a release (moved nodes, a resized frame, a docked panel) is one entry.
`v` and the iteration selectors are view state and make no history entry.

### 4.4 Presets

A preset is one s-expression file (`.rays`), the same text a workspace sketch is written in:
the `(workspace ...)` form with its comments, then optional `(layout ...)`,
`(settings :name value ...)` for settings that differ from their default, and `(view {...})`
for the environment's camera and render settings. `Workspace_doc.to_text` keeps comments
between and after the root forms and keeps a `(view ...)` form verbatim. There is no JSON and
no version number. A file that does not parse, check or lower is rejected without changing
the installed document. An unknown or repeated root form is `E_DOCUMENT_FORM`; a layout or
settings form that does not read is `E_LAYOUT` or `E_SETTINGS`.

## 5. Exposure: which rows a card shows

### 5.1 The rule

`Flow_graph.Exposure.shown` is the one place the rule lives. For one row, in order:

1. A geometry slot shows. The first slot of a node kind is the header's in-port, not a row.
2. A driven row (a wire, an expression or a nested node is written there) shows. A pin
   cannot hide it.
3. If the row has a pin (`layout.rows`), the pin decides.
4. A row with something written in the text shows, the schema default included: what the
   Lisp says is drawn. Taking a wire off a named argument writes its schema default, so the
   row stays.
5. A primary row (§5.2) shows.
6. Otherwise it is hidden.

The canvas card (`Projection.row_shown`) asks the rule with `primary = false`: a Card is its
header plus the rows that are wired, written or pinned, and there is no `+ N more` row. A
list item, a macro hole and a binder always show; the `+` row is not a card line. Level
`full` lists every row under its folder labels. The inspector's pin toggle writes
`layout.rows` (`Pin row to card` / `Unpin row from card`).

### 5.2 Primary rows

`[@sop.primary]` on a field sets `Param.field.primary`; the manifest records it and
`Flow.Check.parameter.primary` carries it.

### 5.3 Vec3 grouping

Literal Vec2/Vec3/Vec4 values use the same grouped numeric field, with two,
three or four editable cells. `Flow_edit.Set_arg` addresses a component by
its zero-based sub-index; editing preserves the literal's width. Vec2/Vec4
ports use the kit's vector ink. Catalog parameters retain the declaration
grouping below; Vec2/Vec4 do not expand `Port_type`.

`[@sop.vec3 "center"]` on three float fields groups them into the vec3 parameter `center`
with components x, y, z. The record keeps its three fields, so cook code does not change;
`Param.field.vec3 : (string * int) option` is the group name and component index, and
`Flow_sop.Port.parameters` checks the same grouping invariants as the PPX. The keyword is
the group name (`:center [0 1 0]`); the underlying field names are not addressable. When the
common prefix already names another field the group takes another name (Ray's
`direction_vector` beside its `direction` choice).

## 6. Canvas

### 6.1 Direction and automatic layout

Data flows left to right. `Projection.layout` places a scope: columns by dependency depth,
graph inputs first and the return last; a node stacks below the previous one of its column.
Columns sit on a 288-point pitch (a 196-point card plus a 92-point gap, rounded up to the
24-point lattice). A saved position (`layout.at`) overrides the computed one. A zone's size
comes from its inner layout, recursively. There is no crossing minimisation.

### 6.2 Node geometry (logical points, kit font, 24-point rows)

Card geometry is the kit sheet's box model, measured against its render: card width 196
(`Projection.node_width`), header 24 overlapping the 1-point border, rows of 24 from
`Projection.body_top`, 4 points of padding under the last row (`card_pad`), and a 24-point
footer row only when the host has probe records (`Projection.layout ~foot`). Ports are
8-point circles centred on the card's edge.

- A **Card** is its header plus the rows of §5.1. A **value card** (a literal binding,
  `Projection.value_card`) is the header alone: name, the value field, the out-port.
- The footer (value, sparkline, cook time, as in `1 204 pts · 0.003 s`) is drawn on Full
  only; the cook time is `Probe.geometry.seconds`.
- Boxes are laid out at the level the node was given (`shown`, never changed by the zoom): a
  point is as wide as its name at the zoom's font, a chip is the header. Ports, wire ends,
  obstacles and hit boxes all read that one box.
- Positions sit on the 24-point dot lattice (`Projection.lattice`, `snap`); a zone's cards,
  not its edge, are on it.
- A zone is a tint, a 1-point edge, a label row (the kind, the binder, `in <source>`) and
  the iteration selector; accumulators, further loop variables and parameters are rows under
  the label row, drawn only when the loop has them (`Projection.extra_rails`). A loop over
  `sop/point_list` or `sop/piece_list` says `by index` or `by <key>` in its header.

### 6.3 Wires

Conditionals keep their test rows on the card and draw a `Branch` zone per
arm. `x#then` and `x#else` identify the two arms of `if`; tested arms of
`cond` and `case` continue as `x#then~2`, `x#then~3`. Their contents are ordinary
scope nodes, with a `when`, `is` or `else` rail and a `then` yield. They have
no iteration selector and the probe tints the selected arm. Collapse and body
edits use the same paths, boxes and history as other zones.

The card menu and keymap expose Wrap conditional (`Shift-I`), Add arm
(`Alt-A`) and Delete first arm (`Alt-Delete`). An inserted cond arm starts
with `false`; case starts with a literal of the existing test's kind.
The final else stays. Arm insertion/deletion remaps the remaining arm paths.
Bypass on `if` selects its then arm; `cond` and `case` cannot be bypassed.

- A wire is one straight segment from port to port, 1.5 points in the port colour, drawn
  with `Ui.line`. No curves.
- When a card is in the way it gets one bend (a 5-point square): horizontal out of the
  source, then a diagonal into the port, the bend 72 points before it. Only when no one-bend
  way is clear does the wire go round above or below, 24 points clear. A zone's label row
  and bottom edge are obstacles. Bends are computed, never authored or saved.
- `:wires "rect"` on a `ui/graph` panel keeps the older orthogonal routing.
- A fold's feedback is a dashed wire.
- Hovering a connected port highlights its wires; hovering a wire highlights that
  connection. Wire hit boxes join the shared PXUI hit tree behind the cards.

### 6.4 Levels of detail and zoom

`Projection.level = Point | Chip | Card | Full`, stored by path (`layout.level`, `pinned`).

- `point`: a 14-point disc and the name.
- `chip`: the header with a `+N` count of the rows with something written.
- `card`: the header plus the rows of §5.1 (the default).
- `full`: every row under its folder labels, plus the footer.
- Zones and value cards have no level.
- Zoom range 0.25 to 2.5, at the pointer. The zoom never changes a node's level: a card
  stays a card with its rows at every zoom, only smaller. `o` opens the selection one level
  and pins it, `p` points it or goes back to the level it had; `⇧O` returns every node to a
  card and `⇧K` points every node, or puts every node back.

### 6.5 Colour and type

A node's type square, its ports and its wires take the colour of the type
(`Pxui_graph.Node_menu.port_color`, from `Pxui.Theme.ports`: geometry is the theme accent;
float, int, vec3, bool, text, function and record have their own; a list draws its elements'
colour). The selection is accent corner brackets, a bypassed card is hatched, the node the
viewport shows wears an accent flag, a drop target is dashed, a node the checker or a cook
refused wears the failed state with the diagnostic's code (`Scope.with_failed`).

### 6.6 Hit testing and PXUI

Every node, row, socket, field and button is a `Ui.box` keyed by stable ids. There is no
second hit-test, capture or text-entry path (root `AGENTS.md`). The pane returns typed
`Scope.change` requests and never edits; the host reduces them after `Ui.frame`. A frame's
work follows what is in view, never the size of the graph.

## 7. Interaction

### 7.1 Pointer

| Gesture | Effect |
|---|---|
| Left-drag on empty canvas | marquee: the nodes of one scope it touches (Shift adds) |
| Right-drag or middle-drag | pan |
| Wheel, two-finger scroll, pinch | zoom at the pointer |
| Click a node | select; Shift toggles |
| Drag a node | move the selection, snapped to the lattice, one `Moved` on release |
| Double-click a node's title | rename it in place (`F2` does the same) |
| Double-click a node's body | follow what it references (`Activated`) |
| Double-click a graph input | edit its default |
| Drag from an output | a wire; released on a row it is `Connect` |
| Drag a number field sideways | scrub: a float by 0.05 a point (0.005 with Shift), an integer by one every 6 points |
| Option-click a number field | type the value |
| Click a wire | select it; Delete takes it off |
| Click `ƒ` on a row | `Unfold` an expression row into its own binding, or `Fold_into` on a row wired from a node nothing else reads |
| Right-click a node | the node becomes the selection and the pane's context menu opens |
| Right-click empty canvas | the host's add menu at that point (`Menu_requested`) |
| Drag a frame by its title | the frame and the nodes whose centres lie inside it move together |

Taking a wire off a nested node's row unfolds the node first (`Unfold`, then `Disconnect`),
so a wire never deletes a node.

### 7.2 Keys

All keys are `Editor_core.Command.t` entries in the one keymap. The graph pane's own keys are
`Pxui_graph.Scope.bindings`; the host scopes them to the graph panel. Node keys act on the
selection, row keys on the row under the pointer.

| Key | Command id | Action |
|---|---|---|
| arrows | `scope.walk.left/down/up/right` | walk (§7.6) |
| `Tab` | `graph.add-after` | the add menu; with a node selected the pick is wired after it (§7.3) |
| `w` | `scope.hints` | connect by letter hints (§7.5) |
| `o` / `p` | `scope.open` / `scope.point` | open the selection one level, pinned / point it, or back |
| `⇧O` / `⇧K` | `scope.open-all` / `scope.point-all` | every node to a card / every node to a point, or back |
| `v` | `scope.display` | preview the selected geometry node at the iteration selectors (below) |
| `b` | `scope.bypass` | toggle `^:bypass`; on a node with a boolean `:visible` and no bypass, toggle that instead |
| `x`, Delete, Backspace | `scope.delete` | the hovered wired row's wire or list item, else the selected wire, else the selected nodes |
| `f` | `scope.frame-selection` | pan and zoom to the selection (all with none) |
| Home | `scope.frame-all` | frame everything |
| `⇧F` / `⇧U` | `scope.fold` / `scope.unfold` | fold a binding into its one use / unfold a call into its own binding |
| `⇧H` | `scope.hoist` | move a loop-invariant binding out of its loop |
| `r` / `⇧R` | `scope.repeat` / `scope.iterate` | wrap the selection in a `for` / a `fold` |
| `l` | `scope.function` | make a local `fn` of the selection |
| `d` | `scope.defn` | make a `defn` (the host's dialog types its parameters) |
| `m` | `scope.macro` | make a macro (the host's dialog picks its holes) |
| `c` | `scope.collapse` | collapse or expand a zone |
| `[` / `]` | `scope.probe-prev` / `scope.probe-next` | step the selected zone's probe |
| `F2` | `scope.rename` | rename the selected node, or edit the default of a selected graph input |
| `⇧G` | `scope.frame` | a titled frame around the selection (its corner resizes, its cross deletes) |
| `⌥↑` / `⌥↓` | `scope.item-up` / `scope.item-down` | move the hovered item of a `list`, a `str` or a `scene/merge` |
| `⌘D` | `scope.duplicate` | copy the selected bindings of one scope with fresh names |
| `⌘C` / `⌘X` / `⌘V` | `scope.copy` / `scope.cut` / `scope.paste` | bindings as text on the clipboard |
| `i` / `⇧I` / `u` | `scene.enter` / `scene.peek` / `scene.up` | follow a reference / peek it in a floating graph / back |
| `y` | `carry.pick-up` | pick up a graph or object (§7.12) |
| `?` | `guide.toggle` | guide strip on or off |

Every `⌘` chord is also bound with Ctrl. Leader keys (`/`, then): `a` add menu, `j` jump
to a graph, `e` the World, `f` frame the displayed tile, `/` palette, `?` key sheet, `s`
save preset, `b` browse presets, `t` `g` `i` `h` toggle the timeline, graph, inspector or
all UI, `p` `r` `x` play, reset, stop (Space also plays and pauses, `⇧P` resets, from any pane; the palette is `/ /`), `z` restore layout, `o` `v`/`h`/`x`/`f` split side by
side, split stacked, close, float or dock the focused panel, `l` `g`/`l`/`t`/`i`/`u`/`m`/`w`
retype the focused panel (graph, list, lisp, inspector, outline, timeline, viewport), `n`
plus the same letters a floating window of that kind, `[` `0`..`9`/`n`/`x` the layouts
(§11.11). `⌘S` saves the sketch, `⌘Z` / `⇧⌘Z` / `⌘Y` undo and redo.

**`v`.** The viewport initially shows each object's graph result. `v` previews the
selected geometry node without changing source, layout or history. The request is a
lexical path owned by the object; it survives leaving the graph and follows subsequent
edits. A node inside a loop shows the tuple chosen by its enclosing iteration selectors.
A geometry loop expands only the selected element in a scratch network, retaining its
captures, live arguments and frame-fold snapshot. The authored network remains available
for probes. Viewport framing follows the preview, and picking it keeps the selected
template and tuple. Viewing the result restores the default picture. A request whose
path no longer evaluates to geometry falls back to the graph result.
`v` on a drawing or image node shows it in every canvas pane (an image fitted at the
origin) instead of the panes' own pictures; `v` on the same node again restores them, and a
path that stops evaluating to a drawing or image falls back too. Like the geometry preview
it is view state, outside the document and history.

### 7.3 Add

`/ a`, `Tab` in the graph panel and a right-click on empty canvas open the node menu
(`Pxui_graph.Node_menu`): a search field over the kinds, the likeliest first (what takes an
input after the selected node, then the rest), typed search over the whole catalog by name,
key or category. A kind of another context is listed after the others, dimmed, and cannot be
picked. The host writes one `Add_node`: a kind with an input reads the selected node, or the
graph's result when nothing is selected, so the text still checks. `Scope.scope_point` gives
the lattice position under a menu opened by the pointer.

**New graph, Rename, Delete.** A graph of any context is made and removed from the UI. A
right-click in the Navigator opens a list menu (`Ui.context_menu`): "New graph" with a submenu
of sop, scene, draw, image, value and material, and, on a graph row, "Rename" (F2's field) and
"Delete" (the `Remove_graph` gesture, refused naming the graphs that read it). The add menu at
the scene level lists the same six under "Graph" as "New graph: <context>", and so does the
Navigator's `+`, so a workspace with no graph can start. Each pick is one `Set_graph` named by
the context (`sop`, then `sop_2` ...) and opens the new graph. The default bodies check and cook:
`(sop/box)`; `(draw/background "#111318")`; `(image/noise :width 256 :height 256 :frequency 0.03
:seed 1)`; `1`; a `material/standard`; and for a scene a `let*` of a camera, a light and, when a
SOP graph exists, `(scene/geometry (ref <that graph>))`, closed by
`(scene/root (scene/merge ...) :camera camera)`, which renders in `ui/viewport`.

### 7.5 Letter hints

`w` with one node selected:

1. The source is that node's output. A zone or the synthetic result is not a source.
2. Candidates: every other node of the same scope that the source does not depend on (a
   connection must not close a cycle) and that has an input the source's type fits, on its
   header port or a row its card shows.
3. Order by distance between node origins, nearest first, at most 676. Labels come from
   `asdfghjklqwertyuiopzxcvbnm`, one letter each; with more than 26 targets every label has
   two letters.
4. Typing narrows; a complete label on a node with one fitting input is the `Connect`. A
   node with several fitting inputs then labels its inputs and asks for a second label.
5. Backspace deletes a letter, Escape or a click cancels. `Scope.editing` is true meanwhile,
   so the host keeps its keys out.

### 7.6 Walk

An arrow selects the nearest node in that direction: among nodes whose centre is more than
one point further along the arrow, the one with the least `along + 2 × across`. With no
selection it selects the first node.

### 7.7 Fold and unfold

- **Unfold** (`ƒ` on an expression row, `⇧U`): the nested call, loop or scope becomes its
  own binding in the same scope, named by `Flow_edit.fresh_name`.
- **Fold** (`ƒ` on a wired row, `⇧F`): a binding used once is inlined into its use
  (`Fold_into`). A row wired from a node that something else also reads has no `ƒ`; the edit
  would be refused.
- An expression row reads `ƒ (expr)`; a row wired from a named node that nothing else reads
  reads `ƒ ← name`.

### 7.9 Field editing

A number field is `Ui.value_field` (`Scope.num_field`): dragged it scrubs, Option-click
types; Enter commits, Escape or a click away cancels. A name, an input default, a frame
title and a new output's name use the same field. Each is one `Set_arg`, `Rename`,
`Set_input_default` or `Add_field`.

### 7.11 Context keys and the World

While the World's graph is open, plain keys in the graph panel are: `t` dome ⇄ light, `n`
reseed, `d` play the day cycle, `[` / `]` time −30 / +30 minutes, `1`..`4` the presets.

### 7.12 Carry

A payload in flight, by pointer or by keys. The payload is a Flow value held as text (`kind`
`material` or `sop`, value `(ref cobalt)`), so carrying the material graph `cobalt` is carrying
`(ref cobalt)`. A place is a target when the edit that writes the value there passes the checker:
`Rays_editor.Carry.put` runs the edit (the one the inspector or the graph already writes) and
the document's own check, and its answer is the preview, the refusal's reason and the write.
No widget lists what it accepts; the table is the set of edits the code knows to write.

| Payload | Put on | Writes, as one undo entry |
|---|---|---|
| material graph | a node of a SOP graph, or the inspector's `:material` row of the selected node | `Set_arg :material (ref name)` (the checker refuses a node that has no such argument) |
| material graph | a surface in a viewport | the pick reads the primitive's `shop_materialpath`; the same `Set_arg` on the node that reads it. A graph with no node for it gets `Add_node (sop/material result :material (ref name))` and `Connect` of the result, in one `Syntax_batch` |
| material graph | a `scene/geometry` node, or a geometry object | the same, on the object's SOP graph |
| SOP graph | the scene graph's canvas or its `scene/merge`, or empty viewport space | `Scene_sync.add_geometry` over the existing graph: one `scene/geometry` binding and one merge input |
| SOP graph | a `scene/geometry` node, a geometry object or the surface of one | its `(ref ...)` re-pointed (`Set_arg` on the first argument) |
| SOP graph | any other call | the reference as its first input, when the checker takes it |
| scene graph (kind `scene`) | a viewport panel | the panel's `(ui/viewport (ref name))` re-pointed (`Set_arg` on its first argument; a panel written in place is bound first, as a dock does) |
| camera object (kind `camera`, the value is its binding name) | a viewport panel | the `:camera` of the `scene/root` of the scene the panel shows; a scene with no root (a part) gets `scene/root <result> :camera name` and a `Connect` of `@result`, in the same entry |
| a graph (`(ref a)`) | a byte of the text pane (Graph, Selection or Document tab) | the reference inserted there, spaced from what it touches; the whole text is then checked (one `Set_graph`, or the Document text as a whole) and a text that does not check is refused with the checker's words |

A scene graph is carried from its Navigator row or by `y` with it open; a camera by `y` with the
object selected (the list's selection, else the pane's selected scene node). The key route's letters
for either are the viewport panels of the editor graph's layout (`viewport 1`, `viewport 2`, ...),
those whose put passes the checker. A document without an editor graph has no viewport panel to
write, so no letter. The text pane is a pointer target only: while a payload is held the pane reads the
document the carry began with, so the byte under the pointer does not move when the put is previewed
(the preview shows in the other panes and in the strip); a tab holding an unapplied draft refuses,
because its bytes are not the document's. Not built: a file from Finder (no place takes a path).

Pick up: press a Navigator row of a material, SOP or scene graph and move 4 points, or press `y`, which
carries the open material or SOP graph, else the graph of the selected geometry object, else the
selected camera object, else the graph the pane's selected node references, else the open scene graph. Every gesture of §7.1 stays as it was; a press
that has not left the 4-point dead zone is the click it always was.

While carrying:

- **Hover is the edit.** While a place is under the pointer the real edit is applied to a
  scratch copy of the document and every panel reads it: the viewport, the graph, the text. The
  history is not touched. The status strip prints what a release writes, in the words of the text
  (`Preview · release writes :material (ref cobalt) on shards/m`).
- **Release is one entry.** Releasing there (or `Enter` on the key route) installs that document
  as one history entry named `Put`, whatever the number of rewrites.
- **Cancel is a restore.** `Esc`, a release over nothing, a refused place, a pointer
  cancellation or a window focus loss puts back the document that was the history's present when
  the carry began, physically (the same value, so nothing was written and there is nothing to undo).
- **Refusal gives its reason.** A place that does not take the payload shows the checker's
  message in the strip (`Refused · A material graph takes no material`) and its picture stays the
  original.
- **Keys are the same carry.** `y` holds the payload with no capture; the places that take it get
  the letters `a s d f g h j k l` (this graph or the scene first, then each geometry object), shown
  in the strip and outlined in the graph pane. A letter previews, `Enter` writes, `Esc` drops, and
  a left press on a place is the put. Letters never reach the commands while the carry lasts.
  The pointer previews too once it moves.
- **It survives navigation.** `i`, `u` and `/ j` (and the walking keys) work while carrying;
  holding the pointer over a node for 0.6 s follows its reference. Nothing else edits the
  document until the put, and the autosave never writes a preview.
- **Budget.** A put whose apply (edit and check) or whose target cook takes 500 ms or more
  (`?carry_budget` of `Editor3.create`, seconds, default 0.5) is not shown: the target is lit and
  the strip says what it would write and why there is no picture (`Would write :material (ref cobalt)
  on shards/m · no preview, applying takes 612 ms · release writes it`); the release still writes it.
  `test_materials` runs it with a zero budget and times a preview's apply and restore frames.

Gesture echo: every other gesture that writes the text also prints what it wrote in the same strip
slot, in the words of the text (`Wrote :visible false on scene/body`, `Wrote :translate [3 0 0] on scene/b`;
`Rays_editor.Echo`), until the next one; an op with no short words (a layout change, a rewrite of
a whole graph) prints nothing and the history label stands. The palette's "Copy workspace as Lisp"
(`Leader.Copy_lisp`, no key) puts the text Command-S writes on the clipboard.

The key `y` is otherwise used only by Command-Y (redo). `Pxui.Ui` holds the
payload on the handle (`Ui.carry`, `Ui.carrying`, `Ui.drop_target`, `Ui.cancel_carry`; see
`pxui.md`), `Scope` reports the node or canvas under it (`Drop_over`, `Dropped`) and never edits,
and `Core` turns a drop into the put.

## 8. Views

A panel of the editor graph is a graph, a list or a lisp panel (§11.11); `/ l` retypes
the focused one. They show the same graph, level and selection and write the same edits.

### 8.1 Graph

Everything in §6 and §7.

### 8.2 List

`Pxui_shell.Tree` rows. Its keys (`Tree.bindings`, scoped to the graph panel): arrows or
`j` / `k` move, Shift extends, Left and Right fold and unfold, Home and End, Tab and
Shift-Tab reparent, `⌥↑` / `⌥↓` move a row, `F2` renames, Delete removes, `/` filters, `h`
hides or shows, Enter opens the selected row in the graph, `f` reveals the selection.

### 8.3 Text

The Lisp pane is editable (`Rays_editor.Text_pane`, `Ui.text_area`).
Its tabs: Selection (the top-level ancestor of the selected binding as a `let*`
over the root bindings it needs, the binding marked; an edit is one `Set_arg`),
Graph (the current graph's text) and Document (the whole workspace
text; Check and apply is atomic, one "Edit text" history entry, a refused apply
keeps the draft and marks the error line).  The editor completes as you type (the
context's kinds, a kind's parameters, slots and choices, special forms, operators,
bindings in scope; ranked prefix, word, fuzzy, then by group and by use in the text),
describes the token under the resting pointer, and lets a number be dragged sideways:
the text applies live on every frame of the drag as one history entry, so the viewport
follows the value (`Lisp_text`, `Ui.language`).  The text is one of the pane's two surfaces of the
same edit: Command-click on a `(ref name)` shows that graph (onto the back stack of `i`); in the Graph
tab the caret inside a binding selects its node, and selecting a node scrolls the text to its binding;
a `"#rrggbb"` literal wears its colour as a bar and a click opens the kit's colour control (swatch,
hex, r g b), each edit applied live as one history entry; and completion after `:material`
(the material graphs, inserted as `(ref name)`), `:camera` (the scene's cameras), `:active` (the
layouts, inserted as their index) and inside `(ref ` reads the document, not only the text shown
(`Lisp_text.names`).  The pane paints at the shared elastic
scroll position, so it overshoots and settles like every other scrolling view.

## 9. Inspector

`Pxui_shell.Inspector` shows the selected node's inputs: the same rows the card has, every
one of them, with a pin toggle per row (§5.1) and a reset. An edit there is the same
`Flow_edit` op the canvas writes and records the same history entry. An `:of` keyword ties it to one graph panel
(§11.11).

## 10. Guide

On by default until the user turns it off (`?`); the setting persists in user preferences.

- **Strip.** `Pxui_shell.Status_bar.guide` lists the keys that apply now. Each command
  carries `guide : Guide_context.t list` (pure data, no predicate), and the host computes the
  current context: `Canvas | Node | Multi | Hints | Leader | Search | List | Text`. `Canvas`
  is the empty canvas, `Node` one node selected, `Multi` several.
- **Which-key** after `/`, and the **key sheet** on `/ ?`, grouped Add, Panel,
  Layout, Go, Time, File, plus a section per pane.
- **HUD.** A key press echoes `key · command label` for 1.5 seconds.

## 11. Language

The forms of the language, their types and their meaning are in
`specification/workspace/iteration.md` (§2 loops, lists, `if`, `ref`, checking and bounds; §7
functions, data, branches, macros) with the rule register `ambiguities.md`. This section has
what those files leave to the reader, the printer and the checker's argument handling.

### 11.1 Lexical syntax

- Whitespace separates tokens. `;` starts a comment to the end of the line. A comment is a
  note on the next form; comments before a closing bracket are that container's tail.
- Delimiters: `(` `)` for calls and special forms, `[` `]` for vectors and binding vectors,
  `{` `}` for records (keys and values alternate).
- Number: `-?digits(.digits)?` with an optional exponent (`1e-14`, `2.5E+6`). A number with
  neither `.` nor exponent is an integer. The tree keeps the spelling, so `2.0` stays a
  float.
- String: `"…"` with the escapes `\"`, `\\`, `\n`, `\t`, `\r`; any other escape is
  `E_UNEXPECTED`.
- Keyword: `:` followed by a name. Metadata: `^:` followed by a name, on the next form.
- Quotes, for macro templates only: `` ` `` quasiquote, `~` unquote, `~@` splice, `'`.
- Names are `[a-z][a-z0-9_-]*` (`Flow.Macro.valid_name`); a SOP key and a slot name have no
  `-` (§3.3). `name.field` reads a record field.
- The bytes 1, 2 and 3 are refused anywhere in a text (`E_UNEXPECTED`): the printer uses
  them as in-band span markers.
- Nesting deeper than 256 forms is `E_DEPTH`, and the steps of a `->` count toward it.

### 11.2 Printing

`Flow.Lisp.print` is the one printer: 84 columns, aligned `let*` bindings, keyword pairs one
per line when a form breaks, notes and `^:` flags kept. Printing is a fixed point:
`print (parse (print x)) = print x`. Comments are kept inside parameter vectors and between
and after root forms; a comment written after a quote prefix is moved before it.

`Flow.Lisp.float` is the one spelling of a float in workspace text, and every writer uses
it: the shortest digits that read back as the same value, always with a `.` and never an
exponent (`1e-14` is written `0.00000000000001`). A non-finite value prints `0.0`; a writer
for which that matters rejects the value first.

### 11.3 Threading and nested nodes

`(-> x (f a) (g b))` is read as `(g (f x a) b)`: each step is a call that takes the value before it
as its first operand, so the text reads in wire order, left to right like the canvas. It is sugar of
the reader (`Syntax.parse`): nothing after the reader sees a `->`. The outermost call keeps the
form's id and the span of the whole `(-> ...)`, each step keeps the span of its own clause, and the
value `x` keeps its own. A step that is not a call, or a `->` with no value, is `E_THREAD`.

The printer threads a chain of three or more calls of node kinds (a head with a `/`, except the
`ui/` layout forms, which nest) whose first operand is the next call down. A step that carries a
comment or `^:bypass` is still threaded and keeps them on its own line. Shorter chains and every
`let*`-named value stay nested, so print and re-read keep the same forms (`test/test_threading.ml`
prints and re-reads every checked-in workspace).

Every step of a `->`, and every call of a node kind written inside another call, is a node of the
graph (`Flow_graph.Projection`): a card before the card that holds it, wired to the row it is written
in. It has no binding, so its path leaf is the holder's leaf, `#`, and the input (§3.4). Its rows
edit in place (`Set_arg`, `Connect`, `Disconnect`, `Toggle_bypass` take the path); naming it
(`Rename`, the name field) binds it under that name; deleting it hands its place to its first input;
dragging its output to a second input, viewing it, or dropping a wire where it is written binds it
first, so a wire never deletes a node. The caret in its text selects it and selecting it marks its
text. Inline `map`, `filter`, `reduce` and `sort-by` are cards too; their `fn` inputs
are zones with typed parameter rails, call selectors and editable body cards. Array
inputs show their checked array type. The selector is view state; scrubbing or wiring
a body row edits the same authored text, including from the text pane. Expressions,
`ref`s, loops, and calls of named functions and macros written in an input stay chips
(`Unfold` binds them); a macro's arguments are pieces of its template and stay chips too.

Rule: no syntax is text-only. New syntax or sugar ships with its graph projection, its
`Flow_edit` gestures and a test.

### 11.4 Resolution

A call head is, in order: a special form; a local function in scope; a `defn`; a `defmacro`; a
built-in operator of the graph's context (a bare name also tries `value/<name>`); a catalog
kind, by its qualified name or its short name within the graph's context
(`Flow.Check.resolve_kind`). An unknown head is `E_UNKNOWN_KIND` with a suggestion at edit
distance 2 or less; a kind of another context is `E_WRONG_CONTEXT`.

`Flow.Op` is the immutable resolution table for built-in operators. Each declaration
contains its context, signature, output type, choices, value shape, validation, evaluator body
and menu category. The checker, evaluator (including compiled arithmetic) and editor read that
record; adding an operator does not add a second name table. Lookup is a hash table built once
from `Op.all`, independent of evaluator initialization. `Context.all ()` and `Ty.names ()` supply
the editor's context and type vocabulary.

Domain types are nominal `Ty.Named name` values; the structural data types stay
closed. `Ty.register` declares a nominal type's palette role, shape behavior
and optional literal default. `Context.register` declares an abstract,
marshalable context identity with a result type, value support, label, palette
role, Outline group and optional catalog prefix. Register on the initial
domain before checking. Repeating an identical declaration is idempotent;
invalid or conflicting declarations leave the registry unchanged.

`Workspace.check ~ops` accepts an immutable operator extension list and retains
it in the checked workspace. Evaluation, checked edits, projection, completion
and the add menu use that same list; it is not a mutable global operator
registry. A new domain therefore needs a named type, a context descriptor and
its operator list, without a new domain match in the checker or pane. The
`test_open_domain` gate checks this through both the pane and the editor host,
including insertion, colored painting and preset reload.

`Port_type.t` stays closed because it is the SOP parameter bridge for the
existing numeric, Boolean and vector field schemas, rather than the graph's
type vocabulary. `Panels.panel` stays closed because its constructors select
the editor's actual pane implementations; `View` and `Canvas` already carry
string identities. `Scene_execution.pipeline_family` stays closed because its
cases select renderer pipelines, not language domains.

`Flow.Value` holds pure values parameterized by evaluator functions and residuals. Catalog
calls retain their resolved context in the checked term; struct values retain the resolved type
with their head and arguments. Neither dispatch nor dynamic typing infers a context from a name
prefix. An operator body can ask the evaluator to create a plan node (`sop/curve`); `Value` and
`Op` themselves have no evaluator state or geometry dependencies.

Parameter keywords need no namespace: `:amp` is resolved against the schema of the kind it
is passed to (a field name, or a vec3 group name). Slot keywords use slot names. An invalid
or reserved binding name is `E_BINDING`; editors pick fresh names with
`Flow.Workspace.name_taken` and `Flow_edit.fresh_name`.

### 11.6 Arguments

- Positional arguments fill a kind's slots in the order they are written, and `:keyword
  value` pairs may stand anywhere among them: `(sop/transform :translate [1 2 3] a)` has `a`
  as input 0 (`Flow_edit.positional`). A positional after a keyword is allowed.
- More positionals than slots is `E_EXTRA_POSITIONAL`. A kind whose last slot repeats
  (`sop/merge`) takes any number.
- An input given twice, by two keywords or by a keyword and a position, is
  `E_DUPLICATE_PARAM`.
- A keyword with no value is `E_MISSING_VALUE`; an unknown one is `E_UNKNOWN_PARAM` with a
  suggestion.
- A literal is checked against the field: a non-integral number for an Int field is
  `E_INT_LITERAL`, outside the hard bounds `E_HARD_RANGE`, outside the soft range
  `W_SOFT_RANGE` (`Flow.Check.validate_parameter`).
- `if` has the type both branches fit (`Ty.join`). A `fold` or `scan` accumulator has the
  wider of its seed's and its body's types, so an int seed does not round a float body; a
  body that does not fit the seed's type is `E_ACC_TYPE`.
- Errors do not cascade: a term that failed is poisoned and its uses report nothing further.

### 11.7 Metadata and macros

`^:bypass` on a call is the only metadata of an expression; any other there is `E_META`.
`^:allow-warnings` on the workspace form lets a build pass with warnings. Any other metadata
on the workspace form, or any on a root child (`graph`, `defn`, `defmacro`), is ignored with
the warning `W_UNKNOWN_META`.

`(defmacro name [a b & rest] `template)` has only the quasiquote form: `~a` fills a hole,
`~@rest` splices, `x#` is a fresh name. A template that is not quoted is
`E_MACRO_TEMPLATE`. Every other name in a template must be global (`E_MACRO_CAPTURE`
otherwise); a name a binding could take, such as `count` or `first`, is free only as the
head of a call, not as an argument.

### 11.9 Diagnostics

`Flow.Diagnostic.t = { code; severity; position : { line; col } option; message; span }`.
A source diagnostic has a 1-based position and a half-open byte span; one without source
text leaves both absent. `Diagnostic.report` prints the OCaml compiler's format, so dune and
editors jump to the line. Messages are sentences that name the fix.

The reader's and the argument checker's codes (the language's own are listed in
`workspace.mli`, `eval.mli` and `macro.mli`):

| Code | When | Message shape |
|---|---|---|
| `E_UNCLOSED` | a bracket or a string never closes | This '(' is never closed |
| `E_UNEXPECTED` | a stray or mismatched close, an unknown string escape, a byte 1 to 3 | Expected ']' to close the '[' on line 3, found ')' |
| `E_DEPTH` | more than 256 nested forms, `->` steps included | S-expression nesting exceeds 256 forms |
| `E_DEPTH` (evaluator) | more than 64 nested calls when the document is evaluated | Call depth exceeds 64. |
| `E_THREAD` | a `->` with no value, or a step that is not a call | A -> step is a call, as in (sop/normals :cusp_angle 0.6) |
| `E_UNKNOWN_KIND` | no such kind | Unknown node x. Did you mean y? |
| `E_WRONG_CONTEXT` | a kind of another context | |
| `E_UNBOUND` | unknown name | x is not bound. Did you mean y? |
| `E_UNKNOWN_PARAM` | no such keyword | noise_displace has no parameter :ampl. Did you mean :amp? |
| `E_DUPLICATE_PARAM` | an input given twice | :amp is given twice / Input input is given twice: by :input and by position |
| `E_EXTRA_POSITIONAL` | more positionals than slots | grid takes 0 geometry inputs; this one is extra |
| `E_MISSING_VALUE` | keyword without value | :amp has no value |
| `E_TYPE` | wrong type | |
| `E_INT_LITERAL` / `E_HARD_RANGE` | bad literal | |
| `W_SOFT_RANGE` | outside the slider range | |
| `E_META` | metadata other than `^:bypass` in an expression | Unknown metadata ^:x. The only metadata is ^:bypass. |
| `W_UNKNOWN_META` | metadata on the workspace form or a root child | Unknown metadata ^:x here; it is ignored. |
| `E_BYPASS` | `^:bypass` on a call that cannot pass its input through | |
| `E_CATALOG` | the catalog manifest does not read | |
| `E_DOCUMENT_FORM` / `E_LAYOUT` / `E_SETTINGS` | a root form of the document that does not read (§4.4) | |
| `E_UNKNOWN_GRAPH` / `E_PANEL_OF` | a `ui/graph` or `:of` that names nothing (§11.11) | |

### 11.10 Ambiguity rules

The register `workspace/ambiguities.md` extends this table.

| # | Case | Rule |
|---|---|---|
| 01 | `3` versus `3.0` | the spelling decides (register L15); an integer literal fits Int and Float fields, `2.5` into an Int field is `E_INT_LITERAL` |
| 02 | soft versus hard range | hard is an error, soft a warning |
| 03 | rename | identity is the path; `Rename` rewrites the binding, its uses and the layout keys together |
| 04 | levels, pins, positions, frames, collapsed zones | layout; never printed in the workspace form |
| 05 | bypass | metadata `^:bypass`, never a parameter |
| 06 | a positional after a keyword | allowed; positionals are numbered in written order (§11.6) |

### 11.11 Editor context: the layout forms

An `editor` graph returns `(ui/workspace root)`, written in place or bound to a name the graph
returns. `Contexts.editor` lowers it to an `Editor_core.Panels.t` tree; `Pxui_shell.Layout.geometry`
places it. All sizes are logical points.

| Form | Meaning |
|---|---|
| `(ui/split axis a b)` | two panels along `"horizontal"` (a left of b) or `"vertical"` (a above b), half each |
| `(ui/split axis a b :first_size n)` | `a` is `n` points along the axis, `b` takes the rest |
| `(ui/split axis a b :second_size n)` | `b` is `n` points, `a` takes the rest |
| `(ui/split-at axis ratio a b)` | `a` gets `ratio` (0.1–0.9) of the split, `b` the rest |
| `(ui/tile panel...)` | a grid of 1–16 equal cells |
| `(ui/floating panel)` | a window over the layout (bounds in `(layout (panel ...))`) |
| `(ui/switch panel... :active n)` | the layouts of the graph; the active one is the tree |
| `(ui/viewport scene :look_through b)` | a viewport of a scene |
| `(ui/canvas drawing :focus b)` | a native 2D Canvas over a Drawing value; an image input is wrapped in `draw/image` at the origin |
| `(ui/graph ["name"] :wires w :view v)` | the graph pane; `name` pins a graph of the workspace (`def:name` a function), `:wires` is `"rect"` or `"straight"`, `:view` is `"graph"`, `"list"` or `"text"` |
| `(ui/list :of g)` `(ui/inspector :of g)` | a list view, an inspector; `:of` names the graph panel it shows |
| `(ui/lisp :tab t :of g)` | a text pane; `:tab` is `"selection"`, `"graph"` or `"document"` |
| `(ui/outline)` | the Navigator |
| `(ui/timeline)` | the timeline strip |

**Fixed sizes.** A split is sized one way: by a ratio, or by one fixed side. `:first_size` and
`:second_size` are whole points (1 or more) and exclude each other (`E_RANGE`); `ui/split-at` takes
neither. The fixed side keeps its points at every window size and the other side takes what is left
of the split after the one-point gutter. When the split is too small for both, the other side keeps
its minimum first (a column: 220 points for a viewport, 180 for a graph, list or lisp panel, 120
otherwise; a row: one point) and the fixed side shrinks, never below one point. A side that is
hidden gives its space to the other; a collapsed side is its strip. Splits by ratio nested along one
axis are one run that divides its extent once by the product of the ratios; a fixed split is placed
on its own, so a fixed column never moves when a neighbour's ratio changes.

**Dragging a gutter** writes what the split is sized by (`Flow_edit.Set_layout_size`, one history
entry "Resize panel"): the fixed side's whole points for a fixed split, else a ratio with four
decimals in a `ui/split-at` (a `ui/split` without a size becomes one). The same op converts a split:
a right-click on a gutter, and the Size row the inspector shows for a selected `ui/split` or
`ui/split-at` card, offer *By ratio*, *Fix first side* and *Fix second side*; the new form keeps the
sizes the split has on screen (the side's points, or their ratio). A panel's header menu has the
same three rows for the split that holds the panel. The keyword rows of a `ui/split`
card edit the points in place.

**Strips.** A `ui/timeline` leaf has no header and, in a vertical split by ratio (a plain
`ui/split` reads best), a height of 30 points whatever the ratio says, the other side taking the
rest: it sits between two panels at any window size. A fixed size written for it wins. Hiding the
timeline (`/ t`) removes the leaf's strip. The strip's frame field is typed (a click opens it,
Enter commits, Escape cancels) and clamps to 0 and the last frame. A tree without a
timeline leaf has the same strip under the tree. The status strip (28 points) spans the window below
both; no panel gives up space for it. A collapsed panel is a strip of its header: 22 points in a
vertical split, 28 points wide in a horizontal one.

**Start keywords.** `:focus true` on any panel form gives that panel the keyboard focus (the first
in tree order when several say so; none: the first viewport), `:look_through true` shows the
viewport through its scene's render camera, `:view` picks a graph panel's view and `:tab` a lisp
panel's tab. They say how the editor opens the document; use never rewrites them. The editor
follows one again whenever its value in the text changes, by any route (a reload of the source file,
a preset, an edit, undo), for the panel that changed; a reload that leaves them as they were leaves
what the user did in the UI alone. `/ v` and the inspector toggle look-through for the focused
viewport only.

**Panels are instances.** Every leaf draws and works, docked or floating, however many of a kind the
layout has. A panel's own view state is keyed by its binding when that binding names one leaf, else
by its place in the tree (a panel written in place, made by a loop, or a binding used twice: each
leaf is its own instance), and stays with it: a graph panel's graph (the one it names, else the
graph of its open level), navigation level, the selection of that level, canvas pan and zoom, node
selection, view and follow-and-back route; a list's folds, filter, focus row and scroll; a lisp
panel's tab, drafts, errors, caret and scroll; an outline's search and scroll; an inspector's scroll
and open sections; a viewport's orbit and look-through. PXUI keys are seeded by the leaf, so two
instances never share widget state or pointer capture. The node menu, the probes and the timeline's
time are one per editor and go with the graph panel in use (the focused one, else the last one
focused); the viewport's handles and picks follow its level. A graph panel shows the view it says,
whatever other panels the layout has. A press gives its panel the focus before the frame builds, so
a gesture works on the first press in any panel. `(ui/graph "nope")` is `E_UNKNOWN_GRAPH`.

**Following and `:of`.** An inspector, a list and a lisp panel show a graph panel: its graph, its
level and its selection. Without `:of` that is the graph panel in use, so the panel follows the
focus. `:of name`, where `name` is the binding of a `ui/graph` panel of the layout shown, ties the
panel to that graph panel whatever has the focus (`(ui/inspector :of network)`; a wire from the
graph panel's card to the row `of`). A press in a tied panel makes its graph panel the one in use,
so its edits land there. An `:of` that is not a binding of a graph panel of the layout shown is
`E_PANEL_OF`.

**Saved panel state.** `(layout (panel [graph name] ...))` is the disclosure and window of the
panel that binding names. When the binding is used by several leaves the entry is what each of them
starts from, and a change to one leaf is saved under its place, `[graph "@panel" i j ...]`, which
wins for that leaf.

**Floating windows.** `(ui/floating panel)` takes its bounds from the `(layout (panel [graph name]
:window [x y w h]))` entry of the panel's binding or, when the float itself is the bound name
(`name (ui/floating (ui/inspector))`), of the float's binding.

**Editing.** Every layout form is a card of the editor graph and its keywords are rows of the card
(`Set_arg`). The layout gestures (`Set_layout_size`, `Split_panel`, `Close_panel`, `Dock_panel`,
`Set_panel_kind`, `Set_layout`, `Layout_new`, `Layout_remove`, `Layout_window`, `Layout_float`,
`Merge_layouts`) accept a graph whose result is the `ui/workspace` call or a binding of it. The
printer never threads a `ui/` call (§11.3): a layout is a tree of containers, not a pipeline.
Named layouts, the `/ [` keys and the migration of an older file with several editor graphs are
in `workspace/iteration.md` §4.

### Import

A document may place `(import "relative/path.rays")` beside its workspace and
metadata forms. Paths resolve beside the document file. The imported file's
`graph`, `defn` and `defmacro` forms (or the children of its workspace) are
spliced before the local children and checked together. Names remain lexical;
duplicate names are `E_NAME`. Imports are one level: an imported `import` is
`E_IMPORT`, as is an unavailable file or an absolute path.

Imported graph cards wear their source file name. Their context menu opens
the source document; a library containing only bare definitions is editable
and saves those forms without adding a workspace wrapper. Edits to imported
forms are refused with `E_IMPORTED`.
Completion includes imported names and their file. Saving preserves the
import form and local comments and writes only the importing file. Imported
files are polled with the main source; changes reload as one history entry
and wait while the document has unsaved work. Generated programs embed the
original imported texts, and generated Dune rules depend on imported files.

### Spreadsheet

`(ui/spreadsheet :of network)` follows the selected cooked geometry of its
graph panel, like an inspector. With no `:of`, it follows the focus. Point,
vertex, primitive and detail tabs select ownership, with an index column,
one column per scalar attribute, component columns for tuples, text and
array cells, and membership columns for groups. Point position `P` has its
three canonical columns. Optional cook targets provide the same immutable
geometry as probes; only visible values are formatted. Owner choice and
scroll belong to the panel instance. Row picking in the viewport is deferred;
the table remains read-only.

## 12. Catalog manifest and `rays-lisp`

`tools/flow_manifest.exe` writes `lib/sop_catalog/flow_manifest.sexp`
(`Flow_sop.Manifest.generate`): the catalog version, a digest, and for every kind its
qualified name, key, aliases, operation, label, category path, slots, fields (name, label,
folder, kind with soft and hard range, default, primary, vec3 group, unit) and outputs. The
file is checked in; `dune build @lib/sop_catalog/runtest` regenerates it and diffs, and an
intended change is accepted with `dune promote`. `Flow.Check.catalog_of_manifest` reads it:
`lib/flow`'s own tests check against it (the library cannot link the catalog), and
`test/test_sop_catalog.ml` proves it equals the live catalog. The editor and `rays-lisp`
check against the live catalog (`Editor_document.Contexts.catalog`), and a `.rays` binary
compares the catalog digest it was generated with (`Contexts.catalog_digest`).

`tools/lisp` is `rays-lisp`:

| Command | Does |
|---|---|
| `check FILE...` | parses, checks, then evaluates and lowers the document as a window opens it (`Contexts.of_workspace`), so a file that passes opens. Diagnostics print in the compiler's format. A warning fails the file unless the workspace form carries `^:allow-warnings` |
| `fmt FILE` | prints the canonical text; a file with warnings still formats |
| `ml FILE` | the generated `main.ml` of a `sketch.rays` (the verbatim source, its digest and the catalog digest, passed to `Rays_editor.Workspace.main`) |
| `source FILE` | the text as an OCaml module, for a sketch with its own `main.ml` |
| `dune DIR` | the `sketches/dune.rays.inc` include |

## 13. Evaluation

### 13.1 Lowering

`Flow_sop.Lower.workspace` checks the source, evaluates every non-geometry term
(`Flow.Eval.static`) and turns the geometry plan into one `Flow_sop.Network.t` per evaluation
of a `sop` graph: each graph with its default inputs and each distinct `(ref g ...)` override
tuple. A plan node keyed by `(site, iter)` in instance `i` gets the compiled id
`compiled_ids.[i :: site_index :: (-(k+1))*]` (`Flow_sop.Instance_path`), allocated on first
use; passing a previous result's `sites` and `compiled_ids` back keeps ids stable across
edits, so session cache entries survive them.

A live reference to a tuple already present in that plan reevaluates its graph
under the same instance identity. Inline and bound references share its state;
coerced-equivalent input overrides share one instance as during planning.

- A catalog call becomes its factory node with literal parameters.
- Every `sop/merge` becomes one `flow.merge_n` node that tags each primitive with a running
  input index in the `__flow_src` primitive attribute; `Lower.origin` maps a tag back to the
  site and iteration that made it (viewport provenance).
- `sop/curve` becomes a `flow.curve` node whose `points` parameter is a text-encoded list
  (`Flow_sop.Curve`).
- A bypassed call makes no node: the evaluator passes its input through.

The editor keeps the checked workspace and recording evaluation together. A
same-type literal written in a catalog parameter patches its authored span and
checked term and validates that parameter using the workspace's schema rules.
An Int/Float change inside a numeric Vec3 keeps the argument's Vec3 type;
Boolean components are rejected by the same full-check fallback.
For a static SOP call outside a geometry template, lowering patches all of its
instances' parameter values and retains the plan's identities and probe records.
The recording evaluation associates plan node IDs with originating syntax IDs,
so anonymous nested calls, thread steps, defn calls and graph overrides update
every copy of that authored call. Syntax IDs belong to one checked source;
they can change on reparse and are kept outside the semantic plan.
The pane updates the existing literal rows and keeps its geometry and routes.
The patch lineage is bounded to 4,096 distinct arguments; structural edits and
unsupported literals use the full check. Geometry templates, frame folds,
retained function records and non-SOP values use the full lowering after the
source patch: measured over every checked-in file, the edit itself is under a
millisecond there and the rest is the evaluation the changed value requires
(`specification/performance-log.md`, "Phase 4 Step 1 closure").

A text-pane number drag uses the numeric token's pre-edit byte range reported
by PXUI and the printer's form IDs to address the innermost source card's
`Set_arg`. Selection, Graph and Document tabs share that path. While an applied
token scrub is held, cached text and spans are patched in place, preserving
line breaks; release restores canonical printing. Unapplied drafts and stale
sources take the existing whole-text merge/check path. Document metadata is
printed with IDs disjoint from workspace source, so layout and view tokens
cannot address a source card accidentally.

Structural edits remap stored layout paths, then validate the surviving keys
against authored paths and graph inputs without projecting every graph. A pane
reuses its projection when its graph's authored content, checked types,
live/invariant paths and macro environment are unchanged. Changes elsewhere
still refresh evaluated records; a dependency that changes a checked type
invalidates the projection.

### 13.2 The value lane

Residuals retain only lexically free bindings, including names read by nested
functions and zone bodies. Sequential and destructured bindings shadow outer
names; a state's initializer is read in the outer scope. A bounded weak cache
per domain memoizes the checked-term walk. Function closures keep their existing
captures: measured retained closure bytes are below 10% of evaluation allocation.
Residual identities and template rebinding by name remain unchanged.

A `Network.t` is the SOP `Edit_graph` plus `drives`: the arguments that depend on `t`, each
a `Flow.Eval.value` holding residuals, keyed (compiled node id, argument name). In the
literal network such a parameter holds its `t = 0` value. Before each cook submission, and
outside `Ui.frame`, `Flow_sop.Value_lane.resolve` runs on the initial domain:

1. Force each drive at the cook time (a scalar, a vec3, a colour text, or a list of vec3 for
   `flow.curve`'s points).
2. Coerce it (§3.2) and normalise hard bounds.
3. Compare with the value applied in the previous resolution (kept in the environment, not
   the document) and apply only changed ports to a copy of the graph. The document's text is
   never overwritten by a live value.
4. Cook the result. An unchanged value leaves the node's cook key unchanged, so nothing
   re-cooks.

A network without drives does no lane work and reuses its result. Live nodes are marked
volatile in the session (`Lower.is_volatile`: one replaced slot each, outside the LRU), so
playing never evicts static entries. Structure cannot depend on `t` (`E_TIME_COUNT`,
`E_TIME_BRANCH`), so one lowering serves every frame.

### 13.3 Determinism

Evaluation and the lane are sequential IEEE double arithmetic with fixed operator semantics,
so results are identical for one and many domains and across runs with `Sketch.Fixed dt`.

The value lane prepares `Flow_ir.Executor` programs once per network. Scalar
programs reuse the existing exact closures or reference walker. Supported numeric
packed `map`, `for`, `sum`, `fold`, `scan`, `reduce` and `array/sum` use
1,024-element blocks over float registers. Independent elements run through the
shared `Parallel` pool. Static packed counts choose between interpreter and CPU
kernel using the measured fixed/per-element cost table; dynamic counts retain
the CPU kernel. Placement and force-time dispatch use the same decision.
Cartesian clauses retain last-clause-fastest order and
`:skip` retains authored iteration indices. Accumulator-dependent instructions
run in element order; invariant instructions run once per block. A fixed binary
tree visits chunk spans left to right, carrying the accumulator across spans.
It preserves the interpreter's left fold rather than reassociating partial sums,
so cancellation, rounding and signed zero are byte-identical across domain counts.
Empty `sum` returns integer zero; empty `fold`/`reduce` retains its seed;
`array/sum` retains its typed zero.

Numeric packed work inside `state` steps uses the same tier. The evaluator owns
the fold cell and frame transaction; a private callback dispatches a checked map
or loop with the step's current immutable bindings. Each prepared IR program
retains at most 32 register templates, shared through an atomic immutable list.
A template rebinds arrays, scalar/record uniforms and cardinality on the next
step; a changed function body or fused lexical captures need new specialization.
Stateful element bodies remain interpreted. Numeric comparisons, Boolean
operators and `if` select register values; an error from eager evaluation of an
untaken pure arm reruns the independent reference walker, preserving branch
diagnostics. Probes and reference drawing never invoke packed dispatch.

Native canvas playback retains prepared drawing argument programs while its
plan is unchanged. Exports prepare them once before the first frame. All maps
read the same frame snapshot and environment-owned fold; repeated views/readers
return the already computed next value. Static canvases retain their Scene
without work proportional to unchanged point count.

Equal-count adjacent maps fuse into one register program, including maps feeding
a numeric reduction. Fusion carries the stages' authored provenance and avoids
intermediate arrays. A single-input chain proves equal length even with dynamic
counts; a multi-input zip requires proven equal static counts. Skipped consumers,
shortened zips, accumulator producers and correlated Cartesian sources retain
their materialization/evaluation boundaries. This preserves errors in a producer's
unused tail. Scratch remains capped at 64 registers per block; a larger group
retains its separate stages. `Packed.compile ~fusion:false` retains intermediate
arrays for parity checks and profiling. Unsupported bodies
remain interpreted. Probe forcing uses the reference walker independently of
compilation settings. The IR retains lexical provenance, cardinality origins,
frame/event rates and exact/approximate precision. Its placement pass refuses
approximate inputs to catalog calls, exports, state seeds and cache keys with
`E_APPROX_SINK`; `(exact x)` is the explicit readback card. CPU evaluation
remains exact. A host GPU backend may place a
covered approximable packed producer at a display sink after measured costs
justify it; `(exact x)` explicitly materializes a selected GPU producer.

The checker records immutable `Workspace.packed` candidates/refusals and
candidate-to-producer links, including aliases and kernel body paths. Its
definitive `Workspace.approx` starts empty. `Flow_ir.qualify_workspace` runs
the ordinary static evaluation once, observes each actual specialization,
compiles with production fusion and applies the shared GPU form checks.
It qualifies a path only when all its producers have observed, unambiguously
associated specializations that pass. A refusal or ambiguous observation
dominates successes; unobserved producers remain explicitly pending.
`approx_reasons` retains structural, actual compilation/emission or pending
reasons. Inputs/captures changing rebuild conclusions from candidates, with
no retained residual/program proof cache and no per-frame qualification.
`Lower.of_checked` publishes this derived metadata, which `Contexts` copies
into the current document without replacing edited source.

`image/map` is an authored packed producer too. Its static observation
evaluates only the checked pixel-function argument, then binds a representative
Vec2 column to that instantiated callable. Qualification uses the same packed
compiler and GPU form checks, including actual captures. The image recipe does
not become an approximate scalar merely because its internal pixel program
qualifies. `Lower.image_sites` retains the authored producer separately from
runtime instance/site/tuple; named-call prefixes are never stripped to infer
permission. Missing or conflicting observations remain unresolved. Prepared
image maps use this plan-bound metadata for their `Display "image/map"` sink;
absent metadata keeps CPU selection. Exact CPU image cooking is unchanged.

Candidates cover maps and one-clause collecting loops over packed
Float/Vec2/Vec3/Vec4 arrays. Captures, folded constants, records, function
bindings and register demand are decided by actual compilation; uncertainty
does not exclude ordinary CPU use. Declaration capabilities in `Flow.Op`
and width/register/octave/float32 facts in `Flow.Packed_ops` are shared with
compilation. `(length vec3)` returns its Euclidean norm as a float, using
`sqrt ((x*x + y*y) + z*z)` with that association and separately rounded
float64 multiplications and additions (no contraction). Concrete scalar inputs are
type errors; unannotated Fn inputs are checked again at the call site.
The packed compiler derives it from existing multiplication/addition/square-root
instructions and preserves the reference's nonfinite diagnostic and lazy branches.
Numeric nullary
live built-ins and `t` are per-frame uniforms. Noise seed/octave
arguments must compile as constants (octaves 1–32). Multi-clause products,
reductions, filters and unsupported actual programs stay outside the qualified
set. One-source Product already has effective Zip behavior; authored skips
are checked against each actual iteration tuple. `(exact x)` clears derived
eligibility without erasing the producer's own facts.

Precision taint remains independent of qualification candidates. The
checker retains precision producer paths through aliases, arithmetic and containers and
reports `E_APPROX_SINK` before a statically tainted value reaches a catalog slot or
parameter, state seed, graph override, or `settings/*`/`scene/*` argument. Its
message names the producer and consumer paths. `draw/*` and `ui/*` consumers
may display these values; exact-only consumers require `(exact x)` for this taint, including
when CPU execution currently supplies the producer. This conservative check
does not change CPU values. Candidate or qualification membership alone does
not apply this static taint; uncertain candidates remain legal CPU programs,
with actual placement and execution enforcing their precision boundaries.
An inline `exact` is a graph card with its input's
cards and function zones projected and edited beneath it.
The inspector reports `approximable` for qualified paths or the pending/refusal
reasons; the graph's tier badge
continues to describe execution. `bench_workspace_lower --approx` prints the
complete qualified sets and every pending/refusal reason, including workspaces
checked by their own custom catalogs. The actual-catalog workspace parity
routes audit every published path against observed authored producers with
fused/unfused compilation and pure emission, alongside ordinary evaluation parity.

Actual packed GPU form checks are shared through `Flow_ir.Packed.gpu_refusals`:
placement, display dispatch and the emitter all refuse non-collecting forms,
multi-source products, skips and ordered accumulators. Output-reachable
constants must stay finite in float32 and noise octaves must be 1–32; unused
constants/noise do not invalidate a program. A one-source Product is already
effective Zip. Ordered accumulators remain refused even when unused. This
runtime backstop remains for hand-built programs and execution boundaries.

`Flow_ir.Packed.compile_result` reports the first actual compilation refusal
with a source span and a concrete state, function, capture, type, form, register
limit, operator, constant or layout reason. Evaluator diagnostic codes are
preserved. The existing option-returning compile APIs and runtime reference
fallback wrap the same result. Declining a child compilation or exceeding the
combined fusion register budget may still produce a valid unfused program;
that successful compilation is not reported as a refusal.

`Eval.Private.static_with_kernels` can observe each actual static entry into
map, reduce, loop or array/sum before materialization, including empty/static
forms and unsupported types. Each handle contains the current checked term,
lexical free captures, graph instance and iteration tuple; repeated entries
are retained and untaken branches stay unvisited. These synthetic handles do
include attempted specializations whose enclosing static evaluation later
defers; they do not establish exhaustive execution coverage. They do
not change ordinary residual identities. The callback is cleared in live
evaluation and when static evaluation exits, so forcing and capture adapters
do not repeat it. Qualification uses these observations, matching physical
authored forms and checked lexical ownership; syntax IDs alone are insufficient
because imports restart IDs and generated forms may use zero. Runtime instance
prefixes and tuple sites are diagnostic provenance, not authored path guesses.

Cook-time specialization uses the instantiated SOP facts, including parameter
overrides, rather than a catalog's default declaration. A regular node with
preserved topology carries its designated input's point-count origin; changed
or undeclared topology starts another origin. Attribute arrays with the same
origin may fuse dynamic multi-input maps. Independent sources retain their
materialization boundaries even when their current lengths happen to agree.
Opaque native algorithms stay `Cooked`, and every CPU attribute program remains
exact; a native declaration's `exact = false` does not invent an approximate
Lisp producer or relax the exact-only catalog boundary.

The host owns an optional `Flow_ir.Profile` with its clock and at most 512
recent execution groups. Packed timings exclude source materialization and
nested groups. Their provenance includes function body cards and the consuming
stage; only that stage displays the duration. Fused members share the `CPU`
badge, beside `t` in card headers, and name the group in the inspector. Reference
fallback reports `Interp`; scalar programs retain `Closure` or `Interp` and
cooked geometry reports `Cooked`. Probe reads never add execution timings.
Value lanes, cooked attribute kernels and prepared drawing share the workspace's
profile; atomic snapshots cross the cook-worker boundary, and a new snapshot
refreshes graph reports without projecting or laying the graph out again.
Reports retain graph-instance identities; the authored pane reads its default
instance, so an override's execution cannot replace its badge or duration.

Full-workspace parity checks lower the same checked document twice with its
actual SOP factories. `Lower.of_checked ~reference:true` independently
interprets value drives and attribute writes while retaining native opaque
catalog cooking. It does not substitute a second catalog. The shared check
compares static plans, instances, arguments, results, states and every recorded
value, then forces all of them at `0`, `0.125`, `1.25` and `7`, at one/eight
domains. Native checks also compare complete cooked payloads, instance
transforms and pixels of every SOP/drawing result. Particle canvases use their
complete 800×600 extent. The two custom-catalog workspaces run this check through
their own executables; the twelve generated fixtures run through it too.

`(noise3 position)` is an ordinary value card with one vec3 input. It uses
seed 0 and raw 0..1 `Rays_math.Noise.sample3` values. The SOP/editor host owns
its declaration through `Flow_sop.Operators.all`; `flow` has no math-layer
dependency. Both the interpreter and packed executor use that declaration's
semantics. Packed selection uses `Flow.Op.packed_kind`: scalar built-ins
require canonical declaration identity, while noise requires an explicit
validated `Packed_ops.Noise3` capability. This capability asserts intrinsic
semantics; code copying an operator and changing its behavior clears it.
An ordinary custom operator with the same name keeps its custom behavior.
Canonical operators without dynamic packed instructions still constant-fold.
`sop/noise_displace :mode "normal_3d"` computes
`P + N * (amplitude * noise3(P * frequency))` at seed 0. The default
`"height_2d"` mode adds signed X/Z noise to Y. Both preserve topology and
invalidate point/vertex normals after displacement.

`(sop/attr geometry :P)` reads positions as `(array vec3)`. Other selectors
read point-owned vec3 attributes, including `:N`; a selector may also be text.
Missing or non-vec3 storage is `E_ATTR_TYPE`. Reads are deferred until the
host has cooked the source geometry. The reference evaluator and packed
executor receive the same immutable attribute resolver; Flow itself has no
geometry dependency.

`(sop/iso_surface :field (fn [p] (- (length p) 1)) :resolution [64 64 64])`
samples an exact float field on a static 65³ XYZ lattice, x fastest. Resolutions
count integral cells; min/max default to `[-2 -2 -2]`/`[2 2 2]`, iso to zero,
and smooth normals to true. Each lattice coordinate uses fused multiply-add,
`Float.fma index ((max-min)/cells) min`, matching native RDK sampling.
Its generated Fn port and typed parameter rails
project through the ordinary function zone. A field-body probe selects one
lattice tuple and reference-evaluates only that call, using the existing bounded
call/body memos and at most 64 sparkline samples. Function call selectors also
cover shared fields and ordinary maps, with stable cumulative call numbers.
Invalid grid/bounds fail at the typed constructor; sample/cook failures are
typed. CPU packed and reference paths remain byte-identical across domains.

`(sop/with_attr geometry :P values)` writes exactly one vec3 per point.
`E_ATTR_COUNT` refuses a different count, and nonfinite components are
`E_NONFINITE`. A position write uses RDK's copy-on-write point ranges; other
selectors create or replace a point vec3 attribute. Topology, groups and
untouched attributes are preserved, including existing normals. Authors use
`sop/normals` after a position edit when shading normals need recomputation.
The operator becomes one cook node, whose packed map program is prepared
once. Live inputs read the cook's frame, and fold inputs receive a snapshot
from the environment-owned value lane. Inline and locally bound `fn` map
bodies can use the CPU tier. See `sketches/flow_kernel/sketch.rays`.

Probes read the immutable geometries returned for the editor's bounded optional
cook targets through that same attribute resolver. A packed map retains a call
template alongside its capped preview records. Selecting an element materializes
the inputs once with the reference walker and records just that function call;
indices beyond 4,096 remain inspectable. Parameter and body cards share the call
memo, and sparklines sample at most 64 calls across the full input. Probe state is
forked from the environment, so inspection does not advance a frame fold. Zone
wire hit boxes are children of the zone, below its controls in PXUI's hit order.

### Frame data and native 2D drawings

An `image` graph returns a cooked `Image` alongside the existing geometry
domain. `image/noise :width :height :frequency :seed` produces row-major,
normalized RGBA samples on the cook worker. Its dimensions default to 256,
frequency to 0.02 and seed to 0; each call is an editable typed card. Geometry
operators refuse image payloads with `E_PAYLOAD`. Deferred image identity uses
`image:<id>` in value keys, avoiding the `i<value>` spelling already used by
integer values. Image and geometry data identities share one allocator.

`sop/attr_from_image geometry image :attribute "image" :channel "r" :uv "uv"`
samples a cooked image at normalized Point UV coordinates into a float
attribute. Its input ports are checked as geometry and image and drawn with
those types; an image graph can supply `(ref image_graph)`. Point Float2/Float3
UV is accepted, channels are `"r"`, `"g"`, `"b"`, `"a"`, and `"luminance"`;
filtering is bilinear with clamped edges and v=0 at the first image row.
Topology is preserved. The constructor/schema/catalog come from one SOP
declaration, including mixed slot types, rather than a checker kind-name case.

The full frame record, `(state [previous init] step)` and packed float/vec3
arrays follow [iteration.md §2.5](workspace/iteration.md#25-frames-frame-folds-and-packed-arrays).
All frame fields are live; array lengths are data, while structural lists
retain T2/T3. A state form has a zone, editable seed rail, step body and
next-value feedback. New drawing calls, including calls nested in arguments,
are ordinary typed cards with editable rows.

A graph with `:context draw` returns `Drawing`. Its operators are
`draw/background`, `draw/point`, `draw/points`, `draw/line`, `draw/rect`,
`draw/circle`, `draw/text`, `draw/translate` and `draw/merge`. Positions,
offsets and rectangle sizes are vec3 data (x/y in logical points, z ignored).
Colors are hex text or RGB vec3s; defaults and keyword types are declared
in `Flow.Op`. `draw/points` consumes a packed vec3 array; it makes one
deferred card regardless of particle count. `draw/merge` preserves painter
order and `draw/translate` scopes a Drawing.

`(ui/canvas (ref picture))` presents that value through native `Scene`
composition inside the panel's clip and translation. Background fills only
that Canvas; it does not clear other panes. Docked, floating, repeated and
bound Canvas leaves keep their own identity. Hiding the UI draws the focused
Canvas over the whole window. The header menu and `/ l c` retype a pane;
`/ n c` opens a floating Canvas. These edits use `Flow_edit` and need a
draw graph to reference (`E_DRAW_GRAPH` when absent).

The add menu lists every Draw operator directly from `Flow.Op`; frame and
array operators use typed defaults. A static Canvas retains one picture per
visible pane, invalidated by a new plan or pane size, so unchanged packed
point arrays are not rebuilt each frame.

`Rays_editor.Workspace.export` uses the same evaluator and Drawing lowering
with a fresh fold and a fixed clock. It pins logical size, step, frame index,
pointer, held keys/buttons and events; `examples/particles/sketch.rays` is
the 10,000-particle reference and its native fixed exports are byte-identical
to the original OCaml example.

## 14. Libraries

| Library | Owns, for Flow |
|---|---|
| `param` | field schemas, with `primary` and `vec3` |
| `flow` | `Syntax` (reader), `Lisp` (printer), `Macro`, `Workspace` (checker), `Eval`, `Ty`, `Port_type`, `Context`, `Check` (catalog descriptors and the manifest reader), `Diagnostic` |
| `frame_input` | immutable logical frame facts, validation and exact cache equality |
| `flow_graph` | `Flow_edit`, `Projection`, `Exposure`, `Probe`, independent of geometry |
| `flow_sop` | `Catalog`, `Manifest`, `Lower`, `Network`, `Port`, `Value_lane`, `Curve` |
| `editor_document` | `Workspace_doc`, `Layout_by_path`, `Contexts` (scene, World, settings and editor lowering), `Scene_sync`, `Preset` |
| `pxui_graph` | `Scope` (the pane) and `Node_menu` |
| `pxui_shell` | the inspector, the list (`Tree`), the status strip and guide |
| `rays_editor` | the keymap, carry, the text pane, cook scheduling |
| `ppx/ppx_rays` | `[@sop.primary]`, `[@sop.vec3]`, `[@@sop.node_key]`, `[@@sop.node_slots]` |

`test/dependency_gate.ml` enforces the edges; the root `AGENTS.md` and `backend.md` state
them.

## 15. Performance

Rules from the root `AGENTS.md` apply. What the code holds itself to:

- A graph-pane frame costs what is in view, never the size of the graph
  (`lib/pxui_graph/AGENTS.md`); hidden iterations are never built, a zone draws its body
  once.
- The value lane does no work for networks without drives.
- A frame never re-lowers.

Benchmarks: `tools/bench_rays_editor.exe`, `tools/bench_workspace_lower.exe`,
`tools/bench_workspace_live.exe`, and `dune exec test/test_main.exe -- bench_scope_big`.

## 16. Tests

Window-free logic tests in `runtest`: the reader, printer, macros, checker and evaluator
(`lib/flow/test_*.ml`), threading round trips over every checked-in workspace
(`test/test_threading.ml`), edits (`lib/flow_sop/test_workspace_edit.ml`), projection and probes
(`lib/flow_sop/test_projection.ml`, `test/test_probe.ml`), the pane's gestures
(`lib/pxui_graph/test_pxui_graph.ml`), the document and its layout (`test/test_workspace_doc.ml`),
lowering, zones and live values (`lib/flow_sop/test_workspace_cook.ml`, `lib/flow_sop/test_workspace_zone.ml`,
`lib/flow_sop/test_workspace_live.ml`), the shell and its layout forms (`test/test_workspace_shell.ml`),
the text pane (`test/test_text_pane.ml`), the carry (`lib/pxui/test_ui.ml`,
`test/test_pxui_graph.ml`, `test/test_materials.ml`), and the gate. Visual checks are in
`@runtest-native`.

## 17. Deferred

Fields and the diamond socket as data; zoom-to-enter; a `[%workspace]` PPX with generated
input records (register O2); procedural macros; a per-node cache ring for scrubbing; a file
dropped from Finder (§7.12).

## 18. Decisions

| Decision | Choice |
|---|---|
| The document | the workspace text; graphs, networks and cards are derived from it and nothing is stored beside it but layout |
| Identity | the lexical path of a binding; a nested node's leaf is `holder#input` |
| Edits | one variant (`Flow_edit.op`) and one `apply` that prints, re-parses and re-checks; a refused edit changes nothing |
| Wire shape | straight segments with computed bends; no curves, no authored bends, no wireless wires |
| Levels | explicit (`o`, `p`), never zoom-driven |
| Viewing a node | `v` is a per-object lexical preview request outside the source, layout and history; loop selectors choose its tuple |
| Vec3 | metadata grouping of three float fields; no new `Param.value` case |
| Names in the language | stable keys and field names verbatim (`noise_displace`, `size_x`) |
| Float spelling | one printer, shortest round-trip, always a `.`, never an exponent; the reader accepts exponents |
| Positional after keyword | allowed; positionals are numbered in written order, an input given twice is `E_DUPLICATE_PARAM` |
| Nesting limit | 256, `->` steps included |
| Macros | quasiquote templates only |
| Stale layout entries | pruned on load and on structural edits, never an error |
| Viewport navigation | view state, also with follow-viewport; not an undo entry |
| Fixed panel sizes (2026-10-05) | `:first_size` / `:second_size` on `ui/split`: one concept, on the split that the gutter drag rewrites; `ui/split-at` stays the ratio form (§11.11) |
| Start keywords (2026-10-05) | keywords on the panel forms (`:focus`, `:look_through`, `:view`, `:tab`), followed when the document opens and whenever their value in the text changes; saved UI state stays in `(layout ...)` |
| Panel instances (2026-10-05) | every leaf is an instance with its own view state; the level and its selection belong to a graph panel; a binding used twice makes two instances keyed by place |
| Following a graph panel (2026-10-05) | `:of binding` on `ui/inspector`, `ui/list`, `ui/lisp`: one keyword, a panel-typed wire in the graph; without it the panel follows the focus |
| Layout forms in the printer (2026-10-05) | `ui/` calls are never threaded with `->` |
| Guide | on by default, persisted off |
| Edit timings (2026-10-07) | the status strip and crash report retain the last document edit's print, parse, check, evaluate, lower, project, layout, reduce and cook durations; `Flow.Phase_timer` also exposes invocation counts for regressions |
| Checked lowering (2026-10-07) | document edits check once; `Lower.of_checked` evaluates once with recording and graph probes reuse that evaluation, including its plan and state folds |
| Edit-frame gate (2026-10-07) | a scrub frame without the recook its value requires costs no more than a layout-drag frame at the same node count (`bench_rays_editor`'s `scrub_edit` row), with zero print/parse/check/evaluate/lower/project/layout; every checked-in `.rays` literal saves the full path's bytes and refuses with its code (`test_workspace_doc`); `(ref g)` is never a binding read |
| Wheel and trackpad scroll | zoom at the pointer; right-drag and middle-drag pan |

### Packed drawings and workspace effects (P3)

`draw/circle`, `draw/rect` and `draw/line` preserve fractional logical coordinates and use the
same 64-byte SDF instance layout as their plural forms. `draw/circles positions :radius` accepts
a scalar radius or packed float radii; `draw/rects positions sizes` accepts one vec3 size or
packed vec3 sizes; `draw/lines from to :color :width` accepts equal-length packed vec3 arrays.
Lengths and finite float32 bounds are checked before publication. Circles and rectangles accept
one `:fill`/`:stroke` color or a packed RGB array with exactly one entry per position. The latter
is used by the generative and noise examples. Line width is shared by the batch. Every batch
retains painter order and enclosing transforms, clip and blend state; unchanged instance bytes
retain their upload. `draw/points` keeps the established `Ink` rasterization.

`draw/rotate angle drawing` uses radians. `draw/scale factor drawing` accepts a scalar or vec3
(x/y). `draw/rounded_rect at size :radius :fill :stroke`, `draw/polygon points :fill :stroke` and
`draw/polyline points :color` use the existing Scene constructors. `draw/merge` also accepts
lists of drawings, permitting a level fold to collect its output. Colors are hex text, normalized
RGB vec3, or `(list r g b a)` with normalized alpha. `color/hsl h s l` uses hue in degrees and
returns RGB; `color/hsla h s l a` returns that four-component list. `color/gradient stops x`
uses the native gradient's clamped interpolation and quantization and returns packed-compatible
RGB (its stops must be opaque). `noise3 p :seed :octaves` defaults to seed 0 and one octave;
1–32 octaves use native fBm with lacunarity 2 and gain 0.5. Seeds retain their native immutable
permutation table in a per-domain cache of 16 tables. `noise3 [x y 0]` is the 2D form.

The `host` context returns effect values or collections of them. `host/quit when`,
`host/save_png path when`, `host/dialog kind when :filters :default`, and
`host/play sample when :volume :loops` return deferred `effect` nodes.
`audio/synth :waveform :frequency :duration :volume` and `audio/load path` return `sample`
nodes. Waveforms are `sine`, `square`, `triangle`, `sawtooth`; defaults are sine, 440 Hz,
0.1 seconds, full volume. Dialog kinds are `open_file`, `open_files`, `save_file`, `open_folder`.
Filters are `(list {:label "Images" :extensions (list "png" "jpg")} {:label "All" :extensions (list)})`.
The editor graph connects them with `(ui/workspace root :effects (ref actions))`. These remain
ordinary graph cards with editable rows. Host effects execute on a false-to-true edge after value
lane evaluation; screenshots are captured after presentation. File-dialog results return in the
existing `frame/input` events. Export rejects active quit/dialog effects with `E_EFFECT_EXPORT`
and never initializes or plays audio; screenshot effects remain deterministic. Inactive quit or
dialog declarations can therefore coexist with exportable drawings.

Each workspace pins at most 64 distinct audio samples and 64 images, keyed by their evaluated
arguments. Capacity and backend errors are typed `E_AUDIO`/`E_IMAGE`; a live resource is never
evicted from a retained scene. Host close destroys owned resources before runtime close and
shuts down audio only if it initialized it.

The example ports also use `array/slice array first count` (a checked owned slice) and
`array/concat first second` (matching packed element types), retaining packed stroke data.
`int/mul`, `int/div`, `int/and` and `int/xor` preserve native OCaml integer bits, including
wrapping multiplication. They support the recursive rectangle example's original palette hash
without converting its large integer products through a float. Division by zero is `E_RANGE`.

`equal? a b` compares data (including event text); numeric `=` keeps its numeric contract.
`exp x` supplies native exponential damping. Pure-data folds/scans may follow a live list
length, still with the 4096-iteration evaluator bound; geometry folds keep their fixed topology
rule. Drawing topology stays fixed; dynamic stroke data feeds statically declared batch nodes.
Dialog filters use records `(list {:label "Images" :extensions (list "png" "jpg")})`.

Host-context state folds advance once per logical host frame, including while the animation
timeline is paused. Draw/value/SOP state continues to follow the timeline index, so seeking and
fixed-step exports retain their existing deterministic playback semantics. The internal
`Frame_input.tick` is the raw host frame count; exports set it equal to the timeline frame.
A successful dialog request returns a `frame/input` event of kind `dialog-opened` with its real
`:id` on the following frame; subsequent `file-dialog` events carry that same request ID.
Fixed-step window runs use the export effect policy: active quit/dialog requests return
`E_EFFECT_EXPORT`, audio does not initialize, and screenshot effects capture after presentation.

### Images

`image/noise :width :height :frequency :seed`, `image/load path`, and
`image/render drawing :width :height`, and
`image/map (fn [uv] [uv.x uv.y 0.5 1]) :width :height` return image values in every value-capable
context. Noise defaults to 256×256, frequency 0.02 and seed 0. `:freq` remains an
alias for frequency. Render dimensions default to the logical frame size.
`draw/image image :at [0 0 0] :scale 1.0 :angle 0.0` uses the ordinary canvas pane.
Loaded images share ownership by path; generated images share their static parameters;
rendered images share their producer and plan. The workspace pins at most 64 image
resources, releases each once on close, and returns `E_IMAGE` on resource failures.
Live rendering replaces pixels in the same owned image. SOP consumers receive an immutable
RGBA snapshot resolved on the initial domain before a worker starts. `image/render` uses
the native offscreen Metal Canvas, including during fixed-step export.

`(exact image)` explicitly freezes the current successful display publication as
an immutable RGBA8 image. A GPU publication is read back once per source identity,
generation and dimensions at that exact site in the current plan. Repeated requests
reuse the snapshot; a changed publication or replan creates a distinct native image
and CPU payload. Previously constructed scenes retain their frozen pixels. These
versions remain pinned under the workspace's existing 64-image limit, including
their source images; admission failure returns `E_IMAGE` before reading pixels.
An expired source is refused even when a frozen version is cached. CPU snapshots
remain valid after close, while native resources are released once. Frozen images
remain image resources: state rejects them, including aliases, lists, records and
opaque values, before exposing a seed or storing a step. Graph image inputs accept
them. Numeric and packed-array `exact` retain their existing data semantics.

`image/map` requires a Vec2-to-Vec4 function and defaults to 256×256. Its
function input is an editable graph zone with typed UV rails. Pixel centers
are `((x+0.5)/width, (y+0.5)/height)`, with the top row first and x varying
fastest. The prepared CPU map preserves lexical captures and live frame facts;
four finite channels are clamped, scaled by 255 and rounded ties to even into
owned RGBA8 storage. Unsupported packed bodies return the actual compilation
refusal. Authored image qualification also covers these instantiated pixel
functions. Qualified workspace display can select the GPU through the existing
measured placement policy, convert/copy completed output to RGBA8 and publish a
resident image for draw/image, UI and mesh consumers. One owner retains at most
64 authored image sites; failed new publications consume no sink slot. An ordinary
CPU request has its own immutable payload and validity stamp: it does not read
or replace the displayed GPU image, and exact-first map cooking creates no
runtime image. Ordinary CPU image/render requests cook child CPU payloads so nested
GPU display cannot change ordinary CPU rounding; an explicit `(exact image)` child
uses its frozen bytes. Display image/render retains a native
Canvas and publishes its texture through the same image boundary. Connected
timing/allocation gates are qualified for the measured uncaptured fixtures in
the performance log. Actual-owner captured geometry, expanded owner qualification,
frozen exact snapshots and changing-source timing gates are also qualified there.
The largest changing-source GPU producer passes its median gate at4.755571 ms,
with range4.344505–5.610975 ms; this is not a worst-case bound.

`scene/geometry geometry :texture image` applies the same image as a texture
without changing its transform, material or render state. The image card footer
shows dimensions, and its inspector borrows an owned thumbnail through the
existing UI image batch. `sop/attr_from_image geometry image :attribute "image"
:channel "r" :uv "uv"` samples Point UV coordinates with clamped bilinear
interpolation. Channels are `r`, `g`, `b`, `a`, and `luminance`;
`sop/grid :uv_attribute "uv"` creates the required Point Float2 coordinates.

GPU display values remain opaque identity/count/generation tokens. Workspace
owners retain at most 64 producer runners, 64 pipelines and 64 styled drawing
sinks, close sinks before their GPU lease, and reject stale generations. A
four-byte status read validates finite shader intermediates and outputs without
reading back the packed array. Each runner input slot retains only its last
successfully uploaded immutable array and covered length. An unchanged source
reuses that upload; a replacement array, changed length or replaced buffer
requires another upload. A failed upload invalidates the prior source before
the write, so a partially overwritten buffer cannot be reused as the old
source. Frame uniforms and validation status are written on every dispatch;
close releases both the buffer and retained array. Compile, GPU execution and explicit readback have separate tier
reports. The GPU badge's group time is the completed device dispatch duration
when timestamps are supported, otherwise wall time. Production placement compares
the measured native GPU row of the Flow IR cost table (pack, upload and dispatch, plus the
resident circle conversion for a display sink or the readback row for `(exact x)`) with the
CPU kernel tier plus CPU instance building; an unmeasured backend keeps CPU. For an input-independent packed producer,
`sop/with_attr` with `(exact x)` materializes selected GPU output on the initial
domain before submitting CPU geometry work. The cook worker receives an owned
CPU array. Attribute-reading cones retain their cooked-input CPU route.
Fixed-step runs,
exports and reference comparisons continue to use CPU execution; the unstable
qualification hook exists only to exercise and measure native selection.

The `Flow_gpu.Image_sink` conversion boundary accepts only a current
width-four output with one element per requested pixel. It writes one
reusable padded RGBA8 buffer, copies into a reusable texture, and publishes
a generation-checked borrowed token after completion. Unchanged dimensions
create no persistent resources; resize and failed writes invalidate previous
tokens. Workspace publication and resident consumers use this boundary;
explicit `(exact image)` freezes the publication through the resource owner.
