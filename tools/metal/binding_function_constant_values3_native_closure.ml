let ids =
  [ "method:-[MTLFunctionConstantValues reset]"
  ; "method:-[MTLFunctionConstantValues setConstantValue:type:atIndex:]"
  ; "method:-[MTLFunctionConstantValues setConstantValues:type:withRange:]" ]

let () =
  if List.length ids <> 3 || List.length (List.sort_uniq String.compare ids) <> 3
  then invalid_arg "FunctionConstantValues3 native closure drift"
