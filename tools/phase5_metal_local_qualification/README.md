# Phase 5 local Metal qualification

This current-commit aggregate is indexed to the locally actionable parts of
M2/M3/M5/M6. It deliberately runs after native R11 benchmarking so ownership
and presentation stress do not interfere with benchmark measurements.

| Requirement | Local evidence in this aggregate |
|---|---|
| M2 | Safe-layer ARC parent/child retention, stale and idempotent destroy, current-device checks, normal conformance, and every 10,000-cycle ownership lane under `/usr/bin/leaks`. |
| M3 | `test_metal_resource100_safe` exercises the supported local-device resource matrix, exact capability branches, failure atomicity, copied attachment lifetime, and 10,000-cycle descriptor/attachment access. Unsupported families remain explicit skips/rejections. |
| M5 | Presentation adapter/complete/snapshot models cover three drawable slots, resize-invalidated snapshots, occluded/timeout/lost classification, injected failures, and one-shot presentation. Safe and native lifecycle tests cover real M1 acquisition, completion retention, and exact pixels. |
| M6 | The native lifecycle and safe facade cover resize and completion; presentation 10k plus snapshot 10k prove zero live-handle delta and bounded teardown. The Leaks stress lanes enforce settled RSS tolerances and zero reported leaks across buffers, textures/samplers/views, heaps/resources, sparse, residency, backed/shared/IO/external resources. |

The aggregate does **not** claim M3+ hardware coverage, alternate macOS/SDK
configurations, sanitizer configurations other than the committed Leaks lane,
window-server behavior unavailable to these tests, or external-machine gates.

## Current local result

On the current Apple M1 commit, all twelve ownership lanes reported `0 leaks`
and stayed within their settled RSS thresholds. Measured handle counts ranged
from 20,000 to 100,000 per lane; the external-buffer lane also completed 10,000
deferred callbacks. The presentation lifecycle completed 10,000 frames with no
live-handle delta, and the native presentation fixture passed three-slot
acquisition, resize, timeout policy, completion retention, and exact pixels.

The broader monolithic conformance executable passes functionally, but wrapping
that entire process in Leaks currently reports 2,976 bytes in 22 roots: AGX
Metal 4 binary-function/dynamic-library objects, one dispatch group, and OCaml
domain stack caches. This is recorded as a local blocker and is not hidden by
the green ownership-lane aggregate; M2's all-process zero-Leaks claim therefore
remains unpromoted.

Run with:

```sh
opam exec -- dune runtest tools/phase5_metal_local_qualification --force
```
