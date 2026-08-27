# Phase 3 OGPU audit — 2026-08-27

This audit compares the frozen O1–O9 gates in `NEW_GPU_STUFF.md` with the
current repository. The frozen plan was not modified.

No `lib/ogpu` or `lib/ogpu_metal` directory, Dune library, public interface,
mock backend, Metal adapter, or Phase 3 evidence manifest currently exists.
Phase 3 is therefore **not started**; architecture prose referring to these
libraries describes the target dependency graph, not implemented coverage.

| Gate | Present evidence | Status | Exact missing package |
| --- | --- | --- | --- |
| O1 Backend independence | `test/gpu_dependency_direction.ml` defines the future forbidden dependency sets. Its negative gate now injects and rejects `ogpu -> metal` and `ogpu_metal -> runtime`. | Partial | Create the pure `ogpu` library and a framework-free mock backend; require both future libraries in the real graph once present. |
| O2 Handle/state safety | None. | Missing | Generational device-owned handles, encoder/pass/present state machine, submitted-release epochs, stale/cross-device tests. |
| O3 Descriptor validation | None. | Missing | Typed descriptors, validation tables, overflow/cardinality rejection before mock allocation, diagnostic-label tests. |
| O4 Capability truthfulness | None. | Missing | Adapter-derived capabilities and mock profiles for M1, M3+, missing RT/MetalFX, and unknown future values. |
| O5 Synchronization | None. | Missing | Declared access/stage model, hazard-tracked default, explicit untracked barriers, Metal mapping and negative tests. |
| O6 Lifetime/bounds | None. | Missing | Bounded frame/ring/queue/arena/cache structures, loss drain order, long-run live-object/RSS evidence. |
| O7 Surface contract | None. | Missing | Acquire/present result model for timeout, occlusion, stale frame, resize and device loss; mock transition tests. |
| O8 Native Metal extension | Metal is independently available, but no OGPU integration exists. | Missing | Lifetime-bounded native pass capability, declared-resource validation, compute/acceleration composition, and proof that generic OGPU exposes no pointer. |
| O9 Determinism | None. | Missing | Stable IDs/order, one-domain versus multi-domain byte equality, deterministic caches/bindings/capture hashes. |

## Focused audit commands

- `test/gpu_dependency_direction.exe` passes and rejects deliberate reverse
  edges for SDL3, Metal, OGPU, and OGPU-Metal.
- Repository search confirms there is no current OGPU implementation to build
  or test. Consequently, no execution, performance, ownership, or Metal
  composition claim is made here.

## Recommended first implementation slice

Start with a framework-independent `ogpu` library containing generational
device-owned handles, explicit command/pass state, typed descriptor validation,
and a deterministic mock backend. This single slice unlocks meaningful O1–O4,
O6, O7, and O9 tests before `ogpu_metal` introduces native complexity.
