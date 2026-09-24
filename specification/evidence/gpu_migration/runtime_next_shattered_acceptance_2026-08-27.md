# Runtime-next shattered acceptance correctness — 2026-08-27

The correctness harness reproduces the frozen `sketches/shattered_cube`
target-neutral SOP graph without editing the acceptance sketch, cooks it through
`Session`, compiles `Packed_pieces`, and uses `mesh_for_node` for the terminal
render representation. The cook executable is deliberately separate from the
native executable: linking Prismel's legacy comparison stack into the SDL3-only
native process is structurally invalid. A typed-versioned binary artifact is
the neutral boundary between them.

The result is exactly 18,278 pieces, 278,368 triangles, and 835,104 render
vertices. Independent one-domain and four-domain cooks produced identical
topology, attribute, group/order, and terminal-render hashes. One-domain cook
took 19.213 seconds, four-domain cook 7.789 seconds, and terminal packing took
0.118 seconds on the recorded M1 host.

The finite native correctness smoke uploads the actual 60,127,488-byte packed
terminal mesh once through the stable prepared identity, then records zero
replacement upload and one draw/pass/backend call. Its single measured frame is
not performance evidence and must not replace the frozen R11 long-run protocol.

```text
opam exec -- dune build --force \
  tools/runtime_next_native_benchmark/shattered_acceptance_cook.exe \
  tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe
_build/default/tools/runtime_next_native_benchmark/shattered_acceptance_cook.exe \
  --output _build/native-bench-results/shattered-acceptance.artifact
_build/default/tools/runtime_next_native_benchmark/runtime_next_native_benchmark.exe \
  shattered --acceptance-artifact \
  _build/native-bench-results/shattered-acceptance.artifact \
  --warmup 1 --samples 1 \
  --report _build/native-bench-results/shattered-acceptance-correctness.json
```
