let () =
  Binding_layer10_safe_closure.validate ();
  if List.length Binding_layer10_safe_closure.promotable_ids <> 10 then
    failwith "CAMetalLayer10 expected exact10";
  print_endline
    "CAMetalLayer10: exact7 callable + 2 public opaque types + 1 private opaque ABI"
