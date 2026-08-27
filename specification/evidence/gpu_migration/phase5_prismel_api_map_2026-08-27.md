# Phase 5 Prismel API preservation map — 2026-08-27

The machine authority is `phase5_prismel_api_map.json`; the standalone Dune
gate joins it to the 40 `library=prismel` modules in the frozen
`api_stable.json`. It rejects missing, extra or duplicate modules, unknown
status values, missing target files, empty explanations, direct interfaces that
are not byte-identical, and any change to the exact raw-only omission list.

Current result: **40 = 2 direct + 38 adapted + 0 high-level raw-only**.
`Vec2` and `Vec3` are the first direct SDL2-free facade modules and retain
byte-identical interfaces; their implementation has deterministic arithmetic
and a 100,000-cycle fixture. “Adapted” is deliberately not “complete”: each row
names the concrete next-stack boundary and an exact reason, including pure
modules that still require extraction from the monolithic Prismel library.

Raw-only omissions are tracked separately because they are not members of the
40 stable high-level modules. The nine exact Low omissions are raw renderer,
window, flag, graphics-context, and native record-field escape hatches. No
ordinary Scene, resource, math, input, application, or rendering module is
classified as raw-only.

Validation:

```text
opam exec -- dune build lib/prismel_next_api/test_prismel_next_api.exe \
  tools/gpu_migration/phase5_prismel_api_map.exe
_build/default/lib/prismel_next_api/test_prismel_next_api.exe
_build/default/tools/gpu_migration/phase5_prismel_api_map.exe --root .
```

This staging evidence neither changes `lib/prismel` nor promotes R1/D1/D7.
The 38 adapted rows must become exact direct facades or receive an explicit
reviewed semantic compatibility fixture before the atomic switch.
