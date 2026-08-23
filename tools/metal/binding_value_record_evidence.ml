let expected_layout_digest = "06b744b336313eaab9e3e47d2a407ab3"

let is_bound_identifier identifier =
  List.exists
    (fun name ->
      String.equal identifier ("record:" ^ name)
      || String.starts_with ~prefix:("field:" ^ name ^ ":") identifier)
    Binding_value_record_plan.record_names

let fail format =
  Printf.ksprintf
    (fun message -> invalid_arg ("Metal value-record evidence: " ^ message))
    format

let contains needle haystack =
  let needle_length = String.length needle in
  let haystack_length = String.length haystack in
  let rec search offset =
    offset + needle_length <= haystack_length
    && (String.sub haystack offset needle_length = needle || search (offset + 1))
  in
  search 0

let snake value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri
    (fun index character ->
      if Char.uppercase_ascii character = character
         && Char.lowercase_ascii character <> character
      then begin
        if index > 0 then Buffer.add_char output '_';
        Buffer.add_char output (Char.lowercase_ascii character)
      end else Buffer.add_char output character)
    value;
  Buffer.contents output

let public_name name =
  if String.length name > 0 && name.[0] = '_' then
    String.sub name 1 (String.length name - 1)
  else name

let public_marker (record : Binding_value_record_plan.record) =
  "module " ^ public_name record.name

let test_marker (record : Binding_value_record_plan.record) =
  "test_metal_value_record_" ^ snake (public_name record.name)

let layout_digest (selection : Binding_value_record_plan.selection) =
  let canonical = Buffer.create 16384 in
  List.iter
    (fun (record : Binding_value_record_plan.record) ->
      Printf.bprintf canonical "R\t%s\t%s\t%s\t%s\n" record.id record.name
        record.header (Option.value ~default:"-" record.introduced);
      List.iter
        (fun (field : Binding_value_record_plan.field) ->
          Printf.bprintf canonical "F\t%s\t%s\t%s\t%s\n" field.id field.owner
            field.name field.objc_type)
        record.fields)
    selection.records;
  Digest.string (Buffer.contents canonical) |> Digest.to_hex

let require_markers ~kind markers source =
  List.iter
    (fun marker ->
      if not (contains marker source) then fail "missing %s marker %s" kind marker)
    markers

let bound_ids ~inventory ~public_interface ~test_source =
  let selection = Binding_value_record_plan.select inventory in
  let digest = layout_digest selection in
  if not (String.equal digest expected_layout_digest) then
    fail "layout digest drift: expected %s, got %s" expected_layout_digest digest;
  require_markers ~kind:"public" (List.map public_marker selection.records)
    public_interface;
  require_markers ~kind:"test" (List.map test_marker selection.records) test_source;
  selection.ids

let () =
  if List.length Binding_value_record_plan.record_names <> Binding_value_record_plan.expected_record_count then
    invalid_arg "Metal value-record evidence family cardinality drift"
