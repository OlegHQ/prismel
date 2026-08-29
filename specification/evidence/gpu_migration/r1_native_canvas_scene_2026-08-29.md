# R1 native Canvas/Scene API review — 2026-08-29

Reviewed against production commit
`03c534dfe703e4e5d730b1f344dd4c1411aed6b5` at
`2026-08-29T14:44:36+02:00`.

The stable-manifest gate reported exactly two changed modules and no added or
removed stable modules:

- `prismel.Canvas` restores the pre-migration `Canvas.render : t -> Scene.t ->
  unit` operation on a layerless native Metal target. Its new `Private` native
  statistics are additive qualification hooks; no public Canvas operation was
  removed.
- `prismel.Scene` adds only `Private.native_layer` and the `clear`/`layers`
  fields used to preserve ordered Scene2/Scene3 native composition. Public
  scene constructors and `Scene.render` are unchanged.

The generated manifest still contains 127 stable native modules. Regeneration
changed only the Canvas and Scene API/source hashes. The following check passes:

```sh
opam exec --switch=. -- dune exec tools/gpu_migration/api_manifest.exe -- \
  --root . --check
```

This is an intentional additive/private boundary review, not authorization for
an unrelated high-level API contraction. R1 remains provisional until the
final installed-consumer and twice-clean release qualification run.
