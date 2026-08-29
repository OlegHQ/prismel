# Current native GPU gate status — 2026-08-29

Captured at `2026-08-29T14:34:00+02:00` on commit
`f50be90ef7f1bfdfb7ad50e99434dda07d211295`. The working tree also contained
uncommitted R10 and Canvas follow-up work, which is excluded from every count.

The denominator is the 47 equally weighted gates in `NEW_GPU_STUFF.md`:
S1–S8, M1–M10, O1–O9, R1–R12, and D1–D8. Status meanings are:

- **strict**: complete gate evidence remains applicable to this commit;
- **provisional**: the implementation or historical evidence exists, but a
  current integrated qualification is required;
- **pending local**: a concrete repository implementation or local evidence
  blocker remains;
- **pending external**: decisive evidence requires another supported OS/GPU,
  clean-host state, sanitizer/tooling lane, or independent review.

| Group | Strict | Provisional | Pending local | Pending external |
| --- | ---: | ---: | ---: | ---: |
| S1–S8 | 8 | 0 | 0 | 0 |
| M1–M10 | 2 | 5 | 0 | 3 |
| O1–O9 | 1 | 6 | 0 | 2 |
| R1–R12 | 0 | 8 | 4 | 0 |
| D1–D8 | 0 | 5 | 0 | 3 |
| **Total** | **11** | **24** | **4** | **8** |

The native code-path cutover is structurally complete: the production tree has
one SDL3 window/input lifecycle and one OGPU/Metal renderer, with no selectable
SDL2, Tsdl, OpenGL, software-rasterizer, headless, Wap, or web fallback. This
is **100% structural cutover**, not the release completion percentage.

Strict release completion is **11/47 = 23.40%**. Strict plus provisional
implementation/evidence coverage is **35/47 = 74.47%**. The remaining
**12/47 = 25.53%** consists of four local and eight external gates.

Strict rows are S1–S8, M1, M9, and O1. The four local blockers at this capture
are R1 public API manifest renewal, R2 native Scene resource parity, R4 native
Canvas/resource completion, and R10 workload-equivalent qualification. The
active offscreen Runtime implementation in `f50be90` establishes a layerless
Metal target and correct FIFO/Immediate pacing, but does not close R4 or R10
until the public Canvas dispatch and qualifying evidence are committed.

The earlier conversational 28/47 strict and 44/47 implemented estimates are
withdrawn: they counted historical qualifications invalidated by later
renderer/runtime changes. This capture is the first corrected timestamped
snapshot, so no percentage-points/hour rate is inferred from those invalid
estimates. Subsequent snapshots must compute elapsed time and rate from this
committed baseline.

## Follow-up — native Canvas milestone

Commit `dc97688271642f3c4fc5c55a84347dc76f0290c3` at
`2026-08-29T14:41:59+02:00` restores public `Canvas.render` through one lazy,
reusable, layerless Metal coordinator per Canvas. The production Scene2/Scene3
lowering, resource leases, caches, readback, and explicit teardown are shared
with the window path. Its 600-frame release fixture completed in 1.94 seconds
with exact pixels and zero Metal-handle delta. The dead public staging function
that rejected image and glyph resources was removed.

This moves R2 and R4 from pending-local to provisional: **11 strict, 26
provisional, 2 pending local, and 8 pending external**. Strict plus provisional
coverage is now **37/47 = 78.72%**; strict completion remains **11/47 =
23.40%**. The two local blockers are now R1 manifest renewal and R10 qualifying
evidence.

The interval from the corrected baseline commit time
`2026-08-29T14:34:59+02:00` is exactly 420 seconds (0.1167 hours). Implemented
or provisional coverage increased by 2/47 = 4.255 percentage points, a short
interval rate of **36.47 percentage points/hour**. Strict completion changed by
zero, so its rate was **0.00 percentage points/hour**. This seven-minute slice
is a measured checkpoint, not an ETA or a sustainable-rate forecast.

## Follow-up — R1 manifest renewal

At production commit `03c534dfe703e4e5d730b1f344dd4c1411aed6b5`
(`2026-08-29T14:44:36+02:00`), the stable API review found exactly the intended
Canvas and `Scene.Private` changes, no removed stable module, and 127 total
stable modules. The regenerated manifest check passes. R1 therefore moves from
pending-local to provisional: **11 strict, 27 provisional, 1 pending local,
and 8 pending external**, or **38/47 = 80.85%** strict-plus-provisional
coverage. The only remaining concrete local implementation/evidence blocker is
R10; final integrated reruns still govern all provisional rows.

## Correction — M4 has no offline Xcode dependency

The initial audit inherited an obsolete 2026-08-27 M4 blocker for an offline
`.air`/`.metallib` build and runtime/offline image parity. Commit `8ec473e`
removed that pipeline from the authoritative plan. Current M4 uses deterministic
runtime MSL compilation/reflection/linking through the public Metal API, and
`specification/metal.md` explicitly states that Prismel has no dependency on
the Xcode command-line shader tools.

M4 is therefore provisional rather than external. The repository still needs
ordinary Apple developer/Command Line Tools facilities—`clang++`, SDK headers,
and Metal/QuartzCore frameworks—to compile its Objective-C++ FFI. It does not
invoke `xcrun metal` or `metallib`, require the Xcode IDE, or ship an offline
shader artifact. M10 remains external for GPU capture/counters and the required
sanitizer/Guard Malloc/Leaks evidence, not for offline shader compilation.

## Correction — visible drawable presentation is not yet proved

Captured at `2026-08-29T16:04:51+02:00` on commit
`28f95deb185faba4062539a456cdf4a1c4a84850`. A source-to-drawable audit found
that the production Scene execution path renders into its owned RGBA target,
while surface acquisition yields a drawable that is subsequently presented
without a typed GPU transfer from that target. The existing pixel assertions
read the owned target, not the acquired visible drawable. They therefore prove
native Metal rendering and readback, but not visible presentation.

This finding moves M6, O7, R5, R8, and R12 from provisional to pending-local.
R10 was already pending-local and remains there. The corrected status is
**11 strict, 22 provisional, 6 pending local, and 8 pending external**. Strict
plus provisional coverage is **33/47 = 70.21%**; strict completion remains
**11/47 = 23.40%**. These percentages classify gate evidence and are not an
estimate of source-code implementation completion.

The SDL3 implementation and all strict S gates remain **100% complete**. The
structural deletion of selectable software-rasterizer, SDL2/Tsdl, OpenGL,
headless, Wap, and web fallbacks also remains **100% complete**. Neither fact
closes visible presentation: a native-only product can still render the right
pixels into an internal Metal texture and fail to put them into the acquired
window drawable.

The exact false-positive mechanism, affected test paths, preserved evidence,
and required typed GPU-only RGBA-source-to-BGRA-drawable proof are recorded in
[`visible_drawable_audit_2026-08-29.md`](visible_drawable_audit_2026-08-29.md).
This correction supersedes only prior claims that internal-target captures
proved visible pixels; it does not rewrite or invalidate their independently
measured rendering, lifecycle, counter, or ownership evidence.

## Follow-up — typed visible Metal presentation

Commit `2de959ef1ce17f1f806a020c94f333897669332d` at
`2026-08-29T17:01:22+02:00` closes the implementation defect identified by the
visible-drawable audit. Scene execution now submits a typed producer queue and
owned RGBA8 source with each acquired frame. A classic final pass appends the
RGBA8-to-BGRA8 conversion and drawable schedule to the producer command buffer;
a Command4-only final pass uses the ordered same-queue classic fallback until
Command4 has a bounded submission-scoped drawable lifetime.

The exact test renders asymmetric RGBA bytes, reads the actual private
`CAMetalDrawable` back through a GPU blit, and checks BGRA bytes at frames 1,
2, 60, and 600 plus resize. Production layers remain framebuffer-only. The
affected release suites pass with exact Scene2/Scene3/runtime pixels, injected
pre-commit retry and terminal-error cleanup, bounded frame/source ownership,
and zero Metal-handle deltas. The retained Scene2 path measured 33,105 allocated
and 969 promoted bytes/frame against unchanged 100,000/1,024-byte ceilings.
An isolated clean worktree of the commit also passes
`dune build --profile release @all`.

M6, O7, R5, and R8 move from pending-local to provisional. R12 remains local
until its 30-minute stability evidence is renewed on this renderer, and R10
remains local until workload-equivalent qualification completes. The resulting
status is **11 strict, 26 provisional, 2 pending local, and 8 pending
external**, or **37/47 = 78.72%** strict-plus-provisional coverage. Strict
completion remains **11/47 = 23.40%**.

The interval from the corrected visible-presentation capture at
`2026-08-29T16:04:51+02:00` is 3,391 seconds (0.9419 hours). Coverage increased
by 4/47 = 8.511 percentage points, a measured rate of **9.04 percentage
points/hour**. Strict completion changed by zero, so its measured rate remains
**0.00 percentage points/hour**. This interval is an implementation checkpoint,
not an ETA or a sustainable-rate forecast.

## Follow-up — native-only static renewal

At `2026-08-29T18:38:13+02:00`, clean commit `5d3d90a` again passed the D1
source-deletion inventory, the exact D2 token scan, and the D8 selector/fallback
source audit. The only D2 matches are the two explicitly permitted generated
SDL3/Metal exception families. The detailed commands and classifications are
recorded in
[`d1_d2_d8_static_renewal_2026-08-29.md`](d1_d2_d8_static_renewal_2026-08-29.md).

These three gates remain provisional pending the final twice-clean integrated
run, so the count remains **11 strict, 26 provisional, 2 pending local, and 8
pending external**: **37/47 = 78.72%** strict-plus-provisional and **11/47 =
23.40%** strict. From the preceding `17:01:22` checkpoint, 5,811 seconds
(1.6142 hours) elapsed with zero classification change, hence both measured
coverage and strict-completion rates were **0.00 percentage points/hour** for
this audit interval.
