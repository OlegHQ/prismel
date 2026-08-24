let promotable_ids =
  [ "class:MTLPipelineBufferDescriptor"
  ; "class:MTLPipelineBufferDescriptorArray"
  ; "method:-[MTLPipelineBufferDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLPipelineBufferDescriptorArray setObject:atIndexedSubscript:]"
  ]

let () =
  if List.length promotable_ids <> 4
     || List.length (List.sort_uniq String.compare promotable_ids) <> 4
  then invalid_arg "Pipeline4 exact safe closure drift"
