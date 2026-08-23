type status = Pending_safe | Blocked
let property owner name setter=["property:"^owner^":"^name;"method:-["^owner^" "^name^"]";"method:-["^owner^" "^setter^":]"]
let ownership_ids=
 [ "class:MTLRenderPipelineDescriptor";"class:MTLComputePipelineDescriptor" ] @
 List.concat
  [ property "MTLRenderPipelineDescriptor" "vertexFunction" "setVertexFunction"
  ; property "MTLRenderPipelineDescriptor" "fragmentFunction" "setFragmentFunction"
  ; property "MTLRenderPipelineDescriptor" "binaryArchives" "setBinaryArchives"
  ; property "MTLRenderPipelineDescriptor" "vertexPreloadedLibraries" "setVertexPreloadedLibraries"
  ; property "MTLRenderPipelineDescriptor" "fragmentPreloadedLibraries" "setFragmentPreloadedLibraries"
  ; property "MTLRenderPipelineDescriptor" "vertexLinkedFunctions" "setVertexLinkedFunctions"
  ; property "MTLRenderPipelineDescriptor" "fragmentLinkedFunctions" "setFragmentLinkedFunctions"
  ; property "MTLComputePipelineDescriptor" "computeFunction" "setComputeFunction"
  ; property "MTLComputePipelineDescriptor" "preloadedLibraries" "setPreloadedLibraries"
  ; property "MTLComputePipelineDescriptor" "stageInputDescriptor" "setStageInputDescriptor" ]
let mechanical_ids=
 [ "method:-[MTLComputePipelineDescriptor reset]" ] @
 property "MTLComputePipelineDescriptor" "requiredThreadsPerThreadgroup" "setRequiredThreadsPerThreadgroup" @
 [ "method:-[MTLRenderPipelineDescriptor reset]" ] @
 List.concat
  [ property "MTLRenderPipelineDescriptor" "depthAttachmentPixelFormat" "setDepthAttachmentPixelFormat"
  ; property "MTLRenderPipelineDescriptor" "inputPrimitiveTopology" "setInputPrimitiveTopology"
  ; property "MTLRenderPipelineDescriptor" "sampleCount" "setSampleCount"
  ; property "MTLRenderPipelineDescriptor" "stencilAttachmentPixelFormat" "setStencilAttachmentPixelFormat"
  ; property "MTLRenderPipelineDescriptor" "tessellationOutputWindingOrder" "setTessellationOutputWindingOrder" ]
let pending_family_ids=List.sort_uniq String.compare(ownership_ids@mechanical_ids)
let enabling_device_ids=
 [ "method:-[MTLDevice newRenderPipelineStateWithDescriptor:options:reflection:error:]"
 ; "method:-[MTLDevice newComputePipelineStateWithDescriptor:options:reflection:error:]" ]
let status id=if List.mem id pending_family_ids then Pending_safe else Blocked
let validate()=
 if List.length ownership_ids<>32||List.length mechanical_ids<>20||List.length pending_family_ids<>52||List.length enabling_device_ids<>2 then failwith"Pipeline113 expanded pending closure drift"
let ()=validate()
