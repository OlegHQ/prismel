let ids =
  [ "class:MTLCommandQueueDescriptor"
  ; "method:-[MTLCommandQueue commandBufferWithDescriptor:]"
  ; "method:-[MTLCommandQueue commandBufferWithUnretainedReferences]"
  ; "method:-[MTLCommandQueue device]"
  ; "method:-[MTLCommandQueue insertDebugCaptureBoundary]"
  ; "method:-[MTLCommandQueue label]"
  ; "method:-[MTLCommandQueue setLabel:]"
  ; "method:-[MTLCommandQueueDescriptor logState]"
  ; "method:-[MTLCommandQueueDescriptor maxCommandBufferCount]"
  ; "method:-[MTLCommandQueueDescriptor setLogState:]"
  ; "method:-[MTLCommandQueueDescriptor setMaxCommandBufferCount:]"
  ; "property:MTLCommandQueue:device"
  ; "property:MTLCommandQueue:label"
  ; "property:MTLCommandQueueDescriptor:logState"
  ; "property:MTLCommandQueueDescriptor:maxCommandBufferCount"
  ]
let () = if List.length ids <> 15 || List.length (List.sort_uniq String.compare ids) <> 15
  then failwith "CommandQueue15 closure drift"
