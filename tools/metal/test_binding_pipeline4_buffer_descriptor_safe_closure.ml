let () =
  let expected =
    [ "class:MTLPipelineBufferDescriptor"
    ; "class:MTLPipelineBufferDescriptorArray"
    ; "method:-[MTLPipelineBufferDescriptorArray objectAtIndexedSubscript:]"
    ; "method:-[MTLPipelineBufferDescriptorArray setObject:atIndexedSubscript:]"
    ]
  in
  if Binding_pipeline4_buffer_descriptor_safe_closure.promotable_ids <> expected
  then failwith "Pipeline4 safe closure drift";
  print_endline "Pipeline4 safe closure: exact4"
