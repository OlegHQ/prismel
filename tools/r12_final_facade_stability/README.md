# R12 final-facade stability protocol

This harness imports only the installed `prismel.prismel_next_api` facade. Each
target cycles Basic, PXUI-like, Canvas/image, and Scene3 scenes, records exact
frames 1/2/60/600, and then continues for 30 minutes. Samples use a fixed
256-entry ring. It performs real alternating window sizes, stable-identity image
reload (including failed-reload retention), short-lived Canvas/image pairs,
audio sample play/stop/destruction, and changing Scene3 meshes. The validator
requires zero facade resource/runtime/cache counters after teardown and at most
5% RSS range in the final sample quarter. The read-only runtime diagnostic uses
the coordinator's owned-resource and cache counts. Native reports also use the
typed Metal deferred-release-queue counter; deterministic headless/web reports
encode that inapplicable counter as JSON null with
`release_queue_counter_supported=false`. Native validation also requires live
Metal handles to return to the explicit pre-runtime baseline and requires the
created-handle delta to equal the released-handle delta.
It also proves that retained samples are the final fixed-ring window (rather
than an earlier flat interval), enforces the frozen 10-second sampling period,
checks live-resource/sample facts, and rejects policy or canonical-hash drift.
Every retained observation also enforces explicit fixed bounds: at most 512
runtime resources, 2,048 cache entries, and (on native) 256 pending deferred
Metal releases. These are schema-checked policy constants, so weakening or
omitting a bound invalidates both smoke and qualification reports. Teardown
zeroes remain independently required; a bounded plateau cannot hide a leak at
shutdown.

Run the three release lanes separately:

```sh
opam exec -- dune build --profile release tools/r12_final_facade_stability/r12_final_facade_stability.exe tools/r12_final_facade_stability/validate_r12_final_facade_stability.exe
for target in native headless web; do
  _build/default/tools/r12_final_facade_stability/r12_final_facade_stability.exe --target "$target" --scenario all --minutes 30 --sample-every 10 --report "_build/r12-$target-30m.json"
  _build/default/tools/r12_final_facade_stability/validate_r12_final_facade_stability.exe "_build/r12-$target-30m.json"
done

# Validate the complete set. Hash equality is intentionally not required:
# duration-driven lanes may complete different frame counts.
_build/default/tools/r12_final_facade_stability/validate_r12_final_facade_stability.exe \
  --complete-set _build/r12-native-30m.json _build/r12-headless-30m.json \
  _build/r12-web-30m.json
```

The Dune `runtest` alias runs only 600-frame headless/web smoke lanes. It is not
30-minute evidence and cannot qualify R12.
