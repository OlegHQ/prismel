(* Exact non-Device small-header declarations already represented by owned
   public safe APIs and real native fixtures.  The two asynchronous MTL4 ML
   compiler declarations remain outside this set until callback roots are
   exposed safely. *)
let ids =
  [ "class:MTL4BinaryFunction"
  ; "class:MTLDynamicLibrary"
  ; "class:MTL4RenderPipelineBinaryFunctionsDescriptor"
  ; "class:MTL4SpecializedFunctionDescriptor"
  ; "protocol:MTLArgumentEncoder"
  ; "variable:MTLAttributeStrideStatic"
  ; "class:MTLBlitPassDescriptor"
  ; "class:MTLBlitPassSampleBufferAttachmentDescriptorArray"
  ; "class:MTLCaptureDescriptor"
  ; "class:MTLCaptureManager"
  ; "protocol:MTLCaptureScope"
  ; "class:MTLCommandQueueDescriptor"
  ; "method:-[MTLComputePipelineState functionHandleWithBinaryFunction:]"
  ; "method:-[MTLDepthStencilState gpuResourceID]"
  ; "property:MTLDepthStencilState:gpuResourceID"
  ; "protocol:MTLDrawable"
  ; "typedef:MTLDrawablePresentedHandler"
  ; "class:MTLLogStateDescriptor"
  ; "protocol:MTLLogState"
  ; "protocol:MTLParallelRenderCommandEncoder"
  ; "protocol:MTLResourceViewPool"
  ; "record:MTLSharedTextureHandlePrivate"
  ; "protocol:MTLTextureViewPool"
  ; "method:-[MTLVisibleFunctionTable setFunctions:withRange:]" ]

let validate () =
  if List.length ids <> 24 then invalid_arg "small-header safe24 cardinality drift";
  if List.length (List.sort_uniq String.compare ids) <> 24 then
    invalid_arg "small-header safe24 duplicate IDs"
