let queue_ids =
  [ "method:-[MTLIOCommandQueue commandBufferWithUnretainedReferences]"
  ; "method:-[MTLIOCommandQueue enqueueBarrier]"
  ; "method:-[MTLIOCommandQueue label]"
  ; "method:-[MTLIOCommandQueue setLabel:]" ]

let file_ids =
  [ "method:-[MTLIOFileHandle label]"
  ; "method:-[MTLIOFileHandle setLabel:]" ]

let command_ids =
  [ "method:-[MTLIOCommandBuffer addBarrier]"
  ; "method:-[MTLIOCommandBuffer copyStatusToBuffer:offset:]"
  ; "method:-[MTLIOCommandBuffer enqueue]"
  ; "method:-[MTLIOCommandBuffer error]"
  ; "method:-[MTLIOCommandBuffer label]"
  ; "method:-[MTLIOCommandBuffer popDebugGroup]"
  ; "method:-[MTLIOCommandBuffer pushDebugGroup:]"
  ; "method:-[MTLIOCommandBuffer setLabel:]"
  ; "method:-[MTLIOCommandBuffer signalEvent:value:]"
  ; "method:-[MTLIOCommandBuffer tryCancel]"
  ; "method:-[MTLIOCommandBuffer waitForEvent:value:]" ]

let promotable_ids =
  List.sort_uniq String.compare (queue_ids @ file_ids @ command_ids)

let validate () =
  if List.length queue_ids <> 4 || List.length file_ids <> 2
     || List.length command_ids <> 11 || List.length promotable_ids <> 17 then
    failwith "IO queue/file/command first safe slice drift";
  if List.exists
       (fun id -> not (List.mem id Binding_io_command_queue34_safe_closure.ids))
       promotable_ids then
    failwith "IO first safe slice escaped authoritative command queue34 closure"

let () = validate ()
