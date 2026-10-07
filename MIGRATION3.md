# Phase 1 close-out and Phase 2 entry: handoff

Date: 2026-10-07. Base: `dev` at `629178d1` (one operator registry, done; `MIGRATION2.md`).
Roadmap: "Rays Lisp as a compiled language" (the owner's doc). Phase 0 (`MIGRATION.md`) and
Phase 1 item 1 (`MIGRATION2.md`) are on `dev`. This file is the plan for whoever picks the
roadmap up next: what the two migrations left for later, measured against the code, and the
recommended order. Nothing here is built.

## Where the roadmap stands (measured, `dev` 629178d1)

| Roadmap item | State | What the code shows |
|---|---|---|
| Phase 0: one declaration per SOP | Done, 8ea576b2 | 159 kinds, none declared twice |
| Phase 0: kernel facts in the declaration | Open | `ppx/ppx_rays` has no element-wise, attribute or topology attribute; `Node.t.cook` is an opaque OCaml function; `cook_mode` is declared (`edit_graph.mli:31`, 138 `Duplicate_input` mentions in `lib/procedural`) and never read by the session |
| Phase 1.1: one operator registry | Done, 629178d1 | `Flow.Op.all`, 58 records; `test_op` sweeps them |
| Phase 1.2: open types, contexts, domains | Half done | Dispatch by name prefix is gone. `Ty.t` is still a closed variant of 15 constructors (6 of them context types, `ty.mli`), `Context.t` of 7 (`context.mli`), `Port_type.t` is matched in 12 files |
| Phase 1.3: neutral graph layer | Open, small | `lib/pxui_graph/dune` links `procedural`; only `node_menu.ml`/`.mli` name it (`Edit_graph.factory`). In `lib/flow_sop`, `Projection`, `Flow_edit` and `Probe` reference no `Procedural` module; `catalog`, `curve`, `lower`, `manifest`, `network` and `value_lane` do |
| Phase 1.4: typed deferred node | Open | `Value.t` has `Geo of int \| No_geo`; `Geo` sites: `eval.ml` 6, `lower.ml` 6, `probe.ml` 4, `value.ml` 4 |
| Phase 2: frame record | Open | `Eval.live = { t : float }` (`eval.mli:81`); `Rays.Frame.t` already carries `width`, `height`, `dt`, `time`, pointer and events (`frame.mli`) |
| Phase 2: state as a fold over frames | Open | No form. `Flow_sop.Value_lane` keeps previous values in the environment, which is the home the roadmap names |
| Phase 2: packed arrays, no per-zone cap | Open | `Op.max_iterations = 4096` (`op.ml:20`), read at `op.ml:94` and `workspace.ml:672`; `E_TIME_COUNT` (T2) guarded at `test_workspace.ml:231` |
| Gap: OCaml inputs to a workspace | Open | `Lower.workspace` takes `inputs` (`lower.mli:63`); `lib/rays_editor` passes it 0 times |
| Gap: panels are closed | Open | `Panels.panel` has 7 kinds (`panels.mli:5`); no canvas kind |

## What the registry changed for the items above

Everything the roadmap wants next adds operators, and an operator is now one record in
`lib/flow/op.ml`. Concretely:

- `frame/dt`, `frame/index`, `pointer/x`, `key/down`, `state/prev` and the whole `draw/*`
  domain are records in a list; `Op.all = value @ sop @ scene @ ... @ draw`. No checker arm,
  no evaluator arm, no editor list to edit. `test_op` sweeps the new records for free.
- A new `Ty.t` constructor (`Drawing`) and a new `Context.t` (`Draw`) are still one constructor
  each in two closed variants. The prefix dispatch that made this painful is gone; the 33 `Ty.t`
  and 15 `Context.t` match sites remain and the compiler lists them. Do not open the variants
  for one new type (`MIGRATION2.md`, "Skipped on purpose").
- `Struct` stores its resolved `Ty.t`, so a `draw/*` struct needs no catalog lookup to type.
- Packed arrays touch `Op.max_iterations`, not `Workspace`: the cap moved with the registry.

## Recommended order

The roadmap's Phase 1 gate is "a toy domain registers without editing `lib/flow`". Read
literally it asks for an open registry and open variants before any visible result. Recommended
reading: the gate is met when the 2D draw domain is a second `Op` list and one constructor each
in `Ty.t` and `Context.t`, which is the measured cost today. So the order is:

1. **Frame record** (Phase 2, item 1). `Eval.live` becomes `{ t; dt; frame; size; pointer;
   keys; events }`, filled from `Rays.Frame.t` by the host and by `Sketch.Fixed dt` for
   exports. Operators `frame/dt`, `frame/index`, `frame/width`, `frame/height`, `pointer/x`,
   `pointer/y`, `pointer/down`, `key/down` are `Op` records with `ctx = Value`. Liveness: every
   field is live, like `t`. Sites: `eval.mli:81`, `residual_eval`/`force` (`eval.mli:116-119`),
   `Value_lane`, `Probe`, `bench_workspace_lower`, `test_workspace_eval`'s times, and
   `Core_host` where it builds `live`.
2. **State** (Phase 2, item 2). One form, `(state [s init] step)`, where `step` sees the
   previous `s` and the frame record. Reference semantics: a fold over frames, previous value
   kept in the value lane, reset by `Sketch.Fixed` exports and by a document reload. Ships with
   its graph projection and `Flow_edit` gesture, per `AGENTS.md`.
3. **Packed arrays** (Phase 2, item 3). A `Value` constructor for a typed float/vec3 array
   whose length is data, exempt from `Op.max_iterations`, with `map`/`fold`/`sum` over it and
   the T2/T3 amendment from the roadmap's decision 2. `E_TIME_COUNT` stays for graph structure.
   Gate for Phase 2: `examples/particles` runs as a `.rays` file and a fixed-step export
   reproduces byte for byte.
4. **Typed deferred node** (Phase 1, item 4), together with the first `Drawing` value: replace
   `Geo of int` by a deferred node tagged with its `Ty.t`, 20 sites.
5. **Neutral graph layer** (Phase 1, item 3): drop `procedural` from `lib/pxui_graph/dune`,
   move `Edit_graph.factory` behind a function the host passes, add the gate rule
   `pxui_graph` → never `procedural` in `test/dependency_gate.ml`, and update
   `specification/backend.md`. Do this when Phase 3 needs the pane without the geometry stack.
6. **Kernel facts** (Phase 0's open half): defer to Phase 4 entry. Nothing before the IR reads
   them, and `cook_mode` is already an unread declaration of the same kind.

## No regression (same contract as `MIGRATION2.md`)

- Every checked-in `.rays` evaluates to the same plan and records at `0`, `0.125`, `1.25`
  and `7`; `bench_workspace_lower _build/default/specification/workspace/cases 7` reports
  unchanged node counts, retention, payload and cook hash. Record before/after medians.
- `test_op`'s 58-record sweep stays green and grows with each new record.
- Bit-exact `value/rand` hashes and the compiled-residual comparison stay as they are.
- `flow_manifest.sexp` changes only when SOP metadata changes; accept with `dune promote`.
- `api_stable.json`: promote once per step, not per edit.
- Final check is `_build/default/tools/check.exe --ship` from a console session with Metal
  access; an SSH/tmux process cannot run `@smoke` (`MIGRATION2.md`).

## Decisions needed (owner)

1. **Phase 1 gate reading.** Literal (open registry, open variants, toy domain) or the measured
   reading above (second `Op` list plus one constructor each). Recommended: measured.
2. **Packed array length is data.** Roadmap decision 2 amends T2/T3. Recommended: yes; a
   particle count is data, the number of cards is structure.
3. **Which frame fields are live.** Recommended: all of them; a canvas size that changes on
   resize is as live as `t`, and the export path pins every field.
4. **Kernel facts wait for Phase 4.** Recommended: yes.

## Skipped on purpose

- Everything under `MIGRATION2.md`'s "Skipped on purpose" still holds: no `Op.register`, no
  opened variants, no PPX-derived operator records, no generated operator list in
  `specification/flow.md`.
- A second evaluator for 2D, user shader text, recursion or `while`: the roadmap's "what not
  to build" list.
- Per-phase timers and `cook_mode` reading: Phase 4, with the cost model.
