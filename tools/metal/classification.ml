type t =
  | Bound
  | Availability_gated
  | Scope_excluded
  | Unreviewed

module String_set = Set.Make (String)

let methods owners =
  List.concat_map
    (fun (owner, selectors) ->
      List.map (fun selector -> "method:-[" ^ owner ^ " " ^ selector ^ "]")
        selectors)
    owners

let properties owners =
  List.concat_map
    (fun (owner, names) ->
      List.map (fun property -> "property:" ^ owner ^ ":" ^ property) names)
    owners

let enum_cases owner names =
  List.map (fun name -> "enum-case:" ^ owner ^ ":" ^ name) names

let bound_identifiers =
  [ "method:-[MTLDrawable addPresentedHandler:]"
  ; "method:-[MTLDrawable drawableID]"
  ; "method:-[MTLDrawable presentAfterMinimumDuration:]"
  ; "method:-[MTLDrawable presentAtTime:]"
  ; "method:-[MTLDrawable present]"
  ; "method:-[MTLDrawable presentedTime]"
  ; "property:MTLDrawable:drawableID"
  ; "property:MTLDrawable:presentedTime"
  ; "method:+[MTLSharedEventListener sharedListener]"
  ; "method:-[MTLSharedEventListener init]"
  ; "method:-[MTLSharedEventListener initWithDispatchQueue:]"
  ; "method:-[MTLSharedEventListener dispatchQueue]"
  ; "property:MTLSharedEventListener:dispatchQueue"
  ; "method:-[MTLSharedEvent newSharedEventHandle]"
  ; "method:-[MTLSharedEventHandle label]"
  ; "property:MTLSharedEventHandle:label"
  ; "property:MTLEvent:device"
  ; "method:-[MTLSharedEvent notifyListener:atValue:block:]"
  ; "class:MTLFunctionDescriptor"
  ; "class:MTLIndirectCommandBufferDescriptor"
  ; "method:+[MTLFunctionDescriptor functionDescriptor]"
  ; "method:-[MTLFunctionDescriptor constantValues]"
  ; "method:-[MTLFunctionDescriptor name]"
  ; "method:-[MTLFunctionDescriptor options]"
  ; "method:-[MTLFunctionDescriptor setConstantValues:]"
  ; "method:-[MTLFunctionDescriptor setName:]"
  ; "method:-[MTLFunctionDescriptor setOptions:]"
  ; "method:-[MTLFunctionDescriptor setSpecializedName:]"
  ; "method:-[MTLFunctionDescriptor specializedName]"
  ; "property:MTLFunctionDescriptor:constantValues"
  ; "property:MTLFunctionDescriptor:name"
  ; "property:MTLFunctionDescriptor:options"
  ; "property:MTLFunctionDescriptor:specializedName"
  ; "class:MTL4ArgumentTableDescriptor"
  ; "class:MTL4AccelerationStructureBoundingBoxGeometryDescriptor"
  ; "class:MTL4AccelerationStructureCurveGeometryDescriptor"
  ; "class:MTL4AccelerationStructureDescriptor"
  ; "class:MTL4AccelerationStructureGeometryDescriptor"
  ; "class:MTL4AccelerationStructureMotionBoundingBoxGeometryDescriptor"
  ; "class:MTL4AccelerationStructureMotionCurveGeometryDescriptor"
  ; "class:MTL4AccelerationStructureMotionTriangleGeometryDescriptor"
  ; "class:MTL4AccelerationStructureTriangleGeometryDescriptor"
  ; "class:MTL4IndirectInstanceAccelerationStructureDescriptor"
  ; "class:MTL4InstanceAccelerationStructureDescriptor"
  ; "class:MTL4PrimitiveAccelerationStructureDescriptor"
  ; "class:MTL4BinaryFunctionDescriptor"
  ; "class:MTL4CommandAllocatorDescriptor"
  ; "class:MTL4CommandBufferOptions"
  ; "class:MTL4CommandQueueDescriptor"
  ; "class:MTL4CommitOptions"
  ; "class:MTL4CompilerDescriptor"
  ; "class:MTL4CompilerTaskOptions"
  ; "class:MTL4ComputePipelineDescriptor"
  ; "class:MTL4FunctionDescriptor"
  ; "class:MTL4LibraryDescriptor"
  ; "class:MTL4LibraryFunctionDescriptor"
  ; "class:MTL4MeshRenderPipelineDescriptor"
  ; "class:MTL4PipelineDataSetSerializerDescriptor"
  ; "class:MTL4PipelineDescriptor"
  ; "class:MTL4PipelineOptions"
  ; "class:MTL4PipelineStageDynamicLinkingDescriptor"
  ; "class:MTL4RenderPipelineColorAttachmentDescriptor"
  ; "class:MTL4RenderPipelineColorAttachmentDescriptorArray"
  ; "class:MTL4RenderPipelineDescriptor"
  ; "class:MTL4RenderPipelineDynamicLinkingDescriptor"
  ; "class:MTL4RenderPassDescriptor"
  ; "class:MTL4StaticLinkingDescriptor"
  ; "class:MTL4TileRenderPipelineDescriptor"
  ; "class:MTLBinaryArchiveDescriptor"
  ; "class:MTLCompileOptions"
  ; "class:MTLComputePipelineDescriptor"
  ; "class:MTLComputePipelineReflection"
  ; "class:MTLDepthStencilDescriptor"
  ; "class:MTLFunctionConstant"
  ; "class:MTLFunctionConstantValues"
  ; "class:MTLHeapDescriptor"
  ; "class:MTLLinkedFunctions"
  ; "class:MTLLogicalToPhysicalColorAttachmentMap"
  ; "class:MTLResidencySetDescriptor"
  ; "class:MTLRenderPipelineReflection"
  ; "class:MTLRenderPassAttachmentDescriptor"
  ; "class:MTLRenderPassColorAttachmentDescriptor"
  ; "class:MTLRenderPassColorAttachmentDescriptorArray"
  ; "class:MTLRenderPassDepthAttachmentDescriptor"
  ; "class:MTLRenderPassStencilAttachmentDescriptor"
  ; "class:MTLSamplerDescriptor"
  ; "class:MTLSharedTextureHandle"
  ; "class:MTLStencilDescriptor"
  ; "class:MTLTextureDescriptor"
  ; "class:MTLTextureViewDescriptor"
  ; "class:MTLTileRenderPipelineColorAttachmentDescriptor"
  ; "class:MTLTileRenderPipelineColorAttachmentDescriptorArray"
  ; "class:MTLVertexAttributeDescriptor"
  ; "class:MTLVertexAttributeDescriptorArray"
  ; "class:MTLVertexBufferLayoutDescriptor"
  ; "class:MTLVertexBufferLayoutDescriptorArray"
  ; "class:MTLVertexDescriptor"
  ; "enum:MTL4AlphaToCoverageState"
  ; "enum:MTL4AlphaToOneState"
  ; "enum:MTL4BinaryFunctionOptions"
  ; "enum:MTL4BlendState"
  ; "enum:MTL4CompilerTaskStatus"
  ; "enum:MTLCommandBufferStatus"
  ; "enum:MTLIndexType"
  ; "enum:MTLLoadAction"
  ; "enum:MTLPrimitiveType"
  ; "enum:MTLRenderStages"
  ; "enum:MTLStoreAction"
  ; "enum:MTL4VisibilityOptions"
  ; "enum:MTL4IndirectCommandBufferSupportState"
  ; "enum:MTL4LogicalToPhysicalColorAttachmentMappingState"
  ; "enum:MTL4PipelineDataSetSerializerConfiguration"
  ; "enum:MTL4ShaderReflection"
  ; "enum:MTLBindingAccess"
  ; "enum:MTLBindingType"
  ; "enum:MTLBlendFactor"
  ; "enum:MTLBlendOperation"
  ; "enum:MTLDataType"
  ; "enum:MTLCompareFunction"
  ; "enum:MTLColorWriteMask"
  ; "enum:MTLBufferSparseTier"
  ; "enum:MTLCPUCacheMode"
  ; "enum:MTLCullMode"
  ; "enum:MTLDepthClipMode"
  ; "enum:MTLGPUFamily"
  ; "enum:MTLHazardTrackingMode"
  ; "enum:MTLHeapType"
  ; "enum:MTLFunctionType"
  ; "enum:MTLLibraryType"
  ; "enum:MTLPixelFormat"
  ; "enum:MTLPipelineOption"
  ; "enum:MTLPrimitiveTopologyClass"
  ; "enum:MTLPurgeableState"
  ; "enum:MTLResourceOptions"
  ; "enum:MTLSamplerAddressMode"
  ; "enum:MTLSamplerBorderColor"
  ; "enum:MTLSamplerMinMagFilter"
  ; "enum:MTLSamplerMipFilter"
  ; "enum:MTLSamplerReductionMode"
  ; "enum:MTLSparsePageSize"
  ; "enum:MTLSparseTextureMappingMode"
  ; "enum:MTLStorageMode"
  ; "enum:MTLStages"
  ; "enum:MTLStencilOperation"
  ; "enum:MTLTextureType"
  ; "enum:MTLTextureCompressionType"
  ; "enum:MTLTextureSparseTier"
  ; "enum:MTLTextureSwizzle"
  ; "enum:MTLTextureUsage"
  ; "enum:MTLTriangleFillMode"
  ; "enum:MTLVertexFormat"
  ; "enum:MTLVertexStepFunction"
  ; "enum:MTLVisibilityResultMode"
  ; "enum:MTLVisibilityResultType"
  ; "enum:MTLWinding"
  ; "function:MTLCopyAllDevices"
  ; "function:MTLClearColorMake"
  ; "function:MTLCreateSystemDefaultDevice"
  ; "function:MTLOriginMake"
  ; "function:MTLRegionMake3D"
  ; "function:MTLSizeMake"
  ; "function:MTLTextureSwizzleChannelsMake"
  ; "method:+[MTLLinkedFunctions linkedFunctions]"
  ; "method:+[MTLVertexDescriptor vertexDescriptor]"
  ; "record:MTLOrigin"
  ; "record:MTLClearColor"
  ; "record:MTL4UpdateSparseBufferMappingOperation"
  ; "record:MTL4UpdateSparseTextureMappingOperation"
  ; "record:MTLDrawIndexedPrimitivesIndirectArguments"
  ; "record:MTLDrawPrimitivesIndirectArguments"
  ; "record:MTLRegion"
  ; "record:MTLResourceID"
  ; "record:MTLScissorRect"
  ; "record:MTLSize"
  ; "record:MTLSizeAndAlign"
  ; "record:MTLTextureSwizzleChannels"
  ; "record:MTLVertexAmplificationViewMapping"
  ; "record:MTLViewport"
  ; "field:MTLClearColor:alpha"
  ; "field:MTLClearColor:blue"
  ; "field:MTLClearColor:green"
  ; "field:MTLClearColor:red"
  ; "field:MTLOrigin:x"
  ; "field:MTLOrigin:y"
  ; "field:MTLOrigin:z"
  ; "field:MTLRegion:origin"
  ; "field:MTLRegion:size"
  ; "field:MTLResourceID:_impl"
  ; "field:MTLScissorRect:height"
  ; "field:MTLScissorRect:width"
  ; "field:MTLScissorRect:x"
  ; "field:MTLScissorRect:y"
  ; "field:MTLSize:width"
  ; "field:MTLSize:height"
  ; "field:MTLSize:depth"
  ; "field:MTLSizeAndAlign:align"
  ; "field:MTLSizeAndAlign:size"
  ; "field:MTLTextureSwizzleChannels:alpha"
  ; "field:MTLTextureSwizzleChannels:blue"
  ; "field:MTLTextureSwizzleChannels:green"
  ; "field:MTLTextureSwizzleChannels:red"
  ; "field:MTLVertexAmplificationViewMapping:renderTargetArrayIndexOffset"
  ; "field:MTLVertexAmplificationViewMapping:viewportArrayIndexOffset"
  ; "field:MTLViewport:height"
  ; "field:MTLViewport:originX"
  ; "field:MTLViewport:originY"
  ; "field:MTLViewport:width"
  ; "field:MTLViewport:zfar"
  ; "field:MTLViewport:znear"
  ; "field:MTL4UpdateSparseBufferMappingOperation:bufferRange"
  ; "field:MTL4UpdateSparseBufferMappingOperation:heapOffset"
  ; "field:MTL4UpdateSparseBufferMappingOperation:mode"
  ; "field:MTL4UpdateSparseTextureMappingOperation:heapOffset"
  ; "field:MTL4UpdateSparseTextureMappingOperation:mode"
  ; "field:MTL4UpdateSparseTextureMappingOperation:textureLevel"
  ; "field:MTL4UpdateSparseTextureMappingOperation:textureRegion"
  ; "field:MTL4UpdateSparseTextureMappingOperation:textureSlice"
  ; "field:MTLDrawIndexedPrimitivesIndirectArguments:baseInstance"
  ; "field:MTLDrawIndexedPrimitivesIndirectArguments:baseVertex"
  ; "field:MTLDrawIndexedPrimitivesIndirectArguments:indexCount"
  ; "field:MTLDrawIndexedPrimitivesIndirectArguments:indexStart"
  ; "field:MTLDrawIndexedPrimitivesIndirectArguments:instanceCount"
  ; "field:MTLDrawPrimitivesIndirectArguments:baseInstance"
  ; "field:MTLDrawPrimitivesIndirectArguments:instanceCount"
  ; "field:MTLDrawPrimitivesIndirectArguments:vertexCount"
  ; "field:MTLDrawPrimitivesIndirectArguments:vertexStart"
  ; "protocol:MTL4ArgumentTable"
  ; "protocol:MTL4BinaryFunction"
  ; "protocol:MTL4CommandAllocator"
  ; "protocol:MTL4CommandBuffer"
  ; "protocol:MTL4CommandEncoder"
  ; "protocol:MTL4CommandQueue"
  ; "protocol:MTL4CommitFeedback"
  ; "protocol:MTL4ComputeCommandEncoder"
  ; "protocol:MTL4RenderCommandEncoder"
  ; "protocol:MTL4Archive"
  ; "protocol:MTL4Compiler"
  ; "protocol:MTL4CompilerTask"
  ; "protocol:MTL4PipelineDataSetSerializer"
  ; "protocol:MTLBinaryArchive"
  ; "protocol:MTLBuffer"
  ; "protocol:MTLAllocation"
  ; "protocol:MTLBlitCommandEncoder"
  ; "protocol:MTLBinding"
  ; "protocol:MTLBufferBinding"
  ; "protocol:MTLCommandBuffer"
  ; "protocol:MTLCommandEncoder"
  ; "protocol:MTLCommandQueue"
  ; "protocol:MTLComputeCommandEncoder"
  ; "protocol:MTLComputePipelineState"
  ; "protocol:MTLDepthStencilState"
  ; "protocol:MTLDevice"
  ; "protocol:MTLDynamicLibrary"
  ; "protocol:MTLEvent"
  ; "protocol:MTLFunction"
  ; "protocol:MTLHeap"
  ; "protocol:MTLLibrary"
  ; "protocol:MTLObjectPayloadBinding"
  ; "protocol:MTLResource"
  ; "protocol:MTLResidencySet"
  ; "protocol:MTLRenderPipelineState"
  ; "protocol:MTLResourceStateCommandEncoder"
  ; "protocol:MTLSamplerState"
  ; "protocol:MTLSharedEvent"
  ; "protocol:MTLTexture"
  ; "protocol:MTLTextureBinding"
  ; "protocol:MTLThreadgroupBinding"
  ; "typedef:MTL4AlphaToCoverageState"
  ; "typedef:MTL4AlphaToOneState"
  ; "typedef:MTL4BinaryFunctionOptions"
  ; "typedef:MTL4BlendState"
  ; "typedef:MTL4CompilerTaskStatus"
  ; "typedef:MTL4CommitFeedbackHandler"
  ; "typedef:MTL4NewBinaryFunctionCompletionHandler"
  ; "typedef:MTLCommandBufferStatus"
  ; "typedef:MTLClearColor"
  ; "typedef:MTLLoadAction"
  ; "typedef:MTLPrimitiveType"
  ; "typedef:MTLRenderStages"
  ; "typedef:MTLResourceID"
  ; "typedef:MTLStoreAction"
  ; "typedef:MTL4IndirectCommandBufferSupportState"
  ; "typedef:MTL4LogicalToPhysicalColorAttachmentMappingState"
  ; "typedef:MTL4PipelineDataSetSerializerConfiguration"
  ; "typedef:MTL4ShaderReflection"
  ; "typedef:MTL4UpdateSparseBufferMappingOperation"
  ; "typedef:MTL4UpdateSparseTextureMappingOperation"
  ; "typedef:MTL4VisibilityOptions"
  ; "typedef:MTLBindingAccess"
  ; "typedef:MTLBindingType"
  ; "typedef:MTLBlendFactor"
  ; "typedef:MTLBlendOperation"
  ; "typedef:MTLDataType"
  ; "typedef:MTLCompareFunction"
  ; "typedef:MTLColorWriteMask"
  ; "typedef:MTLBufferSparseTier"
  ; "typedef:MTLCPUCacheMode"
  ; "typedef:MTLCullMode"
  ; "typedef:MTLDepthClipMode"
  ; "typedef:MTLGPUFamily"
  ; "typedef:MTLHazardTrackingMode"
  ; "typedef:MTLHeapType"
  ; "typedef:MTLFunctionType"
  ; "typedef:MTLGPUAddress"
  ; "typedef:MTLLibraryType"
  ; "typedef:MTLOrigin"
  ; "typedef:MTLPixelFormat"
  ; "typedef:MTLPipelineOption"
  ; "typedef:MTLPrimitiveTopologyClass"
  ; "typedef:MTLPurgeableState"
  ; "typedef:MTLRegion"
  ; "typedef:MTLResourceOptions"
  ; "typedef:MTLScissorRect"
  ; "typedef:MTLSamplerAddressMode"
  ; "typedef:MTLSamplerBorderColor"
  ; "typedef:MTLSamplerMinMagFilter"
  ; "typedef:MTLSamplerMipFilter"
  ; "typedef:MTLSamplerReductionMode"
  ; "typedef:MTLSparsePageSize"
  ; "typedef:MTLSparseTextureMappingMode"
  ; "typedef:MTLSize"
  ; "typedef:MTLSizeAndAlign"
  ; "typedef:MTLStorageMode"
  ; "typedef:MTLStages"
  ; "typedef:MTLStencilOperation"
  ; "typedef:MTLTextureType"
  ; "typedef:MTLTextureCompressionType"
  ; "typedef:MTLTextureSparseTier"
  ; "typedef:MTLTextureSwizzle"
  ; "typedef:MTLTextureSwizzleChannels"
  ; "typedef:MTLTextureUsage"
  ; "typedef:MTLTriangleFillMode"
  ; "typedef:MTLVertexAmplificationViewMapping"
  ; "typedef:MTLVertexFormat"
  ; "typedef:MTLVertexStepFunction"
  ; "typedef:MTLVisibilityResultMode"
  ; "typedef:MTLVisibilityResultType"
  ; "typedef:MTLWinding"
  ; "typedef:MTLViewport"
  ; "typedef:MTLNewLibraryCompletionHandler"
  ; "typedef:MTLNewComputePipelineStateCompletionHandler"
  ; "typedef:MTLNewDynamicLibraryCompletionHandler"
  ; "typedef:MTLNewRenderPipelineStateCompletionHandler"
  ; "variable:MTLBufferLayoutStrideDynamic"
  ; "variable:swizzle"
  ]
  @ methods
      [ ( "MTL4Archive"
        , [ "label"; "newBinaryFunctionWithDescriptor:error:"
          ; "setLabel:"
          ] )
      ; ( "MTL4ArgumentTable"
        , [ "device"; "label"; "setAddress:atIndex:"
          ; "setAddress:attributeStride:atIndex:"
          ; "setSamplerState:atIndex:"; "setTexture:atIndex:"
          ] )
      ; ( "MTL4ArgumentTableDescriptor"
        , [ "initializeBindings"; "label"; "maxBufferBindCount"
          ; "maxSamplerStateBindCount"; "maxTextureBindCount"
          ; "setInitializeBindings:"; "setLabel:"
          ; "setMaxBufferBindCount:"; "setMaxSamplerStateBindCount:"
          ; "setMaxTextureBindCount:"; "setSupportAttributeStrides:"
          ; "supportAttributeStrides"
          ] )
      ; ( "MTL4BinaryFunctionDescriptor"
        , [ "functionDescriptor"; "name"; "options"
          ; "setFunctionDescriptor:"; "setName:"; "setOptions:"
          ] )
      ; ( "MTL4CommandAllocator"
        , [ "allocatedSize"; "device"; "label"; "reset" ] )
      ; ( "MTL4CommandAllocatorDescriptor", [ "label"; "setLabel:" ] )
      ; ( "MTL4CommandBuffer"
        , [ "beginCommandBufferWithAllocator:"; "beginCommandBufferWithAllocator:options:"; "computeCommandEncoder"
          ; "device"; "endCommandBuffer"; "label"
          ; "machineLearningCommandEncoder"; "renderCommandEncoderWithDescriptor:"
          ; "renderCommandEncoderWithDescriptor:options:"; "setLabel:"
          ] )
      ; ( "MTL4CommandBufferOptions", [ "logState"; "setLogState:" ] )
      ; ( "MTL4CommandEncoder"
        , [ "barrierAfterQueueStages:beforeStages:visibilityOptions:"
          ; "commandBuffer"; "endEncoding"; "label"; "setLabel:"
          ] )
      ; ( "MTL4CommandQueue"
        , [ "commit:count:"; "commit:count:options:"; "device"; "label"
          ; "addResidencySet:"
          ; "copyBufferMappingsFromBuffer:toBuffer:operations:count:"
          ; "copyTextureMappingsFromTexture:toTexture:operations:count:"
          ; "signalDrawable:"; "waitForDrawable:"; "waitForEvent:value:"
          ; "signalEvent:value:"
          ; "updateBufferMappings:heap:operations:count:"
          ; "updateTextureMappings:heap:operations:count:"
          ] )
      ; ( "MTL4CommandQueueDescriptor"
        , [ "label"; "setLabel:" ] )
      ; "MTL4CommitFeedback", [ "error" ]
      ; "MTL4CommitOptions", [ "addFeedbackHandler:" ]
      ; ( "MTL4ComputeCommandEncoder"
        , [ "dispatchThreads:threadsPerThreadgroup:"
          ; "setArgumentTable:"; "setComputePipelineState:"
          ] )
      ; ( "MTL4RenderCommandEncoder"
        , [ "dispatchThreadsPerTile:"
          ; "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferLength:"
          ; "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferLength:instanceCount:baseVertex:baseInstance:"
          ; "drawIndexedPrimitives:indexType:indexBuffer:indexBufferLength:indirectBuffer:"
          ; "drawMeshThreadgroups:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:"
          ; "drawPrimitives:indirectBuffer:"
          ; "drawPrimitives:vertexStart:vertexCount:"
          ; "drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:"
          ; "setArgumentTable:atStages:"
          ; "setBlendColorRed:green:blue:alpha:"
          ; "setColorAttachmentMap:"
          ; "setColorStoreAction:atIndex:"
          ; "setDepthBias:slopeScale:clamp:"
          ; "setDepthTestMinBound:maxBound:"
          ; "setDepthStencilState:"; "setDepthStoreAction:"
          ; "setRenderPipelineState:"
          ; "setScissorRect:"; "setScissorRects:count:"
          ; "setStencilStoreAction:"
          ; "setStencilFrontReferenceValue:backReferenceValue:"
          ; "setStencilReferenceValue:"
          ; "setVertexAmplificationCount:viewMappings:"
          ; "setVisibilityResultMode:offset:"
          ; "setViewport:"; "setViewports:count:"; "tileHeight"; "tileWidth"
          ] )
      ; ( "MTL4RenderPassDescriptor"
        , [ "colorAttachments"; "defaultRasterSampleCount"; "depthAttachment"
          ; "getSamplePositions:count:"; "rasterizationRateMap"
          ; "renderTargetHeight"; "renderTargetWidth"
          ; "setDepthAttachment:"; "setRasterizationRateMap:"
          ; "setSamplePositions:count:"; "setStencilAttachment:"
          ; "setDefaultRasterSampleCount:"; "setRenderTargetHeight:"
          ; "setRenderTargetWidth:"; "setSupportColorAttachmentMapping:"
          ; "setVisibilityResultBuffer:"; "setVisibilityResultType:"
          ; "stencilAttachment"; "supportColorAttachmentMapping"
          ; "visibilityResultBuffer"; "visibilityResultType"
          ] )
      ; ( "MTL4Compiler"
        , [ "device"; "label"
          ; "newBinaryFunctionWithDescriptor:compilerTaskOptions:error:"
          ; "newBinaryFunctionWithDescriptor:compilerTaskOptions:completionHandler:"
          ; "newComputePipelineStateWithDescriptor:compilerTaskOptions:error:"
          ; "newComputePipelineStateWithDescriptor:compilerTaskOptions:completionHandler:"
          ; "newComputePipelineStateWithDescriptor:dynamicLinkingDescriptor:compilerTaskOptions:error:"
          ; "newRenderPipelineStateWithDescriptor:compilerTaskOptions:error:"
          ; "newRenderPipelineStateWithDescriptor:compilerTaskOptions:completionHandler:"
          ; "newRenderPipelineStateWithDescriptor:dynamicLinkingDescriptor:compilerTaskOptions:error:"
          ; "newRenderPipelineStateWithDescriptor:dynamicLinkingDescriptor:compilerTaskOptions:completionHandler:"
          ; "newDynamicLibrary:completionHandler:"
          ; "newDynamicLibrary:error:"
          ; "newDynamicLibraryWithURL:completionHandler:"
          ; "newDynamicLibraryWithURL:error:"
          ; "newLibraryWithDescriptor:completionHandler:"
          ; "newLibraryWithDescriptor:error:"; "pipelineDataSetSerializer"
          ] )
      ; ( "MTL4CompilerTask"
        , [ "compiler"; "status"; "waitUntilCompleted" ] )
      ; ( "MTL4CompilerDescriptor"
        , [ "label"; "pipelineDataSetSerializer"; "setLabel:"
          ; "setPipelineDataSetSerializer:"
          ] )
      ; ( "MTL4CompilerTaskOptions"
        , [ "lookupArchives"; "setLookupArchives:" ] )
      ; ( "MTL4ComputePipelineDescriptor"
        , [ "computeFunctionDescriptor"; "maxTotalThreadsPerThreadgroup"
          ; "requiredThreadsPerThreadgroup"; "setComputeFunctionDescriptor:"
          ; "setMaxTotalThreadsPerThreadgroup:"
          ; "setRequiredThreadsPerThreadgroup:"; "setStaticLinkingDescriptor:"
          ; "setSupportBinaryLinking:"
          ; "setSupportIndirectCommandBuffers:"
          ; "setThreadGroupSizeIsMultipleOfThreadExecutionWidth:"
          ; "staticLinkingDescriptor"; "supportBinaryLinking"
          ; "supportIndirectCommandBuffers"
          ; "threadGroupSizeIsMultipleOfThreadExecutionWidth"
          ] )
      ; ( "MTL4RenderPipelineColorAttachmentDescriptor"
        , [ "alphaBlendOperation"; "blendingState"
          ; "destinationAlphaBlendFactor"; "destinationRGBBlendFactor"
          ; "pixelFormat"; "rgbBlendOperation"; "setAlphaBlendOperation:"
          ; "setBlendingState:"; "setDestinationAlphaBlendFactor:"
          ; "setDestinationRGBBlendFactor:"; "setPixelFormat:"
          ; "setRgbBlendOperation:"; "setSourceAlphaBlendFactor:"
          ; "setSourceRGBBlendFactor:"; "setWriteMask:"
          ; "sourceAlphaBlendFactor"; "sourceRGBBlendFactor"; "writeMask"
          ] )
      ; ( "MTL4RenderPipelineColorAttachmentDescriptorArray"
        , [ "objectAtIndexedSubscript:"
          ; "setObject:atIndexedSubscript:"
          ] )
      ; ( "MTL4RenderPipelineDescriptor"
        , [ "alphaToCoverageState"; "alphaToOneState"; "colorAttachments"
          ; "colorAttachmentMappingState"; "fragmentFunctionDescriptor"
          ; "fragmentStaticLinkingDescriptor"
          ; "inputPrimitiveTopology"; "isRasterizationEnabled"
          ; "maxVertexAmplificationCount"; "rasterSampleCount"; "reset"
          ; "setAlphaToCoverageState:"; "setAlphaToOneState:"
          ; "setColorAttachmentMappingState:"
          ; "setFragmentFunctionDescriptor:"
          ; "setFragmentStaticLinkingDescriptor:"
          ; "setInputPrimitiveTopology:"; "setRasterSampleCount:"
          ; "setRasterizationEnabled:"
          ; "setMaxVertexAmplificationCount:"
          ; "setSupportFragmentBinaryLinking:"
          ; "setSupportIndirectCommandBuffers:"
          ; "setSupportVertexBinaryLinking:"
          ; "setVertexStaticLinkingDescriptor:"
          ; "setVertexDescriptor:"; "setVertexFunctionDescriptor:"
          ; "supportFragmentBinaryLinking"; "supportIndirectCommandBuffers"
          ; "supportVertexBinaryLinking"; "vertexDescriptor"
          ; "vertexFunctionDescriptor"; "vertexStaticLinkingDescriptor"
          ] )
      ; ( "MTL4RenderPipelineDynamicLinkingDescriptor"
        , [ "fragmentLinkingDescriptor"; "meshLinkingDescriptor"
          ; "objectLinkingDescriptor"; "tileLinkingDescriptor"
          ; "vertexLinkingDescriptor"
          ] )
      ; ( "MTL4MeshRenderPipelineDescriptor"
        , [ "alphaToCoverageState"; "alphaToOneState"; "colorAttachments"
          ; "colorAttachmentMappingState"; "fragmentFunctionDescriptor"
          ; "fragmentStaticLinkingDescriptor"
          ; "isRasterizationEnabled"; "maxTotalThreadgroupsPerMeshGrid"
          ; "maxTotalThreadsPerMeshThreadgroup"
          ; "maxTotalThreadsPerObjectThreadgroup"
          ; "maxVertexAmplificationCount"
          ; "meshFunctionDescriptor"; "meshStaticLinkingDescriptor"
          ; "meshThreadgroupSizeIsMultipleOfThreadExecutionWidth"
          ; "objectFunctionDescriptor"; "objectStaticLinkingDescriptor"
          ; "objectThreadgroupSizeIsMultipleOfThreadExecutionWidth"
          ; "payloadMemoryLength"; "rasterSampleCount"; "reset"
          ; "requiredThreadsPerMeshThreadgroup"
          ; "requiredThreadsPerObjectThreadgroup"
          ; "setAlphaToCoverageState:"; "setAlphaToOneState:"
          ; "setColorAttachmentMappingState:"
          ; "setFragmentFunctionDescriptor:"
          ; "setFragmentStaticLinkingDescriptor:"
          ; "setMaxTotalThreadgroupsPerMeshGrid:"
          ; "setMaxTotalThreadsPerMeshThreadgroup:"
          ; "setMaxTotalThreadsPerObjectThreadgroup:"
          ; "setMaxVertexAmplificationCount:"
          ; "setMeshFunctionDescriptor:"
          ; "setMeshStaticLinkingDescriptor:"
          ; "setMeshThreadgroupSizeIsMultipleOfThreadExecutionWidth:"
          ; "setObjectFunctionDescriptor:"
          ; "setObjectStaticLinkingDescriptor:"
          ; "setObjectThreadgroupSizeIsMultipleOfThreadExecutionWidth:"
          ; "setPayloadMemoryLength:"; "setRasterSampleCount:"
          ; "setRasterizationEnabled:"
          ; "setSupportFragmentBinaryLinking:"
          ; "setRequiredThreadsPerMeshThreadgroup:"
          ; "setRequiredThreadsPerObjectThreadgroup:"
          ; "setSupportIndirectCommandBuffers:"
          ; "setSupportMeshBinaryLinking:"
          ; "setSupportObjectBinaryLinking:"
          ; "supportFragmentBinaryLinking"; "supportIndirectCommandBuffers"
          ; "supportMeshBinaryLinking"; "supportObjectBinaryLinking"
          ] )
      ; ( "MTL4TileRenderPipelineDescriptor"
        , [ "colorAttachments"; "maxTotalThreadsPerThreadgroup"
          ; "rasterSampleCount"; "requiredThreadsPerThreadgroup"; "reset"
          ; "setMaxTotalThreadsPerThreadgroup:"; "setRasterSampleCount:"
          ; "setRequiredThreadsPerThreadgroup:"
          ; "setStaticLinkingDescriptor:"; "setSupportBinaryLinking:"
          ; "setThreadgroupSizeMatchesTileSize:"
          ; "setTileFunctionDescriptor:"; "staticLinkingDescriptor"
          ; "supportBinaryLinking"; "threadgroupSizeMatchesTileSize"
          ; "tileFunctionDescriptor"
          ] )
      ; ( "MTL4LibraryDescriptor"
        , [ "name"; "options"; "setName:"; "setOptions:"; "setSource:"
          ; "source"
          ] )
      ; ( "MTL4LibraryFunctionDescriptor"
        , [ "library"; "name"; "setLibrary:"; "setName:" ] )
      ; ( "MTL4PipelineDataSetSerializer"
        , [ "serializeAsArchiveAndFlushToURL:error:"
          ; "serializeAsPipelinesScriptWithError:"
          ] )
      ; ( "MTL4PipelineDataSetSerializerDescriptor"
        , [ "configuration"; "setConfiguration:" ] )
      ; ( "MTL4PipelineDescriptor"
        , [ "label"; "options"; "setLabel:"; "setOptions:" ] )
      ; ( "MTL4PipelineOptions"
        , [ "setShaderReflection:"; "shaderReflection" ] )
      ; ( "MTL4PipelineStageDynamicLinkingDescriptor"
        , [ "binaryLinkedFunctions"; "maxCallStackDepth"
          ; "preloadedLibraries"; "setBinaryLinkedFunctions:"
          ; "setMaxCallStackDepth:"; "setPreloadedLibraries:"
          ] )
      ; ( "MTL4StaticLinkingDescriptor"
        , [ "functionDescriptors"; "groups"; "privateFunctionDescriptors"
          ; "setFunctionDescriptors:"; "setGroups:"
          ; "setPrivateFunctionDescriptors:"
          ] )
      ; ( "MTLBuffer"
        , [ "contents"; "didModifyRange:"; "gpuAddress"; "length"
          ; "sparseBufferTier"
          ; "newTextureWithDescriptor:offset:bytesPerRow:"
          ] )
      ; "MTLAllocation", [ "allocatedSize" ]
      ; ( "MTLBinaryArchive"
        , [ "addComputePipelineFunctionsWithDescriptor:error:"; "device"
          ; "label"; "serializeToURL:error:"; "setLabel:"
          ] )
      ; "MTLBinaryArchiveDescriptor", [ "setUrl:"; "url" ]
      ; ( "MTLBlitCommandEncoder"
        , [ "copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:"
          ] )
      ; ( "MTLCommandBuffer"
        , [ "blitCommandEncoder"; "commit"; "computeCommandEncoder"; "error"
          ; "label"; "resourceStateCommandEncoder"; "setLabel:"; "status"
          ; "useResidencySet:"; "useResidencySets:count:"
          ; "waitUntilCompleted"
          ] )
      ; "MTLCommandEncoder", [ "endEncoding" ]
      ; ( "MTLCompileOptions"
        , [ "fastMathEnabled"; "installName"; "libraries"; "libraryType"
          ; "setFastMathEnabled:"; "setInstallName:"; "setLibraries:"
          ; "setLibraryType:"
          ] )
      ; ( "MTLComputeCommandEncoder"
        , [ "dispatchThreads:threadsPerThreadgroup:"
          ; "executeCommandsInBuffer:withRange:"
          ; "setBuffer:offset:atIndex:"
          ; "setComputePipelineState:"; "setTexture:atIndex:"
          ] )
      ; ( "MTLComputePipelineDescriptor"
        , [ "binaryArchives"; "computeFunction"; "label"; "linkedFunctions"
          ; "preloadedLibraries"; "setBinaryArchives:"
          ; "setComputeFunction:"; "setLabel:"; "setLinkedFunctions:"
          ; "setPreloadedLibraries:"
          ; "setSupportIndirectCommandBuffers:"
          ; "supportIndirectCommandBuffers"
          ] )
      ; "MTLComputePipelineReflection", [ "bindings" ]
      ; ( "MTLComputePipelineState"
        , [ "device"; "label"; "maxTotalThreadsPerThreadgroup"; "reflection"
          ; "threadExecutionWidth"
          ] )
      ; ( "MTLIndirectCommandBuffer"
        , [ "indirectComputeCommandAtIndex:"; "resetWithRange:"; "size" ] )
      ; ( "MTLIndirectComputeCommand"
        , [ "concurrentDispatchThreads:threadsPerThreadgroup:"; "reset"
          ; "setComputePipelineState:"; "setKernelBuffer:offset:atIndex:"
          ] )
      ; ( "MTLRenderPipelineReflection"
        , [ "fragmentBindings"; "meshBindings"; "objectBindings"
          ; "tileBindings"; "vertexBindings"
          ] )
      ; ( "MTLRenderPipelineState"
        , [ "device"; "label"; "maxTotalThreadgroupsPerMeshGrid"
          ; "maxTotalThreadsPerMeshThreadgroup"
          ; "maxTotalThreadsPerObjectThreadgroup"
          ; "maxTotalThreadsPerThreadgroup"; "meshThreadExecutionWidth"
          ; "objectThreadExecutionWidth"; "reflection"
          ; "threadgroupSizeMatchesTileSize"
          ] )
      ; ( "MTLRenderPassAttachmentDescriptor"
        , [ "loadAction"; "setLoadAction:"; "setStoreAction:"
          ; "setTexture:"; "storeAction"; "texture"
          ] )
      ; ( "MTLRenderPassColorAttachmentDescriptor"
        , [ "clearColor"; "setClearColor:" ] )
      ; ( "MTLRenderPassColorAttachmentDescriptorArray"
        , [ "objectAtIndexedSubscript:" ] )
      ; ( "MTLRenderPassDepthAttachmentDescriptor"
        , [ "clearDepth"; "setClearDepth:" ] )
      ; ( "MTLRenderPassStencilAttachmentDescriptor"
        , [ "clearStencil"; "setClearStencil:" ] )
      ; ( "MTLDepthStencilDescriptor"
        , [ "backFaceStencil"; "depthCompareFunction"; "frontFaceStencil"
          ; "isDepthWriteEnabled"; "label"; "setBackFaceStencil:"
          ; "setDepthCompareFunction:"; "setDepthWriteEnabled:"
          ; "setFrontFaceStencil:"; "setLabel:"
          ] )
      ; "MTLDepthStencilState", [ "device"; "label" ]
      ; ( "MTLStencilDescriptor"
        , [ "depthFailureOperation"; "depthStencilPassOperation"; "readMask"
          ; "setDepthFailureOperation:"; "setDepthStencilPassOperation:"
          ; "setReadMask:"; "setStencilCompareFunction:"
          ; "setStencilFailureOperation:"; "setWriteMask:"
          ; "stencilCompareFunction"; "stencilFailureOperation"; "writeMask"
          ] )
      ; ( "MTLDevice"
        , [ "currentAllocatedSize"; "hasUnifiedMemory"; "isHeadless"
          ; "heapBufferSizeAndAlignWithLength:options:"
          ; "heapTextureSizeAndAlignWithDescriptor:"
          ; "isLowPower"; "isRemovable"; "maxBufferLength"; "name"
          ; "minimumLinearTextureAlignmentForPixelFormat:"
          ; "minimumTextureBufferAlignmentForPixelFormat:"
          ; "newBufferWithBytes:length:options:"
          ; "newBufferWithBytesNoCopy:length:options:deallocator:"
          ; "newBufferWithLength:options:"
          ; "newBufferWithLength:options:placementSparsePageSize:"
          ; "newArgumentTableWithDescriptor:error:"
          ; "newCommandAllocator"; "newCommandAllocatorWithDescriptor:error:"
          ; "newCommandBuffer"
          ; "newCommandQueue"
          ; "newBinaryArchiveWithDescriptor:error:"
          ; "newArchiveWithURL:error:"
          ; "newCompilerWithDescriptor:error:"
          ; "newComputePipelineStateWithDescriptor:options:reflection:error:"
          ; "newComputePipelineStateWithFunction:error:"
          ; "newDepthStencilStateWithDescriptor:"
          ; "newIndirectCommandBufferWithDescriptor:maxCommandCount:options:"
          ; "newDynamicLibrary:error:"; "newDynamicLibraryWithURL:error:"
          ; "newLibraryWithURL:error:"
          ; "newLibraryWithSource:options:error:"
          ; "newHeapWithDescriptor:"
          ; "newResidencySetWithDescriptor:error:"
          ; "newMTL4CommandQueueWithDescriptor:error:"
          ; "newPipelineDataSetSerializerWithDescriptor:"
          ; "newSamplerStateWithDescriptor:"
          ; "newSharedTextureWithDescriptor:"
          ; "newSharedTextureWithHandle:"
          ; "newSharedEvent"
          ; "newTextureWithDescriptor:iosurface:plane:"
          ; "newTextureWithDescriptor:"
          ; "isDepth24Stencil8PixelFormatSupported"
          ; "supportsBCTextureCompression"
          ; "recommendedMaxWorkingSetSize"; "registryID"
          ; "sparseTileSizeInBytes"
          ; "sparseTileSizeInBytesForSparsePageSize:"
          ; "sparseTileSizeWithTextureType:pixelFormat:sampleCount:sparsePageSize:"
          ; "supportsDynamicLibraries"; "supportsFamily:"
          ; "supportsFunctionPointers"; "supportsFunctionPointersFromRender"
          ; "supportsRaytracing"
          ; "supportsRaytracingFromRender"; "supportsTextureSampleCount:"
          ; "supportsVertexAmplificationCount:"
          ; "supportsPlacementSparse"
          ] )
      ; ( "MTLFunction"
        , [ "device"; "functionConstantsDictionary"; "functionType"; "label"
          ; "name"; "setLabel:"
          ] )
      ; ( "MTLFunctionConstant"
        , [ "index"; "name"; "required"; "type" ] )
      ; ( "MTLFunctionConstantValues"
        , [ "setConstantValue:type:withName:" ] )
      ; ( "MTLDynamicLibrary"
        , [ "device"; "installName"; "label"; "serializeToURL:error:"
          ; "setLabel:"
          ] )
      ; ( "MTLHeap"
        , [ "cpuCacheMode"; "currentAllocatedSize"; "hazardTrackingMode"
          ; "label"; "maxAvailableSizeWithAlignment:"
          ; "newBufferWithLength:options:"
          ; "newBufferWithLength:options:offset:"
          ; "newTextureWithDescriptor:"
          ; "newTextureWithDescriptor:offset:"; "setLabel:"
          ; "setPurgeableState:"; "size"; "storageMode"; "type"
          ; "usedSize"
          ] )
      ; ( "MTLHeapDescriptor"
        , [ "cpuCacheMode"; "hazardTrackingMode"; "setCpuCacheMode:"
          ; "maxCompatiblePlacementSparsePageSize"
          ; "setHazardTrackingMode:"; "setSize:"; "setStorageMode:"
          ; "setMaxCompatiblePlacementSparsePageSize:"
          ; "setSparsePageSize:"; "setType:"; "size"; "sparsePageSize"
          ; "storageMode"; "type"
          ] )
      ; ( "MTLLibrary"
        , [ "device"; "functionNames"; "installName"; "label"
          ; "newFunctionWithName:"
          ; "newFunctionWithName:constantValues:error:"; "setLabel:"
          ; "type"
          ] )
      ; ( "MTLLinkedFunctions"
        , [ "functions"; "setFunctions:" ] )
      ; ( "MTLLogicalToPhysicalColorAttachmentMap"
        , [ "getPhysicalIndexForLogicalIndex:"; "reset"
          ; "setPhysicalIndex:forLogicalIndex:"
          ] )
      ; ( "MTLBinding"
        , [ "access"; "index"; "isArgument"; "isUsed"; "name"; "type" ] )
      ; ( "MTLBufferBinding"
        , [ "bufferAlignment"; "bufferDataSize"; "bufferDataType" ] )
      ; ( "MTLThreadgroupBinding"
        , [ "threadgroupMemoryAlignment"; "threadgroupMemoryDataSize" ] )
      ; ( "MTLTextureBinding"
        , [ "arrayLength"; "isDepthTexture"; "textureDataType"
          ; "textureType"
          ] )
      ; ( "MTLObjectPayloadBinding"
        , [ "objectPayloadAlignment"; "objectPayloadDataSize" ] )
      ; ( "MTLResidencySet"
        , [ "addAllocation:"; "addAllocations:count:"; "allAllocations"
          ; "allocatedSize"; "allocationCount"; "commit"
          ; "containsAllocation:"; "device"; "endResidency"; "label"
          ; "removeAllAllocations"; "removeAllocation:"
          ; "removeAllocations:count:"; "requestResidency"
          ] )
      ; ( "MTLResidencySetDescriptor"
        , [ "initialCapacity"; "label"; "setInitialCapacity:"; "setLabel:" ] )
      ; ( "MTLResourceStateCommandEncoder"
        , [ "updateTextureMapping:mode:region:mipLevel:slice:" ] )
      ; ( "MTLResource"
        , [ "cpuCacheMode"; "hazardTrackingMode"; "heapOffset"; "isAliasable"
          ; "label"; "makeAliasable"; "setLabel:"; "setPurgeableState:"
          ; "storageMode"
          ] )
      ; ( "MTLSamplerDescriptor"
        , [ "borderColor"; "compareFunction"; "label"; "lodAverage"
          ; "lodBias"; "lodMaxClamp"; "lodMinClamp"; "magFilter"
          ; "maxAnisotropy"
          ; "minFilter"; "mipFilter"; "normalizedCoordinates"
          ; "rAddressMode"; "reductionMode"; "sAddressMode"; "setBorderColor:"
          ; "setCompareFunction:"; "setLabel:"; "setLodAverage:"
          ; "setLodBias:"; "setLodMaxClamp:"; "setLodMinClamp:"
          ; "setMagFilter:"
          ; "setMaxAnisotropy:"; "setMinFilter:"; "setMipFilter:"
          ; "setNormalizedCoordinates:"; "setRAddressMode:"
          ; "setReductionMode:"
          ; "setSAddressMode:"; "setSupportArgumentBuffers:"
          ; "setTAddressMode:"; "supportArgumentBuffers"; "tAddressMode"
          ] )
      ; "MTLSamplerState", [ "device"; "gpuResourceID"; "label" ]
      ; "MTLSharedTextureHandle", [ "device"; "label" ]
      ; "MTLSharedEvent", [ "waitUntilSignaledValue:timeoutMS:" ]
      ; ( "MTLTexture"
        , [ "allowGPUOptimizedContents"; "arrayLength"; "buffer"
          ; "bufferBytesPerRow"; "bufferOffset"; "compressionType"; "depth"
          ; "getBytes:bytesPerRow:bytesPerImage:fromRegion:mipmapLevel:slice:"
          ; "firstMipmapInTail"; "height"; "iosurface"; "iosurfacePlane"
          ; "isShareable"; "isSparse"; "mipmapLevelCount"
          ; "newSharedTextureHandle"
          ; "newTextureViewWithDescriptor:"
          ; "newTextureViewWithPixelFormat:textureType:levels:slices:"
          ; "newTextureViewWithPixelFormat:textureType:levels:slices:swizzle:"
          ; "parentRelativeLevel"; "parentRelativeSlice"; "parentTexture"
          ; "gpuResourceID"; "pixelFormat"
          ; "replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:"
          ; "sampleCount"; "sparseTextureTier"; "tailSizeInBytes"
          ; "swizzle"; "textureType"; "usage"; "width"
          ] )
      ; ( "MTLTextureDescriptor"
        , [ "allowGPUOptimizedContents"; "arrayLength"; "cpuCacheMode"
          ; "compressionType"; "depth"; "hazardTrackingMode"; "height"
          ; "mipmapLevelCount"
          ; "pixelFormat"; "sampleCount"; "setAllowGPUOptimizedContents:"
          ; "setArrayLength:"; "setCpuCacheMode:"; "setDepth:"
          ; "setHazardTrackingMode:"; "setHeight:"
          ; "setCompressionType:"; "setMipmapLevelCount:"; "setPixelFormat:"
          ; "setSampleCount:"
          ; "placementSparsePageSize"; "setPlacementSparsePageSize:"
          ; "setStorageMode:"; "setSwizzle:"; "setTextureType:"
          ; "setUsage:"; "setWidth:"; "storageMode"; "swizzle"
          ; "textureType"; "usage"; "width"
          ] )
      ; ( "MTLTextureViewDescriptor"
        , [ "levelRange"; "pixelFormat"; "setLevelRange:"
          ; "setPixelFormat:"; "setSliceRange:"; "setSwizzle:"
          ; "setTextureType:"; "sliceRange"; "swizzle"; "textureType"
          ] )
      ; ( "MTLTileRenderPipelineColorAttachmentDescriptor"
        , [ "pixelFormat"; "setPixelFormat:" ] )
      ; ( "MTLTileRenderPipelineColorAttachmentDescriptorArray"
        , [ "objectAtIndexedSubscript:"
          ; "setObject:atIndexedSubscript:"
          ] )
      ; ( "MTLVertexAttributeDescriptor"
        , [ "bufferIndex"; "format"; "offset"; "setBufferIndex:"
          ; "setFormat:"; "setOffset:"
          ] )
      ; ( "MTLVertexAttributeDescriptorArray"
        , [ "objectAtIndexedSubscript:"
          ; "setObject:atIndexedSubscript:"
          ] )
      ; ( "MTLVertexBufferLayoutDescriptor"
        , [ "setStepFunction:"; "setStepRate:"; "setStride:"
          ; "stepFunction"; "stepRate"; "stride"
          ] )
      ; ( "MTLVertexBufferLayoutDescriptorArray"
        , [ "objectAtIndexedSubscript:"
          ; "setObject:atIndexedSubscript:"
          ] )
      ; "MTLVertexDescriptor", [ "attributes"; "layouts"; "reset" ]
      ; ( "MTLCommandQueue"
        , [ "addResidencySet:"; "addResidencySets:count:"; "commandBuffer"
          ; "removeResidencySet:"; "removeResidencySets:count:"
          ] )
      ]
  @ properties
      [ "MTL4Archive", [ "label" ]
      ; ( "MTL4BinaryFunctionDescriptor"
        , [ "functionDescriptor"; "name"; "options" ] )
      ; ( "MTL4Compiler"
        , [ "device"; "label"; "pipelineDataSetSerializer" ] )
      ; "MTL4CompilerTask", [ "compiler"; "status" ]
      ; ( "MTL4CompilerDescriptor"
        , [ "label"; "pipelineDataSetSerializer" ] )
      ; "MTL4CompilerTaskOptions", [ "lookupArchives" ]
      ; ( "MTL4ComputePipelineDescriptor"
        , [ "computeFunctionDescriptor"; "maxTotalThreadsPerThreadgroup"
          ; "requiredThreadsPerThreadgroup"; "staticLinkingDescriptor"
          ; "supportBinaryLinking"
          ; "supportIndirectCommandBuffers"
          ; "threadGroupSizeIsMultipleOfThreadExecutionWidth"
          ] )
      ; ( "MTL4RenderPipelineColorAttachmentDescriptor"
        , [ "alphaBlendOperation"; "blendingState"
          ; "destinationAlphaBlendFactor"; "destinationRGBBlendFactor"
          ; "pixelFormat"; "rgbBlendOperation"; "sourceAlphaBlendFactor"
          ; "sourceRGBBlendFactor"; "writeMask"
          ] )
      ; ( "MTL4RenderPipelineDescriptor"
        , [ "alphaToCoverageState"; "alphaToOneState"; "colorAttachments"
          ; "colorAttachmentMappingState"; "fragmentFunctionDescriptor"
          ; "fragmentStaticLinkingDescriptor"; "inputPrimitiveTopology"
          ; "maxVertexAmplificationCount"; "rasterSampleCount"
          ; "rasterizationEnabled"; "supportFragmentBinaryLinking"
          ; "supportIndirectCommandBuffers"; "supportVertexBinaryLinking"
          ; "vertexDescriptor"; "vertexFunctionDescriptor"
          ; "vertexStaticLinkingDescriptor"
          ] )
      ; ( "MTL4RenderPipelineDynamicLinkingDescriptor"
        , [ "fragmentLinkingDescriptor"; "meshLinkingDescriptor"
          ; "objectLinkingDescriptor"; "tileLinkingDescriptor"
          ; "vertexLinkingDescriptor"
          ] )
      ; ( "MTL4MeshRenderPipelineDescriptor"
        , [ "alphaToCoverageState"; "alphaToOneState"; "colorAttachments"
          ; "colorAttachmentMappingState"; "fragmentFunctionDescriptor"
          ; "fragmentStaticLinkingDescriptor"
          ; "maxTotalThreadgroupsPerMeshGrid"
          ; "maxTotalThreadsPerMeshThreadgroup"
          ; "maxTotalThreadsPerObjectThreadgroup"
          ; "maxVertexAmplificationCount"
          ; "meshFunctionDescriptor"; "meshStaticLinkingDescriptor"
          ; "meshThreadgroupSizeIsMultipleOfThreadExecutionWidth"
          ; "objectFunctionDescriptor"; "objectStaticLinkingDescriptor"
          ; "objectThreadgroupSizeIsMultipleOfThreadExecutionWidth"
          ; "payloadMemoryLength"; "rasterSampleCount"
          ; "rasterizationEnabled"; "requiredThreadsPerMeshThreadgroup"
          ; "requiredThreadsPerObjectThreadgroup"
          ; "supportFragmentBinaryLinking"; "supportIndirectCommandBuffers"
          ; "supportMeshBinaryLinking"; "supportObjectBinaryLinking"
          ] )
      ; ( "MTL4TileRenderPipelineDescriptor"
        , [ "colorAttachments"; "maxTotalThreadsPerThreadgroup"
          ; "rasterSampleCount"; "requiredThreadsPerThreadgroup"
          ; "staticLinkingDescriptor"; "supportBinaryLinking"
          ; "threadgroupSizeMatchesTileSize"; "tileFunctionDescriptor"
          ] )
      ; "MTL4LibraryDescriptor", [ "name"; "options"; "source" ]
      ; "MTL4LibraryFunctionDescriptor", [ "library"; "name" ]
      ; "MTL4PipelineDataSetSerializerDescriptor", [ "configuration" ]
      ; "MTL4PipelineDescriptor", [ "label"; "options" ]
      ; "MTL4PipelineOptions", [ "shaderReflection" ]
      ; ( "MTL4PipelineStageDynamicLinkingDescriptor"
        , [ "binaryLinkedFunctions"; "maxCallStackDepth"
          ; "preloadedLibraries"
          ] )
      ; ( "MTL4StaticLinkingDescriptor"
        , [ "functionDescriptors"; "groups"; "privateFunctionDescriptors" ] )
      ; "MTL4ArgumentTable", [ "device"; "label" ]
      ; ( "MTL4ArgumentTableDescriptor"
        , [ "initializeBindings"; "label"; "maxBufferBindCount"
          ; "maxSamplerStateBindCount"; "maxTextureBindCount"
          ; "supportAttributeStrides"
          ] )
      ; "MTL4CommandAllocator", [ "device"; "label" ]
      ; "MTL4CommandAllocatorDescriptor", [ "label" ]
      ; "MTL4CommandBuffer", [ "device"; "label" ]
      ; "MTL4CommandBufferOptions", [ "logState" ]
      ; "MTL4CommandEncoder", [ "commandBuffer"; "label" ]
      ; "MTL4CommandQueue", [ "device"; "label" ]
      ; "MTL4CommandQueueDescriptor", [ "label" ]
      ; "MTL4CommitFeedback", [ "error" ]
      ; "MTL4RenderCommandEncoder", [ "tileHeight"; "tileWidth" ]
      ; ( "MTL4RenderPassDescriptor"
        , [ "colorAttachments"; "defaultRasterSampleCount"; "depthAttachment"
          ; "rasterizationRateMap"; "renderTargetHeight"; "renderTargetWidth"; "stencilAttachment"
          ; "supportColorAttachmentMapping"
          ; "visibilityResultBuffer"; "visibilityResultType"
          ] )
      ; "MTLAllocation", [ "allocatedSize" ]
      ; "MTLBinaryArchive", [ "device"; "label" ]
      ; "MTLBinaryArchiveDescriptor", [ "url" ]
      ; ( "MTLCommandBuffer", [ "error"; "label"; "status" ] )
      ; ( "MTLCompileOptions"
        , [ "fastMathEnabled"; "installName"; "libraries"; "libraryType" ] )
      ; ( "MTLComputePipelineDescriptor"
        , [ "binaryArchives"; "computeFunction"; "label"; "linkedFunctions"
          ; "preloadedLibraries"; "supportIndirectCommandBuffers"
          ] )
      ; "MTLComputePipelineReflection", [ "bindings" ]
      ; ( "MTLComputePipelineState"
        , [ "device"; "label"; "maxTotalThreadsPerThreadgroup"; "reflection"
          ; "threadExecutionWidth"
          ] )
      ; "MTLIndirectCommandBuffer", [ "size" ]
      ; ( "MTLRenderPipelineReflection"
        , [ "fragmentBindings"; "meshBindings"; "objectBindings"
          ; "tileBindings"; "vertexBindings"
          ] )
      ; ( "MTLRenderPipelineState"
        , [ "device"; "label"; "maxTotalThreadgroupsPerMeshGrid"
          ; "maxTotalThreadsPerMeshThreadgroup"
          ; "maxTotalThreadsPerObjectThreadgroup"
          ; "maxTotalThreadsPerThreadgroup"; "meshThreadExecutionWidth"
          ; "objectThreadExecutionWidth"; "reflection"
          ; "threadgroupSizeMatchesTileSize"
          ] )
      ; ( "MTLRenderPassAttachmentDescriptor"
        , [ "loadAction"; "storeAction"; "texture" ] )
      ; "MTLRenderPassColorAttachmentDescriptor", [ "clearColor" ]
      ; "MTLRenderPassDepthAttachmentDescriptor", [ "clearDepth" ]
      ; "MTLRenderPassStencilAttachmentDescriptor", [ "clearStencil" ]
      ; ( "MTLDepthStencilDescriptor"
        , [ "backFaceStencil"; "depthCompareFunction"; "depthWriteEnabled"
          ; "frontFaceStencil"; "label"
          ] )
      ; "MTLDepthStencilState", [ "device"; "label" ]
      ; ( "MTLStencilDescriptor"
        , [ "depthFailureOperation"; "depthStencilPassOperation"; "readMask"
          ; "stencilCompareFunction"; "stencilFailureOperation"; "writeMask"
          ] )
      ; ( "MTLDevice"
        , [ "currentAllocatedSize"; "depth24Stencil8PixelFormatSupported"
          ; "hasUnifiedMemory"; "headless"; "lowPower"; "maxBufferLength"
          ; "name"; "recommendedMaxWorkingSetSize"
          ; "registryID"; "removable"; "supportsDynamicLibraries"
          ; "supportsFunctionPointers"; "supportsFunctionPointersFromRender"
          ; "supportsRaytracing"
          ; "supportsPlacementSparse"; "supportsRaytracingFromRender"
          ; "sparseTileSizeInBytes"
          ] )
      ; ( "MTLFunction"
        , [ "device"; "functionConstantsDictionary"; "functionType"; "label"
          ; "name"
          ] )
      ; ( "MTLFunctionConstant"
        , [ "index"; "name"; "required"; "type" ] )
      ; ( "MTLDynamicLibrary"
        , [ "device"; "installName"; "label" ] )
      ; ( "MTLHeap"
        , [ "cpuCacheMode"; "currentAllocatedSize"; "hazardTrackingMode"
          ; "label"; "size"; "storageMode"; "type"; "usedSize"
          ] )
      ; ( "MTLHeapDescriptor"
        , [ "cpuCacheMode"; "hazardTrackingMode"
          ; "maxCompatiblePlacementSparsePageSize"; "size"
          ; "sparsePageSize"; "storageMode"; "type"
          ] )
      ; ( "MTLLibrary"
        , [ "device"; "functionNames"; "installName"; "label"; "type" ] )
      ; "MTLLinkedFunctions", [ "functions" ]
      ; ( "MTLBinding"
        , [ "access"; "argument"; "index"; "name"; "type"; "used" ] )
      ; ( "MTLBufferBinding"
        , [ "bufferAlignment"; "bufferDataSize"; "bufferDataType" ] )
      ; ( "MTLThreadgroupBinding"
        , [ "threadgroupMemoryAlignment"; "threadgroupMemoryDataSize" ] )
      ; ( "MTLTextureBinding"
        , [ "arrayLength"; "depthTexture"; "textureDataType"; "textureType" ] )
      ; ( "MTLObjectPayloadBinding"
        , [ "objectPayloadAlignment"; "objectPayloadDataSize" ] )
      ; ( "MTLResource"
        , [ "cpuCacheMode"; "hazardTrackingMode"; "heapOffset"; "label"
          ; "storageMode"
          ] )
      ; ( "MTLResidencySet"
        , [ "allAllocations"; "allocatedSize"; "allocationCount"; "device"
          ; "label"
          ] )
      ; ( "MTLResidencySetDescriptor", [ "initialCapacity"; "label" ] )
      ; ( "MTLSamplerDescriptor"
        , [ "borderColor"; "compareFunction"; "label"; "lodAverage"
          ; "lodBias"; "lodMaxClamp"; "lodMinClamp"; "magFilter"
          ; "maxAnisotropy"
          ; "minFilter"; "mipFilter"; "normalizedCoordinates"
          ; "rAddressMode"; "reductionMode"; "sAddressMode"
          ; "supportArgumentBuffers"; "tAddressMode"
          ] )
      ; "MTLSamplerState", [ "device"; "gpuResourceID"; "label" ]
      ; "MTLSharedTextureHandle", [ "device"; "label" ]
      ; ( "MTLTexture"
        , [ "allowGPUOptimizedContents"; "arrayLength"; "compressionType"
          ; "depth"; "firstMipmapInTail"; "height"
          ; "iosurface"; "iosurfacePlane"; "isSparse"; "mipmapLevelCount"
          ; "parentRelativeLevel"; "parentRelativeSlice"; "parentTexture"
          ; "gpuResourceID"; "pixelFormat"; "sampleCount"; "shareable"
          ; "sparseTextureTier"
          ; "swizzle"; "tailSizeInBytes"; "textureType"; "usage"; "width"
          ] )
      ; ( "MTLTextureDescriptor"
        , [ "allowGPUOptimizedContents"; "arrayLength"; "cpuCacheMode"
          ; "compressionType"; "depth"; "hazardTrackingMode"; "height"
          ; "mipmapLevelCount"
          ; "pixelFormat"; "placementSparsePageSize"; "sampleCount"
          ; "storageMode"; "swizzle"; "textureType"; "usage"; "width"
          ] )
      ; ( "MTLTextureViewDescriptor"
        , [ "levelRange"; "pixelFormat"; "sliceRange"; "swizzle"
          ; "textureType"
          ] )
      ; "MTLTileRenderPipelineColorAttachmentDescriptor", [ "pixelFormat" ]
      ; ( "MTLVertexAttributeDescriptor"
        , [ "bufferIndex"; "format"; "offset" ] )
      ; ( "MTLVertexBufferLayoutDescriptor"
        , [ "stepFunction"; "stepRate"; "stride" ] )
      ; "MTLVertexDescriptor", [ "attributes"; "layouts" ]
      ; "MTLBuffer", [ "gpuAddress"; "length"; "sparseBufferTier" ]
      ]
  @ enum_cases "MTL4AlphaToCoverageState"
      [ "MTL4AlphaToCoverageStateDisabled"
      ; "MTL4AlphaToCoverageStateEnabled"
      ]
  @ enum_cases "MTL4AlphaToOneState"
      [ "MTL4AlphaToOneStateDisabled"; "MTL4AlphaToOneStateEnabled" ]
  @ enum_cases "MTL4VisibilityOptions"
      [ "MTL4VisibilityOptionResourceAlias" ]
  @ enum_cases "MTL4BinaryFunctionOptions"
      [ "MTL4BinaryFunctionOptionNone"
      ; "MTL4BinaryFunctionOptionPipelineIndependent"
      ]
  @ enum_cases "MTL4BlendState"
      [ "MTL4BlendStateDisabled"; "MTL4BlendStateEnabled" ]
  @ enum_cases "MTL4CompilerTaskStatus"
      [ "MTL4CompilerTaskStatusNone"; "MTL4CompilerTaskStatusScheduled"
      ; "MTL4CompilerTaskStatusCompiling"; "MTL4CompilerTaskStatusFinished"
      ]
  @ enum_cases "MTL4IndirectCommandBufferSupportState"
      [ "MTL4IndirectCommandBufferSupportStateDisabled"
      ; "MTL4IndirectCommandBufferSupportStateEnabled"
      ]
  @ enum_cases "MTL4LogicalToPhysicalColorAttachmentMappingState"
      [ "MTL4LogicalToPhysicalColorAttachmentMappingStateIdentity"
      ; "MTL4LogicalToPhysicalColorAttachmentMappingStateInherited"
      ]
  @ enum_cases "MTL4PipelineDataSetSerializerConfiguration"
      [ "MTL4PipelineDataSetSerializerConfigurationCaptureBinaries"
      ; "MTL4PipelineDataSetSerializerConfigurationCaptureDescriptors"
      ]
  @ enum_cases "MTL4ShaderReflection"
      [ "MTL4ShaderReflectionBindingInfo"
      ; "MTL4ShaderReflectionBufferTypeInfo"
      ]
  @ enum_cases "MTLLoadAction"
      [ "MTLLoadActionClear"; "MTLLoadActionDontCare"; "MTLLoadActionLoad" ]
  @ enum_cases "MTLIndexType"
      [ "MTLIndexTypeUInt16"; "MTLIndexTypeUInt32" ]
  @ enum_cases "MTLCullMode"
      [ "MTLCullModeNone"; "MTLCullModeFront"; "MTLCullModeBack" ]
  @ enum_cases "MTLDepthClipMode"
      [ "MTLDepthClipModeClip"; "MTLDepthClipModeClamp" ]
  @ enum_cases "MTLPrimitiveType"
      [ "MTLPrimitiveTypeLine"; "MTLPrimitiveTypeLineStrip"
      ; "MTLPrimitiveTypePoint"; "MTLPrimitiveTypeTriangle"
      ; "MTLPrimitiveTypeTriangleStrip"
      ]
  @ enum_cases "MTLRenderStages"
      [ "MTLRenderStageFragment"; "MTLRenderStageMesh"
      ; "MTLRenderStageObject"; "MTLRenderStageTile"
      ; "MTLRenderStageVertex"
      ]
  @ enum_cases "MTLStoreAction"
      [ "MTLStoreActionDontCare"; "MTLStoreActionStore"
      ; "MTLStoreActionUnknown"
      ]
  @ enum_cases "MTLTriangleFillMode"
      [ "MTLTriangleFillModeFill"; "MTLTriangleFillModeLines" ]
  @ enum_cases "MTLWinding"
      [ "MTLWindingClockwise"; "MTLWindingCounterClockwise" ]
  @ enum_cases "MTLVisibilityResultMode"
      [ "MTLVisibilityResultModeDisabled"; "MTLVisibilityResultModeBoolean"
      ; "MTLVisibilityResultModeCounting"
      ]
  @ enum_cases "MTLVisibilityResultType"
      [ "MTLVisibilityResultTypeReset"; "MTLVisibilityResultTypeAccumulate" ]
  @ enum_cases "MTLBindingAccess"
      [ "MTLArgumentAccessReadOnly"; "MTLArgumentAccessReadWrite"
      ; "MTLArgumentAccessWriteOnly"; "MTLBindingAccessReadOnly"
      ; "MTLBindingAccessReadWrite"; "MTLBindingAccessWriteOnly"
      ]
  @ enum_cases "MTLBindingType"
      [ "MTLBindingTypeBuffer"; "MTLBindingTypeThreadgroupMemory"
      ; "MTLBindingTypeTexture"; "MTLBindingTypeSampler"
      ; "MTLBindingTypeImageblockData"; "MTLBindingTypeImageblock"
      ; "MTLBindingTypeVisibleFunctionTable"
      ; "MTLBindingTypePrimitiveAccelerationStructure"
      ; "MTLBindingTypeInstanceAccelerationStructure"
      ; "MTLBindingTypeIntersectionFunctionTable"
      ; "MTLBindingTypeObjectPayload"; "MTLBindingTypeTensor"
      ]
  @ enum_cases "MTLBlendFactor"
      [ "MTLBlendFactorZero"; "MTLBlendFactorOne"
      ; "MTLBlendFactorSourceColor"; "MTLBlendFactorOneMinusSourceColor"
      ; "MTLBlendFactorSourceAlpha"; "MTLBlendFactorOneMinusSourceAlpha"
      ; "MTLBlendFactorDestinationColor"
      ; "MTLBlendFactorOneMinusDestinationColor"
      ; "MTLBlendFactorDestinationAlpha"
      ; "MTLBlendFactorOneMinusDestinationAlpha"
      ; "MTLBlendFactorSourceAlphaSaturated"; "MTLBlendFactorBlendColor"
      ; "MTLBlendFactorOneMinusBlendColor"; "MTLBlendFactorBlendAlpha"
      ; "MTLBlendFactorOneMinusBlendAlpha"; "MTLBlendFactorSource1Color"
      ; "MTLBlendFactorOneMinusSource1Color"
      ; "MTLBlendFactorSource1Alpha"
      ; "MTLBlendFactorOneMinusSource1Alpha"
      ]
  @ enum_cases "MTLBlendOperation"
      [ "MTLBlendOperationAdd"; "MTLBlendOperationSubtract"
      ; "MTLBlendOperationReverseSubtract"; "MTLBlendOperationMin"
      ; "MTLBlendOperationMax"
      ]
  @ enum_cases "MTLFunctionType"
      [ "MTLFunctionTypeVertex"; "MTLFunctionTypeFragment"
      ; "MTLFunctionTypeKernel"; "MTLFunctionTypeVisible"
      ; "MTLFunctionTypeIntersection"; "MTLFunctionTypeMesh"
      ; "MTLFunctionTypeObject"
      ]
  @ enum_cases "MTLPrimitiveTopologyClass"
      [ "MTLPrimitiveTopologyClassPoint"; "MTLPrimitiveTopologyClassLine"
      ; "MTLPrimitiveTopologyClassTriangle"
      ]
  @ enum_cases "MTLPipelineOption"
      [ "MTLPipelineOptionNone"; "MTLPipelineOptionArgumentInfo"
      ; "MTLPipelineOptionBindingInfo"; "MTLPipelineOptionBufferTypeInfo"
      ; "MTLPipelineOptionFailOnBinaryArchiveMiss"
      ]
  @ enum_cases "MTLLibraryType"
      [ "MTLLibraryTypeExecutable"; "MTLLibraryTypeDynamic" ]
  @ enum_cases "MTLDataType"
      [ "MTLDataTypeNone"; "MTLDataTypeStruct"; "MTLDataTypeArray"
      ; "MTLDataTypeFloat"; "MTLDataTypeFloat2"; "MTLDataTypeFloat3"
      ; "MTLDataTypeFloat4"; "MTLDataTypeFloat2x2"
      ; "MTLDataTypeFloat2x3"; "MTLDataTypeFloat2x4"
      ; "MTLDataTypeFloat3x2"; "MTLDataTypeFloat3x3"
      ; "MTLDataTypeFloat3x4"; "MTLDataTypeFloat4x2"
      ; "MTLDataTypeFloat4x3"; "MTLDataTypeFloat4x4"
      ; "MTLDataTypeHalf"; "MTLDataTypeHalf2"; "MTLDataTypeHalf3"
      ; "MTLDataTypeHalf4"; "MTLDataTypeHalf2x2"; "MTLDataTypeHalf2x3"
      ; "MTLDataTypeHalf2x4"; "MTLDataTypeHalf3x2"
      ; "MTLDataTypeHalf3x3"; "MTLDataTypeHalf3x4"
      ; "MTLDataTypeHalf4x2"; "MTLDataTypeHalf4x3"
      ; "MTLDataTypeHalf4x4"; "MTLDataTypeInt"; "MTLDataTypeInt2"
      ; "MTLDataTypeInt3"; "MTLDataTypeInt4"; "MTLDataTypeUInt"
      ; "MTLDataTypeUInt2"; "MTLDataTypeUInt3"; "MTLDataTypeUInt4"
      ; "MTLDataTypeShort"; "MTLDataTypeShort2"; "MTLDataTypeShort3"
      ; "MTLDataTypeShort4"; "MTLDataTypeUShort"; "MTLDataTypeUShort2"
      ; "MTLDataTypeUShort3"; "MTLDataTypeUShort4"; "MTLDataTypeChar"
      ; "MTLDataTypeChar2"; "MTLDataTypeChar3"; "MTLDataTypeChar4"
      ; "MTLDataTypeUChar"; "MTLDataTypeUChar2"; "MTLDataTypeUChar3"
      ; "MTLDataTypeUChar4"; "MTLDataTypeBool"; "MTLDataTypeBool2"
      ; "MTLDataTypeBool3"; "MTLDataTypeBool4"; "MTLDataTypeTexture"
      ; "MTLDataTypeSampler"; "MTLDataTypePointer"; "MTLDataTypeLong"
      ; "MTLDataTypeLong2"; "MTLDataTypeLong3"; "MTLDataTypeLong4"
      ; "MTLDataTypeULong"; "MTLDataTypeULong2"; "MTLDataTypeULong3"
      ; "MTLDataTypeULong4"; "MTLDataTypeBFloat"; "MTLDataTypeBFloat2"
      ; "MTLDataTypeBFloat3"; "MTLDataTypeBFloat4"
      ; "MTLDataTypeR8Unorm"; "MTLDataTypeR8Snorm"
      ; "MTLDataTypeR16Unorm"; "MTLDataTypeR16Snorm"
      ; "MTLDataTypeRG8Unorm"; "MTLDataTypeRG8Snorm"
      ; "MTLDataTypeRG16Unorm"; "MTLDataTypeRG16Snorm"
      ; "MTLDataTypeRGBA8Unorm"; "MTLDataTypeRGBA8Unorm_sRGB"
      ; "MTLDataTypeRGBA8Snorm"; "MTLDataTypeRGBA16Unorm"
      ; "MTLDataTypeRGBA16Snorm"; "MTLDataTypeRGB10A2Unorm"
      ; "MTLDataTypeRG11B10Float"; "MTLDataTypeRGB9E5Float"
      ; "MTLDataTypeRenderPipeline"; "MTLDataTypeComputePipeline"
      ; "MTLDataTypeIndirectCommandBuffer"
      ; "MTLDataTypeVisibleFunctionTable"
      ; "MTLDataTypeIntersectionFunctionTable"
      ; "MTLDataTypePrimitiveAccelerationStructure"
      ; "MTLDataTypeInstanceAccelerationStructure"
      ; "MTLDataTypeDepthStencilState"; "MTLDataTypeTensor"
      ]
  @ enum_cases "MTLStages"
      [ "MTLStageAll"; "MTLStageResourceState"
      ; "MTLStageAccelerationStructure"; "MTLStageBlit"
      ; "MTLStageDispatch"; "MTLStageFragment"
      ; "MTLStageMachineLearning"; "MTLStageMesh"
      ; "MTLStageObject"; "MTLStageTile"; "MTLStageVertex"
      ]
  @ enum_cases "MTLGPUFamily"
      [ "MTLGPUFamilyApple1"; "MTLGPUFamilyApple2"; "MTLGPUFamilyApple3"
      ; "MTLGPUFamilyApple4"; "MTLGPUFamilyApple5"; "MTLGPUFamilyApple6"
      ; "MTLGPUFamilyApple7"; "MTLGPUFamilyApple8"; "MTLGPUFamilyApple9"
      ; "MTLGPUFamilyApple10"; "MTLGPUFamilyMac2"; "MTLGPUFamilyCommon1"
      ; "MTLGPUFamilyCommon2"; "MTLGPUFamilyCommon3"; "MTLGPUFamilyMetal3"
      ; "MTLGPUFamilyMetal4"
      ]
  @ enum_cases "MTLStorageMode"
      [ "MTLStorageModeShared"; "MTLStorageModeManaged"; "MTLStorageModePrivate" ]
  @ enum_cases "MTLResourceOptions"
      [ "MTLResourceStorageModeShared"; "MTLResourceStorageModeManaged"
      ; "MTLResourceStorageModePrivate"
      ]
  @ enum_cases "MTLCommandBufferStatus"
      [ "MTLCommandBufferStatusNotEnqueued"; "MTLCommandBufferStatusEnqueued"
      ; "MTLCommandBufferStatusCommitted"; "MTLCommandBufferStatusScheduled"
      ; "MTLCommandBufferStatusCompleted"; "MTLCommandBufferStatusError"
      ]
  @ enum_cases "MTLCompareFunction"
      [ "MTLCompareFunctionNever"; "MTLCompareFunctionLess"
      ; "MTLCompareFunctionEqual"; "MTLCompareFunctionLessEqual"
      ; "MTLCompareFunctionGreater"; "MTLCompareFunctionNotEqual"
      ; "MTLCompareFunctionGreaterEqual"; "MTLCompareFunctionAlways"
      ]
  @ enum_cases "MTLColorWriteMask"
      [ "MTLColorWriteMaskNone"; "MTLColorWriteMaskRed"
      ; "MTLColorWriteMaskGreen"; "MTLColorWriteMaskBlue"
      ; "MTLColorWriteMaskAlpha"; "MTLColorWriteMaskAll"
      ]
  @ enum_cases "MTLVertexFormat"
      [ "MTLVertexFormatUChar2"; "MTLVertexFormatUChar3"
      ; "MTLVertexFormatUChar4"; "MTLVertexFormatChar2"
      ; "MTLVertexFormatChar3"; "MTLVertexFormatChar4"
      ; "MTLVertexFormatUChar2Normalized"
      ; "MTLVertexFormatUChar3Normalized"
      ; "MTLVertexFormatUChar4Normalized"
      ; "MTLVertexFormatChar2Normalized"
      ; "MTLVertexFormatChar3Normalized"
      ; "MTLVertexFormatChar4Normalized"; "MTLVertexFormatUShort2"
      ; "MTLVertexFormatUShort3"; "MTLVertexFormatUShort4"
      ; "MTLVertexFormatShort2"; "MTLVertexFormatShort3"
      ; "MTLVertexFormatShort4"; "MTLVertexFormatUShort2Normalized"
      ; "MTLVertexFormatUShort3Normalized"
      ; "MTLVertexFormatUShort4Normalized"
      ; "MTLVertexFormatShort2Normalized"
      ; "MTLVertexFormatShort3Normalized"
      ; "MTLVertexFormatShort4Normalized"; "MTLVertexFormatHalf2"
      ; "MTLVertexFormatHalf3"; "MTLVertexFormatHalf4"
      ; "MTLVertexFormatFloat"; "MTLVertexFormatFloat2"
      ; "MTLVertexFormatFloat3"; "MTLVertexFormatFloat4"
      ; "MTLVertexFormatInt"; "MTLVertexFormatInt2"
      ; "MTLVertexFormatInt3"; "MTLVertexFormatInt4"
      ; "MTLVertexFormatUInt"; "MTLVertexFormatUInt2"
      ; "MTLVertexFormatUInt3"; "MTLVertexFormatUInt4"
      ; "MTLVertexFormatInt1010102Normalized"
      ; "MTLVertexFormatUInt1010102Normalized"
      ; "MTLVertexFormatUChar4Normalized_BGRA"; "MTLVertexFormatUChar"
      ; "MTLVertexFormatChar"; "MTLVertexFormatUCharNormalized"
      ; "MTLVertexFormatCharNormalized"; "MTLVertexFormatUShort"
      ; "MTLVertexFormatShort"; "MTLVertexFormatUShortNormalized"
      ; "MTLVertexFormatShortNormalized"; "MTLVertexFormatHalf"
      ; "MTLVertexFormatFloatRG11B10"; "MTLVertexFormatFloatRGB9E5"
      ]
  @ enum_cases "MTLVertexStepFunction"
      [ "MTLVertexStepFunctionConstant"; "MTLVertexStepFunctionPerVertex"
      ; "MTLVertexStepFunctionPerInstance"; "MTLVertexStepFunctionPerPatch"
      ; "MTLVertexStepFunctionPerPatchControlPoint"
      ]
  @ enum_cases "MTLStencilOperation"
      [ "MTLStencilOperationKeep"; "MTLStencilOperationZero"
      ; "MTLStencilOperationReplace"; "MTLStencilOperationIncrementClamp"
      ; "MTLStencilOperationDecrementClamp"; "MTLStencilOperationInvert"
      ; "MTLStencilOperationIncrementWrap"
      ; "MTLStencilOperationDecrementWrap"
      ]
  @ enum_cases "MTLCPUCacheMode"
      [ "MTLCPUCacheModeDefaultCache"; "MTLCPUCacheModeWriteCombined" ]
  @ enum_cases "MTLHazardTrackingMode"
      [ "MTLHazardTrackingModeDefault"; "MTLHazardTrackingModeUntracked"
      ; "MTLHazardTrackingModeTracked"
      ]
  @ enum_cases "MTLHeapType"
      [ "MTLHeapTypeAutomatic"; "MTLHeapTypePlacement"; "MTLHeapTypeSparse" ]
  @ enum_cases "MTLSparsePageSize"
      [ "MTLSparsePageSize16"; "MTLSparsePageSize64"
      ; "MTLSparsePageSize256"
      ]
  @ enum_cases "MTLSparseTextureMappingMode"
      [ "MTLSparseTextureMappingModeMap"; "MTLSparseTextureMappingModeUnmap" ]
  @ enum_cases "MTLSamplerReductionMode"
      [ "MTLSamplerReductionModeWeightedAverage"
      ; "MTLSamplerReductionModeMinimum"; "MTLSamplerReductionModeMaximum"
      ]
  @ enum_cases "MTLBufferSparseTier"
      [ "MTLBufferSparseTierNone"; "MTLBufferSparseTier1" ]
  @ enum_cases "MTLTextureSparseTier"
      [ "MTLTextureSparseTierNone"; "MTLTextureSparseTier1"
      ; "MTLTextureSparseTier2"
      ]
  @ enum_cases "MTLTextureCompressionType"
      [ "MTLTextureCompressionTypeLossless"; "MTLTextureCompressionTypeLossy" ]
  @ enum_cases "MTLTextureSwizzle"
      [ "MTLTextureSwizzleZero"; "MTLTextureSwizzleOne"
      ; "MTLTextureSwizzleRed"; "MTLTextureSwizzleGreen"
      ; "MTLTextureSwizzleBlue"; "MTLTextureSwizzleAlpha"
      ]
  @ enum_cases "MTLPixelFormat"
      [ "MTLPixelFormatInvalid"
      ; "MTLPixelFormatPVRTC_RGB_2BPP"
      ; "MTLPixelFormatPVRTC_RGB_2BPP_sRGB"
      ; "MTLPixelFormatPVRTC_RGB_4BPP"
      ; "MTLPixelFormatPVRTC_RGB_4BPP_sRGB"
      ; "MTLPixelFormatPVRTC_RGBA_2BPP"
      ; "MTLPixelFormatPVRTC_RGBA_2BPP_sRGB"
      ; "MTLPixelFormatPVRTC_RGBA_4BPP"
      ; "MTLPixelFormatPVRTC_RGBA_4BPP_sRGB"
      ; "MTLPixelFormatUnspecialized"
      ; "MTLPixelFormatA8Unorm"; "MTLPixelFormatR8Unorm"
      ; "MTLPixelFormatR8Unorm_sRGB"; "MTLPixelFormatR8Snorm"
      ; "MTLPixelFormatR8Uint"; "MTLPixelFormatR8Sint"
      ; "MTLPixelFormatR16Unorm"; "MTLPixelFormatR16Snorm"
      ; "MTLPixelFormatR16Uint"; "MTLPixelFormatR16Sint"
      ; "MTLPixelFormatR16Float"; "MTLPixelFormatRG8Unorm"
      ; "MTLPixelFormatRG8Unorm_sRGB"; "MTLPixelFormatRG8Snorm"
      ; "MTLPixelFormatRG8Uint"; "MTLPixelFormatRG8Sint"
      ; "MTLPixelFormatB5G6R5Unorm"; "MTLPixelFormatA1BGR5Unorm"
      ; "MTLPixelFormatABGR4Unorm"; "MTLPixelFormatBGR5A1Unorm"
      ; "MTLPixelFormatR32Uint"; "MTLPixelFormatR32Sint"
      ; "MTLPixelFormatR32Float"; "MTLPixelFormatRG16Unorm"
      ; "MTLPixelFormatRG16Snorm"; "MTLPixelFormatRG16Uint"
      ; "MTLPixelFormatRG16Sint"; "MTLPixelFormatRG16Float"
      ; "MTLPixelFormatRGBA8Unorm"; "MTLPixelFormatRGBA8Unorm_sRGB"
      ; "MTLPixelFormatRGBA8Snorm"; "MTLPixelFormatRGBA8Uint"
      ; "MTLPixelFormatRGBA8Sint"; "MTLPixelFormatBGRA8Unorm"
      ; "MTLPixelFormatBGRA8Unorm_sRGB"; "MTLPixelFormatRGB10A2Unorm"
      ; "MTLPixelFormatRGB10A2Uint"; "MTLPixelFormatRG11B10Float"
      ; "MTLPixelFormatRGB9E5Float"; "MTLPixelFormatBGR10A2Unorm"
      ; "MTLPixelFormatBGR10_XR"; "MTLPixelFormatBGR10_XR_sRGB"
      ; "MTLPixelFormatRG32Uint"; "MTLPixelFormatRG32Sint"
      ; "MTLPixelFormatRG32Float"; "MTLPixelFormatRGBA16Unorm"
      ; "MTLPixelFormatRGBA16Snorm"; "MTLPixelFormatRGBA16Uint"
      ; "MTLPixelFormatRGBA16Sint"; "MTLPixelFormatRGBA16Float"
      ; "MTLPixelFormatBGRA10_XR"; "MTLPixelFormatBGRA10_XR_sRGB"
      ; "MTLPixelFormatRGBA32Uint"; "MTLPixelFormatRGBA32Sint"
      ; "MTLPixelFormatRGBA32Float"
      ; "MTLPixelFormatBC1_RGBA"; "MTLPixelFormatBC1_RGBA_sRGB"
      ; "MTLPixelFormatBC2_RGBA"; "MTLPixelFormatBC2_RGBA_sRGB"
      ; "MTLPixelFormatBC3_RGBA"; "MTLPixelFormatBC3_RGBA_sRGB"
      ; "MTLPixelFormatBC4_RUnorm"; "MTLPixelFormatBC4_RSnorm"
      ; "MTLPixelFormatBC5_RGUnorm"; "MTLPixelFormatBC5_RGSnorm"
      ; "MTLPixelFormatBC6H_RGBFloat"; "MTLPixelFormatBC6H_RGBUfloat"
      ; "MTLPixelFormatBC7_RGBAUnorm"; "MTLPixelFormatBC7_RGBAUnorm_sRGB"
      ; "MTLPixelFormatEAC_R11Unorm"; "MTLPixelFormatEAC_R11Snorm"
      ; "MTLPixelFormatEAC_RG11Unorm"; "MTLPixelFormatEAC_RG11Snorm"
      ; "MTLPixelFormatEAC_RGBA8"; "MTLPixelFormatEAC_RGBA8_sRGB"
      ; "MTLPixelFormatETC2_RGB8"; "MTLPixelFormatETC2_RGB8_sRGB"
      ; "MTLPixelFormatETC2_RGB8A1"; "MTLPixelFormatETC2_RGB8A1_sRGB"
      ; "MTLPixelFormatASTC_4x4_sRGB"; "MTLPixelFormatASTC_5x4_sRGB"
      ; "MTLPixelFormatASTC_5x5_sRGB"; "MTLPixelFormatASTC_6x5_sRGB"
      ; "MTLPixelFormatASTC_6x6_sRGB"; "MTLPixelFormatASTC_8x5_sRGB"
      ; "MTLPixelFormatASTC_8x6_sRGB"; "MTLPixelFormatASTC_8x8_sRGB"
      ; "MTLPixelFormatASTC_10x5_sRGB"; "MTLPixelFormatASTC_10x6_sRGB"
      ; "MTLPixelFormatASTC_10x8_sRGB"; "MTLPixelFormatASTC_10x10_sRGB"
      ; "MTLPixelFormatASTC_12x10_sRGB"; "MTLPixelFormatASTC_12x12_sRGB"
      ; "MTLPixelFormatASTC_4x4_LDR"; "MTLPixelFormatASTC_5x4_LDR"
      ; "MTLPixelFormatASTC_5x5_LDR"; "MTLPixelFormatASTC_6x5_LDR"
      ; "MTLPixelFormatASTC_6x6_LDR"; "MTLPixelFormatASTC_8x5_LDR"
      ; "MTLPixelFormatASTC_8x6_LDR"; "MTLPixelFormatASTC_8x8_LDR"
      ; "MTLPixelFormatASTC_10x5_LDR"; "MTLPixelFormatASTC_10x6_LDR"
      ; "MTLPixelFormatASTC_10x8_LDR"; "MTLPixelFormatASTC_10x10_LDR"
      ; "MTLPixelFormatASTC_12x10_LDR"; "MTLPixelFormatASTC_12x12_LDR"
      ; "MTLPixelFormatASTC_4x4_HDR"; "MTLPixelFormatASTC_5x4_HDR"
      ; "MTLPixelFormatASTC_5x5_HDR"; "MTLPixelFormatASTC_6x5_HDR"
      ; "MTLPixelFormatASTC_6x6_HDR"; "MTLPixelFormatASTC_8x5_HDR"
      ; "MTLPixelFormatASTC_8x6_HDR"; "MTLPixelFormatASTC_8x8_HDR"
      ; "MTLPixelFormatASTC_10x5_HDR"; "MTLPixelFormatASTC_10x6_HDR"
      ; "MTLPixelFormatASTC_10x8_HDR"; "MTLPixelFormatASTC_10x10_HDR"
      ; "MTLPixelFormatASTC_12x10_HDR"; "MTLPixelFormatASTC_12x12_HDR"
      ; "MTLPixelFormatGBGR422"
      ; "MTLPixelFormatBGRG422"
      ; "MTLPixelFormatDepth16Unorm"; "MTLPixelFormatDepth32Float"
      ; "MTLPixelFormatStencil8"; "MTLPixelFormatDepth24Unorm_Stencil8"
      ; "MTLPixelFormatDepth32Float_Stencil8"; "MTLPixelFormatX32_Stencil8"
      ; "MTLPixelFormatX24_Stencil8"
      ]
  @ enum_cases "MTLPurgeableState"
      [ "MTLPurgeableStateKeepCurrent"; "MTLPurgeableStateNonVolatile"
      ; "MTLPurgeableStateVolatile"; "MTLPurgeableStateEmpty"
      ]
  @ enum_cases "MTLSamplerAddressMode"
      [ "MTLSamplerAddressModeClampToEdge"
      ; "MTLSamplerAddressModeMirrorClampToEdge"
      ; "MTLSamplerAddressModeRepeat"; "MTLSamplerAddressModeMirrorRepeat"
      ; "MTLSamplerAddressModeClampToZero"
      ; "MTLSamplerAddressModeClampToBorderColor"
      ]
  @ enum_cases "MTLSamplerBorderColor"
      [ "MTLSamplerBorderColorTransparentBlack"
      ; "MTLSamplerBorderColorOpaqueBlack"; "MTLSamplerBorderColorOpaqueWhite"
      ]
  @ enum_cases "MTLSamplerMinMagFilter"
      [ "MTLSamplerMinMagFilterNearest"; "MTLSamplerMinMagFilterLinear" ]
  @ enum_cases "MTLSamplerMipFilter"
      [ "MTLSamplerMipFilterNotMipmapped"; "MTLSamplerMipFilterNearest"
      ; "MTLSamplerMipFilterLinear"
      ]
  @ enum_cases "MTLTextureType"
      [ "MTLTextureType1D"; "MTLTextureType1DArray"; "MTLTextureType2D"
      ; "MTLTextureType2DArray"; "MTLTextureType2DMultisample"
      ; "MTLTextureTypeCube"; "MTLTextureTypeCubeArray"; "MTLTextureType3D"
      ; "MTLTextureType2DMultisampleArray"; "MTLTextureTypeTextureBuffer"
      ]
  @ enum_cases "MTLTextureUsage"
      [ "MTLTextureUsageUnknown"; "MTLTextureUsageShaderRead"
      ; "MTLTextureUsageShaderWrite"; "MTLTextureUsageRenderTarget"
      ; "MTLTextureUsagePixelFormatView"; "MTLTextureUsageShaderAtomic"
      ]
  @ enum_cases "MTLResourceOptions"
      [ "MTLResourceCPUCacheModeDefaultCache"
      ; "MTLResourceCPUCacheModeWriteCombined"
      ; "MTLResourceHazardTrackingModeDefault"
      ; "MTLResourceHazardTrackingModeUntracked"
      ; "MTLResourceHazardTrackingModeTracked"
      ]
  @ Binding_plan.bound_identifiers
  @ Binding_direct_plan.safe_device_identifiers
  @ Binding_argument_reflection_plan.inventory_ids

let bound_identifier_set = String_set.of_list bound_identifiers

let generated_public_enum_family_set =
  String_set.of_list
    (Binding_enum_plan.family_names
     @ List.map
         (fun (family : Binding_enum_implicit_plan.family) -> family.sdk_name)
         Binding_enum_implicit_plan.families)

let generated_public_enum_identifier identifier =
  let family_after prefix =
    if String.starts_with ~prefix identifier then
      let suffix =
        String.sub identifier (String.length prefix)
          (String.length identifier - String.length prefix)
      in
      let family =
        match String.index_opt suffix ':' with
        | None -> suffix
        | Some separator -> String.sub suffix 0 separator
      in
      String_set.mem family generated_public_enum_family_set
    else false
  in
  family_after "enum:" || family_after "typedef:"
  || family_after "enum-case:"

let availability_gated_identifier_set =
  String_set.of_list
    [ "method:-[MTL4Compiler newComputePipelineStateWithDescriptor:dynamicLinkingDescriptor:compilerTaskOptions:completionHandler:]"
    ]

let scope_excluded_identifier_set =
  String_set.of_list
    [ "variable:elements"; "variable:icbRange"; "variable:origin"
    ; "variable:packedFloat3"; "variable:packedQuaternion"; "variable:position"
    ; "variable:range"; "variable:region"; "variable:result"; "variable:size"
    ]

let name = function
  | Bound -> "bound"
  | Availability_gated -> "availability-gated"
  | Scope_excluded -> "scope-excluded"
  | Unreviewed -> "unreviewed"

let acceleration_owners =
  [ "MTL4AccelerationStructureBoundingBoxGeometryDescriptor"; "MTL4AccelerationStructureCurveGeometryDescriptor"
  ; "MTL4AccelerationStructureGeometryDescriptor"; "MTL4AccelerationStructureMotionBoundingBoxGeometryDescriptor"
  ; "MTL4AccelerationStructureMotionCurveGeometryDescriptor"; "MTL4AccelerationStructureMotionTriangleGeometryDescriptor"
  ; "MTL4AccelerationStructureTriangleGeometryDescriptor"; "MTL4IndirectInstanceAccelerationStructureDescriptor"
  ; "MTL4InstanceAccelerationStructureDescriptor"; "MTL4PrimitiveAccelerationStructureDescriptor"
  ; "MTLAccelerationStructure"; "MTLAccelerationStructureBoundingBoxGeometryDescriptor"
  ; "MTLAccelerationStructureCurveGeometryDescriptor"; "MTLAccelerationStructureDescriptor"
  ; "MTLAccelerationStructureGeometryDescriptor"; "MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor"
  ; "MTLAccelerationStructureMotionCurveGeometryDescriptor"; "MTLAccelerationStructureMotionTriangleGeometryDescriptor"
  ; "MTLAccelerationStructureTriangleGeometryDescriptor"; "MTLIndirectInstanceAccelerationStructureDescriptor"
  ; "MTLInstanceAccelerationStructureDescriptor"; "MTLMotionKeyframeData"
  ; "MTLPrimitiveAccelerationStructureDescriptor" ]

let acceleration_scalar_signature signature =
  List.exists (fun scalar ->
    signature = scalar || signature = "instance () -> " ^ scalar
    || signature = "instance (" ^ scalar ^ ") -> void")
    ([ "BOOL"; "float"; "NSUInteger" ] @ Binding_acceleration_scalar_plan.enums)

let acceleration_scalar_identifier ~header ~kind ~signature identifier =
  (header = "Metal/MTLAccelerationStructure.h"
   || header = "Metal/MTL4AccelerationStructure.h")
  && (kind = "property" || kind = "method")
  && acceleration_scalar_signature signature
  && List.exists (fun owner ->
       String.starts_with ~prefix:("property:" ^ owner ^ ":") identifier
       || String.starts_with ~prefix:("method:-[" ^ owner ^ " ") identifier)
       acceleration_owners

let acceleration_ownership_signature signature =
  List.exists (fun owned ->
    signature = owned || signature = "instance () -> " ^ owned
    || signature = "instance (" ^ owned ^ ") -> void")
    [ "id<MTLBuffer> _Nullable"; "NSString * _Nullable"; "MTLResourceID"
    ; "MTL4BufferRange" ]
  || String.starts_with ~prefix:"NSArray<" signature
  || String.starts_with ~prefix:"instance () -> NSArray<" signature
  || (String.starts_with ~prefix:"instance (NSArray<" signature
      && String.ends_with ~suffix:") -> void" signature)

let acceleration_ownership_identifier ~header ~kind ~signature identifier =
  (header = "Metal/MTLAccelerationStructure.h"
   || header = "Metal/MTL4AccelerationStructure.h")
  && (kind = "property" || kind = "method")
  && acceleration_ownership_signature signature
  && List.exists (fun owner ->
       String.starts_with ~prefix:("property:" ^ owner ^ ":") identifier
       || String.starts_with ~prefix:("method:-[" ^ owner ^ " ") identifier)
       acceleration_owners

let acceleration_operation_bound_identifiers =
  String_set.of_list
    [ "protocol:MTLFunctionHandle"
    ; "method:-[MTLFunctionHandle device]"
    ; "method:-[MTLFunctionHandle functionType]"
    ; "method:-[MTLFunctionHandle gpuResourceID]"
    ; "method:-[MTLFunctionHandle name]"
    ; "property:MTLFunctionHandle:device"
    ; "property:MTLFunctionHandle:functionType"
    ; "property:MTLFunctionHandle:gpuResourceID"
    ; "property:MTLFunctionHandle:name"
    ; "method:-[MTLComputePipelineState functionHandleWithFunction:]"
    ; "class:MTLVisibleFunctionTableDescriptor"
    ; "method:+[MTLVisibleFunctionTableDescriptor visibleFunctionTableDescriptor]"
    ; "property:MTLVisibleFunctionTableDescriptor:functionCount"
    ; "method:-[MTLVisibleFunctionTableDescriptor functionCount]"
    ; "method:-[MTLVisibleFunctionTableDescriptor setFunctionCount:]"
    ; "protocol:MTLVisibleFunctionTable"
    ; "method:-[MTLComputePipelineState newVisibleFunctionTableWithDescriptor:]"
    ; "property:MTLVisibleFunctionTable:gpuResourceID"
    ; "method:-[MTLVisibleFunctionTable gpuResourceID]"
    ; "method:-[MTLVisibleFunctionTable setFunction:atIndex:]"
    ; "class:MTLIntersectionFunctionTableDescriptor"
    ; "method:+[MTLIntersectionFunctionTableDescriptor intersectionFunctionTableDescriptor]"
    ; "property:MTLIntersectionFunctionTableDescriptor:functionCount"
    ; "method:-[MTLIntersectionFunctionTableDescriptor functionCount]"
    ; "method:-[MTLIntersectionFunctionTableDescriptor setFunctionCount:]"
    ; "protocol:MTLIntersectionFunctionTable"
    ; "method:-[MTLComputePipelineState newIntersectionFunctionTableWithDescriptor:]"
    ; "property:MTLIntersectionFunctionTable:gpuResourceID"
    ; "method:-[MTLIntersectionFunctionTable gpuResourceID]"
    ; "method:-[MTLIntersectionFunctionTable setFunction:atIndex:]"
    ; "method:-[MTLIntersectionFunctionTable setBuffer:offset:atIndex:]"
    ; "method:-[MTLIntersectionFunctionTable setVisibleFunctionTable:atBufferIndex:]" ]

let library_existing_safe18 =
  [ "method:-[MTLAttribute attributeIndex]"; "method:-[MTLAttribute attributeType]"
  ; "method:-[MTLAttribute isActive]"; "method:-[MTLAttribute isPatchControlPointData]"
  ; "method:-[MTLAttribute isPatchData]"; "method:-[MTLAttribute name]"
  ; "property:MTLAttribute:active"; "property:MTLAttribute:attributeIndex"
  ; "property:MTLAttribute:attributeType"; "property:MTLAttribute:name"
  ; "property:MTLAttribute:patchControlPointData"; "property:MTLAttribute:patchData"
  ; "method:-[MTLFunction newArgumentEncoderWithBufferIndex:]"
  ; "method:-[MTLFunction stageInputAttributes]"; "method:-[MTLFunction vertexAttributes]"
  ; "property:MTLFunction:stageInputAttributes"; "property:MTLFunction:vertexAttributes"
  ; "method:-[MTLLibrary newFunctionWithDescriptor:error:]" ]

let blit_safe15 =
  [ "method:-[MTLBlitCommandEncoder copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:options:]"
  ; "method:-[MTLBlitCommandEncoder fillBuffer:range:value:]"
  ; "method:-[MTLBlitCommandEncoder generateMipmapsForTexture:]"
  ; "method:-[MTLBlitCommandEncoder updateFence:]"
  ; "method:-[MTLBlitCommandEncoder waitForFence:]" ]
  @ [ "method:-[MTLBlitCommandEncoder copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:]"
    ; "method:-[MTLBlitCommandEncoder copyFromTexture:toTexture:]"
    ; "method:-[MTLBlitCommandEncoder optimizeContentsForCPUAccess:]"
    ; "method:-[MTLBlitCommandEncoder optimizeContentsForCPUAccess:slice:level:]"
    ; "method:-[MTLBlitCommandEncoder optimizeContentsForGPUAccess:]"
    ; "method:-[MTLBlitCommandEncoder optimizeContentsForGPUAccess:slice:level:]"
    ; "method:-[MTLBlitCommandEncoder optimizeIndirectCommandBuffer:withRange:]"
    ; "method:-[MTLBlitCommandEncoder resetCommandsInBuffer:withRange:]"
    ; "method:-[MTLBlitCommandEncoder synchronizeResource:]"
    ; "method:-[MTLBlitCommandEncoder synchronizeTexture:slice:level:]" ]

let io_compressor_safe5 =
  [ "function:MTLIOCompressionContextAppendData"
  ; "function:MTLIOCompressionContextDefaultChunkSize"
  ; "function:MTLIOCreateCompressionContext"
  ; "function:MTLIOFlushAndDestroyCompressionContext"
  ; "typedef:MTLIOCompressionContext" ]

let render_pipeline93_safe11 =
  [ "class:MTLMeshRenderPipelineDescriptor"
  ; "class:MTLRenderPipelineColorAttachmentDescriptor"
  ; "class:MTLRenderPipelineColorAttachmentDescriptorArray"
  ; "class:MTLTileRenderPipelineDescriptor"
  ; "method:-[MTLMeshRenderPipelineDescriptor reset]"
  ; "method:-[MTLRenderPipelineColorAttachmentDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLRenderPipelineColorAttachmentDescriptorArray setObject:atIndexedSubscript:]"
  ; "method:-[MTLRenderPipelineDescriptor label]"
  ; "method:-[MTLRenderPipelineDescriptor setLabel:]"
  ; "method:-[MTLTileRenderPipelineDescriptor reset]"
  ; "property:MTLRenderPipelineDescriptor:label" ]

let render_pipeline93_mesh_graph12 =
  [ "method:-[MTLMeshRenderPipelineDescriptor binaryArchives]"
  ; "method:-[MTLMeshRenderPipelineDescriptor setBinaryArchives:]"
  ; "property:MTLMeshRenderPipelineDescriptor:binaryArchives"
  ; "method:-[MTLMeshRenderPipelineDescriptor objectFunction]"
  ; "method:-[MTLMeshRenderPipelineDescriptor setObjectFunction:]"
  ; "property:MTLMeshRenderPipelineDescriptor:objectFunction"
  ; "method:-[MTLMeshRenderPipelineDescriptor meshFunction]"
  ; "method:-[MTLMeshRenderPipelineDescriptor setMeshFunction:]"
  ; "property:MTLMeshRenderPipelineDescriptor:meshFunction"
  ; "method:-[MTLMeshRenderPipelineDescriptor fragmentFunction]"
  ; "method:-[MTLMeshRenderPipelineDescriptor setFragmentFunction:]"
  ; "property:MTLMeshRenderPipelineDescriptor:fragmentFunction" ]

let render_pipeline93_tile_graph9 =
  [ "method:-[MTLTileRenderPipelineDescriptor binaryArchives]"
  ; "method:-[MTLTileRenderPipelineDescriptor setBinaryArchives:]"
  ; "property:MTLTileRenderPipelineDescriptor:binaryArchives"
  ; "method:-[MTLTileRenderPipelineDescriptor preloadedLibraries]"
  ; "method:-[MTLTileRenderPipelineDescriptor setPreloadedLibraries:]"
  ; "property:MTLTileRenderPipelineDescriptor:preloadedLibraries"
  ; "method:-[MTLTileRenderPipelineDescriptor tileFunction]"
  ; "method:-[MTLTileRenderPipelineDescriptor setTileFunction:]"
  ; "property:MTLTileRenderPipelineDescriptor:tileFunction" ]

let render_pipeline93_array_snapshots18 =
  [ "method:-[MTLRenderPipelineDescriptor colorAttachments]"
  ; "property:MTLRenderPipelineDescriptor:colorAttachments"
  ; "method:-[MTLRenderPipelineDescriptor fragmentBuffers]"
  ; "property:MTLRenderPipelineDescriptor:fragmentBuffers"
  ; "method:-[MTLRenderPipelineDescriptor vertexBuffers]"
  ; "property:MTLRenderPipelineDescriptor:vertexBuffers"
  ; "method:-[MTLMeshRenderPipelineDescriptor colorAttachments]"
  ; "property:MTLMeshRenderPipelineDescriptor:colorAttachments"
  ; "method:-[MTLMeshRenderPipelineDescriptor fragmentBuffers]"
  ; "property:MTLMeshRenderPipelineDescriptor:fragmentBuffers"
  ; "method:-[MTLMeshRenderPipelineDescriptor meshBuffers]"
  ; "property:MTLMeshRenderPipelineDescriptor:meshBuffers"
  ; "method:-[MTLMeshRenderPipelineDescriptor objectBuffers]"
  ; "property:MTLMeshRenderPipelineDescriptor:objectBuffers"
  ; "method:-[MTLTileRenderPipelineDescriptor colorAttachments]"
  ; "property:MTLTileRenderPipelineDescriptor:colorAttachments"
  ; "method:-[MTLTileRenderPipelineDescriptor tileBuffers]"
  ; "property:MTLTileRenderPipelineDescriptor:tileBuffers" ]

let render_pipeline93_required_thread_sizes4 =
  [ "method:-[MTLRenderPipelineState requiredThreadsPerMeshThreadgroup]"
  ; "property:MTLRenderPipelineState:requiredThreadsPerMeshThreadgroup"
  ; "method:-[MTLRenderPipelineState requiredThreadsPerObjectThreadgroup]"
  ; "property:MTLRenderPipelineState:requiredThreadsPerObjectThreadgroup" ]

let render_pipeline93_linked_graph12 =
  [ "method:-[MTLMeshRenderPipelineDescriptor objectLinkedFunctions]"
  ; "method:-[MTLMeshRenderPipelineDescriptor setObjectLinkedFunctions:]"
  ; "property:MTLMeshRenderPipelineDescriptor:objectLinkedFunctions"
  ; "method:-[MTLMeshRenderPipelineDescriptor meshLinkedFunctions]"
  ; "method:-[MTLMeshRenderPipelineDescriptor setMeshLinkedFunctions:]"
  ; "property:MTLMeshRenderPipelineDescriptor:meshLinkedFunctions"
  ; "method:-[MTLMeshRenderPipelineDescriptor fragmentLinkedFunctions]"
  ; "method:-[MTLMeshRenderPipelineDescriptor setFragmentLinkedFunctions:]"
  ; "property:MTLMeshRenderPipelineDescriptor:fragmentLinkedFunctions"
  ; "method:-[MTLTileRenderPipelineDescriptor linkedFunctions]"
  ; "method:-[MTLTileRenderPipelineDescriptor setLinkedFunctions:]"
  ; "property:MTLTileRenderPipelineDescriptor:linkedFunctions" ]

let render_pipeline93_functions_descriptor10 =
  [ "class:MTLRenderPipelineFunctionsDescriptor"
  ; "method:-[MTLRenderPipelineFunctionsDescriptor vertexAdditionalBinaryFunctions]"
  ; "method:-[MTLRenderPipelineFunctionsDescriptor setVertexAdditionalBinaryFunctions:]"
  ; "property:MTLRenderPipelineFunctionsDescriptor:vertexAdditionalBinaryFunctions"
  ; "method:-[MTLRenderPipelineFunctionsDescriptor fragmentAdditionalBinaryFunctions]"
  ; "method:-[MTLRenderPipelineFunctionsDescriptor setFragmentAdditionalBinaryFunctions:]"
  ; "property:MTLRenderPipelineFunctionsDescriptor:fragmentAdditionalBinaryFunctions"
  ; "method:-[MTLRenderPipelineFunctionsDescriptor tileAdditionalBinaryFunctions]"
  ; "method:-[MTLRenderPipelineFunctionsDescriptor setTileAdditionalBinaryFunctions:]"
  ; "property:MTLRenderPipelineFunctionsDescriptor:tileAdditionalBinaryFunctions" ]

let render_pipeline93_function_lookup2 =
  [ "method:-[MTLRenderPipelineState functionHandleWithFunction:stage:]"
  ; "method:-[MTLRenderPipelineState functionHandleWithName:stage:]" ]

let render_pipeline93_table_specialization3 =
  [ "method:-[MTLRenderPipelineState newVisibleFunctionTableWithDescriptor:stage:]"
  ; "method:-[MTLRenderPipelineState newIntersectionFunctionTableWithDescriptor:stage:]"
  ; "method:-[MTLRenderPipelineState newRenderPipelineDescriptorForSpecialization]" ]

let render_pipeline93_relink2 =
  [ "method:-[MTLRenderPipelineState newRenderPipelineStateWithAdditionalBinaryFunctions:error:]"
  ; "method:-[MTLRenderPipelineState newRenderPipelineStateWithBinaryFunctions:error:]" ]

let render_pipeline93_vertex_descriptor3 =
  [ "method:-[MTLRenderPipelineDescriptor vertexDescriptor]"
  ; "method:-[MTLRenderPipelineDescriptor setVertexDescriptor:]"
  ; "property:MTLRenderPipelineDescriptor:vertexDescriptor" ]

let render_pipeline93_reflection6 =
  [ "method:-[MTLRenderPipelineReflection vertexArguments]"
  ; "property:MTLRenderPipelineReflection:vertexArguments"
  ; "method:-[MTLRenderPipelineReflection fragmentArguments]"
  ; "property:MTLRenderPipelineReflection:fragmentArguments"
  ; "method:-[MTLRenderPipelineReflection tileArguments]"
  ; "property:MTLRenderPipelineReflection:tileArguments" ]

let render_pipeline93_binary_lookup1 =
  [ "method:-[MTLRenderPipelineState functionHandleWithBinaryFunction:stage:]" ]

let linked_functions_safe9 =
  [ "method:-[MTLLinkedFunctions binaryFunctions]"; "method:-[MTLLinkedFunctions groups]"
  ; "method:-[MTLLinkedFunctions privateFunctions]"; "method:-[MTLLinkedFunctions setBinaryFunctions:]"
  ; "method:-[MTLLinkedFunctions setGroups:]"; "method:-[MTLLinkedFunctions setPrivateFunctions:]"
  ; "property:MTLLinkedFunctions:binaryFunctions"; "property:MTLLinkedFunctions:groups"
  ; "property:MTLLinkedFunctions:privateFunctions" ]

let stage_input_output_safe7 =
  [ "method:-[MTLAttributeDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLAttributeDescriptorArray setObject:atIndexedSubscript:]"
  ; "method:-[MTLStageInputOutputDescriptor attributes]"
  ; "method:-[MTLStageInputOutputDescriptor layouts]"
  ; "method:-[MTLStageInputOutputDescriptor reset]"
  ; "property:MTLStageInputOutputDescriptor:attributes"
  ; "property:MTLStageInputOutputDescriptor:layouts" ]

let blit_pass_safe8 =
  [ "method:+[MTLBlitPassDescriptor blitPassDescriptor]"
  ; "method:-[MTLBlitPassDescriptor sampleBufferAttachments]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptor sampleBuffer]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptor setSampleBuffer:]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptorArray setObject:atIndexedSubscript:]"
  ; "property:MTLBlitPassDescriptor:sampleBufferAttachments"
  ; "property:MTLBlitPassSampleBufferAttachmentDescriptor:sampleBuffer" ]

let counters_safe22 =
  [ "method:-[MTLCounter name]";"method:-[MTLCounterSampleBuffer device]";"method:-[MTLCounterSampleBuffer label]";"method:-[MTLCounterSampleBuffer resolveCounterRange:]";"method:-[MTLCounterSampleBuffer sampleCount]";"method:-[MTLCounterSampleBufferDescriptor counterSet]";"method:-[MTLCounterSampleBufferDescriptor label]";"method:-[MTLCounterSampleBufferDescriptor setCounterSet:]";"method:-[MTLCounterSampleBufferDescriptor setLabel:]";"method:-[MTLCounterSet counters]";"method:-[MTLCounterSet name]";"property:MTLCounter:name";"property:MTLCounterSampleBuffer:device";"property:MTLCounterSampleBuffer:label";"property:MTLCounterSampleBuffer:sampleCount";"property:MTLCounterSampleBufferDescriptor:counterSet";"property:MTLCounterSampleBufferDescriptor:label";"property:MTLCounterSet:counters";"property:MTLCounterSet:name";"protocol:MTLCounter";"protocol:MTLCounterSampleBuffer";"protocol:MTLCounterSet" ]

let parallel_render_safe7 =
  [ "method:-[MTLParallelRenderCommandEncoder renderCommandEncoder]"
  ; "method:-[MTLParallelRenderCommandEncoder setColorStoreAction:atIndex:]"
  ; "method:-[MTLParallelRenderCommandEncoder setColorStoreActionOptions:atIndex:]"
  ; "method:-[MTLParallelRenderCommandEncoder setDepthStoreAction:]"
  ; "method:-[MTLParallelRenderCommandEncoder setDepthStoreActionOptions:]"
  ; "method:-[MTLParallelRenderCommandEncoder setStencilStoreAction:]"
  ; "method:-[MTLParallelRenderCommandEncoder setStencilStoreActionOptions:]" ]

let binary_archive_safe2 =
  [ "method:-[MTLBinaryArchive addFunctionWithDescriptor:library:error:]"
  ; "method:-[MTLBinaryArchive addRenderPipelineFunctionsWithDescriptor:error:]" ]

let log_state_safe7 =
  [ "method:-[MTLLogState addLogHandler:]"
  ; "method:-[MTLLogStateDescriptor bufferSize]"
  ; "method:-[MTLLogStateDescriptor level]"
  ; "method:-[MTLLogStateDescriptor setBufferSize:]"
  ; "method:-[MTLLogStateDescriptor setLevel:]"
  ; "property:MTLLogStateDescriptor:bufferSize"
  ; "property:MTLLogStateDescriptor:level" ]

let function_constant_values_safe3 =
  [ "method:-[MTLFunctionConstantValues reset]"
  ; "method:-[MTLFunctionConstantValues setConstantValue:type:atIndex:]"
  ; "method:-[MTLFunctionConstantValues setConstantValues:type:withRange:]" ]

let function_descriptor_safe4 = Binding_function_descriptor4_safe_package.ids
let fence_safe6 = Binding_fence6_safe_package.ids
let indirect_command_buffer_safe4 = Binding_indirect_command_buffer4_safe_package.ids
let argument_safe8 = Binding_argument8_safe_package.ids
let library_safe8 = Binding_library8_safe_package.ids
let metal4_counters_safe2 = Binding_metal4_counters2_safe_package.ids
let render_encoder_safe33 = Binding_render_encoder33_safe_package.ids
let indirect_command_safe14 = Binding_indirect_command14_safe_package.ids
let metal4_argument_table_safe1 =
  Binding_metal4_argument_table_safe_package.callable_ids
let metal4_render_pipeline_reset_safe2 =
  Binding_metal4_render_pipeline_safe_package.callable_ids
let metal4_compute_pipeline_reset_safe1 =
  Binding_metal4_compute_pipeline_safe_package.callable_ids
let metal4_command_encoder_wait_safe1 =
  Binding_metal4_command_encoder_safe_package.callable_ids
let device_residual_safe11 = Binding_device_residual_safe_package.already_safe_ids
let device_library_safe5 = Binding_device_library5_safe_package.ids

let classify ~unavailable ~identifier ~header ~kind ~signature =
  if unavailable then
    Scope_excluded, "Clang marks this declaration unavailable for macOS."
  else if String_set.mem identifier scope_excluded_identifier_set then
    Scope_excluded, "Header-local inline constructor variable; not an exported Metal SDK declaration."
  else if String_set.mem identifier availability_gated_identifier_set then
    ( Availability_gated
    , "Implemented with an Apple9/M3+ capability gate; the Apple7/M1 Metal 4 driver crashes while serializing this asynchronous dynamic-link request." )
  else if String_set.mem identifier bound_identifier_set then
    Bound, "Implemented by the ownership-aware prismel.metal safe layer."
  else if List.mem identifier metal4_argument_table_safe1 then
    Bound,
      "Implemented by the closed ID-bearing resource variant with checked live/device/index/nonzero validation, atomic replacement retention, command lifetime, and real Metal 4 texture-table conformance."
  else if List.mem identifier metal4_render_pipeline_reset_safe2 then
    Bound,
      "Implemented by owned Metal 4 render-pipeline attachment descriptors with exact eight-entry copy snapshots, idempotent default restoration, destroyed/availability rejection, and repeated native conformance."
  else if List.mem identifier metal4_compute_pipeline_reset_safe1 then
    Bound,
      "Implemented by a distinct owned Metal 4 compute descriptor with typed native reset, native-first child replacement, exact default checks, idempotence, and destroyed/availability conformance."
  else if List.mem identifier metal4_command_encoder_wait_safe1 then
    Bound,
      "Implemented by the active Metal 4 encoder path with live same-device fence and nonempty known-stage validation, native-first command retention, and real producer/consumer conformance."
  else if List.mem identifier device_residual_safe11 then
    Bound,
      "Implemented by existing owned Device constructor/query paths with exact selector evidence, same-device retention, capability rejection, and focused native/public conformance."
  else if List.mem identifier device_library_safe5 then
    Bound,
      "Implemented by exact synchronous Device library constructors with copied byte input, checked absolute paths and bundle/descriptor graphs, owned device retention, and execute-or-error conformance."
  else if acceleration_scalar_identifier ~header ~kind ~signature identifier then
    Bound,
      "Implemented by generated immutable acceleration-structure descriptor values with native execute-or-capability-reject conformance."
  else if acceleration_ownership_identifier ~header ~kind ~signature identifier then
    Bound,
      "Implemented by safe owned acceleration structures, immutable buffer-backed descriptors, checked native materialization, completion retention, and execute-or-capability-reject conformance."
  else if String_set.mem identifier acceleration_operation_bound_identifiers then
    Bound,
      "Implemented by owned acceleration/function-table handles, checked capacity/index/device validation, retained bindings, typed direct selectors, and execute-or-capability-reject conformance."
  else if List.exists (fun (item : Binding_pure_tail_plan.item) -> String.equal item.id identifier) Binding_pure_tail_plan.items then
    Bound,
      "Implemented by the generated pure-value tail surface with exact typed round trips and native enum/layout/constructor ABI assertions."
  else if generated_public_enum_identifier identifier then
    Bound, "Implemented by the generated, typed prismel.metal pure-value enum surface."
  else if Binding_value_record_evidence.is_bound_identifier identifier then
    Bound, "Implemented by the generated, typed prismel.metal fixed-layout value-record surface."
  else if Binding_global_string_evidence.is_bound_identifier identifier then
    Bound, "Implemented by the generated prismel.metal copied global-string surface."
  else if Binding_descriptor_property_evidence.is_bound_identifier identifier then
    Bound,
      "Implemented by generated immutable descriptor records with checked native materialization and exact property round-trip conformance."
  else if
    List.mem identifier Binding_render_pipeline_scalar_evidence.promotion_ids
  then
    Bound,
      "Implemented by generated immutable render-pipeline descriptor records with checked native materialization, exact property round trips, and real pipeline conformance."
  else if Binding_render_encoder_promotion.is_bound_identifier identifier then
    Bound,
      "Implemented by the owned classic render encoder, direct typed native calls, checked state/resource validation, completion retention, and real M1 conformance."
  else if List.mem identifier Binding_presentation_public_audit.safe_reachable then
    Bound,
      "Implemented by owned layer/drawable/render-pass values, checked presentation state and callback lifetimes, and real M1 drawable/readback conformance."
  else if List.mem identifier Binding_presentation_safe_handoff.promotable_ids then
    Bound,
      "Implemented by the Presentation81 safe closure with checked native snapshots, owned attachment/layer/drawable/rasterization/sample graphs, command state validation, completion retention, and real M1 conformance."
  else if List.mem identifier Binding_tensor_safe_handoff.safe47_ids then
    Bound,
      "Implemented by the Tensor47 safe closure with owned extents/descriptor/resource graphs, checked ranges and metadata, device/buffer retention, and real M1 conformance."
  else if List.mem identifier Binding_argument_encoder_handoff.callable_ids then
    Bound,
      "Implemented by the ArgumentEncoder32 safe closure with exact device/kind/range validation, atomic array rejection, nested ownership, bounded replacement retention, and real M1 conformance."
  else if List.mem identifier Binding_rasterization_rate_safe_handoff.callable_ids then
    Bound,
      "Implemented by the RasterizationRate50 safe closure with owned layer/descriptor/map graphs, capability and device checks, exact coordinate/range validation, and M1 conformance."
  else if List.mem identifier Binding_function_stitching_handoff.callable_ids then
    Bound,
      "Implemented by the FunctionStitching36 safe node/graph/descriptor closure with cycle and device validation, owned edges, atomic replacement, and real native conformance."
  else if List.mem identifier library_existing_safe18 then
    Bound,
      "Implemented by retained Function/Shader_attribute handles with checked library ownership, typed attribute metadata, argument-encoder construction, and real shader conformance."
  else if List.mem identifier Binding_library_header_handoff.callable_ids then
    Bound,
      "Implemented by the MTLLibrary34 safe closure with immutable compile options, retained reflection and argument-encoder graphs, checked synchronous construction, and cancellable exactly-once asynchronous tasks."
  else if List.mem identifier blit_safe15 then
    Bound,
      "Implemented by the owned Blit_encoder safe surface with checked ranges, device identity, resource retention, and native command execution."
  else if List.mem identifier Binding_blit_command_tail_handoff.callable_ids then
    Bound,
      "Implemented by the complete BlitCommand25 safe closure with checked copy layouts, tensor/indirect/counter ownership, access-counter capability handling, and completion retention."
  else if List.mem identifier Binding_capture_manager_tail_handoff.callable_ids then
    Bound,
      "Implemented by the CaptureManager19 safe closure with atomic descriptor replacement, checked URL/destination and source kinds, retained scope/default/source graphs, and serialized capture lifecycle rollback."
  else if List.mem identifier Binding_compute_pass_tail_handoff.callable_ids then
    Bound,
      "Implemented by the ComputePass17 safe closure with checked dispatch and sample ranges, exact native snapshots, same-device attachment validation, and retained counter-sample-buffer graphs."
  else if List.mem identifier Binding_acceleration_command32_native_closure.ids then
    Bound,
      "Implemented by the AccelerationCommand32 safe closure with owned pass/sample graphs, checked build/refit/copy/fence/resource/counter state, capability gates, and command-completion retention."
  else if List.mem identifier Binding_acceleration_structure23_safe_closure.ids then
    Bound,
      "Implemented by the AccelerationStructure23 safe descriptor variants with checked nested geometry/buffer ownership, same-device range/stride/count validation, and real constructor conformance."
  else if List.mem identifier Binding_function_log_tail_handoff.callable_ids then
    Bound,
      "Implemented by copied FunctionLog16 snapshots after command completion with exact nullable log/location/function graphs, typed validation logs, UTF-8 source identity, and checked source positions."
  else if List.mem identifier Binding_function_log2_protocol_safe_closure.promotable_ids then
    Bound,
      "Represented by immutable Function_log diagnostic snapshots copied from guarded typed enumeration of a real command-owned MTLLogContainer, including nullable function, location, URL, name, and encoder-label fields."
  else if List.mem identifier Binding_command_queue_tail_handoff.callable_ids then
    Bound,
      "Implemented by the CommandQueue14 safe closure with checked descriptor limits and log-state ownership, copied queue identity, capture-state validation, and retained classic command buffers."
  else if List.mem identifier Binding_command_encoder9_closure.ids then
    Bound,
      "Implemented by the CommandEncoder9 shared safe token with retained command parent, exact device/label snapshots, balanced debug depth, known nonzero stage masks, end-state rejection, and real 256-command conformance."
  else if List.mem identifier Binding_pipeline4_buffer_descriptor_safe_closure.promotable_ids then
    Bound,
      "Implemented by immutable PipelineBufferDescriptor values and checked copied array assignment/reset with fixed-slot validation in compute and render pipeline descriptors plus real compute readback."
  else if List.mem identifier Binding_capture_scope_tail_handoff.callable_ids then
    Bound,
      "Implemented by the CaptureScope11 safe lifecycle with retained queue/device identity, copied nullable labels, balanced begin/end state, Metal4 availability, and parent ownership."
  else if List.mem identifier render_pipeline93_safe11
          || List.mem identifier render_pipeline93_mesh_graph12
          || List.mem identifier render_pipeline93_tile_graph9
          || List.mem identifier render_pipeline93_array_snapshots18
          || List.mem identifier render_pipeline93_required_thread_sizes4
          || List.mem identifier render_pipeline93_linked_graph12
          || List.mem identifier render_pipeline93_functions_descriptor10
          || List.mem identifier render_pipeline93_function_lookup2
          || List.mem identifier render_pipeline93_table_specialization3
          || List.mem identifier render_pipeline93_relink2
          || List.mem identifier render_pipeline93_vertex_descriptor3
          || List.mem identifier render_pipeline93_reflection6
          || List.mem identifier render_pipeline93_binary_lookup1 then
    Bound,
      "Implemented by the RenderPipeline93 safe descriptor foundation with typed classes, copied labels, exact reset defaults, checked color-array indexing, and retained attachment ownership."
  else if List.mem identifier Binding_compute_encoder35_safe_closure.callable_ids then
    Bound,
      "Implemented by the ComputeEncoder safe35 closure with checked indices, ranges, strides, cardinality, capabilities and device identity plus command-completion retention."
  else if List.mem identifier Binding_compute_pipeline11_safe_closure.promotable_ids then
    Bound,
      "Implemented by the ComputePipeline11 safe descriptor/reflection/relink closure with owned library inputs, immutable snapshots, nullable named handles, capability-gated binary relink, and real dispatch/readback."
  else if List.mem identifier linked_functions_safe9 then
    Bound,
      "Implemented by the LinkedFunctions safe9 retained nullable arrays and deterministic named-group graph with atomic same-device validation."
  else if List.mem identifier stage_input_output_safe7 then
    Bound,
      "Implemented by the StageInputOutputDescriptor safe7 canonical descriptor graph with retained attribute/layout children, checked indices and parent lifetime validation."
  else if List.mem identifier blit_pass_safe8 then
    Bound,
      "Implemented by the BlitPass safe8 descriptor graph with retained sample buffers, checked device/sample ranges, exact default semantics, and parent-child lifetime validation."
  else if List.mem identifier counters_safe22 then
    Bound,
      "Implemented by the Counters22 safe metadata/descriptor/sample graph with copied names, checked labels/devices/ranges, explicit sampling-point capability, and execute-or-Unsupported conformance."
  else if List.mem identifier parallel_render_safe7 then
    Bound,
      "Implemented by the ParallelRender7 safe parent/child graph with retained pass attachments, checked store writes, exact child ordering, completion ownership, and 256-command native/safe conformance."
  else if List.mem identifier binary_archive_safe2 then
    Bound,
      "Implemented by configured BinaryArchive function/render descriptors with native-first mutation, same-device live validation, retained library/function ownership, NSError propagation, and real serialize/reopen persistence."
  else if List.mem identifier log_state_safe7 then
    Bound,
      "Implemented by the LogState safe7 descriptor and persistent handler API with checked snapshots, rooted multi-shot callbacks, draining cancellation, and owned cleanup."
  else if List.mem identifier function_constant_values_safe3 then
    Bound,
      "Implemented by the FunctionConstantValues safe3 typed byte API with exact width/range/cardinality validation, immutable caller-byte snapshots, reset semantics, and real GPU specialization conformance."
  else if List.mem identifier function_descriptor_safe4 then
    Bound,
      "Implemented by the FunctionDescriptor safe4 owned archive-list and intersection-descriptor API with copied collection semantics, same-device/live checks, parent retention, nil reset, and real function creation conformance."
  else if List.mem identifier fence_safe6 then
    Bound,
      "Implemented by the Fence safe6 owned Device constructor and copied nullable-label/device API with live/same-device encoder validation, command-completion retention, and 256-iteration byte-ordering conformance."
  else if List.mem identifier indirect_command_buffer_safe4 then
    Bound,
      "Implemented by the IndirectCommandBuffer safe4 owned indexed-command graph with exact bounds/type validation, opaque GPU resource identity, parent retention, indirect-capable pipelines, and real framebuffer conformance."
  else if List.mem identifier argument_safe8 then
    Bound,
      "Implemented by the immutable Argument8 reflection tree with copied argument, struct/member, pointer and array metadata, nullable nested variants, bounded traversal/unwind, and macOS-26-gated tensor reflection provenance."
  else if List.mem identifier library_safe8 then
    Bound,
      "Implemented by the Library8 immutable attribute/function-reflection snapshots and private autoreleasing ABI conventions, with bounded exactly-once cancellable tasks, exception capture, and real compute/render callback conformance."
  else if List.mem identifier metal4_counters_safe2 then
    Bound,
      "Implemented by the immutable Metal 4 counter-heap descriptor and owned heap graph, with copied labels, checked ranges, explicit invalidation/resolution, device lifetime retention, and real timestamp-heap conformance."
  else if List.mem identifier render_encoder_safe33 then
    Bound,
      "Implemented by the owned render-command encoder surface with checked buffer/sampler arrays and offsets, retained resources and counter samples, validated patch/mesh/tile/indirect draw layouts, command-state rejection, and real framebuffer conformance."
  else if List.mem identifier indirect_command_safe14 then
    Bound,
      "Implemented by owned indirect compute/render commands with descriptor-capacity and capability gates, checked device/range/stride/index/topology validation, retained pipelines and buffers, reset teardown, and real indirect-command conformance."
  else if List.mem identifier Binding_render_pass24_safe_closure.promotable_ids then
    Bound,
      "Implemented by the owned classic RenderPass24 graph with copied color/sample descriptors, nullable resolve texture and counter buffers, checked device/range/default reset semantics, completion retention, and real render/resolve conformance."
  else if List.mem identifier Binding_command_buffer19_safe_closure.promotable_ids then
    Bound,
      "Implemented by the CommandBuffer19 safe descriptor/callback closure with retained log-state and resources, exact-once completion, queue ownership, and error-only EncoderInfo snapshots."
  else if List.mem identifier io_compressor_safe5 then
    Bound,
      "Implemented by the owned IO.Compressor lifecycle with copied configuration, checked byte ranges, synchronous consumption, exact finalization state, and real compressed-output conformance."
  else if List.mem identifier Binding_resource_safe_reachability.promotable_ids then
    Bound,
      "Implemented by the Resource100 safe surface with checked descriptor ranges, exact handle kinds, parent ownership, same-device validation, completion retention, and M1 conformance."
  else if
    List.mem identifier
      Binding_render_command_safe_reachability.promotable_ids
  then
    Bound,
      "Implemented by the classic render-command safe surface with checked state and resource validation, completion retention, and M1 conformance."
  else if
    List.mem identifier
      Binding_pipeline_state_safe_reachability.promotable_ids
  then
    Bound,
      "Implemented by safe compute/render pipeline state queries with destroyed-handle and argument validation plus exact native conformance."
  else if List.mem identifier Binding_pipeline_expanded_reachability.promotable_ids then
    Bound,
      "Implemented by retained compute/render pipeline descriptors, exact scalar round trips, checked synchronous compilation, and native conformance."
  else if List.mem identifier Binding_shader_safe_reachability.promotable_ids then
    Bound,
      "Implemented by safe shader metadata and scalar descriptor operations with checked ownership, exact round trips, and native conformance."
  else if List.mem identifier Binding_mesh_tile_safe_reachability.promotable_ids then
    Bound,
      "Implemented by safe mesh/tile contained descriptor values with exact scalar round trips and native conformance."
  else if List.mem identifier Binding_mesh_tile_compile_reachability.promotable_ids then
    Bound,
      "Implemented by safe synchronous mesh/tile compilation with descriptor ownership, validation, reflection handling, and native conformance."
  else if List.mem identifier Binding_command_support_safe_reachability.promotable_ids then
    Bound,
      "Implemented by safe indirect-command, capture-state, and event operations with validation, ownership, and native conformance."
  else if List.mem identifier Binding_io_safe_reachability.promotable_ids then
    Bound,
      "Implemented by the retained safe Metal IO queue/file/command chain and contained queue descriptor materialization with native byte-exact conformance."
  else if List.mem identifier Binding_io_command_queue17_safe_reachability.promotable_ids then
    Bound,
      "Implemented by safe IO queue/file/command controls with copied labels, state/range/device validation, retained resources, and real native IO conformance."
  else if List.mem identifier Binding_io_command_queue7_safe_reachability.promotable_ids then
    Bound,
      "Implemented by safe copied IO command properties and a rooted completion callback proven by synchronous real IO completion."
  else if List.mem identifier Binding_io_command_queue10_safe_reachability.promotable_ids then
    Bound,
      "Implemented by byte-exact safe IO byte/texture loads and an owned scratch allocator/buffer graph with checked ranges, device identity, and retention."
  else if List.mem identifier Binding_io_counter_type_reachability.promotable_ids then
    Bound,
      "Represented exactly by a public contained descriptor or retained abstract Metal IO handle with safe ownership."
  else if List.mem identifier Binding_metal4_callable_safe_reachability.promotable_ids then
    Bound,
      "Implemented by the safe Metal4 compute/generic/residency/counter callable surface with checked graph identity, ranges, ownership retention, and native conformance."
  else if List.mem identifier Binding_metal4_second_slice_reachability.promotable_ids then
    Bound,
      "Implemented by the safe Metal4 command-buffer resource, binary-function descriptor, and render-command slice with ownership retention and native conformance."
  else if List.mem identifier Binding_metal4_native32_reachability.promotable_ids then
    Bound,
      "Implemented by the safe Metal4 ML, specialized-function, and stitched-function surface with owned graphs, checked compilation, and native conformance."
  else if List.mem identifier Binding_metal4_final9_reachability.promotable_ids then
    Bound,
      "Implemented by safe Metal4 queue-feedback snapshots with completed-submission validation and real native timing conformance."
  else if List.mem identifier Binding_metal4_pending41_reachability.remaining_promotable_ids then
    Bound,
      "Implemented by safe Metal4 specialization compilation and archive-owned compute/render construction with checked ownership and native conformance."
  else Unreviewed, "Binding classification pending during Phase 2."
