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
| M1–M10 | 2 | 4 | 0 | 4 |
| O1–O9 | 1 | 6 | 0 | 2 |
| R1–R12 | 0 | 8 | 4 | 0 |
| D1–D8 | 0 | 5 | 0 | 3 |
| **Total** | **11** | **23** | **4** | **9** |

The native code-path cutover is structurally complete: the production tree has
one SDL3 window/input lifecycle and one OGPU/Metal renderer, with no selectable
SDL2, Tsdl, OpenGL, software-rasterizer, headless, Wap, or web fallback. This
is **100% structural cutover**, not the release completion percentage.

Strict release completion is **11/47 = 23.40%**. Strict plus provisional
implementation/evidence coverage is **34/47 = 72.34%**. The remaining
**13/47 = 27.66%** consists of four local and nine external gates.

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
