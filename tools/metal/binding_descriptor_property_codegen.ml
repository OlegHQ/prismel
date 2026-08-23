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

let add_record_fields output entries =
  List.iteri
    (fun index entry ->
      if index > 0 then Buffer.add_string output "  ; ";
      Printf.bprintf output "%s : %s\n" (field_name entry) (ocaml_type entry))
    entries

let add_make_arguments output entries =
  List.iter
    (fun entry ->
      Printf.bprintf output " ?(%s = default.%s)" (field_name entry)
        (field_name entry))
    entries

let render_public_mli entries =
  let output = Buffer.create 12288 in
  Buffer.add_string output
    "module Resource_options : sig\n  type cpu_cache = Default_cache | Write_combined\n  type storage = Shared | Managed | Private | Memoryless\n  type hazard_tracking = Default | Tracked | Untracked\n  type t = private int64\n  val make : cpu_cache:cpu_cache -> storage:storage -> hazard_tracking:hazard_tracking -> t\n  val to_int64 : t -> int64\nend\n\n";
  group_by_owner entries
  |> List.iter (fun (owner, entries) ->
    Printf.bprintf output "module %s : sig\n  type t = private\n    { "
      (String.capitalize_ascii (owner_name owner));
    add_record_fields output entries;
    Buffer.add_string output "    }\n  val default : t\n  val make :";
    List.iter
      (fun entry ->
        Printf.bprintf output " ?%s:%s ->" (field_name entry) (ocaml_type entry))
      entries;
    Buffer.add_string output " unit -> (t, string) result\nend\n\n");
  Buffer.contents output

let render_public_ml entries =
  let output = Buffer.create 24576 in
  Buffer.add_string output
    "module Resource_options = struct\n  type cpu_cache = Default_cache | Write_combined\n  type storage = Shared | Managed | Private | Memoryless\n  type hazard_tracking = Default | Tracked | Untracked\n  type t = int64\n  let cpu_cache_bits = function Default_cache -> 0L | Write_combined -> 1L\n  let storage_bits = function Shared -> 0L | Managed -> 16L | Private -> 32L | Memoryless -> 48L\n  let hazard_bits = function Default -> 0L | Tracked -> 256L | Untracked -> 512L\n  let make ~cpu_cache ~storage ~hazard_tracking = Int64.logor (cpu_cache_bits cpu_cache) (Int64.logor (storage_bits storage) (hazard_bits hazard_tracking))\n  let to_int64 value = value\n  let of_bits_exn = function 0L | 1L | 16L | 17L | 32L | 33L | 48L | 49L | 256L | 257L | 272L | 273L | 288L | 289L | 304L | 305L | 512L | 513L | 528L | 529L | 544L | 545L | 560L | 561L as value -> value | value -> invalid_arg (Printf.sprintf \"invalid MTLResourceOptions bits: %Ld\" value)\nend\n\n";
  group_by_owner entries
  |> List.iter (fun (owner, entries) ->
    Printf.bprintf output "module %s = struct\n  type t =\n    { "
      (String.capitalize_ascii (owner_name owner));
    add_record_fields output entries;
    Buffer.add_string output "    }\n\n  let default =\n    { ";
    List.iteri
      (fun index entry ->
        if index > 0 then Buffer.add_string output "    ; ";
        Printf.bprintf output "%s = %s\n" (field_name entry)
          (default_expression entry))
      entries;
    Buffer.add_string output "    }\n\n  let make";
    add_make_arguments output entries;
    Buffer.add_string output " () =\n";
    let nsuints =
      List.filter
        (fun entry -> match entry.representation with Nsuint -> true | _ -> false)
        entries
    in
    (match nsuints with
    | [] -> ()
    | _ ->
        Buffer.add_string output "    if ";
        List.iteri
          (fun index entry ->
            if index > 0 then Buffer.add_string output " || ";
            Printf.bprintf output "Int64.compare %s 0L < 0" (field_name entry))
          nsuints;
        Printf.bprintf output
          " then Error %S\n    else\n"
          (owner ^ " NSUInteger properties must be nonnegative"));
    Buffer.add_string output "    Ok\n      { ";
    List.iteri
      (fun index entry ->
        if index > 0 then Buffer.add_string output "      ; ";
        Buffer.add_string output (field_name entry);
        Buffer.add_char output '\n')
      entries;
    Buffer.add_string output "      }\nend\n\n");
  Buffer.contents output

let render_public_tests entries =
  let output = Buffer.create 24576 in
  Buffer.add_string output "open Metal.Descriptor\n\n";
  group_by_owner entries
  |> List.iter (fun (owner, entries) ->
    let module_name = String.capitalize_ascii (owner_name owner) in
    Printf.bprintf output "let test_%s () =\n" (owner_name owner);
    List.iter
      (fun entry ->
        Printf.bprintf output
          "  let value = match %s.make ~%s:%s.default.%s () with Ok value -> value | Error message -> failwith message in\n"
          module_name (field_name entry) module_name (field_name entry);
        Printf.bprintf output
          "  if value.%s <> %s.default.%s then failwith %S;\n"
          (field_name entry) module_name (field_name entry)
          ("descriptor construction mismatch: " ^ property_sdk_id entry);
        match entry.representation with
        | Nsuint ->
            Printf.bprintf output
              "  (match %s.make ~%s:(-1L) () with Error _ -> () | Ok _ -> failwith %S);\n"
              module_name (field_name entry)
              ("descriptor range validation missing: " ^ property_sdk_id entry)
        | Bool | Enum _ | Flags _ | Resource_options -> ())
      entries;
    Buffer.add_string output "  ()\n\n");
  Buffer.add_string output "let () =\n";
  group_by_owner entries
  |> List.iter (fun (owner, _) ->
    Printf.bprintf output "  test_%s ();\n" (owner_name owner));
  Buffer.add_string output
    "  Printf.printf \"Metal descriptor generated construction tests passed\\n\"\n";
  Buffer.contents output

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
      Printf.bprintf output
        "      %s converted_%d = static_cast<%s>(Int64_val(Field(raw_properties, %d)));\n"
        signature index signature index;
      Printf.bprintf output "      descriptor.%s = converted_%d;\n" entry.name index
  | Flags signature ->
      Printf.bprintf output "      %s converted_%d = (%s)0;\n" signature index signature;
      Printf.bprintf output "      value cursor_%d = Field(raw_properties, %d);\n" index index;
      Printf.bprintf output "      while (cursor_%d != Val_emptylist) {\n" index;
      Printf.bprintf output
        "        converted_%d = static_cast<%s>(static_cast<uint64_t>(converted_%d) | static_cast<uint64_t>(Int64_val(Field(cursor_%d, 0))));\n"
        index signature index index;
      Printf.bprintf output
        "        cursor_%d = Field(cursor_%d, 1);\n      }\n" index index;
      Printf.bprintf output "      descriptor.%s = converted_%d;\n" entry.name index
  | Resource_options ->
      Printf.bprintf output "      descriptor.%s = (MTLResourceOptions)Int64_val(Field(raw_properties, %d));\n" entry.name index);
  (match entry.representation with
  | Bool ->
      Printf.bprintf output
        "      if (descriptor.%s != (Bool_val(Field(raw_properties, %d)) != 0)) return result_error_text(\"Metal descriptor %s round-trip mismatch\");\n"
        entry.name index entry.name
  | Nsuint | Enum _ | Flags _ ->
      Printf.bprintf output
        "      if (descriptor.%s != converted_%d) return result_error_text(\"Metal descriptor %s round-trip mismatch\");\n"
        entry.name index entry.name
  | Resource_options ->
      Printf.bprintf output
        "      if (descriptor.%s != (MTLResourceOptions)Int64_val(Field(raw_properties, %d))) return result_error_text(\"Metal descriptor %s round-trip mismatch\");\n"
        entry.name index entry.name);
  Buffer.add_string output "    } else {\n";
  Printf.bprintf output "      return result_error_text(\"Metal descriptor property %s requires macOS %s\");\n" entry.name entry.macos_introduced;
  Buffer.add_string output "    }\n"

let render_native_materializers entries =
  let output = Buffer.create 16384 in
  group_by_owner entries
  |> List.iter (fun (owner, entries) ->
    if String.starts_with ~prefix:"MTL4" owner then
      Buffer.add_string output "API_AVAILABLE(macos(26.0))\n";
    Printf.bprintf output "[[maybe_unused]] static value materialize_generated_%s_properties(\n    %s *descriptor, value raw_properties) {\n" (owner_name owner) owner;
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
    if String.starts_with ~prefix:"MTL4" owner then
      Buffer.add_string output "API_AVAILABLE(macos(26.0))\n";
    Printf.bprintf output "static bool test_generated_%s_property_roundtrips(%s *descriptor) {\n" (owner_name owner) owner;
    List.iter
      (fun entry ->
        Printf.bprintf output "  if (@available(macOS %s, *)) {\n"
          entry.macos_introduced;
        Printf.bprintf output
          "    static_assert(std::is_same_v<decltype(descriptor.%s), %s>);\n"
          entry.name entry.signature;
        Printf.bprintf output "    %s original_%s = descriptor.%s;\n"
          entry.signature (field_name entry) entry.name;
        (match entry.representation with
        | Bool ->
            Printf.bprintf output "    %s test_%s = !original_%s;\n"
              entry.signature (field_name entry) (field_name entry)
        | Nsuint ->
            Printf.bprintf output
              "    %s test_%s = original_%s == NSUIntegerMax ? 0 : original_%s + 1;\n"
              entry.signature (field_name entry) (field_name entry)
              (field_name entry)
        | Enum _ | Flags _ | Resource_options ->
            Printf.bprintf output "    %s test_%s = original_%s;\n"
              entry.signature (field_name entry) (field_name entry));
        Printf.bprintf output "    descriptor.%s = test_%s;\n" entry.name
          (field_name entry);
        Printf.bprintf output "    if (descriptor.%s != test_%s) return false;\n"
          entry.name (field_name entry);
        Printf.bprintf output "    descriptor.%s = original_%s;\n  }\n"
          entry.name (field_name entry))
      entries;
    Buffer.add_string output "  return true;\n}\n\n");
  Buffer.contents output

let render_native_conformance_executable entries =
  let output = Buffer.create 32768 in
  Buffer.add_string output
    "#import <Foundation/Foundation.h>\n#import <Metal/Metal.h>\n#include <type_traits>\n\n";
  Buffer.add_string output (render_native_roundtrip_tests entries);
  Buffer.add_string output "int main() { @autoreleasepool {\n  bool ok = true;\n";
  group_by_owner entries
  |> List.iter (fun (owner, _) ->
    let constructor =
      if owner = "MTLRenderPassAttachmentDescriptor" then
        "[MTLRenderPassDepthAttachmentDescriptor new]"
      else "[" ^ owner ^ " new]"
    in
    let call =
      Printf.sprintf
        "test_generated_%s_property_roundtrips(%s)" (owner_name owner)
        constructor
    in
    if String.starts_with ~prefix:"MTL4" owner then
      Printf.bprintf output
        "  if (@available(macOS 26.0, *)) ok &= %s;\n" call
    else Printf.bprintf output "  ok &= %s;\n" call);
  Buffer.add_string output
    "  printf(\"Metal descriptor native roundtrips: %s\\n\", ok ? \"passed\" : \"FAILED\");\n  return ok ? 0 : 1;\n} }\n";
  Buffer.contents output
