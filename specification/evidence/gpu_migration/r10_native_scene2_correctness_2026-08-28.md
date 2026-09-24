# R10 native Scene2 correctness authority — 2026-08-28

This evidence closes the native clear-only/fallback-color diagnostic gap for
the frozen Basic and PXUI workloads.  It was captured on an Apple M1 from clean
tracked commit `bc5f5a60b0bb14a568a2a90f1b4dabbb35566ebb`, which contains the
cross-pass Metal attachment-load fix `abe63c2`.

The authority is
[`r10_native_scene2_correctness_authority_2026-08-28.json`](r10_native_scene2_correctness_authority_2026-08-28.json).
Its executable digest is `62836f8e38be195ad17928e0cc28d725`.

The clean authority and an independent repeat were produced with:

```text
_build/default/tools/r10_performance/r10_native_scene2_correctness.exe \
  --report /tmp/native-scene2-authority.json \
  --renderer-commit bc5f5a60b0bb14a568a2a90f1b4dabbb35566ebb
_build/default/tools/r10_performance/r10_native_scene2_correctness.exe \
  --report /tmp/native-scene2-repeat.json \
  --renderer-commit bc5f5a60b0bb14a568a2a90f1b4dabbb35566ebb
_build/default/tools/r10_performance/r10_native_scene2_correctness.exe \
  --validate /tmp/native-scene2-repeat.json \
  --authority /tmp/native-scene2-authority.json
cmp /tmp/native-scene2-authority.json /tmp/native-scene2-repeat.json
```

Validation printed `native Scene2 correctness authority passed`; `cmp` was
byte-identical.  Both scenarios observed the real hide/show/hide transitions.
The validator requires exact framebuffer digests, non-background pixel counts,
and distinct-color counts rather than accepting a tolerance-only or clear-only
capture.

Basic retained 273,236 non-background pixels and 642 distinct non-background
colors at frames 1, 2, 60, and 600.  Its exact digests were
`63defc45b7510c143d556650730bc3c6`,
`606778c375b2f664c9fe271ac25ac874`,
`ba0233dbcb74e08c483f79dd5e55c017`, and
`8d726925c408df76cc5fa36bc92da2df`.  The 800×600 resize contained 437,316
non-background pixels, 642 colors, and digest
`aa71d926c3965e2f6ef5375f8cb26677`.

PXUI retained 251,419 non-background pixels and 1,076 distinct non-background
colors at frames 1, 2, 60, and 600, with digest
`cbb6deb05d2055d6ea0466ee38269e53` at every checkpoint.  The 800×600 resize
contained 268,699 non-background pixels, 1,108 colors, and digest
`1258480171b27ca44f5b715577a6dac7`.

The focused rejection test also proves that the gate rejects clear-only output,
single/fallback-color output, indistinguishable Basic/PXUI output, digest drift,
coverage drift, and dirty provenance.
