# GPU migration evidence

The frozen migration plan has SHA-256
`75cb47632aa2b26199677560c6382b8b94786af5f704867b40d306ccefbe19d3`.
Machine-readable Phase 0, Phase 1, and incremental Phase 2 records live beside
this file. Large machine-local build products and diagnostic traces are
identified by command and content hash in those records.

Phase 1 has passed its technical gates on the recorded M1 lane. Independent
human review remains pending and must be repeated on the final all-gates commit;
these rows therefore do not constitute final release sign-off.

| Gate | Commit | Command | Environment | Result | Artifacts | Reviewer |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | `7a4ed29ca0e66f89d751d9acb03073fda0344cbf` (clean) | `opam exec -- dune runtest lib/sdl3 lib/sdl3_image lib/sdl3_ttf lib/sdl3_mixer --force` | Apple M1, macOS 26.4.1, OCaml 5.3.0, SDL3 3.4.14 | Pass: exact core/extension header, linked-library, provenance, and version checks | `phase1_sdl3.json`; four generated inventories | Pending independent final sign-off |
| S2 | `7a4ed29ca0e66f89d751d9acb03073fda0344cbf` (clean) | focused SDL3 tests plus `shasum -a 256` over generated layout/ABI artifacts | dev, release, ASan, UBSan arm64 builds | Pass: zero unreviewed symbols and identical generated layout/ABI identity | `phase1_sdl3.json`; `generated_layout.json`; generated ABI headers | Pending independent final sign-off |
| S3 | `7a4ed29ca0e66f89d751d9acb03073fda0344cbf` (clean) | `check_sdl3_memory.exe` in `address`, `undefined`, and `leaks` modes | sanitizer-built OCaml 5.3 for ASan; Apple Clang 21; Instruments Leaks | Pass: 10/10 tests in each lane, zero diagnostics, complete constructor/decoder failure matrix | `phase1_sdl3.json`; `check_sdl3_memory.ml`; scoped ASan suppression | Pending independent final sign-off |
| S4 | `7a4ed29ca0e66f89d751d9acb03073fda0344cbf` (clean) | `SDL_VIDEODRIVER=dummy opam exec -- dune exec lib/sdl3/test_sdl3_events.exe` | Apple M1, SDL dummy video | Pass: 33 typed events plus frozen Runtime-shaped logical-coordinate trace | `phase1_sdl3.json`; `test_sdl3_events.ml` | Pending independent final sign-off |
| S5 | `7a4ed29ca0e66f89d751d9acb03073fda0344cbf` (clean) | `SDL_VIDEODRIVER=dummy opam exec -- dune exec lib/sdl3/test_sdl3.exe` | OCaml 5.3 initial-domain validation | Pass: wrong-domain, blocking-wait, ownership, and callback policy checks | `phase1_sdl3.json`; `sdl3.mli`; core conformance test | Pending independent final sign-off |
| S6 | `7a4ed29ca0e66f89d751d9acb03073fda0344cbf` (clean) | `opam exec -- dune exec lib/sdl3/test_sdl3_metal.exe` and dummy 100,000-cycle stress | Retina Apple M1 native window plus dummy video | Pass: DPI, lifecycle, CAMetalLayer, resize/state transition, and recreation checks | `phase1_sdl3.json`; Metal/lifecycle tests | Pending independent final sign-off |
| S7 | `7a4ed29ca0e66f89d751d9acb03073fda0344cbf` (clean) | image, TTF, mixer focused executables and `opam exec -- dune runtest --force` | SDL dummy video/audio plus native font/image decoders | Pass: image/font/audio/resource and exact web-mirroring parity | `phase1_sdl3.json`; 19 image fixtures; TTF/mixer tests | Pending independent final sign-off |
| S8 | `7a4ed29ca0e66f89d751d9acb03073fda0344cbf` (clean) | fresh local switch bootstrap, `dune build @all @doc`, full tests, release packaging, dev/release installed consumers | detached clean checkout `/private/tmp/prismel-sdl3-clean.OR9d4e` | Pass: declared conf probes and Dune packages work without original-checkout paths | `phase1_sdl3.json`; four conf packages; discovery/consumer tests | Pending independent final sign-off |

Phase 2 is in progress. The rows below are qualified partial evidence only; no
M gate or Phase 2 completion is claimed while the SDK inventory still contains
unreviewed in-scope declarations or any M1-M10 requirement remains open.

| Gate slice | Commit | Command | Environment | Result | Artifact |
| --- | --- | --- | --- | --- | --- |
| M9 FFI baseline | `3d4671a08c297f04dca47fd704b224128346ce36` (clean) | `opam exec -- dune exec --profile release tools/bench_metal_ffi.exe -- --iterations 1000000 --samples 7 --profile release` | Apple M1, macOS 26.4.1, SDK 26.5, OCaml 5.3.0 | Pass: batched/native median ratio 1.000149; direct 24.000144 bytes/query; batched 0.000144 bytes/query | `phase2_metal_ffi_baseline.json` |
