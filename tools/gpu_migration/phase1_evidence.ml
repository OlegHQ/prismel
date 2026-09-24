open Support

module String_set = Set.Make (String)

let evidence_relative =
  "specification/evidence/gpu_migration/phase1_sdl3.json"

let plan_relative = "NEW_GPU_STUFF.md"

let expected_gates =
  [ "S1"; "S2"; "S3"; "S4"; "S5"; "S6"; "S7"; "S8" ]

let expected_memory_modes = [ "address"; "undefined"; "leaks" ]

let fail_field field = fail "Phase 1 evidence has invalid or missing %s" field

let required_string field value =
  match member_string field value with
  | Some value when value <> "" -> value
  | Some _ | None -> fail_field field

let required_int field value =
  match member_int field value with
  | Some value -> value
  | None -> fail_field field

let required_bool field value =
  match member_bool field value with
  | Some value -> value
  | None -> fail_field field

let required_list field value =
  match member_list field value with
  | Some value -> value
  | None -> fail_field field

let required_object field value =
  match member field value with
  | Some (`Assoc _ as value) -> value
  | Some _ | None -> fail_field field

let is_lower_hex character =
  match character with
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let require_commit field value =
  let commit = required_string field value in
  if String.length commit <> 40 || not (String.for_all is_lower_hex commit) then
    fail "%s must be a full lowercase Git SHA" field;
  commit

let string_values field value =
  required_list field value
  |> List.map (function
    | `String value when value <> "" -> value
    | _ -> fail "%s must contain nonempty strings" field)

let count field value =
  match member_int field value with
  | Some value -> value
  | None -> 0

let version_tuple value =
  let version = required_object "header_version" value in
  required_int "major" version, required_int "minor" version,
  required_int "patch" version

let validate_source_artifact root artifact =
  let path = required_string "path" artifact in
  let expected = required_string "sha256" artifact in
  let absolute = Filename.concat root path in
  if not (Sys.file_exists absolute && not (Sys.is_directory absolute)) then
    fail "Phase 1 source artifact is missing: %s" path;
  let actual = sha256 (read_file absolute) in
  if actual <> expected then
    fail "Phase 1 source artifact hash changed for %s: expected %s, got %s"
      path expected actual

let validate_inventory root evidence =
  let identifier = required_string "id" evidence in
  let path = required_string "path" evidence in
  let actual =
    read_file (Filename.concat root path) |> Yojson.Safe.from_string
  in
  if member_int "schema" actual <> Some 1 then
    fail "%s inventory schema changed" identifier;
  let expected_version = version_tuple evidence in
  if version_tuple actual <> expected_version then
    fail "%s inventory version changed" identifier;
  let actual_functions = required_list "functions" actual |> List.length in
  if actual_functions <> required_int "function_count" evidence then
    fail "%s inventory function count changed" identifier;
  let classifications = required_object "classification_counts" actual in
  let expected_classifications =
    required_object "classification_counts" evidence
  in
  [ "safe"; "raw-only"; "platform-excluded"; "not-applicable"; "unreviewed" ]
  |> List.iter (fun classification ->
    if count classification classifications
       <> count classification expected_classifications
    then fail "%s %s classification count changed" identifier classification);
  if count "unreviewed" classifications <> 0 then
    fail "%s inventory contains unreviewed symbols" identifier

let validate_gate implementation_commit gate =
  let identifier = required_string "gate" gate in
  if required_string "result" gate <> "pass" then
    fail "%s does not pass" identifier;
  if require_commit "commit" gate <> implementation_commit then
    fail "%s names a different implementation commit" identifier;
  if required_bool "dirty" gate then fail "%s was recorded dirty" identifier;
  if string_values "commands" gate = [] then
    fail "%s has no reproduction command" identifier;
  if string_values "artifacts" gate = [] then
    fail "%s has no artifact" identifier;
  if required_string "reviewer" gate <> "pending-independent-final-signoff" then
    fail "%s reviewer state is not explicit" identifier;
  identifier

let validate_memory memory =
  let mode = required_string "mode" memory in
  if required_string "result" memory <> "pass" then
    fail "%s memory lane did not pass" mode;
  if required_int "test_count" memory <> 10 then
    fail "%s memory lane must retain all ten tests" mode;
  if required_int "diagnostic_count" memory <> 0 then
    fail "%s memory lane contains diagnostics" mode;
  ignore (required_string "command" memory);
  mode

let exact_identifiers label expected actual =
  let duplicate_free =
    List.length actual = String_set.cardinal (String_set.of_list actual)
  in
  if not duplicate_free || String_set.of_list actual <> String_set.of_list expected
  then
    fail "%s identifiers must be exactly [%s]" label (String.concat ", " expected)

let validate_bootstrap value =
  if required_string "result" value <> "pass" then
    fail "fresh bootstrap did not pass";
  if required_bool "dirty" value then fail "fresh bootstrap checkout was dirty";
  if required_string "ocaml" value <> "5.3.0" then
    fail "fresh bootstrap used the wrong OCaml version";
  if required_string "dune" value <> "3.20.2" then
    fail "fresh bootstrap used the wrong Dune version";
  [ "build_all"; "build_doc"; "runtest"; "consumer_dev"; "consumer_release"
  ; "packaging_release"
  ]
  |> List.iter (fun field ->
    if required_string field value <> "pass" then
      fail "fresh bootstrap %s did not pass" field);
  let commands = string_values "commands" value in
  if not
       (List.exists
          (contains ~needle:
             "opam switch create . 5.3.0 --no-install")
          commands)
  then fail "fresh bootstrap omits the supported switch ordering";
  if not
       (List.exists
          (contains ~needle:
             "opam pin add --no-action --yes --recursive ./packaging")
          commands)
  then fail "fresh bootstrap omits local conf-package registration"

let validate_layering value =
  let implementation = string_values "implementation_directories" value in
  exact_identifiers "SDL3 implementation directories"
    [ "lib/sdl3"; "lib/sdl3_image"; "lib/sdl3_ttf"; "lib/sdl3_mixer" ]
    implementation;
  let probes = string_values "native_probe_directories" value in
  exact_identifiers "SDL3 native probe directories"
    [ "packaging/conf-sdl3"; "packaging/conf-sdl3-image"
    ; "packaging/conf-sdl3-ttf"; "packaging/conf-sdl3-mixer"
    ]
    probes;
  if required_string "repository_tool_language" value <> "OCaml" then
    fail "Phase 1 repository tooling is not recorded as OCaml";
  if required_bool "python_glue_added" value then
    fail "Phase 1 evidence reports Python glue"

let validate root value =
  if member_int "schema" value <> Some 1 then
    fail "unsupported Phase 1 evidence schema";
  if required_string "kind" value <> "phase1_sdl3" then
    fail "wrong Phase 1 evidence kind";
  let plan_hash = required_string "new_gpu_stuff_sha256" value in
  let actual_plan_hash = sha256 (read_file (Filename.concat root plan_relative)) in
  if plan_hash <> actual_plan_hash then fail "NEW_GPU_STUFF.md hash changed";
  let implementation_commit = require_commit "implementation_commit" value in
  if required_bool "implementation_dirty" value then
    fail "Phase 1 implementation was recorded dirty";
  required_list "source_artifacts" value
  |> List.iter (validate_source_artifact root);
  required_list "inventories" value |> List.iter (validate_inventory root);
  let layout = required_object "layout_identity" value in
  let layout_hash = required_string "layout_sha256" layout in
  if layout_hash
     <> sha256 (read_file (Filename.concat root "lib/sdl3/generated_layout.json"))
  then fail "SDL3 layout manifest hash changed";
  [ "dev"; "release"; "address"; "undefined" ]
  |> List.iter (fun field ->
    if required_string field layout <> layout_hash then
      fail "%s layout identity differs" field);
  if required_string "derived_abi_sha256" layout
     <> sha256 (read_file (Filename.concat root "lib/sdl3/generated_abi.h"))
  then fail "SDL3 derived ABI header hash changed";
  let memory_modes =
    required_list "memory_qualification" value |> List.map validate_memory
  in
  exact_identifiers "memory modes" expected_memory_modes memory_modes;
  let address =
    required_list "memory_qualification" value
    |> List.find (fun memory -> member_string "mode" memory = Some "address")
  in
  let suppression = required_object "suppression" address in
  if string_values "frames" suppression <> [ "pdf_lexer_scan" ] then
    fail "ASan suppression must remain function-scoped to pdf_lexer_scan";
  let suppression_path = required_string "path" suppression in
  if required_string "sha256" suppression
     <> sha256 (read_file (Filename.concat root suppression_path))
  then fail "ASan suppression hash changed";
  validate_bootstrap (required_object "fresh_bootstrap" value);
  validate_layering (required_object "layering" value);
  let gates = required_list "gates" value in
  let gate_ids = List.map (validate_gate implementation_commit) gates in
  exact_identifiers "Phase 1 gates" expected_gates gate_ids

let root = ref None

let () =
  protect_main (fun () ->
    Arg.parse
      [ "--root", Arg.String (fun value -> root := Some value),
        "DIR repository root"
      ]
      (fun value -> fail "unexpected argument %S" value)
      "phase1_evidence --root DIR";
    let root =
      match !root with
      | Some root -> Unix.realpath root
      | None -> fail "--root is required"
    in
    let evidence_path = Filename.concat root evidence_relative in
    if not (Sys.file_exists evidence_path) then
      fail "missing Phase 1 evidence: %s" evidence_path;
    read_file evidence_path |> Yojson.Safe.from_string |> validate root;
    print_endline "Phase 1 SDL3 evidence is complete")
