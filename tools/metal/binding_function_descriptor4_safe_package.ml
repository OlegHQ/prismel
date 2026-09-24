let ids =
  [ "class:MTLIntersectionFunctionDescriptor"
  ; "method:-[MTLFunctionDescriptor binaryArchives]"
  ; "method:-[MTLFunctionDescriptor setBinaryArchives:]"
  ; "property:MTLFunctionDescriptor:binaryArchives" ]

let validate () =
  if List.length ids <> 4 || List.length (List.sort_uniq String.compare ids) <> 4
  then invalid_arg "FunctionDescriptor4 exact closure drift"
