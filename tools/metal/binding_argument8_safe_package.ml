let ids =
  [ "class:MTLArgument"
  ; "class:MTLArrayType"
  ; "class:MTLPointerType"
  ; "class:MTLStructMember"
  ; "class:MTLStructType"
  ; "class:MTLTensorReferenceType"
  ; "class:MTLType"
  ; "protocol:MTLTensorBinding" ]

let validate () =
  if List.length ids <> 8 || List.length (List.sort_uniq String.compare ids) <> 8
  then invalid_arg "Argument8 exact closure drift"
