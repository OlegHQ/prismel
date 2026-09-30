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
let number = Flow.Expr.sexp_number
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

let sop factory =
  let module Edit = Procedural.Edit_graph in
  let slots = List.map2 (fun name requirement ->
    group "slot" [quote name; (match requirement with
      | Edit.Required -> "required" | Edit.Optional -> "optional"
      | Edit.Rest -> "rest")])
      (Edit.factory_slot_names factory) (Edit.factory_inputs factory) in
  entry ~qualified:("sop/" ^ Edit.factory_key factory)
    ~key:(Edit.factory_key factory) ~operation:(Edit.factory_operation factory)
    ~label:(Edit.factory_label factory)
    ~category:(Edit.factory_category factory) ~slots
    ~fields:(Edit.factory_fields factory)
    ~result:["geo", Flow.Port_type.Geometry]

let value kind =
  let module Value = Flow.Value_kind in
  let key = Value.key kind in
  entry ~qualified:("value/" ^ key) ~key ~operation:key
    ~label:(Value.label kind) ~category:(Value.category kind) ~slots:[]
    ~fields:(Value.fields (Value.make kind)) ~result:(Value.outputs kind)

let generate factories =
  Result.map (fun _ ->
    let kinds = List.map sop factories @ List.map value Flow.Value_kind.all in
    let payload = group "version" [string_of_int version] ^ "\n" ^
      group "kinds" kinds in
    let digest = Digest.to_hex (Digest.string payload) in
    let text = "(flow_manifest\n  " ^ group "version" [string_of_int version] ^
      "\n  " ^ group "digest" [quote digest] ^
      "\n  (kinds\n    " ^ String.concat "\n    " kinds ^ "))\n" in
    text, digest)
    (Catalog.of_factories ~version factories)
