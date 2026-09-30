# Workspace implementation progress

Tracks the implementation of [plan.md](plan.md) (PR #1). One row per
milestone; update the row in the same commit that lands the work. Deviations
from the plan and measurements go in the notes under the table and, per plan
§6.6, in `specification/flow-migration.md` under "Workspace".

Status: `todo` · `wip` · `done` (gate met) · `partial` (what is missing is named).

| Milestone | Status | Commit | Notes |
|---|---|---|---|
| W0 fixes & catalog prerequisites | partial | | Merge group padding, set_color group/vec3 colour + v3 migration, `Manifest.version` in text view and the `:rotate` note landed. Not done: the `Rest` slot for `sop/merge` (see notes). |
| W1 language core (`flow`) | done | | `Flow.Syntax`, `Lisp`, `Ty`, `Macro`, `Workspace` (checker, typed IR, liveness, invariance) and `Eval` (values, loops, functions, records, HOFs, `ref`, the geometry plan, `static` / residual split, `?record`); the 12 fixtures check, print, round-trip and run; the check.cjs suite is ported (119 of 120, see the W1 part C notes). |
| W2 lowering & cooking | done | | `Flow_sop.Lower.workspace`, `Pdk.Mesh_merge ?source_attribute`, session default 512, `test_workspace_cook`, `bench_workspace_lower`. Live parameters are only recorded (`Lower.pending`); drives are W2b. |
| W2b live `t` | todo | | |
| W3 document v4 + history | todo | | |
| W4 graph pane zones | todo | | |
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
- W0 deviation: the `Rest` slot was not built. `Edit_graph` entries, presets
  (`preset.ml` arity), `Prismel_editor.Doc`, `Flow_sop` (`Build`, `Catalog`,
  `Manifest`, `Compound_node`) and `Pxui_graph` all assume a slot count fixed
  by the factory, and existing documents hold three-input merges named
  a/b/c. A rest slot needs growing input arrays plus the `+ input` row, so it
  moves to W4; W2 uses the plan's `ponytail:` fallback (one `flow.merge_n`
  node per collected list, since `Sop.merge` takes a list). `sop/merge` keeps
  its three slots and the manifest is unchanged for it.
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
