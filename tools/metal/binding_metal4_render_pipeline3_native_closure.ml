let ids =
  [ "class:MTL4RenderPipelineBinaryFunctionsDescriptor"
  ; "method:-[MTL4RenderPipelineColorAttachmentDescriptor reset]"
  ; "method:-[MTL4RenderPipelineColorAttachmentDescriptorArray reset]" ]

let () =
  if List.length ids <> 3 || List.length (List.sort_uniq String.compare ids) <> 3
  then invalid_arg "MTL4RenderPipeline3 native closure drift"
