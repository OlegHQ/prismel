let promotable_ids =
  [ "class:MTLTensorDescriptor"; "class:MTLTensorExtents"; "protocol:MTLTensor" ]

let validate () =
  if List.length promotable_ids <> 3
     || List.length (List.sort_uniq String.compare promotable_ids) <> 3
  then failwith "Tensor residual exact3 drift"

let () = validate ()
