let () =
  if Binding_mtl4_residual_plan.expected_count <> Binding_metal4_manifest.count
  then failwith "MTL4 duplicate count changed";
  if Binding_mtl4_residual_plan.expected_digest <> Binding_metal4_manifest.digest
  then failwith "MTL4 duplicate digest changed";
  if Binding_metal4_manifest.count <> 190 then failwith "expected exact 190-ID intersection"
