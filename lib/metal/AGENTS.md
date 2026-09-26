# lib/metal rules

Metal bindings exist only because `ogpu_metal` or `runtime` needs them.
Whole-SDK coverage is not a goal. Declare what you need; the generator writes
the binding. The end-to-end workflow is the `metal-workflow` skill.

## Binding path

- A new native call is a `Method` or `Property` entry in `gen/registry.ml`
  (enums and fixed scalar structs: `Enum`, `Record`). Each entry names its
  receiver `Handle_kind`, Objective-C type, selector/property, argument and
  result types, availability (`since`) and the OGPU `Caps.feature` it serves.
  The generator emits `Metal_raw.Registry.<ocaml>` and a typed Objective-C
  stub; nothing generated is checked in (outputs live in `_build`).
- Handwritten bridge code (`metal_bridge.mm` + `metal_raw.ml`) is only for
  what the registry cannot express: blocks and callbacks, descriptor
  graphs, handle arrays, ownership transfer, native structs. When you touch a
  handwritten stub that the registry can express, move it to the registry.
- The installed SDK is the oracle: generated stubs compile with `-Werror`, so
  an unknown selector, wrong type or unguarded availability fails the build.
  Never use `objc_msgSend`, stringly typed selectors or an unsafe catch-all.
- The generator fails on duplicate names/selectors and on any registry call
  `metal.ml` does not use. Delete a binding when its last consumer goes:
  `dune exec tools/codemod/codemod.exe -- prune lib/metal` removes it, its
  registry entry and its stub (`prune-dead-code` skill).
- The safe `Metal` layer validates (`on_main`, `ensure_live`, same-device,
  ranges), returns typed errors and exposes no raw pointers. Every new safe
  function lands with its first `ogpu_metal` call site and one success and
  one rejection check in a `lib/metal/test_metal_*_safe.ml` suite.
- The M1 AGX driver crashes in a Metal 4 static-linking fixture, so that
  fixture stays under `@qualification`.
