# Workspace implementation progress

Tracks the implementation of [plan.md](plan.md) (PR #1). One row per
milestone; update the row in the same commit that lands the work. Deviations
from the plan and measurements go in the notes under the table and, per plan
§6.6, in `specification/flow-migration.md` under "Workspace".

Status: `todo` · `wip` · `done` (gate met) · `partial` (what is missing is named).

| Milestone | Status | Commit | Notes |
|---|---|---|---|
| W0 fixes & catalog prerequisites | partial | | Merge group padding, set_color group/vec3 colour + v3 migration, `Manifest.version` in text view and the `:rotate` note landed. Not done: the `Rest` slot for `sop/merge` (see notes). |
| W1 language core (`flow`) | wip | | Part A done: `Flow.Syntax`, `Flow.Lisp`, `Flow.Ty`, the 12 fixtures in `cases/` (single source for study and OCaml tests) and their tests. Left for part B: `Flow.Macro` and `Flow.Workspace` (checker/IR, rules and limits from the plan). Left for part C: `Flow.Eval`, `test_workspace.ml` (the 120 check.cjs cases, one positive and one negative test per proposed register rule, macro hygiene), `test_workspace_eval.ml`, flow.md §11 pointer, iteration.md §2/§7 status line. See the W1 part A notes. |
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
