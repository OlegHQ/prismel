let declaration ?owner ?constant_value ~id ~kind ~name ~header ~line ~signature () =
  Binding_enum_implicit_codegen.
    { id; kind; name; owner; header; line = Some line; signature
    ; classification = "unreviewed"; constant_value }

let inventory () =
  List.concat_map
    (fun (family : Binding_enum_implicit_plan.family) ->
      declaration ~id:("enum:" ^ family.sdk_name) ~kind:"enum"
        ~name:family.sdk_name ~header:family.header ~line:family.enum_line ~signature:"" ()
      :: declaration ~id:("typedef:" ^ family.sdk_name) ~kind:"typedef"
           ~name:family.sdk_name ~header:family.header ~line:family.enum_line
           ~signature:family.typedef_signature ()
      :: List.map
           (fun (case : Binding_enum_implicit_plan.case) ->
             declaration ~owner:family.sdk_name
               ~id:(Printf.sprintf "enum-case:%s:%s" family.sdk_name case.sdk_name)
               ~kind:"enum-case" ~name:case.sdk_name ~header:family.header
               ~line:case.expected_line ~signature:family.sdk_name ())
           family.cases)
    Binding_enum_implicit_plan.families

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let required_string name value =
  match member name value with
  | Some (`String value) -> value
  | _ -> failwith ("missing inventory string field " ^ name)

let optional_string name value =
  match member name value with
  | Some (`String value) -> Some value
  | Some `Null | None -> None
  | Some _ -> failwith ("malformed inventory string field " ^ name)

let optional_int name value =
  match member name value with
  | Some (`Int value) -> Some value
  | Some `Null | None -> None
  | Some _ -> failwith ("malformed inventory integer field " ^ name)

let inventory_file path =
  let json = Yojson.Safe.from_file path in
  let symbols =
    match member "symbols" json with
    | Some (`List values) -> values
    | _ -> failwith "inventory symbols must be a list"
  in
  List.map
    (fun value ->
      Binding_enum_implicit_codegen.
        { id = required_string "id" value
        ; kind = required_string "kind" value
        ; name = required_string "name" value
        ; owner = optional_string "owner" value
        ; header = required_string "header" value
        ; line = optional_int "line" value
        ; signature = required_string "signature" value
        ; classification = required_string "classification" value
        ; constant_value = optional_string "constant_value" value
        })
    symbols

let () =
  let selected = Binding_enum_implicit_codegen.select (inventory ()) in
  assert (Binding_enum_implicit_codegen.family_count selected = 7);
  assert (Binding_enum_implicit_codegen.case_count selected = 23);
  assert (Binding_enum_implicit_codegen.declaration_count selected = 37);
  assert (List.length (Binding_enum_implicit_codegen.identifiers selected) = 37);
  let raw = Binding_enum_implicit_codegen.render_raw_ml selected in
  assert (String.starts_with ~prefix:"module Implicit_enum_constants" raw);
  assert
    (let needle = "module Mtl_log_level" in
     let needle_length = String.length needle in
     let rec contains index =
       index + needle_length <= String.length raw
       &&
       (String.sub raw index needle_length = needle || contains (index + 1))
     in
     contains 0);
  let native = Binding_enum_implicit_codegen.render_static_asserts selected in
  assert (String.length native > 1000);
  let malformed =
    match inventory () with
    | first :: rest -> { first with header = "Metal/Wrong.h" } :: rest
    | [] -> assert false
  in
  assert
    (match Binding_enum_implicit_codegen.select malformed with
     | exception Binding_enum_implicit_codegen.Error _ -> true
     | _ -> false);
  if Array.length Sys.argv = 2 then begin
    let selected =
      Binding_enum_implicit_codegen.select (inventory_file Sys.argv.(1))
    in
    assert (Binding_enum_implicit_codegen.declaration_count selected = 37)
  end else if Array.length Sys.argv <> 1 then
    failwith "usage: test_binding_enum_implicit [generated_api_inventory.json]"
