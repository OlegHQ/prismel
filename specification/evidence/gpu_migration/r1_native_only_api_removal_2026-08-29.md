# R1 native-only API removal review — 2026-08-29

Commit `5249472` removed the one-constructor `Sketch.render_target` compatibility
surface as part of the native-only runtime cutover. This is an intentional
public contraction authorized by `NEW_GPU_STUFF.md`: the former headless/web
contract and every render-target selector must be absent, rather than retained
as a fake `Native` choice.

The reviewed `Sketch` interface delta removes only:

```ocaml
type render_target = Native
val render_target : render_target
```

`Sketch.run`, `run_state`, `run_assets`, `export`, `resize`, configuration,
resource cleanup, and finite-run behavior are unchanged. Native startup failure
continues to cross the existing typed runtime error boundary; no alternate
renderer is selected.

The stable manifest was regenerated explicitly after review:

```sh
opam exec --switch=. -- dune exec \
  tools/gpu_migration/api_manifest.exe -- --root . --write
opam exec --switch=. -- dune exec \
  tools/gpu_migration/api_manifest.exe -- --root . --check
```

The manifest still contains 127 stable modules. Only `prismel.Sketch` changed
semantic API hash, from
`d9a1627d2abdccf2c2c160c63e280f5731fde2fb32cb27e70ed9201aa811075a` to
`315ce1c8c391ab77f5980eb1643d8748ef2c2a1c97f859f2537c5458d7231280`.
The `prismel.Texture` source digest was refreshed because of an earlier
comment/source-only change; its semantic API hash remained byte-identical.

This record reviews only the required native-only contraction. It does not
waive any other R1 compatibility delta or replace the final clean manifest
check.
