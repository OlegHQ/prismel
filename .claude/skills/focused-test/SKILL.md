---
name: focused-test
description: Run only the tests for the code you touched in prismel. Use after editing a file under lib/, tools/ or test/ when you want a fast pass/fail instead of the full runtest.
---

1. `eval "$(opam env --switch=. --set-switch)"`.
2. Map the edited path to its directory: `lib/<name>/…` → `lib/<name>`; a
   file under `test/` → `test`.
3. `dune build @check 2>&1 | head -40`: fix type errors first. `@check` also
   reports pre-existing `tools/` .cmi noise; ignore lines outside your paths.
4. `dune build @<dir>/runtest 2>&1 | grep -E '^File|Fatal|rror' -A4 | head -40`.
5. A green default `runtest` is the baseline, so any failure here is yours.
   Tests under `@runtest-native` / `@qualification` are known-red on some
   machines; run them only when your change touches them.
6. If a public `.mli` changed, also run `dune build @tools/api_manifest/runtest`
   and use the promote-manifests skill.
