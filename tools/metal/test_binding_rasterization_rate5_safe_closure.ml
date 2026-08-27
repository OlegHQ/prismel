let () =
  Binding_rasterization_rate5_safe_closure.validate ();
  let open Binding_rasterization_rate5_safe_closure in
  let representations = List.map (fun item -> item.representation) items in
  if representations <>
       [ Layer_array; Layer_descriptor; Map_descriptor; Sample_array; Map_protocol ]
  then failwith "RasterizationRate exact public type mapping drift";
  print_endline "RasterizationRate: exact5 public type closure"
