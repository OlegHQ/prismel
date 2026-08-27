# Phase 5 API manifest gate — 2026-08-27

Commit under review: `8827af925567622ec1aedb0856d44c687a6229fa`.
This tooling checkpoint does not approve a public API delta or promote R1/D7.

`tools/gpu_migration/api_manifest.ml` now compares the frozen stable manifest
semantically: module identity, normalized public signature hash, and the exact
legacy-symbol exclusions remain mandatory, while comment/source-byte changes
do not create false API drift. Two reviewed additive Wap boundaries,
`send_audio` and `remove_asset_checked`, are stripped before hashing. This
allowlist is code-local, exact, and does not permit removal or alteration of an
older declaration.

The executable self-tests three cases on every invocation: source-only drift is
accepted, removal is rejected, and signature mutation is rejected. A failing
check now reports exact added, removed, and signature-changed module keys before
suggesting regeneration. This prevents an indiscriminate `--write` from hiding
a large contraction during B5: write mode itself now refuses any contraction
of the stable module-key set before touching either manifest.

The current checker correctly remains red. It reports exactly 40 removed
`prismel.*` modules after they were placed in the Dune `private_modules` set;
the complete list begins with `Assets`, `Audio`, `Camera`, and `Canvas` and ends
with `Vec2` and `Vec3`. The additive Wap methods no longer count as mutation.
The public-module contraction must be restored or reviewed at the owning API
boundary; this evidence-only/tooling lane does not edit Prismel or compatibility
implementation files and does not regenerate `api_stable.json`.

Reproduction:

```text
opam exec -- dune build tools/gpu_migration/api_manifest.exe
_build/default/tools/gpu_migration/api_manifest.exe --root . --check
```

Expected at this checkpoint: exit 1 with `removed (40)` and
`refusing silent contraction`. Once the owning API surface is restored, the
same command must exit zero before R1 or D7 can be marked Proven.

An explicit write-mode regression also returned exit 1 with
`refusing to write a contracted stable API manifest (40 removed)` and preserved
the stable file byte-for-byte at SHA-256
`ca6861c5dfbfafd6ea64d1c9837bc218e2af0dfe83a5b9589183384ffefcb7e2`.
