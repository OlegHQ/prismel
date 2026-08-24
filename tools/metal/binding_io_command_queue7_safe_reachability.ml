let promotable_ids =
  [ "method:-[MTLIOCommandBuffer addCompletedHandler:]"
  ; "property:MTLIOCommandBuffer:error"
  ; "property:MTLIOCommandBuffer:label"
  ; "property:MTLIOCommandBuffer:status"
  ; "property:MTLIOCommandQueue:label"
  ; "property:MTLIOFileHandle:label"
  ; "typedef:MTLIOCommandBufferHandler" ]

let validate () =
  if List.length promotable_ids <> 7
     || List.length (List.sort_uniq String.compare promotable_ids) <> 7 then
    failwith "IO callback/property safe slice drift";
  if List.exists
       (fun id -> not (List.mem id Binding_io_command_queue34_safe_closure.ids))
       promotable_ids then
    failwith "IO callback/property slice escaped authoritative closure"

let () = validate ()
