let promotable_ids =
  [ "class:MTLRenderPassDescriptor"
  ; "class:MTLRenderPassSampleBufferAttachmentDescriptor"
  ; "class:MTLRenderPassSampleBufferAttachmentDescriptorArray"
  ; "method:-[MTLRenderPassAttachmentDescriptor resolveTexture]"
  ; "method:-[MTLRenderPassAttachmentDescriptor setResolveTexture:]"
  ; "method:-[MTLRenderPassColorAttachmentDescriptorArray setObject:atIndexedSubscript:]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor endOfFragmentSampleIndex]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor endOfVertexSampleIndex]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor sampleBuffer]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setEndOfFragmentSampleIndex:]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setEndOfVertexSampleIndex:]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setSampleBuffer:]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setStartOfFragmentSampleIndex:]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setStartOfVertexSampleIndex:]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor startOfFragmentSampleIndex]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptor startOfVertexSampleIndex]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLRenderPassSampleBufferAttachmentDescriptorArray setObject:atIndexedSubscript:]"
  ; "property:MTLRenderPassAttachmentDescriptor:resolveTexture"
  ; "property:MTLRenderPassSampleBufferAttachmentDescriptor:endOfFragmentSampleIndex"
  ; "property:MTLRenderPassSampleBufferAttachmentDescriptor:endOfVertexSampleIndex"
  ; "property:MTLRenderPassSampleBufferAttachmentDescriptor:sampleBuffer"
  ; "property:MTLRenderPassSampleBufferAttachmentDescriptor:startOfFragmentSampleIndex"
  ; "property:MTLRenderPassSampleBufferAttachmentDescriptor:startOfVertexSampleIndex"
  ]

let () =
  if List.length promotable_ids<>24
     || List.length(List.sort_uniq String.compare promotable_ids)<>24
  then invalid_arg "RenderPass24 exact closure drift"
