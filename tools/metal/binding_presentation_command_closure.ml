let pair name = [ "method:-[MTLCommandBuffer "^name^"]"; "property:MTLCommandBuffer:"^name ]
let callable_ids = List.sort_uniq String.compare
  (List.concat_map pair ["commandQueue";"device";"errorOptions";"GPUEndTime";"GPUStartTime";"kernelEndTime";"kernelStartTime";"retainedReferences"]
   @ [ "method:-[MTLCommandBuffer enqueue]"; "method:-[MTLCommandBuffer waitUntilScheduled]"
     ; "method:-[MTLCommandBuffer pushDebugGroup:]"; "method:-[MTLCommandBuffer popDebugGroup]"
     ; "method:-[MTLCommandBuffer encodeSignalEvent:value:]"; "method:-[MTLCommandBuffer encodeWaitForEvent:value:]"
     ; "method:-[MTLCommandBuffer computeCommandEncoderWithDispatchType:]"
     ; "method:-[MTLCommandBuffer accelerationStructureCommandEncoder]" ])
let validate () = if List.length callable_ids <> 24 then failwith "presentation command24 drift"
let () = validate ()
