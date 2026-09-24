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

The closure makes `Image.t` abstract again and moves migration identity,
generation, reload, pixel, and resource conversion operations under the
reviewed `Image.Private` boundary. The six Scene staging operations are
explicitly reviewed private-only additions. They do not count as high-level API
surface.

Current result: 40/40 modules, zero missing declarations, zero additional
unreviewed declarations, and zero changed high-level declarations.

Run:

```text
opam exec -- dune exec tools/phase5_api_signature_gate/phase5_api_signature_gate.exe -- --root .
```

Expected current result: exit 0 with 0 missing, 0 additional, and 0 changed.
