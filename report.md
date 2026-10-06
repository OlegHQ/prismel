# Rays audit: architecture, editor bugs, Lisp bugs, and a cleanup plan

Date: 2026-10-06. Tree: `dev` at `d88c46b`, clean. Nothing in the repo was changed to produce this
file. Five read-only audits ran in parallel (Lisp, editor shell, graph pane and UI engine,
architecture, dead code); their repro inputs and scratch probes are outside the repo.

## 0. Summary

- **15 crash paths reachable from user input**, 11 reproduced. The worst: a valid-looking workspace
  that passes `rays-lisp check` and cannot open (L1), typing `(max` in the Lisp pane (E1), undo with
  two graph panels open (E2), and a `0x01` byte in a comment (L3).
- **14 silent data-loss or silent-rewrite bugs.** The widest: every float writer can emit exponent
  notation (`1e-14`) that the reader cannot read (X1, seven writers, one reader); print drops
  comments in four positions and print runs on *every graph gesture*, not only on save (L4); an
  external file change replaces unsaved work (E8).
- **The structural cause of most editor bugs is the one `PLAN.md` already names**: a second
  representation disagreeing with the workspace text. It is still there in five places (§2.2).
- **Roughly 6–7k lines can be deleted mechanically** and 14–19k with design decisions (§5), out of
  about 309k tracked OCaml lines. No whole library is dead. The waste is duplicated helpers,
  test-only features, and each SOP being declared three to six times.
- **Docs have drifted**: `flow.md` is called normative but describes compounds (deleted), a
  `(display …)` layout entry (replaced), diagnostics that do not exist, and ten module names that
  are gone.

The plan in §6 is ordered so that each step is a fix at one shared function plus one test, deletion
comes before refactoring, and nothing is a rewrite.

### Evidence tags

| Tag | Meaning |
|---|---|
| **RUN** | Reproduced end to end (CLI tool, scripted editor frames, or a probe against the built libraries) |
| **RUN-unit** | Reproduced against the library in isolation, not through the whole editor |
| **READ** | Inferred from reading the code path; not executed |

I re-read the source for six headline items myself (X1, L1, E1, G1, E4, `Editor2` usage, the empty
gate exception list); they match. Everything else is as reported by the audits. Line-removal
numbers are estimates unless marked measured.

---

## 1. Cross-cutting bugs (one root cause, many symptoms)

Fix these first: each closes several findings listed later.

### X1. Float writers emit exponents the reader rejects — data loss, RUN

- Reader: `Syntax.number` (`lib/flow/syntax.ml:14-24`) accepts `-?digits(.digits)?` only. Its
  duplicate is `lisp_text.ml:20`.
- Writers that produce `1e-14`, `2e+06`, `6.1e-17`: `Layout_by_path.number`
  (`layout_by_path.ml:51`), `Workspace_doc.number` (`workspace_doc.ml:21`), `Store.number`
  (`store.ml:33`), `Scene_sync.number` (`scene_sync.ml:24`, `%.17g`), `scope_pane.ml:1942`,
  `core.ml:933`, `core.ml:3716`, `flow_edit.ml:1123`.
- Symptoms: `rays-lisp fmt` output fails `fmt` (`E_LAYOUT: expected a number`); a gizmo writing
  `3.3e-7` is refused as "`3` is not bound"; a sketch setting of `3.3e-7` saves and will not
  reload; a camera vector with a tiny component silently resets the camera.
- Same functions, second bug: three of the `number` copies end in `Option.get` on a `find_map`
  that is `None` for NaN. A NaN camera (SOP emits a NaN point, `F` frames it) then raises in
  autosave, in `crash_dump`, and in `close`, so the crash folder has no `document.rays` and the
  cook worker is never joined (READ for the path, RUN-unit for the raise).
- Third bug: the `%.6g` / `%.4g` sites truncate values on a scrub (1234567.89 rounds).
- **Fix:** one total float printer in `Flow.Lisp` (shortest round-trip, never exponent, non-finite
  is a typed error at the caller), used by all eight sites; accept exponents in `Syntax.number`
  anyway so hand-written files load. Reject non-finite bounds at `environment.ml:791-796`.

### X2. Print-then-parse runs on every gesture, so printer bugs are editing bugs

`Flow_edit.check` (`flow_edit.ml:1498`) prints and re-parses the whole source per graph gesture.
Consequences: L3, L4 and X1 fire on any card click that edits, not only Command-S; and the cost
shows in the 2,001-node profile (`PROMPT.md` already notes it). Not a bug by itself; it is why the
printer has to be exact. See step 2.6 for the fixed-point test that guards it.

### X3. Positional argument after a keyword — wrong result, RUN

- Checker (`workspace.ml:1162-1174`) counts positionals from 0 regardless of keywords and uses
  `Hashtbl.replace`: `(sop/boolean :left (sop/box) (sop/torus))` passes with `left` filled twice
  and `right = nil`.
- Projection (`projection.ml:81-87`, `split_args`) stops at the first keyword:
  `(sop/transform :translate [1 2 3] a)` checks, but the card shows an unwired input, and dropping
  a wire on it silently replaces the invisible `a`.
- `Flow_edit.positional` (`:155`) accepts any order; `Move_item` then indexes a keyword and refuses
  with `E_SKIP`.
- `flow.md` §11.6 specifies `E_POSITIONAL_AFTER_KEYWORD`. The code does not have it. None of the 18
  checked-in sketches or the spec cases use that order.
- **Fix:** implement the specified error in `Workspace.args_of`. Three readers then agree by
  construction and no reader needs to change. Delete `Projection.split_args` in favour of
  `Flow_edit.positional` afterwards (7 lines).

### X4. Layout keys outlive what they name — data loss and stale state

- `Remove_graph` leaves `layout.editor` dangling; the saved file then fails to load with
  `E_LAYOUT: Unknown editor layout b` (RUN-unit, `flow_edit.ml:1542-1559`,
  `workspace_doc.ml:112-116`).
- Layout entries of removed graphs persist, and a new graph reusing the name inherits them
  (RUN-unit).
- `remap` returns the key unchanged for `Unfold`, `Fold_into` (RUN), and for a `Connect` that binds
  a nested node, `Disconnect Pos i`, `Move_item` (READ): position, level and pins go stale.
- A rename in an external editor orphans entries forever; nothing prunes on load (RUN).
- **Fix:** one prune in `Workspace_doc.of_text` and `Workspace_doc.edit`: drop every layout entry
  whose path is not in the checked workspace, and clear `layout.editor` if it names no editor
  graph. That replaces per-op `remap` completeness with one filter; keep `remap` only for renames
  that should carry a position.

### X5. External reload versus unsaved work — data loss

- A dirty document is replaced within 0.5 s when the file changes on disk; the edit survives only
  as an undo step, and Command-S then saves the file's version (RUN, `environment.ml:637-640`,
  `core.ml:4987-5003`).
- A refused reload overwrites an unapplied Document-tab draft with the broken text (READ,
  `core.ml:5003`).
- Reload is not suspended during a carry (READ).
- **Fix:** in the reload path, when `doc != saved_doc` or a draft exists, keep it and show a notice
  with the choice; skip polling while carrying.

### X6. The edit pipeline has no last-resort guard

`apply_checked` (`flow_edit.ml:1510`) catches only `Fail`. `Workspace_doc.edit` and
`Doc.syntax_edit_result` catch nothing. Any `List.nth`, `Option.get` or `Failure` inside a rewrite
is a dead editor (G1 is one instance). **Fix:** one catch-all around `rewrite` in `apply_checked`
that returns an `E_EDIT` diagnostic. This is the single guard that turns an unknown number of
future crash bugs into refused edits. It does not replace fixing G1.

---

## 2. Architecture

### 2.1 The real dependency graph

Parsed from all 43 `lib/**/dune` files (46 library stanzas).

| Layer | Libraries |
|---|---|
| 0 | `native_layer_token`, `lru`, `param`, `scene_command`, `rays_math` |
| 1 | `sdl3`, `metal`, `ogpu_core`, `flow`, `rdk_core → exact → spatial → attrib → gen/curve → mesh → boolean` |
| 2 | `sdl3_image/ttf/mixer`, `ogpu` (virtual), `ogpu_metal_native`, `ogpu_metal`, `ogpu_mock`, `rdk` |
| 3 | `scene_execution`, `runtime_input`, `runtime_resources`, `procedural` |
| 4 | `runtime`, `flow_sop` |
| 5 | `rays_execution` |
| 6 | `rays` |
| 7 | `pxui`, `editor_core`, `rdk_rays`, `sop_catalog`, `rays_pathtracer` |
| 8 | `pxui_shell`, `editor_document`, `sketch_support` |
| 9 | `pxui_graph` |
| 10 | `rays_editor` |

Where this differs from `AGENTS.md`:

- The pipeline is not `scene_command → scene_execution`. `scene_execution` does not depend on
  `scene_command`; `rays_execution` joins them.
- `rays` uses `Scene_execution.` and `Ogpu.` without listing them; `editor_document` uses `Rdk` and
  `Param` unlisted; `rays_editor` uses `Rdk`, `Rdk_rays`, `Param`. Implicit transitive deps are on,
  so the gate's direct-edge checks cannot see any of it.
- "Known violations are listed there": `reach_exceptions = []`. The sentence is stale.
- `Store` is described as JSON user preferences. It writes s-expressions through `Flow.Lisp`; there
  is no JSON in `lib/editor_core`. That is the only reason `editor_core` depends on `flow`.
- The table omits `lru`, `native_layer_token`, `rays_math`, `rdk_rays` and the eight `rdk_*`
  sub-libraries.

### 2.2 Ranked problems

**A1. `rays` mixes pure data with the native runtime, so "UI-free" layers link SDL3 and Metal.**
`sop_catalog` depends on `rays` for 124 uses of `Vec3`/`Vec2`/`Mat4`/`Color`/`Quat`, all of which
live in `rays_math`. `editor_document` needs only `World`, `Camera`, `Light`, `Mat4`, `Vec3`.
Result: `rays-lisp`, the build-time checker, is a 19.5 MB binary that links Metal, MetalFX and four
SDL3 libraries (`otool -L`, verified). *Target:* point `sop_catalog` at `rays_math` (mechanical);
then, only if the link cost matters, extract the ~3.6k runtime-free lines of `rays` into a core
library re-exported from `Rays`.

**A2. One authored truth, two write paths, five graph forms.** Forms: `Flow.Syntax.t` →
`Flow.Workspace.t` → `Flow_sop.Lower.t`/`Network.t` → `Procedural.Graph.t`, plus `Projection.scope`
and the derived `Document.scene`/`networks`/`homes`. Path A edits text (`Flow_edit.op`, 36
constructors). Path B mutates the derived `Edit_graph` and then `Scene_sync.reconcile` diffs it
back into ops (`scene_sync.ml`, 715 lines; `Edit_graph.` appears 67 times in `core.ml`). Path B is
where E10, E11, E12 and the whole-graph rewrite E9 live. `Edit_graph` also still exports a pre-text
editing API with no caller outside its library and tests (`subgraph`, `copy_nodes`, `paste`,
`dissolve_nodes`, `insert_on_connection`, `set_bypass`, `rebind_factory`, six `factory_*`).
*Target:* inspector and handle edits emit `Flow_edit.Set_arg` at `Document.homes` directly;
`reconcile` stays for adopt only; `Edit_graph` becomes build-only.

**A3. Each SOP is declared three to six times.** rdk op → `Procedural.Sop` function with a
hand-written cache key → `sop_catalog` PPX record → `Edit_graph.factory` →
`Flow_sop.Catalog.descriptor` → `Flow.Check.kind` → `flow_manifest.sexp` → `Node_menu.entry`.
`sop.ml` is 7,642 lines with 191 `*_key` helpers (1,166 lines), 909 `"name=" ^` key lines and 288
`invalid_arg` validations that repeat ranges the catalog record already declares. 132 of 165 `Sop`
functions are called only by `sop_catalog`. `lib/sop_catalog/AGENTS.md` already promises a
"schema-derived cache key". *Target:* the PPX record is the one declaration and emits the key,
the validation and the forwarding call.

**A4. Monoliths.** `core.ml` 5,041 lines, with `update_frame` at 1,645 lines containing a 730-line
`build` closure. `ui.ml` 4,308. `scope_pane.ml` 2,881. `pxui_shell.ml` 2,226 (ten modules in one
file). `workspace.ml` 1,463. The reducer block `core.ml:4158-4551` is where E3, E15 and E16 live
and it cannot be tested without building a UI frame.

**A5. Pass-through tower with singletons.** `set_cursor`, `set_relative_mouse`,
`set_window_background` are each defined in `sdl3`, `runtime`, `rays_execution` and `sketch`.
`Sketch` reaches the window through four callback refs (`sketch.ml:5,6,14,20`);
`rays_execution.ml:203` holds `active_window`. Errors are re-wrapped `Ogpu.Error.t` →
`Rays_execution.error` → `string`. There are at least eleven `{operation; kind; message}` error
types.

**A6. Residue of completed migrations.**

- `Editor2` has zero users in `examples/` and `sketches/` (verified); only
  `test/test_rays_editor.ml` uses it. It costs `viewport2.ml`, 122 `.mli` lines, the `VIEWPORT`
  functor (64 `V.` sites), about 20 `scene_level` branches in `core.ml`, `Easy_camera2` (357
  lines), `Camera2_control`, `Store.Viewport.encode2` — and crash E3.
- Flow keeps the pre-workspace types: `Port_type.t` beside `Ty.t`, `Check.term` beside
  `Workspace.term`, `Flow.Context.t` beside `Workspace.context` (the `.mli` comment says "until
  W10", which is done). `Workspace.to_check` builds dummy `Check.term`s only to call
  `validate_parameter`.
- `Layout_by_path.wireless` and `bends` round-trip a deleted feature with no reader.
- Legacy readers survive (`legacy_render` at `contexts.ml:104`, `adopt_world_legacy` at
  `scene_sync.ml:437`) although `lib/editor_document/AGENTS.md` says "no older reader".
- Legacy `defmacro` without a backquote (`macro.ml:52-61,106-114`) is a second, non-hygienic
  expansion path.
- `layout.display` (PLAN §3) is half removed: `v` rewrites the tail, but the key is still read at
  `core.ml:734,1403,1613` and written for loop nodes at `:4479`.
- The `[%flow]` PPX (M7) does not exist; `ppx_rays` derives only `sop_params` and `sop_node`.

**A7. Error handling.** The typed-result rule holds in the GPU stack (zero `invalid_arg` in
`ogpu_core`, `ogpu_metal`, `runtime`, `rays_execution`, `sdl3*`). It does not hold in `rays` (20
`failwith`, 88 `invalid_arg`, 45 of 61 result signatures carry `string`), `procedural` (310
`invalid_arg`, caught as exceptions at `edit_graph.ml:604,626` and `carry.ml:84`), or `rdk` (259
`assert false`, 236 `Result.get_ok`/`Option.get`). `rays_editor` library code calls `exit 1`
(`rays_editor.ml:101,152`) and `failwith` (`environment.ml:10`, `core.ml:569`, `lower.ml:286`).

**A8. Global state.** One sketch and one window per process is baked in:
`rays_execution.ml:203,207,214,818`; `rays/sketch.ml:4-20`, `time.ml:3-7`, `input_state.ml:7-10`,
`audio.ml:2`, `font.ml:16`, `canvas_runtime.ml:2-3`. Id counters are process-history dependent
(`procedural/node.ml:41`, `display_list.ml:16`, `data_id.ml:1`, `handle.ml:6-7`); harmless unless
an id reaches a dump or a key. `flow/eval.ml:448` (`compile_residuals`) is a test-only switch in
production code. One real race: **`Session.set_volatile` mutates a `Hashtbl` on the main domain
while the worker cooks** (`session.ml:160-163`, called unlocked from `async_cook.ml:155` on every
`Core.install`; READ) — listed as E5.

**A9. The gate is a blacklist.** The "depends only on" claims for `pxui_shell`, `ogpu_core`,
`ogpu`, `param` and Metal native are not whitelisted. `rays_pathtracer`, `rdk_rays`,
`scene_execution_fixtures` have no rule. The Metal token scan skips `tools/` and `test/`.
`lib/metal` is preprocessed by `tools/codemod/result_bind_ppx.exe`: a foundational library depends
on `tools/`.

**A10. Tests and tools.** `test/test_main.exe` links 34 modules against every library;
`lib/rdk/test_main` links 126 files and `rays`. `flow_sop`, `editor_document`, `pxui_graph`,
`rays_editor`, `sop_catalog`, `sketch_support` have no in-library tests. There is no shared test
helper (`let fail` ×220, `let check` ×178, `let get_ok` ×78). `api_stable.json` stores only
SHA-256s, so a doc-comment edit forces `dune promote` and the diff cannot be reviewed.

---

## 3. Editor bugs

### 3.1 Editor shell (`rays_editor`, `editor_core`, `editor_document`, `pxui_shell`)

**Crashes**

| ID | What | Where | Evidence |
|---|---|---|---|
| E1 | Typing `(max` or `(+` in the Lisp pane: `List.nth_opt _ (-1)` raises `Invalid_argument` | `lisp_text.ml:484-486` | RUN |
| E2 | Two `ui/graph` panels; panel B enters an object; Command-Z from panel A removes it; next frame `Option.get` | `core.ml:532` via `:3265`; stale `graph_pane.at` never re-resolved | RUN |
| E3 | Editor2: delete the only geometry object, `Result.get_ok` on `resolve_level` | `core.ml:4555-4557` | RUN |
| E4 | NaN camera crashes autosave, `crash_dump` and `close` | `store.ml:33-35` (see X1) | RUN-unit / READ |
| E5 | `Session.set_volatile` mutates a `Hashtbl` across domains | `procedural/session.ml:160-163` | READ |
| E6 | Paste of two bare forms with the same head, or of `bed` + `bed_2` into a graph with `bed`: partial paste, self-reference `E_GRAPH_CYCLE` | `core.ml:2857-2865` | RUN (clipboard shim) |

Fixes: E1 skip the lookup when `prior = []`. E2 resolve `pane.at` in `as_pane` (`core.ml:437-445`)
with `Result.value ~default:Scene` and clear `picked`. E3 on `Error` keep `doc`/`history` and set
`edit_error` as `install` already does (or delete Editor2, §5). E5 carry the predicate in the cook
request. E6 pair names positionally, substitute simultaneously, emit one `Syntax_batch`.

**Data loss**

| ID | What | Where | Evidence |
|---|---|---|---|
| E7 | Orbiting after a restart overwrites the unsaved-work recovery file with the pristine document | `environment.ml:663-672` | READ |
| E8 | External file change replaces a dirty document (X5) | `environment.ml:637-640` | RUN |
| E9 | Deleting or reordering one World layer rewrites the whole world graph: inputs, expressions and comments lost, bindings renamed | `scene_sync.ml:499-506`, writer `:419-434` | RUN-unit |
| E10 | Command-S does nothing while the Lisp pane has the caret; the draft is in neither file nor autosave | `editor_core.ml:179` | RUN |
| E11 | Comments after the `(workspace …)` form are dropped on save | `workspace_doc.ml:102-107` | RUN-unit |

Fixes: E7 do not overwrite an existing recovery file while `doc` is the opened document. E9 use
the surgical `Delete_nodes`/`Connect` branch (`:516-533`) for member Worlds. E10 with text focus,
still route Meta/Ctrl chords the text widget does not own; `Save_source` with a draft applies then
saves, or refuses with a notice.

**Undo and history**

| ID | What | Where | Evidence |
|---|---|---|---|
| E12 | Viewport navigation is an undoable edit by default (`follow_viewport=true`): every orbit leaves "Move camera", can fill the 128-entry history, and the first Command-Z after a drag is swallowed | `core.ml:4796-4797`, `viewport3.ml:320` | RUN |
| E13 | Painting the visibility column over N rows makes N undo steps | `pxui_shell.ml:1745-1753`, `core.ml:4522-4528` | READ |
| E14 | A splitter drag interrupted by focus loss leaves `shell.live`; a later click on any gutter commits the stale size | `pxui_shell.ml:819-829`, `core.ml:2763-2769` | RUN-unit |
| E15 | A carry preview can be committed to history (`entered_camera` while carrying; `edit_node` lacks the guard its siblings have) | `core.ml:4307-4318`, `:4888` | READ |
| E16 | Multi-change frames are not atomic: one failure leaves earlier changes applied, a later success clears `edit_error` | `core.ml:4335-4425` | RUN |

Fixes: E12 record follow-viewport writes with `Repair`, make `History.amend` keep `future`, skip
the write on a frame that ran undo/redo. E13 give all-`Flag` frames a gesture key. E14 drop `live`
on a frame with no `Resize`/`Settled` (as `window_live` at `core.ml:4032-4036`). E16 fold a frame's
changes into one batch.

Checked and sound (RUN): inspector slider, card field, viewport handle, scene-field scrub, tile
move, splitter and list flags each make exactly one undo entry; Escape, focus loss and undo
mid-drag leave history consistent; windows of 0×0, 1×1, 40×12, 300×30, 100×900 do not crash.

**Input and routing**

| ID | What | Where | Evidence |
|---|---|---|---|
| E17 | `Space ?` opens the command palette, not the key sheet: the pending-leader branch does not map Shift+`/` to `?`. `Leader "?"` and the `KeyChar '+'` chords are unreachable on a real keyboard | `editor_core.ml:201-203` | RUN |
| E18 | The key sheet lists about eight commands: it filters by hard-coded id prefixes that no longer match (`scope.*`, `panel.*`, `view.*`) | `pxui_shell.ml:989-995` | READ |
| E19 | After closing the focused panel, panel keys are dead until a click | `core.ml:2644-2659`, `:4020-4024` | RUN |
| E20 | An open name field or letter hints lock the keyboard when the pane switches to list/text; a pan in progress leaves relative-mouse on | `core.ml:3617`, `:3148`; `scope_pane.ml:1999` unreachable | READ |
| E21 | Relative-mouse grab and fly mode stranded by early returns | `viewport3.ml:256`, `environment.ml:789` | READ |
| E22 | Parinfer and the pane lexer treat strings as single-line; a multi-line string gets brackets added or removed inside it | `lisp_text.ml:42-47`, `:661-671` | RUN-unit |

Smaller (RUN-unit unless noted): a floating window pushed past the right edge stops following the
pointer (`pxui_shell.ml:567`); a click on a sticky ancestor row selects the row hidden under it
(`:1644-1646`); a plain click on a vector cell writes a position-derived value and an undo step
(`:1959-1964`); a viewport's header menu marks "Graph" as its kind (`:596-598`, READ).

**Document layer** (all in `scene_sync.ml`, all on write path B of A2)

- Host-made objects cannot be edited after a re-lowering: networks matched by physical identity
  (`:358-362` vs `contexts.ml:1047-1050`) — RUN-unit.
- Renaming an object to an existing label silently reparents another object's children (`:254`) —
  RUN-unit.
- The first render-settings edit is refused when the scene already binds `root` (`:556`); the file
  has its own fresh-name helper instead of `Flow_edit.fresh_name` — RUN-unit.
- `F` inside a transformed object frames local-space bounds when framing completes asynchronously
  (`core.ml:4713-4729`) — READ.
- The focused path-traced viewport never stops at `max_spp` (`renderer.ml:207-239`) — READ.

**Rule violation still present:** the "no mutation inside `Ui.frame`" rule. `build` mutates
`row_sets`, `bar_action`, `view_pick`, `inspector_drops`, `viewport_drops`, `workspace_requests`,
`workspace_moves` (`core.ml:3263, 3293-3296, 3746`). Benign today.

### 3.2 Graph pane, `Flow_edit`, projection, `Pxui.Ui`

**Crashes**

| ID | What | Where | Evidence |
|---|---|---|---|
| G1 | `(ui/switch a b :active 5)` or `:active -1` (checker accepts both), then leader `[x` / `[n`: `Failure "nth"` | `flow_edit.ml:1405`, `:1351` | RUN |
| G2 | Double-click a word in any text widget, then double-click a numeric field and move one point: `String.sub` inside `Ui.frame` | `ui.ml:2915-2920` | RUN |
| G3 | Command-C / Command-X in an empty focused text area: `String.rindex_from_opt` at 0 of `""` | `ui.ml:3582` | RUN |
| G4 | Letter hints up while the document reloads: `Option.get (node_of …)` | `scope_pane.ml:941` | READ |

Fixes: G1 `List.nth_opt` + `fail` as `edit_layout` (`:775`) already does, and range-check
`:active` in the checker. G2 one `reset_edit` helper used by both editor starts (also fixes G6).
G3 use the existing `line_start`/`line_end` (`:2643-2652`). G4 clear `hinting`, `context`,
`highlighted` in `with_scope`.

**Silent rewrites**

| ID | What | Where | Evidence |
|---|---|---|---|
| G5 | "+ field" names the field `f<row count>`; `{:f2 5}` has two rows, so the click writes `{:f2 0}` | `scope_pane.ml:2274-2276`, `flow_edit.ml:1140` | RUN (edit) |
| G6 | Command-Z in a numeric editor replays another widget's undo stack: field B commits field A's old value | `ui.ml:2915-2920` | RUN |
| G7 | Fold into use drops the binding's note, against the `.mli` | `flow_edit.ml:876-892` | RUN |
| G8 | `Move_item` on `(scene/merge a b c :skip [0])` swaps raw args; `:skip` now names a different object | `flow_edit.ml:1130-1139` | RUN |
| G9 | Keyword-first call loses its inputs in the graph (X3) | `projection.ml:81-87` | RUN |

Fixes: G5 first unused `fN` in the pane and `Add_field` fails on an existing key. G7
`{ e with notes = p.notes @ e.notes }`. G8 index `positional args` and remap skip tuples, as
removal already does.

**Wrong behaviour**

| ID | What | Where | Evidence |
|---|---|---|---|
| G10 | After duplicating a loop, unused inner nodes of either copy cannot be deleted: the "still used" test counts binder names in sibling scopes | `flow_edit.ml:924-927` | RUN |
| G11 | Wires inside a loop body cannot be hovered or selected: their hit boxes are built before the zone tile that covers them | `scope_pane.ml:2055-2085` vs `:2103` | RUN |
| G12 | Click a wire, right-click a node, Delete: removes the wire. The right-click also changes selection without emitting `Selected` | `scope_pane.ml:2629-2634`, `:741-754` | RUN |
| G13 | A float parameter written `:radius 1` scrubs as an integer; 1.5 is unreachable | `scope_pane.ml:1936-1947` | RUN |
| G14 | Taking a wire off a rest input writes a `nil` item no pane gesture can remove | `scope_pane.ml:88-91`, `:2234` | RUN / READ |
| G15 | Three card rows are drawn and can never be used: `+ output` (always `E_RECORD`), `+ list` on `concat` (always `E_TYPE`); `scope_pane.ml:2277` contains `&& false` | `projection.ml:269`, `:248` | RUN |
| G16 | A pointer carry survives its release when a popup takes capture; a later click delivers a spurious `Dropped` | `ui.ml:2394-2396` | RUN |
| G17 | Clicking an unplaceable picker row kills the node menu's keyboard | `ui.ml:4057` | RUN |
| G18 | A `Fit` box whose children are all `~at`-positioned culls them | `ui.ml:1775-1779` | RUN |
| G19 | No elastic scroll in `Grow`/`Pct`/`Rel`-height scroll boxes, including the inspector body | `ui.ml:1844-1845` | RUN |
| G20 | A `###` label breaks `Ui.choice` (latent) | `ui.ml:4265` | RUN |
| G21 | Text-area number scrub is not on the editor's undo stack; `"12\n"` pasted into a numeric field is silently rejected | `ui.ml:3631-3643`, `:2771-2774` | READ |

These contradict the standing "OS-native text editing, right-click everywhere, every scrub one undo
step" requirement: G2, G3, G6, G12, G21, E10.

**Performance** (dev profile, this machine)

| Graph | In view | Per idle frame |
|---|---|---|
| 2,001 nodes, pane 1000×700 | 191 cards | 14.7 MB allocated, 4.7–7.6 ms |
| 2,001 nodes, pane 16×16 | 0 cards | 6.2 MB, 2.0 ms |
| 501 nodes, pane 16×16 | 0 cards | 0.96 MB, 0.4 ms |

This breaks "frame work must not scale with unchanged scene size".

- G22 Over half the off-screen cost is `scope_pane.ml:2070-2074`: every diagonal wire is chopped
  into 16-point segments *before* the viewport test. Clip first.
- G23 With cards in view the top site is `fitted` (`:1057-1064`): it remeasures the whole prefix
  per character. `Ui.ellipsis` and `inspector_fit` (`ui.ml:1022-1030`, `2229-2240`) are the same
  quadratic; eight readouts of a 4,000-character string cost 1.5 s per frame (RUN). One
  forward-pass helper fixes all three.
- G24 The UI key table never reclaims tombstones: two million churned keys grew it from 167k to
  4.3M words (`ui.ml:62-81`, RUN).
- G25 Quadratic gestures: `level_command` (`scope_pane.ml:830-835`; `Point_all` on 2,001 nodes
  takes 49 ms, RUN), `parents_removed` (`:668`), `upstream_of` (`:859`), `shift` via `List.mem`
  (`:2035`).
- G26 Caches without a capacity, against the repo rule: `Probe.forced/across/feet`
  (`probe.ml:23-26`), `Core.locals` (`core.ml:1106`, holds text drafts and base documents, never
  pruned).
- G27 Shell per-frame waste (READ, not measured): `Layout.geometry` is computed about eight times
  per frame in `update_frame`; the Outline is O(graphs² × form size) (`navigator.ml:128`);
  `Lisp_text.complete` runs twice per frame while the popup is open; the catalog is rebuilt per
  edit (`doc.ml:24`).

---

## 4. Lisp bugs

| ID | Severity | What | Where | Evidence |
|---|---|---|---|---|
| L1 | crash at launch | Two inline `let*` / `for` / `fn` under one binding get the same path (`…/~for`), so compiled ids collide: `E_LOWER: editable graph already contains node #3`. `rays-lisp check` exits 0, so the dune build passes and the window fails. Trigger: `(sop/merge (ring 2) (ring 3))` with a `for` in the macro | `workspace.ml:942-944`, `lower.ml:107-114` | RUN |
| L2 | data loss | Exponent floats (X1) | `syntax.ml:14`, `lisp.ml:24-30` | RUN |
| L3 | crash | A `0x01` byte in a comment, string or symbol: `Failure "int_of_string"` in the printer, which uses `\001 id \002 … \003` as in-band markers. `0x03` is silently deleted | `lisp.ml:10`, `:254-273` | RUN |
| L4 | data loss | Print deletes comments: inside parameter vectors of `graph`/`defn`/`defmacro`/`fn`; between `^:meta` or `'` and its form; before `(layout …)`/`(settings …)`; a comment inside `->` un-threads the pipeline. One case also breaks the promised `print (parse (print x)) = print x` | `lisp.ml:187-196`, `syntax.ml:124,129,159` | RUN |
| L5 | wrong result | Positional after keyword refills slot 0 (X3) | `workspace.ml:1162-1174` | RUN |
| L6 | wrong result | `(fold [a 0] [i (range 3)] (+ a 0.5))` gives 3, not 1.5: an int seed rounds a float body each iteration. `reduce` has the exemption, `fold`/`scan` do not | `eval.ml:864`, `workspace.ml:754` | RUN |
| L7 | wrong result | `if` type hole: `(range (if false 3 [1 2 3]))` checks, fails at eval | `workspace.ml:568-571` | RUN |
| L8 | wrong result | Macro hygiene hole: operator and kind names count as "known" in value position; `` `(+ count 1) `` captures the caller's `count` | `workspace.ml:316-320`, `macro.ml:70` | RUN |
| L9 | crash at launch | A catalog kind as a function value (`(map sop/facet …)`) checks and never lowers: `E_PORT: No parameter port $0`, no span | `eval.ml:794-799`, `:671` | RUN |
| L10 | false error | `^:bypass` input index computed two ways (checker counts written args for every call; eval only for kinds) | `workspace.ml:1278-1290`, `eval.ml:728-734` | RUN |
| L11 | data loss | Refused reload overwrites the Document draft (X5) | `core.ml:5003` | READ |
| L12 | data loss | `(view …)` is accepted and dropped on write; `rays-lisp fmt` on a preset removes the camera | `workspace_doc.ml:69`, `:104-107` | RUN |
| L13 | papercut | `E_LAYOUT` / `E_SETTINGS` have no span; a dune build error points at `line 1, characters 0-0` | `workspace_doc.ml:92,95,101` | RUN |
| L14 | gap | Stale layout keys never pruned (X4) | `workspace_doc.ml` | RUN |
| L15 | spec gap | Metadata outside expressions is silently ignored: `^:nonsense (workspace …)` exits 0. Spec says `W_UNKNOWN_META`; that code does not exist | `workspace.ml:1383` | RUN |
| L16 | hang | `->` bypasses the nesting limit and the printer is quadratic in chain length: 8,000 steps take 5 s; 100,000 steps ran over five minutes | `syntax.ml:148-159`, `Lisp.deep`/`spine` | RUN |
| L17 | papercut | Static `E_ITER_BOUND` product overflows to 0 with six `(range 4096)` clauses | `workspace.ml:748` | RUN |
| L18 | papercut | Non-finite values escape `E_NONFINITE` through `value/lerp`, `polar`, `hsv`, vec3 arithmetic; fails at lowering with no span | `eval.ml:258-267` | RUN |
| L19 | papercut | `tools/render_workspace.ml:18` raises `Failure "hd"` with no camera | | RUN |
| L20 | papercut | `%S` escapes UTF-8 in messages (`"h\195\169"`); `t.x` reports "`t` is not bound"; `(nth xs 2.5)` silently reads index 3; malformed `:skip` tuples silently ignored | `workspace.ml:1137,1188,449` | RUN |
| L21 | design gap | `rays-lisp check` stops after `Workspace.check`; it cannot see run-pass or lowering failures, which is why L1 and L9 pass the build | `tools/lisp` | RUN |
| L22 | papercut | Save renames over the target, so a symlinked `sketch.rays` becomes a regular file; no fsync before rename | `store.ml:8-22` | READ |

Also: six checked-in sketches are not print fixed points of `rays-lisp fmt` (confirmed for
`ws_layout`, `ws_variations`), so their first Command-S produces diff noise; `cube_cage` fails
`check` under the default catalog (expected: it has a custom node).

Checked and correct: division and `mod` by zero giving 0 and `pow`/`sqrt` on absolute values are
specified; CRLF, tabs, BOM, empty file, unterminated strings and forms, mismatched closers, bad
escapes, macro expansion loops, graph cycles and `defn` recursion all give typed diagnostics with
correct positions.

**Duplication inside the Lisp layer**

| What | Copies |
|---|---|
| Float to text | 4 `number` functions + 4 `%.Ng` sites (X1) |
| Lexer | `Syntax.tokenize` and `Lisp_text.lex`, with duplicated `separator` and `number`; they already disagree on multi-line strings |
| Special-form lists | `Workspace.special`, `Lisp.bind_forms`, `Lisp_text.specials`, `Lisp_text.body_forms` (which lists `let`, `when`, `do` — forms the language does not have) |
| Operator tables | `Workspace.ops` and `Eval.value_ops` / `arith_fns` / `is_struct_op` |
| Number to int | `Eval.round` is `floor (x + 0.5)`; `Port_type.coerce` uses `Float.round`; they differ on negative halves |
| Bypass index | `Workspace.bypass` and `Eval` (L10) |
| `head` of a form | `tools/lisp/lisp.ml`, `workspace_doc.ml`, `projection.ml` ×2, `text_pane.ml` |
| Fresh name | `scene_sync.ml:332-340` and `flow_edit.ml:413-440` |
| Double check | `rays-lisp check_text` runs `Workspace.check`, then `Workspace_doc.of_text` parses and checks again |

---

## 5. Gaps

### 5.1 Spec versus code

| Spec says | Code does |
|---|---|
| `flow.md` §11.6 `E_POSITIONAL_AFTER_KEYWORD` | absent (X3) |
| `flow.md` §11.6 `W_UNKNOWN_META` | absent; `E_META` inside expressions, silence outside (L15) |
| `flow.md` §11.9 `E_DEPTH` at 256 | limit is 120, and `->` bypasses it (L16) |
| `flow.md:568` `v` writes a `(display …)` layout entry | `v` rewrites the graph tail (the PLAN §3 decision). The spec is the stale side; update it and finish removing `layout.display` |
| `flow.md` Alt-click bends | unbuilt by decision (PLAN §8); `Layout_by_path.bends` still serialises them |
| Root `AGENTS.md`: "value ports, drives, compounds" | compounds deleted per `lib/rays_editor/AGENTS.md`; "compound" appears 95 times in docs |
| `lib/pxui_graph/AGENTS.md` W5 footer hoist button | handler at `scope_pane.ml:2541`, nothing creates the button |
| `flow.md` is normative | it says the workspace plan "supersedes the text form of this file" |
| `PROMPT.md:69` "toggle guide pair is gone" | code remains at `pxui_shell.ml:1186-1224` |
| `lisp.mli` promise `print (parse (print x)) = print x` | broken by L4 |
| `Flow_edit.mli`: folding keeps notes | G7 |

Names in docs that no longer exist in `lib/`: `Pxui_graph.catalog_of_factories` (4 docs),
`catalog_entry`, `open_menu_at`, `Editor_core.Network_layout` (6), `Network_view` (9),
`Flow_sop.Program`, `Flow.Expr`, `Flow.Sexp`, `Voxel3`, `Network.geometry_outputs`.

### 5.2 `PLAN.md` status

| Section | State |
|---|---|
| §1 zero-viewport pick crash | fixed (`environment.ml:770,783,794`) |
| §3 VIEW as a second result | half done (A6) |
| §7 colour row | exists; detects colour by the substring `"color"` (`pxui_shell.ml:2084`) |
| §10 relative mouse on orbit | done; has the stranded grab E21 |
| §2, §4, §5, §6, §8, §9 | not re-audited here |

### 5.3 Test gaps

No test covers: an undo that removes an open graph (E2); an external change over a dirty document
(E8); Command-S or Space with text focus (E10); malformed paste (E6); two editors alive at once; a
zero-size window; `Which_key.sheet` (E18); undo count of a viewport handle drag or the colour
picker; same-named bindings in two scopes (G10); keyword-first calls (X3); wire hover inside a zone
(G11); context menu after a wire selection (G12); state crossing between two text widgets (G2,
G6); copy on an empty area (G3); popup during a carry (G16); IME composition; `Layout_*` with
`:active` out of range (G1); `remap` for `Unfold` / `Fold_into` (X4); the printer fixed point with
comments (L4); exponent round-trip (X1).

Weak tests: `test/test_editor_transactions.ml:92` has a scrub heading with no assertion;
`test_workspace_shell.ml:1348-1352` passes either way when the clipboard is unavailable; shell,
layout, text and carry tests are Editor3 only; the scope gesture suite could not be located by name
in `test_main.exe test_pxui_graph` (it printed only "node menu tests passed").

### 5.4 Tooling gaps

- `rays-lisp check` does not lower (L21).
- No bench has a dune alias except `metal-bench`, so nothing keeps 12k lines of benches compiling
  against intent, and `PROMPT.md`'s scope numbers are not reproducible from an alias.
- The codemod's `dead-exports` does not see uses through a functor signature: `viewport2.ml` and
  `viewport3.ml` report 34 false "dead" exports each. Do not blind-prune `lib/rays_editor`.
- The codemod's `dead-stubs` mode rewrites `metal_bridge.mm`; there is no report-only mode for it.

---

## 6. What to delete or collapse

Measured where marked; otherwise estimated. "Codemod" means `tools/codemod` as described in the
`prune-dead-code` skill.

### 6.1 Safe, mechanical (about 6–7k lines)

| # | Item | Evidence | Lines | How |
|---|---|---|---|---|
| D1 | Copy-pasted test helpers | `fail` ×220, `check` ×178, `get_ok` ×78, `equal_geometry` ×47 (870 lines measured), `equal_storage` ×33 (816), `check_parallel_exact` (492), `equal_group` (279), `contains` (220) | ~3.7k measured | one `rdk_test_support` module shared by `lib/rdk/test_*` and `lib/procedural/test_*` |
| D2 | Hand-rolled utilities in rdk | heapsort ×8, union-find ×13+, parallel `run` ×8, `get_ok` ×31, `checked_add` ×26, `next_power_of_two` ×6, `grow`/`ensure` ×51 | 600–800 | into `rdk_core/support.ml`; the one/four-domain exactness tests already guard it |
| D3 | Hand-rolled stdlib elsewhere | `contains` ×55, `( let* ) = Result.bind` ×59, read-file ×14, `write_file` ×9, `mkdir_p` ×8, three s-expression parsers in tools, a JSON pretty-printer although yojson is a dep, `List.filteri (fun i _ -> i < n)` ×51 | ~900 | one tools support module; `List.take` needs the opam floor at 5.3 |
| D4 | Dead exports in internal libraries | codemod: rdk 30, pxui 8, pxui_shell 3, flow_sop 3, procedural 3, rays_editor ~13 (12 spot-checked, 0 uses each) | 150–300 | codemod `prune` on `lib/rdk lib/pxui_shell lib/flow_sop lib/pxui_graph lib/editor_core lib/editor_document` |
| D5 | Orphan tools | `bench_edit_graph`, `bench_traced_panes`, `pt_convergence` referenced nowhere; `bench_camera_input`, `bench_editor_cook` only from `reports/`; `metal_registry.ml` calls itself "one-shot" | ~810 | delete with their `tools/dune` stanzas |
| D6 | Editor dead code | `pane_ui`, `Core.captions` (written every frame, never read), `Core.hud`, `Status_bar.guide` command path + `hide_guide`, `Inspector ?actions` / `flow_change.Split` / `flow_row.components` (product always passes `~actions:false`), `Layout.toggle`, `Chrome.note`, `Tree.shown`, `common.ml:4-17`, `navigator.ml:143 pretty`, `Link_row.outgoing`, `cook.ml:131 seconds`, `renderer.ml:42 schema`, `Objects.Root.renderer_label`, `Document.object_network`, unreachable `leader.ml` chords | ~130 | by hand |
| D7 | Graph pane dead code | `P.More` line with its paint/tap/handler, the `` `Hoist `` handler, `Scope.with_visible` and its unreachable branch, the `&& false` arm, six no-op statements in `update` (`ignore overlay`, `drawn_rows := !drawn_rows`, …), test-only exports `Projection.place`, `Scope.wires`, `Scope.macro_step`, `Scope.selected_wire` | ~40 | by hand |
| D8 | `ui.ml` exports with no caller outside `lib/pxui` | `Ui.cached` with `snapshot`/`cached_subtree`, `Ui.splitter`, `Paint.arc`, `Ui.hit_rect` with the `hx/hy/hw/hh` arrays, `Ui.panel_padding` | ~107 | codemod, then API manifest promote |
| D9 | Flow migration residue | `Port_type`, `Flow.Context`, `Check.term`/`call`/`checked`/`state`/`known_prefix`, `Layout_by_path.wireless`/`bends`, legacy `defmacro`, `eval.ml:448` test switch | ~300 | confirm each with codemod first |
| D10 | `Edit_graph` pre-text editing API | 12 functions with callers only in its own tests | ~200 + ~250 tests | codemod `--cut-tests` |
| D11 | Env-variable debt | `WINDIR` and Linux font paths in a macOS-only project (`sdl3_ttf.ml:214-226`); `RAYS_UI_FONT` resolved in three places; 56 variables documented nowhere | ~100 | one font resolver; document `RAYS_CRASH_DIR` and `RAYS_PROFILE` |
| D12 | Duplicate workspace sources | 10 of 12 `specification/workspace/cases/*.lisp` are byte-identical to `sketches/ws_*/sketch.rays` | 10 files | point the `test/dune` glob at the sketches |

### 6.2 Duplicates to merge (each fixes a bug listed above)

| Merge | Sites | Fixes |
|---|---|---|
| One float printer | 8 sites | X1, E4, G13's `%.6g` |
| One ellipsis fitter | `scope_pane.ml:1057`, `ui.ml:1022`, `ui.ml:2229` | G23 |
| One argument splitter | `projection.ml:81` → `flow_edit.ml:155` | G9 |
| One fresh-name helper | `scene_sync.ml:332` → `flow_edit.ml:413` | the `root` refusal |
| One text-edit reset | two editor starts in `ui.ml` | G2, G6 |
| One numeric parameter field (`Kit.number` taking range and type) | `scope_pane.ml:1936`, `pxui_shell.ml:1959` | G13, the vector-cell click |
| One type → port colour (`Theme.port_of_ty`) | `scope_pane.ml:1049`, `:1119`, `node_menu.ml:123` (three different fallbacks) | a list is float-coloured on a card and `compound` in the menu |
| One colour control | `text_pane.ml:434-463` reimplements `Kit.colour`; they diverge on alpha | — |
| One tree walk by path (`Panels.at`) | `core.ml:320`, `:405`, `panels.ml:39` | — |
| One "path → probes → plan node → compiled id" | five copies in `core.ml` (690, 1066, 1327, 1358, 1609) | — |
| One draft apply | twelve near-identical branches, `core.ml:2451-2486` | — |
| One 8-corner box transform | `cook.ml:85`, `core.ml:4704`, `viewport3.ml:464` | — |
| One thousands grouping | `core.ml:579`, `:2071`, `:3564` | — |
| One Liang–Barsky clip | `scope_pane.ml:129`, `:1829` | — |
| Inside `ui.ml` | `grow_float`/`grow`, five `text_width`s, two scroll-thumb painters, `accordion`/`inspector_section`, three button grounds, four root-overlay boilerplates | ~85 lines |
| rdk algorithm pairs | `Orientation_cache` ×2, `Stable_bounds_bvh` vs `Bounds2_index`, hash grid in `point_clusters`/`point_snap`, `fuse_reduce` vs `fuse_rules`, triangulation drivers ×5, `remap_attribute` wrappers ×9 | ~900 lines; one pair per commit |

### 6.3 Needs a decision from the owner

| # | Item | Cost of keeping | Lines if cut |
|---|---|---|---|
| Q1 | **`Editor2`** — no sketch or example uses it | the `VIEWPORT` functor, ~20 `scene_level` branches, `Easy_camera2`, `Camera2_control`, crash E3, and every shell test being Editor3-only | 400–800 |
| Q2 | **OGPU features with no product caller** — 66 `Backend` operations are test-only (heaps, residency sets, fences, events, archives, dynamic libraries, mesh/tile pipelines, sparse textures, upscaler) | `lib/ogpu/AGENTS.md` mandates full capability, so this is policy | 2.5–4k |
| Q3 | **rdk operations with no node**: `Blend_shapes` (547), `Attribute_composite` (528), `skin`, `group`, `ordered_group` | register nodes or cut | ~2k |
| Q4 | **`sweep_circle.run_legacy`** duplicates `Polywire.run`; a test asserts identical output | benchmark first, it is the fast path | ~630 |
| Q5 | **Unused public API in `rays` / `rays_math`**: `Bounds3` 20/20 dead, `Bounds2` 16/18, `Easy_camera` 21/44, `Mesh` 21/55, `Font` 19/36, `Audio.Music.*` 17/24 | public surface by rule | 140 certain, up to ~1k |
| Q6 | **91 optional arguments no caller passes** (Metal 42, rays 33) | — | 150–250 |
| Q7 | **`sketches/flow_workspace`** is a scripted test harness with 13 `FLOW_*` variables | move its checks into `test_workspace_shell.ml` | ~200 |
| Q8 | **Old-file readers** (`legacy_render`, `adopt_world_legacy`, `layout.display`) | old files stop loading if cut | ~100 |

### 6.4 Docs and non-code

| Item | Size | Action |
|---|---|---|
| `specification/performance.md` | 5,341 lines; opens with a dated test baseline | keep the rules, move the journal to a log |
| `specification/rdk.md` | 4,704 lines of per-operator bench transcripts | same |
| `flow-migration.md`, `workspace/plan.md`, `workspace/progress.md` | completed work queues | archive |
| `lib/rays_editor/AGENTS.md` | 495 lines, reads as a changelog | cut to rules |
| `lib/pxui_graph/AGENTS.md` | two sections it labels "historical" | delete them |
| `PLAN.md`, `PROMPT.md`, `reports/`, `research_notes/` | hand-off artefacts, two stray `.ml` repro files | delete when their open items land in §7 |
| `specification/pxui-kit` | 3.3 MB; 20 PNGs referenced by no file | check and delete |
| `specification/workspace/prototype/index.html` | 473 KB, generated by `build.cjs` and checked in | generate or keep one of source/output |
| `specification/evidence/code_quadtree/*` | 9 files referenced nowhere | delete |

### 6.5 Leave alone — earning its keep

- `ogpu_core` / `ogpu` / `ogpu_metal_native` / `ogpu_metal`: the split is forced by dune virtual
  libraries and nothing above the path tracer names `Ogpu.`.
- `ogpu_mock`: proves the interface has two implementations and runs conformance without a GPU.
- `native_layer_token` (24 lines), `lru`, `rays_math`, `param`: each is the minimum that keeps
  `flow` and `rdk` below `rays`. Do not rename `Procedural.Parameter` (575 uses).
- `flow` vs `flow_sop`, `editor_core` vs `editor_document`, `scene_command`, `runtime_input`,
  `runtime_resources`, the eight `rdk_*` sub-libraries.
- The dependency gate: extend it, do not replace it.
- `Environment` / `Core` / `Doc` as the single reducer and `Pxui.Ui` as the single UI engine.
- `Syntax.tokenize` vs `Lisp_text.lex` as two *jobs* (strict reader, error-tolerant span lexer);
  share `separator` and `number`, do not force one lexer.
- The five triangulators, the boolean pipeline, `predicates`/`implicit_point`/`exact_dyadic`: layered,
  not duplicated. All 160 rdk modules are reachable from product code.
- `lib/metal`: 0 dead exports; the registry generator already prunes it.
- `ui.ml` as one file: no split removes duplication. The merges in §6.2 do.
- FNV and `65_599` hashes in `scene.ml`, `ui.ml`, `sop.ml`: stable identity, not `Hashtbl.hash`.

---

## 7. The plan

Rules for every step: fix at the function all callers already go through; one test that fails if it
regresses; delete before adding; no new library, registry or framework unless a step says so and
says why. Each numbered step is one commit that passes
`_build/default/tools/check.exe <focused alias>`; each phase ends with `--ship`.

Dependencies between phases: 0 → 1 → 2 are strictly ordered. 3 and 4 are independent of each other
and can run in parallel after 2. 5 needs 3. 6 needs the Q-decisions. 7 last.

### Phase 0 — Safety nets (so later phases cannot regress silently)

| Step | Change | Test |
|---|---|---|
| 0.1 | Catch-all in `Flow_edit.apply_checked` around `rewrite` → `E_EDIT` diagnostic (X6) | an op that raises inside a rewrite returns `Error`, document unchanged |
| 0.2 | `rays-lisp check` also runs `Eval.static` and `Lower.workspace` (L21) | cram case in `test/lisp_build.t`: the L1 and L9 inputs exit non-zero with a diagnostic |
| 0.3 | Printer property test over every `sketches/*/sketch.rays` and `specification/workspace/cases/*`: `print ∘ parse ∘ print = print`, and no comment text disappears | fails today on L4; mark the known cases and remove the marks in phase 2 |
| 0.4 | Scripted-frame probe as a test helper (the audits each rebuilt one): load a `.rays`, feed `key:` / `click:` events as `tools/ui_shot.ml` already parses them, return the editor value | used by every editor test below; reuse `UI_SHOT_DO`'s parser, do not write a second |
| 0.5 | Find or name the scope gesture suite so `test_main.exe test_pxui_graph` actually runs `run_scope` | the alias prints its case count |

### Phase 1 — Crashes

One guard each, at the shared function.

| Step | Fix | Closes |
|---|---|---|
| 1.1 | Unique inline segment per enclosing path in `Workspace.call` (`~for`, `~for#1`, … from a counter keyed by `cx.path`), one helper for `let*`/`for`/`fn` | L1 |
| 1.2 | Reject bytes 1–3 in `Syntax.tokenize` (`E_UNEXPECTED`) | L3 |
| 1.3 | `lisp_text.ml:484`: no positional lookup when `prior = []` | E1 |
| 1.4 | `as_pane` re-resolves `pane.at`, default `Scene`, clears `picked` | E2 and its three sibling `Option.get`s |
| 1.5 | In-frame reducer maps `resolve_level` `Error` to a refusal like `install` | E3 (skip if Q1 deletes Editor2) |
| 1.6 | `Layout_remove` / `Layout_new` use `List.nth_opt`; checker range-checks `:active` | G1 |
| 1.7 | One `reset_edit` in `ui.ml` for both editor starts | G2, G6 |
| 1.8 | `ui.ml:3582` uses `line_start` / `line_end` | G3 |
| 1.9 | `with_scope` clears `hinting`, `context`, `highlighted` on a scope change | G4 |
| 1.10 | Cook request carries the volatile predicate; `set_volatile` runs on the worker | E5 |
| 1.11 | `Kind_fn` in `call_fn` uses the qualified kind and maps positionals to slot names (the checker already resolved both) | L9 |
| 1.12 | `tools/render_workspace.ml:18`: typed error with no camera | L19 |
| 1.13 | Count depth in the `->` fold; make `Lisp.deep` linear; set the limit to the spec's 256 or change the spec to 120; drop the `Stack_overflow` handler | L16 |

### Phase 2 — Data loss and the text round-trip

| Step | Fix | Closes |
|---|---|---|
| 2.1 | One float printer in `Flow.Lisp`; replace all eight sites; `Syntax.number` (and `lisp_text.ml:20`, by sharing it) accepts exponents; non-finite rejected at `environment.ml:791` | X1, E4, L2 |
| 2.2 | `E_POSITIONAL_AFTER_KEYWORD` in `Workspace.args_of`; delete `Projection.split_args` | X3, L5, G9, and `Move_item`'s `E_SKIP` |
| 2.3 | Printer keeps comments: note-aware layout when a parameter vector is `deep`; comments after a prefix attach to the inner form; `Workspace_doc` keeps unknown root forms, `(view …)`, and comments between root forms | L4, L12, E11 |
| 2.4 | Prune layout against checked paths in `Workspace_doc.of_text` and `.edit`; clear a dangling `layout.editor` | X4, L14 |
| 2.5 | Reload: keep a dirty document or a draft, show a notice; no poll while carrying | X5, E8, L11 |
| 2.6 | Remove the "known failure" marks from 0.3; run `rays-lisp fmt` over the six non-fixed-point sketches and commit the result | first-save diff noise |
| 2.7 | Recovery file is not overwritten while `doc` is the opened document | E7 |
| 2.8 | With text focus, the router still delivers Meta/Ctrl chords the text widget does not own; `Save_source` applies a draft or refuses with a notice | E10 |
| 2.9 | `Scene_sync` uses the surgical branch for member Worlds; uses `Flow_edit.fresh_name`; uniqueness check on `name` edits; object id → graph name in `Document.homes` instead of physical identity | E9 and the three document-layer bugs |
| 2.10 | Paste: positional pairing, simultaneous substitution, one `Syntax_batch`; fold a frame's changes into one batch | E6, E16 |
| 2.11 | `Flow_edit`: `Add_field` fails on an existing key (pane picks the first free `fN`); `Fold_into` carries notes; `Move_item` indexes positionals and remaps `:skip`; delete counts references inside the edited scope only | G5, G7, G8, G10 |
| 2.12 | `Store.write_text`: resolve symlinks before rename; fsync | L22 |

### Phase 3 — Editing semantics (undo, input, graph gestures)

| Step | Fix | Closes |
|---|---|---|
| 3.1 | Follow-viewport camera writes use `Repair`; `History.amend` keeps `future`; no write on an undo/redo frame | E12 |
| 3.2 | Gesture key for all-`Flag` frames; drop `shell.live` without `Resize`/`Settled`; carry guard on `edit_node` and `entered_camera` | E13, E14, E15 |
| 3.3 | `Router.step` normalises shifted symbols as `Keymap.label` does; key sheet groups by `Leader.group`, delete the prefix table | E17, E18 |
| 3.4 | Focus falls back to the leaf at the longest surviving prefix | E19 |
| 3.5 | `Scope.suspend` (clear editing, hinting, drag, context; release the grab), called when `scope_active` is false; delete `with_visible`; one release path for relative-mouse on every early return | E20, E21 |
| 3.6 | Context menu clears `selected_wire` and emits `Selected`; zone wire hit boxes are built after the zone tile | G11, G12 |
| 3.7 | One `Kit.number` taking the row's type and soft range, used by the card and the inspector; prints through 2.1 | G13 and the vector-cell click |
| 3.8 | `fallback` returns `None` for rest rows; add a remove-item gesture; `+ output` opens a name field; list/fn add rows show the "wire a node" notice; delete the `&& false` arm | G14, G15 |
| 3.9 | `ui.ml`: drop a `From_pointer` payload when its owner stops being active; `keep_focus` for `off` picker rows; cull only with `clip`; resolve scroll height before `apply_scroll`; number scrub on the editor's undo stack; strip newlines on paste into single-line fields | G16–G21 |
| 3.10 | Multi-line strings in `Lisp_text.lex` and parinfer (share string state across lines) | E22 |
| 3.11 | Language fixes: accumulator typed `Ty.join init body` for `fold`/`scan`; `if` takes the wider branch; `known` split by head vs argument position, `name_taken` in `check_pat`; bypass index stored once in `Bypass`; saturating iteration product; `fin` on `lerp`/`polar`/`hsv`/vec3; metadata outside expressions diagnosed; spans on `E_LAYOUT`/`E_SETTINGS`; `%s` not `%S` for UTF-8 | L6, L7, L8, L10, L13, L15, L17, L18, L20 |

### Phase 4 — Performance (measure before and after; hand off numbers)

Bench command for all of it: `dune exec test/test_main.exe -- bench_scope_big` plus a
`Gc.Memprof` run on an idle frame. Give it a dune alias first.

| Step | Fix | Expected |
|---|---|---|
| 4.1 | Clip each wire segment to the viewport before subdividing; build the tile index and `read` set in `compute`, not per frame | the off-screen 6.2 MB/frame case drops by more than half |
| 4.2 | One forward-pass ellipsis helper for `fitted`, `Ui.ellipsis`, `inspector_fit` | top allocation site with cards in view; removes the 1.5 s/frame worst case |
| 4.3 | Live count in the UI key table, decremented in `remove` | bounded table under key churn |
| 4.4 | `level_command`, `parents_removed`, `upstream_of`, `shift`: int-keyed set instead of `List.mem` / array scans | `Point_all` on 2,001 nodes from 49 ms |
| 4.5 | Capacity on `Probe` memo tables and `Core.locals` (prune as `graph_panes` is at `core.ml:475`) | repo rule |
| 4.6 | Compute `Layout.geometry` once per `update_frame`; build the catalog once per document, not per edit; one `Lisp_text.complete` per frame | measure first; cut only what shows |
| 4.7 | Int keys for path-keyed tables in `Projection` / `Flow_edit` (the `PROMPT.md` profile finding: polymorphic compare and hash) | the 20 ms cold `with_scope` |

### Phase 5 — Mechanical deletion (§6.1)

Order chosen so each deletion makes the next one visible to the codemod.

| Step | Do |
|---|---|
| 5.1 | D6, D7 by hand (editor and pane dead code) |
| 5.2 | D9, D10: flow residue and the `Edit_graph` pre-text API, codemod with `--cut-tests` |
| 5.3 | D4, D8: codemod `prune` on the internal libraries (not `lib/rays_editor`); `dune promote` the API manifest |
| 5.4 | D5: orphan tools |
| 5.5 | D1: `rdk_test_support`; D2: `rdk_core/support.ml`; D3: tools support. This is the one place a new module is justified: it replaces 3.7k measured duplicate lines |
| 5.6 | §6.2 merges not already done in phases 2–4 (tree walk, id lookup, draft apply, box transform, colour control, port colour, `ui.ml` internals) |
| 5.7 | D11, D12 |
| 5.8 | rdk algorithm pairs, one pair per commit, each behind the existing exactness tests |

### Phase 6 — Structural (needs the §6.3 answers)

| Step | Do | Risk |
|---|---|---|
| 6.1 | **Split `core.ml`** along its existing section comments into private modules of the same library. Extract `Reduce` (`4158-4551`) first as a pure `reduce : t -> frame_result -> actions -> …` so E3/E15/E16-class bugs get direct tests. Then `Model`, `Shell_state`, `Panes`, `Scope_sync`, `Inspect`, `Add_menu`, `Scene_list`, `Status`, `Text_apply`; move carry code into `carry.ml`. About 900 lines stay. Moves only; no behaviour change per commit | low; large diff |
| 6.2 | **Move `build`'s seven mutations out of `Ui.frame`** into returned intents (the rule the repo already states) | low |
| 6.3 | **`sop_catalog` → `rays_math`**; add `sop_catalog` to the gate's never-reach-GPU list. Only then consider a runtime-free `rays` core if `rays-lisp` link size or build time matters | low / medium |
| 6.4 | **Q1: delete `Editor2`**, `viewport2.ml`, the `VIEWPORT` functor, `scene_level`, `Easy_camera2`, `Camera2_control`, `Store.Viewport.encode2` | product decision |
| 6.5 | **Collapse write path B (A2)**: inspector and handle edits emit `Flow_edit.Set_arg` at `Document.homes`; `Scene_sync.reconcile` remains for adopt only. Do it one edit kind at a time behind `test_scene_sync` | high; removes 400–500 lines and the bug class of step 2.9 |
| 6.6 | **Finish PLAN §3**: delete the `layout.display` readers and the loop-node writer; update `flow.md:568` | low after Q8 |
| 6.7 | **One SOP declaration (A3)**: the PPX emits the cache key, validation and forwarding call from the record. Start with one catalog file; gate on byte-identical cache keys and the `flow_manifest.sexp` diff being empty | high; 2–4k lines |
| 6.8 | **Q2–Q7** as decided (OGPU test-only features, rdk ops without nodes, `run_legacy`, public API trim, optional arguments, `flow_workspace`) | per item |
| 6.9 | **Gate**: whitelist the "depends only on" claims; add rules for `rays_pathtracer`, `rdk_rays`; scan `tools/` and `test/` for Metal tokens; move `result_bind_ppx` out of `tools/codemod` so `lib/metal` does not depend on `tools/` | low |
| 6.10 | Fold `rays_execution` into `runtime` **only when next touching it**; pass one window token instead of four callback refs | medium; do not schedule on its own |
| 6.11 | Move `flow_sop` / `editor_document` / `pxui_graph` tests that link only those libraries out of `test/test_main` | low; faster links |

Not planned: making `rays`/`procedural`/`rdk` exception-free (A7). 650+ sites, and the exceptions
are already caught at two boundaries. Do it per function when a bug lands there.

### Phase 7 — Docs

| Step | Do |
|---|---|
| 7.1 | Root `AGENTS.md`: fix the library table (add the five missing libraries, `Store` is s-expressions), drop "compounds", drop "known violations are listed there", correct the pipeline sentence |
| 7.2 | `flow.md`: resolve "normative" versus "superseded by the workspace plan"; apply the §5.1 table; remove the ten dead module names across all docs |
| 7.3 | Split `performance.md` and `rdk.md` into rules and a log |
| 7.4 | Cut `lib/rays_editor/AGENTS.md` and `lib/pxui_graph/AGENTS.md` to current rules |
| 7.5 | Archive the completed migration files; delete `PLAN.md`, `PROMPT.md`, `reports/`, `research_notes/` once their open items are closed or moved here |
| 7.6 | `api_stable.json`: store signatures, not hashes, so the diff is reviewable |

---

## 8. Open questions for the owner

1. **Editor2**: delete it? Nothing but one test file uses it, and it is the reason for a functor,
   twenty branches and one crash.
2. **Positional after keyword**: enforce the spec's error (recommended, least code), or allow any
   order and fix three readers?
3. **OGPU "full capability"**: keep 66 test-only backend operations as policy, or cut to what the
   runtime and path tracer call?
4. **Old `.rays` files**: may `layout.display`, `legacy_render` and `adopt_world_legacy` stop
   loading?
5. **Nesting limit**: 120 (code) or 256 (spec)?
6. **`Blend_shapes`, `Attribute_composite`, `skin`**: register nodes, or cut?
7. **Viewport navigation in undo** (E12): confirm camera motion with `follow_viewport` is view
   state, not an edit.
