let version = 202609

let quote value =
  let buffer = Buffer.create (String.length value + 2) in
  Buffer.add_char buffer '"';
  String.iter (function
    | '"' -> Buffer.add_string buffer "\\\""
    | '\\' -> Buffer.add_string buffer "\\\\"
    | '\n' -> Buffer.add_string buffer "\\n"
    | character -> Buffer.add_char buffer character) value;
  Buffer.add_char buffer '"';
  Buffer.contents buffer

let group name values = "(" ^ name ^
  (if values = [] then "" else " " ^ String.concat " " values) ^ ")"
let strings name values = group name (List.map quote values)
let number number =
  if not (Float.is_finite number) then invalid_arg "Manifest.number: non-finite";
  let text = Printf.sprintf "%.17g" number in
  match String.index_opt text 'e' with
  | None -> text
  | Some exponent_at ->
      let negative = text.[0] = '-' in
      let mantissa = String.sub text (if negative then 1 else 0)
        (exponent_at - if negative then 1 else 0) in
      let exponent = int_of_string (String.sub text (exponent_at + 1)
        (String.length text - exponent_at - 1)) in
      let point = Option.value ~default:(String.length mantissa)
        (String.index_opt mantissa '.') in
      let digits = String.concat "" (String.split_on_char '.' mantissa) in
      let shifted = point + exponent in
      let sign = if negative then "-" else "" in
      if shifted <= 0 then sign ^ "0." ^ String.make (-shifted) '0' ^ digits
      else if shifted >= String.length digits then
        sign ^ digits ^ String.make (shifted - String.length digits) '0'
      else sign ^ String.sub digits 0 shifted ^ "." ^
        String.sub digits shifted (String.length digits - shifted)
let optional render = function None -> "nil" | Some value -> render value
let literal = function
  | Param.Bool_value value -> group "bool" [string_of_bool value]
  | Param.Int_value value -> group "int" [string_of_int value]
  | Param.Float_value value -> group "float" [number value]
  | Param.Text_value value -> group "text" [quote value]
  | Param.Choice_value value -> group "choice" [quote value]

let field (field : Param.field_view) =
  let kind = match field.kind with
    | Param.Toggle_view -> group "bool" []
    | Param.Integer_view range -> group "int" [
        group "soft" [string_of_int range.soft_min; string_of_int range.soft_max];
        group "hard" [optional string_of_int range.hard_min;
          optional string_of_int range.hard_max]]
    | Param.Floating_view range -> group "float" [
        group "soft" [number range.soft_min; number range.soft_max];
        group "hard" [optional number range.hard_min;
          optional number range.hard_max]]
    | Param.Text_view -> group "text" []
    | Param.Choice_view labels -> strings "choice" (Array.to_list labels) in
  group "field" [quote field.name; quote field.label;
    strings "folder" field.folder; kind; literal field.default;
    group "primary" [string_of_bool field.primary];
    (match field.vec3 with None -> group "vec3" []
     | Some (name, index) -> group "vec3" [quote name; string_of_int index])]
  |> fun text -> match field.unit with
    | None -> text
    | Some unit -> String.sub text 0 (String.length text - 1) ^ " " ^ group "unit" [quote unit] ^ ")"

let outputs ports = group "outputs" (List.map (fun (name, ty) ->
  group "output" [quote name; String.lowercase_ascii (Flow.Port_type.name ty)]) ports)

let entry ~qualified ~key ~operation ~label ~category ~slots ~fields ~result =
  let fields = match fields with
    | [] -> group "fields" []
    | fields -> "(fields\n        " ^
        String.concat "\n        " (List.map field fields) ^ ")" in
  "(kind " ^ quote qualified ^ "\n      " ^ String.concat "\n      " [
    group "key" [quote key]; group "aliases" [];
    group "operation" [quote operation]; group "label" [quote label];
    strings "category" category; group "slots" slots; fields; outputs result] ^ ")"

let descriptor (d : Catalog.descriptor) =
  let module Edit = Procedural.Edit_graph in
  let slots = List.map (fun (name, requirement) ->
    group "slot" [quote name; (match requirement with
      | Edit.Required -> "required" | Edit.Optional -> "optional"
      | Edit.Rest -> "rest")]) d.slots in
  entry ~qualified:d.qualified ~key:d.key ~operation:d.operation ~label:d.label
    ~category:d.category ~slots ~fields:d.fields
    ~result:(if String.starts_with ~prefix:"sop/" d.qualified
             then ["geo", Flow.Port_type.Geometry] else [])

(* The digest covers the sop kinds, the catalog the PPX links against; the
   generated scene, world and settings kinds ([extra]) follow them and are outside it. *)
let generate ?extra factories =
  Result.map (fun _ ->
    let kinds = List.map (fun f -> descriptor (Catalog.descriptor f)) factories in
    let payload = group "version" [string_of_int version] ^ "\n" ^
      group "kinds" kinds in
    let digest = Digest.to_hex (Digest.string payload) in
    let all = kinds @ List.map descriptor (Option.value extra ~default:[]) in
    let text = "(flow_manifest\n  " ^ group "version" [string_of_int version] ^
      "\n  " ^ group "digest" [quote digest] ^
      "\n  (kinds\n    " ^ String.concat "\n    " all ^ "))\n" in
    text, digest)
    (Catalog.of_factories ~version ?extra factories)
