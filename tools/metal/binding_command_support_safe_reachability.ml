let indirect_ids =
  [ "method:-[MTLIndirectComputeCommand clearBarrier]"
  ; "method:-[MTLIndirectComputeCommand setBarrier]"
  ; "method:-[MTLIndirectComputeCommand setImageblockWidth:height:]"
  ; "method:-[MTLIndirectComputeCommand setStageInRegion:]"
  ; "method:-[MTLIndirectComputeCommand setThreadgroupMemoryLength:atIndex:]"
  ; "method:-[MTLIndirectComputeCommand concurrentDispatchThreadgroups:threadsPerThreadgroup:]"
  ; "method:-[MTLIndirectRenderCommand clearBarrier]"
  ; "method:-[MTLIndirectRenderCommand setBarrier]"
  ; "method:-[MTLIndirectRenderCommand setCullMode:]"
  ; "method:-[MTLIndirectRenderCommand setDepthClipMode:]"
  ; "method:-[MTLIndirectRenderCommand setFrontFacingWinding:]"
  ; "method:-[MTLIndirectRenderCommand setTriangleFillMode:]"
  ; "method:-[MTLIndirectRenderCommand setDepthBias:slopeScale:clamp:]"
  ; "method:-[MTLIndirectRenderCommand setDepthStencilState:]"
  ; "method:-[MTLIndirectRenderCommand setObjectThreadgroupMemoryLength:atIndex:]"
  ; "method:-[MTLIndirectRenderCommand drawMeshThreadgroups:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:]"
  ; "method:-[MTLIndirectRenderCommand drawMeshThreads:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:]" ]
let capture_ids =
  [ "method:+[MTLCaptureManager sharedCaptureManager]"
  ; "method:-[MTLCaptureManager supportsDestination:]"
  ; "method:-[MTLCaptureManager isCapturing]"
  ; "property:MTLCaptureManager:isCapturing"
  ; "method:-[MTLCaptureDescriptor setDestination:]" ]
let event_ids =
  [ "method:-[MTLEvent device]"
  ; "method:-[MTLEvent label]"; "property:MTLEvent:label"; "method:-[MTLEvent setLabel:]"
  ; "method:-[MTLSharedEvent signaledValue]"; "property:MTLSharedEvent:signaledValue"
  ; "method:-[MTLSharedEvent setSignaledValue:]" ]
let manifest_promotable_ids=List.sort_uniq String.compare(indirect_ids@capture_ids@event_ids)
let constructor_ids=["method:-[MTLDevice newEvent]";"method:-[MTLDevice newSharedEvent]"]
let promotable_ids=List.sort_uniq String.compare(manifest_promotable_ids@constructor_ids)
let validate()=
 if List.length indirect_ids<>17||List.length capture_ids<>5||List.length event_ids<>7||List.length manifest_promotable_ids<>29||List.length promotable_ids<>31 then failwith"Command-support121 safe closure drift";
 if List.exists(fun id->not(List.mem id Binding_command_support_manifest.ids))manifest_promotable_ids then failwith"Command-support ID escaped manifest";
 if List.exists(fun id->List.mem id Binding_command_support_manifest.ids)constructor_ids then failwith"Device event constructor unexpectedly entered manifest"
let ()=validate()
