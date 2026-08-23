let promotable_ids =
  [ "property:MTLCounterSampleBufferDescriptor:sampleCount"; "method:-[MTLCounterSampleBufferDescriptor sampleCount]"; "method:-[MTLCounterSampleBufferDescriptor setSampleCount:]"
  ; "property:MTLCounterSampleBufferDescriptor:storageMode"; "method:-[MTLCounterSampleBufferDescriptor storageMode]"; "method:-[MTLCounterSampleBufferDescriptor setStorageMode:]"
  ; "property:MTLIOCommandQueueDescriptor:priority"; "method:-[MTLIOCommandQueueDescriptor priority]"; "method:-[MTLIOCommandQueueDescriptor setPriority:]" ]
let already_bound_ids =
  [ "class:MTLIOCommandQueueDescriptor"
  ; "property:MTLIOCommandQueueDescriptor:type"; "method:-[MTLIOCommandQueueDescriptor setType:]"
  ; "property:MTLIOCommandQueueDescriptor:maxCommandBufferCount"; "method:-[MTLIOCommandQueueDescriptor setMaxCommandBufferCount:]"
  ; "property:MTLIOCommandQueueDescriptor:maxCommandsInFlight"; "method:-[MTLIOCommandQueueDescriptor setMaxCommandsInFlight:]" ]
let safe_public_ids=List.sort_uniq String.compare(promotable_ids@already_bound_ids)
let blocked_ids=
 Binding_io_counter_audit.items|>List.filter_map(fun(x:Binding_io_counter_audit.item)->if x.lane=Mechanical_value&&not(List.mem x.id safe_public_ids)then Some x.id else None)
let validate()=
 let counts = List.length promotable_ids,List.length already_bound_ids,List.length safe_public_ids,List.length blocked_ids in
 if counts<>(9,7,16,25) then let a,b,c,d=counts in failwith(Printf.sprintf"IO/counter scalar reachability drift: %d/%d/%d/%d"a b c d)
let ()=validate()
