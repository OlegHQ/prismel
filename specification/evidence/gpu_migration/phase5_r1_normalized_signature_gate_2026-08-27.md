# Phase 5 R1 normalized signature gate — 2026-08-27

The standalone `tools/phase5_api_signature_gate` parses all 40 frozen Prismel
interfaces and their `prismel_next_api` counterparts with OCaml's parser,
removes documentation comments, recursively indexes values, types, modules,
module types, exceptions, extensions, and classes, and compares normalized
pretty-printed declarations. Missing, additional, and changed declarations are
independent failures.

The only built-in exceptions are the reviewed raw typed adaptations: Low's two
typed replacements and nine omissions, and Image/Font's opaque renderer and
texture hooks. No high-level declaration is allowlisted.

At commit-time the gate is intentionally red with these exact remaining deltas:

- changed: `Image.type:t`
- additional: `Image.val:generation`, `Image.val:identity`, `Image.val:pixels`,
  `Image.val:reload`
- additional private Scene staging hooks: `install_renderer`, `release`,
  `resources`, `stage`, `text_regions`, and `to_ir`
- missing: none

This supersedes fixture-existence as R1 interface evidence. It does not promote
R1: the public Image representation and additions remain unreviewed, and the
Scene private additions are outside the current raw-adaptation allowlist.

Run:

```text
opam exec -- dune exec tools/phase5_api_signature_gate/phase5_api_signature_gate.exe -- --root .
```

Expected current result: exit 1 with 0 missing, 10 additional, and 1 changed.
