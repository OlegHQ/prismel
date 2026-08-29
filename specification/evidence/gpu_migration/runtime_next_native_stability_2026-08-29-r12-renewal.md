# Native Metal stability qualification renewal — 2026-08-29

R12 and the integrated O6 bounded-lifetime lane pass on the clean source commit
`3d736462e05a9b5cf490a95a23c19f35d90657d8`. This run exercises the production
SDL3 + OGPU Metal path with changing mesh payloads, retained plans, periodic
drawable resize, and periodic framebuffer capture for 30 minutes after the
scoped-presentation and transient-image texture reuse work.

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
  --report _build/runtime-next-native-stability-30m-schema5.json
_build/default/tools/runtime_next_native_stability/validate_runtime_next_native_stability.exe \
  _build/runtime-next-native-stability-30m-schema5.json
```

The validator printed `O6 native lifetime/bounds report: valid`. The harness
recorded the same clean commit before and after the run. The ignored raw report
is 198,502 bytes with SHA-256
`bb985327f93c48b704beeebc171a5b67f7036c7c704ff79efd9a5d575e0f0ab1`.
The compact committed summary is
`runtime_next_native_stability_2026-08-29-r12-renewal.json`.

Host: Apple M1, 16 GiB RAM, arm64 Darwin 25.4.0. The report completed at
2026-08-29T22:55:00+0200.

## Result

- 215,505 rendered frames, 718 resize events, and 359 capture events.
- All payload-changing, resize, capture, and retained-plan workload switches
  remained enabled.
- Settled RSS first-half high-water was 85,136 KiB and second-half high-water
  was 85,312 KiB. The latter did not exceed the former plus the fixed 8,192 KiB
  plateau allowance.
- The final retained window was 84,560–85,024 KiB, a 0.5487% range against the
  5% limit.
- Metal creation and release deltas matched exactly at 1,294,508. Final live
  handles and pending releases were both zero.
- The mesh, pipeline, and retained-plan caches all returned to zero at
  teardown.
- The retained-plan cache built and missed exactly 80 plans, then recorded
  215,425 hits with zero evictions and a declared capacity of 256. Periodic
  attachment replacement therefore did not rebuild or retain plans.

This renews R12/O6 for commit `3d73646`. Because the final release contract
requires every gate on one clean commit, later runtime/backend changes must
repeat this qualification before the final D7 release declaration.
