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
  [ "class:MTLCompileOptions"
  ; "class:MTLHeapDescriptor"
  ; "class:MTLResidencySetDescriptor"
  ; "class:MTLSamplerDescriptor"
  ; "class:MTLSharedTextureHandle"
  ; "class:MTLTextureDescriptor"
  ; "class:MTLTextureViewDescriptor"
  ; "enum:MTLCommandBufferStatus"
  ; "enum:MTLCompareFunction"
  ; "enum:MTLBufferSparseTier"
  ; "enum:MTLCPUCacheMode"
  ; "enum:MTLGPUFamily"
  ; "enum:MTLHazardTrackingMode"
  ; "enum:MTLHeapType"
  ; "enum:MTLPixelFormat"
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
  ; "enum:MTLTextureType"
  ; "enum:MTLTextureCompressionType"
  ; "enum:MTLTextureSparseTier"
  ; "enum:MTLTextureSwizzle"
  ; "enum:MTLTextureUsage"
  ; "function:MTLCopyAllDevices"
  ; "function:MTLCreateSystemDefaultDevice"
  ; "function:MTLOriginMake"
  ; "function:MTLRegionMake3D"
  ; "function:MTLSizeMake"
  ; "function:MTLTextureSwizzleChannelsMake"
  ; "record:MTLOrigin"
  ; "record:MTLRegion"
  ; "record:MTLSize"
  ; "record:MTLSizeAndAlign"
  ; "record:MTLTextureSwizzleChannels"
  ; "field:MTLOrigin:x"
  ; "field:MTLOrigin:y"
  ; "field:MTLOrigin:z"
  ; "field:MTLRegion:origin"
  ; "field:MTLRegion:size"
  ; "field:MTLSize:width"
  ; "field:MTLSize:height"
  ; "field:MTLSize:depth"
  ; "field:MTLSizeAndAlign:align"
  ; "field:MTLSizeAndAlign:size"
  ; "field:MTLTextureSwizzleChannels:alpha"
  ; "field:MTLTextureSwizzleChannels:blue"
  ; "field:MTLTextureSwizzleChannels:green"
  ; "field:MTLTextureSwizzleChannels:red"
  ; "protocol:MTLBuffer"
  ; "protocol:MTLAllocation"
  ; "protocol:MTLBlitCommandEncoder"
  ; "protocol:MTLCommandBuffer"
  ; "protocol:MTLCommandEncoder"
  ; "protocol:MTLCommandQueue"
  ; "protocol:MTLComputeCommandEncoder"
  ; "protocol:MTLComputePipelineState"
  ; "protocol:MTLDevice"
  ; "protocol:MTLFunction"
  ; "protocol:MTLHeap"
  ; "protocol:MTLLibrary"
  ; "protocol:MTLResource"
  ; "protocol:MTLResidencySet"
  ; "protocol:MTLResourceStateCommandEncoder"
  ; "protocol:MTLSamplerState"
  ; "protocol:MTLTexture"
  ; "typedef:MTLCommandBufferStatus"
  ; "typedef:MTLCompareFunction"
  ; "typedef:MTLBufferSparseTier"
  ; "typedef:MTLCPUCacheMode"
  ; "typedef:MTLGPUFamily"
  ; "typedef:MTLHazardTrackingMode"
  ; "typedef:MTLHeapType"
  ; "typedef:MTLOrigin"
  ; "typedef:MTLPixelFormat"
  ; "typedef:MTLPurgeableState"
  ; "typedef:MTLRegion"
  ; "typedef:MTLResourceOptions"
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
  ; "typedef:MTLTextureType"
  ; "typedef:MTLTextureCompressionType"
  ; "typedef:MTLTextureSparseTier"
  ; "typedef:MTLTextureSwizzle"
  ; "typedef:MTLTextureSwizzleChannels"
  ; "typedef:MTLTextureUsage"
  ; "variable:swizzle"
  ]
  @ methods
      [ ( "MTLBuffer"
        , [ "contents"; "didModifyRange:"; "length"; "sparseBufferTier"
          ; "newTextureWithDescriptor:offset:bytesPerRow:"
          ] )
      ; "MTLAllocation", [ "allocatedSize" ]
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
        , [ "fastMathEnabled"; "setFastMathEnabled:" ] )
      ; ( "MTLComputeCommandEncoder"
        , [ "dispatchThreads:threadsPerThreadgroup:"
          ; "setBuffer:offset:atIndex:"
          ; "setComputePipelineState:"; "setTexture:atIndex:"
          ] )
      ; ( "MTLComputePipelineState"
        , [ "maxTotalThreadsPerThreadgroup"; "threadExecutionWidth" ] )
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
          ; "newCommandQueue"
          ; "newComputePipelineStateWithFunction:error:"
          ; "newLibraryWithSource:options:error:"
          ; "newHeapWithDescriptor:"
          ; "newResidencySetWithDescriptor:error:"
          ; "newSamplerStateWithDescriptor:"
          ; "newSharedTextureWithDescriptor:"
          ; "newSharedTextureWithHandle:"
          ; "newTextureWithDescriptor:iosurface:plane:"
          ; "newTextureWithDescriptor:"
          ; "isDepth24Stencil8PixelFormatSupported"
          ; "supportsBCTextureCompression"
          ; "recommendedMaxWorkingSetSize"; "registryID"
          ; "sparseTileSizeInBytes"
          ; "sparseTileSizeInBytesForSparsePageSize:"
          ; "sparseTileSizeWithTextureType:pixelFormat:sampleCount:sparsePageSize:"
          ; "supportsDynamicLibraries"; "supportsFamily:"
          ; "supportsFunctionPointers"; "supportsRaytracing"
          ; "supportsRaytracingFromRender"; "supportsTextureSampleCount:"
          ; "supportsPlacementSparse"
          ] )
      ; "MTLFunction", [ "name" ]
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
      ; "MTLLibrary", [ "newFunctionWithName:" ]
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
      ; "MTLSamplerState", [ "device"; "label" ]
      ; "MTLSharedTextureHandle", [ "device"; "label" ]
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
          ; "pixelFormat"
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
      ; ( "MTLCommandQueue"
        , [ "addResidencySet:"; "addResidencySets:count:"; "commandBuffer"
          ; "removeResidencySet:"; "removeResidencySets:count:"
          ] )
      ]
  @ properties
      [ "MTLAllocation", [ "allocatedSize" ]
      ; ( "MTLCommandBuffer", [ "error"; "label"; "status" ] )
      ; "MTLCompileOptions", [ "fastMathEnabled" ]
      ; ( "MTLComputePipelineState"
        , [ "maxTotalThreadsPerThreadgroup"; "threadExecutionWidth" ] )
      ; ( "MTLDevice"
        , [ "currentAllocatedSize"; "depth24Stencil8PixelFormatSupported"
          ; "hasUnifiedMemory"; "headless"; "lowPower"; "maxBufferLength"
          ; "name"; "recommendedMaxWorkingSetSize"
          ; "registryID"; "removable"; "supportsDynamicLibraries"
          ; "supportsFunctionPointers"; "supportsRaytracing"
          ; "supportsPlacementSparse"; "supportsRaytracingFromRender"
          ; "sparseTileSizeInBytes"
          ] )
      ; "MTLFunction", [ "name" ]
      ; ( "MTLHeap"
        , [ "cpuCacheMode"; "currentAllocatedSize"; "hazardTrackingMode"
          ; "label"; "size"; "storageMode"; "type"; "usedSize"
          ] )
      ; ( "MTLHeapDescriptor"
        , [ "cpuCacheMode"; "hazardTrackingMode"
          ; "maxCompatiblePlacementSparsePageSize"; "size"
          ; "sparsePageSize"; "storageMode"; "type"
          ] )
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
      ; "MTLSamplerState", [ "device"; "label" ]
      ; "MTLSharedTextureHandle", [ "device"; "label" ]
      ; ( "MTLTexture"
        , [ "allowGPUOptimizedContents"; "arrayLength"; "compressionType"
          ; "depth"; "firstMipmapInTail"; "height"
          ; "iosurface"; "iosurfacePlane"; "isSparse"; "mipmapLevelCount"
          ; "parentRelativeLevel"; "parentRelativeSlice"; "parentTexture"
          ; "pixelFormat"; "sampleCount"; "shareable"; "sparseTextureTier"
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
      ; "MTLBuffer", [ "length"; "sparseBufferTier" ]
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
      [ "MTLPixelFormatA8Unorm"; "MTLPixelFormatR8Unorm"
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

let bound_identifier_set = String_set.of_list bound_identifiers

let name = function
  | Bound -> "bound"
  | Availability_gated -> "availability-gated"
  | Scope_excluded -> "scope-excluded"
  | Unreviewed -> "unreviewed"

let classify ~unavailable ~identifier =
  if unavailable then
    Scope_excluded, "Clang marks this declaration unavailable for macOS."
  else if String_set.mem identifier bound_identifier_set then
    Bound, "Implemented by the ownership-aware prismel.metal safe layer."
  else Unreviewed, "Binding classification pending during Phase 2."
