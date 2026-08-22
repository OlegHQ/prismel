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
  ; "class:MTLTextureDescriptor"
  ; "enum:MTLCommandBufferStatus"
  ; "enum:MTLCompareFunction"
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
  ; "enum:MTLStorageMode"
  ; "enum:MTLTextureType"
  ; "enum:MTLTextureUsage"
  ; "function:MTLCopyAllDevices"
  ; "function:MTLCreateSystemDefaultDevice"
  ; "function:MTLRegionMake3D"
  ; "function:MTLSizeMake"
  ; "record:MTLOrigin"
  ; "record:MTLRegion"
  ; "record:MTLSize"
  ; "record:MTLSizeAndAlign"
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
  ; "protocol:MTLBuffer"
  ; "protocol:MTLAllocation"
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
  ; "protocol:MTLSamplerState"
  ; "protocol:MTLTexture"
  ; "typedef:MTLCommandBufferStatus"
  ; "typedef:MTLCompareFunction"
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
  ; "typedef:MTLSize"
  ; "typedef:MTLSizeAndAlign"
  ; "typedef:MTLStorageMode"
  ; "typedef:MTLTextureType"
  ; "typedef:MTLTextureUsage"
  ]
  @ methods
      [ ( "MTLBuffer"
        , [ "contents"; "didModifyRange:"; "length" ] )
      ; "MTLAllocation", [ "allocatedSize" ]
      ; ( "MTLCommandBuffer"
        , [ "commit"; "computeCommandEncoder"; "error"; "label"; "setLabel:"
          ; "status"; "useResidencySet:"; "useResidencySets:count:"
          ; "waitUntilCompleted"
          ] )
      ; "MTLCommandEncoder", [ "endEncoding" ]
      ; ( "MTLCompileOptions"
        , [ "fastMathEnabled"; "setFastMathEnabled:" ] )
      ; ( "MTLComputeCommandEncoder"
        , [ "dispatchThreads:threadsPerThreadgroup:"
          ; "setBuffer:offset:atIndex:"
          ; "setComputePipelineState:"
          ] )
      ; ( "MTLComputePipelineState"
        , [ "maxTotalThreadsPerThreadgroup"; "threadExecutionWidth" ] )
      ; ( "MTLDevice"
        , [ "currentAllocatedSize"; "hasUnifiedMemory"; "isHeadless"
          ; "heapBufferSizeAndAlignWithLength:options:"
          ; "heapTextureSizeAndAlignWithDescriptor:"
          ; "isLowPower"; "isRemovable"; "maxBufferLength"; "name"
          ; "newBufferWithBytes:length:options:"
          ; "newBufferWithBytesNoCopy:length:options:deallocator:"
          ; "newBufferWithLength:options:"; "newCommandQueue"
          ; "newComputePipelineStateWithFunction:error:"
          ; "newLibraryWithSource:options:error:"
          ; "newHeapWithDescriptor:"
          ; "newResidencySetWithDescriptor:error:"
          ; "newSamplerStateWithDescriptor:"
          ; "newTextureWithDescriptor:"
          ; "recommendedMaxWorkingSetSize"; "registryID"
          ; "supportsDynamicLibraries"; "supportsFamily:"
          ; "supportsFunctionPointers"; "supportsRaytracing"
          ; "supportsRaytracingFromRender"; "supportsTextureSampleCount:"
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
          ; "setHazardTrackingMode:"; "setSize:"; "setStorageMode:"
          ; "setType:"; "size"; "storageMode"; "type"
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
      ; ( "MTLResource"
        , [ "cpuCacheMode"; "hazardTrackingMode"; "heapOffset"; "isAliasable"
          ; "label"; "makeAliasable"; "setLabel:"; "setPurgeableState:"
          ; "storageMode"
          ] )
      ; ( "MTLSamplerDescriptor"
        , [ "borderColor"; "compareFunction"; "label"; "lodAverage"
          ; "lodMaxClamp"; "lodMinClamp"; "magFilter"; "maxAnisotropy"
          ; "minFilter"; "mipFilter"; "normalizedCoordinates"
          ; "rAddressMode"; "sAddressMode"; "setBorderColor:"
          ; "setCompareFunction:"; "setLabel:"; "setLodAverage:"
          ; "setLodMaxClamp:"; "setLodMinClamp:"; "setMagFilter:"
          ; "setMaxAnisotropy:"; "setMinFilter:"; "setMipFilter:"
          ; "setNormalizedCoordinates:"; "setRAddressMode:"
          ; "setSAddressMode:"; "setSupportArgumentBuffers:"
          ; "setTAddressMode:"; "supportArgumentBuffers"; "tAddressMode"
          ] )
      ; "MTLSamplerState", [ "label" ]
      ; ( "MTLTexture"
        , [ "arrayLength"; "depth"
          ; "getBytes:bytesPerRow:bytesPerImage:fromRegion:mipmapLevel:slice:"
          ; "height"; "mipmapLevelCount"
          ; "newTextureViewWithPixelFormat:textureType:levels:slices:"
          ; "pixelFormat"
          ; "replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:"
          ; "sampleCount"; "textureType"; "usage"; "width"
          ] )
      ; ( "MTLTextureDescriptor"
        , [ "allowGPUOptimizedContents"; "arrayLength"; "cpuCacheMode"
          ; "depth"; "hazardTrackingMode"; "height"; "mipmapLevelCount"
          ; "pixelFormat"; "sampleCount"; "setAllowGPUOptimizedContents:"
          ; "setArrayLength:"; "setCpuCacheMode:"; "setDepth:"
          ; "setHazardTrackingMode:"; "setHeight:"
          ; "setMipmapLevelCount:"; "setPixelFormat:"; "setSampleCount:"
          ; "setStorageMode:"; "setTextureType:"; "setUsage:"; "setWidth:"
          ; "storageMode"; "textureType"; "usage"; "width"
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
        , [ "currentAllocatedSize"; "hasUnifiedMemory"; "headless"; "lowPower"
          ; "maxBufferLength"; "name"; "recommendedMaxWorkingSetSize"
          ; "registryID"; "removable"; "supportsDynamicLibraries"
          ; "supportsFunctionPointers"; "supportsRaytracing"
          ; "supportsRaytracingFromRender"
          ] )
      ; "MTLFunction", [ "name" ]
      ; ( "MTLHeap"
        , [ "cpuCacheMode"; "currentAllocatedSize"; "hazardTrackingMode"
          ; "label"; "size"; "storageMode"; "type"; "usedSize"
          ] )
      ; ( "MTLHeapDescriptor"
        , [ "cpuCacheMode"; "hazardTrackingMode"; "size"; "storageMode"
          ; "type"
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
          ; "lodMaxClamp"; "lodMinClamp"; "magFilter"; "maxAnisotropy"
          ; "minFilter"; "mipFilter"; "normalizedCoordinates"
          ; "rAddressMode"; "sAddressMode"; "supportArgumentBuffers"
          ; "tAddressMode"
          ] )
      ; "MTLSamplerState", [ "label" ]
      ; ( "MTLTexture"
        , [ "arrayLength"; "depth"; "height"; "mipmapLevelCount"
          ; "pixelFormat"; "sampleCount"; "textureType"; "usage"; "width"
          ] )
      ; ( "MTLTextureDescriptor"
        , [ "allowGPUOptimizedContents"; "arrayLength"; "cpuCacheMode"
          ; "depth"; "hazardTrackingMode"; "height"; "mipmapLevelCount"
          ; "pixelFormat"; "sampleCount"; "storageMode"; "textureType"
          ; "usage"; "width"
          ] )
      ; "MTLBuffer", [ "length" ]
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
      [ "MTLHeapTypeAutomatic"; "MTLHeapTypePlacement" ]
  @ enum_cases "MTLPixelFormat"
      [ "MTLPixelFormatA8Unorm"; "MTLPixelFormatR8Unorm"
      ; "MTLPixelFormatR8Unorm_sRGB"; "MTLPixelFormatR8Uint"
      ; "MTLPixelFormatR16Float"; "MTLPixelFormatR32Float"
      ; "MTLPixelFormatRG8Unorm"; "MTLPixelFormatRG8Unorm_sRGB"
      ; "MTLPixelFormatRG16Float"; "MTLPixelFormatRG32Float"
      ; "MTLPixelFormatRGBA8Unorm"; "MTLPixelFormatRGBA8Unorm_sRGB"
      ; "MTLPixelFormatBGRA8Unorm"; "MTLPixelFormatBGRA8Unorm_sRGB"
      ; "MTLPixelFormatRGB10A2Unorm"; "MTLPixelFormatRG11B10Float"
      ; "MTLPixelFormatRGBA16Float"; "MTLPixelFormatRGBA32Float"
      ; "MTLPixelFormatDepth16Unorm"; "MTLPixelFormatDepth32Float"
      ; "MTLPixelFormatStencil8"; "MTLPixelFormatDepth24Unorm_Stencil8"
      ; "MTLPixelFormatDepth32Float_Stencil8"
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
