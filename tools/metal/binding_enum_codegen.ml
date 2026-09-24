exception Error of string

let fail format = Printf.ksprintf (fun message -> raise (Error message)) format

type declaration =
  { id : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; signature : string
  ; classification : string
  ; constant_value : string option
  ; macos_introduced : Binding_availability.version option
  }

type selected_case =
  { declaration : declaration
  ; ocaml_name : string
  ; unsigned_decimal : string
  ; bits : int64
  }

type family =
  { sdk_name : string
  ; module_name : string
  ; enum_declaration : declaration
  ; typedef_declaration : declaration
  ; cases : selected_case list
  }

type selection =
  { families : family list
  ; identifiers : string list
  ; family_count : int
  ; case_count : int
  ; scope_excluded_case_count : int
  ; declaration_count : int
  }

let is_ascii_lower character = character >= 'a' && character <= 'z'
let is_ascii_upper character = character >= 'A' && character <= 'Z'
let is_ascii_letter character = is_ascii_lower character || is_ascii_upper character
let is_ascii_digit character = character >= '0' && character <= '9'
let is_ascii_alphanumeric character = is_ascii_letter character || is_ascii_digit character

let ocaml_keywords =
  [ "and"; "as"; "assert"; "asr"; "begin"; "class"; "constraint"
  ; "continue"; "do"; "done"; "downto"; "effect"; "else"; "end"
  ; "exception"; "external"; "false"; "for"; "fun"; "function"
  ; "functor"; "if"; "in"; "include"; "inherit"; "initializer"; "land"
  ; "lazy"; "let"; "lor"; "lsl"; "lsr"; "lxor"; "match"; "method"
  ; "mod"; "module"; "mutable"; "new"; "nonrec"; "object"; "of"
  ; "open"; "or"; "perform"; "private"; "rec"; "sig"; "struct"
  ; "then"; "to"; "true"; "try"; "type"; "val"; "virtual"; "when"
  ; "while"; "with"
  ]

let is_ocaml_keyword value = List.exists (String.equal value) ocaml_keywords

let validate_sdk_identifier value =
  if String.equal value "" then fail "empty SDK identifier";
  if not (is_ascii_letter value.[0]) then
    fail "SDK identifier must begin with an ASCII letter: %S" value;
  String.iter
    (fun character ->
      if not (is_ascii_alphanumeric character || character = '_') then
        fail "unsupported character in SDK identifier %S" value)
    value

let snake_case value =
  validate_sdk_identifier value;
  let length = String.length value in
  let output = Buffer.create (length + 8) in
  let last_is_separator = ref true in
  let add_separator () =
    if Buffer.length output > 0 && not !last_is_separator then begin
      Buffer.add_char output '_';
      last_is_separator := true
    end
  in
  for index = 0 to length - 1 do
    let character = value.[index] in
    if character = '_' then add_separator ()
    else begin
      let previous = if index = 0 then None else Some value.[index - 1] in
      let next = if index + 1 = length then None else Some value.[index + 1] in
      let starts_word =
        is_ascii_upper character
        &&
        match previous, next with
        | Some previous, _ when is_ascii_lower previous || is_ascii_digit previous ->
            true
        | Some previous, Some next
          when is_ascii_upper previous && is_ascii_lower next ->
            true
        | _ -> false
      in
      if starts_word then add_separator ();
      Buffer.add_char output (Char.lowercase_ascii character);
      last_is_separator := false
    end
  done;
  let result = Buffer.contents output in
  let result =
    if String.ends_with ~suffix:"_" result then
      String.sub result 0 (String.length result - 1)
    else result
  in
  if String.equal result "" then fail "SDK identifier converts to an empty name: %S" value;
  result

let ocaml_value_identifier value =
  let result = snake_case value in
  if not (is_ascii_lower result.[0]) then
    fail "SDK identifier does not convert to an OCaml value identifier: %S" value;
  if is_ocaml_keyword result then
    fail "SDK identifier %S converts to the OCaml keyword %S" value result;
  result

let ocaml_module_identifier value =
  let lower = snake_case value in
  if is_ocaml_keyword lower then
    fail "SDK identifier %S converts from the OCaml keyword %S" value lower;
  let bytes = Bytes.of_string lower in
  Bytes.set bytes 0 (Char.uppercase_ascii (Bytes.get bytes 0));
  Bytes.unsafe_to_string bytes

let maximum_uint64_decimal = "18446744073709551615"

let uint64_bits value =
  let length = String.length value in
  if length = 0 then fail "empty uint64 decimal value";
  String.iter
    (fun character ->
      if not (is_ascii_digit character) then
        fail "malformed uint64 decimal value: %S" value)
    value;
  if length > 1 && value.[0] = '0' then
    fail "non-canonical uint64 decimal value: %S" value;
  let maximum_length = String.length maximum_uint64_decimal in
  if
    length > maximum_length
    || (length = maximum_length
       && String.compare value maximum_uint64_decimal > 0)
  then fail "uint64 decimal value is out of range: %s" value;
  let bits = ref 0L in
  String.iter
    (fun character ->
      bits :=
        Int64.add (Int64.mul !bits 10L)
          (Int64.of_int (Char.code character - Char.code '0')))
    value;
  !bits

module String_set = Set.Make (String)

let reject_duplicate_names ~what names =
  let _ =
    List.fold_left
      (fun seen name ->
        if String_set.mem name seen then fail "duplicate %s: %s" what name;
        String_set.add name seen)
      String_set.empty names
  in
  ()

let require_shape ~family ~expected_kind ~expected_id ~expected_signatures
    declaration =
  if not (String.equal declaration.id expected_id) then
    fail "Metal enum family %s has non-canonical %s identifier %s" family
      expected_kind declaration.id;
  if not (String.equal declaration.kind expected_kind) then
    fail "Metal inventory %s has kind %s, expected %s" declaration.id
      declaration.kind expected_kind;
  if not (String.equal declaration.name family) then
    fail "Metal inventory %s has name %s, expected %s" declaration.id
      declaration.name family;
  if Option.is_some declaration.owner then
    fail "Metal inventory %s unexpectedly has an owner" declaration.id;
  if not (List.exists (String.equal declaration.signature) expected_signatures) then
    fail "Metal inventory %s has unsupported signature %S" declaration.id
      declaration.signature;
  if
    declaration.classification <> "unreviewed"
    && declaration.classification <> "bound"
  then
    fail "Metal inventory %s is %s, expected unreviewed or bound" declaration.id
      declaration.classification;
  if Option.is_some declaration.constant_value then
    fail "Metal inventory %s unexpectedly has a constant value" declaration.id

let require_case_classification declaration =
  match declaration.classification with
  | "unreviewed" | "bound" | "scope-excluded" -> ()
  | classification ->
      fail
        "Metal inventory %s is %s, expected unreviewed, bound, or scope-excluded enum case"
        declaration.id classification

let id_family = function
  | id when String.starts_with ~prefix:"enum-case:" id ->
      let suffix = String.sub id 10 (String.length id - 10) in
      let family =
        match String.index_opt suffix ':' with
        | Some separator -> String.sub suffix 0 separator
        | None -> suffix
      in
      Some family
  | id when String.starts_with ~prefix:"enum:" id ->
      let suffix = String.sub id 5 (String.length id - 5) in
      let family =
        match String.index_opt suffix ':' with
        | Some separator -> String.sub suffix 0 separator
        | None -> suffix
      in
      Some family
  | id when String.starts_with ~prefix:"typedef:" id ->
      let suffix = String.sub id 8 (String.length id - 8) in
      let family =
        match String.index_opt suffix ':' with
        | Some separator -> String.sub suffix 0 separator
        | None -> suffix
      in
      Some family
  | _ -> None

let validate_associated_shape ~family declaration =
  match declaration.kind with
  | "enum" ->
      if
        not
          (String.equal declaration.id ("enum:" ^ family)
           && String.equal declaration.name family
           && declaration.owner = None)
      then
        fail "malformed enum declaration associated with Metal family %s: %s"
          family declaration.id
  | "typedef" ->
      if
        not
          (String.equal declaration.id ("typedef:" ^ family)
           && String.equal declaration.name family
           && declaration.owner = None)
      then
        fail "malformed typedef declaration associated with Metal family %s: %s"
          family declaration.id
  | "enum-case" ->
      if
        not
          (declaration.owner = Some family
           && String.equal declaration.id
                (Printf.sprintf "enum-case:%s:%s" family declaration.name))
      then
        fail "malformed enum case associated with Metal family %s: %s" family
          declaration.id
  | kind ->
      fail "unexpected %s declaration associated with Metal enum family %s: %s"
        kind family declaration.id

let select ~family_names declarations =
  let family_names = List.sort String.compare family_names in
  reject_duplicate_names ~what:"Metal enum family name" family_names;
  List.iter (fun family -> ignore (ocaml_module_identifier family)) family_names;
  let selected_families =
    List.fold_left
      (fun families family -> String_set.add family families)
      String_set.empty family_names
  in
  let by_id = Hashtbl.create (max 16 (List.length declarations * 2)) in
  let by_kind_and_name = Hashtbl.create 128 in
  let cases_by_owner = Hashtbl.create 128 in
  List.iter
    (fun (declaration : declaration) ->
      if String.equal declaration.id "" then fail "empty Metal inventory identifier";
      if Hashtbl.mem by_id declaration.id then
        fail "duplicate Metal inventory identifier: %s" declaration.id;
      Hashtbl.add by_id declaration.id declaration;
      let owner_family =
        Option.bind declaration.owner (fun owner ->
          if String_set.mem owner selected_families then Some owner else None)
      in
      let identifier_family =
        Option.bind (id_family declaration.id) (fun family ->
          if String_set.mem family selected_families then Some family else None)
      in
      (match owner_family, identifier_family with
       | Some owner, Some identifier when not (String.equal owner identifier) ->
           fail
             "Metal declaration %s associates conflicting enum families %s and %s"
             declaration.id owner identifier
       | Some family, _ | None, Some family ->
           validate_associated_shape ~family declaration
       | None, None -> ());
      let key = declaration.kind, declaration.name in
      let same_name =
        Option.value (Hashtbl.find_opt by_kind_and_name key) ~default:[]
      in
      Hashtbl.replace by_kind_and_name key (declaration :: same_name);
      match declaration.kind, declaration.owner with
      | "enum-case", Some owner ->
          let cases = Option.value (Hashtbl.find_opt cases_by_owner owner) ~default:[] in
          Hashtbl.replace cases_by_owner owner (declaration :: cases)
      | _ -> ())
    declarations;
  let require_unique family kind =
    match Hashtbl.find_opt by_kind_and_name (kind, family) with
    | Some [ declaration ] -> declaration
    | None -> fail "Metal enum family %s has no %s declaration" family kind
    | Some declarations ->
        fail "Metal enum family %s has %d %s declarations" family
          (List.length declarations) kind
  in
  let select_family family =
    let enum_declaration = require_unique family "enum" in
    let typedef_declaration = require_unique family "typedef" in
    require_shape ~family ~expected_kind:"enum"
      ~expected_id:("enum:" ^ family) ~expected_signatures:[ "" ]
      enum_declaration;
    require_shape ~family ~expected_kind:"typedef"
      ~expected_id:("typedef:" ^ family)
      ~expected_signatures:[ "enum " ^ family; "NSUInteger"; "uint32_t" ]
      typedef_declaration;
    let declarations =
      Option.value (Hashtbl.find_opt cases_by_owner family) ~default:[]
      |> List.sort (fun (left : declaration) (right : declaration) ->
        let order = String.compare left.name right.name in
        if order <> 0 then order else String.compare left.id right.id)
    in
    if declarations = [] then
      fail "Metal enum family %s has no enum-case declarations" family;
    reject_duplicate_names ~what:("case name in " ^ family)
      (List.map (fun (declaration : declaration) -> declaration.name) declarations);
    let cases =
      List.map
        (fun (declaration : declaration) ->
          let expected_id =
            Printf.sprintf "enum-case:%s:%s" family declaration.name
          in
          if not (String.equal declaration.id expected_id) then
            fail "Metal enum case %s has non-canonical identifier %s"
              declaration.name declaration.id;
          if not (String.equal declaration.kind "enum-case") then
            fail "Metal inventory %s has kind %s, expected enum-case"
              declaration.id declaration.kind;
          if declaration.owner <> Some family then
            fail "Metal enum case %s owner drift" declaration.id;
          let signature_valid =
            if String.equal typedef_declaration.signature ("enum " ^ family) then
              String.equal declaration.signature family
            else
              String.starts_with ~prefix:"(unnamed enum at "
                declaration.signature
              && String.ends_with ~suffix:")" declaration.signature
          in
          if not signature_valid then
            fail "Metal enum case %s has unsupported signature %S"
              declaration.id declaration.signature;
          require_case_classification declaration;
          let unsigned_decimal =
            match declaration.constant_value with
            | Some value -> value
            | None -> fail "Metal enum case %s has no constant value" declaration.id
          in
          let bits = uint64_bits unsigned_decimal in
          let ocaml_name = ocaml_value_identifier declaration.name in
          { declaration; ocaml_name; unsigned_decimal; bits })
        declarations
    in
    reject_duplicate_names ~what:("OCaml case identifier in " ^ family)
      (List.map (fun (case : selected_case) -> case.ocaml_name) cases);
    { sdk_name = family
    ; module_name = ocaml_module_identifier family
    ; enum_declaration
    ; typedef_declaration
    ; cases
    }
  in
  let families = List.map select_family family_names in
  reject_duplicate_names ~what:"OCaml enum-family module identifier"
    (List.map (fun (family : family) -> family.module_name) families);
  let identifiers =
    List.concat_map
      (fun (family : family) ->
        family.enum_declaration.id :: family.typedef_declaration.id
        :: List.map (fun (case : selected_case) -> case.declaration.id) family.cases)
      families
    |> List.sort String.compare
  in
  let family_count = List.length families in
  let case_count =
    List.fold_left
      (fun count (family : family) -> count + List.length family.cases)
      0 families
  in
  let scope_excluded_case_count =
    List.fold_left
      (fun count (family : family) ->
        List.fold_left
          (fun count (case : selected_case) ->
            if
              String.equal case.declaration.classification "scope-excluded"
            then count + 1
            else count)
          count family.cases)
      0 families
  in
  let declaration_count = List.length identifiers in
  if declaration_count <> case_count + (2 * family_count) then
    fail "internal Metal enum selection cardinality mismatch";
  if scope_excluded_case_count > case_count then
    fail "internal Metal enum scope-excluded cardinality mismatch";
  { families; identifiers; family_count; case_count
  ; scope_excluded_case_count; declaration_count
  }

let render_raw_ml ?(outer_module = "Enum_constants") selection =
  let outer_module = ocaml_module_identifier outer_module in
  let output = Buffer.create (selection.case_count * 96) in
  Printf.bprintf output "module %s = struct\n" outer_module;
  List.iter
    (fun (family : family) ->
      Printf.bprintf output "  module %s = struct\n" family.module_name;
      List.iter
        (fun (case : selected_case) ->
          Printf.bprintf output
            "    let %s : int64 = 0x%016LxL (* uint64 %s; %s *)\n"
            case.ocaml_name case.bits case.unsigned_decimal case.declaration.name)
        family.cases;
      Buffer.add_string output "  end\n")
    selection.families;
  Buffer.add_string output "end\n";
  Buffer.contents output

let render_raw_mli ?(outer_module = "Enum_constants") selection =
  let outer_module = ocaml_module_identifier outer_module in
  let output = Buffer.create (selection.case_count * 48) in
  Printf.bprintf output "module %s : sig\n" outer_module;
  List.iter
    (fun (family : family) ->
      Printf.bprintf output "  module %s : sig\n" family.module_name;
      List.iter
        (fun (case : selected_case) ->
          Printf.bprintf output "    val %s : int64\n" case.ocaml_name)
        family.cases;
      Buffer.add_string output "  end\n")
    selection.families;
  Buffer.add_string output "end\n";
  Buffer.contents output

let render_static_asserts selection =
  let output = Buffer.create (selection.case_count * 96) in
  List.iter
    (fun (family : family) ->
      List.iter
        (fun (case : selected_case) ->
          if String.equal case.declaration.classification "bound" then begin
            Option.iter
              (fun (version : Binding_availability.version) ->
                Printf.bprintf output "#if __MAC_OS_X_VERSION_MAX_ALLOWED >= %d\n"
                  ((version.major * 10000) + (version.minor * 100) + version.patch))
              case.declaration.macos_introduced;
            Buffer.add_string output
              "#pragma clang diagnostic push\n#pragma clang diagnostic ignored \"-Wunguarded-availability-new\"\n#pragma clang diagnostic ignored \"-Wdeprecated-declarations\"\n";
            Printf.bprintf output
              "static_assert(static_cast<unsigned long long>(%s) == %sULL);\n"
              case.declaration.name case.unsigned_decimal;
            Buffer.add_string output "#pragma clang diagnostic pop\n";
            Option.iter (fun _ -> Buffer.add_string output "#endif\n")
              case.declaration.macos_introduced
          end)
        family.cases)
    selection.families;
  Buffer.contents output

let manifest_json selection =
  let family_json (family : family) =
    `Assoc
      [ "cases",
        `List
          (List.map
             (fun (case : selected_case) ->
               `Assoc
                 [ "id", `String case.declaration.id
                 ; "classification", `String case.declaration.classification
                 ; "name", `String case.declaration.name
                 ; "ocaml_name", `String case.ocaml_name
                 ; "uint64_bits", `String (Printf.sprintf "0x%016Lx" case.bits)
                 ; "uint64_decimal", `String case.unsigned_decimal
                 ])
             family.cases)
      ; "enum_id", `String family.enum_declaration.id
      ; "module_name", `String family.module_name
      ; "name", `String family.sdk_name
      ; "typedef_id", `String family.typedef_declaration.id
      ]
  in
  `Assoc
    [ "enum_case_count", `Int selection.case_count
    ; "enum_declaration_count", `Int selection.declaration_count
    ; "enum_families", `List (List.map family_json selection.families)
    ; "enum_family_count", `Int selection.family_count
    ; "enum_identifiers",
      `List (List.map (fun identifier -> `String identifier) selection.identifiers)
    ; "enum_scope_excluded_case_count",
      `Int selection.scope_excluded_case_count
    ]
