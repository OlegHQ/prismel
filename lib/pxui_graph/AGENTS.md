# lib/pxui_graph rules

`pxui_graph` presents one immutable `Flow_sop.Network` on the
shared PXUI handle and returns typed `change` requests. It never mutates the
document, cooks, or interprets operation names (hosts pass predicates such as
`~flaggable`). Keys are exported as `Editor_core.Command` entries through
`bindings`; the host scopes and dispatches them. Every interactive element is
a `Ui.box` keyed by stable ids; the graph's spatial index culls tiles and
resolves wire and port hits; there is no second hit-test, capture or
text-entry path.

## Current contract

Deterministic left-to-right layout by longest input path, 196-point cards,
24-point headers and rows, 12-point snapping, geometry sockets in headers
and rows, and polyline wires with editable bends. Levels point/chip/card/full
have zoom caps, explicit pins and temporary full expansion during a wire
drag. Cards edit literals through `Ui.value_field`; value tiles and typed row
sockets use the same hit tree and spatial wire index. A VIEW flag marks the
display node; marquee selects, Alt/right/middle-drag pans, pointer motion
zooms, Alt-click edits bends and Command/Ctrl-drag cuts crossed wires.
The categorised node menu uses `open_menu_at` and `catalog_of_factories`. Details: `specification/pxui.md` (Hosts) and
`specification/procedural.md` (Editable graph document).

## Prismel Flow rework

This library is where most of `specification/flow.md` lands (§6 canvas, §7
interaction). M1 implements the canvas contract above. M2 implements walk, contextual
Tab/append/ripple, qualified repeat, letter hints, mute, dissolve, find and
selection framing as Command entries with guide contexts. Rows and fields
own hover through the shared PXUI hit tree; delayed tooltips never capture
input. Follow `specification/flow-migration.md`: M3 adds value nodes and row sockets through `flow_sop`.
Rules that hold throughout:

- Wires are polylines drawn with `Ui.line`; no curves after M1.
- New interactions return new `change` cases; `Prismel_editor.Doc.apply` is
  the only reducer, and each gesture is one history entry (`flow.md` §4.3).
- Layout (positions, levels, pins, splits, bends, wireless) is document data
  the host stores; selection, hover, pan and zoom stay in this library's
  immutable view value.
- The exposure rule comes from `Flow_sop.Exposure.shown` (M3); do not
  reimplement it here.
- Keep unchanged document replacement allocation-free on the identity fast path and keep
  `test/test_pxui_graph`'s 2,001-node smoke within its recorded baseline.
