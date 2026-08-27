# Phase 3 OGPU progress — 2026-08-27 12:15 CEST

This is the current evidence checkpoint against the frozen O1–O9 gates in
`NEW_GPU_STUFF.md`. It supersedes the pre-implementation state described by
`phase3_ogpu_audit_2026-08-27.md`; that audit remains as historical evidence.
No gate below is promoted to final release sign-off merely because its focused
unit tests pass.

| Gate | Current evidence | Status at this checkpoint |
| --- | --- | --- |
| O1 Backend independence | `prismel.ogpu` depends on no framework library and has a deterministic mock backend (`0fa5ffb`). `gpu_dependency_direction.exe -- lib` passes over 22 libraries and rejects injected `ogpu -> metal` and `ogpu_metal -> runtime` edges. | Focused gate green |
| O2 Handle/state safety | Generational device-owned handles (`fd3858b`), linear command state (`26c7302`), bounded submission epochs/deferred release (`be8200a`), and render/compute/transfer/acceleration/query pass validation are tested for stale, cross-device and invalid transitions. | Focused gate green; final integration stress pending |
| O3 Descriptor validation | Typed resource/pipeline/binding/pass descriptors reject invalid layouts, ranges, usages, pitches, alignments and cardinalities before mutation. Labels and bounded diagnostics are preserved. | Partial: broaden exhaustive format/storage/sample tables |
| O4 Capability truthfulness | Mock profiles include M1, M3+, missing RT and missing MetalFX (`0fa5ffb`); the real M1 adapter derives native capabilities (`600eab7`) and rejects unsupported acceleration paths. | Partial: external M3+ execution remains unavailable on this host |
| O5 Synchronization | Portable synchronization (`bd42bd4`), declared frame-graph hazards (`062e2d4`), negative untracked-barrier tests, and deterministic query descriptions (`a62c09a`) are green. | Partial: real Metal fence/event/query mapping is in progress |
| O6 Resource lifetime and bounds | Frames/submissions, transfer rings, deferred release, heap suballocation, pipeline/resource caches, and diagnostics have explicit capacities; real M1 buffer/texture/queue/pipeline/surface fixtures return to zero handle delta. | Partial: descriptor arena, loss-drain integration, and broad long-run RSS gate remain |
| O7 Surface contract | Portable outcomes cover success, timeout, occlusion, stale resize and device loss (`6da422b`). The typed borrowed `CAMetalLayer` backend (`0faca08`) passed 100 isolated M1 frames plus resize/outcome cases with zero drawable-handle delta and has no Runtime dependency. | Focused gate green; Runtime integration remains Phase 4/5 work |
| O8 Native Metal extension | Scoped native declarations never expose pointers through generic OGPU (`7619c5a`). The backend bridge (`79ec948`) validates declarations/lifetimes atomically and executes a real M1 custom compute dispatch with exact output and zero handle delta. | Partial: real custom acceleration-pass composition requires RT-capable hardware |
| O9 Determinism | Stable handles/descriptions, immutable binding order, bounded deterministic caches, and exact one-domain/four-domain fixtures exist throughout OGPU; real M1 compute/render/readback fixtures are exact. | Partial: integrated capture hashes and work-stealing stress remain |

## Reproduction commands

```sh
opam exec -- dune runtest lib/ogpu --force
opam exec -- dune runtest lib/ogpu_metal --force
opam exec -- dune exec test/gpu_dependency_direction.exe -- lib
```

The `ogpu_metal` suite must run without a concurrent second CAMetalLayer
acquisition fixture on this M1 host; concurrent independent layer tests can
serialize in the window server and are not used as a throughput measurement.
