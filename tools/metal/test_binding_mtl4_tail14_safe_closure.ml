let () =
  Binding_mtl4_tail14_safe_closure.validate ();
  if List.sort String.compare Binding_mtl4_tail14_safe_closure.ml_pipeline5
       <> List.sort String.compare
            (Binding_metal4_ml_pipeline5_native_closure.callable_ids
             @ Binding_metal4_ml_pipeline5_native_closure.metadata_ids)
  then failwith "MTL4 ML pipeline5 closure drift";
  if Binding_mtl4_tail14_safe_closure.compute5
       <> Binding_metal4_compute_encoder5_native_closure.ids
  then failwith "MTL4 compute5 closure drift";
  print_endline "MTL4 residual: exact ML pipeline5 + compute5 + ML encoder4"
