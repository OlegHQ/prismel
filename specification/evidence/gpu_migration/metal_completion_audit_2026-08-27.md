# Metal completion audit — 2026-08-27

This is an independent closure audit, not a declaration that the broader GPU
migration is complete.

## Inventory closure

- Pinned SDK declarations: 5,286.
- Bound: 5,248.
- Scope-excluded: 37.
- Availability-gated: 1.
- Unreviewed: 0.
- `MTLDevice` owner declarations: 182/182 bound.
- Bound declarations with an empty evidence reason: 0.

The counts were read from `lib/metal/generated_api_inventory.json` and checked
with `tools/metal/generate_inventory.exe --root . --check`.

## Final Device surface

The final Device slices have matching public signatures, internal raw
externals, typed Objective-C++ direct selectors, safe ownership code, and real
fixtures:

- descriptor/value25 and capability13;
- synchronous constructor4 and constructor3;
- asynchronous completion-handler9;
- sparse/timestamp6;
- observer metadata4;
- library5, queue3, legacy IO2, and the earlier residual11.

The focused constructor3 and async9 fixtures execute real library, compute,
render, mesh, tile, argument-encoder, and shared-event paths. Unsupported
hardware paths reject before allocating native handles where applicable.

## Availability-gated declaration

The sole gated declaration is
`-[MTL4Compiler newComputePipelineStateWithDescriptor:dynamicLinkingDescriptor:compilerTaskOptions:completionHandler:]`.

- The native bridge is guarded by `@available(macOS 26.0, *)`.
- The safe API detects dynamic-linking inputs and requires `MTLGPUFamilyApple9`
  before calling the raw primitive.
- Apple7/M1 rejection is `Unsupported` and the regression verifies no increase
  in the native-handle creation counter.
- Apple9+ executes the typed selector and validates completion identity,
  exactly-once task materialization, and the resulting compute pipeline.

No stringly selector dispatch or public raw escape hatch was found.

## Audit outcome

No new ownership, ABI, or availability defect was found in this pass. The
inventory check, final Device constructor/async/capability fixtures, and the
full `lib/metal/test_metal.exe` conformance executable passed after concurrent
Dune validation released the build lock.

The later full-suite rerun at `2026-08-27T14:27:52Z` repaired and revalidated
four audit drifts in `71386f5`: immutable pipeline-buffer descriptor mutation
is rejected without state change, GPU-trace capture uses an atomic descriptor
with a valid output path, command-buffer options retain `Log_state` through the
dependent-count lifetime, and the native fence fixture keeps application-owned
unretained command metadata alive through encoder finalization. Focused tests,
`dune runtest lib/metal --force`, the exact inventory check, and
`dune build @tools/metal/runtest --force` all passed afterward.

The resulting inventory/provenance hashes are
`78c0ec7d09e936c95365c3da2a95a98c193aa36b4b502b0f6c593efe08c9300a`
and `f7f80e87fb200240c5195b733a5c7052a0b6617291ed8cd962ded8948e51e9e2`.
This is local Apple M1 evidence only and does not replace outstanding M3+,
full-Xcode/offline, sanitizer, Guard Malloc, or Leaks qualification.
