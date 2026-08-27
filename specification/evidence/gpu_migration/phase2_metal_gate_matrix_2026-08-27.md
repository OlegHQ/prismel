# Phase 2 Metal gate matrix — 2026-08-27

`Proven` means the complete wording of the gate has committed, reproducible
evidence. `Partial` is intentionally not release-green.

| Gate | Status | Current evidence | Missing evidence |
|---|---|---|---|
| M1 inventory | Proven | 5,286 pinned declarations; 5,248 bound, 37 scoped exclusions, one explicit availability gate, zero unreviewed; deterministic inventory/provenance checks | None for M1 |
| M2 ownership | Partial | ARC bridge; release counters; deterministic stale/double-destroy/cross-device tests; the isolated `test_metal_stress --lane buffers` run completed 5,000 warmups and 100,000 measured create/destroy cycles with zero teardown handles and a 1,605,632-byte settled RSS delta | Current Metal-specific Leaks report and sanitizer evidence |
| M3 resources | Partial | Real M1 buffer/texture/view/sampler/heap/sparse/residency/external-resource coverage and extensive pre-native range/alignment rejection | A single requirement-indexed report proving every advertised external/aliasing/purgeability branch on each supported device lane |
| M4 pipelines/shaders | Partial | Runtime MSL, reflection, constants, archives/datasets, dynamic/linked/mesh/object/render/compute/Metal 4 compiler conformance | Full-Xcode offline `.metallib` build and runtime/offline image parity |
| M5 commands/sync | Partial | Real render/compute/blit/parallel/resource-state/AS/ICB/Metal 4 work; fences/events/barriers and deferred completion ownership | Explicit three-frames-in-flight + resize/occlusion + injected command-buffer-error matrix |
| M6 presentation | Partial | Real CAMetalLayer/drawable format, loss/error, resize, scale, HDR/colorspace, callback, presentation and teardown checks; the committed 10,000-frame acquisition/presentation/teardown workload completed with exact zero live-handle delta | Minimize/restore and presentation-specific RSS evidence |
| M7 ray tracing | Partial | BLAS/TLAS build/refit/copy/compact and geometry/function-table/intersection bindings execute on supported M1 paths; a fixed M1 compute ray-query scene produces exact hit/miss bytes and FNV-1a `cc2679258ea31e7d` with zero live-handle delta | Explicit simulated missing-RT graph rollback and M3+ hardware/render-pipeline lane |
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

## Executed software-verifiable gates

`lib/metal/test_metal_presentation_10k.ml` adds the missing M6 steady-state
workload: 10,000 acquire/present/commit/wait/destroy frames followed by release
queue settling and an exact live-handle-delta assertion. The cycle count is an
environment override only for focused debugging; the default remains 10,000.
On the Apple M1 audit host, this completed in approximately 76.5 seconds:

```text
$ opam exec -- dune exec lib/metal/test_metal_presentation_10k.exe
metal presentation lifecycle: 10000 frames, no live-handle delta
```

M2 already had the required resource workload, so no duplicate stress test was
added. Its isolated buffer lane performs 5,000 warmup cycles, settles the
release queue and RSS baseline, then performs exactly 100,000 measured buffer
create/destroy cycles before settling again and requiring zero handles after
device teardown. The actual audit-host run completed as follows:

```text
$ opam exec -- dune exec lib/metal/test_metal_stress.exe -- --lane buffers
Metal ownership lane buffers passed: 100000 measured handles, 1605632-byte settled RSS delta
```

These executions close the software-verifiable steady-state portions only.
They do not constitute Leaks/sanitizer evidence, minimize/restore evidence,
full-Xcode validation, offline shader parity, or M3+ hardware qualification.

## Deterministic M1 compute ray query

`lib/metal/test_metal_m1_ray_query.ml` uses only the public safe Metal API. It
uploads one fixed triangle, queries and allocates its acceleration-structure
storage, builds the structure on an acceleration encoder, dispatches four
fixed compute rays, and compares all 16 readback bytes before hashing them.
The expected words encode two triangle hits followed by two misses. Three
consecutive audit-host executions produced the same result:

```text
$ opam exec -- dune exec lib/metal/test_metal_m1_ray_query.exe
Metal M1 ray query: hash=cc2679258ea31e7d, no live-handle delta
Metal M1 ray query: hash=cc2679258ea31e7d, no live-handle delta
Metal M1 ray query: hash=cc2679258ea31e7d, no live-handle delta
```

The fixture gates execution on the typed `Device.info.raytracing` capability.
On an unsupported device it creates no ray-tracing graph, destroys the queried
device, drains the release queue, and requires exact zero handle delta. That
unsupported branch is committed but was not fabricated as executed on this
ray-tracing-capable M1. This proves deterministic compute ray queries only; it
does not claim the M3+ or hardware render-pipeline ray-tracing lanes.
