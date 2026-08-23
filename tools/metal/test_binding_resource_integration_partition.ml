let () =
  let module P = Binding_resource_integration_partition in
  P.validate ();
  if List.length P.descriptor_owned <> 24 || List.length P.handwritten_ownership <> 56
  then failwith "resource100 24/56 integration partition drift";
  let all = P.descriptor_owned @ P.already_callable @ P.qualification_only @ P.ownership_sensitive in
  if List.length all <> Binding_resource_manifest.count then failwith "resource100 partition total drift";
  List.iter (fun id -> if List.length (List.filter (String.equal id) all) <> 1 then failwith ("duplicate/missing: "^id)) Binding_resource_manifest.ids;
  print_endline "resource100 integration partition: 24 descriptor-owned + 56 handwritten + 10 scalar + 7 qualification + 3 graph-gated green"
