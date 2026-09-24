let descriptor_ids =
  [ "method:-[MTLLogStateDescriptor bufferSize]"
  ; "method:-[MTLLogStateDescriptor level]"
  ; "method:-[MTLLogStateDescriptor setBufferSize:]"
  ; "method:-[MTLLogStateDescriptor setLevel:]"
  ; "property:MTLLogStateDescriptor:bufferSize"
  ; "property:MTLLogStateDescriptor:level" ]

let handler_ids = [ "method:-[MTLLogState addLogHandler:]" ]
let promotable_ids = List.sort_uniq String.compare (descriptor_ids @ handler_ids)

let validate () =
  if List.length descriptor_ids <> 6 || List.length handler_ids <> 1
     || List.length promotable_ids <> 7 then
    failwith "LogState7 safe reachability drift";
  if promotable_ids
     <> List.sort_uniq String.compare Binding_log_state_handoff.callable_ids then
    failwith "LogState7 safe reachability escaped authoritative handoff"

let () = validate ()
