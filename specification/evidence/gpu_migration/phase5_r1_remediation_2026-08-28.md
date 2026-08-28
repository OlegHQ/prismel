# Phase 5 R1 remediation audit — 2026-08-28

Audited commit: `3350ccbfa41c738c78840df4c64d79148eb256b9`.

This is negative evidence, not R1 qualification and not authority
regeneration.  The frozen API authority remains byte-identical at SHA-256
`ca6861c5dfbfafd6ea64d1c9837bc218e2af0dfe83a5b9589183384ffefcb7e2`.

## Findings

`api_manifest --check` reports all 40 `prismel` modules as removed.  Inspection
shows this is not an approved public contraction: `lib/prismel/dune` still uses
`(modules :standard)`, while the manifest scanner treats an explicit `modules`
field as a literal module list and filters out `:standard`, leaving an empty
set.  Regenerating the authority would therefore record a tooling parse error
as an API deletion; the tool correctly refuses that write.

The normalized legacy/next signature comparison reports zero missing and zero
changed declarations, plus six additional declarations:

- `Canvas.Private.copy_to_image`
- `Font.Private.automatic`
- `Font.Private.automatic_counts`
- `Font.Private.automatic_image`
- `Font.Private.borrow_automatic`
- `Font.Private.release_automatic`

All six are migration implementation hooks below `Private`; they are not a
reviewed expansion of the frozen high-level API.  They must be classified by
the signature checker (or hidden by the final packaging boundary), not added to
the stable legacy API authority.

The older Phase-4 R1 freeze also remains red because the frozen acceptance
source comparison now finds committed changes in
`sketches/shattered_cube/{dune,main.ml,r11_native.ml}`.  Those changes require
explicit migration review; refreshing the old hash would not prove that the
sources remained unchanged.

## Reproduction

```text
opam exec -- dune exec tools/phase5_api_signature_gate/phase5_api_signature_gate.exe -- --root .
opam exec -- dune exec tools/gpu_migration/api_manifest.exe -- --root . --check
opam exec -- dune exec tools/gpu_migration/phase4_r1_freeze.exe -- --root .
shasum -a 256 specification/evidence/gpu_migration/api_stable.json
```

Observed exits are respectively 1, 1, and 1.  R1 therefore remains pending.
The smallest honest remediation is to teach the manifest scanner Dune ordered
set semantics for `:standard`, classify only the reviewed private additions in
the normalized-signature gate, review the three shattered-cube source changes,
and rerun all three checks on the final selected clean commit.

## Remediation result

The scanner now evaluates `:standard`, explicit module atoms, and ordered-set
subtraction rather than dropping the standard set.  The normalized-signature
gate narrowly classifies the six private hooks listed above.  Its focused run
now passes with 40/40 modules and zero unreviewed deltas.

With real Prismel module discovery restored, the stable-manifest check reported
one substantive public delta instead of a false 40-module contraction:
`Sketch.run_state` gained `?max_frames` and `Sketch.resize` was added.  Review
confirmed both are backward-compatible migration controls required by the
frozen finite native acceptance and post-resize frame gates.  They preserve the
ordinary unbounded call shape, reject invalid bounds/dimensions, and keep target
selection below Sketch.  `specification/api.md` and both Sketch interfaces
already document the behavior.  The legacy headless smoke now exercises the
public resize boundary and uses `max_frames` for exact termination; the
legacy/next interface and next lifecycle fixture proves exact interface parity,
three-frame termination, resize validation, and exactly-once cleanup.  The
stable manifest and its Phase-4 hash authority were regenerated explicitly for
these two reviewed additions.

The shattered-cube changes remain substantive: they add the R11 native
delegate, artifact validation, and runtime-next dependencies to the unchanged
acceptance sketch.  They are useful qualification work but not source-neutral,
and were therefore reviewed line by line before changing the freeze authority.
The ordinary invocation still reaches the original `Sketch_ui.Environment3.run`
with the same graph, overlay, and configuration; the new branch is reachable
only when the explicit `--r11-renderer` protocol argument is present.  That
branch recooks the same `graph`, rejects every artifact cardinality/render-hash
mismatch, and passes the cooked mesh directly to the native measurement module.
The module retains one prepared draw, checks requested/observed visibility,
warms it before measurement, reports backend upload/draw/pass/cache counters,
and destroys the execution transactionally.

A fresh one/four-domain acceptance cook produced 18,278 pieces, 278,368
triangles, 835,104 vertices, exact topology/attribute/order/render hashes
`f7df96ba5de50db4f964caa418ac4a90`,
`a34503939b89dcd5f6d8503f58b3fd8d`,
`2a4f0c8756d6abc4c0f8cec85c10dc10`, and
`681eacdabdce457de462c3f4fc01a761`.  A focused hidden native run passed the R11
validator with 60,127,488 prepared bytes, zero measurement upload bytes, one
cache entry, and equal draw/pass/backend-call counts.  The freeze now pins the
exact three reviewed source hashes rather than falsely claiming those files are
unchanged from Phase 0.  R1's local source/API freeze is green; final selection
and the complete R11/R10 duration matrix remain separate gates.
