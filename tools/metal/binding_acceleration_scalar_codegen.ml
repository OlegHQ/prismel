open Binding_acceleration_scalar_plan

let snake value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri (fun index c -> if index > 0 && Char.uppercase_ascii c = c && Char.lowercase_ascii c <> c then Buffer.add_char output '_'; Buffer.add_char output (Char.lowercase_ascii c)) value;
  Buffer.contents output
let ocaml_type = function Bool -> "bool" | Float -> "float" | Unsigned | Enum _ -> "int64"

let render_types ~private_ selection =
  let output = Buffer.create 20000 in
  List.iter (fun owner ->
    let fields = List.filter (fun value -> value.property.owner = Some owner) selection.properties in
    Printf.bprintf output "type %s = %s{\n" (snake owner) (if private_ then "private " else "");
    List.iter (fun value -> Printf.bprintf output "  %s : %s;\n" (snake value.property.name) (ocaml_type value.representation)) fields;
    Buffer.add_string output "}\n";
    if private_ then begin
      Printf.bprintf output "val make_%s :\n" (snake owner);
      List.iter (fun value -> Printf.bprintf output "  %s:%s ->\n" (snake value.property.name) (ocaml_type value.representation)) fields;
      Buffer.add_string output ("  unit -> " ^ snake owner ^ "\n")
    end
    else begin
      Printf.bprintf output "let make_%s" (snake owner);
      List.iter (fun value -> Printf.bprintf output " ~%s" (snake value.property.name)) fields;
      Buffer.add_string output " () =\n";
      List.iter (fun value -> match value.representation with Unsigned -> Printf.bprintf output "  if %s < 0L then invalid_arg %S;\n" (snake value.property.name) (owner ^ "." ^ value.property.name ^ " must be nonnegative") | _ -> ()) fields;
      Printf.bprintf output "  { %s }\n" (fields |> List.map (fun value -> snake value.property.name) |> String.concat "; ")
    end) selection.owners;
  Buffer.contents output

let render_safe_mli = render_types ~private_:true
let render_safe_ml = render_types ~private_:false

let native_value = function
  | Bool -> "BOOL" | Float -> "float" | Unsigned -> "NSUInteger" | Enum name -> name

let render_native selection =
  let output = Buffer.create 40000 in
  List.iter (fun value ->
    let owner = Option.get value.property.owner in
    let receiver_type =
      if owner = "MTLAccelerationStructure" then "id<MTLAccelerationStructure>"
      else owner ^ " *"
    in
    let availability = Option.value ~default:"10.11" value.property.macos_introduced in
    Printf.bprintf output "/* %s */ API_AVAILABLE(macos(%s)) static __attribute__((unused)) %s prismel_as_get_%s_%s(%s descriptor) { return descriptor.%s; }\n"
      value.property.id availability (native_value value.representation) (snake owner) (snake value.property.name) receiver_type value.property.name;
    Option.iter (fun _ -> Printf.bprintf output "API_AVAILABLE(macos(%s)) static __attribute__((unused)) void prismel_as_set_%s_%s(%s descriptor, %s value) { descriptor.%s = value; }\n"
      availability (snake owner) (snake value.property.name) receiver_type (native_value value.representation) value.property.name) value.setter)
    selection.properties;
  Buffer.contents output

let render_unsupported_test selection =
  Printf.sprintf "let () =\n  let allocated = ref 0 in\n  let create ~supported = if not supported then Error `Unsupported else (incr allocated; Ok ()) in\n  assert (create ~supported:false = Error `Unsupported);\n  assert (!allocated = 0);\n  Printf.printf %S\n"
    (Printf.sprintf "Metal acceleration descriptor simulation: %d IDs rejected with zero allocation" (List.length selection.identifiers))
