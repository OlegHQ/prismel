# MTLDevice/type exact-119 foundation

The initial `Metal/MTLDevice.h` qualification covered 103 IDs (digest
`9f666df70c672fc3c6ff3ed267bc09e575e1f9e4673aed76058e6aac5d044961`),
but it is not a countable disjoint batch: two IDs belong to resource100 and
seven belong to acceleration115. Those nine IDs are now explicit exclusions.
The unique Device net is 94 IDs; adding the adjacent 25 unreviewed
`Metal/MTLDataType.h` enum declarations produces exactly 119 unique IDs with
digest `8d460a76b5f5e00d2bab8b55af7a148127272bee5099f97e9fd4f383573a0d6c`.
Presentation, mesh/tile, and classic render have zero overlap.

- 31 IDs are mechanical scalar/value operations: 21 unique direct typed calls
  and 10 property companions. The generated Objective-C++ shard compiles
  against the pinned SDK. Deprecated barycentric/feature-set calls remain
  compatibility aliases and emit the expected SDK warnings.
- 49 IDs require handwritten ownership: constructors, nullable NSError
  transfer, callbacks, observer lifetime, borrowed object graphs, descriptor
  validation, or caller-owned variable-size buffers.
- 39 IDs are metadata declarations (classes, protocols, typedefs, and enum
  cases). They remain inventory evidence rather than callable functions.

The safe graph requires a live parent device for every constructor, blocks
device destruction while a child or async completion exists, releases exactly
once on success/error unwind, and validates array cardinality and three-axis
sizes before native calls. Generated low-level calls remain unreviewed until
their public safe resource type and real execute-or-capability-reject lane land.

Focused gates:

```text
xcrun clang++ -std=c++17 -fobjc-arc -fsyntax-only \
  tools/metal/metal_device_header_mechanical_generated.mm
ocamlc binding_device_header_safe_graph.mli \
  binding_device_header_safe_graph.ml test_binding_device_header_safe_graph.ml
```
