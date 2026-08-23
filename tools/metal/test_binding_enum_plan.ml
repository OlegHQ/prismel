open Support

module String_table = Hashtbl

type declaration =
  { identifier : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; signature : string
  ; classification : string
  ; constant_value : string option
  }

type family_entries =
  { mutable enum_declarations : declaration list
  ; mutable typedef_declarations : declaration list
  ; cases : (string, declaration) String_table.t
  }

let require_string field value =
  match member_string field value with
  | Some value -> value
  | None -> fail "Metal enum inventory field %s must be a string" field

let nullable_string field value =
  match member field value with
  | Some (`String value) -> Some value
  | Some `Null | None -> None
  | Some _ ->
      fail "Metal enum inventory field %s must be a string or null" field

let declaration value =
  { identifier = require_string "id" value
  ; kind = require_string "kind" value
  ; name = require_string "name" value
  ; owner = nullable_string "owner" value
  ; signature = require_string "signature" value
  ; classification = require_string "classification" value
  ; constant_value = nullable_string "constant_value" value
  }

let parse_options () =
  let inventory = ref "" in
  Arg.parse
    [ ( "--inventory"
      , Arg.Set_string inventory
      , "Pinned Metal API inventory to validate" )
    ]
    (fun value -> fail "unexpected enum-plan test argument: %s" value)
    "Test the fail-closed bulk Metal enum plan";
  if String.equal !inventory "" then
    fail "missing enum-plan test option --inventory";
  !inventory

let selected_simple_identifier_family families ~prefix identifier =
  if String.starts_with ~prefix identifier then
    let family =
      String.sub identifier (String.length prefix)
        (String.length identifier - String.length prefix)
    in
    if String_table.mem families family then Some family else None
  else None

let selected_case_identifier families identifier =
  match String.split_on_char ':' identifier with
  | "enum-case" :: family :: case_parts
    when String_table.mem families family ->
      Some (family, String.concat ":" case_parts)
  | _ -> None

let selected_owner families = function
  | Some owner when String_table.mem families owner -> Some owner
  | Some _ | None -> None

let require_same_family description left right =
  match left, right with
  | Some left, Some right when not (String.equal left right) ->
      fail "%s names conflicting Metal enum families %s and %s" description
        left right
  | Some family, _ | _, Some family -> Some family
  | None, None -> None

let add_enum bucket declaration =
  bucket.enum_declarations <- declaration :: bucket.enum_declarations

let add_typedef bucket declaration =
  bucket.typedef_declarations <- declaration :: bucket.typedef_declarations

let add_case family bucket declaration =
  if String_table.mem bucket.cases declaration.name then
    fail "duplicate Metal enum case %s in family %s" declaration.name family;
  String_table.add bucket.cases declaration.name declaration

let require_unreviewed description declaration =
  if not (String.equal declaration.classification "unreviewed") then
    fail "%s %s must be unreviewed, found %s" description
      declaration.identifier declaration.classification

let require_case_classification declaration =
  match declaration.classification with
  | "unreviewed" | "scope-excluded" -> ()
  | classification ->
      fail
        "Metal enum case %s must be unreviewed or scope-excluded, found %s"
        declaration.identifier classification

let index_inventory families path =
  let root = read_file path |> Yojson.Safe.from_string in
  if member_int "schema" root <> Some 2 then
    fail "Metal enum inventory schema must be 2";
  let symbols =
    match member_list "symbols" root with
    | Some symbols -> symbols
    | None -> fail "Metal enum inventory symbols field must be a list"
  in
  let identifiers = String_table.create (List.length symbols) in
  let parsed_declarations = ref [] in
  List.iter
    (fun value ->
      let declaration = declaration value in
      parsed_declarations := declaration :: !parsed_declarations;
      if String_table.mem identifiers declaration.identifier then
        fail "duplicate Metal inventory identifier: %s" declaration.identifier;
      String_table.add identifiers declaration.identifier declaration;
      let owner_family = selected_owner families declaration.owner in
      let enum_id_family =
        selected_simple_identifier_family families ~prefix:"enum:"
          declaration.identifier
      in
      let typedef_id_family =
        selected_simple_identifier_family families ~prefix:"typedef:"
          declaration.identifier
      in
      let case_id =
        selected_case_identifier families declaration.identifier
      in
      match declaration.kind with
      | "enum" ->
          let name_family =
            if String_table.mem families declaration.name then
              Some declaration.name
            else None
          in
          let family =
            require_same_family "Metal enum declaration" name_family
              enum_id_family
            |> require_same_family "Metal enum declaration" owner_family
            |> require_same_family "Metal enum declaration" typedef_id_family
          in
          (match family, case_id with
           | None, None -> ()
           | Some family, None ->
               if declaration.owner <> None then
                 fail "Metal enum declaration %s must not have an owner"
                   declaration.identifier;
               let expected_identifier = "enum:" ^ family in
               if not (String.equal declaration.identifier expected_identifier)
                  || not (String.equal declaration.name family)
               then
                 fail "non-canonical Metal enum declaration for family %s: %s"
                   family declaration.identifier;
               add_enum (String_table.find families family) declaration
           | _, Some (family, _) ->
               fail "Metal enum family %s has a non-case case identifier %s"
                 family declaration.identifier)
      | "typedef" ->
          let name_family =
            if String_table.mem families declaration.name then
              Some declaration.name
            else None
          in
          let family =
            require_same_family "Metal enum typedef" name_family
              typedef_id_family
            |> require_same_family "Metal enum typedef" owner_family
            |> require_same_family "Metal enum typedef" enum_id_family
          in
          (match family, case_id with
           | None, None -> ()
           | Some family, None ->
               if declaration.owner <> None then
                 fail "Metal enum typedef %s must not have an owner"
                   declaration.identifier;
               let expected_identifier = "typedef:" ^ family in
               if not (String.equal declaration.identifier expected_identifier)
                  || not (String.equal declaration.name family)
               then
                 fail "non-canonical Metal enum typedef for family %s: %s"
                   family declaration.identifier;
               add_typedef (String_table.find families family) declaration
           | _, Some (family, _) ->
               fail "Metal enum family %s has a non-case case identifier %s"
                 family declaration.identifier)
      | "enum-case" ->
          let case_id_family, case_id_name =
            match case_id with
            | Some (family, name) -> Some family, Some name
            | None -> None, None
          in
          let family =
            require_same_family "Metal enum case" owner_family case_id_family
          in
          (match family with
           | None -> ()
           | Some family ->
               let case_name = Option.value ~default:"" case_id_name in
               let expected_identifier =
                 Printf.sprintf "enum-case:%s:%s" family declaration.name
               in
               if not (String.equal case_name declaration.name)
                  || not (String.equal declaration.identifier expected_identifier)
                  || declaration.owner <> Some family
               then
                 fail "non-canonical Metal enum case for family %s: %s" family
                   declaration.identifier;
               require_case_classification declaration;
               (match declaration.constant_value with
                | Some _ -> ()
                | None ->
                    fail "Metal enum case %s has no constant_value"
                      declaration.identifier);
               add_case family (String_table.find families family) declaration)
      | _ ->
          let associated_family =
            require_same_family "Metal enum-associated declaration"
              owner_family enum_id_family
            |> require_same_family "Metal enum-associated declaration"
                 typedef_id_family
          in
          let associated_family =
            match associated_family, case_id with
            | Some family, Some (case_family, _)
              when not (String.equal family case_family) ->
                fail
                  "Metal enum-associated declaration %s names conflicting families"
                  declaration.identifier
            | Some family, _ -> Some family
            | None, Some (family, _) -> Some family
            | None, None -> None
          in
          (match associated_family with
           | None -> ()
           | Some family ->
               fail "Metal enum family %s has unexpected %s declaration %s"
                 family declaration.kind declaration.identifier))
    symbols;
  identifiers, List.rev !parsed_declarations

let require_singleton description family = function
  | [ declaration ] ->
      require_unreviewed description declaration;
      declaration
  | [] -> fail "Metal enum family %s is missing its %s" family description
  | declarations ->
      fail "Metal enum family %s has %d %s entries" family
        (List.length declarations) description

let build_families () =
  let families =
    String_table.create Binding_enum_plan.expected_family_count
  in
  List.iter
    (fun family ->
      if String.equal family "" then fail "Metal enum family name is empty";
      if String_table.mem families family then
        fail "duplicate Metal enum family in plan: %s" family;
      String_table.add families family
        { enum_declarations = []; typedef_declarations = []
        ; cases = String_table.create 16
        })
    Binding_enum_plan.family_names;
  if String_table.length families <> 61 then
    fail "Metal enum plan must select exactly 61 families, found %d"
      (String_table.length families);
  if Binding_enum_plan.expected_family_count <> 61
     || Binding_enum_plan.expected_case_count <> 326
     || Binding_enum_plan.expected_declaration_count <> 448
  then fail "Metal enum plan's checked aggregate totals drifted from 61/326/448";
  families

let check_families families =
  let enum_count = ref 0 in
  let typedef_count = ref 0 in
  let case_count = ref 0 in
  let scope_excluded_case_count = ref 0 in
  String_table.iter
    (fun family entries ->
      ignore
        (require_singleton "enum declaration" family
           entries.enum_declarations);
      ignore
        (require_singleton "typedef declaration" family
           entries.typedef_declarations);
      if String_table.length entries.cases = 0 then
        fail "Metal enum family %s has no enum cases" family;
      incr enum_count;
      incr typedef_count;
      case_count := !case_count + String_table.length entries.cases;
      String_table.iter
        (fun _ declaration ->
          if
            String.equal declaration.classification "scope-excluded"
          then incr scope_excluded_case_count)
        entries.cases)
    families;
  if !enum_count <> 61 || !typedef_count <> 61 || !case_count <> 326 then
    fail
      "Metal enum inventory totals drifted: %d enums, %d typedefs, %d cases"
      !enum_count !typedef_count !case_count;
  let declaration_count = !enum_count + !typedef_count + !case_count in
  if declaration_count <> 448 then
    fail "Metal enum inventory must select 448 declarations, found %d"
      declaration_count;
  if !scope_excluded_case_count <> 25 then
    fail
      "Metal enum inventory must select 25 scope-excluded cases, found %d"
      !scope_excluded_case_count;
  !scope_excluded_case_count

let check_uint64_max identifiers =
  let identifier =
    "enum-case:MTLDeviceLocation:MTLDeviceLocationUnspecified"
  in
  match String_table.find_opt identifiers identifier with
  | Some declaration
    when declaration.constant_value = Some "18446744073709551615" ->
      ()
  | Some declaration ->
      fail "Metal UINT64_MAX enum case %s drifted to %s" identifier
        (Option.value ~default:"null" declaration.constant_value)
  | None -> fail "Metal UINT64_MAX enum case %s is missing" identifier

let codegen_declaration (declaration : declaration) :
    Binding_enum_codegen.declaration =
  { id = declaration.identifier
  ; kind = declaration.kind
  ; name = declaration.name
  ; owner = declaration.owner
  ; signature = declaration.signature
  ; classification = declaration.classification
  ; constant_value = declaration.constant_value
  }

let check_codegen_manifest identifiers declarations =
  let selection =
    declarations |> List.map codegen_declaration
    |> Binding_enum_codegen.select
         ~family_names:Binding_enum_plan.family_names
  in
  if
    selection.family_count <> 61 || selection.case_count <> 326
    || selection.scope_excluded_case_count <> 25
    || selection.declaration_count <> 448
  then
    fail
      "Metal enum codegen totals drifted: %d families, %d cases, %d scope-excluded, %d declarations"
      selection.family_count selection.case_count
      selection.scope_excluded_case_count selection.declaration_count;
  let manifest = Binding_enum_codegen.manifest_json selection in
  if member_int "enum_scope_excluded_case_count" manifest <> Some 25 then
    fail "Metal enum manifest scope-excluded aggregate count drifted";
  let families =
    match member_list "enum_families" manifest with
    | Some families -> families
    | None -> fail "Metal enum manifest has no enum_families list"
  in
  let cases =
    List.concat_map
      (fun family ->
        match member_list "cases" family with
        | Some cases -> cases
        | None -> fail "Metal enum manifest family has no cases list")
      families
  in
  if List.length cases <> 326 then
    fail "Metal enum manifest must contain 326 cases, found %d"
      (List.length cases);
  let raw_ml = Binding_enum_codegen.render_raw_ml selection in
  let scope_excluded_count = ref 0 in
  List.iter
    (fun case ->
      let identifier = require_string "id" case in
      let classification = require_string "classification" case in
      let declaration =
        match String_table.find_opt identifiers identifier with
        | Some declaration -> declaration
        | None ->
            fail "Metal enum manifest case is absent from inventory: %s"
              identifier
      in
      if not (String.equal classification declaration.classification) then
        fail "Metal enum manifest classification drift for %s" identifier;
      let decimal = require_string "uint64_decimal" case in
      let expected_decimal =
        match declaration.constant_value with
        | Some value -> value
        | None -> fail "Metal enum manifest case has no inventory value: %s"
                    identifier
      in
      if not (String.equal decimal expected_decimal) then
        fail "Metal enum manifest decimal value drift for %s" identifier;
      let bits = Binding_enum_codegen.uint64_bits expected_decimal in
      let expected_bits = Printf.sprintf "0x%016Lx" bits in
      if member_string "uint64_bits" case <> Some expected_bits then
        fail "Metal enum manifest bit pattern drift for %s" identifier;
      let ocaml_name = require_string "ocaml_name" case in
      let expected_raw =
        Printf.sprintf
          "let %s : int64 = 0x%016LxL (* uint64 %s; %s *)"
          ocaml_name bits expected_decimal declaration.name
      in
      if not (contains ~needle:expected_raw raw_ml) then
        fail "Metal enum raw constant drift for %s" identifier;
      match classification with
      | "unreviewed" -> ()
      | "scope-excluded" -> incr scope_excluded_count
      | other ->
          fail "Metal enum manifest contains disallowed classification %s for %s"
            other identifier)
    cases;
  if !scope_excluded_count <> 25 then
    fail "Metal enum manifest must contain 25 scope-excluded cases, found %d"
      !scope_excluded_count;
  if
    not
      (contains
         ~needle:
           "let mtl_device_location_unspecified : int64 = 0xffffffffffffffffL (* uint64 18446744073709551615; MTLDeviceLocationUnspecified *)"
         raw_ml)
  then fail "Metal enum codegen UINT64_MAX constant drifted";
  if
    not
      (contains
         ~needle:
           "let mtl_language_version1_0 : int64 = 0x0000000000010000L (* uint64 65536; MTLLanguageVersion1_0 *)"
         raw_ml)
  then fail "Metal scope-excluded enum constant generation drifted"

let replace_classification identifier classification declarations =
  let found = ref false in
  let declarations =
    List.map
      (fun (declaration : declaration) ->
        if String.equal declaration.identifier identifier then begin
          found := true;
          { declaration with classification }
        end
        else declaration)
      declarations
  in
  if not !found then
    fail "Metal enum rejection fixture is missing %s" identifier;
  declarations

let expect_codegen_rejection label needle declarations =
  match
    declarations |> List.map codegen_declaration
    |> Binding_enum_codegen.select
         ~family_names:Binding_enum_plan.family_names
  with
  | exception Binding_enum_codegen.Error message ->
      if not (contains ~needle message) then
        fail "%s reported the wrong error: %s" label message
  | _ -> fail "%s was accepted" label

let check_codegen_rejections declarations =
  replace_classification
    "enum-case:MTLLanguageVersion:MTLLanguageVersion1_0" "bound"
    declarations
  |> expect_codegen_rejection "bound Metal enum case"
       "expected unreviewed or scope-excluded enum case";
  replace_classification "enum:MTLFeatureSet" "scope-excluded" declarations
  |> expect_codegen_rejection "scope-excluded Metal enum declaration"
       "expected unreviewed";
  replace_classification "typedef:MTLFeatureSet" "scope-excluded"
    declarations
  |> expect_codegen_rejection "scope-excluded Metal enum typedef"
       "expected unreviewed"

let main () =
  let inventory = parse_options () in
  let families = build_families () in
  let identifiers, declarations = index_inventory families inventory in
  let scope_excluded_case_count = check_families families in
  check_uint64_max identifiers;
  check_codegen_manifest identifiers declarations;
  check_codegen_rejections declarations;
  Printf.printf
    "Metal bulk enum plan is closed over 61 families, 326 cases (including %d scope-excluded), and 448 declarations\n%!"
    scope_excluded_case_count

let () = protect_main main
