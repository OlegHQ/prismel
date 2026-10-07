# Phase 1 close-out and Phase 2 entry: implementation record

## Completion (2026-10-07)

The implementation follows the four recommended decisions below: closed
types/contexts and a second immutable operator list; packed lengths are data;
all frame fields are live; kernel facts remain deferred to Phase 4. The
historical handoff follows this record.

| Requirement | Implementation and runnable evidence |
|---|---|
| Complete live frame | Dependency-free `Frame_input`; `Eval.live` aliases it. `Sketch_support.Live_frame` captures every host event and held key/button before routing. Probes, value lanes, context drives and zone workers receive the same full snapshot. `lib/flow/test_frame.ml` covers accessors, resize/pointer/key changes, events, invalid input, exact float equality and compiled/interpreted agreement. |
| Frame fold | `(state [previous init] step)`, environment-owned `Eval.state`, atomic failure rollback, stable call/iteration identity, idempotence within a frame, backward-seek/reset/stop/reload/export reset. `test_state.ml`, `test_array.ml` and `test/test_probe.ml` cover accumulation, independent exports and read-only probes. A fold outside a geometry loop is captured for pure worker reads; `flow_sop/test_workspace_zone.ml` checks one/three-domain bytes and same-frame reset invalidation. Worker-local folds are explicitly refused as `E_STATE_ELEMENT`. |
| State graph and gestures | `Flow_graph.Projection.State` has seed/previous rails, step cards and next-value feedback; no iteration selector. Existing add-node and `Set_arg (Bv (1, 1))` gestures add it and edit its seed. `flow_graph/test_domain.ml` and `test/test_drawing.ml` exercise both routes. |
| Packed arrays and T2/T3 | Packed finite float/vec3 arrays, constructors, strict access, count/sum, direct packed map/filter/sort/reduce/for/fold/scan/sum. Length is data and can be live or exceed 4,096; graph construction inside packed loops is refused. Structural lists retain the cap and live-count/shape restrictions, including record fields. `lib/flow/test_array.ml` exercises 10,000 elements and deterministic folds. Probe previews retain their separate 4,096-record bound. |
| Phase 2 gate | `examples/particles/sketch.rays` replaces its OCaml program: 10,000 particles, three deferred Drawing nodes. `test/test_drawing.ml` compares positions/bounces to the original model and exports four fixed frames from OCaml and two fresh Lisp sessions; all three PNG sets are byte-identical. The native test runs under `@runtest-native`. |
| Typed deferred nodes and Draw domain | `Value.Deferred (Ty.t, id)`, `Eval.node.ty`, `Ty.Drawing`, `Context.Draw`, nine `draw/*` records in a second `Op` list. Native lowering is `Sketch_support.Drawing`, using existing `Scene`/`Ink` commands. `test_op` sweeps all 83 operators; `flow_graph/test_domain.ml` links no geometry library. |
| Neutral graph boundary | `Projection`, `Flow_edit`, `Exposure` and `Probe` moved from `flow_sop` to `flow_graph` (only `flow`/`param`). `pxui_graph` has no transitive `procedural`/`rdk` dependency; menu entries come from the host. The dependency gate passes with 49 libraries, 50 rules, 15 direct-dependency whitelists and no exceptions. |
| OCaml workspace inputs | `Workspace.run`/`export` and `Editor3.create`/`run` accept `?inputs`; unknown/duplicate/incompatible overrides are typed errors. Inputs survive source edits/reloads and remain host configuration. `test/test_drawing.ml` and context lowering checks cover preservation and rejection. |
| Canvas panels | `(ui/canvas drawing)` with stable leaf identity, pane clipping/translation, docked/floating composition and full-window drawing when UI is hidden. Header retype plus `Space l c`/`Space n c` use checked layout edits. Static pictures are cached once per visible pane/plan/size; frame work does not rebuild unchanged point arrays. `test/test_drawing.ml` checks retype, drawing through `Editor3.scene` and 4-vs-10,000-point frame allocations (both 198,263 bytes/frame); `tools/ui_shot.exe` confirms visible and hidden editor pictures. |
| Architecture/API documentation | `flow.md`, `workspace/iteration.md`, `workspace/ambiguities.md`, `api.md`, `backend.md` and subsystem guides updated. `api_stable.json` accepts the intended API migration and now tracks `frame_input` and `flow_graph`; SOP metadata and `flow_manifest.sexp` are unchanged. |

### Regression and native evidence

Canonical plans, instances, values and records for all 21 existing `.rays`
files and 12 generated workspace fixtures match their baseline at static
evaluation and `0`, `0.125`, `1.25`, `7`. The three custom-catalog files
(gallery, voxel wall and PXUI kit) were compared with their host factories.
Fixture cooks at capacities 32/512, cold plus seven warm cooks, preserve
every geometry hash, retained entry count, eviction count and payload byte.
Completion vocabulary grows; the existing 48-result display cap changes the
first visible page for an empty query without removing older operators.

Evidence from this run lives under `/tmp/rays-migration3-`: `before.snapshot`,
`after.snapshot`, `before-values.snapshot`, `after-values.snapshot`,
`hosts-before.snapshot`, `hosts-after.snapshot`, `before-bench.txt`,
`after-bench.txt`, `ship.log`, `native-check.log`, `doc.log`,
`particles-ui.png` and `particles-hidden.png`. The particle export comparison
also writes `/tmp/rays-drawing-export/{ocaml,lisp-a,lisp-b}`. Frame SHA-256s:

```text
000000 1b1210c53b9e1ba2e776942a61c85516915f31e9a2ccd9978fdf91b0022f72ec
000001 cce3b76eb26ef8d341fa939ba92b593b4d8804e16e0f42f6a6a6e0d555b7ef16
000002 b357b31c3b522dcfdef880c2944d33ee3cc37ad73aaba1a2150104059959b1e5
000003 8c4b773fb0c5d5360b7ce86da20f52eb12010e158ee674dd37f540d980e73073
```

Required shipping command `_build/default/tools/check.exe --ship` passes
(`@all`, `@runtest`, native `@smoke`, `git diff --check`). Focused Flow,
neutral graph, SOP, graph pane and editor tests pass. Native particle exports,
23 SOP one/four-domain PNG comparisons and editor rendering pass. The broader
native run reports a failure in the existing optional runtime teardown
qualification: physical footprint did not plateau. Runtime, scene execution
and Metal source files are unchanged by this migration; that memory
qualification is separate from the required shipping gate.

### Before/after performance

Apple M1, OCaml 5.3.0, Dune dev profile, eight domains available, seven-repeat
medians; fixture cold cook uses one domain. Command:

```sh
_build/default/tools/check.exe tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe _build/default/specification/workspace/cases 7
```

| Fixture | Nodes (unchanged) | Eval ms before → after | Allocated bytes before → after | Lower ms before → after |
|---|---:|---:|---:|---:|
| bloom | 84 | 0.106 → 0.117 | 470760 → 514760 | 3.617 → 3.535 |
| facade | 69 | 0.072 → 0.079 | 291216 → 320128 | 1.701 → 1.737 |
| garland | 40 | 0.070 → 0.075 | 315488 → 347656 | 2.085 → 2.087 |
| kit | 24 | 0.031 → 0.032 | 117880 → 127048 | 0.801 → 0.891 |
| orrery | 56 | 0.137 → 0.147 | 579896 → 627240 | 2.010 → 2.025 |
| rosette | 39 | 0.044 → 0.046 | 179640 → 197592 | 2.398 → 2.027 |
| sunflower | 241 | 0.971 → 0.960 | 3887248 → 4310592 | 10.115 → 10.073 |
| tiles | 193 | 0.318 → 0.360 | 1105008 → 1215384 | 7.263 → 7.177 |
| tree | 27 | 0.018 → 0.019 | 70168 → 74328 | 1.557 → 1.548 |
| tunnel | 37 | 0.021 → 0.022 | 94384 → 101440 | 1.467 → 1.464 |
| variations | 30 | 0.018 → 0.019 | 88064 → 95792 | 0.711 → 0.724 |
| wave | 13 | 3.663 → 4.120 | 15035576 → 16494488 | 5.702 → 5.891 |

The new frame/fold context carries a measurable allocation cost (about
6–11% in these evaluator fixtures); this is recorded rather than described
as an allocation-free change. Geometry retention, evictions, payload and
hashes remain exact. Compilation/IR kernel optimization remains Phase 4.

## Historical handoff

Date: 2026-10-07. Base: `dev` at `629178d1` (one operator registry, done; `MIGRATION2.md`).
Roadmap: "Rays Lisp as a compiled language" (the owner's doc). Phase 0 (`MIGRATION.md`) and
Phase 1 item 1 (`MIGRATION2.md`) are on `dev`. This file is the plan for whoever picks the
roadmap up next: what the two migrations left for later, measured against the code, and the
recommended order. The baseline below predates the implementation recorded above.

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
