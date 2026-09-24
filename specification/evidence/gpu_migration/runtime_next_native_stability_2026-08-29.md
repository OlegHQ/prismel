# Native Metal stability qualification — 2026-08-29

R12 and the integrated O6 bounded-lifetime lane pass on the clean source commit
`a50e9809a9f968f5d98d8aba225601a95f7fe3e7`. This run exercises the production
SDL3 + OGPU Metal path with changing mesh payloads, retained plans, periodic
drawable resize, and periodic framebuffer capture for 30 minutes.

## Command and provenance

The harness and independent validator were built and run in Dune's release
profile with the repository-local OCaml 5.3.0 switch:

```sh
opam exec --switch=. -- dune build --profile release \
  tools/runtime_next_native_stability/runtime_next_native_stability.exe \
  tools/runtime_next_native_stability/validate_runtime_next_native_stability.exe
opam exec --switch=. -- \
  _build/default/tools/runtime_next_native_stability/runtime_next_native_stability.exe \
  --minutes 30 \
  --report _build/runtime-next-native-stability-30m-schema5-a50e980.json
_build/default/tools/runtime_next_native_stability/validate_runtime_next_native_stability.exe \
  _build/runtime-next-native-stability-30m-schema5-a50e980.json
```

The validator printed `O6 native lifetime/bounds report: valid`. The harness
recorded the same clean commit before and after the run. The ignored raw report
is 198,381 bytes with SHA-256
`ece644edbddc027adc44e0a72d63a9564195ffed64a0d44f21d4b5129f111253`.
The compact committed summary is
`runtime_next_native_stability_2026-08-29.json`.

Host: Apple M1, 16 GiB RAM, arm64 Darwin 25.4.0. The report completed at
2026-08-29T13:28:01+0200.

## Result

- 215,429 rendered frames, 718 resize events, and 359 capture events.
- All payload-changing, resize, capture, and retained-plan workload switches
  remained enabled.
- Settled RSS first-half high-water was 96,016 KiB and second-half high-water
  was 86,768 KiB. The latter did not exceed the former plus the fixed 8,192 KiB
  plateau allowance.
- The final retained window was 85,744–86,768 KiB, a 1.1943% range against the
  5% limit.
- Metal creation and release deltas matched exactly at 1,078,620. Final live
  handles and pending releases were both zero.
- The mesh, pipeline, and retained-plan caches all returned to zero at
  teardown.
- The retained-plan cache built and missed exactly 80 plans, then recorded
  215,349 hits with zero evictions and a declared capacity of 256. Periodic
  attachment replacement therefore did not rebuild or retain plans.

This closes R12/O6 for commit `a50e980`. Because the final release contract
requires every gate on one clean commit, any later runtime/backend change must
repeat this qualification before the final D7 release declaration.
