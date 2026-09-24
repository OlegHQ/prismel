let ownership_ids =
  [ "method:+[MTLBlitPassDescriptor blitPassDescriptor]"
  ; "method:-[MTLBlitPassDescriptor sampleBufferAttachments]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptor sampleBuffer]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptor setSampleBuffer:]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptorArray setObject:atIndexedSubscript:]"
  ; "property:MTLBlitPassDescriptor:sampleBufferAttachments"
  ; "property:MTLBlitPassSampleBufferAttachmentDescriptor:sampleBuffer" ]

let metadata_ids =
  [ "class:MTLBlitPassDescriptor"
  ; "class:MTLBlitPassSampleBufferAttachmentDescriptorArray" ]

let () =
  let ids = ownership_ids @ metadata_ids in
  if List.length ownership_ids <> 8 || List.length metadata_ids <> 2
     || List.length (List.sort_uniq String.compare ids) <> 10
  then invalid_arg "BlitPass10 native closure drift"
