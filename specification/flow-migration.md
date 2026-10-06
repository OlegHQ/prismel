# Rays Flow migration

How to take Rays Editor from today's SOP graph to the design in
`flow.md`. This file is the work queue for agents: milestones, the files each
one touches, the tests that prove it, and the docs that change when it lands.

## How to use this file

1. Read `flow.md` §1 and the milestone's sections before touching code.
   Open `specification/flow/prototype/index.html` to see the behavior.
2. Take the first milestone whose status is not `done`. Never start one whose
   preconditions are not met, and never add code for a later milestone.
3. Work in small commits. Every commit keeps default `dune runtest` green and
   passes `dune build @check`. Use focused tests while iterating
   (`dune build @lib/<name>/runtest`, `test/` aliases) and run
   `@runtest-native` once at the end of the milestone, not per commit (tests
   must not spam windows).
4. When the milestone is complete: tick every task, set its status row to
   `done` with the date, add a log line, apply its "Docs when it lands" list,
   and report the benchmark numbers named in its "Measure" line.
5. If the spec is wrong or ambiguous, stop and fix `flow.md` first (and the
   prototype if affected), recording the decision in `flow.md` §18.

Pre-commit loop (root `AGENTS.md`):
`dune build @all && dune runtest && dune build @smoke && git diff --check`.
A public `.mli` change shows as an `tools/api_manifest/api_stable.json` diff;
accept an intended one with `dune promote`.

## Status

| Milestone | Scope | Status | Landed |
|---|---|---|---|
| M0 | Spec, prototype, docs aligned | done | 2026-09-27 |
| M1 | Canvas: direction, polylines, bends, levels, box select, rows, preset v3 layout | done | 2026-09-27 |
| M2 | Keys and guide mode, World key remap | done | 2026-09-27 |
| M3 | Value ports: `flow`, `flow_sop`, value nodes, drives by wire, exposure, vec3, inspector | done | 2026-09-28 |
| M4 | Wireless binds, expressions, fold/unfold, row keys | done | 2026-09-28 |
| M5 | Compounds and contexts | done | 2026-09-28 |
| M6 | Views: list with values, read-only text, reader and checker | done | 2026-09-28 |
| M7 | `[%flow]` PPX and catalog manifest | done (PPX, `Build`, `Program` deleted in W12; the manifest stays) | 2026-09-28 |

## Original → target map

Every original behavior that changes, and the milestone that changes it.
Completed milestones use the target column. Anything not listed keeps working
as documented today.

| Area | Original behavior | Target | Milestone |
|---|---|---|---|
| Layout direction | rows by input depth, top to bottom (`automatic_layout`) | columns by longest path, left to right (`flow.md` §6.1) | M1 |
| Wires | cubic Béziers (`wire_handle`, `wire_segments`, `wire_distance_squared`) | polylines with bends, `Ui.line` | M1 |
| Ports | output below, inputs above the tile | primary slot and single output in the header row; others as rows | M1 |
| Tile | fixed 196×78 tile with VIEW button | levels point/chip/card/full; VIEW flag in the header | M1 |
| Tile position storage | `Document.network.layout : (float * float) Layout.t` | layout record (`flow.md` §4.1) | M1 |
| Preset format | version 2 | version 3 only | M1 (layout), M3 (values, drives), M5 (definitions) |
| Parameters on the canvas | none; inspector only | rows on cards by the exposure rule | M1 (literal rows), M3 (sockets) |
| Empty-canvas left drag | marquee (exists) | marquee; Alt-drag also pans | M1 |
| Graph keys | Copy, Cut, Paste, Duplicate, Delete, Frame_all; `f` frames displayed tile | full grammar (`flow.md` §7.2); `f` frames the selection or the display node | M2 |
| World graph keys | `e` `r` `p` `[` `]` `1`–`4` | `t` `n` `d` `[` `]` `1`–`4` | M2 |
| Status bar | names the open level's keys | guide strip by context | M2 |
| Value nodes, drives | none | `flow` value kinds; wires into parameter rows | M3 |
| `Param.field` | no primary or vec3 metadata | `primary`, `vec3` | M3 |
| `_x/_y/_z` triples | three separate float rows | one vec3 port per `[@sop.vec3]` group | M3 |
| Inspector | folders, all rows | plus card pins, vec3 rows, drive display, reset | M3 |
| Expressions | none | `=` fields, fold/unfold | M4 |
| Levels | scene → object network; "there are no subnetworks" | plus compound definitions under instances | M5 |
| `Space l` | list ⇄ graph | graph → list → text | M6 |
| Sketch source | OCaml `Sop.*` pipelines (still supported) | also `[%flow {| … |}]` | M7 |

## M1 Canvas

Preconditions: none.

Tasks:

1. [x] `lib/pxui_graph/pxui_graph.ml`: replace `automatic_layout` with the
   left-to-right column layout of `flow.md` §6.1 (column pitch 256, snap 12).
   Keep determinism and the identity fast path for unchanged documents.
2. [x] Same file: port geometry of §6.2 (header trunk sockets, row sockets, chip
   bottom attachments, point centres) and a `levels` input from layout.
   Remove `wire_handle`, `wire_segments`, `wire_distance_squared`; add polyline
   construction (stubs, bends), segment-distance hit testing through the
   existing spatial index, bend handles as `Ui.box`es keyed by
   (destination node, slot, bend index).
3. [x] Render levels point/chip/card/full (§6.4) with explicit
   pinning (the zoom caps were removed: a node keeps its level at every zoom), bloom during wire drags. Cards show slot rows and parameter rows by
   the exposure rule, with steps 1, 3, 4 and the first-folder primary default
   (driven rows arrive with M3); non-drivable kinds render as fields without
   sockets. Rows edit literals: scrub (soft range / 150, Shift / 1500) and
   click-to-type, emitting a new `Set_parameter_requested { node; path; value }`
   change; the host applies it with `Edit_graph.apply_parameters`.
4. [x] Change list additions in `pxui_graph.mli`: `Set_parameter_requested`,
   `Bend_changed of { node : int; slot : int }` (layout only),
   `Level_changed of int list`.
   `Doc.apply` in `lib/rays_editor/doc.ml` handles them and reports the
   touched ids and ports so `Network_view.edit` updates only those.
5. [x] `lib/editor_document/document.ml`: `network.layout` becomes the layout
   record of §4.1 (row exposure metadata is preserved; split and wireless stay
   empty until M3/M4). Update `validate`, `positions`, `Network_view.of_view/edit/to_view`.
6. [x] `lib/editor_document/preset.ml`: version 3 for layout fields (level, pinned,
   geometry bends) and stable ids (§4.4). Read and write only v3; remove the
   v1/v2 compatibility paths.
7. [x] Pointer map of §7.1 for what exists in M1: box select on empty drag
   (exists), Alt-drag pan, Alt-click bend add/remove, bend drag, Ctrl/Command-drag
   knife (one `Step` entry "Cut wires"), double-click card ⇄ chip.
8. [x] `o`, `p`, `⇧O`, `⇧P` as `Pxui_graph.command` cases exported through
   `bindings` (the host scopes them); "Detail level" history entries use
   `Burst` merging (§4.3).
9. [x] `lib/pxui/theme.ml(i)`: port palette tokens of §6.5 as additions; nothing
   existing changes.

Tests:

- `test/test_pxui_graph.ml`: layout is left to right and deterministic;
  polyline hit tests (on segment, off by 7 points, at bends); bend add, move,
  remove; knife removes exactly the crossed wires; level rendering counts
  boxes per level; pinning; bloom; exposure rows for a SOP with
  folders; scrub and typed edits emit `Set_parameter_requested`.
- `test/test_editor_document.ml`: v1/v2 rejection; v3
  round trip; invalid layout rejected without installing.
- `test/test_editor_transactions.ml`: one undo entry per move, bend, scrub
  gesture; Burst merging for level changes.
- `lib/pxui/test_ui_parity`: regenerate only the graph fixtures, intentionally.

Docs when it lands: `pxui.md` (Hosts: `Pxui_graph.update` paragraph; wire
rendering line), `procedural.md` (Editable graph paragraph), `api.md`
(pxui_graph paragraph and tile wording), `performance.md` (SOP graph
baseline), `scene.md` (tile wording), `lib/pxui_graph/AGENTS.md`,
`lib/rays_editor/AGENTS.md`: replace the "M1" target notes with the new
current text.

Measure: `tools/bench_pxui_graph.ml`, `tools/bench_rays_editor.exe 200 1000 2000`,
`test_pxui_graph` 2,001-node smoke, plus an all-points case, before and after.

## M2 Keys and guide

Preconditions: M1 done.

Tasks:

1. [x] Command entries for every M2 row of `flow.md` §7.2 with the listed ids:
   `Pxui_graph.command` gains the canvas cases (walk, add, repeat,
   connect-hint, display, mute, delete, dissolve, find, frame); host-level
   ones go in `lib/rays_editor/leader.ml`. Validation of overlaps stays as
   today.
2. [x] Tab contexts and ripple (§7.3), repeat (§7.4), letter hints (§7.5, the
   `c` half), walk (§7.6), dissolve (`⇧X`: reconnect the primary input's source
   to every consumer), find (§7.10).
3. [x] `f`: frame the selection, or the display node with none selected.
4. [x] World keys: `leader.ml` `world.emit` → `t`, `world.reseed` → `n`,
   `world.play` → `d` (graph scope, World level only, as today).
5. [x] `Editor_core.Command.t` gains `guide : Guide_context.t list` (pure data,
   default `[]`); `lib/pxui_shell` `Status_bar` renders the strip of §10 for
   the focused graph pane; tooltips after 380 ms (a `Ui` hover-delay helper in
   `pxui`, one path for all tooltips); `Space k` key sheet
   (`Pxui_shell.Which_key` style panel listing the grouped table); `?`
   toggles, persisted with `Editor_core.Store` user preferences; key HUD.

Tests: `test/test_editor_commands.ml` routes every new key window-free and
checks scopes; hint labels for a fixed 30-node layout (two-letter case);
walk from each node of a fixed graph; Tab ripple moves exactly the
downstream nodes; guide strip contents per context; World keys at the World
level only.

Docs when it lands: `api.md` "Sketch workspace keys" table and plain-key
paragraph; `scene.md` World keys; `lib/rays_editor/AGENTS.md` key rules;
the `extend-rays-editor` skill (commands now carry `guide` contexts).

## M3 Value ports

Preconditions: M2 done.

Tasks:

1. [x] `lib/param`: `primary : bool` (default false) and
   `vec3 : (string * int) option` on `field` and `field_view`; `field` gets
   `?primary` and `?vec3` arguments. Dependency-free still.
2. [x] `ppx/ppx_rays`: `[@sop.primary]`, `[@sop.vec3 "name"]` (checks of
   `flow.md` §5.3), `[@@sop.node_slots "a, b"]`, key alphabet check
   `[a-z][a-z0-9_]*`, slot/field name clash check. PPX expect tests for each
   error.
3. [x] `lib/sop_catalog`: annotate every `*_x/_y/_z` triple with
   `[@sop.vec3 "<prefix>"]` (89 float triples today; mechanical, verify with a
   catalog test that no ungrouped `_x/_y/_z` triple remains); add
   `[@sop.primary]` where the first-folder default is wrong; name slots of
   multi-input SOPs. Catalog tests still instantiate every factory.
   Split the catalog's related SOP modules into a few coherent files using
   an OCaml codemod. Retain one PPX-generated registry, stable keys and
   factory behavior; do not add mutable registration or a second factory
   list. Verify the descriptor set before and after extraction.
4. [x] New `lib/flow` (`flow.ml`/`.mli` per module, wrapped): `Symbol`,
   `Context`, `Port_type` with coercions (§3.2), `Expr` (AST, infix parser,
   printers, evaluator; no exceptions), value kinds with `Param` schemas
   (§3.3), `Graph` (value nodes and outputs), `Diagnostic`.
5. [x] New `lib/flow_sop`: `Port`, `Drive`, `Network` (overlay, `validate`,
   operations of §3.11 for wires), `Exposure.shown` (§5.1, used by canvas, list
   and inspector), `Value_lane.resolve` (§13.1). Expose
   `Procedural.Node.Private.fresh_id` for value-node ids.
6. [x] `editor_document`: `Document.network` carries the overlay; preset v3
   `values` and `drives` arrays (§4.4); validation of §3.10.
7. [x] `pxui_graph`: value nodes, row sockets, drives rendering (← source, live
   readouts), drop onto rows including hidden ones via bloom, chip bottom
   attachments, `s` row pin (`Row_pinned`), vec3 rows and split toggle. Value
   kinds and SOP kinds share Tab search (categories Value, Math, Vector).
8. [x] `pxui_shell/Inspector`: §9 rows, pins, vec3 editors and split, drive
   display and reset (reset removes a drive; literal defaults come in M4 with
   `r`).
9. [x] `rays_editor/cook.ml`: run `Value_lane.resolve` before every submission;
   keep the applied-value table in the environment; time-dependent networks
   resolve every frame while playing.
10. [x] `test/dependency_gate.ml`: rules of `flow.md` §14.

Tests: exposure table; coercions; value lane change-only application and
unchanged cook key; 1 vs N domain byte-identical cooks with drives; preset v3
values/drives round trip and invalid drives rejected; drag-to-row and
hidden-row drop; inspector pins; vec3 split rules; gate.

Docs when it lands: `procedural.md` (drives and value lane), `api.md`
(inspector, parameters), `pxui.md` (Inspector host paragraph), `backend.md`
dependency section, root `AGENTS.md` libraries table (add `flow`,
`flow_sop` as current), `lib/sop_catalog/AGENTS.md`, `add-sop` skill
(`[@sop.primary]`, `[@sop.vec3]`, `[@@sop.node_slots]`).

Measure: value lane with 200 driven rows and a time source; editor frame
benchmarks before and after.

## M4 Binds and expressions

Preconditions: M3 done.

Tasks: `b` hints and toggle on a selected wire, wireless rendering rule and
`w` (§6.3); `=` field entry and inspector `=…` fields (§7.9, §3.5); `Expr`
drives in the lane; fold and unfold (§7.7) as `Flow_sop.Network.fold/unfold`
plus canvas ƒ buttons; `r` (§7.2 semantics); layout `wireless` in presets.

Tests: fold ∘ unfold identity property over random expressions (fixed seed);
fold refusal cases (shared node, non-math node); wireless visibility rule;
expression parse errors as values; `r` on driven vs undriven rows.

Docs when it lands: `api.md`, `procedural.md`, `lib/rays_editor/AGENTS.md`.

## M5 Compounds and contexts

Preconditions: M4 done.

Tasks: definitions and instances (§3.8) in `flow_sop`; `⌘G`, `⇧⌘G`, enter
and up for compounds with `Document.level` extended to instance paths;
export, unexport, interface rename/reorder in the inspector of the
Inputs/Outputs nodes; "make unique" (context menu and palette); `compiled_ids`
and `Compile.flatten` (§13.3); definition and instance contexts in presets
(built-in network contexts already land in M3);
`E_RECURSIVE` on load.

Tests: group → enter → up keeps ids, values and cooked geometry; ungroup is
the inverse on fixtures; export adds exactly one interface row; editing one
instance's definition changes all instances; make unique detaches; compiled
ids stable across unrelated edits; presets with definitions round trip.

Docs when it lands: `scene.md` levels and "no subnetworks" limit, `api.md`
levels, `lib/rays_editor/AGENTS.md` levels.

## M6 Views and text

Preconditions: M5 done.

Tasks: `Flow.Sexp` reader with positions and `Flow.Check` (resolution,
typing, diagnostics of §11.9, poison bindings), both context-generic over a
catalog descriptor; `Flow_sop.Print.network` (§11.7); list rows include value
nodes and badges (§8.2); text projection (read-only, click to select,
qualified toggle, `j`/`k`) in `pxui_shell` or `rays_editor`;
`Space l` cycles three views, remembered per level.

Tests: print/read/check over every catalog factory (non-default literals,
drives, a compound) and the generated sketch preset documents; every
diagnostic code has a failing sample and its message; printing unaffected by
layout edits. The two reconstruction laws of §11.8 run in M7 with its builder.

Docs when it lands: `scene.md` (`Space l`), `api.md` keys table,
`pxui.md` (text view host).

## M7 `[%flow]`

Preconditions: M6 done.

Tasks: `tools/flow_manifest.ml` writing `lib/sop_catalog/flow_manifest.sexp`
with a diff-and-promote runtest rule (§12.2); the `[%flow]` rewriter in
`ppx/ppx_rays` with located diagnostics and file-local nodes (§12.3–12.4);
`Flow_sop.Build.program` and `Program.t`; editor entry point accepting a
program; one example sketch (`sketches/flow_terrain/`, via
`dune exec tools/new_example.exe -- flow_terrain` conventions) that runs
finitely under `RAYS_MAX_FRAMES`.

Tests: expect tests for each diagnostic and ambiguity rule; manifest stays
current; §11.8's reconstruction and canonical reprinting laws hold over the
M6 catalog and preset cases; the example builds and opens in the editor.

Docs when it lands: `api.md` (`[%flow]` usage and dune stanza),
`lib/sop_catalog/AGENTS.md` (manifest), root `AGENTS.md` (loops: manifest
promotion), `add-sop` skill.

## After M7

Revise `flow.md` for the scene and World contexts (objects as a `scene`
network with the same canvas, keys, views and text), then plan it here.

## Workspace

The workspace plan (`specification/workspace/plan.md`, milestones W0-W12)
evolves Flow into Lisp documents with loops, functions, data, macros and live
`t`. Progress and notes are in `specification/workspace/progress.md`; each
milestone is recorded here with its date, what landed and its deviations.

| Milestone | Status | Landed |
|---|---|---|
| W0 fixes and catalog prerequisites | done | 2026-09-30 |
| W1 language core (`flow`) | done | 2026-09-30 |
| W2 lowering and cooking | done | 2026-09-30 |
| W2b live `t` | partial | 2026-09-30 |
| W3 document v4 and history | done | 2026-09-30 |
| W4 graph pane zones | done | 2026-09-30 |
| W5 probes and footers | done | 2026-09-30 |
| W6 viewport provenance | done | 2026-09-30 |
| W7 editable text | done | 2026-09-30 |
| W8 loops over geometry | done | 2026-09-30 |
| W9 macros UI, notes, bypass | done | 2026-09-30 |
| W10 contexts and shell | done | 2026-09-30 |
| W11 `.rays` sketches | done | 2026-09-30 |
| W12 migration and removal | done | 2026-09-30 |

### W0 fixes and catalog prerequisites (2026-09-30, done with W4 part A)

Landed: `sop/merge` pads group membership across inputs (a group one input
lacks is padded, bench in progress.md: `merge_pair` unchanged at 0.020 s,
`merge_pair_padded` 0.028-0.030 s), `sop/set_color` takes a `group` (empty means
all elements, a missing one is an error like other group-taking SOPs) and a
vec3 colour with the v3 preset migration, `Manifest.version` in the text
view, and the `:rotate` note.

The `Rest` slot landed with W4 part A (below): `sop/merge` takes any number
of inputs, W2's per-arity `flow.merge_n` factory is one `merge` factory.

### W1 language core (2026-09-30, done)

Landed in `lib/flow` (which still depends only on `param`): `Syntax` (authored
tree with notes, meta and stable form ids), `Lisp` (canonical 84-column printer
with spans per form), `Ty`, `Macro` (hygienic quasiquote expansion, limits 32
and 5,000), `Workspace` (checker and typed IR, liveness for `t`, loop
invariance), and `Eval` (the evaluator of everything that is not geometry: a
geometry plan keyed by `(site, iteration tuple)`, the `static` / residual split
for live `t`, `?record`, the bit-exact `value/rand` hash specified in
`iteration.md` 2.2, and the run-time bounds). The 12 case fixtures
(`specification/workspace/cases/*.lisp`) are the single source for the study
and the OCaml tests; they check with no diagnostics, print canonically,
round-trip and run deterministically at any `t`. 119 of the study's 120
`check.cjs` cases are ported (`test_workspace.ml`, `test_workspace_eval.ml`);
`freeSymbols`, a JS helper of the canvas, has no OCaml counterpart.
`flow.md` 11 points to the workspace language and `iteration.md` 2 and 7 are
normative.

Deviations: fixtures were changed to fit the real catalog (`group_random`
takes `:probability`, `sop/circle` has `radius_x` and `radius_y` so Variations
uses a tube, Tree's third rotation is inside the soft range) and Wave uses a
workspace operator `sop/curve` because no catalog node builds a polyline from a
list of points (W2 gives it a native node). `Workspace.context` carries
`Settings` and `Editor` until `Context.t` does (W10). Two study tests that put
a literal `(range 9999)` in an untaken branch use a graph input, because L3
rejects the literal at check time. Details and measurements are in
`specification/workspace/progress.md`.

### W2 lowering and cooking (2026-09-30, done)

`Flow_sop.Lower.workspace` checks a workspace, evaluates it and returns one
`Network.t` per sop-context graph instance (top-level graphs and each distinct
`ref` override tuple, shared nodes keeping their ids), with compiled ids per
`(instance, site, iteration tuple)` in the existing
`compiled_ids : int Instance_path.Map.t` (an iteration segment is `-(index+1)`),
a plan-to-compiled id map, the live parameters (drives since W2b) and
a provenance table (W6: tag -> merge, input, site, iteration tuple).
Merges write `__flow_src` through the new `?source_attribute` of
`Rdk.Mesh_merge.merge` and `Procedural.Sop.merge`. The editor `Session` default
is 512 entries (measured in `progress.md`). `test_workspace_cook` cooks every
fixture at 1 and 3 domains byte for byte; `tools/bench_workspace_lower.ml`
records the timings (Bloom lower + cook 2.2 ms).

Deviations: every `sop/merge` lowered to an internal `flow.merge_n` node until
the `Rest` slot landed (W4 part A: one `merge` factory with a rest slot); `sop/curve` is a `flow.curve` node (points baked in W2, an encoded parameter driven live in W2b);
bypass is resolved by `Eval` so `Edit.set_bypass` is not used yet; four
fixtures changed so their merges have identical attribute schemas; cooking
exposed four bugs (Eval `reduce` with an int seed, the `cap_group` default of
PolyWire/Revolve/Sweep, Tube's default `rows`), fixed in this milestone.

### W2b live `t` (2026-09-30, partial)

Landed: `Flow_sop.Drive.Live of Flow.Eval.value` (a value holding residuals),
evaluated by `Value_lane.resolve` beside `Expr`; `time_dependent` is true with
any live drive; only changed ports are applied (scalars and vec3 by value,
colour text as vec3, text and lists by their encoded text in the new
`resolved.applied_text`). `Lower.workspace` installs one live drive per pending
argument in every network holding the node, keyed (compiled id, argument
name); `Lower.is_volatile`, `objects` and `counts` serve the session, the
editor cook and the viewport header. `sop/curve` lowers to
`Flow_sop.Curve.factory` (`flow.curve`, a text-encoded `points` parameter that
is part of the cook key), so Wave animates with one drive per strand.
`Procedural.Session.set_volatile` gives a volatile node one replaced-in-place
slot outside the LRU (`volatile_hits`, `volatile_misses`, `volatile_entries`
in `stats`); `Async_cook.await`, `set_volatile` and `stats`; `Cook.create
?await` (default: `RAYS_MAX_FRAMES` set) makes `Cook.update` wait for the
cook it submits, so a fixed-step run shows exactly frame n; the status reads
`cook N ms · skipping frames` while playing with a newer frame queued. Tests:
`test/test_workspace_live.ml` (live equals the static evaluation at that time
for Orrery, Wave and a live Sunflower; Orrery 600 frames with session
counters; 1 and 3 domains; the realtime-edit cone; the editor cook path with
await) and `test_procedural.ml` (volatile slots, await).
`tools/bench_workspace_live.ml`; numbers in `progress.md`.

Deviations: `?volatile` is `Session.set_volatile` (an optional argument on
`create` cannot be erased at its 100+ callers, and each lowering changes the
set); `Drive.Live` holds an `Eval.value` (Wave needs lists, Orrery colour
text) and is not type checked. What W3 must connect: `Cook.set_volatile cook
(Lower.is_volatile lowered)` and `Cook.update ~objects:(Lower.objects
lowered)` after each lowering (`Cook.update` is otherwise unchanged; the
document still holds v3 networks), and an export host passes `~await:true`.
Not done: the UI text (◷ chips, the inspector cook line, the viewport header)
is W4/W5, which read `Lower.pending`, `Lower.counts` and `Cook.seconds`.


### W3 document v4 and history (2026-09-30, done)

Landed: `Flow_sop.Flow_edit` (one `op` variant, `apply`, `apply_checked`,
`label`, `gesture`, `remap`, `fresh_name`, `default_for`, `literals`, the
`arg_key` type), `Editor_document.Workspace_doc` (`of_text`, `to_text`,
`edit`) and `Layout_by_path`, `Document.workspace` and `Document.of_workspace`,
s-expression presets (`Preset`), `Document.dump`, `Doc.syntax_edit`,
`Pxui_graph.Syntax_edit`, `Editor3/2 ?workspace`, `edit`, `workspace`,
`undo_label`, `redo_label`. The editor is fed by a workspace: every gesture
lowers again and `Cook.set_volatile` gets `Lower.is_volatile`, so time-driven
workspaces animate in the editor and static nodes stay cached
(`test_workspace_doc`). `Lower`'s `sites` and `compiled_ids` travel in
`Document.workspace` (history state), so ids stay stable across edits and
undo. Tests: `test_workspace_edit` (every study gesture as a text test),
`test_workspace_doc`.

Decisions: no older presets are read or converted. The v3 JSON reader and
writer, W0's set_color migration and the `Preset` kind of `Editor_core.Store`
are deleted. A preset is one `.rays` file: the workspace form with its
comments, then optional `(layout ...)`, `(settings ...)` and `(view ...)`
forms, the same text a W11 sketch is. JSON remains only where it is not a
document: user preferences and viewport encoders (`Store.Settings`,
`Store.Viewport`, the in-memory `view` value, which `Preset` writes as an
s-expression) and build glue such as `api_stable.json`.

Deviations and gaps: only workspace documents save; a sketch opened with
`?graph` or `?program` has the legacy scene network (camera and light
objects, compounds, value nodes) that has no workspace text yet (W10, W12),
so `Space s` reports why and the crash report writes `document.txt` (a
deterministic text of any document) but no `.rays`. Loading a preset gives
geometry objects only; the editor adds its default camera. `Layout_by_path` is
stored, remapped and saved, and the workspace pane reads it since W4 (`frames` are titled rectangles under the tiles). `Doc.apply`'s `Syntax_edit` case
is a no-op inside the network fold; `Doc.syntax_edit` is the reduction (the
source is not a `Flow_sop.Network`). `Wrap` uses the checker as its type
oracle (geometry, then number shape; each candidate feedback input) instead of
reading types from the IR; the study's `exceptIteration` and
`set_layout_ratio` (W10 part B: `Set_layout_ratio`) are not ported. A new binding's name comes from
`fresh_name`, so a caller can select it. `Flow.Workspace.name_taken` says which
names a binding may not take. `test_editor_document` builds its fixtures in
code (the JSON fixtures and rejection matrix are gone) and
`test_rays_editor` no longer restores a fixed camera from a preset (the native look-through framebuffer comparison went with it: a following camera does not reproduce it).

### W4 graph pane, part A (projection) and part B (drawing) (2026-09-30, done)

Landed (UI-free): `Flow_sop.Projection` (`of_graph`, `find`, `zones`,
`layout`, `place`, the row types and card constants), the `Rest` input
requirement and `sop/merge` with one rest slot (`Edit_graph`, `Check.slot.rest`,
the manifest, `Build`, `Lower`), `Flow.Workspace.op_signature`, `group_reader`
and `group_writer`, `Flow_edit.free_names/pat_names/pat_key`, and
`test/test_projection.ml`. Deviations, the Rest design, and exactly what part
B (the `Pxui_graph` side) must do are in `specification/workspace/progress.md`
(W0 `Rest` and W4 part A notes).

Part B: `Pxui_graph.Scope` (`lib/pxui_graph/scope_pane.ml`) draws a
`Projection.scope`: zones under the tiles in the canvas paint (`Theme.zone_*`,
dashed and hollow for `fn` and `let*`), rail rows with source sockets, a yield
row, the fold feedback line, the iteration selector (two buttons, a track and
a readout, plain boxes; it emits `Probe_set`), chips with the glyphs
`ƒ for Σ ↵ λ {} ◊` (hover expands, the glyph unfolds), scrubbable numbers
(`Ui.value_field ~scrub`, `Set_arg`), output rows under a record or pattern
card, stacked (list), diamond (fn) and pill (record) sockets, the ◷ and ↥
marks. A wire dropped on a row is `Connect` (`iter` when its source is a loop
name), the input socket of a wired row disconnects, Delete on a hovered wired
row is `Disconnect`, the `+` row is `Add_item` / `Add_field` / `Set_arg`, the
context menu and keys (`r R l H F U b m c [ ] Del Home`, arrows) are the
rest; every one is a `Scope.change`, mapped to `Pxui_graph.Syntax_edit` by
`Core`. Only visible items are built and a zone's body is drawn once whatever
its count. `Core` shows the pane for a geometry object of a workspace document
(`scope_name`), reads `Layout_by_path.at`, `collapsed` and `frames` (a frame
is a titled rectangle under the tiles; nothing creates one before W10), keeps
the probes in `Core.probes` (view state, no history) and writes moves and
collapses as layout edits (`Doc.layout_edit`, one history entry, no recook).
Iteration counts come from one `Eval.static ~record:true` per checked source
(`Projection.counts`). Deviations: the pane has its own `Scope.change` type
(the flat pane's `change` and `Scope` cannot share one); the flat pane and its
BVH stay for non-workspace documents (converting it is a later ponytail);
DepartureMono lacks ⟲ ◆ ◷ ↥ ▸ ▾ so the pane draws ↵ ◊ t ↑ ► ▼; the
`[%flow]`-style value nodes have no pane in a workspace (`Add_requested`
becomes `Add_node`); there is no marquee (shift-click multi-selects);
the inspector still shows the lowered object (W5+). Perf, Sunflower with 240
iterations, `dune exec test/test_main.exe -- bench_scope_pane` (M-series, one
run): flat pane over the 241-node lowered network 0.135 ms and 503 KB per
frame; workspace pane zone expanded 0.259 ms, 675 KB; collapsed 0.070 ms,
173 KB. The 2,001-node smoke is unchanged (0.56 s, 619.7 MB standalone, baseline
578 ms / 619.7 MB).

### W5 probes, footers and sparklines (2026-09-30, done)

Landed: `Flow_sop.Probe` (values at the probe, footers, per-outer-probe
iteration counts, inspector rows), `Pxui_graph.Scope.with_records`, footers on
node and collapsed-zone cards (value, sparkline of at most 16 segments across
the innermost zone, `×n`, `then a · else b`, `kept a of b`, `↑ same each time`
as the Hoist button, `t` on live nodes), geometry counts from the cook
(`Cook.update ?probes`, `Cook.geometry`), `Core.workspace_inspector` (value at
probe, cook mode, Hoist, the node's catalog parameters through `Set_arg`, the
per-iteration list with `Probe_set`), the status strip `t N live · M cached ·
cook X ms`, and the W4 leftovers (a node added from the menu is selected, nested
zones count per outer iteration). Deviations, the perf table and the
`Eval`/`Lower` `default` instance fix (the editor had been showing a `ref`
override as the object) are in `specification/workspace/progress.md`. Native
check: `sketches/flow_workspace` (`FLOW_CASE`, `FLOW_ADD=1`, `FLOW_EXPORT`).

## Do not

- Do not draw curved wires or keep Bézier code for the graph after M1.
- Do not add a second hit-test, capture, text-entry or painting path; every
  interactive element is a `Ui.box` (root `AGENTS.md` UI rules).
- Do not mutate the model inside `Ui.frame`; panes return intents and
  `Core.update` applies them.
- Do not match `KeyPressed` in panes; keys go through the one Command table.
- Do not overwrite a parameter's literal with a driven value.
- Do not put value kinds in `sop_catalog`, or give `flow` a dependency beyond
  `param`.
- Do not change pixels outside the graph in `test_ui_parity`.
- Do not build, link or ship the prototype; do not add JavaScript or Python to
  the build.

## Log

- 2026-09-28 M7 complete: the generated manifest and its reader feed located
  `[%flow]` checks; the PPX emits checked terms and discovers earlier
  registered file-local SOP modules. `Build.program` verifies the linked
  digest and rebuilds SOP/value nodes, drives and definitions. Both editor
  hosts accept programs, and `sketches/flow_terrain` builds and runs finitely.
  The checker samples cover §11.9 diagnostics and §11.10 resolution rules;
  builder tests reprint every registered SOP and the generated v3 preset
  cases, including a partly driven vector and layout-only changes.

- 2026-09-28 M7 editor-entry checkpoint: `Editor3/2.create` and `run` accept
  `?program` in place of `?graph`; the program's network, display and shared
  definitions seed the initial document. Compiled compound IDs are allocated
  before the cook worker starts. Window-free editor tests cover a plain Flow
  network and a geometry compound from the program builder. The example and
  file-local PPX nodes remain.

- 2026-09-28 M7 PPX checkpoint: `-flow-manifest` loads the checked-in snapshot;
  `[%flow {|…|}]` checks the source at compile time and emits plain typed Flow
  terms for `Build.program`. Error spans map into the quoted OCaml string,
  with additional diagnostics as located sub-errors; warnings use the OCaml
  preprocessor warning. A Dune fixture compiles and runs the expansion, and a
  diagnostic fixture checks source offsets. File-local node discovery, the
  editor entry point, and the broader diagnostic matrix remain.

- 2026-09-28 M7 builder checkpoint: `Flow.Check.catalog_of_manifest` reads the
  generated snapshot for compile-time checking. `Flow_sop.Program` and
  `Build.program` reconstruct checked SOP/value nodes, parameter drives and
  compound definitions, assigning visible IDs in print order and rejecting a
  stale manifest digest. Focused canonical reprint cases cover geometry,
  value math, mixed Vec3 drives and both geometry/value definitions. The PPX,
  editor entry point, and full reconstruction matrix remain.

- 2026-09-28 M7 manifest checkpoint: `Flow_sop.Manifest` serializes the live
  factory registry and value kinds with slots, field kinds/defaults/ranges,
  primary and Vec3 metadata, plus a digest. `tools/flow_manifest.exe` writes
  the checked-in S-expression; the `sop_catalog` runtest diff requires
  promotion when metadata changes. The catalog test parses the generated file
  and checks every registered SOP key.

- 2026-09-28 M6 complete: reader and checker cover all emitted diagnostic
  codes with located samples and message assertions; nesting has a
  deterministic 256-form limit. The all-factory printer pass and generated
  preset documents print/read/check, including non-default literals, drives,
  compounds and layout-only edits. The three projections share selection,
  with keyboard and pointer checks in the editor. The two rebuild laws move
  to M7, where `Build.program` supplies the missing inverse.

- 2026-09-28 M6 text-view checkpoint: `Space l` cycles graph, list and text
  per level. The SOP/compound text pane caches canonical printing, maps
  binding clicks and `j`/`k` into shared selection, and toggles qualified
  symbols. Enter in list or text opens and frames the selected graph node.
  Scene and World show the reserved-context message pending their later Flow
  syntax revision. Window-free editor interaction and compound binding-line
  tests cover the new projection; full reconstruction laws remain.

- 2026-09-28 M6 printer checkpoint: `Flow_sop.Print.network` emits canonical
  text and binding-line mappings from the saved network without reading
  layout. It orders SOP and value dependencies, preserves named compound
  outputs, bypass, scalar and vector literals, drives, optional slots and
  absent displays. A live factory adapter supplies the checker/printer
  descriptor; every registered SOP factory prints and checks. Actual
  network reconstruction and the full `read(print d)` law follow with Build.

- 2026-09-28 M6 named-output decision: `defgraph` now accepts
  `(values :name expr …)` so M5 compound output renames survive text
  round trips. The checker and prototype recognize named results and reject
  duplicate or invalid output names; unnamed results retain `geo`/`out`
  defaults. The printer will emit explicit names where needed.

- 2026-09-28 M6 checker checkpoint: `Flow.Check` accepts plain catalog
  descriptors and returns a typed, qualified program plus located warnings or
  errors. It checks top-level forms, ordered definitions, contexts, namespace
  ambiguity, calls, references and outputs, keywords and slots, numbers,
  vectors, ranges, metadata and interface defaults. Failed bindings poison
  their later uses. Focused tests exercise valid SOP/value forms, referenced
  math, definitions and diagnostic cases. The printer, full round-trip law and
  text projection remain.

- 2026-09-28 M6 number-printing checkpoint: `Expr.sexp_number` expands
  scientific notation into exact decimal text accepted by `Flow.Sexp`, even
  for the smallest subnormal and largest finite Float. The checker normalizes
  accepted numeric and choice literals to their parameter kinds so the later
  builder can apply them without guessing a type.

- 2026-09-28 M6 list checkpoint: the existing tree now traverses the full
  `Flow_sop.Network`, placing value nodes before consumers along incoming
  drive edges and repeating shared sources as links. Rows show grouped
  driven/overridden counts plus `VIEW` and mute badges; unchanged networks
  reuse the cached rows. The text projection and checker still follow.

- 2026-09-28 M6 diagnostics checkpoint: language errors and warnings now carry
  severity, a 1-based source position and a byte span; runtime errors can
  omit source coordinates. Reader errors report the offending token or opener.

- 2026-09-28 M6 reader checkpoint: `Flow.Sexp` reads the specified forms with
  byte spans and 1-based line/column positions, including comments, quoted
  strings, keywords, vectors and metadata. It reports mismatched/unclosed
  delimiters and invalid escapes before checking names or types. A focused
  test covers structure, locations and syntax errors. The catalog checker,
  canonical printer, list extension and text view follow.

- 2026-09-28 M5 complete: geometry-port unexport now refuses connected body
  and instance wires and the displayed output, then removes an idle port from
  the definition and every shared instance while preserving other named
  wires. `Edit_graph.rebind_factory` supports changing optional slot arity by
  name and refuses deletion of a connected slot. Focused tests cover the
  shared edit, value-aware group/ungroup, Vec3 defaults, export, nested levels,
  stable compiled ids, preset round trips and recursive-definition rejection.

- 2026-09-28 M5 Vec3-default/export checkpoint: compound interface defaults
  now use `Port.literal`, so a whole Vec3 row keeps all three components.
  Grouping and `e` export preserve nonuniform defaults; factory fields,
  instance rows, document validation and preset round trips agree. A split
  vector must be joined before whole-row export. At this checkpoint,
  geometry-port unexport remained pending.

- 2026-09-28 M5 value-group round-trip checkpoint: grouping accepts mixed SOP
  and value selections, deduplicates typed value boundary ports, and rewires
  internal and external drives. Ungroup clones both node kinds, restores
  boundary drives and literal overrides, and projects Vec3 output components
  through a value splitter where needed. A value-only compound needs no
  geometry display. Focused tests cover cooked geometry parity, shared value
  sources, component projection, document validation, and preset round trips.
  At this checkpoint, whole-Vec3 export, geometry-port unexport, and
  nonuniform Vec3 interface defaults remained pending.

- 2026-09-28 M5 scalar-export checkpoint: `e` on a hovered Float, Int or Bool
  row inside a definition adds one typed Inputs port, wires it to the row,
  and rebinds every shared instance. Compound value rows now render on cards
  and in the inspector; editing an instance changes its own literal. The
  interface inspector renames and reorders value ports and unexports an
  unused value port, refusing instance drives or non-default overrides that
  would be lost. Tests cover preset round trips, shared metadata, value-port
  rename/reorder, and unexport guards. Vec3 whole-row export, value-aware
  grouping/ungrouping, and geometry-port unexport remain pending.

- 2026-09-28 M5 value-flatten checkpoint: `Compile.flatten` now substitutes
  instance value inputs and Outputs-marker wires into the flat drive set,
  clones inner value nodes under saved instance-path ids, and carries scalar,
  Vec3/component and expression drives into the value lane. Focused fixtures
  compare cooked geometry, two instances of one definition, nested value
  boundaries, time dependence, stable and missing ids, and a boundary cycle.
  Export/unexport, value-aware grouping/ungrouping, and inspector editing of
  value interfaces remain pending.

- 2026-09-28 M5 value-interface validation checkpoint: compound factory
  metadata now exposes typed value inputs and outputs on the Inputs/Outputs
  markers and on instances. Network validation accepts value wires across
  those boundaries, and instance literals use the same normalization as
  ordinary value rows. The focused test covers marker-to-value-node and
  instance-to-value-node wires. Flattening those drives for cook, export,
  unexport, and value-aware ungroup remain pending.

- 2026-09-28 M5 geometry-interface reorder checkpoint: Inputs/Outputs
  inspector move controls reorder adjacent geometry ports. Factory slots and
  logical input arrays move together by port name, so two-input/two-output
  tests retain their sources and compiled graph. Value interfaces and
  unexport remain pending.

- 2026-09-28 M5 geometry-interface rename checkpoint: the Inputs/Outputs
  inspector renames geometry ports on shared definitions. All instances keep
  their ids; incoming slot names, outgoing named wires, bend keys, compiled
  geometry and preset round trips follow the new name. Value-port editing
  and interface reorder/unexport remain pending.

- 2026-09-28 M5 make-unique checkpoint: the palette and compound tile context
  menu copy one shared definition with fresh internal ids, retarget only the
  chosen instance, preserve its geometry wires and layout, and record one undo
  step. Presets round-trip both definitions and compiled-id allocation
  traverses both copies. Value interfaces remain pending.

- 2026-09-28 M5 ungroup checkpoint: `⇧⌘G`/Shift-Ctrl-G replaces one
  geometry-only instance with fresh copies of its inner nodes, reconnects
  named geometry boundaries, carries layout into the parent, prunes stale
  compiled paths and records one undo step. Focused tests cover multi-output
  routing, nested definitions, cooked geometry, Editor2 undo/redo and the
  command route. Value interfaces remain pending.

- 2026-09-28 M5 compound-level checkpoint: `Document.level` now follows
  instance paths through shared definitions. `i` or double-click enters a
  compound; `u` returns to its parent and selects the instance. Editing at
  that level updates the shared definition, while display selection remains
  on the enclosing SOP network. Nested paths, undo fallback, preset reload
  and Editor2 navigation have focused tests. Value interfaces remain pending.

- 2026-09-28 M5 group checkpoint: `⌘G`/Ctrl-G groups selected SOP geometry
  nodes into the first free `compound_<n>` definition, deduplicates external
  geometry sources, rewires named outputs, preserves moved node ids and layout,
  and records one undo step. The canvas shows named compound output sockets
  and preserves the chosen port in new wires. The editor cooks the grouped result; preset
  round-trip and undo/redo tests pass. Driven/value selections and interface
  editing remain pending.

- 2026-09-28 M5 cook checkpoint: document edits allocate instance-path IDs
  before entering history; `Cook.update` flattens geometry before the value
  lane and uses only saved IDs. It caches the flattened network while the
  source, definition map, display and ID map are unchanged. Focused tests
  cover cooked geometry, idle reuse, missing-ID rejection and ID persistence
  through preset save/reload. Value interfaces and graph commands remain.

- 2026-09-28 M5 structural-node checkpoint: compound Inputs, Outputs and
  instance nodes now have interface-derived factories with stable preset keys.
  Preset v3 restores their named geometry slots from saved definitions;
  document validation requires one Inputs and one Outputs marker per definition
  and checks each instance's role, definition key and geometry slots. Round-trip
  and malformed-preset tests cover the boundary. Group/ungroup, value interfaces
  and cook integration are still pending.

- 2026-09-28 M5 geometry flatten checkpoint: `Flow_sop.Compile.flatten`
  resolves named compound geometry outputs and Inputs/Outputs interfaces,
  recursively inlines used SOP nodes under saved instance-path ids, and
  rejects missing ports or recursive definitions. A two-instance chain and
  cooked-geometry parity pass. Value ports and drives, editor commands,
  levels, and the cook handoff remain pending.

- 2026-09-28 M5 compiled-id checkpoint: `Edit_graph.paste ~ids` can inline a
  definition fragment under the document's saved compiled ids while retaining
  its factory metadata, optional slots and internal wires. It rejects missing,
  duplicate or occupied id mappings. The ordinary clipboard paste still
  allocates fresh ids; flattening will use the explicit mapping.

- 2026-09-28 M5 geometry-output checkpoint: `Network.geometry_outputs` records
  a named compound geometry source by destination port while ordinary SOP
  wires continue to use `geo`. Connect, disconnect, copy/paste and preset v3
  preserve it; load checks that the named output exists on the referenced
  definition. This supplies the multi-output route that `Edit_graph`'s
  source-id-only connections cannot express. Group/flatten UI is still pending.

- 2026-09-28 M5 identity/preset checkpoint: the Flow overlay carries instance
  references, and the editor document owns shared definitions plus compiled
  ids keyed by instance path. Preset v3 saves and reloads definitions,
  interfaces, instance literals and compiled ids. Loading rejects unknown or
  recursively referenced definitions, incompatible contexts, malformed
  interface data, duplicate compiled ids and orphan paths. Grouping, editor
  levels and flattening remain in progress.

- 2026-09-28 M5 foundation: `Edit_graph.subgraph` retains selected SOP ids,
  internal connections and factory metadata while disconnecting edges from
  outside the selection. Focused tests cover the retained identity and cut
  boundary. This supplies the move into a definition without paste's fresh-id
  behavior; compound definitions, instances and cooking still remain.

- 2026-09-28 M4 complete: `Flow_sop.Network.fold/unfold` converts unshared
  Math/Value/Time chains and checked expressions, with fixed-seed identity and
  refusal tests. ƒ buttons use the shared PXUI hit tree; the host places
  unfolded nodes left of the row and records each conversion as one edit.
  Wireless visibility, expression entry, reset semantics and preset layout
  were verified in focused and full default tests. `@all`, window-free
  `runtest`, and `@smoke` pass; native Flow/UI checks pass while the wider
  native target still reaches the GPU-film assertion at
  `lib/rays_pathtracer/test_gpu_film.ml:64`.

- 2026-09-28 M4 expression/reset checkpoint: `=` opens the shared PXUI text
  editor for a hovered numeric row, and a leading `=` in a canvas field or
  inspector expression field submits through the same document reducer.
  Parsed expressions remain drives; a pure number clears the drive and writes
  a normalized literal. `r` clears a drive without overwriting its literal,
  or restores the schema default on an undriven row. Editor-level tests cover
  dynamic expressions, literal restoration, numeric expressions and rejected
  malformed text. Fold/unfold remains.

- 2026-09-28 M4 wireless checkpoint: `b` reuses the shared letter-hint path
  for type-checked value binds and toggles a selected geometry or value wire;
  `w` temporarily reveals wireless wires. Wireless links use 2/5 dashes and
  otherwise appear only with a selected or hovered endpoint or wire. Layout
  flags persist through the existing edit/preset path and are removed when a
  drive disconnects or its source disappears. Graph, command and default
  window-free tests pass. Expressions, row reset and fold/unfold remain.

- 2026-09-28 M3 complete: the generated SOP factory metadata and value-kind
  schemas feed one typed Tab search. A selected value node or an output dropped
  on empty canvas filters compatible destinations and connects the new node;
  dropping on a card body chooses its first free compatible row. The canvas and
  inspector show live values from the cook environment, while literal records
  stay unchanged. The host resolves visible networks before submission, also
  while time advances. Focused UI, preset, drive, unchanged-key and one-vs-many
  domain checks pass, as do `@all`, window-free `runtest`, `@smoke`, and the API
  manifest. The native suite's unrelated GPU-film test fails at its two-texture
  assertion; the other native cases pass. Measurements are in `performance.md`.

- 2026-09-28 M3 canvas checkpoint: value tiles and typed drive wires share the
  geometry canvas's spatial index and PXUI hit tree. Card rows expose typed
  sockets; dragging a value output to a visible or bloom-revealed row emits a
  checked connection request. Chip wires attach at bottom sockets, vector
  rows split and join, `s` pins rows, and `c` includes compatible value ports.
  Live readouts, the inspector, and cook integration landed in the final M3
  checkpoint.

- 2026-09-28 M3 document integration: each saved network owns a context and
  one immutable geometry/value/drive overlay. Preset v3 requires and validates
  its value and drive arrays, logical vector splits, named geometry slots,
  wire bends and wireless flags; scene and World reject value nodes. The graph
  clipboard carries Flow fragments, preserving expression drives on copy and
  paste. This checkpoint preceded the value canvas work above; cook integration
  still follows in task 9.

- 2026-09-27 M3 SOP overlay and lane: `flow_sop` validates ids, grouped ports,
  coercions, vector conflicts and value cycles; copy/paste remaps the induced
  geometry/value graph together. Shared exposure follows drive/pin/default
  precedence. The environment-owned lane retains one plan/result, resolves
  only reachable values, keeps literals intact and applies changed SOP ports.
  Regressions cover removal, later literal edits, hard-bound plateaus and exact
  one/four-domain geometry payloads on a 16,384-point driven noise graph.
  Static cached resolutions reuse their result; the 200-drive benchmark and
  unchanged-parameter-write measurement are recorded in `performance.md`.
  Default tests and the dependency gate pass. Editor/preset integration follows.

- 2026-09-27 M3 expression and value graph foundation: expressions have
  located errors, checked arity, fixed IEEE semantics and exact infix/sexp
  round trips (4,624 generated cases). Six built-in value kinds keep typed
  `Param` literals, including grouped vector storage and inactive unary
  inputs. Immutable value graphs validate ids and preserve unchanged record
  identity. Focused and default tests pass; SOP overlay work follows.

- 2026-09-27 M3 value-core foundation: `flow` depends only on `param` and
  supplies diagnostics, checked symbols, reserved contexts, port types and
  coercions. PPX declarations reuse its name check. The gate rejects UI,
  geometry and GPU edges from the value core and PPX, with injected-edge
  regressions. Coercion checks cover vector rejection/broadcast, rounding,
  overflow and field hard bounds. Expression/value-node/overlay work follows.

- 2026-09-27 M3 catalog annotations: an OCaml AST codemod annotated all 89
  named float triples and 26 PPX input signatures; Switch and Merge retain
  their custom builders with named slots (28 multi-input factories total).
  Ten schemas mark their main size/deformation/UV controls primary. The
  registry regression rejects ungrouped triples and slot/field clashes;
  descriptors preserve literal defaults, bounds and operator keys. `@check`,
  catalog/cache-key regressions and default tests pass. `flow` is next.

- 2026-09-27 M3 catalog extraction: an OCaml AST codemod moved the unchanged
  operation modules into four private files (shapes, topology, attributes,
  groups) plus common helpers. The public facade keeps all 154 tagged aliases
  in registry order. Before/after descriptors are exactly equal, including
  defaults, ranges, slot order and cook keys (canonical snapshot digest
  `961e191a6b0c7b2ec966250a6ce03714`). Catalog annotations follow separately.

- 2026-09-27 M3 PPX metadata: primary and checked vec3 groups generate
  schema metadata; stable keys and geometry-slot names are checked at the
  declaration. Factory descriptors retain named slots with canonical
  `in0`/`in1` defaults. Located error checks and a compiled tagged module
  alias fixture pass, alongside the catalog and editable graph regressions.

- 2026-09-27 M3 foundation: dependency-free Param fields and field views
  carry primary/vec3 metadata. The field constructor validates float group
  components, and a window-free check proves metadata preserves literal
  values, updates and both full/cook keys. `@check` and default `runtest`
  pass; the intended Param API manifest is promoted. PPX annotations and
  catalog extraction follow before value ports and drives.

- 2026-09-27 M2 complete: contextual guide strip, shared 380 ms hover
  tooltips, grouped key sheet, atomic user preference toggle/Hide and 1.5 s
  HUD. Router returns exact matched Command entries, preserving alias keys
  and labels; every caller is migrated. Guide context/scope, hover reset,
  modal shielding, preference preservation and HUD alias/expiry regressions
  pass. `@all`, default `runtest`, smoke, native editor/SOP parity and PXUI
  parity pass. Native previews verified tooltip, key sheet and HUD; modifier
  labels use the kit's supported ASCII spelling. Documentation and intended
  API manifests are updated. Final guide benchmark: 0.175 ms median held
  frame at 2,000 nodes, 635,543 bytes/frame; see `performance.md` for the
  before comparison. M3 starts next with schema metadata and catalog split.

- 2026-09-27 M2 interaction: walk, contextual Tab/append/ripple, qualified
  repeat across levels, cycle-safe letter hints, display, mute, delete,
  dissolve, find and selection framing; World `t/n/d`. Bypass suppresses
  scene objects and World layers without altering literals; a muted ACTIVE
  camera falls back to the viewport. Tab yields subsequent ordered events
  to the UI and Shift-Tab retains traversal. Fixed-layout, routing, shared
  input, World and camera regressions, `@check` and default `runtest` pass.
  Guide strip/tooltips, key sheet, preferences and HUD remain for M2.

- 2026-09-27 M2 foundation: Command guide contexts, immutable bypass
  metadata shared by cooking/copy/presets, selected-chain dissolve and
  primary-slot insertion for multi-input nodes. Focused regressions,
  `@check` and default `runtest` pass; M2 interaction and guide UI remain
  in progress.

- 2026-09-27 M0: `flow.md`, this file, the prototype under
  `specification/flow/prototype/`, and pointers in `AGENTS.md` files,
  `pxui.md`, `procedural.md`, `api.md`, `scene.md`, `backend.md`,
  `performance.md` and the editor skills.

- 2026-09-27 M1: left-to-right snapped canvas, polyline wires and bends,
  point/chip/card/full, bloom, shared literal fields, knife, detail keys,
  incremental saved layout and v3-only stable-id presets. Removed curves,
  old preset readers and identity remapping. Shared history seals pointer
  gestures after all host reducers, preserving detail bursts.
  `@all`, default `runtest`, `@smoke` and diff checks pass; native editor,
  SOP parity and PXUI parity pass. The wider native target's GPU-film
  texture-count assertion fails at `test_gpu_film.ml:64` on both the
  unchanged `af55fffc` baseline and this change. Matched benchmark numbers
  and release/undo limits are in `performance.md`.

### W6 viewport provenance (2026-09-30, done)

Landed: clicking the view selects the node and iteration that made the shape
under the pointer, and the selection highlights it. `Mesh_merge` and
`Sop.merge` take `?source_base` and keep an input's existing tag, so
`__flow_src` is a workspace-wide tag (a running count over merge inputs) that
survives merges of merges; `Lower.provenance` maps tag to `{merge; input;
source; site; iter}`. (A triangle-to-primitive map,
`Rays_mesh.to_mesh_with_primitives`, was added here and deleted in W12: the pick's hit already
names its primitive, so only an ID-buffer upgrade would need it.) `Rays_editor.Pick` casts a CPU ray
over `Rdk.Surface_index` (built at the first click, kept per piece) and tints
by a per-corner `Cd`; `Viewport3.pick_ray`, the click recogniser in
`Environment`, `Core.pick` (select the site, probe every enclosing zone) and
`Core.lit_tags` / `Cook.update ?lit` (the highlight, prepared again from the
kept output, never recooked or lowered). Tests: `test_viewport_pick`,
`test_rdk`, `test_workspace_cook`. Native check: `sketches/flow_workspace`
with `FLOW_PICK`. Deviations, the bench numbers and the ceilings (BVH build at
the first click, instances, collapsed zones) are in
`specification/workspace/progress.md`.

### W7 editable text (2026-09-30, done)

Landed: `Pxui.Ui.text_area` (multiline, gutter, error lines, shared text-entry
path with `text_field`) and the workspace text pane, `Space l` from list: tabs
Selection (top-level ancestor and upstream closure of the selected binding,
marked; the binding editable), Graph (the active graph, selection marked) and
Document (the whole workspace as a draft). Check & apply is atomic and one
"Edit text" history entry; an invalid draft stays in the pane with its error
line marked while every other pane shows the last applied document; Discard
reverts. The read-only text pane and the flat network's text view are deleted:
only a workspace graph object has a text projection. Tests: `test_ui`,
`test_text_pane`. Deviations and gaps are in `specification/workspace/progress.md`.

### W8 loops over geometry (2026-09-30, done)

Landed: `(sop/point_list g :key "id")` and `(sop/piece_list g :key "id")` are
workspace operators (typed `list vec3` / `list geometry`, next to `sop/curve`),
and `(for [p (sop/point_list g)] body)` (one clause, `for` only) is a **zone
node**. `Flow.Eval` evaluates the body once, as a template, with the element
unknown: a point is a residual read from `Eval.force ?elems` (bound by
`Eval.element_key zone`), a piece is a plan node `zone/element`; the template's
nodes (ids `lo` to `hi - 1`) and the plan node `zone/points` / `zone/pieces`
(a `Geo`, the merged elements) carry `input`, `key`, `body`, `lo`, `hi` and
`element`. A body whose structure reads the element is `E_ZONE`, a `count` or
other list use of the result `E_TYPE` (only `sop/merge` takes it), a body that
reads `t` is `E_ZONE_LIVE` at lowering. `Procedural.Zone` is the cook step: a
node with an optional `expand` (`Node.Private.make ?expand`) that
`Session` calls after cooking the inputs: it derives the elements (points, or
pieces from `Rdk.Deletion.primitive_partitions`, ordered by the int/float
`key` attribute when present, else by index, at most 4,096), asks the
zone for each element's sub-graph, cooks them through the same session and
hands their outputs to the node's merge (`__flow_src` = `base + element
index`; `Lower` reserves 4,096 tags per zone). `Lower` keeps template nodes out
of the network; each element's copy is built by `instantiate` (element-invariant
nodes once per cook of the zone, the rest per element, the element's arguments
forced with `?elems`), so the network holds one `zone` node. `Lower.origin`,
`Lower.tags` and `Lower.zone_count` extend provenance to zones; `Core.pick` and
`Core.lit_tags` use them, `Probe.make ?dynamic` reports the last cook's element
count in the selector and every element reads the template's record.
Deviations from the plan: cache identity is `(template node id, forced
arguments, input data ids)` instead of new ids per `(path, element key)`: an
unchanged element has the same key, so it is a hit, and two equal elements
share a result; the zone's own key changes with any change of the collection,
so it re-expands and merges (misses: the zone, its merge and the changed
element). A piece element is a `zone_element` node keyed by a content digest of
the piece (its data id is fresh per cook). Gaps: a body may read the element
only through arguments; values inside the loop read the template record (an
element-dependent value shows `?`); `t` inside the body; a merge inside the
body keeps its own (template) tags, so a pick resolves to the template
iteration; the zone title does not say "by index"; sequential over elements
(`ponytail:`). Session capacity matters: two cache entries per element and a
default of 512 entries mean the editor default only caches a few hundred
elements; pass `?max_entries`. Tests: `lib/flow/test_workspace_eval.ml`, `test/test_workspace_zone.ml` (Garden-like
scatter then for over points, 1 vs 3 domains byte-identical, deterministic,
one zone node and no template in the network, provenance, hits after moving
one point, pieces, keys, `E_ZONE_LIVE`), `test/test_probe.ml`. Bench
(`test_main.exe bench_workspace_zone` from `_build/default/test`): see
`specification/workspace/progress.md`. Native: `FLOW_CASE=garden` in
`sketches/flow_workspace` (40 dots over a scattered bed; selecting the zone
lights every element, the rest dims).

### W9 macros UI, notes, bypass (2026-09-30, done)

Landed: **Macro lens.** `Projection.node.lens` (the call, then each `Flow.Macro.expand_once`
step printed by `Flow.Lisp`, at most 12) and `Projection.layout ?lens` (an open panel adds
`lens_height` and widens the card to `lens_width`). `Scope` draws a toggle at the right of a macro
call's title; the open panel has step buttons (`call`, 1, 2, ...), the printed step (at most 16
lines), the reading, and "Replace call with expansion" = `Syntax_edit (Inline_macro ...)`. The open
state and step are `Scope` view state (`macro_step`), not history; a change lays the graph out
again for the next frame. **Make macro.** `m` (the old `m` alias of bypass is gone; `b` remains)
and a context-menu entry emit `Scope.Macro_requested`; `Flow_edit.macro_draft` lists the template's
literals and the outside names that always become holes, `Pxui_shell.Prompt.macro` (a modal: a
toggle and a hole name per literal, the first 12, the macro name, Create) is the dialog (state in
`Core`'s `Making_macro` prompt; the first two literals start ticked, as in the study), and
`Flow_edit.macro_op` turns the answer into one `Make_macro`, reduced like any other gesture (a bad
name or a capture is `edit_error` and the prompt closes). **Notes.** The note row on the card
already existed; the workspace inspector has a `note` field whose edits are `Set_note`, merged into
one history entry per node (`Flow_edit.gesture`); a note of several lines is edited in the text
pane. The inspector also lists a macro call's "Replace call with expansion". **Bypass.** The `M`
mark is replaced by a `B` flag on the title of a call whose first input fits its result
(`Projection.bypassable`; the checker refuses the rest), filled while bypassed; the click is
`Toggle_bypass`, the request of the key. Decision: bypass stays an Eval-level pass-through
(`^:bypass` is metadata on the authored form and the evaluator makes no plan node for it), so a
lowered network never holds a bypassed node and `Edit.set_bypass` (the flat pane's flag on a compiled
node) has nothing to flag; the pane and the inspector only edit the source. Tests:
`test_pxui_graph` (lens toggle, step, panel size, replace request, bypass flag, `m`),
`lib/pxui_shell/test_shell.ml` (dialog state), `test_workspace_edit` (`macro_draft`, `macro_op`, note
gesture), `test_text_pane` (the editor driven: flag, note, make-macro Create; the sketch's 1400x800
window and pointer conventions). Native: `FLOW_CASE=rosette` with `FLOW_W9` / `FLOW_W9KEY` /
`FLOW_W9TEXT` and `FLOW_SCROLL=9`. Gaps: making a macro from a macro call whose loop variable is a
binder is refused (`E_MACRO_CAPTURE`, shown in the status); the lens has no "Template" button (the
study's `macroDialog` of an existing macro); the dialog cannot be submitted with Enter; step
buttons past 13 overflow the panel; the inspector has no bypass toggle.

### W10 part A: scene, world and settings contexts (2026-09-30, done)

The three contexts check and lower. Their spellings are generated from the object, layer and
settings schemas (`Editor_document.Contexts`), so a new schema field is a new keyword. Scene
calls become nodes of the scene network (geometry objects own the network lowered from the sop
graph they `ref`), the World a node with its layer stack as a network, settings the document
`Settings.t` and `Contexts.window` (title, size, fps, seed) for the host. Presets and `Flow_edit`
work unchanged (source text). Deviations are in `specification/workspace/progress.md` (W10 part A notes).

### W10 part B: the composable shell (2026-09-30, done)

The editor graph is the shell. `Pxui_shell.Layout`'s fixed three columns became a tree of panels
(`Editor_core.Panels`: leaf, split, tile, float; panels `View key`, `Graph`, `List`, `Lisp`, `Inspector`,
`Outline`, `Timeline`) whose default reproduces the columns; `Contexts` lowers `(graph editor ...)` into
`Document.shell`, so the tree, its history and its text are the document's. Focus, pane roots and command
scopes are keyed by panel; viewports over `(ref scene :seed n)` draw one scene instance per override (Variations
renders four); split, close, retype and resize are `Flow_edit` ops emitted by the header menu and the
splitters (one history entry each); "Restore layout" (`Space z`) is host state outside the tree; a
`(ui/graph "name")` names the pane's graph and `Space o` is removed. Deviations, the geometry API and
the gaps are in `specification/workspace/progress.md` (W10 part B notes); `lib/rays_editor/AGENTS.md`
has the rules (its "keep the three-column workspace" rule is replaced by "Workspace shell (W10)").

### W11 `.rays` sketches (2026-09-30, done)

Part A: `tools/lisp` (`rays-lisp check | ml | dune | fmt`), `sketches/dune` with the checked-in
`dune.rays.inc` (promote after adding a sketch), `Rays_editor.Workspace.load | run | main`,
`new_example --lisp`, and the twelve `sketches/ws_*` cases running under `smoke-all`.

Part B: Save and live reload. Command-S rewrites the sketch's `.rays` (comments kept, atomic) while the
file is still the text the document came from, else saves a preset; the frame loop polls the file twice a
second and reloads a changed file as one history entry "Reload sketch.rays" (layout, settings, probes and
selection kept by path), or keeps the last good document and shows the diagnostics. The viewport starts at
the scene's camera. Deviations, notes and the gaps are in `specification/workspace/progress.md` (W11 part A
and part B notes).

### W12 migration and removal (2026-09-30, done)

Migrated: `sketches/flow_terrain` is `sketch.rays` (the only sketch or example that was a `[%flow]`
graph plus an `Editor3.run` call; `value/time :speed 0.4` became the live `t`), its `main.ml`, `dune`
and smoke rule are gone and `sketches/dune.rays.inc` was promoted. Decision on `[%flow]`: after that
port nothing used it but its own two tests, and making a single `graph` payload sugar for
`(workspace name graph)` would have kept the PPX, `Flow.Check.check`, `Build`, `Program`, `Print` and
`?program` alive for no caller (the sugar would also have had to re-emit checked terms for the workspace
checker, or lose its compile-time diagnostics). The leaner option was taken: `[%flow]` is deleted, an
OCaml host with its own code passes a workspace text through `Workspace_doc.of_text` /
`Workspace.load`. Also lost: file-local `user/<node_key>` nodes in `[%flow]` (no workspace spelling
uses them) and the `-flow-manifest` PPX flag.

Deleted (net of the commit range, about 2,400 lines): the `[%flow]` rewriter (about 300 lines of
`ppx_rays.ml`) and its two tests; `Flow.Check.check` and its term/graph/binding/definition/program
types (about 530 lines; `Check` keeps the catalog types, `catalog_of_manifest`, `resolve_kind`,
`validate_parameter`, `suggestion`, `short` for the workspace checker); `Flow_sop.Build`, `Program`,
`Print` (about 650 lines); `?program` of `Editor3/2` and the program branch of `Core.initial_doc`; the
v3 round-trip tests (`test_network` print/check blocks, `test_sop_catalog` build/print samples, the
three `?program` editor fixtures and the Time-source value-node UI test of `test_editor_document`, which
needed a `Program` to start from); `Rays_mesh.to_mesh_with_primitives` and its test (unused by the
pick); ten dead exports found by `prune-dead-code` (`Network_layout.slot_index`, `Store.load/save`,
`Document.positions`, `Curve.decode/key`, `Probe.describe/series`, `Eval.max_*`, several `pxui_graph`
ones). Unknown-operator errors now suggest (`sop/bx`: "Did you mean box?").

Kept at W12 and deleted by Gap A (below): the flat `Pxui_graph` pane, `Drive.Expr`/`Flow.Expr`, `Flow.Sexp`, JSON `Store.Settings`/`Store.Viewport`.

Also fixed: the `test_workspace_shell` "status names the loop" race (the editor recooks every frame
for a live workspace and reported `cook N ms · skipping frames` instead of the notice; `settle` waited
that state out, and Gap B removed the wait: the tests use `Editor3/2.create ~await:true`). The remaining audit, per milestone, is the table in
`specification/workspace/progress.md`.

### W13 audit gaps (2026-09-30, done)

The W12 audit's gaps that the plan's text required were closed (details, tests and numbers in
`specification/workspace/progress.md` "W13"): the graph pane makes every W3 gesture (rename, input default,
list item move, frames as `Frames_set` layout edits, marquee selection); `Space o v/h/x/g/l/t/i/u/m/w` split,
close and retype the focused panel; a binding apply's checker error carries a line and error marks clear on
typing; instanced pieces are picked per instance; residuals compile to closures (Wave 7.0 to 1.8 ms p50,
bit-identical); a `.rays` that differs from the built text reloads on the first poll and `(layout ...)` /
`(settings ...)` forms in it are honoured. `Space o` had been the removed graph-cycling key.

### Gap A (2026-09-30, done)
Every document is a workspace. The four `?graph` sketches are workspace text; `?graph`, the flat document
constructors, `Network_view`, the flat `Pxui_graph` pane (and its BVH path), `Flow.{Expr,Value_kind,Graph,Sexp}`,
`Flow_sop.{Drive,Compound_node,Group,Compile,Exposure}` and `Editor_core.Network_layout` are deleted
(about 4000 lines net). `Flow_sop.Network` is geometry plus live drives. `Pxui_graph` is `Scope` plus `Node_menu`.
`Store.Settings` and `Store.Viewport` are s-expressions; `Preset.loaded.view` is a `Flow.Syntax.t`. Flow manifests no
longer list value kinds (promoted). Known limits: see the Gap A entry in `specification/workspace/progress.md`.

### Gap B (2026-09-30, done)
The text is the single truth of the scene and World: `Editor_document.Scene_sync` writes every derived-object edit
back as `Flow_edit` ops (`Doc.reconcile`), `Document.homes` and `Document.origin = Inline` say where things are
written, `:parent` and `:active` are keywords of the object kinds, and `Flow_edit` gained `Duplicate`, `Set_graph`,
`Remove_graph` and mixed positional/keyword arguments. Workspace gestures were restored (duplicate, view node, frame
drag, frame selection, list walk and selection, the "Value" add menu, expression and reset rows, inspector rename,
Bypass, input default and list movers, editable in-place and looped panels); `Editor_core.Guide_context` lost its
five dead contexts; each viewport has its own orbit and picks in its own scene instance; `Ui.text_area` gained Tab,
wrapping and Command-Enter and the Graph text tab edits; a zone whose body reads `t` is live (`Zone.node ~live`,
`E_ZONE_LIVE` removed), footers force element-dependent values per element and count nodes off the display
(`Async_cook.submit_some`). `Editor3/2.create ?await` replaces the clock in tests. Details, tests and what remains:
`specification/workspace/progress.md`.

## Gap C: ownership and loop copies (2026-09-30)

A scene graph is authoritative for cameras and lights, and a world graph for the World (`(world/none)` says none): the
host seeds only a workspace with no such graph, and deleting a host object writes the graph, so Save and reload keep
it. The copies of a loop are one template: editing one edits the template, deleting one adds its iteration to a
`:skip` list (register L16), exact at any nesting depth. Details, tests and native checks: `workspace/progress.md` "Gap C".
