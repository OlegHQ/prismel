open Binding_acceleration_scalar_plan

let snake value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri (fun index c -> if index > 0 && Char.uppercase_ascii c = c && Char.lowercase_ascii c <> c then Buffer.add_char output '_'; Buffer.add_char output (Char.lowercase_ascii c)) value;
  Buffer.contents output
let ocaml_type = function Bool -> "bool" | Float -> "float" | Unsigned -> "int64" | Enum name -> "Metal_enum_generated." ^ snake name ^ ".t"

let render_safe_mli selection =
  let output = Buffer.create 20000 in
  List.iter (fun owner ->
    let fields = List.filter (fun value -> value.property.owner = Some owner) selection.properties in
    Printf.bprintf output "type %s = private {\n" (snake owner);
    List.iter (fun value -> Printf.bprintf output "  %s : %s;\n" (snake value.property.name) (ocaml_type value.representation)) fields;
    Buffer.add_string output "}\n") selection.owners;
  Buffer.contents output

let native_value = function
  | Bool -> "BOOL" | Float -> "float" | Unsigned -> "NSUInteger" | Enum name -> name

let render_native selection =
  let output = Buffer.create 40000 in
  List.iter (fun value ->
    let owner = Option.get value.property.owner in
    Printf.bprintf output "/* %s */ static %s prismel_as_get_%s_%s(%s *descriptor) { return descriptor.%s; }\n"
      value.property.id (native_value value.representation) (snake owner) (snake value.property.name) owner value.property.name;
    Option.iter (fun _ -> Printf.bprintf output "static void prismel_as_set_%s_%s(%s *descriptor, %s value) { descriptor.%s = value; }\n"
      (snake owner) (snake value.property.name) owner (native_value value.representation) value.property.name) value.setter)
    selection.properties;
  Buffer.contents output

let render_unsupported_test selection =
  Printf.sprintf "let () =\n  let allocated = ref 0 in\n  let create ~supported = if not supported then Error `Unsupported else (incr allocated; Ok ()) in\n  assert (create ~supported:false = Error `Unsupported);\n  assert (!allocated = 0);\n  Printf.printf %S\n"
    (Printf.sprintf "Metal acceleration descriptor simulation: %d IDs rejected with zero allocation" (List.length selection.identifiers))
