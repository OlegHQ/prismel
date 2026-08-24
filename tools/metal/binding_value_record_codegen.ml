type output =
  { ocaml_ml : string
  ; ocaml_mli : string
  ; test_ml : string
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
  | "float[3]" -> "float * float * float"
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
  | "MTLOrigin" | "MTLSize" -> "int64 * int64 * int64"
  | "MTLRegion" -> "(int64 * int64 * int64) * (int64 * int64 * int64)"
  | objc_type -> invalid_arg ("unsupported generated Metal value-record field: " ^ objc_type)

let emit_record ~interface buffer (record : Binding_value_record_plan.record) =
  Printf.bprintf buffer "module %s %s\n  type t =\n    { " (module_name record.name)
    (if interface then ": sig" else "= struct");
  List.iteri
    (fun index (field : Binding_value_record_plan.field) ->
      if index > 0 then Buffer.add_string buffer "    ; ";
      Printf.bprintf buffer "%s : %s\n" (snake field.name) (ocaml_type field.objc_type))
    record.fields;
  Buffer.add_string buffer "    }\nend\n\n"

let zero = function
  | "float" -> "0.0"
  | "uint32_t" -> "0l"
  | "uint16_t" -> "0"
  | "MTLGPUAddress" | "NSUInteger" | "uint64_t"
  | "MTLAccelerationStructureInstanceOptions" | "MTLMotionBorderMode"
  | "MTLResourceID" -> "0L"
  | "uint32_t[3]" -> "0l, 0l, 0l"
  | "float[3]" -> "0.0, 0.0, 0.0"
  | "uint16_t[2]" -> "0, 0"
  | "uint16_t[3]" -> "0, 0, 0"
  | "uint16_t[4]" -> "0, 0, 0, 0"
  | "NSRange" -> "0L, 0L"
  | "MTLPackedFloat3" -> "0.0, 0.0, 0.0"
  | "MTLOrigin" | "MTLSize" -> "0L, 0L, 0L"
  | "MTLPackedFloatQuaternion" -> "0.0, 0.0, 0.0, 0.0"
  | "MTLPackedFloat4x3" | "MTLPackedFloat3[4]" ->
      "(0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)"
  | "MTLRegion" -> "(0L, 0L, 0L), (0L, 0L, 0L)"
  | objc_type -> invalid_arg ("unsupported generated Metal value-record zero: " ^ objc_type)

let emit_test buffer (record : Binding_value_record_plan.record) =
  let module_name = module_name record.name in
  Printf.bprintf buffer "let test_metal_value_record_%s () =\n" (snake module_name);
  Printf.bprintf buffer "  let value : Metal.Value.%s.t =\n    { " module_name;
  List.iteri
    (fun index (field : Binding_value_record_plan.field) ->
      if index > 0 then Buffer.add_string buffer "    ; ";
      Printf.bprintf buffer "%s = (%s)\n" (snake field.name) (zero field.objc_type))
    record.fields;
  Buffer.add_string buffer "    }\n  in\n";
  List.iter
    (fun (field : Binding_value_record_plan.field) ->
      Printf.bprintf buffer "  if value.%s <> (%s) then failwith %S;\n"
        (snake field.name) (zero field.objc_type) field.id)
    record.fields;
  Buffer.add_string buffer "  ()\n\n"

let emit_checks buffer (record : Binding_value_record_plan.record) =
  Printf.bprintf buffer "static_assert(std::is_standard_layout_v<%s>);\n" record.name;
  Printf.bprintf buffer "static_assert(sizeof(%s) > 0);\n" record.name;
  Printf.bprintf buffer "static_assert(alignof(%s) > 0);\n" record.name;
  List.iter
    (fun (field : Binding_value_record_plan.field) ->
      Printf.bprintf buffer
        "static_assert(std::is_same_v<std::remove_reference_t<decltype(((%s *)nullptr)->%s)>, %s>);\n"
        record.name field.name field.objc_type;
      Printf.bprintf buffer
        "static_assert(offsetof(%s, %s) + sizeof(((%s *)nullptr)->%s) <= sizeof(%s));\n"
        record.name field.name record.name field.name record.name)
    record.fields;
  Buffer.add_char buffer '\n'

let generate (selection : Binding_value_record_plan.selection) =
  let ocaml = Buffer.create 32768 in
  let ocaml_mli = Buffer.create 32768 in
  let tests = Buffer.create 32768 in
  let native = Buffer.create 32768 in
  Buffer.add_string ocaml "(* Generated fixed-layout Metal value records. Do not edit. *)\n\n";
  Buffer.add_string ocaml_mli "(* Generated fixed-layout Metal value records. Do not edit. *)\n\n";
  Buffer.add_string tests "(* Generated exhaustive Metal value-record tests. Do not edit. *)\n\n";
  Buffer.add_string native
    "// Generated fixed-layout Metal ABI checks. Do not edit.\n#include <Metal/Metal.h>\n#include <cstddef>\n#include <type_traits>\n#pragma clang diagnostic push\n#pragma clang diagnostic ignored \"-Wunguarded-availability-new\"\n\n";
  List.iter (emit_record ~interface:false ocaml) selection.records;
  List.iter (emit_record ~interface:true ocaml_mli) selection.records;
  Buffer.add_string ocaml
    "let packed_float3_make x y z : MTLPackedFloat3.t =\n  { elements = (x, y, z); x; y; z }\n\nlet packed_float_quaternion_make x y z w : MTLPackedFloatQuaternion.t =\n  { w; x; y; z }\n\n";
  Buffer.add_string ocaml_mli
    "val packed_float3_make : float -> float -> float -> MTLPackedFloat3.t\nval packed_float_quaternion_make : float -> float -> float -> float -> MTLPackedFloatQuaternion.t\n\n";
  Buffer.add_string ocaml
    "module MTLArgumentAccess = struct type t = int64 let of_int64 x = x let to_int64 x = x end\nmodule MTLIndexType = struct type t = int64 let of_int64 x = x let to_int64 x = x end\nmodule MTLTimestamp = struct type t = int64 let of_int64 x = x let to_int64 x = x end\nmodule MTLCoordinate2D = struct type t = MTLSamplePosition.t end\n\nlet buffer_range_make buffer_address length : MTL4BufferRange.t = { buffer_address; length }\nlet coordinate2d_make x y : MTLCoordinate2D.t = { x; y }\nlet indirect_command_buffer_execution_range_make location length : MTLIndirectCommandBufferExecutionRange.t = { length; location }\nlet region_make_1d x width : MTLRegion.t = { origin = (x, 0L, 0L); size = (width, 1L, 1L) }\nlet region_make_2d x y width height : MTLRegion.t = { origin = (x, y, 0L); size = (width, height, 1L) }\nlet sample_position_make x y : MTLSamplePosition.t = { x; y }\n\n";
  Buffer.add_string ocaml_mli
    "module MTLArgumentAccess : sig type t = private int64 val of_int64 : int64 -> t val to_int64 : t -> int64 end\nmodule MTLIndexType : sig type t = private int64 val of_int64 : int64 -> t val to_int64 : t -> int64 end\nmodule MTLTimestamp : sig type t = private int64 val of_int64 : int64 -> t val to_int64 : t -> int64 end\nmodule MTLCoordinate2D : sig type t = MTLSamplePosition.t end\n\nval buffer_range_make : int64 -> int64 -> MTL4BufferRange.t\nval coordinate2d_make : float -> float -> MTLCoordinate2D.t\nval indirect_command_buffer_execution_range_make : int32 -> int32 -> MTLIndirectCommandBufferExecutionRange.t\nval region_make_1d : int64 -> int64 -> MTLRegion.t\nval region_make_2d : int64 -> int64 -> int64 -> int64 -> MTLRegion.t\nval sample_position_make : float -> float -> MTLSamplePosition.t\n\n";
  List.iter (emit_test tests) selection.records;
  List.iter (emit_checks native) selection.records;
  Buffer.add_string native
    "static_assert(sizeof(MTLTimestamp) == sizeof(uint64_t));\nstatic_assert(std::is_same_v<decltype(MTL4BufferRangeMake(0, 0)), MTL4BufferRange>);\nstatic_assert(std::is_same_v<decltype(MTLCoordinate2DMake(0, 0)), MTLCoordinate2D>);\nstatic_assert(std::is_same_v<decltype(MTLIndirectCommandBufferExecutionRangeMake(0, 0)), MTLIndirectCommandBufferExecutionRange>);\nstatic_assert(std::is_same_v<decltype(MTLRegionMake1D(0, 0)), MTLRegion>);\nstatic_assert(std::is_same_v<decltype(MTLRegionMake2D(0, 0, 0, 0)), MTLRegion>);\nstatic_assert(std::is_same_v<decltype(MTLSamplePositionMake(0, 0)), MTLSamplePosition>);\n";
  Buffer.add_string native "#pragma clang diagnostic pop\n";
  Buffer.add_string tests "let () =\n";
  List.iter
    (fun (record : Binding_value_record_plan.record) ->
      Printf.bprintf tests "  test_metal_value_record_%s ();\n"
        (snake (module_name record.name)))
    selection.records;
  Buffer.add_string tests
    "  let p = Metal.Value.packed_float3_make 1.0 2.0 3.0 in\n  if p.elements <> (1.0, 2.0, 3.0) || p.x <> 1.0 || p.y <> 2.0 || p.z <> 3.0 then failwith \"MTLPackedFloat3Make\";\n  let q = Metal.Value.packed_float_quaternion_make 1.0 2.0 3.0 4.0 in\n  if (q.x, q.y, q.z, q.w) <> (1.0, 2.0, 3.0, 4.0) then failwith \"MTLPackedFloatQuaternionMake\";\n";
  Buffer.add_string tests
    "  if Metal.Value.MTLArgumentAccess.(to_int64 (of_int64 7L)) <> 7L then failwith \"MTLArgumentAccess\";\n  if Metal.Value.MTLIndexType.(to_int64 (of_int64 1L)) <> 1L then failwith \"MTLIndexType\";\n  if Metal.Value.MTLTimestamp.(to_int64 (of_int64 9L)) <> 9L then failwith \"MTLTimestamp\";\n  let b = Metal.Value.buffer_range_make 4L 8L in if (b.buffer_address, b.length) <> (4L, 8L) then failwith \"MTL4BufferRangeMake\";\n  let c = Metal.Value.coordinate2d_make 1.0 2.0 in if (c.x, c.y) <> (1.0, 2.0) then failwith \"MTLCoordinate2DMake\";\n  let e = Metal.Value.indirect_command_buffer_execution_range_make 3l 5l in if (e.location, e.length) <> (3l, 5l) then failwith \"MTLIndirectCommandBufferExecutionRangeMake\";\n  let r1 = Metal.Value.region_make_1d 2L 7L in if (r1.origin, r1.size) <> ((2L, 0L, 0L), (7L, 1L, 1L)) then failwith \"MTLRegionMake1D\";\n  let r2 = Metal.Value.region_make_2d 2L 3L 7L 8L in if (r2.origin, r2.size) <> ((2L, 3L, 0L), (7L, 8L, 1L)) then failwith \"MTLRegionMake2D\";\n  let s = Metal.Value.sample_position_make 0.25 0.75 in if (s.x, s.y) <> (0.25, 0.75) then failwith \"MTLSamplePositionMake\";\n";
  Printf.bprintf tests "  Printf.printf %S\n"
    "Metal generated value records/types: 29 records + 114 fields + 37 aliases/functions = 180 IDs\n%!";
  { ocaml_ml = Buffer.contents ocaml
  ; ocaml_mli = Buffer.contents ocaml_mli
  ; test_ml = Buffer.contents tests
  ; native_checks = Buffer.contents native
  }
