# Runtime-next native M1 qualification — 2026-08-27

This qualification links SDL3, Metal, OGPU Metal, `scene_execution`, and
`runtime_next`; it does not link Prismel or SDL2. It ran on an Apple M1 with
16 GiB RAM, Darwin 25.4.0 arm64. The focused command was:

```sh
opam exec -- dune exec \
  lib/runtime_next/native_qualification/runtime_next_native_qualification.exe
```

The final run completed at `2026-08-27T13:37:10Z`. Each representative workload
rendered frames 1, 2, 60, and 600, performed an 4×4→8×8 resize, captured the
actual Metal target, and destroyed the complete window/view/device graph.

| Workload | Prepared upload | Draws | Passes | Runtime/backend calls | Native 4×4 hash | Frozen software hash | Exact parity |
|---|---:|---:|---:|---:|---|---|---|
| Basic Scene2 | 60 B | 601 | 601 | 607 | `c28fb438cfaf0381adc6b8dddec9d6cf` | `183be222f2a9499335f80e49bab17f24` | No |
| PXUI-like | 480 B | 4,808 | 601 | 607 | `c28fb438cfaf0381adc6b8dddec9d6cf` | `c28fb438cfaf0381adc6b8dddec9d6cf` | Yes |
| Canvas/offscreen-like | 180 B | 1,803 | 601 | 607 | `c28fb438cfaf0381adc6b8dddec9d6cf` | `6669327647bf796bcc136e62a62f7c95` | No |
| Built-in Scene3-like | 240 B | 2,404 | 601 | 607 | `c28fb438cfaf0381adc6b8dddec9d6cf` | `52462b7485ced3177c5f7bf2fda8a7ae` | No |

All four native checkpoint sets were byte-exact at frames 1/2/60/600. Every
resized 8×8 capture was `f9dc84a13290d920f46adc67e228d10e`.
The exact pixel value at every location was RGBA `(64,128,191,255)`; there was
therefore no per-channel tolerance involved in the native assertion.

The comparison is intentionally not presented as general renderer parity.
Current `runtime_next` uses one fixed full-screen fragment shader and does not
yet lower Scene2, Canvas, or Scene3 material/color semantics to the native
pipeline. PXUI-like happens to equal its frozen software fixture exactly; the
other three hashes differ, and hashes alone do not support a meaningful
per-channel tolerance comparison. This is a real native lifecycle/batching/
readback qualification and also direct evidence of the remaining lowering gap.

RSS samples were 12,288 KiB before native initialization, then 85,808, 87,232,
88,256, and 89,312 KiB after the four sequential scenarios. The increase is
mostly first-use SDL3/Metal/compiler state; this finite fixture does not prove a
long-run native RSS plateau. Metal live handles were exactly 0 before and after
the final release-queue drain.

## Explicit exclusions

- Runtime-next configures `sample_count=1`; MSAA is unsupported by this native
  slice and was not silently treated as qualified.
- Public Shader3 remains software-only here and was not exercised.
- Resize and capture are real. Retina drawable scale is not exposed by the
  current narrow `Runtime_next` API, so this run does not qualify a true 2×
  drawable/logical-size split or monitor move.
- Canvas behavior is represented by owned prepared geometry and native
  readback; it is not yet the full public Canvas mutation/resource graph.
