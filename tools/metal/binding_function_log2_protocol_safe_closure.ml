let promotable_ids =
  [ "protocol:MTLFunctionLog"
  ; "protocol:MTLFunctionLogDebugLocation"
  ]

let () =
  if List.length promotable_ids <> 2
     || List.length (List.sort_uniq String.compare promotable_ids) <> 2
  then invalid_arg "FunctionLog2 protocol closure drift"
