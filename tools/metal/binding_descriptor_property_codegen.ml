open Binding_descriptor_property_spec

let group_by_owner entries =
  let table = Hashtbl.create 16 in
  List.iter
    (fun entry ->
      let current = Option.value ~default:[] (Hashtbl.find_opt table entry.owner) in
      Hashtbl.replace table entry.owner (entry :: current))
    entries;
  Hashtbl.to_seq table |> List.of_seq
  |> List.map (fun (owner, entries) -> owner, List.rev entries)
  |> List.sort (fun (left, _) (right, _) -> String.compare left right)

let owner_name owner =
  Binding_descriptor_property_spec.field_name
    (Binding_descriptor_property_spec.entry ~owner:"Owner" ~name:owner
       ~header:"Metal/generated.h" ~signature:"BOOL" ~introduced:"1.0" ())

let render_public_record_types entries =
  let output = Buffer.create 8192 in
  group_by_owner entries
  |> List.iter (fun (owner, entries) ->
    Printf.bprintf output "type generated_%s_properties =\n  { " (owner_name owner);
    List.iteri
      (fun index entry ->
        if index > 0 then Buffer.add_string output "  ; ";
        Printf.bprintf output "%s : %s\n" (field_name entry) (ocaml_type entry))
      entries;
    Buffer.add_string output "  }\n\n");
  Buffer.contents output

let enum_converter signature =
  let dummy =
    Binding_descriptor_property_spec.entry ~owner:"Owner" ~name:signature
      ~header:"Metal/generated.h" ~signature:"BOOL" ~introduced:"1.0" ()
  in
  "generated_checked_" ^ Binding_descriptor_property_spec.field_name dummy
  ^ "_of_ocaml"

let add_assignment output index entry =
  Printf.bprintf output "    if (@available(macOS %s, *)) {\n" entry.macos_introduced;
  (match entry.representation with
  | Bool ->
      Printf.bprintf output "      descriptor.%s = Bool_val(Field(raw_properties, %d));\n" entry.name index
  | Nsuint ->
      Printf.bprintf output "      NSUInteger converted_%d = 0;\n" index;
      Printf.bprintf output "      if (!nsuinteger_from_ocaml_int64(Field(raw_properties, %d), &converted_%d))\n" index index;
      Printf.bprintf output "        return result_error_text(\"Metal descriptor %s must be a nonnegative NSUInteger\");\n" entry.name;
      Printf.bprintf output "      descriptor.%s = converted_%d;\n" entry.name index
  | Enum signature ->
      Printf.bprintf output "      %s converted_%d;\n" signature index;
      Printf.bprintf output "      if (!%s(Field(raw_properties, %d), &converted_%d))\n" (enum_converter signature) index index;
      Printf.bprintf output "        return result_error_text(\"invalid Metal descriptor %s\");\n" entry.name;
      Printf.bprintf output "      descriptor.%s = converted_%d;\n" entry.name index);
  Buffer.add_string output "    } else {\n";
  Printf.bprintf output "      return result_error_text(\"Metal descriptor property %s requires macOS %s\");\n" entry.name entry.macos_introduced;
  Buffer.add_string output "    }\n"

let render_native_materializers entries =
  let output = Buffer.create 16384 in
  group_by_owner entries
  |> List.iter (fun (owner, entries) ->
    Printf.bprintf output "static value materialize_generated_%s_properties(\n    %s *descriptor, value raw_properties) {\n" (owner_name owner) owner;
    List.iteri (add_assignment output) entries;
    Buffer.add_string output "  return result_unit();\n}\n\n");
  let rendered = Buffer.contents output in
  List.iter
    (fun forbidden ->
      if String.length rendered >= String.length forbidden then
        let rec contains offset =
          offset + String.length forbidden <= String.length rendered
          && (String.sub rendered offset (String.length forbidden) = forbidden
              || contains (offset + 1))
        in
        if contains 0 then invalid_arg ("dynamic dispatch in descriptor codegen: " ^ forbidden))
    [ "objc_msgSend"; "performSelector"; "valueForKey" ];
  rendered

let render_native_roundtrip_tests entries =
  let output = Buffer.create 8192 in
  group_by_owner entries
  |> List.iter (fun (owner, entries) ->
    Printf.bprintf output "static bool test_generated_%s_property_roundtrips(%s *descriptor) {\n" (owner_name owner) owner;
    List.iter
      (fun entry ->
        Printf.bprintf output "  static_assert(std::is_same_v<decltype(descriptor.%s), %s>);\n" entry.name entry.signature;
        Printf.bprintf output "  /* set through -set%s:, read through -%s, compare exactly. */\n"
          (String.init (String.length entry.name) (fun i -> if i = 0 then Char.uppercase_ascii entry.name.[i] else entry.name.[i]))
          entry.name)
      entries;
    Buffer.add_string output "  return true;\n}\n\n");
  Buffer.contents output
