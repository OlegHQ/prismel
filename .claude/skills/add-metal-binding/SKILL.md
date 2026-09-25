---
name: add-metal-binding
description: Add a Metal binding needed by an OGPU Metal backend feature, from the registry or a handwritten trampoline. Use for new Metal safe/raw/bridge API work in prismel.
---

# Add a Metal binding

1. Identify the `ogpu_metal` call site and its `Ogpu_core.Caps.feature`. Check
   `lib/metal/gen/registry.ml`, `metal_raw.mli`, and the safe
   `Metal` API for an existing binding. Do not add a binding without a consumer.
2. Put plain enums and selectors supported by the typed generator in the
   registry, alphabetical by OCaml name. Add record generation there when a
   consumed fixed struct needs it. Record `since` for APIs newer
   than the deployment target. Keep handles, descriptors, blocks, callbacks,
   and ownership in `metal_bridge.mm` plus `metal_raw.ml/.mli`. The old
   whole-SDK inventory and tooling have been removed.
3. Add a safe `metal.ml/.mli` wrapper with validation and typed errors. Do not
   expose raw pointers. Use it from `ogpu_metal` in the same change. Update the
   feature map when a feature's Metal symbols change.
4. Add one success and one rejection check in `lib/metal/test_metal.ml`, plus
   OGPU conformance for the capability when applicable. Build
   `@lib/metal/runtest` and `@lib/ogpu_metal/runtest`, then `@all` and run
   `git diff --check`. For SDK-dependent tests, use the existing
   `@qualification` lane. Treat a Clang type or availability error as a bad
   binding, never as a warning to suppress.
