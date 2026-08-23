let direct_method_ids =
  [ "method:-[MTLDevice newIOCommandQueueWithDescriptor:error:]"
  ; "method:-[MTLDevice newIOFileHandleWithURL:error:]"
  ; "method:-[MTLIOCommandQueue commandBuffer]"
  ; "method:-[MTLIOCommandBuffer loadBuffer:offset:size:sourceHandle:sourceHandleOffset:]"
  ; "method:-[MTLIOCommandBuffer commit]"
  ; "method:-[MTLIOCommandBuffer waitUntilCompleted]"
  ; "method:-[MTLIOCommandBuffer status]" ]
let descriptor_ids =
  [ "class:MTLIOCommandQueueDescriptor"
  ; "property:MTLIOCommandQueueDescriptor:type"; "method:-[MTLIOCommandQueueDescriptor type]"; "method:-[MTLIOCommandQueueDescriptor setType:]"
  ; "property:MTLIOCommandQueueDescriptor:maxCommandBufferCount"; "method:-[MTLIOCommandQueueDescriptor maxCommandBufferCount]"; "method:-[MTLIOCommandQueueDescriptor setMaxCommandBufferCount:]"
  ; "property:MTLIOCommandQueueDescriptor:maxCommandsInFlight"; "method:-[MTLIOCommandQueueDescriptor maxCommandsInFlight]"; "method:-[MTLIOCommandQueueDescriptor setMaxCommandsInFlight:]" ]
let promotable_ids=List.sort_uniq String.compare(direct_method_ids@descriptor_ids)
let validate()=
 if List.length direct_method_ids<>7||List.length descriptor_ids<>10||List.length promotable_ids<>17 then failwith"IO safe closure drift";
 let constructors=List.filter(fun id->String.starts_with~prefix:"method:-[MTLDevice "id)direct_method_ids in
 if List.length constructors<>2 then failwith"IO constructor partition drift";
 let outside_manifest = constructors @ descriptor_ids in
 if List.exists(fun id->not(List.mem id Binding_io_counter_manifest.ids)&&not(List.mem id outside_manifest))promotable_ids then failwith"IO safe ID escaped IO/counter111"
let ()=validate()
