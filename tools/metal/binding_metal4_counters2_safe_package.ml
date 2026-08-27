let ids =
  [ "class:MTL4CounterHeapDescriptor"
  ; "protocol:MTL4CounterHeap" ]

let validate () =
  if List.length ids <> 2 || List.length (List.sort_uniq String.compare ids) <> 2
  then invalid_arg "MTL4Counters2 exact closure drift"
