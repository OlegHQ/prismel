# Phase 5 B0 pre-switch freeze — 2026-08-27

This is rollback evidence, not authorization to switch defaults or delete the
legacy stack. The rollback point is `20e03d03ddf1ff160b3c643dff18399a9815188d`.
The frozen plan SHA-256 remains
`75cb47632aa2b26199677560c6382b8b94786af5f704867b40d306ccefbe19d3`
and the old public API manifest remains byte-pinned at
`ca6861c5dfbfafd6ea64d1c9837bc218e2af0dfe83a5b9589183384ffefcb7e2`.

The machine-readable companion freezes the Basic, PXUI-like, Canvas and
Scene3 native/software hashes already qualified on the M1 at frames
1/2/60/600. Basic, PXUI and Canvas are byte-exact. Scene3 retains the reviewed
per-channel tolerance of 3, while the current corpus is byte-identical. Upload
bytes are pinned at 60/480/180/240 respectively. It also freezes the
backend-neutral RGBA bytes and ownership invariants formerly observable only
inside the SDL2 halves of the Image, Font and Canvas snapshot tests: copied
RGBA, generation replacement, pitch 28, empty-text no-op and the 256-entry font
cache ceiling. SDL3/Raster2 execution remains covered by the committed
runtime-next resource and parity fixtures; the old SDL2 tests remain in place
until the atomic switch and are not weakened by this freeze. The pure
`phase5_b0_snapshot_freeze` fixture reconstructs those three frozen snapshots
as packed `Raster2.Surface` values and checks copied storage, replacement,
pitch/alpha, density-key identity, empty text, and the cache bound without
linking SDL2. It is the backend-neutral half used by B0; SDL3 decode and
presentation remain independently exercised by their existing focused tests.

The only reviewed future API-delta allowlist is:

- private Tsdl handle types under `Prismel.Low`;
- private Tsdl handle types under `Prismel.Private`.

No delta is applied at B0. High-level modules, examples and sketches remain
frozen. The acceptance tree IDs for Basic, PXUI, Canvas and shattered_cube are
recorded in the JSON and checked against `HEAD` ancestry.

R1 local freeze, R2/R3 private parity, R4 resource lifecycle, R5–R8 local
target/input/web behavior, R9 structural batching and the three local R12
long-run lanes have committed evidence. R10 remains short of the frozen
interleaved five-by-30-second comparison; R11 still lacks the final accepted
native visible/hidden protocol; external OS/M3/Xcode/sanitizer and reviewer
gates remain open. Consequently B0 is reproducible, but D1 and the default
selection switch remain blocked.

Validation:

```text
opam exec -- dune runtest tools/gpu_migration --force
opam exec -- dune runtest test/dependency_direction --force
_build/default/tools/gpu_migration/api_manifest.exe --root . --check
```
