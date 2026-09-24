# Pipeline113 safe state-query shard

The 13 callable inventory selectors map one-to-one to these safe operations:

- `MTLComputePipelineState.gpuResourceID` → `Compute_pipeline.resource_id`
- `requiredThreadsPerThreadgroup` → `required_threads_per_threadgroup`
- `shaderValidation` → `shader_validation`
- `supportIndirectCommandBuffers` → `supports_indirect_command_buffers`
- `imageblockMemoryLengthForDimensions:` → `imageblock_memory_length`
- `MTLRenderPipelineState.gpuResourceID` → `Render_pipeline.resource_id`
- `imageblockSampleLength` → `imageblock_sample_length`
- `maxTotalThreadsPerMeshThreadgroup` → `mesh_threads_per_threadgroup`
- `maxTotalThreadsPerObjectThreadgroup` → `object_threads_per_threadgroup`
- `maxTotalThreadsPerTileThreadgroup` → `tile_threads_per_threadgroup`
- `shaderValidation` → `shader_validation`
- `supportIndirectCommandBuffers` → `supports_indirect_command_buffers`
- `imageblockMemoryLengthForDimensions:` → `imageblock_memory_length`

All queries reject destroyed handles before FFI. Imageblock dimensions must be
strictly positive. Shader-validation codes are exhaustively mapped to
`Default`, `Enabled`, and `Disabled`; unknown future SDK codes return a typed
`Unsupported` error rather than escaping as an integer.
