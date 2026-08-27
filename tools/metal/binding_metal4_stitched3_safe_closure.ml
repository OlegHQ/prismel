let promotable_ids =
  [ "class:MTL4StitchedFunctionDescriptor"
  ; "method:-[MTL4StitchedFunctionDescriptor setFunctionGraph:]"
  ; "property:MTL4StitchedFunctionDescriptor:functionGraph" ]

let validate () =
  if List.length promotable_ids <> 3
     || List.length (List.sort_uniq String.compare promotable_ids) <> 3
  then failwith "MTL4StitchedFunctionDescriptor exact3 drift"

let () = validate ()
