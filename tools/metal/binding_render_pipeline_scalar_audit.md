# Render-pipeline scalar descriptor batch

This isolated M4 batch covers 37 non-deprecated fixed scalar properties in the
pinned `MTLRenderPipeline.h` inventory for
`MTLRenderPipelineDescriptor`,
`MTLMeshRenderPipelineDescriptor`, `MTLTileRenderPipelineDescriptor`, and
`MTLRenderPipelineColorAttachmentDescriptor`, except the bitmask-valued
`writeMask` property. Explicit `is...` getter-selector metadata is preserved.
Enum families not yet present in the generated pure-value surface remain out of
this promotion rather than being represented by unsafe raw integers.

The batch contains 37 properties and exactly 111 inventory declarations: one
property, one typed direct getter, and one typed direct setter per property.
It deliberately excludes object/string/array ownership, `MTLSize` values,
read-only pipeline-state queries, and deprecated `sampleCount`.

The existing descriptor generator produces private immutable OCaml records,
checked nonnegative `NSUInteger` conversion, direct Objective-C++ assignments,
SDK-type `static_assert` checks, exact setter/getter round trips, availability
guards, and native conformance executables. Promotion to `bound` is permitted
only after those artifacts are integrated and their native conformance passes;
the plan alone leaves all 111 declarations `unreviewed`.

`lib/metal/test_metal_render_pipeline_scalar_native.mm` is the integration-ready
native gate. It compile-time checks the planned SDK property types plus adjacent
enum properties, verifies every planned descriptor default and direct
setter/getter round trip, compiles a real
vertex/fragment pipeline on the active device, requires a deliberately invalid
sample count to fail with a full diagnostic, and verifies that a successful
pipeline is released after its autorelease scope. It passed on Apple M1 with
the pinned SDK. No OCaml handle is allocated by the rejected native operation;
the eventual safe integration must additionally bracket its public rejection
case with `Metal.Debug.stats` before promoting the declarations.
