let owner_ids =
  [ "method:-[MTLDevice areBarycentricCoordsSupported]"
  ; "method:-[MTLDevice convertSparsePixelRegions:toTileRegions:withTileSize:alignmentMode:numRegions:]"
  ; "method:-[MTLDevice convertSparseTileRegions:toPixelRegions:withTileSize:numRegions:]"
  ; "method:-[MTLDevice counterSets]"
  ; "method:-[MTLDevice getDefaultSamplePositions:count:]"
  ; "method:-[MTLDevice maxThreadsPerThreadgroup]"
  ; "method:-[MTLDevice newArgumentEncoderWithBufferBinding:]"
  ; "method:-[MTLDevice newComputePipelineStateWithDescriptor:options:completionHandler:]"
  ; "method:-[MTLDevice newComputePipelineStateWithFunction:completionHandler:]"
  ; "method:-[MTLDevice newComputePipelineStateWithFunction:options:completionHandler:]"
  ; "method:-[MTLDevice newComputePipelineStateWithFunction:options:reflection:error:]"
  ; "method:-[MTLDevice newLibraryWithSource:options:completionHandler:]"
  ; "method:-[MTLDevice newLibraryWithStitchedDescriptor:completionHandler:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithDescriptor:completionHandler:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithDescriptor:options:completionHandler:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithMeshDescriptor:options:completionHandler:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithTileDescriptor:options:completionHandler:]"
  ; "method:-[MTLDevice newSharedEventWithHandle:]"
  ; "method:-[MTLDevice queryTimestampFrequency]"
  ; "method:-[MTLDevice sampleTimestamps:gpuTimestamp:]"
  ; "method:-[MTLDevice setShouldMaximizeConcurrentCompilation:]"
  ; "method:-[MTLDevice shouldMaximizeConcurrentCompilation]"
  ; "method:-[MTLDevice sizeOfCounterHeapEntry:]"
  ; "method:-[MTLDevice supportsCounterSampling:]"
  ; "method:-[MTLDevice supportsFeatureSet:]"
  ; "method:-[MTLDevice supportsRasterizationRateMapWithLayerCount:]"
  ; "property:MTLDevice:barycentricCoordsSupported"
  ; "property:MTLDevice:counterSets"
  ; "property:MTLDevice:maxThreadsPerThreadgroup"
  ; "property:MTLDevice:shouldMaximizeConcurrentCompilation"
  ; "property:MTLDevice:supportsBCTextureCompression" ]

let metadata_ids =
  [ "class:MTLTilePipelineColorAttachmentDescriptor"
  ; "function:MTLCopyAllDevicesWithObserver"
  ; "function:MTLRemoveDeviceObserver"
  ; "protocol:MTLIndirectComputeCommandEncoder"
  ; "protocol:MTLIndirectRenderCommandEncoder"
  ; "typedef:MTLDeviceNotificationHandler"
  ; "typedef:MTLDeviceNotificationName" ]

let async9 =
  List.filter (fun id ->
    String.ends_with ~suffix:"completionHandler:]" id)
    owner_ids

let validate () =
  let all = owner_ids @ metadata_ids in
  if List.length owner_ids <> 31 || List.length metadata_ids <> 7
     || List.length all <> 38
     || List.length (List.sort_uniq String.compare all) <> 38
  then invalid_arg "Device MTLDevice.h tail38 drift";
  if List.length async9 <> 9 then invalid_arg "Device async9 drift"
