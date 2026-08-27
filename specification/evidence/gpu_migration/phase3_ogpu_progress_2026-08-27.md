# Phase 3 OGPU progress — 2026-08-27, current software-close checkpoint

This is the current evidence checkpoint against the frozen O1–O9 gates in
`NEW_GPU_STUFF.md`. It supersedes the pre-implementation state described by
`phase3_ogpu_audit_2026-08-27.md`; that audit remains as historical evidence.
No gate below is promoted to final release sign-off merely because its focused
unit tests pass.

| Gate | Current evidence | Status at this checkpoint |
| --- | --- | --- |
| O1 Backend independence | `prismel.ogpu` depends on no framework library and has a deterministic mock backend (`0fa5ffb`). `gpu_dependency_direction.exe -- lib` passes over 22 libraries and rejects injected `ogpu -> metal` and `ogpu_metal -> runtime` edges. | Focused gate green |
| O2 Handle/state safety | Generational device-owned handles (`fd3858b`), linear command state (`26c7302`), bounded submission epochs (`be8200a`), and render/compute/transfer/acceleration/query pass validation are tested for stale, cross-device and invalid transitions. Metal buffer, texture, and pipeline destruction requested after submission is now deferred through the exact completion epoch (`103ceae`); handles become stale immediately while native objects remain retained until `Queue.wait_through`. | Software-verifiable gate green; final renderer integration remains later-phase work |
| O3 Descriptor validation | Central validation (`f955868`) covers all 1,920 current format × storage × sample × usage combinations plus buffer/texture cardinality, overflow, aligned ranges, binding layouts and immutable labels. Both generic and Metal resource creation delegate before backend allocation. | Focused gate green |
| O4 Capability truthfulness | Probe-driven profiles (`1bbb8c1`) cover 16 operation families across minimum M1, M3-like RT/timestamp, missing RT, requested-but-unimplemented MetalFX/sparse, and future-unknown cases. Real M1 buffer, RT, sample and timestamp facts agree with typed Metal probes; conservative ceilings are explicit and `Metal.Unsupported` remains `Ogpu.Error.Unsupported`. | Software-verifiable matrix green; external M3+ execution remains unavailable on this host |
| O5 Synchronization | Portable synchronization (`bd42bd4`), declared frame-graph hazards (`062e2d4`), negative untracked-barrier tests, and deterministic query descriptions (`a62c09a`) are green. Typed Metal fences/events/counters (`09c6c41`) run when supported and return explicit `Unsupported` on this M1 where the required counter set is absent. | Focused gate green; final render integration pending |
| O6 Resource lifetime and bounds | Frames/submissions, transfer rings, deferred release, heap suballocation, pipeline/resource caches, diagnostics and descriptor arenas have explicit capacities. Descriptor arenas (`3a6bfba`) and ordered loss draining (`4dffa4b`) pass 100,000-cycle plateau tests; typed Metal placement heaps (`f1fff01`) pass 1,000 allocation/free cycles with zero handle delta. Submission-owned Metal resources now survive early public destroy and settle at their completion epoch (`103ceae`). | Software-verifiable lifetime/bounds gates green; external-duration integrated RSS qualification remains |
| O7 Surface contract | Portable outcomes cover success, timeout, occlusion, stale resize and device loss (`6da422b`). The typed borrowed `CAMetalLayer` backend (`0faca08`) passed 100 isolated M1 frames plus resize/outcome cases with zero drawable-handle delta and has no Runtime dependency. | Focused gate green; Runtime integration remains Phase 4/5 work |
| O8 Native Metal extension | Scoped native declarations never expose pointers through generic OGPU (`7619c5a`). The backend bridge (`79ec948`) validates declarations/lifetimes atomically and executes a real M1 custom compute dispatch with exact output and zero handle delta. | Partial: real custom acceleration-pass composition requires RT-capable hardware |
| O9 Determinism | Stable handles/descriptions, immutable binding order, bounded deterministic caches, and exact one-domain/four-domain fixtures exist throughout OGPU. Canonical pointer-free Metal captures (`f518c03`) preserve command order and produced exact hash `eb7f2278b69b28fb3242d741a2965e66` on the real M1 in both one- and four-domain preparation. | Focused gate green; final renderer work-stealing integration remains |

## Reproduction commands

```sh
opam exec -- dune runtest lib/ogpu --force
opam exec -- dune runtest lib/ogpu_metal --force
opam exec -- dune exec test/gpu_dependency_direction.exe -- lib
```

The `ogpu_metal` suite must run without a concurrent second CAMetalLayer
acquisition fixture on this M1 host; concurrent independent layer tests can
serialize in the window server and are not used as a throughput measurement.

## Current O1–O9 software-close audit

Executed after `103ceae` on the real M1 host:

```sh
opam exec -- dune runtest lib/ogpu --force
opam exec -- dune runtest lib/ogpu_metal --force
opam exec -- dune exec test/gpu_dependency_direction.exe -- lib
```

All three commands exited zero. The dependency gate inspected 22 libraries and
rejected its injected reverse edge. The Metal suite included real buffer copy,
compute, render clear, 100 surface frames, placement heaps, capability probes,
canonical capture hashing, and the new destroy-while-submitted regression; all
reported zero final live-handle delta where applicable.

The audit found and fixed one local defect: command operation records kept OCaml
resources reachable but did not prevent an explicit public `destroy` from
releasing their native Metal objects before GPU completion. `103ceae` adds
submission-use retention for buffers, textures, and pipelines, immediate stale
public handles, rollback on failed submit/encode/commit, and native release at
the completed epoch. The focused submission fixture executes this path on M1.

No final Phase 3 completion claim is made. The remaining evidence is not local
software work: O4 and O8 still require the external M3+/RT-capable execution
lane, O6 retains an external-duration integrated RSS qualification, and the
renderer/work-stealing and Runtime presentation integrations named by O5, O7,
and O9 belong to the later renderer/switch phases.
