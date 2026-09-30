# Workspace implementation progress

Tracks the implementation of [plan.md](plan.md) (PR #1). One row per
milestone; update the row in the same commit that lands the work. Deviations
from the plan and measurements go in the notes under the table and, per plan
§6.6, in `specification/flow-migration.md` under "Workspace".

Status: `todo` · `wip` · `done` (gate met) · `partial` (what is missing is named).

| Milestone | Status | Commit | Notes |
|---|---|---|---|
| W0 fixes & catalog prerequisites | partial | | Merge group padding, set_color group/vec3 colour + v3 migration, `Manifest.version` in text view and the `:rotate` note landed. Not done: the `Rest` slot for `sop/merge` (see notes). |
| W1 language core (`flow`) | todo | | |
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
