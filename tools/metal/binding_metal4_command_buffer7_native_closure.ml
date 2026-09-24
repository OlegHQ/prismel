let exact_ids =
  [ "class:MTL4CommandBufferOptions"
  ; "method:-[MTL4CommandBuffer beginCommandBufferWithAllocator:options:]"
  ; "method:-[MTL4CommandBuffer machineLearningCommandEncoder]"
  ; "method:-[MTL4CommandBuffer renderCommandEncoderWithDescriptor:options:]"
  ; "method:-[MTL4CommandBufferOptions logState]"
  ; "method:-[MTL4CommandBufferOptions setLogState:]"
  ; "property:MTL4CommandBufferOptions:logState" ]

let () =
  if List.length exact_ids <> 7 then failwith "MTL4CommandBuffer7 count drift";
  if List.length (List.sort_uniq String.compare exact_ids) <> 7 then
    failwith "MTL4CommandBuffer7 duplicate ID";
  Printf.printf "MTL4CommandBuffer7 native closure: exact 7/7\n%!"
