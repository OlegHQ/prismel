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
  let text = Flow.Lisp.float number in
  if String.ends_with ~suffix:".0" text then String.sub text 0 (String.length text - 2) else text
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

let facts (facts : Procedural.Node.facts) =
  let mode = match facts.cook_mode with
    | Generator -> ["generator"] | Duplicate_input index -> ["duplicate-input"; string_of_int index]
    | In_place index -> ["in-place"; string_of_int index]
    | Instance_input index -> ["instance-input"; string_of_int index]
    | Passthrough index -> ["passthrough"; string_of_int index] | Generic -> ["generic"] in
  group "facts" [group "cook-mode" mode;
    group "elementwise" [match facts.elementwise with Points -> "points" | Primitives -> "primitives" | None -> "none"];
    strings "reads" facts.reads; strings "writes" facts.writes;
    group "topology" [match facts.topology with Preserved -> "preserved" | Changed -> "changed"];
    group "exact" [string_of_bool facts.exact]]

let entry ?facts:declaration ~qualified ~key ~operation ~label ~category ~slots ~fields ~result () =
  let fields = match fields with
    | [] -> group "fields" []
    | fields -> "(fields\n        " ^
        String.concat "\n        " (List.map field fields) ^ ")" in
  let properties = [
    group "key" [quote key]; group "aliases" [];
    group "operation" [quote operation]; group "label" [quote label];
    strings "category" category; group "slots" slots; fields; outputs result]
    @ List.map facts (Option.to_list declaration) in
  "(kind " ^ quote qualified ^ "\n      " ^ String.concat "\n      " properties ^ ")"

let descriptor ?facts (d : Catalog.descriptor) =
  let module Edit = Procedural.Edit_graph in
  let slots = List.map (fun (name, requirement) ->
    group "slot" [quote name; (match requirement with
      | Edit.Required -> "required" | Edit.Optional -> "optional"
      | Edit.Rest -> "rest"
      | Edit.Optional_rest -> "optional-rest")]) d.slots in
  entry ?facts ~qualified:d.qualified ~key:d.key ~operation:d.operation ~label:d.label
    ~category:d.category ~slots ~fields:d.fields
    ~result:(if String.starts_with ~prefix:"sop/" d.qualified
             then ["geo", Flow.Port_type.Geometry] else []) ()

(* The digest covers the sop kinds, the catalog the PPX links against; the
   generated scene, world and settings kinds ([extra]) follow them and are outside it. *)
let generate ?extra factories =
  Result.map (fun _ ->
    let kinds = List.map (fun f -> descriptor ~facts:(Procedural.Edit_graph.factory_facts f)
      (Catalog.descriptor f)) factories in
    let payload = group "version" [string_of_int version] ^ "\n" ^
      group "kinds" kinds in
    let digest = Digest.to_hex (Digest.string payload) in
    let all = kinds @ List.map descriptor (Option.value extra ~default:[]) in
    let text = "(flow_manifest\n  " ^ group "version" [string_of_int version] ^
      "\n  " ^ group "digest" [quote digest] ^
      "\n  (kinds\n    " ^ String.concat "\n    " all ^ "))\n" in
    text, digest)
    (Catalog.of_factories ~version ?extra factories)
