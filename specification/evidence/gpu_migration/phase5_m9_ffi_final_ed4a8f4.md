# M9 final FFI qualification — ed4a8f4

- Source: `ed4a8f460193614909f63047fee0f55f918febab`, clean before and after measurement.
- Host: Apple M1, macOS 26.4.1, SDK 26.5, OCaml 5.3.0, release profile.
- Command: `opam exec -- dune exec --profile release tools/bench_metal_ffi.exe -- --iterations 1000000 --samples 7 --profile release --output /tmp/prismel-phase5-m9-ed4a8f4.json`.
- Benchmark executable SHA-256: `487d967779d2661318dbe4ebe58053a9d42eb8c7e789ba5b52c9f2e3972f704d`.
- Validator executable SHA-256: `fa92660a10ee43e8b70933657d706946d5768f081ab4d617647da66697577228`.
- Evidence SHA-256 before import: `deaec98e0b5c8399940ca0596a31a461b4bb5de45a7b5f7de85aa2cbab112195`.
- Result: batched/native median ratio `0.9948251072`, below the frozen `1.05` maximum.
- Allocation: direct `24.000144` bytes/query; batched `0.000144` bytes/query.
- Validator: passed the new evidence. The validator self-test also passed its
  positive fixture and rejected both the missing-commit and dirty-after
  negative fixtures.

The evidence was first requested at its repository destination. The benchmark
correctly aborted because its atomic temporary output was itself visible as an
untracked file to the final clean-worktree check, and removed that temporary.
The successful run therefore wrote to `/tmp`; both built-in source checks ran
while the repository was clean, after which the byte-identical JSON was added
to this directory.
