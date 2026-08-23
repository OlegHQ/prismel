open Binding_acceleration_ownership_plan
let snake value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri (fun index c -> if index > 0 && c >= 'A' && c <= 'Z' then Buffer.add_char output '_'; Buffer.add_char output (Char.lowercase_ascii c)) value;
  Buffer.contents output
let type_ = function
  | Borrowed_buffer -> "'buffer option" | Copied_string -> "string option"
  | Copied_retained_array -> "'element list" | Buffer_range -> "'buffer buffer_range"
  | Resource_id -> "int64"
let render_types ~private_ selection =
  let output = Buffer.create 12000 in
  Printf.bprintf output "type 'buffer buffer_range = %s{ buffer : 'buffer; offset : int64; length : int64 }\n"
    (if private_ then "private " else "");
  if private_ then Buffer.add_string output "val make_buffer_range : buffer:'buffer -> offset:int64 -> length:int64 -> 'buffer buffer_range\n"
  else Buffer.add_string output "let make_buffer_range ~buffer ~offset ~length = if offset < 0L || length < 0L || offset > Int64.sub Int64.max_int length then invalid_arg \"Metal acceleration buffer range is invalid\"; { buffer; offset; length }\n";
  List.iter (fun owner ->
    let fields = List.filter (fun value -> value.property.owner = Some owner) selection.properties in
    let name = snake owner ^ "_ownership" in
    Printf.bprintf output "type ('buffer, 'element) %s = %s{\n" name (if private_ then "private " else "");
    List.iter (fun value -> Printf.bprintf output "  %s : %s;\n" (snake value.property.name) (type_ value.ownership)) fields;
    Buffer.add_string output "}\n";
    if private_ then begin
      Printf.bprintf output "val make_%s :\n" name;
      List.iter (fun value -> Printf.bprintf output "  %s:%s ->\n" (snake value.property.name) (type_ value.ownership)) fields;
      Printf.bprintf output "  unit -> ('buffer, 'element) %s\n" name
    end else begin
      Printf.bprintf output "let make_%s" name;
      List.iter (fun value -> Printf.bprintf output " ~%s" (snake value.property.name)) fields;
      Printf.bprintf output " () = { %s }\n"
        (fields |> List.map (fun value -> snake value.property.name) |> String.concat "; ")
    end) selection.owners;
  Buffer.contents output
let render_safe_schema = render_types ~private_:true
let render_safe_ml = render_types ~private_:false
let render_safe_mli = render_types ~private_:true
let render_native_contract selection =
  let output = Buffer.create 16000 in
  List.iter (fun value ->
    let policy = match value.ownership with Borrowed_buffer -> "retain OCaml buffer owner through call" | Copied_string -> "copy UTF-8 before autorelease exit" | Copied_retained_array -> "copy NSArray, retain each child, unwind every +1" | Buffer_range -> "retain range buffer and validate offset/length" | Resource_id -> "copy fixed resource identifier" in
    Printf.bprintf output "%s\t%s\n" value.property.id policy) selection.properties;
  Buffer.contents output
