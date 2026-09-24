# Metal global declaration audit

Source: the pinned schema-2 Metal inventory generated from the active Xcode SDK.
This audit does not change `NEW_GPU_STUFF.md` and does not itself change an
inventory classification.

## Functions (14 unreviewed)

- Eight pure fixed-layout constructors belong to the value-record generator:
  `MTL4BufferRangeMake`, `MTLCoordinate2DMake`,
  `MTLIndirectCommandBufferExecutionRangeMake`, `MTLPackedFloat3Make`,
  `MTLPackedFloatQuaternionMake`, `MTLRegionMake1D`, `MTLRegionMake2D`, and
  `MTLSamplePositionMake`.
- `MTLIOCompressionContextDefaultChunkSize` is a pure scalar query and can use
  a scalar global-function template.
- `MTLIOCompressionContextAppendData`, `MTLIOCreateCompressionContext`, and
  `MTLIOFlushAndDestroyCompressionContext` form one stateful ownership API.
  They must remain handwritten until the compression-context lifetime,
  nullable construction, buffer borrowing, and exactly-once destruction are
  modeled and tested together.
- `MTLCopyAllDevicesWithObserver` and `MTLRemoveDeviceObserver` require a
  retained observer token and callback/block lifetime. They are not mechanical
  global functions.

## Variables (44 unreviewed)

- Thirty-three are nonnull immutable NSString-typed SDK globals: eleven error
  domains, one error user-info key, eighteen common counter/counter-set names,
  and three device notifications. `binding_global_string_spec.ml` covers this
  complete family. The native generator checks each declared typedef with a
  C++ `static_assert`, uses its exact availability guard, rejects nil, and
  copies UTF-8 bytes into an OCaml string before returning. No Objective-C
  object or borrowed pointer crosses the FFI boundary.
- `MTLAttributeStrideStatic` is the sole scalar global and belongs in a scalar
  constant template with an SDK equality assertion.
- Ten entries (`elements`, `icbRange`, `origin`, `packedFloat3`,
  `packedQuaternion`, `position`, `range`, `region`, `result`, and `size`) are
  local variables from inline constructor bodies, not exported SDK globals.
  They should become `scope-excluded`; generating symbols for them would be a
  false binding.

## Accounting

This shard has 33 declarations with generated raw/native/safe source potential.
They remain `unreviewed` until generated artifacts are integrated, inventory
signatures are checked at generation time, the native SDK assertions compile,
and safe exact-value/availability/no-handle-delta tests pass. The audit exposes
no legitimate route to count the ten local variables as progress.
