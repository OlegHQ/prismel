# Native Metal migration evidence

`NEW_GPU_STUFF.md` is the current migration authority. This directory keeps
machine-readable and textual evidence for the native Apple-Silicon SDL3 + Metal
delivery path. Each record is tied to the commit and command that produced it;
partial records do not claim final release qualification.

## Evidence index

| Area | Evidence | Scope |
| --- | --- | --- |
| SDL3 ABI and lifecycle | `phase1_sdl3.json`, generated layout and ABI records | Native window, Metal-view, DPI, initial-domain, resource, and extension validation. |
| Metal binding coverage | `metal_completion_audit_2026-08-27.md`, `phase2_metal_ffi_baseline.json`, `phase3_ogpu_audit_2026-08-27.md` | Typed binding inventory, conformance, ownership, and FFI-envelope measurements. |
| M10 local harness | `gpu_migration/m10_local_harness_audit_2026-08-29.md` | Current M1 sanitizer/Leaks/Guard Malloc/validation/counter availability, hardened executable preflight, and explicit external Xcode trace boundary. |
| Visible drawable audit | `gpu_migration/visible_drawable_audit_2026-08-29.md` | Corrected internal-target/visible-drawable evidence boundary and the exact GPU-only RGBA-to-BGRA remediation contract. |
| Native runtime | `r10_native_scene2_correctness_2026-08-28.md`, `runtime_next_native_stability_2026-08-29.md`, `runtime_next_native_r11_candidate_protocol_2026-08-27.md` | Native scene lowering, current clean 30-minute changing-resource stability, readback, and lifecycle evidence. |
| Production linkage and native-only selection | `d3_native_link_audit_2026-08-29.md`, `d2_d3_d8_native_only_audit_2026-08-29.md` | Fresh release build linkage plus current token classification, dependency/artifact refresh, retired SDL presenter deletion, and durable selector gate. |
| Frozen fixtures | `gpu_migration/fixtures.json` | Exact native reference artifact dimensions, bytes, digests, and capture environment. |

## Reading the records

The records preserve the command profile, toolchain, machine context, and
artifact digests necessary to repeat a qualification lane. Native fixture
entries retain their original dimensions and hashes; a changed native capture
requires an explicit semantic justification and renewed correctness evidence.

Completion requires the clean-tree gate matrix in `NEW_GPU_STUFF.md`, including
the required native conformance, ownership, sanitizer, benchmark, and
dependency/link checks. Evidence from an earlier commit remains useful for
provenance but cannot close a gate for later code without a compatible rerun.
