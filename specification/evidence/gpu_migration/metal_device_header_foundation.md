# MTLDevice.h exact-103 foundation

The pinned unreviewed `Metal/MTLDevice.h` closure contains exactly 103 IDs with
sorted-ID SHA-256
`9f666df70c672fc3c6ff3ed267bc09e575e1f9e4673aed76058e6aac5d044961`.
It is disjoint from the resource, presentation, mesh/tile, acceleration, and
classic render batches.

- 32 IDs are mechanical scalar/value operations: 22 unique direct typed calls
  and 10 property companions. The generated Objective-C++ shard compiles
  against the pinned SDK. Deprecated barycentric/feature-set calls remain
  compatibility aliases and emit the expected SDK warnings.
- 57 IDs require handwritten ownership: constructors, nullable NSError
  transfer, callbacks, observer lifetime, borrowed object graphs, descriptor
  validation, or caller-owned variable-size buffers.
- 14 IDs are metadata declarations (classes, protocols, typedefs, and enum
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
