let () =
  Binding_metal4_counters2_safe_package.validate ();
  let expected =
    [ "class:MTL4CounterHeapDescriptor"; "protocol:MTL4CounterHeap" ]
  in
  if List.sort String.compare Binding_metal4_counters2_safe_package.ids <>
     List.sort String.compare expected then
    failwith "MTL4Counters2 exact membership drift";
  print_endline "MTL4Counters2 safe package: exact2 descriptor/owned heap"
