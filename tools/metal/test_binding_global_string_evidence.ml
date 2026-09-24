open Support

let required_string name value =
  match member_string name value with
  | Some value -> value
  | None -> fail "Metal global evidence field %s must be a string" name

let required_int name value =
  match member_int name value with
  | Some value -> value
  | None -> fail "Metal global evidence field %s must be an integer" name

let optional_string name value =
  match member name value with
  | None | Some `Null -> ""
  | Some (`String value) -> value
  | Some _ -> fail "Metal global evidence field %s must be string or null" name

let source value =
  Printf.sprintf "%s:%d" (required_string "header" value)
    (required_int "line" value)

let contains haystack needle =
  let rec loop offset =
    offset + String.length needle <= String.length haystack
    && (String.sub haystack offset (String.length needle) = needle
       || loop (offset + 1))
  in
  loop 0

let parse_options () =
  let inventory = ref "" in
  Arg.parse
    [ "--inventory", Arg.Set_string inventory, "generated Metal inventory" ]
    (fun value -> fail "unexpected global-evidence argument: %s" value)
    "Validate generated Metal global-string evidence";
  if String.equal !inventory "" then fail "missing --inventory";
  !inventory

let () =
  let root = Yojson.Safe.from_file (parse_options ()) in
  if member_int "schema" root <> Some 2 then
    fail "Metal global evidence requires inventory schema 2";
  let symbols =
    match member_list "symbols" root with
    | Some symbols -> symbols
    | None -> fail "Metal global evidence inventory symbols must be a list"
  in
  let selected =
    List.filter
      (fun value ->
        Binding_global_string_evidence.is_bound_identifier
          (required_string "id" value))
      symbols
  in
  if List.length selected <> Binding_global_string_evidence.bound_count then
    fail "Metal global evidence cardinality drift: %d" (List.length selected);
  List.iter
    (fun value ->
      let id = required_string "id" value in
      if not (String.equal (required_string "kind" value) "variable") then
        fail "Metal global evidence selected non-variable %s" id;
      let classification = required_string "classification" value in
      if classification <> "unreviewed" && classification <> "bound" then
        fail "Metal global evidence selected %s declaration %s" classification id;
      let planned =
        match
          List.find_opt
            (fun entry ->
              String.equal entry.Binding_global_string_spec.sdk_id id)
            Binding_global_string_spec.entries
        with
        | Some entry -> entry
        | None -> fail "Metal global evidence has no plan entry for %s" id
      in
      if not (String.equal planned.header (required_string "header" value)) then
        fail "Metal global header drift for %s" id;
      if not (String.equal planned.signature (required_string "signature" value)) then
        fail "Metal global signature drift for %s" id;
      if
        not
          (String.equal
             (Binding_availability.canonical planned.macos_introduced)
             (optional_string "macos_introduced" value))
      then fail "Metal global availability drift for %s" id)
    selected;
  let identifiers =
    selected |> List.map (required_string "id") |> List.sort String.compare
  in
  let availability =
    selected
    |> List.map (fun value ->
         let sources =
           match member_list "availability_sources" value with
           | None -> []
           | Some values -> List.map source values |> List.sort String.compare
         in
         String.concat "\t"
           [ required_string "id" value; required_string "header" value
           ; string_of_int (required_int "line" value)
           ; required_string "signature" value
           ; optional_string "macos_introduced" value
           ; String.concat "," sources
           ])
    |> List.sort String.compare
  in
  let digest lines = sha256 (String.concat "\n" lines ^ "\n") in
  let require_digest description expected actual =
    if not (String.equal expected actual) then
      fail "Metal global %s digest drift: %s, expected %s" description actual expected
  in
  require_digest "identifier" Binding_global_string_evidence.identifier_sha256
    (digest identifiers);
  require_digest "availability" Binding_global_string_evidence.availability_sha256
    (digest availability);
  let conformance =
    Binding_global_string_conformance_codegen.render
      Binding_global_string_spec.entries
  in
  List.iter
    (fun marker ->
      if not (contains conformance marker) then
        fail "generated conformance missing marker %s" marker)
    [ "for _iteration = 1 to 64"
    ; "did not return an independent OCaml copy"
    ; "changed native handle accounting"
    ];
  Printf.printf "Metal global evidence: %d exact declarations\n"
    (List.length selected)
