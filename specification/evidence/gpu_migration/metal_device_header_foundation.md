# MTLDevice exact-94 qualification

The initial `Metal/MTLDevice.h` qualification covered 103 IDs (digest
`9f666df70c672fc3c6ff3ed267bc09e575e1f9e4673aed76058e6aac5d044961`),
but it is not a countable disjoint batch: two IDs belong to resource100 and
seven belong to acceleration115. Those nine IDs are now explicit exclusions.
The unique Device net is 94 IDs with digest
`81285a3cf295bf0394f127daafbb8e75972f0cfe70c55e42a5937afc5a2eec71`.
The adjacent 25 `MTLDataType.h` IDs belong to the committed shader157 batch and
are explicitly not part of this qualification. Presentation, mesh/tile, and
classic render have zero overlap. This sub-100 foundation must not be reported
as a production-scale batch by itself.

- 31 IDs are mechanical scalar/value operations: 21 unique direct typed calls
  and 10 property companions. The generated Objective-C++ shard compiles
  against the pinned SDK. Deprecated barycentric/feature-set calls remain
  compatibility aliases and emit the expected SDK warnings.
- 49 IDs require handwritten ownership: constructors, nullable NSError
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
