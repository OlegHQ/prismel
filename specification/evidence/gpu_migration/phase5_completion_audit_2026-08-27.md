# Phase 5 completion audit — 2026-08-27

Captured at `2026-08-27T17:53:10Z` on commit
`8827af925567622ec1aedb0856d44c687a6229fa`. This is a mechanical readiness
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
is dated `2026-08-22T12:34:54Z`; this capture is 125.30 hours later. Eleven
strict gates over that interval are **0.0878 gates/hour**, or **4.48 percentage
points/day** of the 47-gate denominator. The interval contains 1,304 commits
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
| M2 ownership | Pending | ARC/stale/destroy/stress coverage exists; final current-commit Metal Leaks and sanitizer reports remain. |
| M3 resources | Pending | Broad real-M1 coverage exists; one requirement-indexed supported-device matrix is absent. |
| M4 pipelines/shaders | External | Full-Xcode offline metallib build and runtime/offline image parity require unavailable tools. |
| M5 commands/sync | Pending | Three-frames-in-flight resize/occlusion/error injection matrix remains. |
| M6 presentation | Pending | 10,000-frame zero-handle fixture is green; minimize/restore and presentation RSS qualification remain. |
| M7 ray tracing | External | Deterministic M1 compute query is green; missing-RT rollback and M3+ render lane remain. |
| M8 Metal4/MetalFX | External | M1 typed rejection is covered; M3+ and weak-linked MetalFX presence/absence matrix remains. |
| M9 FFI performance | Pending | Tooling/baseline exists; final ABI release rerun against the frozen threshold remains. |
| M10 tooling | External | Full Xcode shaders, GPU capture/counters, validation, ASan/UBSan/TSan and Guard Malloc/Leaks suite remains. |

## O1–O9: OGPU

Evidence authority: `phase3_ogpu_progress_2026-08-27.md`.

| Gate | Status | Exact evidence or blocker |
| --- | --- | --- |
| O1 backend independence | Proven | Dependency gate proves generic OGPU has no framework edge and rejects injected reverse edges. |
| O2 handle/state safety | Pending | Local generational/linear/deferred-release suites are green; final renderer integration remains. |
| O3 descriptor validation | Proven | Exhaustive 1,920 format/storage/sample/usage combinations and pre-allocation validation. |
| O4 capability truthfulness | External | Software profiles and M1 agree; M3+ execution remains unavailable. |
| O5 synchronization | Pending | Portable and typed Metal fixtures exist; final render integration remains. |
| O6 lifetime/bounds | Pending | 100,000-cycle plateaus exist; integrated external-duration RSS qualification remains. |
| O7 surface contract | Pending | Portable outcomes and real M1 frames exist; final selected Runtime integration remains. |
| O8 native extension | External | Pointer-free boundary and M1 compute pass; RT-capable acceleration composition remains. |
| O9 determinism | Pending | Canonical one/four-domain capture is exact; final renderer work-stealing integration remains. |

## R1–R12: renderer prerequisites

Evidence authority: `phase4_raster2_audit_2026-08-27.md`,
`runtime_next_native_m1_qualification_2026-08-27.md`,
`runtime_next_target_stability_2026-08-27.md`, and the R10/R11/R12 reports.

| Gate | Status | Exact evidence or blocker |
| --- | --- | --- |
| R1 stable API | Pending | B0 freeze `bf30654` pins API/plan/examples and a narrow future private-Low allowlist; final selected commit rerun remains. |
| R2 Scene2/PXUI | Pending | Private exact frames 1/2/60/600 exist; public/default acceptance matrix remains. |
| R3 Scene3 | Pending | Topology/state/shading/multi-shadow private native parity is green through `20e03d0`; final selected/hardware matrix remains. |
| R4 resources | Pending | Watched Image, density Text, Canvas, Assets and Audio lifecycle fixtures exist; final selected cross-target examples remain. |
| R5 targets | Pending | Native/headless/web compositions exist privately; public/default Runtime is not switched. |
| R6 coordinates/DPI | Pending | Typed logical/drawable/Retina fixtures exist; final real browser/mobile and selected-native capture remain. |
| R7 deterministic pixels | Pending | Software exactness and M1 tolerance evidence exist; final required hardware matrix remains. |
| R8 multi-frame | Pending | Broad frames 1/2/60/600 fixtures exist; unchanged selected example/sketch matrix remains. |
| R9 upload/batching | Pending | Stable portable counters exist; final native Metal upload/encoder/FFI evidence remains. |
| R10 performance | Pending | Protocol/tooling exists; five interleaved warmed 30-second legacy/candidate samples per scenario have not passed. |
| R11 shattered cube | Pending | Actual artifact correctness and structural batching are recorded; accepted visible/hidden native protocol remains. |
| R12 stability | Pending | Headless/web fixed-ring 30-minute evidence passes; the recorded native lane failed RSS and must pass after fixes. |

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
| Performance and one-upload shattered proof | Pending | Final interleaved R10/R11 qualification remains. |
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

At capture, the B0 verifier and dependency-direction gate passed. The API
checker correctly reported the checked manifest stale after the newly committed
private runtime-compatibility facade (`d490e22`, `868da7a`); this audit does not
regenerate or approve that delta. That is why R1 remains Pending rather than
being promoted from the older byte-pinned B0 baseline.
