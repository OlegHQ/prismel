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

Deterministic left-to-right layout by longest input path with short branches
tightened toward consumers and shared fan-outs anchored. Upstream branches
are separated in port order; layout reserves authored detail heights at every
zoom and re-layout clears stale bends. 196-point cards,
24-point headers and rows, 12-point snapping, geometry sockets in headers
and rows, and polyline wires with editable bends. Levels point/chip/card/full
have zoom caps, explicit pins and temporary full expansion during a wire
drag. Cards set numeric literals from pointer position through `Ui.value_field`;
Option-click or label double-click opens text entry. Value tiles and typed row
sockets use the same hit tree and spatial wire index. A VIEW flag marks the
display node; marquee selects, Alt/right/middle-drag pans, wheel and
two-finger scroll zoom at the pointer, Alt-click edits bends and
Command/Ctrl-drag cuts crossed wires.
Hovering a connected socket highlights its incident wires and both ends; hovering
a wire highlights that connection. Segment rectangles join the shared PXUI hit
tree behind the cards, so socket and control ownership takes precedence.
The categorised node menu uses `open_menu_at` and `catalog_of_factories`. Details: `specification/pxui.md` (Hosts) and
`specification/procedural.md` (Editable graph document).

## Prismel Flow rework

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

- Wires are polylines drawn with `Ui.line`; no curves after M1.
- New interactions return new `change` cases; `Prismel_editor.Doc.apply` is
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
`Syntax_edit (Inline_macro ...)`. A call whose first input fits its result
(`Projection.bypassable`) has a `B` flag on its title, `Syntax_edit (Toggle_bypass ...)`
like the `b` key. `m` is `Macro_requested paths`: the host owns the dialog
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
