# Phase 5 forbidden dependency/link audit

`tools/phase5_link_audit/phase5_link_audit.exe` is the read-only D2/D3 gate.
It combines `dune describe external-lib-deps --format=sexp` with `otool -L`
over built executables, plugins, shared libraries, and dylibs. Normalized,
sorted, timestamp-free JSON reports dependency/link line counts, the exact
forbidden family, violations, and pass state.

Fixture tests prove a clean SDL3/Metal graph passes, the legacy graph fails
with four exact violations, and `--report-only` preserves violations while
returning success for honest pre-switch evidence collection. The enforcing
mode is required after B5; report-only is not a passing D2/D3 result.

The live pre-switch report on 2026-08-27 inspected 5,835 Dune description
lines and 5,574 artifact/link lines. It found 1,469 normalized violations
(nine dependency-description lines and 1,460 artifact links), so
`passed=false`. This is the expected honest pre-switch failure; built artifacts
may include stale products and must be removed before the eventual two clean
post-switch sweeps.

```sh
dune exec tools/phase5_link_audit/phase5_link_audit.exe > phase5-links.json
dune exec tools/phase5_link_audit/phase5_link_audit.exe -- --report-only \
  > phase5-pre-switch-links.json
```
