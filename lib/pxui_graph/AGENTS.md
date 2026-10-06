# lib/pxui_graph rules

`pxui_graph` exports two modules, `Scope` (the graph pane over one `Flow_sop.Projection.scope` of workspace text) and
`Node_menu` (the categorised add menu). The flat pane that once presented a `Flow_sop.Network` was deleted in Gap A;
the two sections below that describe its layout, levels, value tiles, wireless and compounds are historical. The pane
shares the PXUI handle and returns typed `change` requests. It never mutates the
document, cooks, or interprets operation names (hosts pass predicates such as
`~flaggable`). Keys are exported as `Editor_core.Command` entries through
`bindings`; the host scopes and dispatches them. Every interactive element is
a `Ui.box` keyed by stable ids; the graph's spatial index culls tiles and
resolves wire and port hits; there is no second hit-test, capture or
text-entry path.

## Current contract

Card geometry is the kit sheet's box model (`graph.html`, `kit.css` `.node .nh .nr .port`), measured
against its render: header 24 overlapping the 1-point border, rows from `Projection.body_top` (23),
4 points of padding (`card_pad` 5 with the border), a 24-point footer row only when the host has probe
records (`Projection.layout ~foot`), text placed with `Ui.text_top`. Strokes are inset by half a point
(`paint_card`); ports are 8-point circles centred on the edge. Do not paint by eye: re-measure.

Painting follows kit rev 3 (`specification/pxui.md`): a card is a sheet with one hairline, a type
square, the name and the kind in ink-2; ports are rings (filled once wired), wires 1.5 points in
the port colour (ink when selected); the selection is accent corner brackets, a bypassed card is
hatched, the displayed node wears an accent flag, a drop target is dashed; the canvas is the ground
with a dot every 24 points and a register cross every 480 by 192.


Card rule (kit rev 3): a Card is the header plus its wired or written rows, with no `+ N more` row; the footer
(value, spark, `1 204 pts · 0.003 s` cook time) is drawn on Full only. Geometry is computed once per node at the
level it was given (`shown`; the zoom never reduces a card to a chip or a point): a point's box is as wide as its name at the zoom's font (re-measured when the font
changes), a chip is the header, and ports, wire ends, obstacles and hit boxes all read that box. Columns sit on a
288-point pitch (196 + 92 gap on the 24-point lattice). A wire is one straight segment, or one bend (5-point square,
72 points before the port) when a card is in the way, round above or below only as a last resort; zone label rows
and bottom edges are obstacles. The obstacle grid is int-keyed and `crosses` rejects by box first: routing is on the
`with_scope` hot path (`dune exec test/test_main.exe -- bench_scope_big`).

Deterministic left-to-right layout by longest input path with short branches
tightened toward consumers and shared fan-outs anchored. Upstream branches
are separated in port order; layout reserves authored detail heights at every
zoom and re-layout clears stale bends. 196-point cards,
24-point headers and rows, 12-point snapping, geometry sockets in headers
and rows, and polyline wires with editable bends. Levels point/chip/card/full
are explicit (`o`, `p`), never zoom-driven. Cards set numeric literals from pointer position through `Ui.value_field`;
Option-click or label double-click opens text entry. Value tiles and typed row
sockets use the same hit tree and spatial wire index. A VIEW flag marks the
display node; marquee selects, Alt/right/middle-drag pans, wheel,
two-finger scroll and trackpad pinch (`signal.pinch`) zoom at the pointer, Alt-click edits bends and
Command/Ctrl-drag cuts crossed wires.
Hovering a connected socket highlights its incident wires and both ends; hovering
a wire highlights that connection. Segment rectangles join the shared PXUI hit
tree behind the cards, so socket and control ownership takes precedence.
The categorised node menu uses `open_menu_at` and `catalog_of_factories`. Details: `specification/pxui.md` (Hosts) and
`specification/procedural.md` (Editable graph document).

## Rays Flow rework

This library is where most of `specification/flow.md` lands (§6 canvas, §7
interaction). M1 implements the canvas contract above. M2 implements walk, contextual
Tab/append/ripple, qualified repeat, letter hints, mute, dissolve, find and
selection framing as Command entries with guide contexts. Rows and fields
own hover through the shared PXUI hit tree; delayed tooltips never capture
input. M3 adds value nodes and row sockets through `flow_sop`; the canvas
shares one typed Tab search for value and SOP kinds.
M4 adds wireless bind visibility, expression fields and ƒ row actions as
typed requests; the host reduces them after the shared PXUI frame.
M5 presents compound output names from `Flow_sop.Network.outputs`; geometry
connect requests carry the selected source port, including its output name.
Compound bodies hide the display flag; `v` reports that display belongs to
the enclosing SOP network. Double-click entry follows current instance data.
Rules that hold throughout:

- Wires are straight segments, port to port, 1.5 points in the source port's colour, drawn with `Ui.line`; a wire
  that would pass under a card is a two-or-more segment polyline bent clear of it (a 5-point square marks each
  bend, `route` in `scope_pane.ml`). `:wires "rect"` keeps the old orthogonal routing. No curves.
- New interactions return new `change` cases; `Rays_editor.Doc.apply` is
  the only reducer, and each gesture is one history entry (`flow.md` §4.3).
- Layout (positions, levels, pins, splits, bends, wireless) is document data
  the host stores; selection, hover, pan and zoom stay in this library's
  immutable view value.
- The exposure rule comes from `Flow_sop.Exposure.shown`; do not
  reimplement it here.
- Keep unchanged document replacement allocation-free on the identity fast path and keep
  `test/test_pxui_graph`'s 2,001-node smoke within its recorded baseline.

## Workspace pane (`Scope`, plan W4)

`Pxui_graph.Scope` (`scope_pane.ml`) presents one `Flow_sop.Projection.scope`
for workspace documents: zones are painted in the canvas pass under the
tiles (`Pxui.Theme.zone_*`), each item is a `Ui.box` tile, and the iteration
selector, socket, field and toggle boxes are its children. It has its own
`change` type; the host maps `Syntax_edit` to `Doc.syntax_edit`, and layout
(`Moved`, `Zone_collapsed`) and probes are the host's, passed back through
`with_scope ~at ~collapsed ~probe ~count ~frames`. Rules: build only visible
items (a zone body is drawn once, whatever its iteration count); a row under
the pointer comes from the pointer and the tile's rectangle, never a second
hit tree; DepartureMono lacks ⟲ ◆ ◷ ↥ ▸ ▾, use the substitutes in
`scope_pane.ml`. It is the only graph pane.

Footers (W5): `with_records` takes a `Flow_sop.Probe.t`; footers are built
only for visible cards at zoom >= 0.4, a sparkline draws at most 16 segments
whatever the count (the paint test bounds it), and the `↑ same each time`
button is a `Ui.box` emitting `Syntax_edit (Hoist ...)`. `with_scope` drops
selected paths that no longer exist.

W9: a macro call card has a toggle at the right of its title; the open panel (its
step, in `Scope` view state, not the document) is part of the card's height and width
through `Projection.layout ~lens`, so opening it re-lays the graph out for the next frame
(the frame that opened it is painted with the old geometry). Its buttons are `Ui.box`es
in the tile: step buttons choose the printed step, "Replace call with expansion" is
`Syntax_edit (Inline_macro ...)`. A node call written in an input (a `->` step) is a card of its
own (`Projection.anonymous`, titled by its kind, wired through `Projection.sources`): never draw it
as a chip, and take a wire off its row with `Scope_pane.unwire` (Unfold, then Disconnect) so the
node stays. A call whose first input fits its result
(`Projection.bypassable`) is bypassed by the `b` key or the context menu, `Syntax_edit (Toggle_bypass ...)`;
a bypassed card is hatched with ink-3 text (kit rev 3 has no flag on the title). On a node that cannot be bypassed but has a boolean `:visible` argument (a scene
object) `b` is `Set_arg :visible` instead (`Scope_pane.hide_row`: false, then true): one key means
"out of the render, not removed" in every graph. `Alt` `Up`/`Down` on a hovered input of a node for
which `Projection.reorderable` holds (a `list`, a `str` or a `scene/merge`) is `Move_item`. `m` is `Macro_requested paths`: the host owns the dialog
(`Pxui_shell.Prompt.macro`) and answers with one `Make_macro`.

W13: every W3 gesture the pane can make is a request. Text entry over a tile or frame is `Ui.value_field ~edit:true`
(Enter commits, Escape or a click away cancels; `Scope.editing` tells the host to keep its keys out), never a second
text path. Marquee is the canvas's own drag (`Marquee` in the drag state, one scope's nodes, Shift adds); frames are
`Frames_set` of a scope's whole list, their boxes are built after the tiles because a zone's tile covers its body,
and their resize is a `Sizing` drag applied on release. Keep new gestures as tests in `test_pxui_graph.ml`
(`scope_gestures`), which runs in a 3,000 x 2,000 frame so the zoom stays 1 and every field is built.

## Gap A additions

`Scope.bindings` now lists, per guide context (`Canvas` empty canvas, `Node` one node, `Multi` several), only the keys
that act there: walking and framing on the canvas; editing needs a selection; `Duplicate` (Command/Ctrl-D) and
`Delete` take several nodes, `Rename`, `Display` (`v`, `Display_set`) and `Fold_into` one.  Command/Ctrl-C, X and V
are `Copy_requested paths` (a cut adds `Delete_nodes`) and `Paste_requested`: the host owns the clipboard and the
text.  `scope_point` maps a screen point to a grid-snapped position inside a scope (where the host places a node
added from its menu); a right-click on empty canvas is `Menu_requested (x, y)`, the host's add menu there (a
right-click on a tile is the pane's own context menu).  Tile text follows the zoom down to 5 points; nothing is clamped larger than its row.  A frame is dragged by its
title (`Carrying`: the nodes of the scope whose centres lie inside it travel with it, one `Moved` and one
`Frames_set`); `f` (`Frame_selection`) pans and zooms to the selection.  A zone draws its own footer under its body
(the layout reserves `foot_height`), and a loop over `sop/point_list` or `sop/piece_list` says `by index` or `by <key>`
in its header.  The macro lens has a Template button (one step past the expansions) and every footer of a node
inside a geometry loop is forced for the probed element once the zone cooked.

## Carry (flow.md §7.12)

`Scope` is a drop target and never a drop handler. While `Pxui.Ui.carrying` holds a payload, `update` asks
`Ui.drop_target` of the canvas (one call per frame, nothing when idle) and then of each visible tile, and
reports the innermost node under the pointer, else the empty canvas, as `Drop_over {path; kind; value}`;
the frame the pointer releases there it is `Dropped {path; kind; value}`. The canvas is the one-segment
path `[graph]`. The host decides whether the place takes the payload (it runs the edit and the checker)
and hands the answer back with `with_carry ~lit ~hot`: `lit` are the letters of the key route's places
(nodes, or the canvas), `hot` the place under the pointer and whether it takes the payload; the pane only
outlines them. Never match a node's operation here, and never emit a `Syntax_edit` for a drop.

## Sheet structure (Package B, round 2)

The pane's structure is `graph.html`'s, not only its card internals:

- **Levels.** `Projection.level` Point / Chip / Card / Full is layout data stored by path (`Layout_by_path.level`,
  `pinned`) and travels as `Level_set` through `Doc.layout_edit`, one history entry per gesture. `o` opens the
  selection one level and pins it, `p` points it or goes back, `⇧O` / `⇧P` do it for every node. The layout reserves the requested level's size and the pane draws that level at every zoom. A card's body is `P.placed.lines` (`Projection.lines`): the rows
  `Flow_sop.Exposure.shown` lets through (wired or written, a written default included, so a row whose wire is taken off stays: `fallback` writes the
  schema default; the schema's primary rows are not applied on the card, see
  flow.md 5.1); Full lists every row under its folder label rows. Index rows through `lines`
  (`line_of_row`), never through `n.rows`.
- **Header in-port.** The first geometry slot of a node kind (`row.head`) is the header's in-port at (1, 13), not a row;
  connecting, disconnecting, hover and the drop target work on it (`row_at ~header`).
- **Value cards.** A literal binding (`Projection.value_card`) is the header-only card: name, the value field, out port.
- **Lattice.** Cards and columns sit on the 24-point dot lattice (`Projection.lattice`, `snap`); a zone's cards, not its
  edge, are on it. `Moved` and `scope_point` snap to it.
- **Zones.** A plain `for` is the tint, a 1-point edge, the label row (`FOR`, binder, `in <source>`) and the selector at
  top + 3; cards inside are wired across the edge. What a loop needs beyond that is drawn only when used: the
  collection's in-port at the label row when a name feeds it, the loop variable's out-port at (12, 36) when something
  reads it, accumulators and further variables as rows under the label row (`Projection.extra_rails`, out-port at the
  row's right end), the zone's own out-port at the right of the label row, and a fold's feedback as a dashed wire.
- **Failed node.** `Scope.with_failed` paths with codes; the host (`Core.failed_nodes`) maps a failed cook's node id to
  paths through the probe plan. **Letter hints.** `w` (`Show_hints`) labels every node the selected output can connect
  to; `f` frames the selection (all with none selected).
- **Fold button.** A row wired from one named node that nothing else reads (`fold_sources`, computed in
  `with_scope`) draws `ƒ` before its `←`; a click is `Syntax_edit (Fold_into ...)`, the inverse of the click on an
  expression row's `ƒ` (`Unfold`). `wired_geo` places the glyph for the painter and the hit box alike. 1-point frames are drawn inside the box (`frame_in`), never as a centred stroke.

## What a frame costs (audit G22, G25)

A frame's work follows what is in view, never the size of the graph. `compute` builds, with the geometry, the
bucket indices over the tiles and over the wires' bounds (`geo.tiles`, `geo.reach`, asked through `index_query`),
the item of a path (`geo.slot`, `item_at`), the wired out-ports (`geo.read`) and the wires that end inside each
zone (`geo.inside`); `update` asks them and never walks `geo.items` or `geo.wires`. A wire segment is cut to the
viewport (`clip_segment`, the pane's one Liang-Barsky clip, which routing's `crosses` shares) before it is made
into 16-point hit boxes; the wires of a zone's body get their boxes again right after the zone's tile, cut to
it, so they lie over the tile and under the cards. Gestures that take every node (`⇧P`, a drag of the whole
selection, the letter hints) look paths up in tables or sets, never in lists. `scope_idle_frame` in
`test/test_pxui_graph.ml` bounds the allocation of an idle frame with nothing in view on 2,001 nodes;
`dune exec test/test_main.exe -- bench_scope_big` prints the frame, the 16 x 16 pane, `Point_all` and one
`Set_arg` edit.

## Rows and items (audit G5, G12, G14, G15)

A port's colour is `Node_menu.port_color`, for the menu's squares and the pane's ports, type squares and wires.
`+ field` names the field with the first unused `fN`; `+ output` opens a name field over its row (`Output` in
the editing state) and commits `Add_field`; a `+` row whose type has no literal (geometry, a list, a function,
a scene) answers with the "wire a node" notice. An item of a variadic input has no fallback: taking its wire off
removes the item, and Delete over a hovered item removes it whatever it holds. A right-click on a node makes
the nodes the selection (`Selected`, and the selected wire is dropped). `with_scope` ends the letter hints and
the context menu when the scope it is given is a new one.
