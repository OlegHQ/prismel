# Workspace implementation progress

Tracks the implementation of [plan.md](plan.md) (PR #1). One row per
milestone; update the row in the same commit that lands the work. Deviations
from the plan and measurements go in the notes under the table and, per plan
§6.6, in `specification/flow-migration.md` under "Workspace".

Status: `todo` · `wip` · `done` (gate met) · `partial` (what is missing is named).

| Milestone | Status | Commit | Notes |
|---|---|---|---|
| W0 fixes & catalog prerequisites | done | | Merge group padding, set_color group/vec3 colour (its v3 preset migration was deleted with v3 in W3), `Manifest.version` in text view and the `:rotate` note landed; the `Rest` slot landed with W4 part A (notes below). |
| W1 language core (`flow`) | done | | `Flow.Syntax`, `Lisp`, `Ty`, `Macro`, `Workspace` (checker, typed IR, liveness, invariance) and `Eval` (values, loops, functions, records, HOFs, `ref`, the geometry plan, `static` / residual split, `?record`); the 12 fixtures check, print, round-trip and run; the check.cjs suite is ported (119 of 120, see the W1 part C notes). |
| W2 lowering & cooking | done | | `Flow_sop.Lower.workspace`, `Pdk.Mesh_merge ?source_attribute`, session default 512, `test_workspace_cook`, `bench_workspace_lower`. Live parameters are only recorded (`Lower.pending`); drives are W2b. |
| W2b live `t` | partial | | `Drive.Live`, `Lower` live drives, `flow.curve` text-encoded points, volatile session slots, `Async_cook.await`, `Cook ?await`, status text, tests and bench (notes below). Gaps: UI text (W4/W5), `Frame` cannot tell a fixed clock. The editor is fed by a workspace since W3. |
| W3 document v4 + history | done | | `Flow_edit`, `Workspace_doc`, `Layout_by_path`, s-expression presets, the editor opens a workspace and recooks live `t` (notes below). No older presets. Gaps: only workspace documents save. |
| W4 graph pane zones | done | | Part A (`Flow_sop.Projection`, `Rest`) and part B (`Pxui_graph.Scope`, zone tokens, selectors, `Core` wiring, layout by path, probes); see the W4 part B notes and `flow-migration.md`. Gaps: no marquee (the inspector follows the selection since W5), the flat pane remains for non-workspace documents, only `sop` graphs open. |
| W5 probes & footers | done | | `Flow_sop.Probe` (records, footers, counts, inspector rows), `Pxui_graph.Scope.with_records`, cook geometry counts piggybacked on the display cook, the workspace inspector, the `t N live · M cached` status, auto-select of an added node (notes below). Gaps: no zone footer while expanded, the geometry of a node that is not upstream of the display shows only its type. |
| W6 viewport provenance | done | | `Pdk_prismel.Prismel_mesh.to_mesh_with_primitives`, global `__flow_src` tags that survive nested merges, `Pick` (CPU ray over `Pdk.Surface_index`, per-corner tint), `Core.pick`, the highlight follows the selection and probes; click in Viewport3 selects the node and probes its iteration (notes below). Gaps: geometry drawn as instances is not picked, a collapsed zone stays collapsed. |
| W7 editable text | done | | `Ui.text_area`, the text pane's Selection, Graph and Document tabs (`Prismel_editor.Text_pane`), atomic Check & apply (`Doc.text_edit`, `Core.text_edit`/`binding_edit`, one "Edit text" entry), per-binding apply, error marks at their line; the old read-only text pane and the flat network text view are deleted (notes below). Gaps: the Graph tab is read-only, no Tab key, wrapping or Cmd-Enter apply. |
| W8 loops over geometry | done | | `point_list` / `piece_list`, the zone node (`Eval` template, `Procedural.Zone` + `Node.Private.expand` + `Session`), lowering by `Lower.instantiate`, zone provenance and count, `FLOW_CASE=garden`, `test_workspace_zone`, bench (notes below). Gaps: values inside the loop read the template record, no `t` in the body, no "by index" title, sequential. |
| W9 macros UI, notes, bypass | done | | `Projection` lens and `layout ?lens`, the panel and `B` flag in `Scope`, `Macro_requested` + `Flow_edit.macro_draft` / `macro_op` + `Pxui_shell.Prompt.macro`, the inspector note field, tests through the pane and the editor, `FLOW_CASE=rosette` (notes below). Gaps: no Template button, no Enter to create, no inspector bypass toggle. |
| W10 contexts & composable shell | done | | Part A (contexts): `scene`, `world`, `settings` graphs check, lower into the document and open in the pane. Part B (shell): `Editor_core.Panels` and `Pxui_shell.Layout` (the tree and its geometry), the editor graph lowered into `Document.shell`, focus and commands keyed by panel, split/close/retype/resize as `Flow_edit` ops, Restore layout, one scene instance per viewport override, `ui/graph` names its graph (notes below). Gaps: `Contexts.window` is still not fed into a host (W11); no key for split/close/retype (the header menu only); viewports share one camera; only bound panels are editable. |
| W11 `.plisp` sketches | todo | | |
| W12 migration & removal | todo | | |

## Notes

- The build needs dune >= 3.21 (`Pdk` re-exports private `Pdk_mesh` modules);
  the repo-local switch has 3.24.2.
- W0 `Rest` slot (landed in W4 part A). The old obstacles were fixed arity
  persisted in documents; presets are workspace text now, so `Rest` is a
  plain factory requirement: `Edit_graph.input_requirement = Required |
  Optional | Rest`, only last, and an entry then holds any number of inputs
  at least the slot count (the first rest input required, the rest
  optional; extras are named `input_2`, `input_3`, ... by `node_slot_names`;
  `connect` one past the last input appends; a disconnected extra is
  skipped; `factory_ready`, `instantiate*`, `add_node`, `rebind_factory`,
  compile and rebuild honour it). `Check.slot` has `rest`, the manifest says
  `(slot "input" rest)`, `sop/merge` declares one rest slot and calls
  `Sop.merge` directly, and the workspace checker's `sop/merge` special case
  is now "has a rest slot". `Check.kind_call` and `Build` accept
  `:input_2` and positional overflow for a rest slot so the `[%flow]`
  text round-trips (test sample with four inputs). `Lower` builds one
  `merge` factory (key `merge`, one rest slot) instead of `flow.merge_n`;
  it stays a local factory only because it writes `__flow_src` through
  `Sop.merge ~source_attribute`, which the editor's merge must not. Not done:
  the legacy flat pane draws a merge with its current inputs only (no
  `+ input` socket); the projection pane edits the text (`Pos n`).
- W0 merge bench (`PRISMEL_PDK_OPS_FILTER=merge_pair PRISMEL_PDK_OPS_REPEATS=7
  dune exec tools/bench_pdk_ops.exe`, 1002001-point grid pair, 8 domains,
  Apple Silicon, median s): `merge_pair` before 0.0211 / 0.0205, after 0.0197 /
  0.0202 (identical output hash and 228.3 MB allocated, so unchanged). New
  `merge_pair_padded` (one input carries a group the other lacks): 0.0281 /
  0.0296.
- W0 set_color: a missing `group` now errors like other group-taking SOPs;
  an empty `group` means all elements.
- W1 part A notes. `Syntax.t` has a sixth field `tail` (comments before a
  closing bracket; comments after the last top-level form join that form's
  `tail` if it is a container, otherwise they are dropped). `Ty.t` also has
  `Color` (the study's `fits` needs it for catalog colour parameters); the
  value-level `coerceD` belongs to `Eval`. `Lisp.print` returns text plus a
  span for every form id (`?mark` is not needed: the map subsumes it) and
  `Lisp.flat` is the one-line spelling for messages. Deliberate differences
  from the study printer: a blank `;` comment line is kept, numbers are
  normalised losslessly (`.5` to `0.5`, `1.` to `1.0`, but `007` and
  `0.0000001` stay), `(quote x)` is a plain call while `'x` is a `Quote`,
  and `^:flag` applies to any form. The 12 fixtures are the study printer's
  canonical text (the study's own sources were not canonical); `prototype/build.cjs`
  injects them as `CASE_SOURCES`, `cases.js` reads them from disk under node;
  `check.cjs` still passes 120/120. The golden layout cases in `test_lisp.ml`
  were generated with the study's `print`.
- W1 part B notes. `Flow.Macro` (`check`, `expand_once`, `expand`, `params`,
  `state`; limits 32 / 5,000 in the messages) and `Flow.Workspace.check`
  (`Check.catalog -> Syntax.t list -> t option * Diagnostic.t list`). Tests:
  `test_macro.ml` (hygiene, unquotes, fresh names, stepping, limits) and
  `test_workspace.ml` (12 fixtures with no diagnostics at all, then one
  positive and one negative case per rule: E_SHADOW, E_FN_ESCAPES,
  E_ACC_TYPE, E_ITER_BOUND, E_MACRO_*, E_NO_ELSE, E_PATTERN, E_INPUT_DEFAULT,
  E_TIME_COUNT, E_TIME_BRANCH, W_UNKNOWN_GROUP, `t` unbindable, liveness
  through binding, capture, fold accumulator, function, defn, ref override and
  macro gensym, loop invariance). The catalog comes from
  `lib/sop_catalog/flow_manifest.sexp` by a dune `deps` (no library
  dependency).
- Deviations from the plan. IR: `Vec` and `List_lit` (no clash with
  `Syntax`), `Op` for built-in operators next to `Call` for catalog kinds,
  `Bypass of term` instead of `Call.bypass`, `Expanded` for a macro call and
  its expansion, `Fn_ref` for a defn/operator name used as a value, `Call_fn`
  arguments in parameter order with defaults filled in, `graph.inputs` carry
  `term option`. `Workspace.context` has `Settings` and `Editor` (the study's
  fixtures need them; `Context.t` gets them in W10), so `E_CONTEXT_PLANNED` is
  not used. Catalog literals are not normalised (`:size 2` stays an int
  literal; `Eval` coerces). `Check` now exports `resolve_kind`,
  `validate_parameter` (callback based), `suggestion` and `short`.
  A colour parameter is a catalog vec3 whose fields end `_r _g _b`; it takes
  `"#rrggbb"` text or a vec3. Group readers/writers are inferred from the
  catalog (`group` parameters read; `name` on `sop/group_*` writes) because
  the manifest carries no markers. `sop/merge` accepts any number of inputs
  and lists (its three slots stay in the manifest, W4 adds the rest slot).
  Liveness of a `defn` body is the union over its call sites.
- Fixtures changed to fit the real catalog (study kernel and case-studies.md
  updated, check.cjs still 120/120): `group_random :ratio` is `:probability`,
  `group_bounds :size [20 20 20]` (soft range), Tree's third rotation is
  `-2.094` (soft range), Variations' bed is a `sop/tube` (the real
  `sop/circle` has `radius_x`/`radius_y`), and Wave uses a new workspace
  operator `sop/curve` (list of vec3 to a polyline) because the catalog's
  `sop/poly_path` takes geometry. W2 must give `sop/curve` a native node.
- W1 part C notes. `Flow.Eval` (`eval.ml`, `eval.mli` documents the plan): values
  are dynamic (`Int`, `Float`, `Bool`, `Text`, `Vec3`, `List`, `Record`, `Geo`,
  `No_geo`, `Struct`, `Fn`, `Residual`); geometry calls become plan nodes keyed
  by `(site, iter)` and never run. `static` evaluates every non-live term once;
  a live term is a `Residual` (the term plus its environment) that
  `residual_eval` / `force` evaluate for a time, memoised per call so a chain
  that reads its predecessor twice stays linear; `run ~time` is both. `t`
  is discovered while evaluating (an exception at the first use of `t` or of a
  residual, caught at the nearest term), not by a separate analysis, so the
  static liveness set of part B is for the canvas and Eval agrees with it by
  construction; the fixtures' plans are identical at every time (test).
  `?record:true` is implemented (bindings, results, zone variables `:x`, `fn`
  parameters, graph inputs; at most 4,096 per path; only instances without
  overrides record, like the study; `defn` bodies record for every call).
  `hash` is specified in iteration.md 2.2 with vectors from the study. `str`
  matches JS `toFixed(4)` including exact ties (0.03125 is 0.0313).
  Bounds at run time: `E_ITER_BOUND`, `E_EVAL_BUDGET` (600,000 steps),
  `E_LIST_RANGE`, `E_PATTERN`, `E_NONFINITE`, `E_RANGE` (`ui/tile`, computed
  split and settings arguments), `E_DEPTH`.
- W1 part C deviations. The study's "only the taken branch runs" and "cond is
  lazy" use a literal `(range 9999)` in the untaken arm; the checker rejects
  that literal statically (L3), so the ports use a graph input. IR types of a
  `fn` body are those of its declared types or `Any` (`float` for arithmetic),
  not refined per call as the study's `types` are. `freeSymbols` (a JS helper
  of the canvas) is the one check.cjs case with no OCaml counterpart. `Eval`
  returns the first error as one `Diagnostic.t`, not a list. `point_list` and
  `piece_list` are not workspace operators yet (W8). A catalog kind used as a
  function value has positional plan arguments named `$0`, `$1`, ... and the
  kind as written. Nodes made by an attempt abandoned because it turned out
  live are dropped, its records are not.
- Wave's `sop/curve`: the catalog has no node that builds a polyline from a
  list of points (`sop/line` is two points from an origin, `sop/poly_path` and
  `sop/join_curves` take geometry, `sop/points` generates points), so
  `sop/curve` stays a workspace operator that `Eval` turns into a plan node
  with a `points` argument; W2 gives it a native node. In Wave the points
  depend on `t`, so each point is a residual inside the list (540 of them): W2b
  must drive a whole list parameter (one residual list) or lower the curve
  live.
- Timings (`Eval.static` / `Eval.run ~time:1.0`, Apple Silicon, one domain,
  mean of 50, plan nodes): Bloom 0.11 / 0.11 ms (84), Sunflower 0.75 / 0.76 ms
  (241), Tiles 0.26 / 0.26 ms (193), Orrery 0.15 / 0.25 ms (55), Wave 3.0 /
  8.6 ms (13; 540 residuals of about a hundred steps each), the rest under
  0.1 ms. Wave is the case to watch in W2b (`residual` environments hold the
  whole scope; no free-variable pruning yet).
- Tests: `test_workspace.ml` (12 fixtures, then 55 check.cjs cases: the static
  half) and `test_workspace_eval.ml` (53 check.cjs cases with values, plus the
  register rules that run: L2, L3, L4, L5, L6, L14, C2, D3, W5 bounds, the
  panel checks, nonfinite math, the hash, residual evaluation, and for every
  fixture: runs, deterministic, unique plan keys, structure independent of
  `t`).
- W2b notes. Landed as listed in `flow-migration.md` "W2b". Deviations:
  `Session.set_volatile` instead of `create ?volatile` (see there);
  `Drive.Live` holds an `Eval.value`; a live list parameter is a
  text-encoded `points` parameter (`Flow_sop.Curve`, lossless hexadecimal
  floats, in the cook key) because `Sop.polyline`'s key was only the point
  count (`Sop.points` has the same latent key; not changed). Each `Lower`
  network is built once with its live drives; `Value_lane` applies the ones
  that changed. Cooking stays bit-identical to the static evaluation at that
  time (test: the symbol `t` replaced by a literal, Orrery, Wave, live
  Sunflower at four times, including going back).
- W2b bench: `dune exec tools/bench_workspace_live.exe -- 600 1` (also `600 3`;
  `BENCH_CASE=wave` filters), Apple M1, 8 cores, 600 frames at 1/60 s, synchronous
  `Async_cook.submit` then `await`, medians (p50) in ms. Cook is the worker's
  Session cook plus prepare; hits/misses are the whole run.

  | case | live args | volatile nodes | resolve | compile | submit | cook | total p50 | total p99 |
  |---|---|---|---|---|---|---|---|---|
  | Orrery | 50 | 52 | 0.41 | 0.11 | 0.004 | 0.31 | 0.91 | 3.2 (1.4 at 3 domains) |
  | Wave | 6 lists (540 residuals) | 13 | 6.61 | 0.07 | 0.007 | 0.49 | 7.27 | 13.3 (8.1 at 3 domains) |
  | Sunflower (static) | 0 | 0 | 0 | 0.07 | 0.001 | 0.19 | 0.26 | 0.38 |
  | Sunflower live `spread` | 240 | 241 | 2.99 | 0.08 | 0.007 | 1.35 | 4.43 | 4.9 |

  Session counters: Orrery 4 static misses then 2,396 hits (599 frames x 4),
  31,200 volatile misses (52 x 600), 0 evictions, retained 4 + 52 slots.
  Orrery meets 60 fps with a large margin (0.9 ms of a 16.7 ms frame); the
  static nodes stay cached. Bottlenecks measured, not guessed: Wave's frame is
  `Eval.force` of its 540 residuals (5.7 ms of the 6.6 ms resolve; a `sample`
  profile of the main thread shows the tree-walking interpreter itself: route
  strings built per subterm, `Hashtbl` memo per residual, string-dispatched
  operators, `Printf` from `string_of_int`), about 10 us per residual of about
  a hundred steps; its cook is 0.5 ms. Sunflower live: `Eval.force` is 0.42 ms
  of the 3.0 ms resolve, the remaining 2.6 ms is 240 `Edit_graph.apply_parameters`
  (about 11 us each), and the cook 1.3 ms. Fixes, when wanted: skip route
  building in live evaluation (routes only key plan nodes) and free-variable
  pruning of residual environments; a batched `apply_parameters` per network.
  Wave is under a frame (7.3 ms) so neither was done. 3 domains changes only
  the cook column slightly (these cooks are small).
- W2b gaps: no UI text (W4/W5); `Cook.update` is not yet fed by a lowered
  workspace in the running editor (W3 makes documents v4; `Lower.objects`,
  `Cook.set_volatile` and `~await:true` are the connection); `Frame.t` does
  not say the clock is fixed, so `Cook.create ?await` defaults to
  `PRISMEL_MAX_FRAMES` being set and `Sketch.export` hosts must pass it;
  `Drive.Live` is not covered by a `test_network.ml` unit test (the lane tests
  run through `Lower`, which needs the catalog, in `test/test_workspace_live.ml`);
  the one-slot volatile cache recooks when scrubbing back (a per-node ring is
  the `ponytail:` fix); live text drives support colour text and choice
  parameters only.
- W3 notes. Documents and presets are s-expressions: one `.plisp` file holds
  the workspace form (comments kept), optional `(layout ...)` keyed by path,
  `(settings ...)` for non-default settings and `(view ...)`; no JSON and no
  older format (the v3 reader and writer, the set_color preset migration and
  `Store`'s preset kind are deleted). Still JSON, and not documents: user
  preferences (`Store.Settings`), the viewport encoders (`Store.Viewport`, an
  in-memory `Yojson` value that `Preset` writes as an s-expression) and build
  glue (`api_stable.json`, generated inventories). Only a workspace document
  saves; sketches opened with `?graph` or `?program` keep the legacy scene
  network and cannot save until W10/W12 give it a text. `Document.workspace`
  holds the `Workspace_doc` and its `Lower.t` (compiled ids and sites), so
  undo restores both; the derived scene and networks feed the old graph pane
  and the cook. The tests that built documents from JSON (`test_editor_document`)
  build them in code now; the preset-format, migration and rejection-matrix
  cases and the fixed-camera preset checks of `test_prismel_editor` (including the
  native look-through framebuffer comparison) are gone with the format. Not ported from the study: `exceptIteration`, `set_layout_ratio`
  (W10). Details: `flow-migration.md` "W3".
- W4 part A notes. `Flow_sop.Projection.of_graph catalog workspace name` (a
  graph, or `"def:name"`) returns a `scope` (`path`, `inputs`, `nodes`,
  `result`). Deviations from the plan's types: it takes the catalog (row
  labels and defaults of a catalog kind are not in the IR); `row.default`
  is text (`string option`; graph defaults are expressions); rows also carry
  `chip` (`No_value | Const | Name | Inline {glyph; text}`); `result` is
  `Link name | Node path | Literal syntax` (the synthetic `@result` node is
  in `nodes`, last); `node` has `ty`, `binds`, `live`, `invariant`,
  `synthetic`. Structure and keys come from the authored syntax, types,
  liveness and invariance from the checker IR. Only a *bound* loop, `let*`
  or `fn` is a zone; an inline one is a chip until unfolded. Rows of a
  built-in operator come from the new `Flow.Workspace.op_signature`; group
  readers/writers from `Workspace.group_reader/writer`; the Flow_edit
  helpers `free_names`, `pat_names`, `pat_key` are exported. Layout:
  `Projection.layout ?at ?collapsed scope` and `place`, the study's
  constants in logical points. Not ported: macro lens sizes (`macroLens`),
  the ghost/probe values (W5). `test/test_projection.ml`: 12 fixtures of
  snapshot counts, row and chip checks on Bloom, Rosette, Kit and Facade,
  Orrery liveness, Sunflower and Tree invariance, layout (no overlaps, zones
  contain children, deterministic, `at`, collapsed).
- What W4 part B must do. Draw `Projection.layout (Projection.of_graph
  catalog workspace graph) ~at ~collapsed` (with `Layout_by_path.at` and
  `collapsed` as the closures): `place` gives absolute boxes, a zone's
  children start at `x + rail_width + 14`, `y + rail_top`. `Pxui_graph` needs
  a projection entry point (a new `Pxui_graph.set_scope` beside the flat
  network), zone backgrounds in `paint_background` with new
  `Pxui.Theme` tokens (`zone_for`, `zone_fold`, `zone_sum`, `zone_fn`; dashed
  hollow for `Fn`), rail and yield rows with the existing row code, the
  iteration selector (`Ui.box`, two buttons, a track, a readout; `Probe_set`,
  view state `Core.probes`), chips (glyphs on `Inline`, scrubbable `Const`),
  output rows from `node.outputs`, stacked and diamond sockets in
  `Theme.ports`, `Zone_collapsed`, and mapping every gesture to
  `Syntax_edit (Flow_edit.op)` with `row.key`: a wire on a row is
  `Connect {node = path; key; src; iter}`, a scrub `Set_arg`, the `Add` row
  `Set_arg`/`Connect` at its key, delete `Disconnect`, the ƒ button
  `Fold_into`/`Unfold`. The `↥` (invariant) and `◷` (live) marks come from
  `node.invariant` / `node.live`. `Doc.syntax_edit` already reduces the
  edit; the projection is rebuilt from `Document.workspace` after each.
- W5 notes. `Flow_sop.Probe` is the UI-free half: `make ?time ?geometry
  eval` (records forced at the time shown, memoised per path, series and
  footer), `describe`, `footer` (value at the probe, sparkline across the
  innermost zone, `then a · else b`, `kept a of b`, `×n`, `↑ same each time`,
  `t`), `counts` (per outer probe: a nested zone counts the iterations of the
  selected outer iteration, not the whole product), `series`, `iterations`,
  `readouts` (the inspector rows), `geometry_targets`. Deviations from the plan:
  `Cook` does not expose `records`; `Core` builds the `Probe.t` from its own
  recording evaluation (`Eval.static ~record:true`, once per checked source,
  kept in `scope_key`) and `Cook` reports geometry counts (`Cook.geometry`,
  `summary`): `Cook.update ?probes` appends up to 64 `(object, compiled node)`
  pairs to the display job's `submit_all` (cache hits, only nodes upstream of the
  display, so a footer cannot fail the display) and returns `Probe.geometry`
  (`prims`, `groups`, `data_id`) per pair; a changed target list forces one
  cheap resubmit. `Eval` now records a live term as its `Residual` (forced by
  the probe at the time shown), and `Eval.instance.default` /
  `Lower.graph.default` mark the graph evaluated with its own inputs: the
  editor showed the last `ref` override of a graph (Bloom's `petals 7`) as its
  object until now, `Document.of_workspace` keeps only the default instance.
  `Projection.counts` moved to `Probe.counts`; `Scope.with_scope` lost
  `~count` (the pane reads the counts from `with_records`). Footers draw at
  zoom >= 0.4, on node cards and collapsed zone cards only (an expanded zone
  has no foot; its header carries the marks and its selector the count).
  `t` stands for ◷ and `↑` for ↥ (DepartureMono). The workspace inspector
  (`Core.workspace_inspector`): value at probe, `cook: live, recooks every frame`
  or `cached`, Move out of the loop, the lowered node's catalog parameters at
  the probed iteration (an edit is `Set_arg` on the authored argument, a
  non-literal argument is locked and shows its expression) and the per-iteration
  list (64 rows, a click is `Probe_set`). The status strip reads
  `t N live · M cached · cook X ms` (`Lower.status`) for a document with live
  nodes. A node added from the menu is selected, and `with_scope` drops a
  selection whose path no longer exists. Tests: `test/test_probe.ml`. Perf
  (`bench_scope_pane`, `tools/bench_workspace_live.exe`; M-series, one run):
  Sunflower pane frame 0.27 ms and 676 KB with no records, 0.44 ms and 985 KB
  with records (first cut 2.4 ms before the series and footer memo and the
  16-segment sparkline cap); Orrery pane frame 0.53 ms without records, 0.86 ms
  with `Probe.make` and the forced footers rebuilt every frame; one recording
  evaluation 0.93 ms (Sunflower) and 0.17 ms (Orrery), only when the checked
  source changes; the idle frame only compares the key. Orrery playback with the
  64 probe nodes added to the cook (`BENCH_PROBES=1 BENCH_CASE=orrery
  ./_build/default/tools/bench_workspace_live.exe 600 1`): total p50 0.79 ms to
  0.93 ms (Session hits, no extra misses).
- W4 part B notes. `Pxui_graph.Scope` is a separate pane module with its own
  `change` type (`Syntax_edit`, `Probe_set`, `Zone_collapsed`, `Selected`,
  `Moved`, `Notice`), not new cases of the flat pane's `change`; `Core` maps
  them. Theme tokens: `Theme.zone_for/fold/sum/fn/let`, `Theme.ports` `text`,
  `fn`, `record`, `Theme.dark`; parity fixture `kit_zones_1x.png` (1x: the
  headless renderer is 1x, the 2x fixtures stay). Iteration counts:
  `Projection.counts` from a recording `Eval.static`. Native check:
  `sketches/flow_workspace` (`FLOW_CASE=bloom|sunflower|orrery`,
  `FLOW_EXPORT=dir` renders the editor to PNG frames by driving a click, `j`
  and `i`): zones, rails, selector, chips, notes, marks and wires draw. Glyph
  fallbacks and perf numbers are in `flow-migration.md`.
- W6 notes. Tags. `__flow_src` is no longer the input index: every collecting
  merge writes `base + input index` where `base` is a running count over the
  inputs of all merges in lowering order (deterministic for one source), and an
  input that already carries the attribute KEEPS its values
  (`Mesh_merge ?source_base`, `Sop.merge ?source_base`). So a merge of merges
  keeps the innermost tag and the ceiling of the plan ("nested merges keep only
  the outermost input") is gone: Bloom's petals resolve to their own iteration
  through two merges. `Lower.provenance` is `origin Int_map.t` keyed by tag
  (`origin = {merge; input; source; site; iter}`), replacing `Origins`. Cost:
  a merge's `base` is in its cook key, so adding inputs to an early merge
  shifts the later merges' bases and recooks them. Pick. `Pdk_prismel.
  Prismel_mesh.to_mesh_with_primitives` (a separate function, not
  `to_mesh ?prim_of_triangle`, because the result type differs) returns the
  triangle to primitive map by tagging primitives with their index before the
  triangulation `to_mesh` does anyway. The editor's pick does not need it:
  `Pick` (`lib/prismel_editor/pick.ml`) builds a `Pdk.Surface_index` on the
  displayed geometry at the first click (kept per piece, lazy) and its hit
  already names the source primitive; the map is what an ID-buffer upgrade
  would use (`ponytail:` in `pick.ml`). Flow. Viewport3 `pick_ray` (screen ray
  of the film rect), `Environment` recognises a left press and release within 4
  points among the events the UI did not consume (handles keep theirs, an orbit
  drag is not a click), `Core.pick` casts the ray against every placed piece in
  its own space, reads the tag, looks up the origin, selects the site node in
  the workspace pane and sets the probe of every enclosing zone to the origin's
  iteration tuple; a miss deselects. Highlight. `Core.lit_tags` (cached by
  selection, probes, lowering and scope) is the set of tags whose origin is the
  selected node at the current probes; `Cook.update ?lit` prepares a piece
  again from its kept `output` with `Pick.tint` (a vertex `Cd`: the lit
  primitives mix 60% toward the theme accent, the rest are scaled by 0.3), only
  when the set changed and only for pieces that carry tags, never recooking or
  lowering. Selecting any merge-input node in the pane lights its iteration too
  (the highlight is a function of selection and probes, not of the click), the
  selectors move it, deselecting restores the original geometry. Tests:
  `test/test_viewport_pick.ml` (triangle map on a triangle, quad and pentagon;
  Sunflower seed 83 and Bloom petal 4 through two merges picked by a ray and
  resolved to `(site, iteration)`; the tint values; one prepare per changed
  highlight, none unchanged, no recook misses; deselect restores physically),
  `test_pdk` (merge tag semantics), `test_workspace_cook` (provenance). Native:
  `sketches/flow_workspace` with `FLOW_PICK="x,y[;x,y]"` clicks the view at
  frames 26 and 32 (`FLOW_CASE=bloom FLOW_PICK="330,300;100,600"`): petal 4 is
  tinted, the rest dim, the selector track sits at 4, the inspector shows its
  transform node, and the miss restores the colours. The sketch got a light and
  a closer camera (the default scene was unlit and black). Bench
  (`dune build test/test_main.exe @test/test_viewport_pick && cd
  _build/default/test && ./test_main.exe bench_viewport_pick`, M-series, one
  domain, ms): Sunflower (8,640 triangles, 240 tags) first pick with the BVH
  build 11, later picks 0.0024, tint 0.65, `to_mesh` 1.3, tint + `to_mesh` 3.9
  (all of it only when the highlight changes); Bloom (3,888 triangles, 23 tags)
  first pick 3.5, pick 0.0016, tint 0.3, `to_mesh` 1.6, tint + `to_mesh` 2.2;
  `Cook.update` with nothing picked or with a highlight held 0.0002-0.0004 ms
  (the same code path; a frame never scales with the scene). Ceilings: the BVH
  build is about 1.3 us per triangle, so a 1M-triangle mesh hitches about a
  second at its first click and the re-prepare runs on the initial domain
  (`ponytail:` move both to the worker or use the ID buffer); instanced pieces
  are not picked; a pick inside a collapsed zone selects the node but the zone
  stays collapsed (expanding it is a layout edit); `Viewport2` never picks.
- W7 notes. `Ui.text_area ui ~at ~w ~h ?readonly ?errors ?spans ?reveal label text`
  returns the edited text. It is `text_field`'s path over lines: the same
  `ui.edit_*` state and `load_text_edit` / `save_text_edit`, the same
  `edit_text_event` (clipboard through `Clipboard`, IME composition and
  `input_region`, Backspace/Delete/arrows); added are Enter (a newline), Up and
  Down (column kept), line-scoped Home/End/Cmd-arrows, Escape leaving, pointer to
  (line, column), the wheel and follow-the-caret scrolling, a line-number gutter
  and error lines. `ponytail:` line starts are recomputed per frame (O(text)),
  only visible lines are drawn, no wrapping and no Tab insertion. Only additive to
  the kit: no parity fixture (the gutter and marks are new pixels outside the
  guarded rows). The pane keeps `Text_pane.state` in `Core.text` (view state, not
  history): tab, the Document draft, the binding draft and the errors of the
  last refused apply. The draft lives there, never in the document; every other
  pane reads the applied document. Selection prints the top-level ancestor of
  the selected binding as a `let*` over the root bindings it needs (a note names
  the count and the graph inputs it reads) with the binding marked from the
  printer's span map, and edits the selected binding's expression (one
  `Set_arg { key = Whole }` through `Doc.syntax_edit`); Document applies
  `Workspace_doc.of_text` with the current layout (keyed by path) and settings
  kept. A refused apply keeps the draft and its errors (line from
  `Diagnostic.position`, else the span), marks the line in the gutter, shows the
  message under the buttons and in the status text while the pane is open.
  Errors persist until the next apply or Discard; a line mark can
  drift while typing (`ponytail:`). Binding-apply errors from the checker carry
  no line (they are checked in the whole workspace). Deleted: `Core.text_pane`,
  `printed_level`, `text_cache`, the qualified-name toggle and j/k text walking;
  the text projection exists only for a workspace graph object, so `Space l` on
  any other document cycles list and graph (tests updated). Tests:
  `test_ui` (text_area: insert, Enter, Up, Home/End, Delete, IME, copy/cut/paste,
  readonly, scrolling, Escape), `test_text_pane` (Sunflower and Bloom closures and
  marks, error lines, then the editor driven through the UI: draft, Discard,
  invalid apply at the right line with the document `==` unchanged, apply, one
  "Edit text" entry, undo and redo labels). Native: `FLOW_TEXT=selection|graph|
  edit|error|binding` on `sketches/flow_workspace`; each tab, a typed edit
  (240 to 60 seeds re-cooked), a refused edit (line 6 marked) and a binding edit
  were read from the PNGs.
- W8 notes. Design and deviations are in `flow-migration.md` "W8". Bench
  (`dune build test/test_main.exe && cd _build/default/test && ./test_main.exe
  bench_workspace_zone`, Apple M1, one domain, one run; a scatter of N points, a
  `for` over them whose body is a `uv_sphere` (element-invariant, built once) and a
  `transform :translate p`, then a merge): with a 16,384-entry session, cold cook /
  recook after point 0 moved / recook misses and hits / allocation: N=100 2.2 ms /
  2.4 ms / 4 and 101 / 0.76 Mwords, N=1,000 28.7 / 25.1 ms / 4 and 1,001 / 8.9
  Mwords, N=4,000 196 / 181 ms / 4 and 4,001 / 53 Mwords. A recook is about as
  slow as a cold cook because expanding (instantiating the varying nodes of every
  element: about 15 us of the 25 us per element at N=1,000, `Edit.instantiate_optional` then
  `Node.apply_parameters`), the merge (2.5 ms) and the session lookups run for every element
  even when every cook is a hit; the win is the elements' cooks and their outputs' identity
  (downstream data ids stay, so nothing after the zone recooks but the merge).
  With the editor's default of 512 entries the same run misses (1,004 misses at N=1,000,
  1 hit): the cache holds fewer entries than the elements need. Per-element cost is not
  linear (45 us at N=4,000 against 25 us at 1,000, not profiled). Ideas, not done: build
  a template node with its parameters in one step, keep the expansion between cooks when
  the collection's points are unchanged, and `Parallel.map_array` over elements once a
  byte-identical test and a bench show a win.
- W9 notes. Details are in `flow-migration.md` "W9". Bypass stays Eval-level:
  `^:bypass` never makes a plan node, so nothing lowered can carry a flag and
  `Edit_graph.set_bypass` remains only the flat pane's; the pane and inspector edit the source.
  The lens panel is part of the card (layout height and width), not an overlay, so the nodes
  below move down; the lens state is view state. `m` now makes a macro (bypass is `b` and the
  `B` flag). Native: a rosette with the lens open on `outer` at step 2, a step click, Replace
  (the call becomes `sop/merge` with a `for` chip), the flag toggling `soft`, `m` over `soft`
  and Create (a `soft_tpl` call), and a typed note (`FLOW_W9`, PNG frames read). A macro
  made from `inner` (a call whose loop variable is a binder) is refused by the checker
  (`E_MACRO_CAPTURE`) and reported in the status strip.

- W10 part A notes (contexts). Lisp spellings are generated from the schemas
  (`Editor_document.Contexts`, one `Flow_sop.Catalog.descriptor` per kind, also written to
  `flow_manifest.sexp` after the sop and value kinds): `scene/geometry`, `scene/light`,
  `scene/camera` (Objects), `world/world`, `world/gradient|sky|sun|shape|scatter|room` (Layers),
  `settings/config` (title, width, height, fps, seed: the new `Contexts.window` record).
  Keywords are schema fields; three consecutive `_x _y _z` / `_r _g _b` floats are one vec3 or
  colour (`:translate [0 1 0]`, `:color "#..."`; a stem that is a field name becomes `p_color`),
  `:name` is the node label. A geometry object's first argument is its `(ref sopgraph ...)`; a
  layer's is the layer below (`world/world` takes the top). `scene/merge` stays a hand op.
  `Context.t` has `Settings`; the checker takes a kind's result type from its context and a
  world kind's slot type is `world`. Eval returns these calls as `Struct`; args are forced at
  `t = 0` (no animated scene values). Ranges are the schema's: literals are check errors,
  computed values clamp like any write. `Document.of_workspace` moved to
  `Contexts.of_workspace` (the old flat path is deleted): without a scene graph it still makes one
  geometry object per sop graph. The workspace owns geometry always, cameras/lights only when its
  scene declares one (else the host's seeded ones stay), the World only with a world graph;
  ids are matched by (operation, label) across rebuilds, params it does not mention keep their
  document value. A settings graph becomes `doc.settings` (workspace schema) and is not written
  as a trailing `(settings ...)` form; inspector edits of it are overwritten on the next edit.
  `Prismel_editor.workspace_catalog` / `workspace_window` are the host's entry points. The
  manifest digest covers only sop and value kinds (the PPX links those). Fixtures: Bloom and
  Variations use the new spellings (`:color` on objects is gone: colour lives in the geometry;
  the prototype HTML no longer runs them). Pane: `Space o` (`Cycle_graph`) cycles scene, world
  and settings graphs; a geometry object shows the sop graph its network was lowered from
  (an override instance shows the graph's defaults), the World its world graph.
  Part B (landed, see its notes) had to: replace `Pxui_shell.Layout` by the layout tree, evaluate `(graph editor ...)`
  (Eval already returns `ui/*` Structs; `Contexts` has no editor lowering, viewports over
  `(ref scene :seed n)` need one scene instance per override: `Contexts.result` only reads the
  default instance), key focus by panel, make the panels of a `for` addressable (E1), keep
  "Restore layout" outside the tree, let `ui/graph` name its graph (then drop `Cycle_graph`),
  feed `Contexts.window` into `Workspace.main` (W11), update `prismel_editor/AGENTS.md`.

- W10 part B notes (shell). The tree type is `Editor_core.Panels` (`panel`, `t`, `path`,
  `default`, `set_ratio`, `valid`, `leaves`; the document library cannot import `pxui_shell`, which
  re-exports it as `Pxui_shell.Layout`).  `Layout.geometry ?hidden tree frame` returns a record
  (`leaves` with `path`, `panel`, `header`, `body`; `splitters`; `status_at`; `timeline_at`), not the
  plan's `(panel * bounds) list`: the header and the path are needed by every caller.  A run of
  splits along one axis is one row of columns, weights being the products of the ratios, so the default
  tree (0.45, then 0.35/0.55) reproduces the retired fixed columns; the old `distribute` (minimum
  widths, hidden columns vanishing, a hidden viewport keeping a 28-point strip, the rounding remainder
  to the last column) is generalised, and `test_shell` holds golden rectangles of the old layout at five
  sizes and states.  One degenerate state differs by one point (300 points wide, graph hidden: float
  weights).  Tiles are a grid of `ceil sqrt n` columns (a short last row stretches), with one-point
  gutters; a `Float` is the parent's rectangle inset by an eighth, drawn last, never a window.  The
  timeline strip stays outside the tree (30 points, hidden until `Space t`) unless the tree has a
  `Timeline` panel.  Dragging a splitter now resizes only the split it belongs to (the columns after it scale
  together), as in the study; the old layout kept the third column fixed.  A drag is `Core.shell.live` until
  release (one `Set_layout_ratio`, "Resize panel"); a document without an editor graph keeps the resized tree
  locally (no history).  The drag targets are built last (`Chrome.splitters`): pane roots created after
  the chrome would cover the seven-point hit area.
  `Contexts.editor` lowers the graph into `Document.shell` (`tree`, `origins`, `named`, `views`): the
  origins walk the checked terms beside the values (a bound panel keeps its binding; a panel in a `for`
  names the loop, register E1; an inline one is not editable), viewport keys are tile indices (`v1.1.2`),
  so a count change keeps the first panels.  A viewport over a scene instance other than the default gets
  objects of its own in the scene network (`garden (v1.1.1)`, listed in `views`, drawn only by that
  viewport); the default instance is the primary scene.  Viewports share one camera and the handles,
  picking and the sketch overlay follow the focused one; picking does not look in another instance.
  `ui/graph` takes an optional graph name, `ui/timeline` is a panel; `Space o` and `Cycle_graph` are gone
  (an `Outline` row picks a graph, `(ui/graph "name")` pins one).  `List` and `Lisp` panels are the graph
  pane's projections drawn on their own (`Space l` cycles them inside `Graph` when there are none); a
  second panel of a kind says it is shown elsewhere.  `Flow_edit` has `Set_layout_ratio`, `Split_panel`,
  `Close_panel`, `Set_panel_kind` (labels "Resize panel", "Split panel", "Close panel", "Retype panel");
  the header right-click menu emits them.  Recovery: `Space z` is "Restore layout" (`Core.shell.restored`, status
  text "Default layout"), and any edit that changes the tree ends it; a refused edit (checker or evaluator error,
  a ratio outside 0.1-0.9) changes nothing, so an invalid editor graph never reaches the editor.
  Two defects found on the way are fixed: a frame with several 3D layers reused the first layer's draws
  (`Native_scene_lowering` cached per frame; regression: `test_workspace_shell_native`), and the workspace graph
  pane painted its grid, zones and wires outside its clip.  `FLOW_CASE=variations` and `FLOW_SHELL=drag|split|close|retype|restore`
  drive the native check in `sketches/flow_workspace`.
