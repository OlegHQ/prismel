# Workspace implementation progress

Tracks the implementation of [plan.md](plan.md) (PR #1). One row per
milestone; update the row in the same commit that lands the work. Deviations
from the plan and measurements go in the notes under the table and, per plan
§6.6, in `specification/flow-migration.md` under "Workspace".

Status: `todo` · `wip` · `done` (gate met) · `partial` (what is missing is named).

| Milestone | Status | Commit | Notes |
|---|---|---|---|
| W0 fixes & catalog prerequisites | partial | | Merge group padding, set_color group/vec3 colour + v3 migration, `Manifest.version` in text view and the `:rotate` note landed. Not done: the `Rest` slot for `sop/merge` (see notes). |
| W1 language core (`flow`) | wip | | Parts A and B done: `Flow.Syntax`, `Flow.Lisp`, `Flow.Ty`, `Flow.Macro`, `Flow.Workspace` (checker, typed IR, liveness, invariance) and the 12 fixtures, which check with no diagnostics against the real catalog. Left for part C: `Flow.Eval`, the 120 check.cjs cases ported (static ones can use `test_workspace.ml`'s `good`/`bad`), `test_workspace_eval.ml`, flow.md §11 pointer, iteration.md §2/§7 status line. See the W1 part A and B notes. |
| W2 lowering & cooking | todo | | |
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
- Left for part C (Eval time): driven counts over 4,096 (`range`, loops, `concat`
  over 4,096 elements), the step budget, `first`/`nth` out of range, list
  lengths that are not literals (D3 length errors), nonfinite math, `ui/tile`
  panel count, `settings/config` and `ui/split` arguments that are not
  literals. `Workspace` only bounds literal `range`/`linspace`/`list` counts
  and their products. Part C reads `Workspace.t` (`graphs`, `defs`, terms with
  `path` and `form`) and `live` / `invariant`.
