# Phase 5 deletion readiness — 2026-08-27

This is a readiness audit, not deletion authorization. The frozen plan defines
only **D1–D8**; there are no authoritative D9–D12 gates. R1–R12 remain the
renderer prerequisites and must all pass before D1 begins. This matrix does not
rename R9–R12 as deletion gates.

| Gate | Current evidence | Readiness / exact blocker |
| --- | --- | --- |
| D1 Source deletion | SDL3, Metal, OGPU, Raster2 and private runtime-next replacements exist side by side. | **Not ready.** Legacy `tsdl_gfx`, SDL2 compatibility, OpenGL renderer, discovery logic and comparison paths are intentionally still present because default selection and R1–R12 are not complete. |
| D2 Textual absence | Dependency-direction gates constrain new foundational edges. | **Not ready.** The frozen `rg` command necessarily has production matches while D1 is undone. Every eventual residual must be listed; no broad textual exemption is approved here. |
| D3 Link absence | New SDL3/Metal compositions have focused link gates. | **Not ready.** Repository executables still link legacy SDL2/OpenGL through the active stack. A complete `dune describe external-lib-deps` plus `otool -L` artifact sweep is absent. |
| D4 Clean dependency install | Binding/build prerequisites are increasingly explicit. | **Not run.** No fresh switch without SDL2 and no final `opam install . --deps-only --with-test --with-doc` artifact is recorded. |
| D5 License and provenance | Metal/SDL generation audits and committed inventory provenance exist. | **Partial.** Final copied/generated-file census, package notices, extension licenses and release artifact review require human sign-off on the selected commit. |
| D6 Documentation | `AGENTS.md`, backend and Phase 4 evidence describe the side-by-side graph. | **Partial.** Documents must be rewritten after the atomic switch; current documents correctly retain legacy as active/selectable and therefore cannot satisfy final-stack wording. |
| D7 Full validation | Focused libraries and many full subsystem suites are green at their commits. | **Not run.** The frozen clean-build command list has not passed twice on one final clean commit; unchanged examples, docs, web, sanitizer, hardware matrix and shattered-cube release evidence remain. |
| D8 No legacy fallback | Typed runtime-next selection exists privately. | **Not ready.** Public/default Runtime still permits and uses legacy behavior. Capability failure policy cannot be certified until the atomic switch removes every old selection path. |

## Preconditions still open

- R1–R8 need the atomic selected Runtime/Prismel application matrix, unchanged
  public API/examples, native tolerance images and final target/resource runs.
- R9 has useful portable structural evidence in `62447a5`, but native Metal
  upload/pass/encoder/FFI counters are still required.
- R10 has local runtime-next release numbers, not the required interleaved
  same-M1 Phase-0 comparison with five warmed 30-second samples per scenario.
- R11 has exact synthetic prepared cardinality/batching, not the actual
  shattered-cube sketch, cook invariants, 835,104 render vertices or native
  visible/hidden residency and pacing.
- R12 has one passing fixed-ring 30-minute SDL-free Raster2/Wap lane in
  `51cc55d` (23,464,561 frames, 1.73% final-window RSS range, zero target/view
  teardown). It still requires separate selected native, headless and web
  long-run qualification with SDL/audio ownership before deletion.
- Fresh-machine packaging, full Xcode offline shader artifacts, sanitizers,
  leak tooling, ray tracing/capability lanes and required human reviewers are
  external release gates.

Deletion must be one atomic, reviewed phase after those prerequisites pass.
No current Phase 4 commit, including `62447a5` or `8648d38`, is deletion-ready.
