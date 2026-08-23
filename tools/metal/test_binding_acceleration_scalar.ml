let string name json = Yojson.Safe.Util.(json |> member name |> to_string)
let optional_string name json = match Yojson.Safe.Util.(json |> member name) with `String value -> Some value | `Null -> None | _ -> failwith name
let declaration json : Binding_acceleration_scalar_plan.declaration =
  { id = string "id" json; kind = string "kind" json; owner = optional_string "owner" json
  ; name = string "name" json; header = string "header" json; signature = string "signature" json
  ; macos_introduced = optional_string "macos_introduced" json; classification = string "classification" json }
let () =
  if Array.length Sys.argv <> 2 then failwith "inventory path required";
  let json = Yojson.Safe.from_file Sys.argv.(1) in
  let declarations = Yojson.Safe.Util.(json |> member "symbols" |> to_list |> List.map declaration) in
  let selection = Binding_acceleration_scalar_plan.select declarations in
  Binding_acceleration_scalar_evidence.validate selection;
  let safe = Binding_acceleration_scalar_codegen.render_safe_mli selection in
  let native = Binding_acceleration_scalar_codegen.render_native selection in
  let unsupported = Binding_acceleration_scalar_codegen.render_unsupported_test selection in
  if String.length safe < 8_000 || String.length native < 50_000 || String.length unsupported < 200 then failwith "acceleration batch output unexpectedly small";
  Printf.printf "Metal acceleration scalar batch: %d properties, %d IDs, %d owners\n" (List.length selection.properties) (List.length selection.identifiers) (List.length selection.owners)
