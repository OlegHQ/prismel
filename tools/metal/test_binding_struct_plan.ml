open Support

let fail format = Printf.ksprintf failwith format

let require_string name value =
  match member_string name value with
  | Some value -> value
  | None -> fail "inventory field %s is not a string" name

let declaration value : Binding_struct_plan.declaration =
  { id = require_string "id" value
  ; kind = require_string "kind" value
  ; owner = member_string "owner" value
  ; signature = require_string "signature" value
  ; classification = require_string "classification" value
  }

let () =
  if Array.length Sys.argv <> 3 || Sys.argv.(1) <> "--inventory" then
    fail "usage: %s --inventory PATH" Sys.argv.(0);
  let json = read_file Sys.argv.(2) |> Yojson.Safe.from_string in
  let symbols =
    match member_list "symbols" json with
    | Some symbols -> List.map declaration symbols
    | None -> fail "inventory symbols is not a list"
  in
  let selection = Binding_struct_plan.select symbols in
  if selection.method_count + selection.property_count
     <> Binding_struct_plan.expected_declaration_count then
    fail "struct shard cardinality drift";
  if not (Binding_struct_spec.contains_type "instance (MTLSize) -> void" "MTLSize")
  then fail "exact type token was not found";
  if Binding_struct_spec.contains_type "instance (MTLSizeAndAlign) -> void" "MTLSize"
  then fail "type-token selection accepted a prefix";
  if Binding_struct_spec.mechanically_safe_signature
       "instance (const MTLRegion * _Nonnull) -> void"
  then fail "pointer-bearing struct signature was accepted";
  if Binding_struct_spec.mechanically_safe_signature
       "instance (id<MTLBuffer>, MTLSize) -> void"
  then fail "object-bearing struct signature was accepted";
  Printf.printf "Metal struct plan: %d methods + %d properties = %d declarations across %d owners\n"
    selection.method_count selection.property_count
    (List.length selection.declarations) selection.owner_count
