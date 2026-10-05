# Rays Flow: the SOP network editor

## 1. Status and authority

Status: approved design, revision 3 (2026-09-28). **M1–M7 implemented; the
workspace plan (W0–W12, `workspace/plan.md`) is implemented too and supersedes
the text form of this file.** Milestones M1–M7, the file-level tasks for each,
progress and the W12 removals live in `flow-migration.md`. What W12 deleted
(the v3 text checker, printer and builder, `Flow_sop.Program`, the `[%flow]`
PPX and the `?program` editor argument) is marked where it is described below;
those paragraphs are the origin of the value semantics, not a guide to code
that still exists. The language, the projection pane, probes, the editable text
pane, contexts, the composable shell and `.rays` sketches are specified in
`workspace/` (`iteration.md` §2 and §7 are normative). The behavioral reference is the prototype at
`specification/flow/prototype/index.html` (open it in a browser; no build).

Authority, in order:

1. This file.
2. The prototype, for behavior this file does not pin down.
3. Other specifications (`pxui.md`, `procedural.md`, `api.md`, `scene.md`),
   **only** for areas whose milestone has not landed. Each of those files
   marks the paragraphs that a milestone replaces.

Rules for implementers:

- Implement milestones in order. Do not add hooks for a later milestone to an
  earlier one. A milestone is finished only when its tests, docs and status
  row in `flow-migration.md` are done.
- Keep the current editor working at every commit; default `dune runtest` stays
  green.
- The prototype is HTML/JS reference material. It is never linked, built, or
  shipped, and is not a browser fallback.
- If implementation shows that this spec is wrong, change this spec (and the
  prototype, if affected) in the same change as the code, and record the
  decision in §18.

> Status (Gap A, 2026-09-30): value nodes, compounds and expression drives described below were deleted with the
> flat pane; read them as historical design. The live model is `.rays` workspace text.

## 2. Scope, non-goals and vocabulary

In scope: the SOP network canvas; keys and guide mode; the inspector's role;
graph, list and text views; value ports, value nodes and drives; compounds;
per-level contexts; the canonical Lisp text form with its reader and checker;
the `[%flow]` PPX (removed in W12); workspace presets (s-expressions).

Not in scope (do not build): Bézier wires anywhere in the graph; an editable
text view in the editor; per-element fields (the diamond socket and `Field`
port type are reserved names only); zoom-to-enter; modulation depth rings;
macros; exposing `defgraph` as OCaml functions; sharing cooked results between
compound instances; the scene-graph conversion (a later spec revision after
M7); any Python or JavaScript in the build.

| Term | Meaning |
|---|---|
| network | One editable graph: today's `Document.network` (a SOP network, the scene, or the World's layers) |
| level | The network the graph pane shows (`Document.level`), extended with compound paths in M5 |
| context | What a network is about: `sop`, `value`; reserved `scene`, `world`. Decides the port types and the catalog that short names resolve to |
| kind | A node type: a SOP factory (`sop/<key>`), a value kind (`value/<key>`), or a compound definition (`user/<name>`) |
| slot | A geometry input of a SOP node (today's `Edit_graph` input index) |
| parameter | A schema field of a node (`Param.field`) |
| row | One slot, parameter, vec3 component, or output shown on a card |
| port | A slot, parameter or output that a wire can attach to |
| literal | The value stored in a node's parameter record |
| drive | What overrides a literal while cooking: a wire from a value output, or an expression |
| wireless | A wire drawn only while one of its ends is selected or hovered (view flag, same semantics) |
| compound | A node whose kind is a definition: an inner network with an interface |
| layout | Per-network view metadata saved with the document: positions, levels, pins, splits, bends, wireless flags |
| trunk | The chain of primary geometry slots; it runs through node headers |
| level of detail | `point`, `chip`, `card` or `full` (§6.4) |
| display node | The node the viewport cooks (today's VIEW flag) |

## 3. Document model

### 3.1 Contexts

Every network has a context. Before M5 the SOP networks are `sop`, the
scene network is `scene` and World networks are `world`; only `sop` networks
get value ports, value nodes and drives (M3). The scene and World canvases keep
their current behavior (plus M1 rendering and M2 keys) until the scene
revision of this spec. A compound definition declares its context; a `value`
definition contains only value nodes and may be used in any context.

### 3.2 Port types and coercions

| Type | Comes from | Socket | Drivable |
|---|---|---|---|
| Geometry | SOP slots and outputs | square 9×9 | wire only |
| Float | `Param.Floating` fields, value outputs | circle r 4.5 | yes |
| Int | `Param.Integer` fields | circle r 4.5 | yes |
| Bool | `Param.Toggle` fields | circle r 4.5 | yes |
| Vec3 | three float fields grouped with `[@sop.vec3]` (§5.3); `combine_xyz` output | circle r 4.5 | yes, whole or per component |
| Text, Choice, Encoded | `Param.Text`, `Choice`, `Encoded` | none | no; literal only |
| Field | reserved | diamond | not in this revision |

Coercions happen when a drive's value reaches a port, never in storage:

| From → to | Rule |
|---|---|
| Int → Float | IEEE double conversion (integers beyond its 53-bit precision may round) |
| Float → Int | finite values: `Float.round`, saturate the machine int range, then the field's hard bounds through `Param.apply`; non-finite values are errors |
| Float or Int → Bool | nonzero is `true` |
| Bool → Float or Int | `true` is 1 |
| Float, Int or Bool → Vec3 | broadcast to all three components |
| Vec3 → scalar, Geometry ↔ anything else | rejected when connecting (`E_TYPE`) |

### 3.3 Kinds

- **SOP kinds** are the registered factories (`Sop_catalog.Editor.factories`).
  Symbol `sop/<key>` where `<key>` is the factory's stable key verbatim
  (`uv_sphere`, `noise_displace`). Keys match `[a-z][a-z0-9_]*` (PPX check,
  M3) and are never renamed; a rename ships an alias (§11.4).
- **Value kinds** live in the new `flow` library and are context-free. Each has
  a `Param` schema, so the inspector renders them like SOPs:

| Kind | Inputs (default) | Outputs | Semantics |
|---|---|---|---|
| `time` | `speed` Float (1) | `t` Float | context time in seconds × speed |
| `value` | `v` Float (0) | `out` Float | `v` |
| `math` | `op` Choice (`mul`), `a` Float (0), `b` Float (1; hidden for unary ops) | `out` Float | see ops below |
| `combine_xyz` | `x`, `y`, `z` Float (0) | `out` Vec3 | |
| `separate_xyz` | `v` Vec3 (0,0,0) | `x`, `y`, `z` Float | |
| `remap` | `v` Float (0), `from_min` 0, `from_max` 1, `to_min` 0, `to_max` 1, `clamp` Bool (false) | `out` Float | linear map; `from_min = from_max` gives `to_min`; clamp limits the input fraction to [0,1], including reversed ranges |

Math ops (radians, IEEE doubles, no exceptions): `add`, `sub`, `mul`,
`div` (b = 0 gives 0), `pow` (|a|^b), `min`, `max`, `sin`, `cos`, `abs`,
`floor`, `sqrt` (of |a|). The Lisp spells them `+ - * / pow min max sin cos
abs floor sqrt`.

- **Compound kinds** are definitions (§3.8), symbol `user/<name>`.

### 3.4 Ports and port paths

A port is `{ node : int; path : string }`. Paths:

- a slot name, a parameter name, or a vec3 group name;
- `<group>.x`, `<group>.y`, `<group>.z` for one vec3 component;
- output names on the source side (`t`, `out`, `x`…; SOP geometry output is `geo`).

Slot names come from `[@@sop.node_slots "input, target"]` (new in M3); a SOP
without the attribute names its slots `in0`, `in1`, …. Inside a vec3 group the
underlying field names (`center_x`) are not addressable; the group name is.

### 3.5 Literals and drives

Every parameter keeps its literal in the node's record (today's behavior).
A drive is optional per port:

```ocaml
type drive =
  | Wire of { node : int; output : string }   (* a value node's output *)
  | Expr of Flow.Expr.t
```

While a port is driven, cooking uses the driven value (§13) and the stored
literal is untouched, so removing the drive (`r`, inspector "reset") restores
it. A vec3 port is driven either whole (`center`) or per component
(`center.y`), never both at once.

`Flow.Expr.t`:

```ocaml
type op = Add | Sub | Mul | Div | Pow | Min | Max | Sin | Cos | Abs | Floor | Sqrt
type t = Num of float | Time | Op of op * t list   (* arity checked on construction *)
```

The infix form typed into fields: numbers, `t`, `pi`, `+ - * / ^`, unary
minus, parentheses, calls `sin(x) cos(x) abs(x) floor(x) sqrt(x) min(a, b)
max(a, b) pow(a, b)`. Unary minus binds tighter than `^`, following the
prototype. `^` is right-associative; `*` `/` bind tighter than `+` `-`.
Printers preserve the operation tree, including parentheses around a
right-nested sum or product; IEEE arithmetic is not reassociated.
Parse errors are values (`(t, Flow.Diagnostic.t) result`), never
exceptions. Fields also accept the s-expression form when the text starts
with `(`. A known operator head followed by whitespace prefers s-expression
parsing, with infix as a fallback; otherwise infix is tried first. This makes
`(- -2 -0)` unambiguously a subtraction. Fields print infix with minimal
parentheses; the text form prints
s-expressions (§11.7).

### 3.6 Edges

Every input port has at most one incoming edge, so an edge is identified by
its destination port. There are no edge ids.

- Geometry edges are today's `Edit_graph` connections (consumer, input index);
  the destination port is `{ node = consumer; path = slot name }`.
- Value edges are `Wire` drives whose destination is a SOP parameter or a
  value-node input.
- Bends and wireless flags are layout keyed by destination port (§4.1).

### 3.7 The `sop` network overlay

`Edit_graph` retains geometry topology and gains a per-entry bypass flag in
M2. A bypassed SOP passes its primary slot through, including packed
instances; without a connected primary slot it produces empty geometry.
Other slots are not cooked while bypassed. The flag preserves the node's
identity, literal record and wiring and is saved as `^:bypass` in the workspace text.
In the existing scene and World contexts, bypass suppresses the selected
object's or layer's contribution while retaining parent transforms and
the layer stack. It does not overwrite visibility literals.
The `sop` context adds an overlay beside it in the new `flow_sop` library:

```ocaml
(* lib/flow_sop/network.mli *)
type t = private {
  geometry : Procedural.Edit_graph.t;       (* SOP nodes and geometry edges, as today *)
  values : Flow.Graph.t;                    (* value nodes: kind, label, literal record *)
  drives : Drive.t Port.Map.t;              (* destination -> drive *)
  geometry_outputs : string Port.Map.t;     (* destination -> named compound source output; absent = geo *)
  instances : Instance.t Int_map.t;         (* compound nodes (M5) *)
}
```

Node ids share one space per network. Value-node ids are allocated from the
same process-wide source as `Procedural.Node` (`Node.Private.fresh_id`,
exposed in M3). Loading validates disjointness.

### 3.8 Compounds (M5)

```ocaml
type interface_port = {
  name : string; ty : Port_type.t; default : Port.literal option;
  label : string; soft : (float * float) option;
}
type definition = {
  name : string;                  (* user/<name>; [a-z][a-z0-9_]* *)
  context : Context.t;
  inputs : interface_port list;   (* geometry first *)
  outputs : interface_port list;
  body : Network.t;               (* contains exactly one Inputs and one Outputs node *)
}
```

- Definitions are shared: a document holds `definitions : definition
  String_map.t`, and an instance node stores only the definition name, its
  interface literals and its drives. Editing inside an instance edits the
  definition; "make unique" copies it under a new name.
- Definitions may nest; a definition that reaches itself is rejected (`E_RECURSIVE`).
- Compile inlines definitions (§13.3).

### 3.9 Identity

- Node ids are unique within a network and never reused for another node.
  Paste allocates fresh ids (today's behavior).
- A label is display only. Binding names in the text form derive from labels
  (§11.7); renaming never changes an id.
- Compiled ids for compound internals are allocated once per
  (instance id, inner id) pair and stored in the document, so they stay stable
  across edits and sessions (§13.3).

### 3.10 Invariants (checked by `Flow_sop.Network.validate` on load and in tests)

1. Every drive's destination exists, is drivable (§3.2), and is not both
   whole-vec3 and per-component driven.
2. Every `Wire` source is a value-node output; the value graph plus drives is
   acyclic.
3. Types are compatible after coercion (§3.2).
4. No id is both a SOP node and a value node.
5. Every instance names an existing definition of a compatible context;
   definitions are acyclic.
6. Layout keys refer to existing nodes and ports; coordinates are finite.

### 3.11 Operations

All edits are pure functions returning `(Network.t, Flow.Diagnostic.t) result`:
`add_value_node`, `remove_nodes` (SOP and value alike, drives into and out of
them removed), `connect_value` (source output → destination port),
`disconnect` (by destination), `set_literal`, `set_expr`, `clear_drive`,
`fold`, `unfold` (§7.7), `group`, `ungroup`, `export`, `unexport`,
`rename_interface_port`, `reorder_interface`, `make_unique` (§7.8). Existing
`Edit_graph` operations (connect geometry, insert on connection, copy, paste,
parameters) keep their current API; `flow_sop` wraps them so drives and layout
follow node ids through paste and delete.

## 4. Layout, view state and history

### 4.1 Layout (saved with the document, undoable)

`Document.network.layout` changes from `(float * float) Layout.t` to:

```ocaml
type level = Point | Chip | Card | Full
type layout = {
  at : (float * float) Int_map.t;               (* graph-space top-left, snapped to 12 pt *)
  level : level Int_map.t;                      (* absent: Card for SOP nodes, Chip for time *)
  pinned : bool Int_map.t;                      (* opened explicitly: ignores zoom caps *)
  rows : bool String_map.t Int_map.t;           (* per node: row -> shown on card (the s pin) *)
  split : String_set.t Int_map.t;               (* per node: vec3 groups shown as x/y/z rows *)
  bends : (float * float) list Port.Map.t;      (* by destination port *)
  wireless : Port.Set.t;                        (* by destination port *)
}
```

`display` stays where it is today (`Document.network.displayed`).
`Network_view.edit` keeps its rule: an edit frame updates only the ids and
ports that frame touched.

### 4.2 View state (not saved in the document, not undoable)

Selection, hover, pan and zoom, the open projection per level (graph, list,
text; today's per-level list/graph memory extended), hint mode, search, guide
on/off (persisted in user preferences through `Editor_core.Store`).

### 4.3 History

Each gesture is one `Editor_core.History` entry with a label shown as
"Undo <label>":

| Gesture | Label | Merge |
|---|---|---|
| Move nodes | Move | `Gesture "graph.move:<level>"` until release |
| Bend drag, add, remove | Bend wire | `Gesture "graph.bend:<port>"` |
| Scrub a row | Set <parameter> | `Gesture "graph.scrub:<node>:<path>"` |
| Type a value or expression | Set <parameter> / Expression on <parameter> | `Step` |
| Connect, pick up, bind, knife | Connect / Disconnect / Bind / Cut wires | `Step` |
| Level, pin, row pin, split changes | Detail level | `Burst { key = "layout.level:<level>"; window = 1.0 }` |
| Fold, unfold, group, ungroup, export | Fold / Unfold / Group / Ungroup / Export <parameter> | `Step` |
| Add via Tab or `.` (including the ripple move) | Add <kind label> | `Step` |

Undo restores selection only where the selected ids still exist.

### 4.4 Presets

A preset is one s-expression file (`.rays`), the same text a workspace
sketch is written in: the `(workspace ...)` form with its comments, then
optional `(layout ...)` (tile positions, pins, row exposure, bends, wireless
flags, collapsed zones and frames, keyed by lexical path, so they survive text
edits), `(settings :name value ...)` for settings that differ from their
default, and `(view {...})` for the environment's camera and render settings.
Nothing else is written: no JSON, no version number, and no reader for older
presets (the migration removed the old editor representation without a
compatibility layer). A file that does not parse, check or lower is
rejected without changing the installed document; only a workspace document
can be saved. See `workspace/plan.md` W3.

## 5. Exposure: which rows a card shows

### 5.1 The rule

For each parameter row of a node at level `card`, evaluated in order:

1. Geometry slots always show. Primary slot 0 is in the header, not a row.
2. A driven row (wire, wireless, expression, or any driven vec3 component)
   shows. Pins cannot hide it.
3. If the row has a pin (`layout.rows`), the pin decides.
4. A row whose literal differs from its schema default shows.
5. A primary row (§5.2) shows.
6. Otherwise it is hidden, and the card ends with a `+ N more` row.

The inactive `b` input of unary Math keeps its literal and drives. It is
hidden after rules 2–3 unless explicitly pinned; changing `op` never deletes
its data. Full shows it dimmed when neither driven nor pinned.

The canvas card applies rules 1 to 4 and 6: a primary row (rule 5) that is neither wired nor written stays
behind `+ N more` so that the fixture's layout shows its cards at zoom 1 as `workspace.html` does; `Exposure.shown`
still takes `primary`, and Full, the list and the inspector show it.

Level `full` shows every row, grouped under folder headers in schema order,
with rows that fail the rule drawn dimmed, and ends with `− show fewer`.
Compound nodes and the Inputs/Outputs nodes show every interface row.
Non-drivable rows (Text, Choice, Encoded) follow the same rule and render as
fields without sockets. The rule is the same function for the canvas, the
list badges and the inspector's ● toggle (`Flow_sop.Exposure.shown`).

### 5.2 Primary rows

`[@sop.primary]` on a field marks it primary (new PPX attribute, M3; sets
`Param.field.primary`). A schema with no primary field treats the fields of
its first folder, in declaration order, as primary (the first field's folder,
including the empty folder). Value kinds mark every input primary.

### 5.3 Vec3 grouping

`[@sop.vec3 "center"]` on three consecutive float fields groups them into
the vec3 port `center` with components x, y, z in declaration order. The PPX
rejects a group that is not exactly three consecutive `float` fields in one
folder, or a group name equal to another field's name. The record keeps its
three fields, so cook code does not change. `Param.field` gains
`vec3 : (string * int) option` (group name, component index).
In M3 every catalog triple named `*_x/_y/_z` (89 float triples, 267 fields
in the current catalog) is annotated; the group name is the common prefix.
If that prefix already names another field, use `<prefix>_vector` (Ray's
`direction_vector` keeps its `direction` choice field unambiguous).

### 5.4 Split vectors

A vec3 row shows one socket and three fields (x, y, z). Clicking its name, or
the inspector's `xyz` button, toggles `layout.split`: split rows show a header
row with the live vector and three component rows, each with its own socket.
Joining is refused while any component is driven; splitting is refused while
the whole vector is driven (toast names the fix: `r` first). Wiring or typing
an expression into a component splits automatically.

## 6. Canvas

### 6.1 Direction and auto layout

Data flows left to right. Auto layout (context menu and palette only, as
today; also for code graphs): column =
longest path from any source over all edges, then move each upstream node
right to the column immediately before its earliest consumer (processing
consumers first); destinations of shared sources retain their initial column
so tightening does not stretch a fan-out across its siblings. This keeps short branches near their join rather than
stretching them across unrelated columns. Starting at each output, lay out
its upstream input branches in separate vertical bands in port order;
place the consumer between its input branches. Shared sources are placed once.
Independent outputs get separate bands. Keep at least 36 points between cards
in a column, 60 between input branches, and 96 between independent outputs;
x = column × (W + 60), with
positions on the 24-point dot lattice (Package B: a card's top-left corner is on a dot; a card whose header
in-port reads another card lines up with it). Ascending id keeps disconnected nodes deterministic.
Reserve the requested card/full height regardless of the current zoom cap;
re-layout at point/chip zoom must leave space for the cards on zoom-in.
Align unary chains at their header sockets. Re-layout clears old bend points
along with moving nodes; the host saves the result as one undoable view edit.

This is a deterministic branch heuristic, not a globally optimal DAG drawing.
Dense shared cross-branch graphs can still need manual bends; dummy edge lanes
and constrained layer sweeps are the next step if those graphs become common.
The decomposition follows the separation of ranking, ordering and placement
used by [ELK Layered](https://eclipse.dev/elk/blog/posts/2025/25-08-21-layered.html)
and [Graphviz dot](https://graphviz.org/docs/layouts/dot/), without adding a runtime dependency.

### 6.2 Node geometry (logical points, kit font, 24-point rows)

| Element | Geometry |
|---|---|
| Card width `W` | 196 (today's `node_width`) |
| Header | 24 high; 10×10 type square at (7, 7); label at x 24, baseline 16; truncated with … to fit |
| Rows | 24 high each below the header; body bottom padding 6; corner radius 3 |
| Primary slot socket | header left edge, y 12 |
| Single output socket | header right edge, y 12. Multiple outputs are rows at the top of the body, right-aligned |
| Row socket | left edge, row centre |
| Row label | x 14 (vec3 components x 26, in the vec colour) |
| Scalar field | 76×16 at x `W − 84`, soft-range fill, value right-aligned |
| Vec3 fields | three 34×16 fields at x 82, 118, 154 with axis letters |
| Choice field | 98×16 at x `W − 106`; click cycles, Shift-click back |
| Driven row | right-aligned `← <source> <live value>`; `⌁` instead of `←` when wireless |
| Fold button ƒ | 14×14 at x `W − 104` on rows whose drive is foldable or is an expression |
| Expression field | 76×16 accent field showing the infix text |
| Folder header row (full) | uppercase folder name in the accent colour at x 10, then a rule |
| More row | `+ N more` / `− show fewer`, accent text, whole row clickable |
| VIEW flag | 26×12 filled accent at the header's right; `M` tag for muted; `+N` badge on chips counts driven rows |

Positions of nodes and bend points snap to a 12-point grid.

**Kit rev 3 (current, supersedes the table where they differ).** A Card is its header plus the rows that are
wired or written (§5.1 rules 1 to 4); there is no `+ N more` row. The footer row (value, spark, cook
time) is drawn on Full only: geometry reads `1 204 pts · 0.003 s`, the cook time from
`Probe.geometry.seconds`. Boxes are laid out at the level the zoom shows (`shown`): a point is as wide as
its name drawn at the zoom's font, a chip is the header, so ports, wire ends and obstacles come from the
one geometry. Positions sit on the 24-point lattice and columns on a 288-point pitch (196 card plus 92
gap, rounded up). A scope's inputs stack in the order written.

### 6.3 Wires

- A wire is a polyline: source port, a 14-point stub (right from outputs,
  left into row and header sockets, down into chip bottom attachments),
  the bend points in order, the destination stub, the destination port.
  Rendered with `Ui.line` segments; no curves.
- Widths: Geometry 2.4, Float and Int 1.5, Vec3 1.8, Bool 1.5. Wireless:
  dashed 2/5, drawn only while either end is selected or hovered or the
  selected wire is it, or `w` is on.
- Hit tolerance: 6 points either side of any segment. Alt-click on a wire
  inserts a bend point at the click, in the segment nearest the pointer, and
  starts dragging it. Alt-click or double-click on a bend point removes it.
- Selected wire: an 8-point accent halo at 28% opacity. Bend handles are 7×7
  squares.
- Scalar and vec3 wires carry a live readout (10-point text 6 points above the
  polyline's arc-length midpoint, `paint-order: stroke` style outline in the
  canvas colour).
- Kit rev 3 routing (supersedes the stub and bend-point rules above for generated wires): a wire is
  one straight segment from port to port, 1.5 points in the port colour. When a card is in the way it
  gets one bend (a 5-point square), horizontal out of the source then a diagonal into the port, the bend
  72 points before it (or 24-point steps, or the diagonal first). Only when no one-bend way is clear
  does it go round above or below, 24 points clear; a backward wire always goes round. A zone's label
  row and bottom edge are obstacles, so no wire runs along them. Wires are cut to the pane's body.
- Wires into collapsed nodes: chips take driven rows along their bottom edge
  at x 22 + 12k (k = index among driven rows); points take every wire at the
  centre, trimmed 10 points from it.

### 6.4 Levels of detail and zoom

- `point`: a filled circle r 7 at (x + 12, y + 12) in the node's type colour
  (compound: hollow ring with a dot), label to the right. Selection ring r 11;
  display halo r 15 dashed.
- `chip`: the header only.
- `card`: header plus the rows of §5.1.
- `full`: header plus every row with folder headers.
- Selected chips, cards and full nodes have a 2-point theme-accent outline;
  unselected nodes keep the faint neutral outline. The VIEW flag remains
  separate from selection.
- Zoom range 0.25–2.0. Zoom caps the shown level: below 0.34 every unpinned
  node shows as a point, below 0.50 at most as a chip. Pinned nodes ignore
  caps. `o`, double-click and opening a field pin a node; `p` and `⇧P` unpin.
- During a wire drag, hovering a node that has a compatible input and shows
  less than `full` shows it as `full` until the pointer leaves it (bloom), so
  hidden rows are drop targets.

### 6.5 Colour and type

A node's square, point and header accent use the colour of the type it
produces. `Pxui.Theme` gains a port palette; the existing six theme tokens do
not change.

| Token | Light | Dark |
|---|---|---|
| geometry | theme accent `#285f77` | `#72b3cf` |
| float | `#b0680f` | `#e5a54c` |
| int | `#3b7d4e` | `#74c28e` |
| vec3 | `#6b50ae` | `#a98cf5` |
| bool | `#b0435f` | `#f08aa3` |
| compound | `#6b50ae` | `#a98cf5` |
| output node | theme foreground | theme foreground |
| hint label | `#f5cf4f` on foreground | same |

`lib/pxui/test_ui_parity` fixtures that include the graph change on purpose
in M1; every other fixture stays pixel-identical.

### 6.6 Hit testing and PXUI

Every node, row, socket, field, fold button, more row and bend handle is a
`Ui.box` keyed by stable ids (node id, port path, bend index). Wire hits keep
using the graph's spatial index over polyline segments. No second hit-test,
capture or text-entry path (root `AGENTS.md`). The canvas emits typed
requests; `Doc.apply` applies them after `Ui.frame`.

## 7. Interaction

### 7.1 Pointer

| Gesture | Effect |
|---|---|
| Left-drag on empty canvas | box select (replaces the selection; Shift adds) |
| Right-drag, middle-drag, Alt-drag on empty canvas | pan |
| Pinch, two-finger scroll, Command/Ctrl-wheel, mouse wheel | zoom at the pointer |
| Click node | select; Shift toggles |
| Drag node | move the selection (snap 12) |
| Double-click node | card ⇄ chip (pins); on a compound: enter |
| Drag from an output socket | wire; release on a socket connects, on a node body connects to the row under the pointer or the first free compatible input, on empty canvas opens search filtered to kinds with a compatible input |
| Drag from a connected input socket | picks the wire up (release on empty canvas disconnects) |
| Drag from an unconnected input socket | reverse wire; release on empty canvas opens search filtered to kinds with a compatible output |
| Click or drag a numeric field | set its soft-range value from the pointer's position on the field |
| Alt-click a numeric field or double-click its label | text entry; a leading `=` makes an expression |
| Click a wire | select it |
| Alt-click a wire | add a bend point and drag it |
| Ctrl-drag or Command-drag on empty canvas | knife; wires crossing the stroke are removed in one entry |
| Right click (no drag) | context menu, as today |

### 7.2 Keys

All keys are `Editor_core.Command.t` entries in the one keymap (today's rule).
Graph-pane scope unless noted. Row verbs act on the row under the pointer;
node verbs on the selection. The letters in this table are reserved in every
context (§7.11).

| Key | Command id | Action | Milestone |
|---|---|---|---|
| `h` `j` `k` `l`, arrows | `graph.walk.left/down/up/right` | walk (§7.6) | M2 |
| `Tab` | `graph.add` | add by context (§7.3) | M2 |
| `.` | `graph.repeat` | repeat the last add (§7.4) | M2 |
| `f` | `scope.hints` | connect by letter hints (§7.5); the sheet's status bar says `f hints` (`c` stays collapse) | Package B |
| `b` | `graph.bind` | bind by hints; on a selected wire, toggle wireless | M4 |
| `o` | `graph.open` | open the selection one level, pinning | M1 |
| `p` | `graph.point` | selection to points, or back to its previous level | M1 |
| `⇧O` | `graph.open-all` | every node to card | M1 |
| `⇧P` | `graph.point-all` | every node to a point, or every node back to its previous level | M1 |
| `v` | `scope.display` | view the selected geometry node in the viewport instead of the graph's result (a `(display ...)` entry of the layout, one history entry; again returns to the result) | Gap A |
| `m` | `graph.mute` | toggle bypass | M2 |
| `x`, Delete, Backspace | `graph.delete` | delete selection or selected wire | M2 (Delete/Backspace exist) |
| `⇧X` | `graph.dissolve` | delete and reconnect the trunk | M2 |
| `/` | `graph.find` | find a node by name in the current level | M2 |
| `⇧F` | `scope.frame-selection` | pan and zoom the pane to the selection (all with none); in the list `f` reveals the selection | Gap A (moved from `f` by Package B) |
| Home | `graph.frame-all` | frame all (exists) | – |
| `w` | `graph.show-wireless` | show every wireless wire | M4 |
| `=` | `row.expression` | expression on the hovered row | M4 |
| `r` | `row.reset` | remove the hovered row's drive; restore its literal default if undriven | M4 |
| `s` | `row.pin` | keep the hovered row on the card, or hide it | M3 |
| `e` | `row.export` | export the hovered row to the enclosing compound | M5 |
| `⌘G` / `⇧⌘G` | `graph.group` / `graph.ungroup` | group selection / ungroup a compound | M5 |
| `i` / `u` | `scene.enter` / `scene.up` | enter / leave (exists; extended to compounds) | M5 |
| `?` | `guide.toggle` (global) | guide strip and tooltips on or off | M2 |
| `Space ?` | `guide.keys` (leader) | key sheet | M2 |
| `Space l` | `graph.projection` (leader, exists) | graph → list → text → graph | M6 (two-way until then) |
| `F2` | `scope.rename` | rename the selected node, or edit the default of a selected graph input (double-click does the same) | W13 |
| `⇧G` | `scope.frame` | titled frame around the selected nodes (corner resizes, title double-click renames, cross deletes) | W13 |
| `⌥↑` / `⌥↓` | `scope.item-up` / `scope.item-down` | move the hovered list item | W13 |
| drag on empty canvas, `⇧` adds | – | marquee selection of one scope's nodes | W13 |
| `Space o` `v` `h` `x` | `panel.split-right/below`, `panel.close` | split (side by side, stacked) or close the focused panel | W13 |
| `Space o` `g` `l` `t` `i` `u` `m` `w` | `panel.graph/list/lisp/inspector/outline/timeline/viewport` | retype the focused panel | W13 |
| `⌘D` / Ctrl-D | `scope.duplicate` | copy the selected bindings of one scope with fresh names (the copies read each other), select the copies | Gap A |
| `j` / `k` (list) | `list.down` / `list.up` | walk the list like the arrows; a row of a geometry object's list selects its node in the pane | Gap A |
| drag a frame by its title | – | the frame and the nodes whose centres lie inside move together (one `Moved`, one `Frames_set`) | Gap A |
| `⌘C/V/X`, `⌘Z`, `⇧⌘Z` | exist | unchanged | – |

`Space a` (categorised add menu), `Space f` (frame displayed), `Space /`
(palette) and every other leader key keep their current meaning.

### 7.3 Tab

- A wire is selected: insert a node on it (kinds with a compatible input and a
  compatible output), placed at the wire's midpoint.
- Exactly one node is selected and it has an output: append. The new node is
  placed at (x + W + 60, y). If the selection's output feeds a trunk slot, the
  new node is inserted into that edge and every node downstream of it along
  non-wireless edges, with x ≥ the new node's x, moves right by W + 60.
- Otherwise: add at the pointer.

The search lists kinds filtered by that context, ranked: label prefix,
word prefix, substring, subsequence, category match. It searches SOP kinds,
value kinds and definitions. The new node is selected.

### 7.4 Repeat

`.` adds the last added kind (including its preset op, such as Sine) with the
append rule of §7.3 relative to the current single selection, or at the
pointer when there is none.

### 7.5 Letter hints

`c` (and `b`, which excludes geometry ports and creates wireless wires):

1. The source is the single selected node's first output. None: toast.
2. Candidates: every input port of every other node in the level that is type
   compatible and would not create a cycle.
3. A node whose compatible candidates are all visible at its current level
   gets one label per candidate; a node with exactly one candidate gets one
   label for it; any other node gets one label for the node.
4. Order by distance between node origins, nearest first. Labels come from
   `asdfghjklqwertyuiopzxcvbnm`, one letter each; if there are more than 26
   targets, every label has two letters (first × second in that alphabet,
   limit 676).
5. Typing narrows; an exact label picks. Picking a node label shows that node
   as `full` and relabels its candidates. Backspace deletes a letter, Escape
   cancels, a click cancels.

### 7.6 Walk

`h` moves to the source of the selection's first connected input (port order,
primary slot first); `l` to the consumer of its first output, topmost first.
If there is none, or for `j`/`k`, pick the nearest node in that direction:
candidates with Δx < −10 (`h`), Δx > 10 (`l`), Δy > 10 (`j`), Δy < −10 (`k`);
score |Δ along| + 2·|Δ across|. With no selection, select the leftmost node.
Pan so the new selection is visible.

### 7.7 Fold and unfold

- **Fold** (ƒ on a row driven by a wire): collect the source and, recursively,
  every node feeding it. Only `math`, `value` and `time` nodes with no drive
  on `time.speed` other than a literal or expression may take part, and no
  collected node may feed anything outside the collection except this row.
  Otherwise refuse with a toast naming the offending node. The expression is
  built as: `time` → `t` (or `t * speed`), `value` → its `v`, `math` → its op
  over `a` (and `b`). Remove the collected nodes; set the row's drive to
  `Expr`. A pure number becomes the row's literal instead.
- **Unfold** (ƒ on an expression row): build one `math` node per operator,
  numbers become literals on their inputs, all `t` share one `time` chip.
  Place math nodes in columns to the left of the target (W + 24 apart), each
  vertically centred on its inputs; the `time` node goes left of the leftmost
  column. Wire the result into the row.
- Property: unfold then fold gives back an equal expression when it contains
  `t` or an operator (M4 test). A bare number becomes a literal.

### 7.8 Compounds (M5)

- **Group** (`⌘G`): a definition named `compound_<n>` (first free n) gets the
  selected nodes. Inputs: one interface input per distinct outside source
  feeding the selection (named after the first destination port, deduplicated
  with `_2`, `_3`; type and default from that port; geometry first). Outputs:
  one per distinct inside output used outside. Outside edges are rewired to
  the instance; inside edges attach to Inputs/Outputs. The instance takes the
  selection's top-left position; Inputs goes 240 left of the leftmost node and
  Outputs W + 60 right of the rightmost. If the display node was grouped, the
  instance becomes the display node when it has a geometry output.
- **Ungroup** (`⇧⌘G`): the inverse for one instance; inner ids are freshly
  allocated.
- **Enter** (`i`, double-click): the level becomes the definition body at
  that instance; crumbs show `network · sop › Compound 1 · sop compound`.
  **Up** (`u`) returns and selects the instance.
- **Export** (`e` on a hovered row inside a definition): add an interface
  input with the row's type, current literal as default, label and range; wire
  Inputs to the row. The instance gains the row. Refused on a driven row.
- **Unexport** (Inputs/Outputs inspector): remove an interface port across the
  shared definition and its instances. A geometry port must first have its
  body wire and every instance wire disconnected; a displayed geometry output
  is in use. Removing another geometry port preserves the remaining named
  wires. Value-port removal retains the literal at the body destination.
- The display flag lives at the top level of a SOP network; `v` inside a
  definition toasts.

### 7.9 Field editing

Numbers parse with the OCaml float syntax used by the inspector today; Int
fields round; hard bounds normalize through `Param.apply`. `=expr` sets an
expression drive (§3.5); an expression that is a pure number sets the literal.
Enter commits, Escape cancels, blur commits.

### 7.10 Search and find

Search (Tab, `Space a`, release on empty canvas) is today's node menu data
(`Pxui_graph.catalog_of_factories`, category submenus, windowed results)
plus value kinds and definitions. Find (`/`) lists nodes of the current
level by label and qualified kind; picking selects and frames.

### 7.11 Context keys and the World

The grammar's letters are reserved in every context. Context-specific plain
keys use only free letters (`a d g n q t z`, digits, brackets; `y` picks up a carry, §7.12). In M2 the
World's graph-scope keys change: `e` (dome ⇄ light) becomes `t`, `r`
(reseed) becomes `n`, `p` (play day cycle) becomes `d`; `[`, `]` and `1`–`4`
stay. `scene.md` and `api.md` update with that milestone.

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
- **It survives navigation.** `i`, `u` and `Space j` (and the walking keys) work while carrying;
  holding the pointer over a node for 0.6 s follows its reference. Nothing else edits the
  document until the put, and the autosave never writes a preview.
- **Budget.** A put whose apply (edit and check) or whose target cook takes 500 ms or more
  (`?carry_budget` of `Editor3/2.create`, seconds, default 0.5) is not shown: the target is lit and
  the strip says what it would write and why there is no picture (`Would write :material (ref cobalt)
  on shards/m · no preview, applying takes 612 ms · release writes it`); the release still writes it.
  `test_materials` runs it with a zero budget.
  `test_materials` times a preview's apply and restore frames (about 1 ms each on the fixture,
  cooks awaited).

Gesture echo: every other gesture that writes the text also prints what it wrote in the same strip
slot, in the words of the text (`Wrote :visible false on scene/body`, `Wrote :translate [3 0 0] on scene/b`;
`Rays_editor.Echo`), until the next one; an op with no short words (a layout change, a rewrite of
a whole graph) prints nothing and the history label stands. The palette's "Copy workspace as Lisp"
(`Leader.Copy_lisp`, no key) puts the text Command-S writes on the clipboard.

The key `y` is unbound as a plain key; only Command-Y (redo) uses the letter. `Pxui.Ui` holds the
payload on the handle (`Ui.carry`, `Ui.carrying`, `Ui.drop_target`, `Ui.cancel_carry`; see
`pxui.md`), `Scope` reports the node or canvas under it (`Drop_over`, `Dropped`) and never edits,
and `Core` turns a drop into the put.

## 8. Views (M6; the list exists today)

### 8.1 Graph

Everything in §6–§7. Default for SOP networks, as today.

### 8.2 List

Today's `Pxui_shell.Tree` over `Pxui_graph.trunk` rows, extended: value nodes
appear, a node's first incoming edge (by port order) continues its row
chain, other inputs nest one level under their consumer, a node reached twice
repeats as a `↳` link row. Badges: `n driven`, `n set` (overridden, undriven),
`VIEW`, `M`. `j`/`k` move, Enter opens the node in the graph (switch and
frame). Existing WAI-ARIA tree keys stay.

### 8.3 Text

Since W7 the Lisp pane is editable (`Rays_editor.Text_pane`, `Ui.text_area`).
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
scroll position, so it overshoots and settles like every other scrolling view. The qualified-names toggle and the
network printer of M6 are gone (W12); a document that is not a workspace has no
text projection. See `workspace/plan.md` W7 and `flow-migration.md`.

### 8.4 Shared state

The three views share selection, the inspector, history, the display node and
the document. `Space l` cycles graph → list → text and each level remembers its
view (today's per-level projection memory, three-valued).

## 9. Inspector

`Pxui_shell.Inspector` keeps its role and current behavior: empty selection
shows camera/render controls (and, new, a short network summary: context,
node count, display node, the exposure rule in one sentence); a multi-selection
shows the count and `⌘G`; a single node shows every parameter.

Single node (M3):

- Header: editable label; `qualified kind · #id` and flags (muted, displayed).
- Inputs section: geometry slots with their sources, read-only.
- Folders: accordions in schema order (existing), nested with `/` paths
  (existing `[@sop.folder "Transform/Center"]`).
- Row: label, editor, card pin (● shown on the card, ○ hidden, locked ● when
  driven). Editors: number fields (Float/Int), toggle (Bool), choice, text,
  vec3 as three number fields plus an `xyz` split toggle; a driven row shows
  `← source live-value` or `⌁ …`, an expression row shows an editable `=…`
  field, and both show a `reset` button.
- Every edit goes through the same `Doc.apply` requests as the canvas and
  records the same history entries (§4.3).

## 10. Guide mode (M2)

On by default until the user turns it off (`?`, "hide" button); the setting
persists in user preferences.

- **Context strip**, rendered by `Pxui_shell.Status_bar` when the graph pane
  has focus (today the status bar already names the open level's keys; this
  generalizes it). It shows a context name and the keys that apply now.
- **Tooltips** after 380 ms of pointer rest on a socket, row, field, fold
  button, more row, wire, bend handle or node header; text says what the
  thing is and what can be done to it (the prototype's `describe` is the
  reference wording).
- **Which-key** after `Space` (exists).
- **Key sheet** `Space ?`: the whole table of §7.2 grouped as Move, Build,
  Shape, Rows, Change, Guide.
- **HUD**: each key press echoes `key · command label` for 1.5 s in the
  graph pane's corner.

Data model: `Editor_core.Command.t` gains `guide : Guide_context.t list`
(pure data; no predicate, keeping the "no `enabled`" rule). The strip lists,
in table order, the commands whose `guide` contains the current context,
computed by the host:

`Canvas | Node | Value_node | Compound | Multi | Wire | Row | Hints | Leader |
Search | List | Text | Inside_compound`

A value node is a node whose first output is not geometry. Row applies while a
parameter row is hovered.

## 11. Language

The workspace language is in `specification/workspace/` (`iteration.md` §2 and §7)
and is what the editor reads, checks, prints and lowers. The rest of §11 is the
M1–M7 single-graph language; its reader, checker, printer and builder were deleted
in W12 and it is kept for the value semantics (types, coercions, expressions) that
the workspace language inherits.

### 11.1 Lexical syntax

- Whitespace separates tokens. `;` starts a comment to the end of the line.
- Delimiters: `(` `)` `[` `]`.
- Number: `-?(\d+\.?\d*|\.\d+)`; an integer literal has no `.`.
- String: `"…"` with `\"`, `\\`, `\n` escapes.
- Keyword: `:` followed by a name.
- Metadata: `^:` followed by a name, applying to the next form.
- Symbol: anything else up to a delimiter, whitespace, `;` or `"`.
- Name: `[a-z][a-z0-9_]*`. Qualified symbol: `<namespace>/<name>`. Output
  reference: `<binding>.<output>`.
- Reserved symbols: `t`, `pi`, `nil`, `true`, `false`, `let*`, `values`,
  `graph`, `defgraph`, and the math op symbols.

### 11.2 Literals

Float and Int numbers; `true`/`false` for Bool; strings for Text, Choice (the
choice's public label, as `Param` prints it) and Encoded (its encoding);
vectors `[x y z]` whose components are numbers, expressions or scalar
references; `nil` for an unconnected geometry slot.

### 11.3 Grammar

```text
file      = { graph_form | defgraph_form } ;
graph     = "(" "graph" name [ ":context" context ] [ ":catalog" integer ] body ")" ;
defgraph  = "(" "defgraph" name [ ":context" context ]
            "[" { "(" name ":" type [ literal ] ")" } "]" body ")" ;
type      = "geometry" | "float" | "int" | "bool" | "vec3" ;
body      = "(" "let*" "[" { name expr } "]" result ")" | result ;
result    = expr | "(" "values" result_entry { result_entry } ")" ;
result_entry = expr | ":" name expr ;                       (* values: defgraph only *)
expr      = literal | "t" | "pi" | name | name "." name | vector
          | [ "^:bypass" ] "(" head { arg } ")" | thread ;
thread    = "(" "->" expr { "(" head { arg } ")" } ")" ;          (* sugar, read as nested calls *)
vector    = "[" expr expr expr "]" ;
head      = op | name | namespace "/" name ;
op        = "+" | "-" | "*" | "/" | "pow" | "min" | "max"
          | "sin" | "cos" | "abs" | "floor" | "sqrt" ;
arg       = expr | ":" name expr ;       (* positional geometry slots first *)
```

`(-> x (f a) (g b))` is read as `(g (f x a) b)`: each step is a call that takes the value before it
as its first operand, so the text reads in wire order, left to right like the canvas. It is sugar of
the reader (`Syntax.parse`): nothing after the reader sees a `->`. The outermost call keeps the
form's id and the span of the whole `(-> ...)`, each step keeps the span of its own clause, and the
value `x` keeps its own. A step that is not a call, or a `->` with no value, is `E_THREAD`.
The printer threads a chain of three or more calls of node kinds (a head with a `/`, except the
`ui/` layout forms, which nest) whose first
operand is the next call down, and leaves shorter chains, chains with a note or a `^:` flag on a
link, and every `let*`-named value nested, so print and re-read keep the same forms
(`test/test_threading.ml` prints and re-reads every checked-in workspace).

Every step of a `->`, and every call of a node kind written inside another call, is a node of the
graph (`Flow_sop.Projection`): a card before the card that holds it, wired to the row it is written
in. It has no binding, so its path leaf is the holder's leaf, `#`, and the input (`result#0`,
`result#0#:cutters`; `Flow_edit.nested_leaf`). Its rows edit in place (`Set_arg`, `Connect`,
`Disconnect`, `Toggle_bypass` take the path); naming it (`Rename`, the name field) binds it under that
name; deleting it hands its place to its first input; dragging its output to a second input, viewing
it, or dropping a wire where it is written binds it first, so a wire never deletes a node. The caret
in its text selects it and selecting it marks its text. Expressions, `ref`s, loops, and calls of
functions and macros written in an input stay chips (`Unfold` binds them); a macro's arguments are
pieces of its template and stay chips too. Rule: no syntax is text-only.

A file has exactly one `graph` and any number of `defgraph`s; a definition is
defined before its first use (single pass, so definitions are acyclic by
construction). `let*` is sequential.

### 11.4 Namespaces and resolution

| Namespace | Holds |
|---|---|
| `sop/` | registered SOP factories by stable key |
| `value/` | value kinds and math ops; usable in every context |
| `user/` | this file's `defgraph`s and file-local custom nodes (§12.4) |
| `<library>/` | a compound library (reserved; name = library name) |
| `scene/`, `world/`, `shader/` | reserved for later contexts |

Parameter keywords need no namespace: `:amp` is resolved against the schema
of the node it is passed to (field name, or vec3 group name). Slot keywords
use slot names. A kind's rename keeps the old key as an alias in the catalog
manifest; the printer always writes the current key.

Call heads resolve in this order: math op symbols; qualified symbols as
written; otherwise `user/`, then the graph's context catalog, then `value/`.
More than one match is `E_AMBIGUOUS`. A bare symbol in argument position is a
binding (or `t`, `pi`, `nil`, `true`, `false`); a kind name used as a value is
`E_KIND_AS_VALUE`. Kinds and bindings are separate namespaces, so
`(let* [grid (grid)] …)` is valid.

### 11.5 Contexts

`:context` defaults to `sop`. A `sop` graph may call `sop/`, `value/` and
`user/` kinds whose context is `sop` or `value`. A `value` definition may call
only `value/` and `value` definitions. `scene`, `world` and `shader` are
`E_CONTEXT_PLANNED` in this revision.

### 11.6 Typing and construction

- Positional arguments fill geometry slots in order; extra positionals are
  `E_EXTRA_POSITIONAL`; a positional after a keyword is `E_POSITIONAL_AFTER_KEYWORD`.
- A keyword argument sets a parameter: a number or literal sets the literal
  (Int fields reject non-integral numbers, `E_INT_LITERAL`; outside hard
  bounds `E_HARD_RANGE`; outside the soft range `W_SOFT_RANGE`); an
  expression over numbers and `t` becomes an `Expr` drive; a reference to a
  scalar or vec3 output becomes a `Wire` drive; a vector sets a vec3 literal
  or per-component drives (splitting it).
- A math call whose arguments are all numbers or expressions is an expression.
  A math call with any reference argument creates a `math` value node.
- A `let*` binding always names a node: if its form is a number or
  expression, a `value` node is created with that literal or expression.
  The node's label is the binding name.
- `^:bypass` mutes the node. Other metadata is `W_UNKNOWN_META`.
- A `graph` result is a geometry reference (the display node), or `nil` when
  the network has no display node. Other result types are `E_RESULT_TYPE`.
- A `defgraph` result is one expression or `(values …)`; each unnamed value
  becomes an interface output (`geo`, `geo2`… for geometry, `out`, `out2`…
  otherwise). `:name expr` entries give explicit interface output names, so
  renaming an output remains round-trippable. Duplicate or invalid output
  names are `E_INTERFACE_ENTRY`. The canonical printer names every output in
  a multi-output or renamed-output definition.
- Errors do not cascade: a binding whose form failed is poisoned, and uses of
  it report nothing further.

### 11.7 Canonical printing

*(Removed in W12: the printer of the M6 text view. `Flow.Lisp.print` prints workspaces.)*
`Flow_sop.Print.network` took the level's context, display selection,
definitions and live `Flow.Check.catalog`. It returns canonical text and a
node-id-to-binding-line map deterministically and independently of layout.
The read-only text view requests six significant digits for legibility;
the default printer retains 17-digit float spelling for exact round trips.
Parameter fields likewise show six significant digits while retaining full
precision for editing and storage:

- Header `(graph <name> :context sop` where the sketch or network name follows
  the binding-name normalization rule below; definitions print first as
  `defgraph` blocks, innermost first, each
  once.
- Order: visit nodes by ascending id; before a node, visit the sources of its
  inputs in port order (slots, then fields in declaration order, vec3
  components x < y < z); print each node once, after its sources.
- Binding names: the label lowercased, runs of other characters replaced by
  `_`, leading digits prefixed `n`, never a reserved symbol; duplicates get
  `_2`, `_3` in print order.
- Arguments: the primary slot positionally when connected (`nil` only when a
  later positional slot is connected); other connected slots as `:slot`;
  parameters in declaration order, only when driven or overridden; vec3 as
  `[x y z]` with per-component drives inline; expressions as s-expressions;
  math nodes with a reference operand as `(op a b)`; literal-only Math nodes as
  `value/math` calls so reading does not fold the node into an expression;
  `^:bypass` before muted nodes.
- Layout: `let*` with bindings aligned in one column (two-space indent, `(let* [`
  then 9-space continuation), result on its own line, closing parens on the
  last line.
- `;;` comment lines after the graph report layout counts in the text view
  only; they are not part of the canonical form.
- Short names in the text view by default; qualified names in presets'
  debug dumps, `[%flow]` diagnostics and the "qualified names" toggle.

### 11.8 Round-trip laws (M6 text checks; M7 rebuild checks)

1. `read (print d)` equals `d` up to layout and id renumbering.
2. `print (read s) = s` for every canonical `s`.
3. Printing does not depend on layout: moving, bending, re-levelling or
   pinning never changes the text.

### 11.9 Diagnostics

`Flow.Diagnostic.t = { code; severity; position : { line; col } option;
message; span }`. Source-language diagnostics have a 1-based position and a
half-open byte span. Runtime diagnostics without source text leave position
and span absent.
Messages are sentences that name the fix; the prototype's wording is the
reference.

| Code | When | Message shape |
|---|---|---|
| `E_UNCLOSED` | a `(`/`[` never closes | This "(" is never closed |
| `E_UNEXPECTED` | stray `)`/`]` or mismatched close | Expected "]" to close the "[" on line 3, found ")" |
| `E_DEPTH` | more than 256 nested forms | S-expression nesting exceeds 256 forms |
| `E_TOPLEVEL` | other top-level form | Top-level forms are graph and defgraph |
| `E_NO_GRAPH` / `E_ONE_GRAPH` | zero / several graphs | No (graph …) form found / One graph per file |
| `E_CONTEXT_UNKNOWN` / `E_CONTEXT_PLANNED` | bad `:context` | Unknown context x. Known contexts: sop, value |
| `E_NAMESPACE` | unknown prefix | Unknown namespace x. This file knows sop, value and user |
| `E_UNKNOWN_KIND` | no such kind | Unknown node x. Did you mean y? |
| `E_AMBIGUOUS` | several matches | swirl is ambiguous: user/swirl or sop/swirl. Write the namespace to choose |
| `E_WRONG_CONTEXT` | kind not allowed here | sop/grid is a SOP node and cannot appear in a value graph |
| `E_UNBOUND` | unknown binding | x is not bound. Did you mean y? |
| `E_KIND_AS_VALUE` | kind used as a value | grid is a node kind; call it as (grid …) or bind it in let* |
| `E_BINDING_T` / `E_BINDING_NAME` / `E_DUPLICATE_BINDING` | bad binding | t is the context time; pick another binding name |
| `E_DUPLICATE_DEF` | definition twice | defgraph ripple is defined twice |
| `E_UNKNOWN_PARAM` | no such keyword | noise_displace has no parameter :ampl. Did you mean :amp (amplitude)? |
| `E_DUPLICATE_PARAM` | keyword twice | :amp is given twice |
| `E_EXTRA_POSITIONAL` / `E_POSITIONAL_AFTER_KEYWORD` | argument order | grid takes 0 geometry inputs; this one is extra |
| `E_MISSING_VALUE` | keyword without value | :amp has no value |
| `E_TYPE` | wrong type | Input in0 of ripple takes geometry, but this is Float |
| `E_INT_LITERAL` / `E_HARD_RANGE` | bad literal | :rows is an integer (2–40), not 22.5 |
| `W_SOFT_RANGE` | outside the slider range | :amp 3 is outside the slider range 0–2. Allowed, but check it |
| `E_VECTOR_ARITY` | not 3 components | A vector has 3 components [x y z]; this one has 2 |
| `E_ARITY` | math op arity | sin takes 1 argument, got 2 |
| `E_OUTPUT_UNKNOWN` | bad `.port` | Separate XYZ has no output w. Outputs: x, y, z |
| `E_VALUES_PLACE` / `E_RESULT_TYPE` | bad result | A sop graph returns geometry, but this returns Float |
| `E_INTERFACE_ENTRY` / `E_UNKNOWN_TYPE` / `W_NO_DEFAULT` | bad defgraph interface | Each interface entry is (name :type default) |
| `E_RECURSIVE` | definition reaches itself (documents only) | Compound ripple contains itself |
| `W_UNKNOWN_META` | metadata other than bypass | Unknown metadata ^:x; only ^:bypass is defined |
| `E_CATALOG` | `:catalog` newer than the build's manifest | This file needs catalog 202611; the build has 202609 |

Suggestions use edit distance ≤ 2 over the candidates in scope, and for
parameters also match labels written with `_` for spaces.

### 11.10 Ambiguity rules

| # | Case | Rule |
|---|---|---|
| 01 | same short name in two namespaces | `E_AMBIGUOUS` at every use; qualify |
| 02 | binding named like a kind | allowed (separate namespaces) |
| 03 | binding named `t` | `E_BINDING_T` |
| 04 | several outputs | `binding.output`; `.` and `/` are illegal in names |
| 05 | slot and field with the same name | PPX error when the node is declared (M3) |
| 06 | `3` vs `3.0` | integer literals fit Int and Float fields; `2.5` into Int is `E_INT_LITERAL` |
| 07 | soft vs hard range | hard is an error, soft a warning |
| 08 | a default changes between catalog versions | the manifest has an integer catalog version; files may pin `:catalog N`; upgrading a document whose node's default changed writes the old default as an explicit literal |
| 09 | rename | ids are document data, never derived from names |
| 10 | wire vs wireless, bends, levels, pins, display | layout; never printed |
| 11 | bypass | metadata `^:bypass`, never a parameter |
| 12 | partly driven vector | `[0 wave 0]`; splitting is implied |

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
timeline (`Space t`) removes the leaf's strip. The strip's frame field is typed (a click opens it,
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
what the user did in the UI alone. `Space v` and the inspector toggle look-through for the focused
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

## 12. `[%flow]` (M7, removed in W12)

The `[%flow]` PPX, `Flow_sop.Build.program`, `Flow_sop.Program.t`, `Flow.Check.check`
and the editors' `?program` argument were deleted in W12: no sketch needed them once
single-graph sketches became `sketches/<name>/sketch.rays` (`workspace/plan.md` W11-W12),
and a workspace is the one document. An OCaml sketch that mixes host code passes a
workspace text through `Rays_editor.Workspace_doc.of_text`, or writes the `.rays`
beside it (`Rays_editor.Workspace.load`).

### 12.2 Catalog manifest (still current)

`tools/flow_manifest.exe` (OCaml, links `sop_catalog` and `flow_sop`) writes
`lib/sop_catalog/flow_manifest.sexp`: catalog version, digest, and for every
factory its key, aliases, label, category path, slots (name, required),
fields (name, label, folder, kind, default, soft and hard range, primary,
vec3 group), outputs; plus the value kinds. The file is checked in; a runtest
rule regenerates it and diffs, and an intended change is accepted with
`dune promote` (the same flow as `tools/api_manifest`). `tools/lisp` and the
workspace checker read it (`Flow.Check.catalog_of_manifest`).

## 13. Evaluation

### 13.1 The value lane

Cooking keeps its path (compile `Edit_graph`, `Async_cook`, session cache).
Before each cook submission, `Flow_sop.Value_lane.resolve` runs on the initial
domain:

1. Evaluate value nodes reachable from drives, memoized per frame, in
   dependency order. `time` reads the cook context time (`Frame.time`, or
   `Sketch.Fixed dt` time).
2. For each driven port, compute the value (expression or wire), coerce it
   (§3.2) and normalize hard bounds with `Param.apply`.
3. Compare with the value applied for that port in the previous resolution
   (kept in the environment, not the document). Apply only changed ports with
   `Edit_graph.apply_parameters` to a copy of the document graph. The document
   literal is never overwritten by a drive.
4. Cook the resulting graph. An unchanged value leaves the node's cook key
   unchanged, so nothing re-cooks.

A lowered workspace (specification/workspace/plan.md W2b) adds one more drive kind,
`Drive.Live`: an argument that depends on `t`, held as an `Eval` value with its
static captures folded in. `resolve` evaluates it beside expression drives
(a scalar, a vec3, a colour text, or a list of vec3 for a text-encoded list
parameter such as `flow.curve`'s points) and applies it only when the value
changed. Its nodes are marked volatile in the session (one replaced slot each,
outside the LRU), so playing never evicts the static entries.

A network whose drives read `t` is time-dependent: it resolves every frame
while the timeline plays, and its SOP nodes' cook keys change each frame.
`Async_cook`'s latest-request rule bounds the work to one active and one
pending cook. Networks without drives do no lane work.

### 13.2 Determinism

The lane is sequential IEEE double arithmetic with fixed op semantics (§3.3),
so results are identical for one and many domains and across runs with
`Sketch.Fixed dt`. The M3 regression runs the same drives at 1 and N domains
and compares cooked geometry bytes.

### 13.3 Compounds

`Flow_sop.Compile.flatten` inlines instances recursively into one
`Edit_graph` plus one resolved drive set before the value lane. Inner nodes
get compiled ids from the document's `compiled_ids : int Instance_path.Map.t`,
allocated once per (instance path, inner id) and saved in presets, so session
cache entries survive unrelated edits. Two instances of one definition cook
separately (cache keys include node ids; sharing is out of scope).
The editor allocates missing compiled ids into the document before recording
an edit in history. Cooking calls `flatten ~allocate:false` and reports a
missing-id diagnostic instead of creating an unsaved id. An unchanged source
network, definitions, display and id map reuse the same flattened network.

### 13.4 Workspace lowering

`Flow_sop.Lower.workspace` (specification/workspace/plan.md W2) builds one
network per evaluated sop graph from the `Flow.Eval` geometry plan. Its
compiled ids use the same `Instance_path.Map` with the key
`instance :: site_index :: (-(k+1))*`; a negative segment is an iteration
index, so the encoding needs no new type. A collected geometry list is one
`flow.merge_n` node that tags each primitive with its input index in the
`__flow_src` primitive attribute; `Lower` records where each input came from.
Parameters that depend on `t` cook with their `t = 0` value and are listed for
W2b, so a frame never re-lowers.

## 14. Libraries and the dependency gate

| Library | Status | Depends on | Owns |
|---|---|---|---|
| `param` | changed (M3) | nothing | adds `primary : bool` and `vec3 : (string * int) option` to fields and field views |
| `flow` | new (M3) | `param` | `Symbol`, `Context`, `Port_type`, `Expr`, value kinds, `Graph`, `Sexp` (reader with positions, printer primitives), `Check`, `Diagnostic` |
| `flow_sop` | new (M3) | `flow`, `param`, `procedural` | `Network`, `Drive`, `Exposure`, `Value_lane`, `Compile`, manifest writer, and since W2-W9 `Lower`, `Flow_edit`, `Projection`, `Probe` (`Print`, `Build`, `Program` were deleted in W12) |
| `editor_document` | changed | + `flow_sop` | overlay and layout record in `Document.network`; `Workspace_doc`, `Layout_by_path`, s-expression presets |
| `pxui_graph` | changed | + `flow`, `flow_sop` | the canvas of §6–§7 |
| `pxui_shell` | changed | + `flow` (types only) | inspector rows (§9), guide strip in `Status_bar` |
| `rays_editor` | changed | + `flow`, `flow_sop` | keys, guide contexts, views, value lane scheduling |
| `ppx_rays` | changed | `ppxlib`, + `flow` | `[@sop.primary]`, `[@sop.vec3]`, `[@@sop.node_slots]` (`[%flow]` was deleted in W12) |
| `sop_catalog` | changed (M3) | unchanged | annotations, private operation groups and one PPX registry facade |

Gate changes in `test/dependency_gate.ml` (M3): add `flow` and `flow_sop` to
`upper`; rules `"flow", "rays" :: "rays_math" :: "rdk" :: "procedural" ::
"editor_core" :: "pxui" :: "pxui_shell" :: "pxui_graph" :: "sop_catalog" ::
"editor_document" :: "rays_editor" :: gpu` and `"flow_sop", ["rays";
"pxui"; "pxui_shell"; "pxui_graph"; "sop_catalog"; "sketch_support";
"editor_document"; "rays_editor"] @ gpu`; `ppx_rays` never reaches
anything but `ppxlib`, `flow` and `param`. `specification/backend.md` records
the new edges in the same change.

## 15. Performance

Rules from the root `AGENTS.md` apply. Targets to measure, not claims:

- Canvas frame cost scales with visible nodes and wires; points are one quad
  and one label, wires are segment lists without allocation per unchanged frame.
- The value lane does no work for networks without drives and no allocation
  for time-independent drives after their first resolution.
- Text printing and list rows are computed only when their view is open and
  the document or selection changed.

Benchmarks, reported before and after in each milestone's hand-off:
`tools/bench_rays_editor.exe 200 1000 2000` (existing), `test/test_pxui_graph`'s
2,001-node smoke (existing), plus new cases: all nodes as points, 200 driven
rows with a time source, printing a 2,000-node network.

## 16. Tests

Window-free logic tests in `runtest` for: exposure rule table (every row of
§5.1), vec3 grouping and PPX errors, coercions, value lane (exactness,
change-only application, cook-key identity when unchanged, 1 vs N domains),
walk and hint labelling (deterministic labels for fixed layouts), Tab
placement and ripple, fold/unfold identity, group/ungroup/export invariants,
preset round trip, printer laws of §11.8 over every
catalog factory with non-default literals and drives, every diagnostic code,
key routing for every new command (`test_rays_editor_logic`), the carry (the payload's life in `lib/pxui/test_ui.ml`, a drop over a node in `test_pxui_graph`, a put as one entry by pointer and by keys, a cancel that leaves the document physically equal and the preview timings in `test_materials`), and gate
rules. Visual checks go in `@runtest-native` once per milestone
(`test_ui_parity` fixtures updated intentionally in M1).

## 17. Deferred

Done since this revision (workspace plan): the editable text view (W7), the scene,
World and settings as contexts (W10), macros (W9), loops, records and functions
(W1, W8). Still deferred: fields and the diamond socket as data; zoom-to-enter;
depth rings; compound libraries as packages; content-addressed cache sharing
between instances; `defgraph` as OCaml functions. Deferred by the workspace plan
and listed in `workspace/plan.md` §4 and `workspace/progress.md` (gaps): procedural macros,
a per-node cache ring for scrubbing. (Marquee selection and panel keys were built in W13.)

## 18. Decisions

| Decision | Choice |
|---|---|
| Wire shape | straight polylines with authored bends; no curves |
| Automatic layout | output-rooted input branches receive separate vertical bands in port order; tighten short branches toward consumers, anchor shared fan-outs, reserve authored detail heights, clear stale bends |
| Architecture | `flow` overlay beside the geometry `Edit_graph`; M2 adds bypass metadata to its existing entries |
| Value kinds | built into `flow`, context-free; not SOP catalog entries |
| Edge identity | destination port; no edge ids |
| Shared saved layout | UI-free `Editor_core.Network_layout`; document and canvas share it without importing presentation into the document |
| Vec3 | metadata grouping of three float fields; no new `Param.value` case |
| Compound Vec3 default | `Port.literal` stores the three components on one interface port; scalar defaults remain `Port.Scalar` |
| Named `defgraph` results | `(values :name expr …)` preserves M5 output renames; unnamed results still receive `geo`/`out` names |
| No display node | a graph result of `nil` preserves `display = None` |
| Fixed panel sizes (2026-10-05) | `:first_size` / `:second_size` on `ui/split`: one concept, on the split that the gutter drag rewrites; `ui/split-at` stays the ratio form (§11.11) |
| Start keywords (2026-10-05) | keywords on the panel forms (`:focus`, `:look_through`, `:view`, `:tab`), followed when the document opens and whenever their value in the text changes; saved UI state stays in `(layout ...)` |
| Panel instances (2026-10-05) | every leaf is an instance with its own view state; the level and its selection belong to a graph panel; a binding used twice makes two instances keyed by place |
| Following a graph panel (2026-10-05) | `:of binding` on `ui/inspector`, `ui/list`, `ui/lisp`: one keyword, a panel-typed wire in the graph; without it the panel follows the focus |
| Layout forms in the printer (2026-10-05) | `ui/` calls are never threaded with `->` |
| Literal-only Math node | explicit `value/math` call preserves the node; operator syntax with no references lowers to an expression |
| Primary rows without annotations | the first folder's fields |
| Compound reuse | shared definitions with "make unique" |
| Names in the language | stable keys and field names verbatim (`noise_displace`, `size_x`), `[a-z][a-z0-9_]*` |
| Names in the text view | short by default, qualified toggle; qualified in diagnostics |
| World keys | `e`→`t`, `r`→`n`, `p`→`d`; grammar letters reserved everywhere |
| `f` | frames the selection, or the display node when nothing is selected |
| Editor text view | read-only in this revision; editable since W7 |
| Scene and World text | the third projection shows a reserved-context message until those contexts receive Flow syntax after M7 |
| Round-trip test staging | M6 checks printed text and layout independence; M7's builder enables document reconstruction and canonical reprinting laws |
| Catalog pinning | integer catalog version in the manifest, optional `:catalog N` in files |
| Cache sharing between instances | none |
| Guide mode | on by default, persisted off |
| Wheel and trackpad scroll | zoom at the pointer after SDL normalizes natural direction; SDL3 wheel events do not identify a trackpad separately, so right/Alt-drag pans |

2026-09-28: a bare number has no source node after unfolding, so the
fold/unfold identity law applies to expressions containing time or an operator.
Bare numbers become normalized target literals as specified above.

2026-09-28: compound interface defaults use `Port.literal` rather than one
`Param.value`, because a Vec3 default can have three different components.
Presets encode that case as a `vec3` triple; scalar defaults keep their
existing value encoding.

2026-09-28: M5 permits renaming compound outputs. Unnamed `defgraph` results
could only reconstruct `geo`/`out` names, so the `values` form now accepts
`:name expr` entries. Canonical text writes explicit names whenever a
definition has multiple outputs or a renamed single output.

2026-09-28: the M6 printer and checker can verify that printed networks are
well typed and unaffected by layout. The `read(print d)` and `print(read s)`
laws require reconstructing a network from the checked program, which belongs
to M7's `Flow_sop.Build.program`; those two laws run in M7 rather than adding
a throwaway builder in M6.

2026-09-28: saved editor networks can have no display node, and `Program.t`
already models display as optional. A graph result of `nil` now represents
that state. Literal-only Math nodes print as explicit `value/math` calls,
because operator syntax with no references is intentionally an expression.

2026-09-28: unexporting a connected geometry port would discard topology,
unlike a value input that can fall back to a literal. Geometry unexport is
therefore allowed only after body and instance wires are disconnected; the
displayed output also counts as a use.

2026-09-28: `Flow.Diagnostic` also serves runtime and expression errors, so
its source position is optional. Language-reader and checker diagnostics always
populate it; byte spans remain for PPX source mapping.

2026-09-27: the requested full migration has no backward compatibility;
version 3 replaces the v1/v2 readers and preserves saved node ids.
M1 preserves explicit row exposure metadata as part of that layout; vector
splits and wireless flags stay empty until their milestones.

2026-09-30 (W3): the v3 JSON preset reader and writer are deleted; presets are
s-expression workspace files (§4.4) and old presets are not supported.

2026-09-27: bypass was specified without a storage or execution path. It is
an immutable `Edit_graph` entry flag, shared by compile, copy, undo and
presets, rather than a second host map. Only the primary slot is compiled
while bypassed; disconnected secondary slots cannot prevent the pass-through.

2026-09-27: an AST inventory found 89 named float triples; the previous
92/278 count was stale. Ray has both a `direction` choice and
`direction_x/y/z`; its group is `direction_vector`, preserving the existing
field names and the rule that a group cannot shadow another field.

2026-09-27: coercions use the actual OCaml int and IEEE double ranges.
Int-to-Float cannot be exact beyond 53 bits. Rounded Float-to-Int saturates
the machine range before field hard bounds, preventing overflow wraparound;
non-finite values cannot drive an integer field.

2026-09-27: expression unary minus follows the prototype's tight binding.
Infix printing preserves right-nested sums/products as well as subtraction,
division and powers, so a print/parse round trip cannot reassociate IEEE
operations. The prototype printer now follows that same rule.

2026-09-27: automatic expression parsing prefers a spaced operator head as
an s-expression; trying infix first changes the meaning of `(- -2 -0)`.
Unary Math keeps its inactive `b` input, including any drive; driven and
pinned rows remain visible and full shows all schema fields. Remap's `v`
defaults to zero and clamping applies to its interpolation fraction, so
reversed ranges behave consistently.

2026-09-28: `Edit_graph` geometry connections identify a source by node id,
while compound instances may expose multiple geometry outputs. The Flow
overlay therefore stores a named source output by destination port for those
connections; an absent entry means the ordinary `geo` output. This keeps
existing SOP geometry topology and `Edit_graph` APIs intact while preserving
the selected output through copying and presets.

2026-09-30 (W12): the M1-M7 text stack is deleted: `[%flow]`, `Flow.Check.check`,
`Flow_sop.Build`/`Print`/`Program`, `?program`. The flat single-graph pane stays for
documents built from an OCaml `Procedural.Graph` (`?graph`), which have no text.

2026-09-30 (Gap A): the flat pane and `?graph` are deleted too, together with value nodes, compounds (group,
ungroup, make unique), `Flow.Expr`/`Drive.Expr` and `Flow.Sexp`. Sections above describing them (value nodes,
compound definitions, expression drives, the flat canvas keys, `Network_layout`) are historical design; the
implemented editor is the workspace text plus `Pxui_graph.Scope`.
