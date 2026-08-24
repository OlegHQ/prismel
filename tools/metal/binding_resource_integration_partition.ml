let descriptor_owned =
  [ "method:-[MTLBufferLayoutDescriptor setStepFunction:]"; "method:-[MTLBufferLayoutDescriptor setStepRate:]"; "method:-[MTLBufferLayoutDescriptor setStride:]"
  ; "method:-[MTLBufferLayoutDescriptor stepFunction]"; "method:-[MTLBufferLayoutDescriptor stepRate]"; "method:-[MTLBufferLayoutDescriptor stride]"
  ; "property:MTLBufferLayoutDescriptor:stepFunction"; "property:MTLBufferLayoutDescriptor:stepRate"; "property:MTLBufferLayoutDescriptor:stride"
  ; "method:-[MTLResourceStatePassSampleBufferAttachmentDescriptor endOfEncoderSampleIndex]"
  ; "method:-[MTLResourceStatePassSampleBufferAttachmentDescriptor setEndOfEncoderSampleIndex:]"
  ; "method:-[MTLResourceStatePassSampleBufferAttachmentDescriptor setStartOfEncoderSampleIndex:]"
  ; "method:-[MTLResourceStatePassSampleBufferAttachmentDescriptor startOfEncoderSampleIndex]"
  ; "property:MTLResourceStatePassSampleBufferAttachmentDescriptor:endOfEncoderSampleIndex"
  ; "property:MTLResourceStatePassSampleBufferAttachmentDescriptor:startOfEncoderSampleIndex"
  ; "method:-[MTLResourceViewPoolDescriptor label]"; "method:-[MTLResourceViewPoolDescriptor resourceViewCount]"
  ; "method:-[MTLResourceViewPoolDescriptor setLabel:]"; "method:-[MTLResourceViewPoolDescriptor setResourceViewCount:]"
  ; "property:MTLResourceViewPoolDescriptor:label"; "property:MTLResourceViewPoolDescriptor:resourceViewCount"
  ; "class:MTLBufferLayoutDescriptor"; "class:MTLResourceStatePassSampleBufferAttachmentDescriptor"
  ; "class:MTLResourceViewPoolDescriptor"
  ]

let already_callable =
  [ "method:-[MTLBuffer removeAllDebugMarkers]"; "method:-[MTLDevice sparseTileSizeWithTextureType:pixelFormat:sampleCount:]"
  ; "method:-[MTLHeap resourceOptions]"; "property:MTLHeap:resourceOptions"
  ; "method:-[MTLResource allocatedSize]"; "property:MTLResource:allocatedSize"
  ; "method:-[MTLResource resourceOptions]"; "property:MTLResource:resourceOptions"
  ; "method:-[MTLTexture isFramebufferOnly]"; "property:MTLTexture:framebufferOnly" ]

let qualification_only =
  [ "class:MTLBufferLayoutDescriptorArray"; "class:MTLResourceStatePassDescriptor"
  ; "class:MTLResourceStatePassSampleBufferAttachmentDescriptorArray"
  ; "class:MTLTextureReferenceType"; "enum-case:MTLResourceOptions:MTLResourceOptionCPUCacheModeDefault"
  ; "enum-case:MTLResourceOptions:MTLResourceOptionCPUCacheModeWriteCombined"
  ; "enum-case:MTLResourceOptions:MTLResourceStorageModeMemoryless" ]

let mem id values = List.exists (String.equal id) values
let ownership_sensitive = List.filter (fun id -> not (mem id descriptor_owned || mem id already_callable || mem id qualification_only)) Binding_resource_manifest.ids

let validate () =
  if List.length descriptor_owned <> 24 then failwith "resource descriptor-owned partition drift";
  if List.length already_callable <> 10 then failwith "resource callable partition drift";
  if List.length qualification_only <> 7 then failwith "resource qualification partition drift";
  if List.length ownership_sensitive <> 59 then failwith "resource ownership partition drift"

(* Two texture buffer layout scalar properties are callable only after the safe
   texture-parent graph validates that the texture is buffer-backed. *)
let graph_gated_scalars =
  [ "property:MTLTexture:buffer"; "property:MTLTexture:bufferBytesPerRow"; "property:MTLTexture:bufferOffset" ]

let safe_ownership_tail =
  [ "method:-[MTLBuffer newRemoteBufferViewForDevice:]"
  ; "method:-[MTLBuffer remoteStorageBuffer]"
  ; "property:MTLBuffer:remoteStorageBuffer"
  ; "method:-[MTLResourceViewPool baseResourceID]"
  ; "property:MTLResourceViewPool:baseResourceID"
  ; "method:-[MTLResourceViewPool label]"
  ; "property:MTLResourceViewPool:label"
  ; "method:-[MTLResource device]"
  ; "property:MTLResource:device"
  ; "method:-[MTLResource heap]"
  ; "property:MTLResource:heap"
  ; "method:-[MTLTexture newRemoteTextureViewForDevice:]"
  ; "method:-[MTLTexture remoteStorageTexture]"
  ; "property:MTLTexture:remoteStorageTexture"
  ; "method:-[MTLTexture rootResource]"
  ; "property:MTLTexture:rootResource"
  ; "method:-[MTLTextureViewPool setTextureViewFromBuffer:descriptor:offset:bytesPerRow:atIndex:]"
  ; "method:-[MTLHeap newAccelerationStructureWithSize:]"
  ; "method:-[MTLResourceStateCommandEncoder updateTextureMapping:mode:indirectBuffer:indirectBufferOffset:]"
  ; "method:-[MTLResourceStateCommandEncoder updateTextureMappings:mode:regions:mipLevels:slices:numRegions:]"
  ; "method:-[MTLResourceStatePassDescriptor sampleBufferAttachments]"
  ; "property:MTLResourceStatePassDescriptor:sampleBufferAttachments"
  ; "method:-[MTLResourceStatePassSampleBufferAttachmentDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLResourceStatePassSampleBufferAttachmentDescriptorArray setObject:atIndexedSubscript:]"
  ; "method:-[MTLHeap device]"
  ; "property:MTLHeap:device"
  ; "method:-[MTLResourceStateCommandEncoder updateFence:]"
  ; "method:-[MTLResourceStateCommandEncoder waitForFence:]"
  ; "method:+[MTLResourceStatePassDescriptor resourceStatePassDescriptor]"
  ]

let handwritten_ownership =
  List.filter
    (fun id -> not (mem id graph_gated_scalars || mem id safe_ownership_tail))
    ownership_sensitive

let () =
  validate ();
  if List.length safe_ownership_tail <> 29 then failwith "resource safe ownership29 drift";
  if List.length handwritten_ownership <> 27 then failwith "resource handwritten27 drift"
