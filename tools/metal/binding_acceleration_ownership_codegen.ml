open Binding_acceleration_ownership_plan
let snake value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri (fun index c -> if index > 0 && c >= 'A' && c <= 'Z' then Buffer.add_char output '_'; Buffer.add_char output (Char.lowercase_ascii c)) value;
  Buffer.contents output
let type_ = function
  | Borrowed_buffer -> "'buffer option" | Copied_string -> "string option"
  | Copied_retained_array -> "'element list" | Buffer_range -> "'buffer buffer_range"
  | Resource_id -> "int64"
let render_safe_schema selection =
  let output = Buffer.create 12000 in
  Buffer.add_string output "type 'buffer buffer_range = private { buffer : 'buffer; offset : int64; length : int64 }\n";
  List.iter (fun owner ->
    let fields = List.filter (fun value -> value.property.owner = Some owner) selection.properties in
    Printf.bprintf output "type ('buffer, 'element) %s = private {\n" (snake owner);
    List.iter (fun value -> Printf.bprintf output "  %s : %s;\n" (snake value.property.name) (type_ value.ownership)) fields;
    Buffer.add_string output "}\n") selection.owners;
  Buffer.contents output
let render_native_contract selection =
  let output = Buffer.create 16000 in
  List.iter (fun value ->
    let policy = match value.ownership with Borrowed_buffer -> "retain OCaml buffer owner through call" | Copied_string -> "copy UTF-8 before autorelease exit" | Copied_retained_array -> "copy NSArray, retain each child, unwind every +1" | Buffer_range -> "retain range buffer and validate offset/length" | Resource_id -> "copy fixed resource identifier" in
    Printf.bprintf output "%s\t%s\n" value.property.id policy) selection.properties;
  Buffer.contents output
