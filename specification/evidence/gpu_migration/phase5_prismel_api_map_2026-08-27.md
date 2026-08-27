# Phase 5 Prismel API preservation map — 2026-08-27

The machine authority is `phase5_prismel_api_map.json`; the standalone Dune
gate joins it to the 40 `library=prismel` modules in the frozen
`api_stable.json`. It rejects missing, extra or duplicate modules, unknown
status values, missing target files, empty explanations, direct interfaces that
are not byte-identical, and any change to the exact raw-only omission list.

Current result: **40/40 = 20 direct + 20 implemented**, with **zero pending
adapted** and **zero high-level raw-only** modules. Direct modules retain
byte-identical interfaces. Every implemented module maps to a compiled public
`prismel_next_api` interface and an explicit semantic fixture checked by the
machine gate.

Raw-only omissions are tracked separately because they are not members of the
40 stable high-level modules. The nine exact Low omissions are raw renderer,
window, flag, graphics-context, and native record-field escape hatches. The two
reviewed target-neutral adaptations are `Low.App.get_renderer` and
`Low.Backend.present`. No
ordinary Scene, resource, math, input, application, or rendering module is
classified as raw-only.

Validation:

```text
opam exec -- dune build lib/prismel_next_api/test_prismel_next_api.exe \
  tools/gpu_migration/phase5_prismel_api_map.exe
_build/default/lib/prismel_next_api/test_prismel_next_api.exe
_build/default/tools/gpu_migration/phase5_prismel_api_map.exe --root .
```

This staging evidence neither changes `lib/prismel` nor performs the atomic
owner switch. It proves the facade preservation prerequisite: 100% of the 40
frozen high-level modules are direct or implemented with semantic fixtures.
