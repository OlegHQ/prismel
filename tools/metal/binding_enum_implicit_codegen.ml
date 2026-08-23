exception Error of string

let fail format = Printf.ksprintf (fun message -> raise (Error message)) format

type declaration =
  { id : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; header : string
  ; line : int option
  ; signature : string
  ; classification : string
  ; constant_value : string option
  }

type selected_case =
  { declaration : declaration
  ; spec : Binding_enum_implicit_plan.case
  ; ocaml_name : string
  ; bits : int64
  }

type selected_family =
  { spec : Binding_enum_implicit_plan.family
  ; enum_declaration : declaration
  ; typedef_declaration : declaration
  ; module_name : string
  ; cases : selected_case list
  }

type selection = selected_family list

module String_map = Map.Make (String)

let snake_case value =
  let output = Buffer.create (String.length value + 8) in
  let uppercase character = character >= 'A' && character <= 'Z' in
  let lowercase character = character >= 'a' && character <= 'z' in
  let digit character = character >= '0' && character <= '9' in
  String.iteri
    (fun index character ->
      if character = '_' then Buffer.add_char output '_'
      else begin
        let previous = if index = 0 then None else Some value.[index - 1] in
        let next =
          if index + 1 = String.length value then None else Some value.[index + 1]
        in
        let starts_word =
          uppercase character
          &&
          match previous, next with
          | Some previous, _ when lowercase previous || digit previous -> true
          | Some previous, Some next when uppercase previous && lowercase next -> true
          | _ -> false
        in
        if starts_word then Buffer.add_char output '_';
        Buffer.add_char output (Char.lowercase_ascii character)
      end)
    value;
  Buffer.contents output

let module_name value =
  let value = snake_case value in
  String.mapi (fun index char -> if index = 0 then Char.uppercase_ascii char else char) value

let require map id =
  match String_map.find_opt id map with
  | Some declaration -> declaration
  | None -> fail "missing implicit Metal enum inventory declaration %s" id

let require_shape ~id ~kind ~name ~owner ~header ~line ~signature declaration =
  if declaration.kind <> kind || declaration.name <> name
     || declaration.owner <> owner || declaration.header <> header
     || declaration.line <> Some line || declaration.signature <> signature
  then fail "implicit Metal enum inventory shape drift for %s" id;
  if declaration.classification <> "unreviewed" then
    fail "implicit Metal enum %s is %s, expected unreviewed" id declaration.classification

let select declarations =
  let by_id =
    List.fold_left
      (fun map declaration ->
        if String_map.mem declaration.id map then fail "duplicate Metal inventory id %s" declaration.id;
        String_map.add declaration.id declaration map)
      String_map.empty declarations
  in
  let select_family (spec : Binding_enum_implicit_plan.family) =
    let enum_id = "enum:" ^ spec.sdk_name in
    let typedef_id = "typedef:" ^ spec.sdk_name in
    let enum_declaration = require by_id enum_id in
    let typedef_declaration = require by_id typedef_id in
    require_shape ~id:enum_id ~kind:"enum" ~name:spec.sdk_name ~owner:None
      ~header:spec.header ~line:spec.enum_line ~signature:"" enum_declaration;
    require_shape ~id:typedef_id ~kind:"typedef" ~name:spec.sdk_name ~owner:None
      ~header:spec.header ~line:spec.enum_line ~signature:spec.typedef_signature
      typedef_declaration;
    let cases =
      List.map
        (fun (case_spec : Binding_enum_implicit_plan.case) ->
          let id = Printf.sprintf "enum-case:%s:%s" spec.sdk_name case_spec.sdk_name in
          let declaration = require by_id id in
          require_shape ~id ~kind:"enum-case" ~name:case_spec.sdk_name
            ~owner:(Some spec.sdk_name) ~header:spec.header
            ~line:case_spec.expected_line ~signature:spec.sdk_name declaration;
          (match declaration.constant_value with
           | None -> ()
           | Some actual when String.equal actual case_spec.unsigned_decimal -> ()
           | Some actual -> fail "implicit Metal enum value drift for %s: %s, expected %s"
                              id actual case_spec.unsigned_decimal);
          let bits = Int64.of_string case_spec.unsigned_decimal in
          { declaration; spec = case_spec; ocaml_name = snake_case case_spec.sdk_name; bits })
        spec.cases
    in
    { spec; enum_declaration; typedef_declaration; module_name = module_name spec.sdk_name; cases }
  in
  List.map select_family Binding_enum_implicit_plan.families

let family_count selection = List.length selection
let case_count selection = List.fold_left (fun total family -> total + List.length family.cases) 0 selection
let declaration_count selection = case_count selection + (2 * family_count selection)

let identifiers selection =
  List.concat_map
    (fun family ->
      family.enum_declaration.id :: family.typedef_declaration.id
      :: List.map (fun case -> case.declaration.id) family.cases)
    selection
  |> List.sort String.compare

let render_raw_ml ?(outer_module = "Implicit_enum_constants") selection =
  let output = Buffer.create 2048 in
  Printf.bprintf output "module %s = struct\n" (module_name outer_module);
  List.iter
    (fun family ->
      Printf.bprintf output "  module %s = struct\n" family.module_name;
      List.iter
        (fun case -> Printf.bprintf output "    let %s : int64 = 0x%016LxL\n" case.ocaml_name case.bits)
        family.cases;
      Buffer.add_string output "  end\n")
    selection;
  Buffer.add_string output "end\n";
  Buffer.contents output

let render_raw_mli ?(outer_module = "Implicit_enum_constants") selection =
  let output = Buffer.create 1024 in
  Printf.bprintf output "module %s : sig\n" (module_name outer_module);
  List.iter
    (fun family ->
      Printf.bprintf output "  module %s : sig\n" family.module_name;
      List.iter (fun case -> Printf.bprintf output "    val %s : int64\n" case.ocaml_name) family.cases;
      Buffer.add_string output "  end\n")
    selection;
  Buffer.add_string output "end\n";
  Buffer.contents output

let render_static_asserts selection =
  let output = Buffer.create 4096 in
  Buffer.add_string output "// Compile-time validation for SDK enums whose implicit values are absent from clang JSON.\n";
  List.iter
    (fun family ->
      List.iter
        (fun (case : selected_case) ->
          Printf.bprintf output
            "static_assert(static_cast<uint64_t>(%s) == UINT64_C(%s), \"Metal enum value drift: %s\");\n"
            case.spec.sdk_name case.spec.unsigned_decimal case.spec.sdk_name)
        family.cases)
    selection;
  Buffer.contents output
