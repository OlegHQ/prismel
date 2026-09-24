# Runtime-next native M1 qualification — 2026-08-27

This qualification links SDL3, Metal, OGPU Metal, `scene_execution`, and
`runtime_next`; it does not link Prismel or SDL2. It ran on an Apple M1 with
16 GiB RAM, Darwin 25.4.0 arm64. The focused command was:

```sh
opam exec -- dune exec \
  lib/runtime_next/native_qualification/runtime_next_native_qualification.exe
```

The corrected run completed before `2026-08-27T13:48:21Z`. Each representative workload
rendered frames 1, 2, 60, and 600, performed an 4×4→8×8 resize, captured the
actual Metal target, and destroyed the complete window/view/device graph.

| Workload | Prepared upload | Draws | Passes | Runtime/backend calls | Native 4×4 hash | Frozen software hash | Exact parity |
|---|---:|---:|---:|---:|---|---|---|
| Basic Scene2 | 60 B | 601 | 601 | 607 | `183be222f2a9499335f80e49bab17f24` | `183be222f2a9499335f80e49bab17f24` | Yes |
| PXUI-like | 480 B | 4,808 | 601 | 607 | `c28fb438cfaf0381adc6b8dddec9d6cf` | `c28fb438cfaf0381adc6b8dddec9d6cf` | Yes |
| Canvas/offscreen-like | 180 B | 1,803 | 601 | 607 | `6669327647bf796bcc136e62a62f7c95` | `6669327647bf796bcc136e62a62f7c95` | Yes |
| Built-in Scene3-like | 240 B | 2,404 | 601 | 607 | `52462b7485ced3177c5f7bf2fda8a7ae` | `52462b7485ced3177c5f7bf2fda8a7ae` | Yes |

All four native checkpoint sets now equal their frozen software hashes byte for
byte at frames 1/2/60/600. Basic's frozen resized 8×8 hash is also exact:
`a07e462221d8a87c5d83ad9a18411a44`. No per-channel tolerance was needed.

The original gap was a real lowering bug: the native vertex function ignored
the prepared vertex buffer and emitted one full-screen constant color. The
corrected path consumes packed position/color vertices at the typed buffer-zero
binding and carries explicit clear color through runtime-next and
`scene_execution`. Mapping top-left logical coordinates to Metal NDC with the
Y-axis inversion produced the frozen topology exactly; no edge-rule tolerance
was required.

RSS samples were 12,272 KiB before native initialization, then 85,920, 86,544,
87,808, and 88,352 KiB after the four sequential scenarios. Explicit full GC
and twelve additional create/destroy cycles produced 88,368–89,776 KiB, a
1,408 KiB range. This is bounded first-use Metal compiler/driver allocator
retention, not live wrapper/cache growth: each scenario reports pipeline cache
length 1 while live and 0 after destroy, exact uploads 60/480/180/240 bytes,
and Metal live handles exactly 0 before and after the final release-queue
drain. This finite test establishes handle/cache teardown and a small warm
allocator envelope; it is not a substitute for the separate native long-run
RSS gate.

The host's hidden Metal windows reported authoritative SDL3 logical/drawable
facts `4×4 / 4×4`, density `1×1`; this host configuration therefore did not
exercise a real Retina backing scale. Runtime-next now queries both sizes from
SDL3 at creation and after authoritative size-change handling, maps logical
viewport/scissor edges to drawable pixels exactly once, and ignores caller
guesses for native drawable size. A synthetic `10×10 / 15×15` fixture proves
the 1.5× half-open edge mapping (`1,1,3,3` → `1,1,5,5`), while an SDL3 pointer
fixture proves `(3.25,4.5)` remains in logical coordinates without scaling.

## Explicit exclusions

- Runtime-next configures `sample_count=1`; MSAA is unsupported by this native
  slice and was not silently treated as qualified.
- Public Shader3 remains software-only here and was not exercised.
- Resize and capture are real and drawable facts are now exposed. This run
  observed 1×, so a true host-provided 2× Retina window/monitor move remains an
  external qualification even though the synthetic edge contract is green.
- Canvas behavior is represented by owned prepared geometry and native
  readback; it is not yet the full public Canvas mutation/resource graph.

## Subsequent native stability status

The R6 coordinate qualification above remains exact: all frozen hashes are
unchanged, the host supplied authoritative 1× logical/drawable facts, the 1.5×
synthetic edge fixture maps once, and pointer coordinates remain logical.

The separate native R12 long-run result is now qualified after eliminating
same-size mesh-buffer replacement churn. The final real 30-minute schema-3 run
kept its full payload/resize/capture workload, reproduced hash
`ed1f9fcf05a686c5`, held settled RSS to 80,448–81,904 KiB, decreased retained
half-window high-water 81,904→80,976 KiB, kept caches/live handles fixed, and
returned caches and Metal handles to zero. Exact failed precursors, diagnosis,
commands, timestamps, counters, and exclusions remain recorded in
`runtime_next_native_stability_2026-08-27.md` rather than being hidden by the
passing repair.
