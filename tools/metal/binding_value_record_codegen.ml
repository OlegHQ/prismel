type output =
  { ocaml_ml : string
  ; ocaml_mli : string
  ; native_checks : string
  }

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

let module_name value =
  let value = if String.length value > 0 && value.[0] = '_' then String.sub value 1 (String.length value - 1) else value in
  value

let ocaml_type = function
  | "float" -> "float"
  | "uint32_t" -> "int32"
  | "uint16_t" -> "int"
  | "MTLGPUAddress" | "NSUInteger" | "uint64_t"
  | "MTLAccelerationStructureInstanceOptions" | "MTLMotionBorderMode" -> "int64"
  | "uint32_t[3]" -> "int32 * int32 * int32"
  | "uint16_t[2]" -> "int * int"
  | "uint16_t[3]" -> "int * int * int"
  | "uint16_t[4]" -> "int * int * int * int"
  | "MTLPackedFloat3[4]" ->
      "(float * float * float) * (float * float * float) * (float * float * float) * (float * float * float)"
  | "NSRange" -> "int64 * int64"
  | "MTLPackedFloat3" -> "float * float * float"
  | "MTLPackedFloatQuaternion" -> "float * float * float * float"
  | "MTLPackedFloat4x3" ->
      "(float * float * float) * (float * float * float) * (float * float * float) * (float * float * float)"
  | "MTLResourceID" -> "int64"
  | "MTLOrigin" -> "int64 * int64 * int64"
  | "MTLRegion" -> "(int64 * int64 * int64) * (int64 * int64 * int64)"
  | objc_type -> invalid_arg ("unsupported generated Metal value-record field: " ^ objc_type)

let emit_record buffer (record : Binding_value_record_plan.record) =
  Printf.bprintf buffer "module %s = struct\n  type t =\n    { " (module_name record.name);
  List.iteri
    (fun index (field : Binding_value_record_plan.field) ->
      if index > 0 then Buffer.add_string buffer "    ; ";
      Printf.bprintf buffer "%s : %s\n" (snake field.name) (ocaml_type field.objc_type))
    record.fields;
  Buffer.add_string buffer "    }\nend\n\n"

let emit_checks buffer (record : Binding_value_record_plan.record) =
  Printf.bprintf buffer "static_assert(std::is_standard_layout_v<%s>);\n" record.name;
  Printf.bprintf buffer "static_assert(sizeof(%s) > 0);\n" record.name;
  Printf.bprintf buffer "static_assert(alignof(%s) > 0);\n" record.name;
  List.iter
    (fun (field : Binding_value_record_plan.field) ->
      Printf.bprintf buffer
        "static_assert(offsetof(%s, %s) + sizeof(((%s *)nullptr)->%s) <= sizeof(%s));\n"
        record.name field.name record.name field.name record.name)
    record.fields;
  Buffer.add_char buffer '\n'

let generate (selection : Binding_value_record_plan.selection) =
  let ocaml = Buffer.create 32768 in
  let native = Buffer.create 32768 in
  Buffer.add_string ocaml "(* Generated fixed-layout Metal value records. Do not edit. *)\n\n";
  Buffer.add_string native "// Generated fixed-layout Metal ABI checks. Do not edit.\n#include <Metal/Metal.h>\n#include <cstddef>\n#include <type_traits>\n\n";
  List.iter (emit_record ocaml) selection.records;
  List.iter (emit_checks native) selection.records;
  let text = Buffer.contents ocaml in
  { ocaml_ml = text; ocaml_mli = text; native_checks = Buffer.contents native }
