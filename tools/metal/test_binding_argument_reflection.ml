let check condition message = if not condition then failwith message

let string name json = Yojson.Safe.Util.(json |> member name |> to_string)
let optional_string name json =
  match Yojson.Safe.Util.(json |> member name) with
  | `String value -> Some value
  | `Null -> None
  | _ -> failwith ("invalid inventory field " ^ name)

let symbol json : Binding_argument_reflection_evidence.symbol =
  { id = string "id" json
  ; kind = string "kind" json
  ; owner = optional_string "owner" json
  ; name = string "name" json
  ; header = string "header" json
  ; signature = string "signature" json
  ; macos_introduced = optional_string "macos_introduced" json
  ; classification = string "classification" json
  }

let () =
  if Array.length Sys.argv <> 2 then failwith "expected generated inventory path";
  let json = Yojson.Safe.from_file Sys.argv.(1) in
  let symbols =
    Yojson.Safe.Util.(json |> member "symbols" |> to_list |> List.map symbol)
  in
  Binding_argument_reflection_evidence.validate_inventory symbols;
  let open Binding_argument_reflection_plan in
  check (List.length entries = 57) "method count";
  check (List.length inventory_ids = 101) "declaration count";
  check
    (List.length (List.sort_uniq String.compare inventory_ids) = 101)
    "unique inventory IDs";
  let manifest = Binding_argument_reflection_codegen.render_manifest entries in
  let native = Binding_argument_reflection_codegen.render_native_calls entries in
  let ownership =
    Binding_argument_reflection_codegen.render_snapshot_ownership_helpers ()
  in
  check (String.length manifest > 5_000) "manifest unexpectedly small";
  check (String.length native > 9_000) "native call batch unexpectedly small";
  check
    (not (String.contains native '\000'))
    "native output contains invalid byte";
  check (String.length ownership > 700) "ownership helpers unexpectedly small";
  print_endline "Metal argument reflection plan: 57 methods + 44 property companions = 101 declarations"
