let () =
  Binding_mtl4_tail14_safe_closure.validate ();
  if List.length Binding_mtl4_tail14_safe_closure.ml_pipeline5 <> 5
     || List.length Binding_mtl4_tail14_safe_closure.compute5 <> 5
     || List.length Binding_mtl4_tail14_safe_closure.ml_encoder4 <> 4
  then failwith "MTL4 tail partition drift";
  print_endline "MTL4 residual: exact ML pipeline5 + compute5 + ML encoder4"
