let ids =
  [ "method:-[MTLDevice newCommandQueueWithDescriptor:]"
  ; "method:-[MTLDevice newCommandQueueWithMaxCommandBufferCount:]"
  ; "method:-[MTLDevice newMTL4CommandQueue]" ]

let validate () =
  if List.length ids <> 3 || List.length (List.sort_uniq String.compare ids) <> 3 then
    invalid_arg "Device queue3 exact closure drift"
