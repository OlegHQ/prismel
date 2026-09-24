let callable_ids =
  [ "method:-[CAMetalLayer colorspace]"; "method:-[CAMetalLayer setColorspace:]"; "property:CAMetalLayer:colorspace"
  ; "method:-[MTLRenderPassDescriptor setDepthAttachment:]"; "method:-[MTLRenderPassDescriptor setStencilAttachment:]"
  ; "method:-[MTLRenderPassDescriptor sampleBufferAttachments]"; "property:MTLRenderPassDescriptor:sampleBufferAttachments" ]
let validate () = if List.length (List.sort_uniq String.compare callable_ids) <> 7 then failwith "presentation graph-tail7 drift"
let () = validate ()
