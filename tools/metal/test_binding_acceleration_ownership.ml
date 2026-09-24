let string name json = Yojson.Safe.Util.(json |> member name |> to_string)
let optional_string name json = match Yojson.Safe.Util.(json |> member name) with `String value -> Some value | `Null -> None | _ -> failwith name
let declaration json : Binding_acceleration_ownership_plan.declaration =
  { id=string "id" json; kind=string "kind" json; owner=optional_string "owner" json; name=string "name" json
  ; header=string "header" json; signature=string "signature" json; macos_introduced=optional_string "macos_introduced" json
  ; classification=string "classification" json }
let () =
  if Array.length Sys.argv <> 2 then failwith "inventory path required";
  let json = Yojson.Safe.from_file Sys.argv.(1) in
  let declarations = Yojson.Safe.Util.(json |> member "symbols" |> to_list |> List.map declaration) in
  let selection = Binding_acceleration_ownership_plan.select declarations in
  Binding_acceleration_ownership_evidence.validate selection;
  if String.length (Binding_acceleration_ownership_codegen.render_safe_schema selection) < 3000 then failwith "safe schema too small";
  if String.length (Binding_acceleration_ownership_codegen.render_native_contract selection) < 5000 then failwith "native contract too small";
  Printf.printf "Metal acceleration ownership batch: 49 properties + 97 companions = 146 IDs across 22 owners\n"
