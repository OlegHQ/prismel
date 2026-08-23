open Support

module String_map = Map.Make (String)
module String_set = Set.Make (String)

type inventory_declaration =
  { identifier : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; header : string
  ; signature : string
  ; attributes : string list
  ; classification : string
  ; constant_value : string option
  }

type receiver_spec =
  { owner : string
  ; objc_type : string
  ; handle_kind : string
  ; raw_name : string
  ; local_name : string
  }

let receiver_spec = function
  | Binding_plan.Render_encoder4 ->
      { owner = "MTL4RenderCommandEncoder"
      ; objc_type = "id<MTL4RenderCommandEncoder>"
      ; handle_kind = "Render_encoder4"
      ; raw_name = "raw_encoder"
      ; local_name = "encoder"
      }
  | Binding_plan.Compute_encoder4 ->
      { owner = "MTL4ComputeCommandEncoder"
      ; objc_type = "id<MTL4ComputeCommandEncoder>"
      ; handle_kind = "Compute_encoder4"
      ; raw_name = "raw_encoder"
      ; local_name = "encoder"
      }
  | Binding_plan.Device ->
      { owner = "MTLDevice"
      ; objc_type = "id<MTLDevice>"
      ; handle_kind = "Device"
      ; raw_name = "raw_device"
      ; local_name = "device"
      }

let enum_objc_type = function
  | Binding_plan.Winding -> "MTLWinding"
  | Binding_plan.Cull_mode -> "MTLCullMode"
  | Binding_plan.Depth_clip_mode -> "MTLDepthClipMode"
  | Binding_plan.Triangle_fill_mode -> "MTLTriangleFillMode"

let require_string name value =
  match member_string name value with
  | Some value -> value
  | None -> fail "Metal binding inventory field %s must be a string" name

let require_string_list name value =
  match member_list name value with
  | None -> fail "Metal binding inventory field %s must be a list" name
  | Some values ->
      List.map
        (function
          | `String value -> value
          | _ -> fail "Metal binding inventory field %s must contain strings" name)
        values

let inventory_declaration value =
  { identifier = require_string "id" value
  ; kind = require_string "kind" value
  ; name = require_string "name" value
  ; owner = member_string "owner" value
  ; header = require_string "header" value
  ; signature = require_string "signature" value
  ; attributes = require_string_list "attributes" value
  ; classification = require_string "classification" value
  ; constant_value = member_string "constant_value" value
  }

let load_inventory path =
  let value = read_file path |> Yojson.Safe.from_string in
  let sdk_version = require_string "sdk_version" value in
  let inventory_plan_sha256 =
    require_string "binding_plan_source_sha256" value
  in
  if sdk_version <> Binding_plan.expected_sdk_version then
    fail "Metal binding plan requires SDK %s, inventory records SDK %s"
      Binding_plan.expected_sdk_version sdk_version;
  let symbols =
    match member_list "symbols" value with
    | Some values -> values
    | None -> fail "Metal binding inventory has no symbols list"
  in
  let declarations =
    List.fold_left
      (fun declarations value ->
        let declaration = inventory_declaration value in
        if String_map.mem declaration.identifier declarations then
          fail "duplicate Metal inventory identifier: %s" declaration.identifier;
        String_map.add declaration.identifier declaration declarations)
      String_map.empty symbols
  in
  sdk_version, inventory_plan_sha256, declarations

let valid_identifier ~initial value =
  let valid_initial character =
    match initial with
    | `Lower -> character >= 'a' && character <= 'z'
    | `Any_letter ->
        (character >= 'a' && character <= 'z')
        || (character >= 'A' && character <= 'Z')
        || character = '_'
  in
  let valid_tail character =
    (character >= 'a' && character <= 'z')
    || (character >= 'A' && character <= 'Z')
    || (character >= '0' && character <= '9')
    || character = '_'
  in
  String.length value > 0
  && valid_initial value.[0]
  && String.for_all valid_tail value

let validate_identifier description ~initial value =
  if not (valid_identifier ~initial value) then
    fail "invalid %s in Metal binding plan: %S" description value

let selector_pieces selector argument_count =
  let pieces = String.split_on_char ':' selector in
  let pieces =
    if argument_count = 0 then pieces
    else
      match List.rev pieces with
      | "" :: reversed -> List.rev reversed
      | _ ->
          fail "Objective-C selector %s must end in a colon" selector
  in
  let expected_piece_count = if argument_count = 0 then 1 else argument_count in
  if List.length pieces <> expected_piece_count then
    fail "Objective-C selector %s has %d pieces for %d arguments" selector
      (List.length pieces) argument_count;
  List.iter
    (validate_identifier "Objective-C selector piece" ~initial:`Any_letter)
    pieces;
  pieces

let reject_duplicates description values =
  let duplicates =
    values
    |> List.sort String.compare
    |> List.to_seq
    |> Seq.group String.equal
    |> Seq.filter_map (fun group ->
      match List.of_seq group with
      | value :: _ :: _ -> Some value
      | _ -> None)
    |> List.of_seq
  in
  if duplicates <> [] then
    fail "duplicate %s in Metal binding plan: %s" description
      (String.concat ", " duplicates)

let expected_argument_type = function
  | Binding_plan.Enum_int { enum_type; cases = _ } -> enum_objc_type enum_type
  | Binding_plan.Unsigned_int _ -> "NSUInteger"

let validate_enum_cases inventory binding_id enum_type
    (cases : Binding_plan.enum_case list) =
  if cases = [] then fail "Metal binding %s has no enum cases" binding_id;
  reject_duplicates "enum-case SDK identifier"
    (List.map (fun (case : Binding_plan.enum_case) -> case.sdk_id) cases);
  reject_duplicates "enum-case value"
    (List.map (fun (case : Binding_plan.enum_case) ->
       string_of_int case.value)
       cases);
  let owner = enum_objc_type enum_type in
  let planned_identifiers =
    cases |> List.map (fun (case : Binding_plan.enum_case) -> case.sdk_id)
    |> String_set.of_list
  in
  let inventory_identifiers =
    inventory
    |> String_map.to_seq
    |> Seq.map snd
    |> Seq.filter_map (fun declaration ->
      if declaration.kind = "enum-case"
         && declaration.owner = Some owner
      then Some declaration.identifier
      else None)
    |> String_set.of_seq
  in
  if not (String_set.equal planned_identifiers inventory_identifiers) then
    fail "Metal enum-case inventory drift for %s used by %s" owner binding_id;
  List.iter
    (fun (case : Binding_plan.enum_case) ->
      let declaration =
        match String_map.find_opt case.Binding_plan.sdk_id inventory with
        | Some declaration -> declaration
        | None ->
            fail "Metal enum case is absent from the pinned inventory: %s"
              case.sdk_id
      in
      if declaration.kind <> "enum-case"
         || declaration.owner <> Some owner
         || declaration.signature <> owner
      then
        fail "Metal enum-case type drift for %s" case.sdk_id;
      if declaration.constant_value <> Some (string_of_int case.value) then
        fail "Metal enum-case value drift for %s" case.sdk_id;
      if declaration.classification <> "bound" then
        fail "generated Metal enum case must be bound: %s" case.sdk_id)
    cases

let compare_declaration identifier field expected actual =
  if expected <> actual then
    fail "Metal inventory drift for %s (%s): expected %S, found %S" identifier
      field expected actual

let require_declaration inventory identifier =
  match String_map.find_opt identifier inventory with
  | Some declaration -> declaration
  | None ->
      fail "generated Metal identifier is absent from the pinned inventory: %s"
        identifier

let validate_companion inventory safe_api (companion : Binding_plan.companion) =
  let declaration = require_declaration inventory companion.sdk_id in
  let compare field expected actual =
    compare_declaration companion.sdk_id field expected actual
  in
  compare "kind" companion.kind declaration.kind;
  (match declaration.owner with
   | Some owner -> compare "owner" companion.owner owner
   | None ->
       fail "Metal inventory drift for %s: owner is absent" companion.sdk_id);
  compare "name" companion.name declaration.name;
  compare "header" companion.header declaration.header;
  compare "signature" companion.signature declaration.signature;
  if companion.attributes <> declaration.attributes then
    fail "Metal inventory drift for %s (attributes)" companion.sdk_id;
  match safe_api with
  | Some _ when declaration.classification <> "bound" ->
      fail "safe generated Metal companion must be bound, found %s for %s"
        declaration.classification companion.sdk_id
  | None when declaration.classification = "bound" ->
      fail "generated Metal companion lacks safe-API evidence: %s"
        companion.sdk_id
  | Some _ | None -> ()

let generation_identity = function
  | Binding_plan.Direct_void binding ->
      binding.ocaml_name, binding.c_symbol, binding.receiver
  | Binding_plan.Direct_getter binding ->
      binding.ocaml_name, binding.c_symbol, binding.receiver

let generated_identity entry =
  match entry.Binding_plan.disposition with
  | Binding_plan.Generate generation -> generation_identity generation
  | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
      fail "internal error: non-generated Metal binding %s" entry.sdk_id

let generated_ocaml_name entry =
  let ocaml_name, _, _ = generated_identity entry in
  ocaml_name

let generated_c_symbol entry =
  let _, c_symbol, _ = generated_identity entry in
  c_symbol

let validate_binding_identity entry generation =
  let ocaml_name, c_symbol, receiver_kind = generation_identity generation in
  validate_identifier "OCaml external name" ~initial:`Lower ocaml_name;
  validate_identifier "C primitive symbol" ~initial:`Any_letter c_symbol;
  if not (String.starts_with ~prefix:"caml_prismel_metal_" c_symbol) then
    fail "generated Metal C symbol has the wrong namespace: %s" c_symbol;
  let receiver = receiver_spec receiver_kind in
  compare_declaration entry.Binding_plan.sdk_id "generated receiver owner"
    entry.expect.owner receiver.owner;
  receiver

let validate_entry inventory entry =
  let declaration = require_declaration inventory entry.Binding_plan.sdk_id in
  let expect = entry.expect in
  let compare field expected actual =
    compare_declaration entry.sdk_id field expected actual
  in
  compare "kind" expect.kind declaration.kind;
  (match declaration.owner with
   | Some owner -> compare "owner" expect.owner owner
   | None -> fail "Metal inventory drift for %s: owner is absent" entry.sdk_id);
  compare "name" expect.name declaration.name;
  compare "header" expect.header declaration.header;
  compare "signature" expect.signature declaration.signature;
  if expect.attributes <> declaration.attributes then
    fail "Metal inventory drift for %s (attributes)" entry.sdk_id;
  (match entry.safe_api with
   | Some _ when declaration.classification <> "bound" ->
       fail "safe generated Metal identifier must be bound, found %s for %s"
         declaration.classification entry.sdk_id
   | None when declaration.classification = "bound" ->
       fail "generated Metal identifier lacks safe-API evidence: %s" entry.sdk_id
   | Some _ | None -> ());
  List.iter (validate_companion inventory entry.safe_api) entry.companions;
  let availability = expect.availability in
  if availability.macos_major <= 0 || availability.macos_minor < 0 then
    fail "invalid macOS availability for Metal binding %s" entry.sdk_id;
  if availability.unavailable_error = "" then
    fail "empty availability error for Metal binding %s" entry.sdk_id;
  match entry.disposition with
  | Binding_plan.Generate (Binding_plan.Direct_void binding as generation) ->
      ignore (validate_binding_identity entry generation);
      let argument_count = List.length binding.arguments in
      ignore (selector_pieces expect.name argument_count);
      if argument_count + 1 > 5 then
        fail "generated Metal primitive %s exceeds native arity five"
          binding.ocaml_name;
      let argument_names =
        List.map
          (fun (argument : Binding_plan.argument) ->
            validate_identifier "native argument name" ~initial:`Lower
              argument.Binding_plan.name;
            if argument.error = "" then
              fail "generated Metal argument %s has an empty validation error"
                argument.name;
            (match argument.kind with
             | Binding_plan.Enum_int { enum_type; cases } ->
                 validate_enum_cases inventory entry.sdk_id enum_type cases
             | Binding_plan.Unsigned_int { minimum; multiple_of } ->
                 if minimum < 0 then
                   fail
                     "generated Metal unsigned argument %s has a negative minimum"
                     argument.name;
                 (match multiple_of with
                  | Some divisor when divisor <= 0 ->
                      fail
                        "generated Metal unsigned argument %s has a nonpositive multiple"
                        argument.name
                  | None | Some _ -> ()));
            argument.name)
          binding.arguments
      in
      let unique_argument_names = List.sort_uniq String.compare argument_names in
      if List.length unique_argument_names <> List.length argument_names then
        fail "generated Metal primitive %s has duplicate argument names"
          binding.ocaml_name;
      let expected_signature =
        Printf.sprintf "instance (%s) -> void"
          (binding.arguments
           |> List.map (fun (argument : Binding_plan.argument) ->
             expected_argument_type argument.kind)
           |> String.concat ", ")
      in
      compare "template-derived signature" expected_signature expect.signature
  | Binding_plan.Generate (Binding_plan.Direct_getter binding as generation) ->
      ignore (validate_binding_identity entry generation);
      ignore (selector_pieces expect.name 0);
      (match binding.result with
       | Binding_plan.Nsuint_to_checked_int64 { overflow_error } ->
           if overflow_error = "" then
             fail "generated Metal getter %s has an empty overflow error"
               binding.ocaml_name;
           compare "template-derived signature" "instance () -> NSUInteger"
             expect.signature)
  | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
      fail "non-generated disposition reached the Metal generator for %s"
        entry.sdk_id

let identifier_start character =
  (character >= 'a' && character <= 'z')
  || (character >= 'A' && character <= 'Z')
  || character = '_'

let identifier_tail character =
  identifier_start character || (character >= '0' && character <= '9')

let skip_quoted source quote start =
  let length = String.length source in
  let rec loop index =
    if index >= length then length
    else if source.[index] = '\\' then loop (min length (index + 2))
    else if source.[index] = quote then index + 1
    else loop (index + 1)
  in
  loop start

let c_identifiers source =
  let length = String.length source in
  let rec skip_line index =
    if index >= length || source.[index] = '\n' then index
    else skip_line (index + 1)
  in
  let rec skip_block index =
    if index + 1 >= length then length
    else if source.[index] = '*' && source.[index + 1] = '/' then index + 2
    else skip_block (index + 1)
  in
  let rec identifier_end index =
    if index < length && identifier_tail source.[index] then
      identifier_end (index + 1)
    else index
  in
  let rec collect index identifiers =
    if index >= length then identifiers
    else if index + 1 < length && source.[index] = '/'
            && source.[index + 1] = '/'
    then collect (skip_line (index + 2)) identifiers
    else if index + 1 < length && source.[index] = '/'
            && source.[index + 1] = '*'
    then collect (skip_block (index + 2)) identifiers
    else if source.[index] = '"' then
      collect (skip_quoted source source.[index] (index + 1)) identifiers
    else if source.[index] = '\''
            && not
                 (index > 0 && index + 1 < length
                 && source.[index - 1] >= '0' && source.[index - 1] <= '9'
                 && source.[index + 1] >= '0' && source.[index + 1] <= '9')
    then collect (skip_quoted source '\'' (index + 1)) identifiers
    else if identifier_start source.[index] then
      let ending = identifier_end (index + 1) in
      let identifier = String.sub source index (ending - index) in
      collect ending (String_set.add identifier identifiers)
    else collect (index + 1) identifiers
  in
  collect 0 String_set.empty

type ocaml_tokens =
  { identifiers : String_set.t
  ; strings : String_set.t
  }

let ocaml_tokens source =
  let length = String.length source in
  let rec skip_comment depth index =
    if index >= length then length
    else if index + 1 < length && source.[index] = '('
            && source.[index + 1] = '*'
    then skip_comment (depth + 1) (index + 2)
    else if index + 1 < length && source.[index] = '*'
            && source.[index + 1] = ')'
    then if depth = 1 then index + 2 else skip_comment (depth - 1) (index + 2)
    else skip_comment depth (index + 1)
  in
  let rec identifier_end index =
    if index < length
       && (identifier_tail source.[index] || source.[index] = '\'')
    then identifier_end (index + 1)
    else index
  in
  let read_string start =
    let output = Buffer.create 64 in
    let rec loop index escaped =
      if index >= length then None, length
      else
        match source.[index] with
        | '"' ->
            (if escaped then None else Some (Buffer.contents output)), index + 1
        | '\\' ->
            if index + 1 >= length then None, length
            else begin
              Buffer.add_char output source.[index];
              Buffer.add_char output source.[index + 1];
              loop (index + 2) true
            end
        | character ->
            Buffer.add_char output character;
            loop (index + 1) escaped
    in
    loop start false
  in
  let rec collect index tokens =
    if index >= length then tokens
    else if index + 1 < length && source.[index] = '('
            && source.[index + 1] = '*'
    then collect (skip_comment 1 (index + 2)) tokens
    else if source.[index] = '"' then
      let literal, ending = read_string (index + 1) in
      let strings =
        match literal with
        | Some literal -> String_set.add literal tokens.strings
        | None -> tokens.strings
      in
      collect ending { tokens with strings }
    else if identifier_start source.[index] then
      let ending = identifier_end (index + 1) in
      let identifier = String.sub source index (ending - index) in
      collect ending
        { tokens with
          identifiers = String_set.add identifier tokens.identifiers
        }
    else collect (index + 1) tokens
  in
  collect 0 { identifiers = String_set.empty; strings = String_set.empty }

let parse_implementation description source =
  let lexbuf = Lexing.from_string source in
  Location.init lexbuf description;
  try Parse.implementation lexbuf with
  | exception_value ->
      fail "cannot parse %s for Metal safe-API evidence: %s" description
        (Printexc.to_string exception_value)

let rec longident_path = function
  | Longident.Lident name -> Some [ name ]
  | Longident.Ldot (prefix, name) ->
      Option.map (fun path -> path @ [ name ]) (longident_path prefix)
  | Longident.Lapply _ -> None

let expression_calls path expression =
  let found = ref false in
  let expr iterator expression =
    (match expression.Parsetree.pexp_desc with
     | Parsetree.Pexp_apply
         ({ pexp_desc = Pexp_ident identifier; _ }, _)
       when longident_path identifier.txt = Some path -> found := true
     | _ -> ());
    Ast_iterator.default_iterator.expr iterator expression
  in
  let iterator = { Ast_iterator.default_iterator with expr } in
  iterator.expr iterator expression;
  !found

let rec module_structure = function
  | { Parsetree.pmod_desc = Pmod_structure structure; _ } -> Some structure
  | { pmod_desc = Pmod_constraint (expression, _); _ } ->
      module_structure expression
  | _ -> None

let descend_module name structure =
  List.find_map
    (fun item ->
      match item.Parsetree.pstr_desc with
      | Parsetree.Pstr_module binding when binding.pmb_name.txt = Some name ->
          module_structure binding.pmb_expr
      | _ -> None)
    structure

let rec find_module_path path structure =
  match path with
  | [] -> Some structure
  | name :: rest ->
      Option.bind (descend_module name structure)
        (find_module_path rest)

let rec pattern_name pattern =
  match pattern.Parsetree.ppat_desc with
  | Parsetree.Ppat_var name -> Some name.txt
  | Parsetree.Ppat_constraint (pattern, _)
  | Parsetree.Ppat_alias (pattern, _) -> pattern_name pattern
  | _ -> None

let value_expression name structure =
  let expressions =
    structure
    |> List.concat_map (fun item ->
      match item.Parsetree.pstr_desc with
      | Parsetree.Pstr_value (_, bindings) ->
          List.filter_map
            (fun binding ->
              if pattern_name binding.Parsetree.pvb_pat = Some name then
                Some binding.pvb_expr
              else None)
            bindings
      | _ -> [])
  in
  match expressions with
  | [ expression ] -> Some expression
  | [] -> None
  | _ -> fail "duplicate safe-evidence OCaml value binding: %s" name

let rec is_function_expression expression =
  match expression.Parsetree.pexp_desc with
  | Parsetree.Pexp_function _ -> true
  | Parsetree.Pexp_constraint (expression, _)
  | Parsetree.Pexp_coerce (expression, _, _)
  | Parsetree.Pexp_poly (expression, _) -> is_function_expression expression
  | _ -> false

let function_execution_expressions expression =
  let rec descend expression =
    match expression.Parsetree.pexp_desc with
    | Parsetree.Pexp_function
        (_, _, Parsetree.Pfunction_body expression) -> descend expression
    | Parsetree.Pexp_function
        (_, _, Parsetree.Pfunction_cases (cases, _, _)) ->
        List.concat_map
          (fun case -> Option.to_list case.Parsetree.pc_guard @ [ case.pc_rhs ])
          cases
    | Parsetree.Pexp_constraint (expression, _)
    | Parsetree.Pexp_coerce (expression, _, _)
    | Parsetree.Pexp_poly (expression, _) -> descend expression
    | _ -> [ expression ]
  in
  descend expression

let direct_local_calls expressions =
  let calls = ref String_set.empty in
  let expr iterator expression =
    match expression.Parsetree.pexp_desc with
    | Parsetree.Pexp_function _ | Parsetree.Pexp_lazy _ -> ()
    | Parsetree.Pexp_apply
        ({ pexp_desc = Pexp_ident identifier; _ }, _arguments) ->
        (match identifier.txt with
         | Longident.Lident name -> calls := String_set.add name !calls
         | Longident.Ldot _ | Longident.Lapply _ -> ());
        Ast_iterator.default_iterator.expr iterator expression
    | _ -> Ast_iterator.default_iterator.expr iterator expression
  in
  let iterator = { Ast_iterator.default_iterator with expr } in
  List.iter (iterator.expr iterator) expressions;
  !calls

let reachable_top_level_values structure =
  let bindings =
    List.fold_left
      (fun bindings item ->
        match item.Parsetree.pstr_desc with
        | Parsetree.Pstr_value (_, value_bindings) ->
            List.fold_left
              (fun bindings binding ->
                match pattern_name binding.Parsetree.pvb_pat with
                | None -> bindings
                | Some name ->
                    String_map.update name
                      (function
                        | None -> Some [ binding.pvb_expr ]
                        | Some expressions ->
                            Some (binding.pvb_expr :: expressions))
                      bindings)
              bindings value_bindings
        | _ -> bindings)
      String_map.empty structure
  in
  let graph =
    String_map.map
      (fun expressions ->
        expressions
        |> List.concat_map function_execution_expressions
        |> direct_local_calls)
      bindings
  in
  let roots =
    structure
    |> List.concat_map (fun item ->
      match item.Parsetree.pstr_desc with
      | Parsetree.Pstr_eval (expression, _) -> [ expression ]
      | Parsetree.Pstr_value (_, value_bindings) ->
          List.filter_map
            (fun binding ->
              match pattern_name binding.Parsetree.pvb_pat with
              | None -> Some binding.pvb_expr
              | Some _ when not (is_function_expression binding.pvb_expr) ->
                  Some binding.pvb_expr
              | Some _ -> None)
            value_bindings
      | _ -> [])
    |> direct_local_calls
  in
  let rec visit reachable pending =
    match pending with
    | [] -> reachable
    | name :: rest when String_set.mem name reachable -> visit reachable rest
    | name :: rest ->
        let reachable = String_set.add name reachable in
        let successors =
          match String_map.find_opt name graph with
          | None -> []
          | Some successors -> String_set.elements successors
        in
        visit reachable (successors @ rest)
  in
  visit String_set.empty (String_set.elements roots)

let validate_safe_api safe_structure test_structure reachable_test_values entry =
  match entry.Binding_plan.safe_api with
  | None -> ()
  | Some evidence ->
      let ocaml_name = generated_ocaml_name entry in
      if evidence.operation = "" || evidence.module_path = []
         || evidence.value_name = "" || evidence.test_value = ""
         || evidence.test_call = []
      then
        fail "empty safe-API evidence for generated Metal binding %s" entry.sdk_id;
      let expected_operation =
        String.concat "."
          ("Metal" :: evidence.module_path @ [ evidence.value_name ])
      in
      if evidence.operation <> expected_operation then
        fail "safe Metal operation path drift for generated binding %s"
          entry.sdk_id;
      let safe_module =
        match find_module_path evidence.module_path safe_structure with
        | Some structure -> structure
        | None ->
            fail "safe Metal module is absent for generated binding %s"
              entry.sdk_id
      in
      let safe_expression =
        match value_expression evidence.value_name safe_module with
        | Some expression -> expression
        | None ->
            fail "safe Metal operation is absent for generated binding %s"
              entry.sdk_id
      in
      if not
           (expression_calls [ "Metal_raw"; ocaml_name ] safe_expression)
      then
        fail "safe Metal operation does not call generated raw binding %s"
          entry.sdk_id;
      let test_expression =
        match value_expression evidence.test_value test_structure with
        | Some expression -> expression
        | None ->
            fail "conformance function is absent for generated Metal binding %s"
              entry.sdk_id
      in
      if not (expression_calls evidence.test_call test_expression) then
        fail "conformance function does not call generated Metal operation %s"
          entry.sdk_id;
      if not (String_set.mem evidence.test_value reachable_test_values) then
        fail
          "conformance function is not reachable from an executable top-level runner for generated Metal binding %s"
          entry.sdk_id

let validate_plan inventory manual_native manual_raw_ml manual_raw_mli safe_source
    safe_tests =
  let entries = Binding_plan.generated_entries in
  if entries = [] then fail "Metal binding plan has no generated entries";
  reject_duplicates "SDK identifier"
    (Binding_plan.entries
     |> List.concat_map (fun entry ->
       entry.Binding_plan.sdk_id
       :: List.map
            (fun (companion : Binding_plan.companion) -> companion.sdk_id)
            entry.companions));
  reject_duplicates "generated OCaml name"
    (List.map generated_ocaml_name entries);
  reject_duplicates "generated C symbol"
    (List.map generated_c_symbol entries);
  List.iter (validate_entry inventory) entries;
  let safe_structure = parse_implementation "Metal safe source" safe_source in
  let test_structure = parse_implementation "Metal conformance tests" safe_tests in
  let reachable_test_values = reachable_top_level_values test_structure in
  List.iter
    (validate_safe_api safe_structure test_structure reachable_test_values)
    entries;
  let manual_native_identifiers = c_identifiers manual_native in
  let manual_raw_tokens =
    let ml = ocaml_tokens manual_raw_ml in
    let mli = ocaml_tokens manual_raw_mli in
    { identifiers = String_set.union ml.identifiers mli.identifiers
    ; strings = String_set.union ml.strings mli.strings
    }
  in
  List.iter
    (fun entry ->
      let ocaml_name = generated_ocaml_name entry in
      let c_symbol = generated_c_symbol entry in
      if String_set.mem c_symbol manual_native_identifiers then
        fail "generated C symbol still exists in the handwritten bridge: %s"
          c_symbol;
      if String_set.mem ocaml_name manual_raw_tokens.identifiers then
        fail "generated OCaml external still exists in handwritten Metal_raw: %s"
          ocaml_name;
      if String_set.mem c_symbol manual_raw_tokens.strings then
        fail "generated C primitive still exists in handwritten Metal_raw: %s"
          c_symbol)
    entries;
  List.sort
    (fun left right -> String.compare left.Binding_plan.sdk_id right.sdk_id)
    entries

let generated_header ~plan_sha256 ~inventory_sha256 =
  Printf.sprintf
    "Generated by tools/metal/generate_bindings.ml.\nPlan SHA-256: %s\nInventory SHA-256: %s\nDo not edit."
    plan_sha256 inventory_sha256

let raw_type = function
  | Binding_plan.Enum_int _ -> "int"
  | Binding_plan.Unsigned_int _ -> "int"

let add_raw_external output entry =
  let ocaml_name, c_symbol, _ = generated_identity entry in
  let arguments =
    match entry.Binding_plan.disposition with
    | Binding_plan.Generate (Binding_plan.Direct_void binding) ->
        "Types.handle"
        :: List.map
             (fun (argument : Binding_plan.argument) -> raw_type argument.kind)
             binding.arguments
        @ [ "(unit, string) result" ]
    | Binding_plan.Generate (Binding_plan.Direct_getter binding) ->
        let result_type =
          match binding.result with
          | Binding_plan.Nsuint_to_checked_int64 _ -> "int64"
        in
        [ "Types.handle"; Printf.sprintf "(%s, string) result" result_type ]
    | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
        fail "internal error: non-generated Metal binding %s" entry.sdk_id
  in
  Buffer.add_string output "  external ";
  Buffer.add_string output ocaml_name;
  Buffer.add_string output " :\n    ";
  Buffer.add_string output (String.concat " -> " arguments);
  Buffer.add_string output " =\n    ";
  Buffer.add_string output (Printf.sprintf "%S\n\n" c_symbol)

let raw_ml ~header entries =
  let output = Buffer.create 4096 in
  Printf.bprintf output "(* %s *)\n\n" header;
  Buffer.add_string output "module Make (Types : sig\n  type handle\nend) = struct\n";
  List.iter (add_raw_external output) entries;
  Buffer.add_string output "end\n";
  Buffer.contents output

let raw_mli ~header entries =
  let output = Buffer.create 4096 in
  Printf.bprintf output "(* %s *)\n\n" header;
  Buffer.add_string output
    "module Make (Types : sig\n  type handle\nend) : sig\n";
  List.iter (add_raw_external output) entries;
  Buffer.add_string output "end\n";
  Buffer.contents output

let c_string value =
  let output = Buffer.create (String.length value + 2) in
  Buffer.add_char output '"';
  String.iter
    (function
      | '"' -> Buffer.add_string output "\\\""
      | '\\' -> Buffer.add_string output "\\\\"
      | '\n' -> Buffer.add_string output "\\n"
      | '\r' -> Buffer.add_string output "\\r"
      | '\t' -> Buffer.add_string output "\\t"
      | '\000' -> fail "NUL byte in generated Metal C string"
      | character -> Buffer.add_char output character)
    value;
  Buffer.add_char output '"';
  Buffer.contents output

let validation_condition name (cases : Binding_plan.enum_case list) =
  let values =
    cases |> List.map (fun (case : Binding_plan.enum_case) -> case.value)
    |> List.sort Int.compare
  in
  let rec consecutive = function
    | [] | [ _ ] -> true
    | left :: (right :: _ as rest) ->
        right = left + 1 && consecutive rest
  in
  match values with
  | minimum :: _ when consecutive values ->
      let maximum = List.hd (List.rev values) in
      Printf.sprintf "%s < %d || %s > %d" name minimum name maximum
  | _ ->
      values
      |> List.map (fun value -> Printf.sprintf "%s != %d" name value)
      |> String.concat " && "

let argument_conversion output (argument : Binding_plan.argument) =
  match argument.Binding_plan.kind with
  | Binding_plan.Enum_int { cases; _ } ->
      Printf.bprintf output "        const intnat %s = Long_val(raw_%s);\n"
        argument.name argument.name;
      Printf.bprintf output "        if (%s) {\n"
        (validation_condition argument.name cases);
      Printf.bprintf output "          CAMLreturn(result_error_text(%s));\n"
        (c_string argument.error);
      Buffer.add_string output "        }\n"
  | Binding_plan.Unsigned_int { minimum; multiple_of } ->
      Printf.bprintf output "        const intnat %s = Long_val(raw_%s);\n"
        argument.name argument.name;
      let conditions =
        (if minimum = 0 then [ Printf.sprintf "%s < 0" argument.name ]
         else [ Printf.sprintf "%s < %d" argument.name minimum ])
        @
        match multiple_of with
        | None -> []
        | Some divisor ->
            [ Printf.sprintf "%s %% %d != 0" argument.name divisor ]
      in
      Printf.bprintf output "        if (%s) {\n"
        (String.concat " || " conditions);
      Printf.bprintf output "          CAMLreturn(result_error_text(%s));\n"
        (c_string argument.error);
      Buffer.add_string output "        }\n"

let argument_expression (argument : Binding_plan.argument) =
  match argument.Binding_plan.kind with
  | Binding_plan.Enum_int { enum_type; _ } ->
      Printf.sprintf "static_cast<%s>(%s)" (enum_objc_type enum_type)
        argument.name
  | Binding_plan.Unsigned_int _ ->
      Printf.sprintf "static_cast<NSUInteger>(%s)" argument.name

let objc_call receiver selector arguments =
  match arguments with
  | [] -> Printf.sprintf "[%s %s]" receiver.local_name selector
  | _ ->
      let pieces = selector_pieces selector (List.length arguments) in
      let components =
        List.map2
          (fun piece argument ->
            Printf.sprintf "%s:%s" piece (argument_expression argument))
          pieces arguments
      in
      Printf.sprintf "[%s %s]" receiver.local_name
        (String.concat " " components)

let camlparam arguments =
  let count = List.length arguments in
  if count < 1 || count > 5 then fail "unsupported CAMLparam arity: %d" count;
  Printf.sprintf "CAMLparam%d(%s);" count (String.concat ", " arguments)

let add_native_void_binding output (entry : Binding_plan.entry)
    (binding : Binding_plan.direct_void) =
  let receiver = receiver_spec binding.receiver in
  let raw_arguments =
    receiver.raw_name
    :: List.map
         (fun (argument : Binding_plan.argument) -> "raw_" ^ argument.name)
         binding.arguments
  in
  Buffer.add_string output "extern \"C\" CAMLprim value\n";
  Printf.bprintf output "%s(\n    %s) {\n" binding.c_symbol
    (raw_arguments
     |> List.map (fun argument -> "value " ^ argument)
     |> String.concat ", ");
  Printf.bprintf output "  %s\n" (camlparam raw_arguments);
  Buffer.add_string output "  @autoreleasepool {\n";
  Printf.bprintf output "    if (@available(macOS %d.%d, *)) {\n"
    entry.expect.availability.macos_major
    entry.expect.availability.macos_minor;
  Buffer.add_string output "      @try {\n";
  Printf.bprintf output "        %s %s =\n" receiver.objc_type receiver.local_name;
  Printf.bprintf output "            object_of_handle(%s, Handle_kind::%s);\n"
    receiver.raw_name receiver.handle_kind;
  List.iter (argument_conversion output) binding.arguments;
  Printf.bprintf output "        %s;\n"
    (objc_call receiver entry.expect.name binding.arguments);
  Buffer.add_string output "        CAMLreturn(result_unit());\n";
  Buffer.add_string output "      } @catch (NSException *exception) {\n";
  Buffer.add_string output "        CAMLreturn(result_error(exception.reason));\n";
  Buffer.add_string output "      }\n";
  Buffer.add_string output "    }\n";
  Printf.bprintf output "    CAMLreturn(result_error_text(%s));\n"
    (c_string entry.expect.availability.unavailable_error);
  Buffer.add_string output "  }\n";
  Buffer.add_string output "}\n\n"

let add_native_getter_binding output (entry : Binding_plan.entry)
    (binding : Binding_plan.direct_getter) =
  let receiver = receiver_spec binding.receiver in
  Buffer.add_string output "extern \"C\" CAMLprim value\n";
  Printf.bprintf output "%s(value %s) {\n" binding.c_symbol receiver.raw_name;
  Printf.bprintf output "  %s\n" (camlparam [ receiver.raw_name ]);
  Buffer.add_string output "  CAMLlocal2(result, copied_result);\n";
  Buffer.add_string output "  @autoreleasepool {\n";
  Printf.bprintf output "    if (@available(macOS %d.%d, *)) {\n"
    entry.expect.availability.macos_major
    entry.expect.availability.macos_minor;
  Buffer.add_string output "      @try {\n";
  Printf.bprintf output "        %s %s =\n" receiver.objc_type receiver.local_name;
  Printf.bprintf output "            object_of_handle(%s, Handle_kind::%s);\n"
    receiver.raw_name receiver.handle_kind;
  (match binding.result with
   | Binding_plan.Nsuint_to_checked_int64 { overflow_error } ->
       Printf.bprintf output "        const NSUInteger native_result = %s;\n"
         (objc_call receiver entry.expect.name []);
       Buffer.add_string output
         "        if (native_result > static_cast<NSUInteger>(INT64_MAX)) {\n";
       Printf.bprintf output "          CAMLreturn(result_error_text(%s));\n"
         (c_string overflow_error);
       Buffer.add_string output "        }\n";
       Buffer.add_string output
         "        copied_result = caml_copy_int64(\n            static_cast<std::int64_t>(native_result));\n";
       Buffer.add_string output "        result = result_ok(copied_result);\n";
       Buffer.add_string output "        CAMLreturn(result);\n");
  Buffer.add_string output "      } @catch (NSException *exception) {\n";
  Buffer.add_string output "        CAMLreturn(result_error(exception.reason));\n";
  Buffer.add_string output "      }\n";
  Buffer.add_string output "    }\n";
  Printf.bprintf output "    CAMLreturn(result_error_text(%s));\n"
    (c_string entry.expect.availability.unavailable_error);
  Buffer.add_string output "  }\n";
  Buffer.add_string output "}\n\n"

let add_native_binding output entry =
  match entry.Binding_plan.disposition with
  | Binding_plan.Generate (Binding_plan.Direct_void binding) ->
      add_native_void_binding output entry binding
  | Binding_plan.Generate (Binding_plan.Direct_getter binding) ->
      add_native_getter_binding output entry binding
  | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
      fail "internal error: non-generated Metal binding %s" entry.sdk_id

let native_include ~header entries =
  let output = Buffer.create 8192 in
  Printf.bprintf output "/* %s */\n\n" header;
  List.iter (add_native_binding output) entries;
  let contents = Buffer.contents output in
  [ "objc_msgSend"; "performSelector"; "valueForKey" ]
  |> List.iter (fun forbidden ->
    if contains ~needle:forbidden contents then
      fail "forbidden dynamic Objective-C dispatch in generated bridge: %s"
        forbidden);
  contents

let argument_json (argument : Binding_plan.argument) =
  match argument.kind with
  | Binding_plan.Enum_int { enum_type; cases } ->
      `Assoc
        [ "name", `String argument.name
        ; "abi", `String "ocaml_int_to_objc_enum"
        ; "objc_type", `String (enum_objc_type enum_type)
        ; "error", `String argument.error
        ; "cases",
          `List
            (List.map
               (fun (case : Binding_plan.enum_case) ->
                 `Assoc
                   [ "sdk_id", `String case.Binding_plan.sdk_id
                   ; "value", `Int case.value
                   ])
               cases)
        ]
  | Binding_plan.Unsigned_int { minimum; multiple_of } ->
      `Assoc
        [ "name", `String argument.name
        ; "abi", `String "ocaml_int_to_nsuint"
        ; "objc_type", `String "NSUInteger"
        ; "error", `String argument.error
        ; "minimum", `Int minimum
        ; "multiple_of",
          (match multiple_of with None -> `Null | Some value -> `Int value)
        ]

let companion_json (companion : Binding_plan.companion) =
  `Assoc
    [ "sdk_id", `String companion.sdk_id
    ; "kind", `String companion.kind
    ; "owner", `String companion.owner
    ; "name", `String companion.name
    ; "header", `String companion.header
    ; "signature", `String companion.signature
    ; "attributes", `List (List.map (fun value -> `String value) companion.attributes)
    ]

let safe_api_json = function
  | Some evidence ->
      `Assoc
        [ "operation", `String evidence.Binding_plan.operation
        ; "module_path",
          `List (List.map (fun name -> `String name) evidence.module_path)
        ; "value_name", `String evidence.value_name
        ; "test_value", `String evidence.test_value
        ; "test_call",
          `List (List.map (fun name -> `String name) evidence.test_call)
        ]
  | None -> `Null

let result_json = function
  | Binding_plan.Nsuint_to_checked_int64 { overflow_error } ->
      `Assoc
        [ "abi", `String "objc_nsuint_to_checked_ocaml_int64"
        ; "objc_type", `String "NSUInteger"
        ; "ocaml_type", `String "int64"
        ; "overflow_error", `String overflow_error
        ]

let entry_json entry =
  let ocaml_name, c_symbol, receiver_kind = generated_identity entry in
  let receiver = receiver_spec receiver_kind in
  let generation_fields =
    match entry.Binding_plan.disposition with
    | Binding_plan.Generate (Binding_plan.Direct_void binding) ->
        [ "arguments", `List (List.map argument_json binding.arguments)
        ; "template", `String "direct_void_scalar"
        ]
    | Binding_plan.Generate (Binding_plan.Direct_getter binding) ->
        [ "arguments", `List []
        ; "result", result_json binding.result
        ; "template", `String "direct_getter"
        ]
    | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
        fail "internal error: non-generated Metal binding %s" entry.sdk_id
  in
  `Assoc
    ([ "sdk_id", `String entry.Binding_plan.sdk_id
     ; "owner", `String entry.expect.owner
     ; "selector", `String entry.expect.name
     ; "header", `String entry.expect.header
     ; "signature", `String entry.expect.signature
     ; "macos_introduced",
       `String
         (Printf.sprintf "%d.%d" entry.expect.availability.macos_major
            entry.expect.availability.macos_minor)
     ; "ocaml_name", `String ocaml_name
     ; "c_symbol", `String c_symbol
     ; "receiver_handle_kind", `String receiver.handle_kind
     ]
     @ generation_fields
     @ [ "companions", `List (List.map companion_json entry.companions)
       ; "safe_api", safe_api_json entry.safe_api
       ])

let manifest ~sdk_version ~plan_sha256 ~generator_sha256 ~inventory_sha256
    ~raw_ml_contents ~raw_mli_contents ~native_contents entries =
  pretty_json
    (`Assoc
       [ "schema", `Int 1
       ; "kind", `String "metal_generated_bindings"
       ; "generator", `String "tools/metal/generate_bindings.exe"
       ; "sdk_version", `String sdk_version
       ; "binding_plan_source_sha256", `String plan_sha256
       ; "generator_source_sha256", `String generator_sha256
       ; "inventory_sha256", `String inventory_sha256
       ; "raw_ml_sha256", `String (sha256 raw_ml_contents)
       ; "raw_mli_sha256", `String (sha256 raw_mli_contents)
       ; "native_include_sha256", `String (sha256 native_contents)
       ; "entry_count", `Int (List.length entries)
       ; "entries", `List (List.map entry_json entries)
       ])

type options =
  { inventory : string
  ; plan_source : string
  ; generator_source : string
  ; manual_native : string
  ; manual_raw_ml : string
  ; manual_raw_mli : string
  ; safe_source : string
  ; safe_tests : string
  ; output_raw_ml : string
  ; output_raw_mli : string
  ; output_native : string
  ; output_manifest : string
  }

let options () =
  let inventory = ref "" in
  let plan_source = ref "" in
  let generator_source = ref "" in
  let manual_native = ref "" in
  let manual_raw_ml = ref "" in
  let manual_raw_mli = ref "" in
  let safe_source = ref "" in
  let safe_tests = ref "" in
  let output_raw_ml = ref "" in
  let output_raw_mli = ref "" in
  let output_native = ref "" in
  let output_manifest = ref "" in
  let set target value = target := value in
  let arguments =
    [ "--inventory", Arg.String (set inventory), "Pinned inventory JSON"
    ; "--plan-source", Arg.String (set plan_source), "Binding plan source"
    ; ( "--generator-source"
      , Arg.String (set generator_source)
      , "Generator source" )
    ; "--manual-native", Arg.String (set manual_native), "Manual bridge source"
    ; "--manual-raw-ml", Arg.String (set manual_raw_ml), "Manual raw ML source"
    ; "--manual-raw-mli", Arg.String (set manual_raw_mli), "Manual raw MLI source"
    ; "--safe-source", Arg.String (set safe_source), "Handwritten safe Metal API"
    ; "--safe-tests", Arg.String (set safe_tests), "Metal conformance tests"
    ; "--output-raw-ml", Arg.String (set output_raw_ml), "Generated raw ML"
    ; "--output-raw-mli", Arg.String (set output_raw_mli), "Generated raw MLI"
    ; "--output-native", Arg.String (set output_native), "Generated native include"
    ; ( "--output-manifest"
      , Arg.String (set output_manifest)
      , "Generated provenance manifest" )
    ]
  in
  Arg.parse arguments
    (fun argument -> fail "unexpected Metal generator argument: %s" argument)
    "Generate typed Metal raw/native bindings";
  let require name value =
    if !value = "" then fail "missing required Metal generator option %s" name;
    !value
  in
  { inventory = require "--inventory" inventory
  ; plan_source = require "--plan-source" plan_source
  ; generator_source = require "--generator-source" generator_source
  ; manual_native = require "--manual-native" manual_native
  ; manual_raw_ml = require "--manual-raw-ml" manual_raw_ml
  ; manual_raw_mli = require "--manual-raw-mli" manual_raw_mli
  ; safe_source = require "--safe-source" safe_source
  ; safe_tests = require "--safe-tests" safe_tests
  ; output_raw_ml = require "--output-raw-ml" output_raw_ml
  ; output_raw_mli = require "--output-raw-mli" output_raw_mli
  ; output_native = require "--output-native" output_native
  ; output_manifest = require "--output-manifest" output_manifest
  }

let main () =
  let options = options () in
  let inventory_contents = read_file options.inventory in
  let plan_sha256 = read_file options.plan_source |> sha256 in
  let sdk_version, inventory_plan_sha256, inventory =
    load_inventory options.inventory
  in
  if inventory_plan_sha256 <> plan_sha256 then
    fail
      "Metal inventory binding-plan provenance drift: regenerate the pinned inventory";
  let generator_sha256 = read_file options.generator_source |> sha256 in
  let inventory_sha256 = sha256 inventory_contents in
  let entries =
    validate_plan inventory (read_file options.manual_native)
      (read_file options.manual_raw_ml) (read_file options.manual_raw_mli)
      (read_file options.safe_source) (read_file options.safe_tests)
  in
  let header = generated_header ~plan_sha256 ~inventory_sha256 in
  let raw_ml_contents = raw_ml ~header entries in
  let raw_mli_contents = raw_mli ~header entries in
  let native_contents = native_include ~header entries in
  let manifest_contents =
    manifest ~sdk_version ~plan_sha256 ~generator_sha256 ~inventory_sha256
      ~raw_ml_contents ~raw_mli_contents ~native_contents entries
  in
  write_file options.output_raw_ml raw_ml_contents;
  write_file options.output_raw_mli raw_mli_contents;
  write_file options.output_native native_contents;
  write_file options.output_manifest manifest_contents;
  Printf.printf "generated %d typed Metal bindings\n%!" (List.length entries)

let () = protect_main main
