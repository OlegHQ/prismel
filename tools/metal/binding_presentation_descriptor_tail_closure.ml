let callable_ids =
  [ "method:-[CAMetalLayer EDRMetadata]"; "method:-[CAMetalLayer setEDRMetadata:]"; "property:CAMetalLayer:EDRMetadata"
  ; "method:-[MTLCommandBuffer logs]"; "property:MTLCommandBuffer:logs"
  ; "method:-[MTLCommandBuffer accelerationStructureCommandEncoderWithDescriptor:]"
  ; "method:-[MTLCommandBuffer blitCommandEncoderWithDescriptor:]"
  ; "method:-[MTLCommandBuffer computeCommandEncoderWithDescriptor:]"
  ; "method:-[MTLCommandBuffer parallelRenderCommandEncoderWithDescriptor:]"
  ; "method:-[MTLCommandBuffer resourceStateCommandEncoderWithDescriptor:]" ]
let validate () = if List.length (List.sort_uniq String.compare callable_ids) <> 10 then failwith "presentation descriptor-tail10 drift"
let () = validate ()
