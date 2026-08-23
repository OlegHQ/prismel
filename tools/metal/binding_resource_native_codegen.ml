let c_symbol id =
  let buffer = Bytes.of_string ("caml_prismel_metal_generated_resource_" ^ id) in
  Bytes.iteri
    (fun index character ->
      match character with
      | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> ()
      | _ -> Bytes.set buffer index '_') buffer;
  Bytes.to_string buffer

let emit_provenance_table () =
  Binding_resource_manifest.ids
  |> List.map (fun id -> Printf.sprintf "{ \"%s\", \"%s\" }," id (c_symbol id))
  |> String.concat "\n"

let expected_native_output = "tools/metal/metal_resource_typed_generated.mm"
