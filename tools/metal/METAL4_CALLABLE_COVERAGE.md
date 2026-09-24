# Metal4 callable coverage after the compute/counter stage

This stage exposes **51 authoritative inventory IDs** through typed native and
raw OCaml calls:

- 27 `MTL4ComputeCommandEncoder` method IDs;
- 6 generic `MTL4CommandEncoder` method IDs;
- 3 `MTL4CommandQueue` residency method IDs; and
- 10 `MTL4CounterHeap{,Descriptor}` method IDs plus their 5 exact property
  companions.

The earlier 38/151 ownership audit already counted the generated 32-method
compute plan, although it was not callable. Consequently this stage adds 24
new IDs to that authoritative union: coverage becomes **62/151**, with
**89 ownership IDs remaining**. At the callable ABI boundary, the stage itself
is exactly 51 IDs; the buffer-to-buffer compute selector also had an earlier
special-purpose materializer, so the unique callable union grows by 50 IDs.

The five compute methods deliberately left non-callable are:

- `copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:`
- `buildAccelerationStructure:descriptor:scratchBuffer:`
- both `refitAccelerationStructure:descriptor:destination:scratchBuffer:` variants
- `writeCompactedAccelerationStructureSize:toBuffer:`

They require an exact `MTLTensorExtents` marshaller or owned
`MTL4AccelerationStructureDescriptor`/`MTL4BufferRange` schema. The remaining
27 calls validate command-graph identity, resource device identity, ranges,
dimensions and counter indices, and retain encoded objects through the command
buffer state.
