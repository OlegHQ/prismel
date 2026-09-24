let load_ids =
  [ "method:-[MTLIOCommandBuffer loadBytes:size:sourceHandle:sourceHandleOffset:]"
  ; "method:-[MTLIOCommandBuffer loadTexture:slice:level:size:sourceBytesPerRow:sourceBytesPerImage:destinationOrigin:sourceHandle:sourceHandleOffset:]" ]

let scratch_ids =
  [ "method:-[MTLIOCommandQueueDescriptor scratchBufferAllocator]"
  ; "method:-[MTLIOCommandQueueDescriptor setScratchBufferAllocator:]"
  ; "method:-[MTLIOScratchBuffer buffer]"
  ; "method:-[MTLIOScratchBufferAllocator newScratchBufferWithMinimumSize:]"
  ; "property:MTLIOCommandQueueDescriptor:scratchBufferAllocator"
  ; "property:MTLIOScratchBuffer:buffer"
  ; "protocol:MTLIOScratchBuffer"
  ; "protocol:MTLIOScratchBufferAllocator" ]

let promotable_ids = List.sort_uniq String.compare (load_ids @ scratch_ids)

let validate () =
  if List.length load_ids <> 2 || List.length scratch_ids <> 8
     || List.length promotable_ids <> 10 then
    failwith "IO load/scratch final safe slice drift";
  if List.exists
       (fun id -> not (List.mem id Binding_io_command_queue34_safe_closure.ids))
       promotable_ids then
    failwith "IO final safe slice escaped authoritative closure";
  let prior =
    Binding_io_command_queue17_safe_reachability.promotable_ids
    @ Binding_io_command_queue7_safe_reachability.promotable_ids
  in
  if List.exists (fun id -> List.mem id prior) promotable_ids then
    failwith "IO final safe slice overlaps a prior promotion";
  if List.sort_uniq String.compare (prior @ promotable_ids)
     <> List.sort_uniq String.compare Binding_io_command_queue34_safe_closure.ids
  then failwith "IO command queue34 safe closure is incomplete"

let () = validate ()
