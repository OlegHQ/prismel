# Phase 1 SDL3 qualification audit — 2026-08-27

This audit compares the frozen S1–S8 requirements in `NEW_GPU_STUFF.md` with
the current SDL3 core and extension libraries. It does not modify the frozen
plan and does not replace the signed evidence in `phase1_sdl3.json`.

| Gate | Current executable evidence | Result | Remaining limitation |
| --- | --- | --- | --- |
| S1 | Four generated inventories/provenance records; generator drift checks; linked-version checks in each safe library test | Green | Release rejection of a future prerelease build remains packaging-environment dependent. |
| S2 | Core layout/ABI manifest and compiled assertions; four inventories report zero `unreviewed`; focused generator checks pass | Green | Cross-profile layout identity is recorded from the qualified commit, not rebuilt by this audit. |
| S3 | Core failure/stress tests, extension decoder/device failures, 100,000 surface/window cycles, recorded ASan/UBSan/Leaks lanes | Green | Sanitizer and Instruments results are historical machine evidence and need renewal after native ownership changes. |
| S4 | 33-event typed trace plus `test/sdl3_platform_harness.ml` logical Prismel translation | Green | Physical controller/pen/touch hardware delivery is represented by injected native event fixtures. |
| S5 | Initial-domain rejection and blocking-wait runtime-lock tests; public API documents callback policy | Green | No production callback API currently crosses from an SDL-created foreign thread into OCaml. |
| S6 | Real Metal/Retina lifecycle fixture plus dummy-driver 100,000-cycle stress | Green | A real 1x external display/monitor move remains qualified by the recorded host run. |
| S7 | 19 image formats, malformed/reload behavior, font discovery/metrics/cache, mixer lifecycle/device failure | Green | Web audio mirroring is covered by the higher-level frozen trace rather than an extension-only browser process. |
| S8 | Four conf packages, discovery tests, installed-consumer tool, recorded clean bootstrap for dev/release/static/dynamic | Green | Fresh-machine bootstrap is historical and must be rerun when package metadata or minimum versions change. |

Additional Phase 1 completion conditions:

- Production SDL3 binding modules contain no `Ctypes`, `Foreign.foreign`, or
  `foreign_value` use. `test_sdl3_no_dynamic_ffi.exe` now enforces this directly.
- SDL3 dependencies remain below Runtime/Prismel and are covered by
  `test/gpu_dependency_direction.ml`.
- Current focused core/image/TTF/mixer and Phase 1 evidence aliases pass.

The largest gaps are therefore evidence-renewal tasks requiring a clean host,
sanitizers, Instruments, display hardware, or packaging installation. They are
not missing binding implementation on the audited tree.
