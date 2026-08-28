# R12 post-switch prerequisite audit — 2026-08-28

This is short smoke evidence, not the required 30-minute R12 qualification.
It exercises the installed `prismel.prismel_next_api` facade without changing
the default public selection.

## Passing prerequisites

The release-profile Dune R12 alias passed both 600-frame headless and web
`scenario=all` lanes and their cross-target deterministic comparison.  Each
lane exercised frames 1, 2, 60, and 600, resize churn, watched image reload and
failed-reload retention, Canvas/image create-destroy cycles, dummy audio
lifecycle, changing Scene3 meshes, bounded samples, and zero teardown counters.

Separate 600-frame native Basic, PXUI, Canvas, and Scene3 lanes completed.  This
shows that each workload and its resize/reload/audio/teardown churn is locally
viable in isolation; the individual reports are diagnostic because the frozen
validator intentionally accepts only `scenario=all`.

## Native combined blocker

The real native `scenario=all` lane fails before producing an acceptable report:

```text
Prismel_next_execution.step: Ogpu_metal.Sampler.retain: sampler is destroyed
```

The same image reload succeeds in the isolated Canvas lane.  Failure requires
alternating Basic/PXUI/Canvas/Scene3 plans, which narrows the defect to retained
cross-plan resource invalidation rather than image decode or the standalone
reload lifecycle.  R12 native endurance must not start until the combined
600-frame smoke passes and returns Metal live handles and the deferred release
queue to their pre-runtime baselines.

## Reproduction

```text
opam exec -- dune runtest --profile release tools/r12_final_facade_stability
_build/default/tools/r12_final_facade_stability/r12_final_facade_stability.exe \
  --target native --scenario all --frames 600 --sample-every 0.01 \
  --report _build/r12-native-prereq-smoke.json
```

The first command exits zero.  The second currently exits 2 with the destroyed
sampler diagnostic above.  No duration or leak qualification is claimed.
