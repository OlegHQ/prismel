# lib/metal rules

Metal bindings exist only because `ogpu_metal` or `runtime` needs them.
Whole-SDK coverage is not a goal (plan decision 1).

## Binding path (plan M1–M3)

- Generated bindings come solely from `gen/registry.ml` (Enum, Record,
  Selector). Every entry names the OGPU `Caps.feature` it serves. Nothing else
  is generated.
- Outputs live in `_build` only. Never check in generated code, SDK dumps,
  inventories, or coverage ledgers.
- The installed SDK is the oracle: typed direct Objective-C calls compiled
  with `-Werror`, so unknown selectors, wrong types, and unguarded availability
  fail the build. Never use `objc_msgSend`, stringly typed selectors, or a
  public unsafe catch-all.
- The generator fails on duplicate OCaml/C names and on any registry entry not
  referenced from `metal.ml`. M2's raw-external trim remains in progress.
- Every new safe Metal function lands with its first `ogpu_metal` call site
  and one success and one rejection test in `test_metal.ml`.
- Encoders with resources, descriptors, blocks, callbacks, and ownership
  transfer stay handwritten in `metal_bridge.mm` + `metal_raw.ml`. Do not grow
  the generator for them.
- The safe `Metal` layer validates, returns typed errors, and exposes no raw
  pointers. Delete bindings when their last consumer goes away.

## While M1–M3 are in progress

The whole-SDK tooling and inventory are gone. Add a binding through the
registry when its supported types cover the call; otherwise keep ownership and
callback code in the handwritten bridge. Follow the `add-metal-binding` skill
in `.claude/skills/`. The M1 AGX driver crashes in a Metal 4 static-linking
fixture, so that fixture remains under `@qualification`.
