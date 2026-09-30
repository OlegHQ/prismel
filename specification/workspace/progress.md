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
| W4 graph pane zones | done | | Part A (`Flow_sop.Projection`, `Rest`) and part B (`Pxui_graph.Scope`, zone tokens, selectors, `Core` wiring, layout by path, probes); see the W4 part B notes and `flow-migration.md`. Gaps: no marquee, the inspector still shows the lowered object, the flat pane remains for non-workspace documents, only `sop` graphs open. |
| W5 probes & footers | todo | | |
| W6 viewport provenance | todo | | |
| W7 editable text | todo | | |
| W8 loops over geometry | todo | | |
| W9 macros UI, notes, bypass | todo | | |
| W10 contexts & composable shell | todo | | |
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
