# Tensor/raster layout exact-102 foundation

The complete current unreviewed closures of `Metal/MTLTensor.h` (47 IDs) and
`Metal/MTLRasterizationRate.h` (55 IDs) form an exact 102-ID resource-layout
family. Sorted-ID SHA-256 is
`64ffa1fb0bc770c38e2da86d3fb6f02b1c4b29d30306cdd220cbec7432eb97e6`.
Exact ID intersections with resource100, presentation125, mesh/tile105,
acceleration115, render-resource19, render-encoder106, shader157, and the
Device94 qualification are all zero.

- 48 mechanical IDs comprise 30 direct typed Objective-C calls and 18 property
  companions. The generated shard compiles against the pinned SDK.
- 46 ownership-sensitive IDs cover descriptor factories, layer arrays, copied
  labels, borrowed buffers/devices/extents, sample storage, tensor byte ranges,
  and nullable parent resources.
- 8 class/protocol declarations are metadata.

The safe graph blocks parent destruction while descriptors/arrays/maps/tensors
are retained, validates tensor rank/extents (1..16), finite positive raster
rates, and layer indices, and unwinds every retained child exactly once.
Generated calls remain unreviewed until safe materialization and real
execute-or-capability-reject conformance are integrated.
