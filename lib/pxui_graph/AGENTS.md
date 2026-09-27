# lib/pxui_graph rules

`pxui_graph` presents one editable network (`Procedural.Edit_graph`) on the
shared PXUI handle and returns typed `change` requests. It never mutates the
document, cooks, or interprets operation names (hosts pass predicates such as
`~flaggable`). Keys are exported as `Editor_core.Command` entries through
`bindings`; the host scopes and dispatches them. Every interactive element is
a `Ui.box` keyed by stable ids; the graph's spatial index culls tiles and
resolves wire and port hits; there is no second hit-test, capture or
text-entry path.

## Current contract

Deterministic top-to-bottom layout by input depth (196×78 tiles), cubic
Bézier wires, output ports below and input ports above, a VIEW button per
tile, marquee selection on blank-area drag, right/middle-drag pan, pointer
zoom, and the categorised node menu (`open_menu_at`,
`catalog_of_factories`). Details: `specification/pxui.md` (Hosts) and
`specification/procedural.md` (Editable graph document).

## Prismel Flow rework

This library is where most of `specification/flow.md` lands (§6 canvas, §7
interaction). Follow `specification/flow-migration.md`: M1 replaces layout,
ports, wires and tiles (left to right, header trunk, polylines with bends,
levels point/chip/card/full, parameter rows, knife, box select); M2 adds the
grammar commands; M3 adds value nodes and row sockets through `flow_sop`.
Rules that hold throughout:

- Wires are polylines drawn with `Ui.line`; no curves after M1.
- New interactions return new `change` cases; `Prismel_editor.Doc.apply` is
  the only reducer, and each gesture is one history entry (`flow.md` §4.3).
- Layout (positions, levels, pins, splits, bends, wireless) is document data
  the host stores; selection, hover, pan and zoom stay in this library's
  immutable view value.
- The exposure rule comes from `Flow_sop.Exposure.shown` (M3); do not
  reimplement it here.
- Keep unchanged frames allocation-free on the identity fast path and keep
  `test/test_pxui_graph`'s 2,001-node smoke within its recorded baseline.
