open Support

module String_set = Set.Make (String)

type declaration =
  { id : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; header : string
  ; line : int
  ; signature : string
  ; classification : string
  ; macos_introduced : string
  ; availability_sources : string list
  }

let required_string name value =
  match member_string name value with
  | Some value -> value
  | None -> fail "Metal enum evidence field %s must be a string" name

let optional_string name value =
  match member name value with
  | None | Some `Null -> ""
  | Some (`String value) -> value
  | Some _ -> fail "Metal enum evidence field %s must be string or null" name

let required_int name value =
  match member_int name value with
  | Some value -> value
  | None -> fail "Metal enum evidence field %s must be an integer" name

let availability_source value =
  Printf.sprintf "%s:%d" (required_string "header" value)
    (required_int "line" value)

let declaration value =
  { id = required_string "id" value
  ; kind = required_string "kind" value
  ; name = required_string "name" value
  ; owner =
      (match member "owner" value with
       | None | Some `Null -> None
       | Some (`String owner) -> Some owner
       | Some _ -> fail "Metal enum evidence owner must be string or null")
  ; header = required_string "header" value
  ; line = required_int "line" value
  ; signature = required_string "signature" value
  ; classification = required_string "classification" value
  ; macos_introduced = optional_string "macos_introduced" value
  ; availability_sources =
      (match member_list "availability_sources" value with
       | None -> []
       | Some sources -> List.map availability_source sources |> List.sort String.compare)
  }

let parse_options () =
  let inventory = ref "" in
  let public_ml = ref "" in
  let public_mli = ref "" in
  let exhaustive_test = ref "" in
  Arg.parse
    [ "--inventory", Arg.Set_string inventory, "generated Metal inventory"
    ; "--public-ml", Arg.Set_string public_ml, "generated public enum implementation"
    ; "--public-mli", Arg.Set_string public_mli, "generated public enum interface"
    ; "--exhaustive-test", Arg.Set_string exhaustive_test, "generated exhaustive enum test"
    ]
    (fun value -> fail "unexpected enum-bound-evidence argument: %s" value)
    "Validate generated Metal enum promotion evidence";
  List.iter
    (fun (name, value) -> if String.equal !value "" then fail "missing %s" name)
    [ "--inventory", inventory; "--public-ml", public_ml; "--public-mli", public_mli
    ; "--exhaustive-test", exhaustive_test
    ];
  !inventory, !public_ml, !public_mli, !exhaustive_test

let selected_declarations inventory =
  let root = Yojson.Safe.from_file inventory in
  if member_int "schema" root <> Some 2 then
    fail "Metal enum evidence requires inventory schema 2";
  let symbols =
    match member_list "symbols" root with
    | Some symbols -> symbols
    | None -> fail "Metal enum evidence inventory symbols must be a list"
  in
  let seen = Hashtbl.create (List.length symbols) in
  List.filter_map
    (fun value ->
      let declaration = declaration value in
      if Hashtbl.mem seen declaration.id then
        fail "duplicate Metal inventory identifier %s" declaration.id;
      Hashtbl.add seen declaration.id ();
      if Binding_enum_bound_evidence.is_selected_identifier declaration.id then
        Some declaration
      else None)
    symbols

let canonical_identifiers declarations =
  declarations
  |> List.filter (fun declaration ->
       Binding_enum_bound_evidence.is_bound_identifier declaration.id)
  |> List.map (fun declaration -> declaration.id)
  |> List.sort String.compare

let canonical_availability declarations =
  declarations
  |> List.filter (fun declaration ->
       Binding_enum_bound_evidence.is_bound_identifier declaration.id)
  |> List.map (fun declaration ->
       String.concat "\t"
         [ declaration.id; declaration.header; string_of_int declaration.line
         ; declaration.signature; declaration.macos_introduced
         ; String.concat "," declaration.availability_sources
         ])
  |> List.sort String.compare

let digest_lines lines = sha256 (String.concat "\n" lines ^ "\n")

let require_digest description expected actual =
  if not (String.equal expected actual) then
    fail "Metal enum %s digest drift: %s, expected %s" description actual expected

let check_inventory declarations =
  let selected_count = List.length declarations in
  let excluded =
    List.filter (fun declaration ->
      Binding_enum_bound_evidence.is_scope_excluded_identifier declaration.id)
      declarations
  in
  let bound =
    List.filter (fun declaration ->
      Binding_enum_bound_evidence.is_bound_identifier declaration.id)
      declarations
  in
  if selected_count <> Binding_enum_bound_evidence.bound_count
                       + Binding_enum_bound_evidence.excluded_count
  then fail "Metal enum selected declaration count drift: %d" selected_count;
  if List.length excluded <> Binding_enum_bound_evidence.excluded_count then
    fail "Metal enum scope exclusion count drift: %d" (List.length excluded);
  if List.length bound <> Binding_enum_bound_evidence.bound_count then
    fail "Metal enum bound declaration count drift: %d" (List.length bound);
  List.iter
    (fun declaration ->
      let expected =
        if Binding_enum_bound_evidence.is_scope_excluded_identifier declaration.id
        then "scope-excluded" else "bound"
      in
      if not (String.equal declaration.classification expected) then
        fail "Metal enum %s is %s, expected %s" declaration.id
          declaration.classification expected)
    declarations;
  let actual_exclusions =
    List.map (fun declaration -> declaration.id) excluded |> String_set.of_list
  in
  let expected_exclusions =
    String_set.of_list Binding_enum_bound_evidence.excluded_identifiers
  in
  if not (String_set.equal actual_exclusions expected_exclusions) then
    fail "Metal enum scope exclusion identifier set drift";
  require_digest "identifier" Binding_enum_bound_evidence.identifier_sha256
    (digest_lines (canonical_identifiers declarations));
  require_digest "availability" Binding_enum_bound_evidence.availability_sha256
    (digest_lines (canonical_availability declarations))

let contains ~needle haystack =
  let needle_length = String.length needle in
  let rec loop offset =
    offset + needle_length <= String.length haystack
    && (String.sub haystack offset needle_length = needle || loop (offset + 1))
  in
  String.equal needle "" || loop 0

let require_witness path kind =
  let source = read_file path in
  List.iter
    (fun (name, value) ->
      let witness = Printf.sprintf "metal-enum-evidence %s: %s" name value in
      if not (contains ~needle:witness source) then
        fail "Metal enum %s lacks witness %s" kind witness)
    [ "identifier-sha256", Binding_enum_bound_evidence.identifier_sha256
    ; "availability-sha256", Binding_enum_bound_evidence.availability_sha256
    ];
  let count_witness =
    Printf.sprintf "metal-enum-evidence declaration-count: %d"
      Binding_enum_bound_evidence.bound_count
  in
  if not (contains ~needle:count_witness source) then
    fail "Metal enum %s lacks witness %s" kind count_witness

let main () =
  let inventory, public_ml, public_mli, exhaustive_test = parse_options () in
  let declarations = selected_declarations inventory in
  check_inventory declarations;
  require_witness public_ml "public implementation";
  require_witness public_mli "public interface";
  require_witness exhaustive_test "exhaustive test";
  Printf.printf
    "Metal enum promotion evidence is closed over %d bound declarations and %d scope exclusions\n%!"
    Binding_enum_bound_evidence.bound_count
    Binding_enum_bound_evidence.excluded_count

let () = protect_main main
