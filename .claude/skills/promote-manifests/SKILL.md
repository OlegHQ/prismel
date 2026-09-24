---
name: promote-manifests
description: Accept an intended public API change in prismel. Use when runtest shows a diff of tools/api_manifest/api_stable.json after editing a public .mli.
---

1. `dune build @tools/api_manifest/runtest 2>&1 | grep '"source"'` lists the
   changed modules. Confirm each one is a change you meant.
2. `dune promote`, then rerun step 1: it must print nothing.
3. Summarize the public API change (module, what changed) in your handoff and
   update `specification/api.md` if the high-level design moved.
