---
name: prune-dead-code
description: Delete unreferenced code in prismel with the compiler-driven codemod (tools/codemod) - exports nothing uses, test-only features, dead Metal bindings and stubs - to a fixpoint, instead of hand-editing. Use after removing a feature or caller, or when auditing a library for dead code.
---

# Prune dead code with tools/codemod

The compiler is the oracle: the tool resolves every identifier in the
`_build` `.cmt` files to its definition through compiler shapes, drops what no
other file references, rebuilds, and deletes whatever the compiler then
flags unused, until nothing changes. Builds use `--profile codemod` (the dev
warnings plus unused modules).

```sh
eval "$(opam env --switch=. --set-switch)"
dune build @check                      # fresh .cmt files first
dune exec tools/codemod/codemod.exe -- dead-exports lib/<name>     # report only
dune exec tools/codemod/codemod.exe -- prune lib/<name> [lib/<other> ...]
```

- `--users-exclude SUBSTR` (repeatable): references from matching files do not
  count, e.g. `--users-exclude lib/metal/test_` finds what only tests use.
- `--modules`: a submodule whose values are all dead goes as a unit (kept, with
  its values dropped, while a type or live value still names it).
- `--cut-tests`: a test that stops compiling is removed (its top-level item, or
  the failing statement inside `run`/`let () =`). Cutting a statement can leave
  an assertion whose setup is gone: run the tests and repair.
- Metal: after pruning `lib/metal`, run
  `codemod.exe -- dead-stubs lib/metal/metal_bridge.mm lib tools test` and
  `codemod.exe -- drop-c-unused lib/metal` (clang's unused-function errors as
  the oracle); unused registry entries are dropped during `prune`.

## Rules

- Only prune libraries whose exports are internal. For user-facing APIs
  (`prismel`, `pxui`, `procedural`, `prismel_pathtracer`, `prismel_editor`,
  `prismel_math`) list with `dead-exports` and decide by hand: unused is not
  unwanted there.
- Unused `let x = e in` locals are deleted; check the printed `26 ...` lines
  when `e` could have a side effect. Unused parameters become `_x` / `~x:_`
  (listed as `27 ...`); remove them with their arguments by hand.
- Records or variants left with only dead fields/constructors are marked
  `[@@warning "-69"]` / `[@@warning "-37"]`: delete those types by hand.
- The loop stops on a hard error and prints it; fix it and rerun. Review the
  diff, then `dune build @all`, window-free `runtest`, promote the API
  manifest if a public `.mli` changed, and commit the prune on its own.
