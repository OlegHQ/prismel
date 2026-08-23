type item = { id : string; public_representation : string option }

let items =
  [ { id = "class:MTLBlitPassDescriptor"; public_representation = None }
  ; { id = "class:MTLBlitPassSampleBufferAttachmentDescriptor"; public_representation = Some "Metal.Descriptor.Mtl_blit_pass_sample_buffer_attachment_descriptor.t" }
  ; { id = "class:MTLBlitPassSampleBufferAttachmentDescriptorArray"; public_representation = None }
  ; { id = "class:MTLCounterSampleBufferDescriptor"; public_representation = Some "Metal.Descriptor.Mtl_counter_sample_buffer_descriptor.t" }
  ; { id = "protocol:MTLCounter"; public_representation = None }
  ; { id = "protocol:MTLCounterSampleBuffer"; public_representation = None }
  ; { id = "protocol:MTLCounterSet"; public_representation = None }
  ; { id = "protocol:MTLIOCommandBuffer"; public_representation = Some "Metal.IO.Command_buffer.t" }
  ; { id = "protocol:MTLIOCommandQueue"; public_representation = Some "Metal.IO.Queue.t" }
  ; { id = "protocol:MTLIOFileHandle"; public_representation = Some "Metal.IO.File.t" }
  ; { id = "protocol:MTLIOScratchBuffer"; public_representation = None }
  ; { id = "protocol:MTLIOScratchBufferAllocator"; public_representation = None }
  ; { id = "typedef:MTLCommonCounter"; public_representation = None }
  ; { id = "typedef:MTLCommonCounterSet"; public_representation = None }
  ; { id = "typedef:MTLCounterResultStageUtilization"; public_representation = None }
  ; { id = "typedef:MTLCounterResultStatistic"; public_representation = None }
  ; { id = "typedef:MTLCounterResultTimestamp"; public_representation = None }
  ; { id = "typedef:MTLIOCommandBufferHandler"; public_representation = None }
  ; { id = "typedef:MTLIOCompressionContext"; public_representation = None } ]

let promotable_ids = List.filter_map (fun item -> Option.map (fun _ -> item.id) item.public_representation) items
let blocked_ids = List.filter_map (fun item -> if Option.is_none item.public_representation then Some item.id else None) items
let runtime_property_handoff =
  [ "property:MTLCounterSampleBuffer:sampleCount", "instance () -> NSUInteger", "Metal.Counter_sample_buffer.sample_count"
  ; "property:MTLIOCommandBuffer:status", "instance () -> MTLIOStatus", "Metal.IO.Command_buffer.status" ]

let validate () =
  if List.length items <> 19 || List.length promotable_ids <> 5 || List.length blocked_ids <> 14
     || List.length runtime_property_handoff <> 2
     || List.exists (fun item -> not (List.mem item.id Binding_io_counter_manifest.ids)) items
  then failwith "IO/counter type reachability drift"

let () = validate ()
