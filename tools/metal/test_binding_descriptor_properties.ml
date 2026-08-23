let fail format = Printf.ksprintf failwith format

let string name json = Yojson.Safe.Util.(json |> member name |> to_string)
let optional_string name json =
  match Yojson.Safe.Util.(json |> member name) with
  | `String value -> Some value
  | `Null -> None
  | _ -> fail "invalid inventory field %s" name

let symbol json : Binding_descriptor_property_evidence.inventory_symbol =
  let open Yojson.Safe.Util in
  { id = string "id" json
  ; kind = string "kind" json
  ; owner = optional_string "owner" json
  ; name = string "name" json
  ; header = string "header" json
  ; signature = string "signature" json
  ; macos_introduced = optional_string "macos_introduced" json
  ; attributes = json |> member "attributes" |> to_list |> List.map to_string
  ; classification = string "classification" json
  }

let require_contains haystack needle =
  let rec loop offset =
    offset + String.length needle <= String.length haystack
    && (String.sub haystack offset (String.length needle) = needle
        || loop (offset + 1))
  in
  if not (loop 0) then fail "generated output lacks %S" needle

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let json = Yojson.Safe.from_file Sys.argv.(1) in
  let symbols =
    Yojson.Safe.Util.(json |> member "symbols" |> to_list |> List.map symbol)
  in
  Binding_descriptor_property_evidence.validate_inventory symbols;
  let entries = Binding_descriptor_property_plan.entries in
  if List.length entries <> Binding_descriptor_property_plan.expected_property_count then
    fail "property count drift";
  let owners =
    entries |> List.map (fun entry -> entry.Binding_descriptor_property_spec.owner)
    |> List.sort_uniq String.compare
  in
  if List.length owners <> Binding_descriptor_property_plan.expected_owner_count then
    fail "owner count drift";
  let public = Binding_descriptor_property_codegen.render_public_record_types entries in
  let native = Binding_descriptor_property_codegen.render_native_materializers entries in
  let roundtrips = Binding_descriptor_property_codegen.render_native_roundtrip_tests entries in
  require_contains public "generated_mtl_indirect_command_buffer_descriptor_properties";
  require_contains native "nsuinteger_from_ocaml_int64";
  require_contains native "@available(macOS 26.0, *)";
  require_contains native "generated_checked_mtl_indirect_command_type_of_ocaml";
  require_contains roundtrips "setSupportRayTracing:";
  if String.length native < 10000 then fail "descriptor batch unexpectedly small";
  Printf.printf
    "Metal descriptor property batch: %d properties, %d companion methods, %d inventory IDs across %d owners\n"
    (List.length entries) (2 * List.length entries)
    (List.length Binding_descriptor_property_evidence.promotion_ids)
    (List.length owners)
