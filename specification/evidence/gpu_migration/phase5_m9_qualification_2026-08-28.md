# Phase 5 M9 qualification — 2026-08-28

Status: **Proven** by evidence commit
`56467abea0cadeab8bd4ccbbbcbce74e1dd2dfca`.

The frozen release benchmark ran on clean source commit
`ed4a8f460193614909f63047fee0f55f918febab` with 1,000,000 iterations,
seven samples, the release profile, Apple M1, macOS 26.4.1, SDK 26.5, and
OCaml 5.3.0. The batched/native median ratio was `0.9948251072`, below the
frozen `1.05` maximum. Direct calls allocated `24.000144` bytes/query and the
batched call allocated `0.000144` bytes/query. The evidence validator passed;
its negative self-test rejected both a missing source commit and a dirty-after
measurement.

Authorities:

- `phase5_m9_ffi_final_ed4a8f4.json`
- `phase5_m9_ffi_final_ed4a8f4.md`

## Strict ledger update

The original 47-row audit recorded 11 Proven, 27 Pending, and 9 External
gates. R9 was subsequently proven by
`phase5_r9_qualification_2026-08-28.md`, bringing the ledger to 12. This M9
qualification brings it to exactly **13 Proven gates**. No other gate status
changes in this update.

Strict completion is therefore **13/47 = 27.6596%**. The nine External gates
remain in the release denominator. Excluding them only for the scheduling
view gives **13/38 = 34.2105%** locally closed coverage.

The counts were checked mechanically from the original 47-row table plus the
two committed qualification overlays:

```text
base=11 overlays=2 proven=13 total=47 external=9 local=38 strict=27.6596 local_pct=34.2105
```
