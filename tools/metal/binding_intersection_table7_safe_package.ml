let ids =
  List.filter (fun id -> id <> "typedef:MTLIntersectionFunctionBufferArguments")
    Binding_intersection_table8_native_closure.ids

let validate () =
  if List.length ids <> 7 || List.length (List.sort_uniq String.compare ids) <> 7
  then invalid_arg "IntersectionFunctionTable7 safe closure drift"
