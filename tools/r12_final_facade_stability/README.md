# R12 final-facade stability protocol

This harness imports only the installed `prismel.prismel_next_api` facade. Each
target cycles Basic, PXUI-like, Canvas/image, and Scene3 scenes, records exact
frames 1/2/60/600, and then continues for 30 minutes. Samples use a fixed
256-entry ring. The validator requires zero facade resource/window/cache/release
counters after teardown and at most 5% RSS range in the final sample quarter.

Run the three release lanes separately:

```sh
opam exec -- dune build --profile release tools/r12_final_facade_stability/r12_final_facade_stability.exe tools/r12_final_facade_stability/validate_r12_final_facade_stability.exe
for target in native headless web; do
  _build/default/tools/r12_final_facade_stability/r12_final_facade_stability.exe --target "$target" --scenario all --minutes 30 --sample-every 10 --report "_build/r12-$target-30m.json"
  _build/default/tools/r12_final_facade_stability/validate_r12_final_facade_stability.exe "_build/r12-$target-30m.json"
done
```

The Dune `runtest` alias runs only 600-frame headless/web smoke lanes. It is not
30-minute evidence and cannot qualify R12.
