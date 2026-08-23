open Binding_descriptor_property_spec

let a = [ "AvailabilityAttr" ]
let p ?(attributes = []) ?(default = 0L) owner name header signature introduced =
  entry ~attributes ~default_int64:default ~owner ~name ~header ~signature
    ~introduced ()

let entries =
  [ p "MTL4PipelineOptions" "shaderValidation" "Metal/MTL4PipelineState.h" "MTLShaderValidation" "26.0"
  ; p "MTL4RenderPassDescriptor" "imageblockSampleLength" "Metal/MTL4RenderPass.h" "NSUInteger" "26.0"
  ; p "MTL4RenderPassDescriptor" "renderTargetArrayLength" "Metal/MTL4RenderPass.h" "NSUInteger" "26.0"
  ; p "MTL4RenderPassDescriptor" "threadgroupMemoryLength" "Metal/MTL4RenderPass.h" "NSUInteger" "26.0"
  ; p "MTL4RenderPassDescriptor" "tileHeight" "Metal/MTL4RenderPass.h" "NSUInteger" "26.0"
  ; p "MTL4RenderPassDescriptor" "tileWidth" "Metal/MTL4RenderPass.h" "NSUInteger" "26.0"
  ; p ~attributes:a "MTLCompileOptions" "allowReferencingUndefinedSymbols" "Metal/MTLLibrary.h" "BOOL" "13.3"
  ; p ~attributes:a "MTLCompileOptions" "compileSymbolVisibility" "Metal/MTLLibrary.h" "MTLCompileSymbolVisibility" "13.3"
  ; p ~attributes:a "MTLCompileOptions" "enableLogging" "Metal/MTLLibrary.h" "BOOL" "15.0"
  ; p ~attributes:a ~default:262144L "MTLCompileOptions" "languageVersion" "Metal/MTLLibrary.h" "MTLLanguageVersion" "10.11"
  ; p ~attributes:a "MTLCompileOptions" "mathFloatingPointFunctions" "Metal/MTLLibrary.h" "MTLMathFloatingPointFunctions" "15.0"
  ; p ~attributes:a ~default:2L "MTLCompileOptions" "mathMode" "Metal/MTLLibrary.h" "MTLMathMode" "15.0"
  ; p ~attributes:a "MTLCompileOptions" "maxTotalThreadsPerThreadgroup" "Metal/MTLLibrary.h" "NSUInteger" "13.3"
  ; p ~attributes:a "MTLCompileOptions" "optimizationLevel" "Metal/MTLLibrary.h" "MTLLibraryOptimizationLevel" "13.0"
  ; p ~attributes:a "MTLCompileOptions" "preserveInvariance" "Metal/MTLLibrary.h" "BOOL" "11.0"
  ; p ~attributes:a ~default:1L "MTLComputePipelineDescriptor" "maxCallStackDepth" "Metal/MTLComputePipeline.h" "NSUInteger" "11.0"
  ; p ~attributes:a "MTLComputePipelineDescriptor" "maxTotalThreadsPerThreadgroup" "Metal/MTLComputePipeline.h" "NSUInteger" "10.14"
  ; p ~attributes:a "MTLComputePipelineDescriptor" "shaderValidation" "Metal/MTLComputePipeline.h" "MTLShaderValidation" "15.0"
  ; p ~attributes:a "MTLComputePipelineDescriptor" "supportAddingBinaryFunctions" "Metal/MTLComputePipeline.h" "BOOL" "11.0"
  ; p ~attributes:a "MTLComputePipelineDescriptor" "supportIndirectCommandBuffers" "Metal/MTLComputePipeline.h" "BOOL" "11.0"
  ; p ~attributes:a "MTLCounterSampleBufferDescriptor" "sampleCount" "Metal/MTLCounters.h" "NSUInteger" "10.15"
  ; p ~attributes:a "MTLCounterSampleBufferDescriptor" "storageMode" "Metal/MTLCounters.h" "MTLStorageMode" "10.15"
  ; p "MTLComputePipelineDescriptor" "threadGroupSizeIsMultipleOfThreadExecutionWidth" "Metal/MTLComputePipeline.h" "BOOL" "10.11"
  ; p ~attributes:a ~default:32L "MTLHeapDescriptor" "resourceOptions" "Metal/MTLHeap.h" "MTLResourceOptions" "10.15"
  ; p "MTLRenderPassAttachmentDescriptor" "depthPlane" "Metal/MTLRenderPass.h" "NSUInteger" "10.11"
  ; p "MTLRenderPassAttachmentDescriptor" "level" "Metal/MTLRenderPass.h" "NSUInteger" "10.11"
  ; p "MTLRenderPassAttachmentDescriptor" "resolveDepthPlane" "Metal/MTLRenderPass.h" "NSUInteger" "10.11"
  ; p "MTLRenderPassAttachmentDescriptor" "resolveLevel" "Metal/MTLRenderPass.h" "NSUInteger" "10.11"
  ; p "MTLRenderPassAttachmentDescriptor" "resolveSlice" "Metal/MTLRenderPass.h" "NSUInteger" "10.11"
  ; p "MTLRenderPassAttachmentDescriptor" "slice" "Metal/MTLRenderPass.h" "NSUInteger" "10.11"
  ; p ~attributes:a "MTLRenderPassAttachmentDescriptor" "storeActionOptions" "Metal/MTLRenderPass.h" "MTLStoreActionOptions" "10.13"
  ; p ~attributes:a "MTLRenderPassDepthAttachmentDescriptor" "depthResolveFilter" "Metal/MTLRenderPass.h" "MTLMultisampleDepthResolveFilter" "10.14"
  ; p ~attributes:a "MTLRenderPassStencilAttachmentDescriptor" "stencilResolveFilter" "Metal/MTLRenderPass.h" "MTLMultisampleStencilResolveFilter" "10.14"
  ; p ~default:16L "MTLTextureDescriptor" "resourceOptions" "Metal/MTLTexture.h" "MTLResourceOptions" "10.11"
  ; p "MTLIndirectCommandBufferDescriptor" "commandTypes" "Metal/MTLIndirectCommandBuffer.h" "MTLIndirectCommandType" "10.14"
  ; p "MTLIndirectCommandBufferDescriptor" "inheritBuffers" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "10.14"
  ; p "MTLIOCommandQueueDescriptor" "priority" "Metal/MTLIOCommandQueue.h" "MTLIOPriority" "13.0"
  ; p ~attributes:a ~default:1L "MTLIndirectCommandBufferDescriptor" "inheritCullMode" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "26.0"
  ; p ~attributes:a ~default:1L "MTLIndirectCommandBufferDescriptor" "inheritDepthBias" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "26.0"
  ; p ~attributes:a ~default:1L "MTLIndirectCommandBufferDescriptor" "inheritDepthClipMode" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "26.0"
  ; p ~attributes:a ~default:1L "MTLIndirectCommandBufferDescriptor" "inheritDepthStencilState" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "26.0"
  ; p ~attributes:a ~default:1L "MTLIndirectCommandBufferDescriptor" "inheritFrontFacingWinding" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "26.0"
  ; p ~attributes:a "MTLIndirectCommandBufferDescriptor" "inheritPipelineState" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "10.14"
  ; p ~attributes:a ~default:1L "MTLIndirectCommandBufferDescriptor" "inheritTriangleFillMode" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "26.0"
  ; p "MTLIndirectCommandBufferDescriptor" "maxFragmentBufferBindCount" "Metal/MTLIndirectCommandBuffer.h" "NSUInteger" "10.14"
  ; p ~attributes:a "MTLIndirectCommandBufferDescriptor" "maxKernelBufferBindCount" "Metal/MTLIndirectCommandBuffer.h" "NSUInteger" "11.0"
  ; p ~attributes:a ~default:31L "MTLIndirectCommandBufferDescriptor" "maxKernelThreadgroupMemoryBindCount" "Metal/MTLIndirectCommandBuffer.h" "NSUInteger" "14.0"
  ; p ~attributes:a "MTLIndirectCommandBufferDescriptor" "maxMeshBufferBindCount" "Metal/MTLIndirectCommandBuffer.h" "NSUInteger" "14.0"
  ; p ~attributes:a "MTLIndirectCommandBufferDescriptor" "maxObjectBufferBindCount" "Metal/MTLIndirectCommandBuffer.h" "NSUInteger" "14.0"
  ; p ~attributes:a "MTLIndirectCommandBufferDescriptor" "maxObjectThreadgroupMemoryBindCount" "Metal/MTLIndirectCommandBuffer.h" "NSUInteger" "14.0"
  ; p "MTLIndirectCommandBufferDescriptor" "maxVertexBufferBindCount" "Metal/MTLIndirectCommandBuffer.h" "NSUInteger" "10.14"
  ; p ~attributes:a "MTLIndirectCommandBufferDescriptor" "supportColorAttachmentMapping" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "26.0"
  ; p ~attributes:a "MTLIndirectCommandBufferDescriptor" "supportDynamicAttributeStride" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "14.0"
  ; p ~attributes:a "MTLIndirectCommandBufferDescriptor" "supportRayTracing" "Metal/MTLIndirectCommandBuffer.h" "BOOL" "13.0"
  ]

let expected_property_count = 54
let expected_inventory_id_count = 162
let expected_owner_count = 12
let source_paths =
  [ "tools/metal/binding_descriptor_property_spec.ml"
  ; "tools/metal/binding_descriptor_property_spec.mli"
  ; "tools/metal/binding_descriptor_property_plan.ml"
  ; "tools/metal/binding_descriptor_property_plan.mli"
  ]

let () = validate entries
