# Phase 5 Runtime public-owner candidate — 2026-08-27

The non-live candidate in `tools/phase5_switch` specifies the atomic B5
replacement of old `lib/runtime` by a narrow `Runtime` alias over
`Runtime_next_compat`, which in turn owns translation into
`Runtime_next_orchestrator`.

The checked preservation manifest records:

- 16 directly mapped high-level values;
- two intentional high-level adaptations (`selected_target` reports invalid
  configuration and file drops carry owned bytes);
- exactly five raw/private omissions: raw-renderer `present` and the four
  legacy `Private` selection/pacing/scaling helpers;
- three directly mapped and three target-neutral adapted public types; and
- no surviving sibling library with a direct dependency on old `runtime`.

Legacy Prismel is the sole old-Runtime consumer and belongs to the same atomic
deletion batch. External consumers retain the unchanged public library name
`prismel.runtime`.

The candidate depends only on `runtime_next_compat`. The checker proves that
the compatibility facade directly depends only on the orchestrator,
`scene_execution`, and `ogpu`; its public interface exposes neither `Tsdl` nor
raw `Wap` values. Within the Runtime-next library group, direct Wap dependency
is limited exactly to the typed owned `runtime_next_web` and
`runtime_next_input` boundaries.

Reproduce with:

```sh
opam exec -- dune build tools/phase5_switch/test_runtime_owner_candidate.exe
_build/default/tools/phase5_switch/test_runtime_owner_candidate.exe \
  --root . \
  --candidate tools/phase5_switch/runtime_owner_candidate.dune \
  --manifest tools/phase5_switch/runtime_owner_candidate.json
```

Expected result:

```text
B5 Runtime owner candidate passed: 18 portable values + 5 exact raw omissions, 6 public types, 0 surviving old-Runtime consumers, typed transport only
```

This candidate does not mutate the live owner. It may be activated only in the
reviewed atomic switch that deletes old `lib/runtime`; the two owners must
never coexist under `prismel.runtime`.
