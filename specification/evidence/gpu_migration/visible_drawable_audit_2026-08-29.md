# Visible drawable presentation audit — 2026-08-29

Captured at `2026-08-29T16:04:51+02:00` on commit
`28f95deb185faba4062539a456cdf4a1c4a84850`.

## Finding

Visible drawable presentation is incomplete and must not be inferred from the
current capture tests. `lib/scene_execution/scene_execution.ml` acquires an
`Ogpu.Backend.frame` for presented work, but its render-pass color attachment
is the execution object's owned RGBA target. `finish_submission` then presents
the acquired frame without a typed GPU operation that copies or renders that
RGBA target into the frame's BGRA drawable. `Scene_execution.read_pixels`
reads the owned target with `Ogpu.Backend.read_texture`; it does not read the
drawable that the window presents.

The portable `Ogpu.Backend.frame` interface in `lib/ogpu/backend.mli` exposes a
presentation token, not a drawable texture suitable for a typed attachment or
copy. Consequently, a correct internal capture and a successful present call
can coexist with a blank, stale, or otherwise unproved visible drawable.

This is a presentation-boundary gap, not evidence of a CPU renderer. The scene
work, internal texture, and readback are native Metal. The missing operation
must also remain native GPU work.

## Existing coverage and the false-positive boundary

The following tests exercise important production behavior, but their pixel
checks stop at the internal RGBA target:

| Path | Evidence that remains valid | Why it does not prove visible pixels |
| --- | --- | --- |
| `lib/runtime/test_runtime_next.ml` | Runtime lifecycle and 600-frame rendering, including checks at frames 1, 2, 60, and 600 | `Runtime_next.read_pixels` forwards to `Scene_execution.read_pixels`, which reads the owned target |
| `lib/runtime/test_runtime_next_scene3_lighting.ml` | Native Scene3 lighting output in the internal target through frames 1, 2, 60, and 600 | Its assertions use the same internal-target readback |
| `lib/runtime/test_runtime_next_scene2_argument.ml` | Scene2 argument-buffer output, mixed 600-frame behavior, and exact internal pixels | Its exact pixels come from `Runtime_next.read_pixels`, not the drawable |
| `lib/ogpu_metal/test_scene_execution_metal.ml` | Exact Scene execution pixels and repeated-frame Metal behavior | `Scene_execution.read_pixels` reads the owned RGBA texture |
| `lib/runtime/native_qualification/runtime_next_native_qualification.ml` | Native device/runtime execution, counters, ownership, and internal-target output | The described captured Metal target is not the acquired window drawable |
| `tools/runtime_next_native_stability/runtime_next_native_stability.ml` | Long-run native lifecycle, resize, resource, and internal-target stability | Its readbacks use `Runtime_next.read_pixels` |
| `tools/r10_performance/r10_scene2_candidate.ml`, `tools/r10_performance/r10_native_scene2_correctness.ml`, and `tools/runtime_next_native_benchmark/runtime_next_native_benchmark.ml` | Candidate workload execution, internal framebuffer digest, and performance counters | Their capture chain terminates at `Runtime_next.read_pixels`; R10 was already pending-local |

`lib/prismel/test_canvas_native.ml` remains valid evidence for the deliberately
offscreen `Canvas` contract. It never claimed to present a window drawable and
must not be promoted into visible-presentation evidence.

The following tests reach actual surface acquisition and presentation, but do
not encode known pixel content into the acquired drawable and then observe it:

- `lib/metal/test_metal_presentation_safe.ml` proves drawable acquisition,
  presentation callbacks, and lifecycle behavior.
- `lib/metal/test_metal_presentation_10k.ml` proves 10,000 bounded
  acquire/present/commit/wait/destroy cycles.
- `lib/ogpu_metal/test_ogpu_metal_surface.ml` proves surface acquire, present,
  discard, resize, and lifecycle behavior.

Those tests are genuine lifecycle evidence, but presenting an acquired token
is not an exact pixel-content assertion.

Historical qualification notes are preserved as recorded. This audit
supersedes only their interpretation of internal-target readback as visible
drawable proof. Their independently measured renderer output, resource
lifetime, counters, and timing remain usable within their stated scope.

## Gate correction

M6, O7, R5, R8, and R12 move from provisional to pending-local. R10 was already
pending-local. The corrected inventory is:

- 11 strict;
- 22 provisional;
- 6 pending local;
- 8 pending external.

Strict plus provisional coverage is **33/47 = 70.21%**. Strict completion is
unchanged at **11/47 = 23.40%**. This is a gate-evidence classification, not an
implementation-percent estimate.

SDL3 implementation and the strict S-gate set remain **100% complete**. The
structural deletion of every selectable software-rasterizer, SDL2/Tsdl,
OpenGL, headless, Wap, and web fallback remains **100% complete**. Visible
presentation remains incomplete until the proof below passes.

## Remediation and proof contract

The production fix must provide a narrow, typed GPU-only operation from the
owned RGBA scene target to the exact BGRA texture belonging to the acquired
drawable. It must execute before presentation of that same drawable. It must
not introduce CPU readback/upload, a software copy or raster fallback, an
untyped selector, a generic raw-pointer escape, or a second presentation path.

The decisive pixel fixture must use asymmetric channels. For example, a source
RGBA texel with raw bytes `11 22 33 ff` must be observed from the actual BGRA
drawable as raw bytes `33 22 11 ff`. Comparing only a semantic color sampled
from the internal RGBA target is insufficient. The probe must identify the
same acquired drawable whose presentation completes, and must occur before the
drawable is consumed by presentation.

Two non-conflicting focused tests should close the local proof:

1. Add `lib/ogpu_metal/test_ogpu_metal_present_rgba_to_bgra.ml` for the typed
   backend boundary. Render or copy an asymmetric 2-by-2 RGBA source into an
   acquired BGRA drawable entirely on the GPU, read/probe that drawable before
   presentation, assert exact raw BGRA bytes, require exactly one completion
   for the same drawable, and require zero live-handle delta after teardown.
2. Add `lib/runtime/test_runtime_next_visible_present_600.ml` for the product
   path. Use a real visible SDL3 Metal window, render changing asymmetric
   content for 600 frames through `Runtime_next`, and probe actual drawables at
   frames 1, 2, 60, and 600 without calling `Runtime_next.read_pixels`. Assert
   exact BGRA bytes and drawable dimensions, 600 successful presentations,
   balanced created/released resources, zero outstanding frames, and zero
   pending, dropped, or live-handle delta after teardown. A mid-run resize may
   additionally prove that drawable replacement preserves the contract.

After those tests pass, repeat the affected native qualification and stability
lanes against the production presentation path before restoring provisional or
strict gate status. Thresholds, frozen workloads, and historical artifacts
must not be weakened or rewritten to accommodate the fix.
