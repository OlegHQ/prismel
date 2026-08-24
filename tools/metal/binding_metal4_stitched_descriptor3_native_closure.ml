let ids =
  [ "class:MTL4StitchedFunctionDescriptor"
  ; "method:-[MTL4StitchedFunctionDescriptor setFunctionGraph:]"
  ; "property:MTL4StitchedFunctionDescriptor:functionGraph" ]

let () =
  if List.length ids <> 3 || List.length (List.sort_uniq String.compare ids) <> 3
  then invalid_arg "MTL4StitchedFunctionDescriptor3 native closure drift"
