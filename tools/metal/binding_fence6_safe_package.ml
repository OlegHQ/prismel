let ids =
  [ "method:-[MTLFence device]"
  ; "method:-[MTLFence label]"
  ; "method:-[MTLFence setLabel:]"
  ; "property:MTLFence:device"
  ; "property:MTLFence:label"
  ; "protocol:MTLFence" ]

let validate () =
  if List.length ids <> 6 || List.length (List.sort_uniq String.compare ids) <> 6
  then invalid_arg "Fence6 exact closure drift"
