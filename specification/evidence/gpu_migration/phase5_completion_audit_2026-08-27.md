# Phase 5 completion audit — 2026-08-27

Captured at `2026-08-27T19:37:24Z` on commit
`2c32b7ee5affe8dd635dba2ad77f8c0fda0b60ef`. This is a mechanical readiness
ledger, not deletion authorization. `NEW_GPU_STUFF.md` remains the authority.

Status has one strict meaning:

- **Proven**: the complete frozen gate has committed evidence; a focused or
  private precursor is insufficient.
- **Pending**: repository work or a final integrated rerun remains.
- **External**: the remaining decisive evidence needs unavailable hardware,
  toolchain, clean-host state, or independent human review. An external row is
  not waived or counted complete.

## Exact gate denominator and completion

The frozen definition of done names exactly **47 equally weighted gates**:
S1–S8 (8), M1–M10 (10), O1–O9 (9), R1–R12 (12), and D1–D8 (8).
At this checkpoint: **11 Proven, 27 Pending, 9 External**. Strict completion is
therefore **11 / 47 = 23.40%**. Excluding external rows only as a scheduling
view (never as release completion), locally closed coverage is
**11 / 38 = 28.95%**.

The wall-clock rate is reproducible rather than an estimate of human effort.
The Phase-0 baseline commit `4622091a65bc9a8816a1f10bcc83c1a625ca7522`
is dated `2026-08-22T12:34:54Z`; this capture is 127.04 hours later. Eleven
strict gates over that interval are **0.0866 gates/hour**, or **4.42 percentage
points/day** of the 47-gate denominator. The interval contains 1,344 commits
and parallel work, so it must not be extrapolated as an ETA.

## S1–S8: SDL3

Evidence authority: `phase1_sdl3_audit_2026-08-27.md` and
`phase1_sdl3.json`.

| Gate | Status | Exact evidence or blocker |
| --- | --- | --- |
| S1 version/provenance | Proven | Four pinned inventories, linked-version and drift gates are green. |
| S2 API/ABI completeness | Proven | Zero unreviewed declarations plus compiled ABI/layout assertions. |
| S3 ownership/error safety | Proven | Failure/stress, 100,000-cycle lifecycle and recorded sanitizer/leak lanes. Renewal is required after ownership changes but does not erase the qualified gate. |
| S4 event fidelity | Proven | Exact typed 33-event trace and platform translation fixture. |
| S5 domain/callback safety | Proven | Initial-domain rejection and runtime-lock callback policy tests. |
| S6 DPI/window lifecycle | Proven | Real Metal/Retina lifecycle plus dummy 100,000-cycle fixture. |
| S7 extension parity | Proven | Image, TTF and mixer inventories and malformed/lifecycle coverage. |
| S8 packaging | Proven | Conf packages, discovery, installed consumer and recorded clean bootstrap. Final D4 is separately open. |

## M1–M10: Metal

Evidence authority: `phase2_metal_gate_matrix_2026-08-27.md`,
`metal_completion_audit_2026-08-27.md`, and the exact inventory/provenance.

| Gate | Status | Exact evidence or blocker |
| --- | --- | --- |
| M1 inventory | Proven | 5,286 declarations: 5,248 bound, 37 scoped exclusions, one availability gate, zero unreviewed. |
| M2 ownership | Pending | `2e013c0` passes twelve current-M1 10k ownership lanes with zero Leaks, but the complete conformance process still reports 2,976 bytes in 22 AGX/dispatch/OCaml roots and the external sanitizer matrix remains. |
| M3 resources | Pending | `2e013c0` adds a requirement-indexed supported-M1 resource matrix and atomic rejection, but alternate supported-device/OS coverage remains incomplete. |
| M4 pipelines/shaders | External | Full-Xcode offline metallib build and runtime/offline image parity require unavailable tools. |
| M5 commands/sync | Pending | `2e013c0` covers three drawable slots, resize-invalidated snapshots, occlusion/timeout/loss, injected failures and real-M1 completion retention; the full frozen device/toolchain matrix remains. |
| M6 presentation | Pending | `2e013c0` proves 10,000-frame zero-handle presentation and settled local RSS, but complete minimize/restore/window-server and external diagnostics remain. |
| M7 ray tracing | External | Deterministic M1 compute query is green; missing-RT rollback and M3+ render lane remain. |
| M8 Metal4/MetalFX | External | M1 typed rejection is covered; M3+ and weak-linked MetalFX presence/absence matrix remains. |
| M9 FFI performance | Pending | Tooling/baseline exists; final ABI release rerun against the frozen threshold remains. |
| M10 tooling | External | Full Xcode shaders, GPU capture/counters, validation, ASan/UBSan/TSan and Guard Malloc/Leaks suite remains. |

## O1–O9: OGPU

Evidence authority: `phase3_ogpu_progress_2026-08-27.md`.

| Gate | Status | Exact evidence or blocker |
| --- | --- | --- |
| O1 backend independence | Proven | Dependency gate proves generic OGPU has no framework edge and rejects injected reverse edges. |
| O2 handle/state safety | Pending | `0e5d366` integrates generational/linear/deferred-release rejection through mock, Raster2 and the final facade; it explicitly omits native GPU/driver qualification. |
| O3 descriptor validation | Proven | Exhaustive 1,920 format/storage/sample/usage combinations and pre-allocation validation. |
| O4 capability truthfulness | External | Software profiles and M1 agree; M3+ execution remains unavailable. |
| O5 synchronization | Pending | `0e5d366` adds final-facade render integration for portable fences/deferred release; native driver synchronization remains. |
| O6 lifetime/bounds | Pending | 100,000-cycle plateaus exist; integrated external-duration RSS qualification remains. |
| O7 surface contract | Pending | Resize invalidation, timeout and loss reach final-facade headless/web paths in `0e5d366`; native selected-Runtime matrix remains. |
| O8 native extension | External | Pointer-free boundary and M1 compute pass; RT-capable acceleration composition remains. |
| O9 determinism | Pending | `0e5d366` proves exact one/four-domain mock/Raster2/facade ordering; native renderer work-stealing integration remains. |

## R1–R12: renderer prerequisites

Evidence authority: `phase4_raster2_audit_2026-08-27.md`,
`runtime_next_native_m1_qualification_2026-08-27.md`,
`runtime_next_target_stability_2026-08-27.md`, `phase5_final_facade`, and the
R10/R11/R12 reports and protocols through `2c32b7e`.

| Gate | Status | Exact evidence or blocker |
| --- | --- | --- |
| R1 stable API | Pending | The exact 40-module map, installed consumer and typed Low delta are green through `0d4a868`; the facade is still staged and the atomic selected-commit freeze rerun remains. |
| R2 Scene2/PXUI | Pending | `d31dba3` proves public headless/web Basic/PXUI-like exact 1/2/60/600 hashes; native and unchanged selected-example acceptance remain. |
| R3 Scene3 | Pending | Topology/state/shading/multi-shadow private native parity is green through `20e03d0`; final selected/hardware matrix remains. |
| R4 resources | Pending | Public watched Image, density Text, Canvas, Assets and Audio fixtures plus headless/web facade lowering exist; final selected native/cross-target example lifecycle remains. |
| R5 targets | Pending | Public headless/web facade compositions are exact and native staging exists; public/default Runtime is not switched. |
| R6 coordinates/DPI | Pending | Typed logical/drawable/Retina fixtures exist; final real browser/mobile and selected-native capture remain. |
| R7 deterministic pixels | Pending | Software exactness and M1 tolerance evidence exist; final required hardware matrix remains. |
| R8 multi-frame | Pending | Public final-facade 1/2/60/600 fixtures are green; unchanged selected native example/sketch matrix remains. |
| R9 upload/batching | Pending | Stable portable counters exist; final native Metal upload/encoder/FFI evidence remains. |
| R10 performance | Pending | Full `db9a6f5` execution completed, but its cross-target totals compared non-equivalent synthetic workloads and unpaced web frame counts, so its regression conclusions are invalid rather than a pass or actionable failure. `3d8c8b0` normalizes pacing/per-frame metrics and `2f70461`/`b351826` define canonical Scene3 equivalence; the complete superseding five-round run remains. |
| R11 shattered cube | Pending | `bf61858` passes five visible and five hidden 30-second real-M1 runs with exact artifact/cook identity, one upload and bounded cache, but GPU counters are null, process cleanliness was not captured, and R10's common envelope is not yet valid. |
| R12 stability | Pending | Earlier native and headless/web 30-minute component lanes pass. `2c32b7e` adds the public-facade three-target, four-scenario fixed-ring protocol, but only its 600-frame headless/web smoke has run; native/headless/web 30-minute final-facade reports remain. |

## D1–D8: deletion/release

Evidence authority: `phase5_deletion_readiness_2026-08-27.md` and B0 freeze
`bf30654`.

| Gate | Status | Exact evidence or blocker |
| --- | --- | --- |
| D1 source deletion | Pending | Exact deletion batches are mapped; no deletion is authorized before R1–R12. |
| D2 textual absence | Pending | Current 64-file legacy-reference census is classified; production matches intentionally remain. |
| D3 link absence | Pending | Current 288-artifact legacy linkage baseline exists; post-deletion clean sweep remains. |
| D4 clean install | External | Fresh switch with SDL2 absent and complete opam install has not run. |
| D5 license/provenance | External | Inventories exist; final artifact census and independent license sign-off remain. |
| D6 documentation | Pending | Side-by-side docs are accurate; final-stack rewrite must follow the atomic switch. |
| D7 full validation | External | Twice-clean repository suite plus OS/GPU/sanitizer matrix remains. |
| D8 no fallback | Pending | Typed private selector exists; public/default legacy selection still exists. |

## Phase 5 work and completion bullets

Every Phase 5 work item is still **Pending**: (1) switch Runtime/Prismel,
(2) remove migration flags/comparison target, (3) delete tsdl_gfx/Tsdl/OpenGL/
SDL2 discovery, (4) remove unused legacy dependencies, and (5) update final
documentation/packaging/licenses/release notes. `prismel_next_low` commits
`8dc2b08`, `429157e`, and `08d2206` stage an opaque SDL2-free Low recorder and
window boundary, but do not flip the public API.

The six Phase 5 completion bullets are also **Pending**: D1–D8 plus every final
gate; no legacy text/linkage; fresh SDL2-free switch; two clean full-suite runs;
no compatibility fallback; and final-commit evidence hashes. B0 proves the
rollback inputs, not these post-switch outcomes.

## Final definition-of-done checklist

| Frozen final condition | Status | Reason |
| --- | --- | --- |
| All 47 gates pass on one commit | Pending | 11/47 strict gates proven. |
| Evidence contains no failure/waiver/skip/TODO | Pending | Honest failed native/R10 precursors and external lanes remain. |
| API and unchanged acceptance sources pass | Pending | B0 pins them; final switch rerun remains. |
| Deterministic/tolerance fixtures pass hardware matrix | External | Required alternate hardware/OS lanes remain. |
| Performance and one-upload shattered proof | Pending | R11 one-upload evidence passes its local protocol; a workload-equivalent superseding R10 and its required counters remain. |
| Packaging/Xcode/sanitizers/leaks/stability/RT pass | External | Several host/tool/hardware lanes are unavailable. |
| Legacy absent from source/deps/binaries | Pending | D1 has intentionally not begun. |
| Final architecture/API/backend/package/license docs | Pending | Must describe the post-switch tree, not the side-by-side tree. |

## Reproduction

```text
git show -s --format='%H %cI' 4622091a65bc9a8816a1f10bcc83c1a625ca7522 HEAD
rg -n '^\*\*(S[1-8]|M([1-9]|10)|O[1-9]|R([1-9]|1[0-2])|D[1-8]) -' NEW_GPU_STUFF.md
opam exec -- dune exec tools/gpu_migration/phase5_b0_freeze.exe -- --root .
opam exec -- dune exec tools/gpu_migration/api_manifest.exe -- --root . --check
opam exec -- dune exec test/gpu_dependency_direction.exe -- lib
```

Only a future audit on the atomic final commit may move Pending/External rows to
Proven or call Phase 5 complete.

At capture, committed evidence records green B0, dependency-direction, exact
40-module API-map, and installed-consumer checks. This evidence-only refresh did
not rerun them in the shared dirty worktree. R1 remains Pending because those
checks qualify the staged facade, not the unswitched final selected tree.

## Explicit next blockers

1. Run the canonical workload-equivalent, fixed-rate five-round R10 matrix and
   capture the frozen CPU/frame/allocation/RSS plus GPU/display/power facts.
2. Run all three `2c32b7e` public-facade R12 lanes for 30 minutes and validate
   the final-window RSS, bounded caches/queues and teardown report.
3. Complete the atomic default Runtime/Prismel switch, then rerun unchanged
   examples/sketches, API freeze, R1–R9 integration, clean install and twice-clean
   full-suite gates on that one commit.
4. Obtain the external M3+/Xcode, RT/MetalFX, sanitizer/diagnostics, packaging,
   OS/GPU and independent license lanes; no local precursor substitutes for them.
