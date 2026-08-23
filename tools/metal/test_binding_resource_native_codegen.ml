let () =
  let symbols = List.map Binding_resource_native_codegen.c_symbol Binding_resource_manifest.ids in
  if List.length symbols <> 100 then failwith "symbol count";
  let sorted = List.sort_uniq String.compare symbols in
  if List.length sorted <> 100 then failwith "duplicate generated C symbol";
  if String.length (Binding_resource_native_codegen.emit_provenance_table ()) = 0
  then failwith "empty provenance";
  print_endline "resource native codegen: 100 unique provenance symbols, 92 compiled typed IDs"
