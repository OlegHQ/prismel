# Phase 5 Prismel public-owner candidate — 2026-08-27

`tools/phase5_switch/prismel_owner_candidate.dune` is a non-live, generated
candidate for the B5 ownership flip. It is deliberately outside
`lib/prismel_next_api`; validation does not change either current public
library owner.

The candidate proves the following current facts:

- the future library has both `(name prismel)` and `(public_name prismel)`;
- all 40 modules in the frozen preservation map have staged `.ml` and `.mli`
  files;
- the two implementation-only Raster2 lowering/resource modules exist and are
  explicitly private;
- its seven dependencies contain neither `prismel`, `prismel_next_api`, old
  `runtime`, nor any legacy SDL2 library;
- the nine sibling libraries that currently consume `prismel` continue to
  resolve that unchanged public name; and
- no such sibling currently co-links `prismel_next_api` or old `runtime`.

The exact sibling set is `geom`, `pdk`, `prismel_runtime_next`, `procedural`,
`pxui`, `pxui_graph`, `sketch`, `sketch_ui`, and `sop_catalog`. The checker
parses only Dune `libraries` fields, avoiding false ownership conclusions from
package prefixes, test fixtures, or historical dependency paths.

Reproduce with:

```sh
opam exec -- dune build tools/phase5_switch/test_prismel_owner_candidate.exe
_build/default/tools/phase5_switch/test_prismel_owner_candidate.exe \
  --root . \
  --candidate tools/phase5_switch/prismel_owner_candidate.dune \
  --map specification/evidence/gpu_migration/phase5_prismel_api_map.json
```

Expected result:

```text
B5 Prismel owner candidate passed: name/public_name prismel, 40 public + 2 private modules, 7 dependencies, 9 sibling consumers, no legacy co-link
```

This is switch preparation, not authorization or evidence that the deletion
has happened. The old owners must be deleted in the reviewed atomic B5 batch
before this candidate can become live; Dune must never see both libraries
claiming `prismel` in one workspace.
