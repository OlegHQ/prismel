# MTLRenderCommandEncoder owner closure

The pinned inventory contains exactly 133 unreviewed declarations owned by
`MTLRenderCommandEncoder`: 131 methods and two properties. The frozen signature
digest is `1acf1024ee348e211bff0dbfb0a98583fde97456fcbb2c60023ef06c2212529c`.

This batch is command semantics, not mechanical scalar glue. The safe model
therefore makes encoder state, same-device checks, binding indices, byte ranges,
pipeline-before-draw ordering, command ordering, and resource retention
explicit. Generation may emit exact identity/type evidence and typed direct
Objective-C++ calls, but it must not infer ownership or validation.

All 133 declarations remain unreviewed until complete command-group integration
and native conformance. Promotion must cover deterministic offscreen pixels,
invalid state/range/device rejection before Objective-C, zero handle delta on
rejection, retained resources through completion, and encoder invalidation after
`endEncoding`.
