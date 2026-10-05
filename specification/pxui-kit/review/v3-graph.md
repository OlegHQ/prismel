The graph panel still does not match the sheet: the card internals are right, but layout, wiring, the zone's extras, the card bodies and the bottom bar all read differently at a glance. Nothing was built or edited; all renders are at 2x in `/private/tmp/claude-501/-Users-snowbear-WORK-GIT-prismel/3f162fa8-7a40-429c-8606-d41c30b5f285/scratchpad/kit/v2-graph/` (`V/` below).

The useful side-by-sides are `V/ws_cmp.png` (workspace sheet over the app), `V/z_ref.png` against `V/z_sel.png` (zone), `V/l_ref1.png` / `V/l_ref2.png` against `V/l_app1.png` / `V/l_app2.png` (levels), and `V/s_hint.png`, `V/s_tip.png`, `V/s_hov.png` (states). Fixtures are `V/m1.rays` (a `for` zone like the sheet's) and `V/m2.rays` (point, chip, card, full, bypassed, failed).

Ordered by how much it hurts the eye:

### 1. Workspace pane — the graph does not fit and its wires cross
- **Sheet:** five items in one tidy row, all inside the 902-point pane; grid1, count, box1 stacked in that order; the main chain is one straight line.
- **App (`V/ws_cmp.png`):** `out` is cut off at the right edge and `count` at the bottom. The order is grid1, box1, count. `copy1` sits on box1's row, so scatter1 → copy1 is a long diagonal crossing the box1 wire, and count → scatter1 is a near-vertical diagonal through the gap between the columns.
- **Change:** in `Projection.layout` (`lib/flow_sop/projection.ml`):
  - keep graph inputs in written order instead of sorting them last (the `order` sort on column 0);
  - line a card up with its upstream neighbour on the main chain, not only with its `head_src`;
  - make the first view fit the pane (see finding 2, which is what makes it overflow).

### 2. Cards in the graph carry two rows the sheet's cards do not
- **Sheet:** in the main graph and the workspace, a card ends after its rows (scatter1 is header plus three rows; grid1, box1 and out are a header only). `+ 5 more` appears only on the Card specimen and the footer only on the Full specimen.
- **App:** every card has `+ N more` and a `200 prims` footer, so header-only nodes become three-row cards (grid1: `+ 11 more`, `200 prims`; out: `+ 1 more`, `720 prims`). This is what makes the graph too tall and too busy.
- **Change:**
  - Do not reserve or paint the footer on Card level; keep it for Full (`Projection.size ~foot`, `paint_node` → `paint_footer` in `lib/pxui_graph/scope_pane.ml`).
  - `+ 1 more` on `out` is wrong against the sheet: the hidden `[+]` Add row must not count (`Projection.lines`, the `hidden` partition).
  - Whether `+ N more` shows on every Card is the owner's call: the sheet draws it on the specimen and omits it in both graphs.

### 3. Wires — orthogonal multi-bend routes over the zone label; point wires strike through names
- **Sheet:** a wire is straight; the one detour (box1 → copy1.template) runs out horizontally, then one bend square, then one diagonal to the port.
- **App:**
  - `V/z_sel.png`: box1 → copy1 is a four-bend right-angle path that runs through the zone's label row (`FOR f in range floors`) and enters the zone twice.
  - `V/a_s2_c.png`: the box1 wire runs along the bottom brackets of the selected scatter1.
  - `V/l_app1.png`: a Point's out wire starts at the disc centre and strikes through its name (`pt`, `window`).
  - `V/s_hint.png`: detours put their bend at the far end, so three wires into one node become near-vertical parallel lines.
- **Change:**
  - `route` in `scope_pane.ml`: one bend — horizontal from the source, then a diagonal into the port, with the bend about 72 points before the target as on the sheet. Treat the zone label row as an obstacle and keep 12 points clear of cards.
  - `out_anchor`: start a point's wire after its name (x + 22 + name width + 6), or draw the name on the ground fill above the wire.

### 4. `for` zone — extra ports, marks and footers, and its cards drop a row
- **Sheet (`V/z_ref.png`):** tint, edge, `FOR f in range floors` flush left, selector. Cards inside sit on the same row as the cards outside (zone top is 52 above them), so grid1 → scatter1 and copy1 → out are straight lines across the edge.
- **App (`V/z_sel.png`, `V/m1_a.png`, `V/m1_b.png`):**
  - The zone starts on the outer row, so its cards are 48 points lower and every wire across the edge is a diagonal.
  - There is a green in-port on the left of the label with `FOR` pushed 8 points right, and a wire from the `floors` input into it.
  - There is an out-port at the zone's top-right corner; copy1 is wired up to it and from there to `out`, instead of copy1 → out directly.
  - An accent `↑` sits after the kind in each header, and `↑ same each time` in each footer.
- **Change:**
  - `Projection.layout`: place the zone so its first inner card is on the lattice row of its header source (zone y = row − `rail_top`), not `zdy = -4`.
  - `paint_zone_frame`: drop the label in-port and indent, and the zone out-port, for a plain `for`. Wire the yielded card straight to the consumer in `compute`.
  - The invariant mark (`marks`) and the hoist button (`paint_footer`) have no place on the sheet: move them to the inspector or the context menu, or get the owner's sign-off.

### 5. Bottom bar — wrong content
- **Sheet:** `SCATTER1  Tab add after  o open  v view  b bypass  i enter  f hints  Space leader`, and at the right `6 nodes · 1 selected  ZOOM 100%`.
- **App (`V/a_k_c1.png`, `V/a_k_c2.png`):** `kit.rays ● checked · cooked 0.000 s | GRAPH SCATTER1  ? toggle guide  Space k all Flow keys  i follow / enter  ⇧I peek (floating graph)  y pick up (carry it onto a place)  u back (up a level)  ⌦ delete`, then cut off; at the right `LAYOUT 1 · GRAPH | INSPECTOR  60 FPS`.
  - None of Tab, o, v, b or f is listed.
  - There is no node count, no selected count and no zoom.
  - Labels are sentences, not the sheet's one word.
- **Change:** `status_box` in `lib/rays_editor/core.ml` and `Status_bar.guide` in `lib/pxui_shell/pxui_shell.ml`.
  - With the graph focused and one node selected, list exactly the sheet's seven pairs in that order.
  - Right side: `N nodes · M selected` and `ZOOM nn%` (from `Scope.stats` / `Scope.zoom`).
  - Shorten the labels in `Scope_pane.bindings` (`open`, `view`, `bypass`, `hints`).
- **Bug:** a click on a card's *name* (not its kind) leaves the strip with no keys at all until Esc (`V/b_app2.png`); a click on the kind side shows them.

### 6. Terminal node draws an empty out-port ring beside the view flag
- **Sheet:** `out` ends with the flag; there is no port on its right edge.
- **App (`V/s_tip.png`, `V/m1_b.png`):** an orange ring sits to the right of the flag.
- **Change:** in `paint_node`, skip the out socket when nothing reads the node and it is the displayed result (`out_wired = false` and `t.display = Some path`).

### 7. A boolean written `true` or `false` shows a filled, "wired" port
- **Sheet:** `normals` (on) has a ring.
- **App (`V/z_sel.png` `pack`, `V/l_app2.png` `use_density`):** a filled disc.
- **Change:** `wired` in `scope_pane.ml` goes through `Projection.sources`, which appears to count `true` / `false` as names (not traced); exclude the constants there, as `Projection.chip` already does.

### 8. Column spacing is tighter than the sheet
- **Sheet:** 96 points between cards. **App:** 68.
- **Change:** `Projection.column_gap` so the pitch is 288 (the lattice multiple nearest the sheet's 292).

### 9. `out` in the workspace sheet is a Point; the app draws a card
- **Sheet (`V/ws_cmp.png`, top):** a black disc, `out`, with the view flag under it.
- **App:** a three-row card. The point drawing with the flag below exists (`paint_point`), but the fixture and default level do not use it.
- **Change:** store `:level "point"` for `out` in `kit.rays`, or default a slot-only result node to Point.

### 10. Header toolbar — no `macro M`
- **Sheet:** `graph.html` has Add, Repeat, Iterate, fn, macro, defn. `workspace.html` has no macro.
- **App:** Add, Repeat, Iterate, fn, defn at both 1200 and 902 widths.
- **Change:** `Bars.tools` in `lib/rays_editor/bars.ml`: add `macro M` between fn and defn. Its existing width rule can drop it in the narrow pane, though there is room there too, so the owner should pick which sheet wins at 902.

### 11. Card footer wording
- **Sheet:** `1 204 pts · 0.003 s`. **App:** `200 prims`; a scatter reads `0 prims`.
- **Change:** `Flow_sop.Probe` footer value: points for point-only geometry, plus the cook time (the implementer listed the time as not done).

### 12. Text rows have no port
- **Sheet:** `group` has an ink-2 ring. **App:** `group`, `target_group` and similar rows have none.
- **Change:** `kind_rows` in `projection.ml` (`~socket`) — a small one.

## The implementer's four deviations, against the sheet
- **Primary rows hidden on Card:** not decidable from the sheet. Its specimen shows three rows and `+ 5 more`, while Full shows six rows, so the mock is inconsistent; the visible rule (wired or set rows) is what the app does. The cost is that header-only kinds get a lone `+ 11 more` row — see finding 2.
- **`+ 1 more` on `out`:** wrong; the sheet's `out` is a header only.
- **First view snaps to zoom 1:** right in intent (the sheet is at 100%), but it now overflows the workspace pane. It needs findings 1 and 2 to fit.
- **`f` hints, `⇧F` frame:** matches the sheet's bar. The chips render correctly (yellow, at the top-left corner, `V/s_hint.png`).

## Sheet items with no real feature behind them
- A range and position line on a graph input (`count 120` with a fill).
- `relax` / `pscale` sliders and `align` on these node kinds.
- The `E_PORT_TYPE` checker code: the app only shows cook codes such as `missing_group`.
- Cook time in the footer.
- The wireless-drive dashed wire, the function diamond port and the selected ink wire: no script step reaches them, so they are unchecked.
- The drop-target dashed card and the carry chip: also unreached.
- The bypass hatch: the sheet's own render shows none, and the app shows none, so they agree.