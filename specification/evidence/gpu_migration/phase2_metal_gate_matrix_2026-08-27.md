# Phase 2 Metal gate matrix — 2026-08-27

`Proven` means the complete wording of the gate has committed, reproducible
evidence. `Partial` is intentionally not release-green.

| Gate | Status | Current evidence | Missing evidence |
|---|---|---|---|
| M1 inventory | Proven | 5,286 pinned declarations; 5,248 bound, 37 scoped exclusions, one explicit availability gate, zero unreviewed; deterministic inventory/provenance checks | None for M1 |
| M2 ownership | Partial | ARC bridge; release counters; deterministic stale/double-destroy/cross-device tests; `test_metal_stress` includes 100,000 buffer cycles and settled RSS checks | Current Metal-specific Leaks report and sanitizer evidence |
| M3 resources | Partial | Real M1 buffer/texture/view/sampler/heap/sparse/residency/external-resource coverage and extensive pre-native range/alignment rejection | A single requirement-indexed report proving every advertised external/aliasing/purgeability branch on each supported device lane |
| M4 pipelines/shaders | Partial | Runtime MSL, reflection, constants, archives/datasets, dynamic/linked/mesh/object/render/compute/Metal 4 compiler conformance | Full-Xcode offline `.metallib` build and runtime/offline image parity |
| M5 commands/sync | Partial | Real render/compute/blit/parallel/resource-state/AS/ICB/Metal 4 work; fences/events/barriers and deferred completion ownership | Explicit three-frames-in-flight + resize/occlusion + injected command-buffer-error matrix |
| M6 presentation | Partial | Real CAMetalLayer/drawable format, loss/error, resize, scale, HDR/colorspace, callback, presentation and teardown checks | Green 10,000-frame acquisition/presentation/teardown run; minimize/restore and RSS evidence |
| M7 ray tracing | Partial | BLAS/TLAS build/refit/copy/compact and geometry/function-table/intersection bindings execute on supported M1 paths | Deterministic compute ray-query image, explicit simulated missing-RT graph rollback, and M3+ hardware/render-pipeline lane |
| M8 Metal 4/MetalFX | Partial | Broad Metal 4 compiler/pipeline/command/resource/counter/ML/sparse execution with typed M1 capability rejection | M3+ execution matrix and weak-linked MetalFX support/limit/absence evidence |
| M9 FFI performance | Partial | `phase2_metal_ffi_baseline.json` and direct/batched benchmark tooling record timing, calls and allocations | Fresh release-profile rerun proving the frozen 5% threshold on the final ABI |
| M10 tooling | Missing | Generator drift checks and ordinary diagnostics are green | Full Xcode offline shaders, validation layers, GPU capture/counter trace, ASan/UBSan/TSan and Guard Malloc/Leaks reports |

## Cross-gate release lanes

- Full Xcode validation: missing on this Command Line Tools host.
- Runtime/offline shader parity: missing because offline Metal tools are absent.
- M1 ray-tracing lane: resource operations exist; required deterministic
  compute ray-query image is not yet evidenced.
- M3+ hardware-ray-tracing lane: missing; no M3+ result was fabricated.
- Unsupported simulations: many M1 capability/no-handle-delta regressions are
  green, but the complete simulated missing-RT and missing-MetalFX profiles do
  not yet exist.

## New software-verifiable gate

`lib/metal/test_metal_presentation_10k.ml` adds the missing M6 steady-state
workload: 10,000 acquire/present/commit/wait/destroy frames followed by release
queue settling and an exact live-handle-delta assertion. The cycle count is an
environment override only for focused debugging; the default remains 10,000.
The source parses cleanly. A first focused Dune execution was interrupted after
the Dune process stopped making progress without launching a child; therefore
this gate remains `Partial` until an uninterrupted run records green evidence.
