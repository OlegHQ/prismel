type field =
  { id : string
  ; owner : string
  ; name : string
  ; objc_type : string
  }

type record =
  { id : string
  ; name : string
  ; header : string
  ; introduced : string option
  ; fields : field list
  }

type selection =
  { records : record list
  ; ids : string list
  }

let expected_record_count = 27
let expected_field_count = 108
let expected_id_count = 135

let fail format = Printf.ksprintf (fun message -> invalid_arg ("Metal value-record plan: " ^ message)) format

let member name = function
  | `Assoc members -> List.assoc_opt name members
  | _ -> None

let string_member name value =
  match member name value with
  | Some (`String text) -> text
  | _ -> fail "missing string member %s" name

let optional_string_member name value =
  match member name value with
  | Some (`String text) -> Some text
  | Some `Null | None -> None
  | _ -> fail "invalid optional string member %s" name

let public_record name =
  not
    (List.mem name
       [ "MTLSharedEventHandlePrivate"
       ; "MTLSharedTextureHandlePrivate"
       ; "_CAMetalLayerPrivate"
       ; "_MTLPackedFloat3" (* anonymous union exposes elements and x/y/z aliases *)
       ])

let fixed_field_type = function
  | "MTLGPUAddress" | "NSUInteger" | "uint64_t" | "uint32_t" | "uint16_t" | "float"
  | "MTLAccelerationStructureInstanceOptions" | "MTLMotionBorderMode"
  | "MTLPackedFloat3" | "MTLPackedFloatQuaternion" | "MTLPackedFloat4x3"
  | "MTLResourceID" | "MTLOrigin" | "MTLRegion" | "NSRange"
  | "uint32_t[3]" | "uint16_t[2]" | "uint16_t[3]" | "uint16_t[4]"
  | "MTLPackedFloat3[4]" -> true
  | _ -> false

let select json =
  let symbols =
    match member "symbols" json with
    | Some (`List symbols) -> symbols
    | _ -> fail "inventory has no symbols array"
  in
  let unreviewed symbol = String.equal (string_member "classification" symbol) "unreviewed" in
  let fields = Hashtbl.create expected_record_count in
  List.iter
    (fun symbol ->
      if String.equal (string_member "kind" symbol) "field" && unreviewed symbol then
        let owner = string_member "owner" symbol in
        let objc_type = string_member "signature" symbol in
        if public_record owner then begin
          if not (fixed_field_type objc_type) then
            fail "unsupported field type %s for %s" objc_type (string_member "id" symbol);
          let field =
            { id = string_member "id" symbol
            ; owner
            ; name = string_member "name" symbol
            ; objc_type
            }
          in
          Hashtbl.replace fields owner (field :: Option.value ~default:[] (Hashtbl.find_opt fields owner))
        end)
    symbols;
  let records =
    List.filter_map
      (fun symbol ->
        if String.equal (string_member "kind" symbol) "record" && unreviewed symbol then
          let name = string_member "name" symbol in
          if public_record name then
            match Hashtbl.find_opt fields name with
            | Some fields ->
                Some
                  { id = string_member "id" symbol
                  ; name
                  ; header = string_member "header" symbol
                  ; introduced = optional_string_member "macos_introduced" symbol
                  ; fields =
                      List.sort
                        (fun (left : field) (right : field) -> String.compare left.id right.id)
                        fields
                  }
            | None -> fail "public record %s has no fixed fields" name
          else None
        else None)
      symbols
    |> List.sort (fun (left : record) (right : record) -> String.compare left.id right.id)
  in
  let ids =
    List.concat_map
      (fun (record : record) ->
        record.id :: List.map (fun (field : field) -> field.id) record.fields)
      records
  in
  if List.length records <> expected_record_count then
    fail "record cardinality drift: expected %d, got %d" expected_record_count (List.length records);
  if List.length ids <> expected_id_count then
    fail "identifier cardinality drift: expected %d, got %d" expected_id_count (List.length ids);
  let field_count = List.fold_left (fun count record -> count + List.length record.fields) 0 records in
  if field_count <> expected_field_count then
    fail "field cardinality drift: expected %d, got %d" expected_field_count field_count;
  { records; ids }
