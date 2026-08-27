let () =
  Binding_render_encoder33_safe_package.validate ();
  let total = List.fold_left (fun n (_,count) -> n + count) 0
      Binding_render_encoder33_safe_package.public_groups in
  if total <> 33 then failwith "RenderEncoder33 public group cardinality drift";
  Printf.printf "RenderEncoder33 safe package: exact%d public IDs\n%!"
    (List.length Binding_render_encoder33_safe_package.ids)
