# Runtime-next native benchmark evidence

The R11 protocol invokes `sketches/shattered_cube/main.exe` first. Its R11-only
entrypoint cooks the sketch's own graph and validates the 18,278-piece artifact
cardinality and render hash, then delegates measurement with `execv` to
`runtime_next_native_benchmark.exe`.

Reports from this path must identify the sketch as `invoked_executable`, the
benchmark as `measured_executable`, and carry
`status: graph-validated-renderer-delegated`, `evidence_class: precursor`, and
`frozen_r11_closure: false`. The protocol executable validates those fields for
every run.

This is precursor evidence only. Because the delegated renderer, rather than
the sketch executable's own rendering loop, is measured, these reports cannot
close frozen gate R11.
