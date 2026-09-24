# Phase 5 atomic switch preflight

`phase5_atomic_switch_manifest.json` turns the D1–D8 deletion plan into exact
machine-readable deletion/replacement batches, required public modules,
forbidden source/dependency/link names, and historical-text exceptions.

The tool is deliberately read-only:

```sh
dune exec tools/phase5_switch/phase5_switch.exe -- --mode validate
dune exec tools/phase5_switch/phase5_switch.exe -- --mode pre-switch
dune exec tools/phase5_switch/phase5_switch.exe -- --mode post-switch
```

Both stateful preflights refuse a dirty worktree. `pre-switch` requires every
deletion and replacement input to exist and prints cardinalities without
mutating anything. `post-switch` requires deleted paths absent, replacement
owners present, and forbidden production source/dependency text absent. Link,
clean-install, full-suite, performance, long-run, and human license gates remain
external required steps; the tool does not claim them from a source scan.
