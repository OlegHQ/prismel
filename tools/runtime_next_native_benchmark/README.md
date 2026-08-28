# Runtime-next native benchmark evidence

The R11 protocol invokes and measures `sketches/shattered_cube/main.exe` itself.
Its R11-only entrypoint cooks the sketch's own graph, validates the 18,278-piece
artifact cardinality and render hash, packs that freshly cooked terminal mesh,
and renders it through the next native execution path at the frozen 1200×760
extent without replacing the process.

Reports identify the sketch as both `invoked_executable` and
`measured_executable`, carry `status: actual-sketch-cooked-and-rendered`, and
remain `evidence_class: candidate` with `frozen_r11_closure: false`. The
protocol also validates the frozen cardinality and dimensions, zero replacement
upload, one draw/pass/submission per frame, one resident cache entry, and either
measured GPU counters or an explicit unsupported/null result.

This removes the delegated-renderer blocker but does not by itself close R11.
Comparable R10 envelope evidence, clean full-length visible and hidden runs,
RSS plateau evidence, and any unavailable GPU counters remain honest
qualification requirements. Each report records and validates observed SDL
window visibility rather than trusting the requested mode alone.
