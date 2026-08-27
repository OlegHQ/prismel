module Strings = Set.Make (String)

let require condition format =
  Printf.ksprintf (fun message -> if not condition then failwith message) format

let read_file path =
  let input = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr input)
    (fun () -> really_input_string input (in_channel_length input))

let set values =
  List.fold_left (fun result value -> Strings.add value result) Strings.empty values

let words contents =
  let value = Bytes.of_string contents in
  Bytes.iteri
    (fun index character ->
      if not
           ((character >= 'a' && character <= 'z')
            || (character >= 'A' && character <= 'Z')
            || (character >= '0' && character <= '9')
            || character = '_')
      then Bytes.set value index ' ')
    value;
  Bytes.to_string value |> String.split_on_char ' '
  |> List.filter (fun word -> word <> "") |> set

let find_substring ~needle contents start =
  let rec loop index =
    if index + String.length needle > String.length contents then None
    else if String.sub contents index (String.length needle) = needle then Some index
    else loop (index + 1)
  in
  loop start

let dune_library_dependencies contents =
  let marker = "(libraries" in
  let rec collect offset result =
    match find_substring ~needle:marker contents offset with
    | None -> result
    | Some start ->
        let body_start = start + String.length marker in
        (match String.index_from_opt contents body_start ')' with
         | None -> failwith "unterminated Dune libraries field"
         | Some finish ->
             let body = String.sub contents body_start (finish - body_start) in
             collect (finish + 1) (Strings.union result (words body)))
  in
  collect 0 Strings.empty

let first_dune_library_dependencies contents =
  let marker = "(libraries" in
  match find_substring ~needle:marker contents 0 with
  | None -> Strings.empty
  | Some start ->
      let body_start = start + String.length marker in
      (match String.index_from_opt contents body_start ')' with
       | None -> failwith "unterminated first Dune libraries field"
       | Some finish -> words (String.sub contents body_start (finish - body_start)))

let dune_library_stanzas contents =
  let marker = "(library\n" in
  let rec collect offset result =
    match find_substring ~needle:marker contents offset with
    | None -> List.rev result
    | Some start ->
        let finish =
          match find_substring ~needle:"\n\n(" contents (start + String.length marker) with
          | Some finish -> finish
          | None -> String.length contents
        in
        collect finish (String.sub contents start (finish - start) :: result)
  in
  collect 0 []

let dune_stanza_name stanza =
  let marker = "(name " in
  match find_substring ~needle:marker stanza 0 with
  | None -> failwith "library stanza has no name"
  | Some start ->
      let value_start = start + String.length marker in
      let finish = String.index_from stanza value_start ')' in
      String.sub stanza value_start (finish - value_start)

let strings json field =
  let open Yojson.Safe.Util in
  json |> member field |> to_list |> List.map to_string

let quoted_in contents value =
  find_substring ~needle:(Printf.sprintf "%S" value) contents 0 <> None

let () =
  let root = ref "." in
  let candidate = ref "tools/phase5_switch/runtime_owner_candidate.dune" in
  let manifest = ref "tools/phase5_switch/runtime_owner_candidate.json" in
  Arg.parse
    [ "--root", Arg.Set_string root, "repository root"
    ; "--candidate", Arg.Set_string candidate, "candidate Dune template"
    ; "--manifest", Arg.Set_string manifest, "Runtime preservation manifest"
    ]
    (fun value -> raise (Arg.Bad value)) "B5 Runtime owner candidate gate";
  let root = Unix.realpath !root in
  let absolute path = if Filename.is_relative path then Filename.concat root path else path in
  let manifest = Yojson.Safe.from_file (absolute !manifest) in
  let open Yojson.Safe.Util in
  require (manifest |> member "schema" |> to_int = 1) "Runtime candidate schema drift";
  require (manifest |> member "name" |> to_string = "runtime") "Runtime owner name drift";
  require (manifest |> member "public_name" |> to_string = "prismel.runtime")
    "Runtime public name drift";
  let mapped = strings manifest "mapped_values" in
  let adapted = strings manifest "adapted_values" in
  let omissions = strings manifest "raw_omissions" in
  require (List.length mapped = 16 && List.length adapted = 2 && List.length omissions = 5)
    "Runtime value coverage cardinality drift";
  require (omissions = [ "present"; "Private.select_target";
                         "Private.next_web_deadline";
                         "Private.fitted_web_drawable_size";
                         "Private.idle_frame_interval" ])
    "Runtime raw omission allowlist drift";
  let all_values = mapped @ adapted @ omissions in
  require (Strings.cardinal (set all_values) = 23) "Runtime value coverage duplicates";
  let mapped_types = strings manifest "mapped_types" in
  let adapted_types = strings manifest "adapted_types" in
  require (List.length mapped_types = 3 && List.length adapted_types = 3)
    "Runtime type coverage cardinality drift";
  let compat_ml = read_file (Filename.concat root "lib/runtime_next_compat/runtime_next_compat.ml") in
  let compat_mli = read_file (Filename.concat root "lib/runtime_next_compat/runtime_next_compat.mli") in
  List.iter (fun name -> require (quoted_in compat_ml name)
    "Runtime compatibility coverage does not record %s" name) all_values;
  List.iter (fun name -> require (Strings.mem name (words compat_mli))
    "Runtime compatibility interface does not expose %s" name) (mapped @ adapted);
  List.iter (fun name -> require (Strings.mem name (words compat_mli))
    "Runtime compatibility interface does not expose type %s" name)
    (mapped_types @ adapted_types);
  require (not (Strings.mem "Tsdl" (words compat_mli)))
    "Runtime compatibility interface exposes Tsdl";
  require (not (Strings.mem "Wap" (words compat_mli)))
    "Runtime compatibility interface exposes raw Wap values";
  let candidate_dependencies = strings manifest "dependencies" in
  require (candidate_dependencies = [ "runtime_next_compat" ])
    "Runtime candidate must depend only on its typed compatibility adapter";
  let compat_dependencies =
    read_file (Filename.concat root "lib/runtime_next_compat/dune")
    |> first_dune_library_dependencies
  in
  require (compat_dependencies = set [ "runtime_next_orchestrator"; "scene_execution"; "ogpu" ])
    "Runtime compatibility dependencies drift";
  let consumers =
    Sys.readdir (Filename.concat root "lib") |> Array.to_list
    |> List.filter_map (fun directory ->
      let path = Filename.concat root ("lib/" ^ directory ^ "/dune") in
      if directory = "runtime" || directory = "prismel" || not (Sys.file_exists path) then None
      else if Strings.mem "runtime" (dune_library_dependencies (read_file path))
      then Some directory else None)
    |> List.sort String.compare
  in
  require (consumers = []) "surviving libraries still consume old Runtime: [%s]"
    (String.concat "," consumers);
  let old_prismel_dependencies =
    read_file (Filename.concat root "lib/prismel/dune") |> dune_library_dependencies
  in
  require (Strings.mem "runtime" old_prismel_dependencies)
    "legacy Prismel is no longer the expected atomic Runtime consumer";
  let orchestrator_mli =
    read_file (Filename.concat root "lib/runtime_next/runtime_next_orchestrator.mli")
  in
  require (not (Strings.mem "Wap" (words orchestrator_mli)))
    "Runtime orchestrator exposes raw Wap values";
  require (strings manifest "typed_wap_boundaries" =
           [ "runtime_next_web"; "runtime_next_input" ])
    "typed Wap boundary allowlist drift";
  let runtime_next_dune = read_file (Filename.concat root "lib/runtime_next/dune") in
  List.iter
    (fun public_name ->
      require (find_substring ~needle:("(public_name prismel." ^ public_name ^ ")")
                 runtime_next_dune 0 <> None)
        "typed Wap boundary owner missing: %s" public_name)
    (strings manifest "typed_wap_boundaries");
  let actual_wap_boundaries =
    dune_library_stanzas runtime_next_dune
    |> List.filter_map (fun stanza ->
      if Strings.mem "wap" (dune_library_dependencies stanza)
      then Some (dune_stanza_name stanza) else None)
  in
  require (actual_wap_boundaries = strings manifest "typed_wap_boundaries")
    "raw Wap dependency escaped typed boundary: [%s]"
    (String.concat "," actual_wap_boundaries);
  let expected_candidate =
    "; Validated B5 candidate only. The atomic switch generates Runtime as the\n\
     ; narrow public alias of Runtime_next_compat after deleting lib/runtime.\n\
     (library\n\
     \ (name runtime)\n\
     \ (public_name prismel.runtime)\n\
     \ (modules runtime)\n\
     \ (libraries runtime_next_compat))\n"
  in
  require (read_file (absolute !candidate) = expected_candidate)
    "Runtime owner candidate Dune template drift";
  Printf.printf
    "B5 Runtime owner candidate passed: 18 portable values + 5 exact raw omissions, 6 public types, 0 surviving old-Runtime consumers, typed transport only\n"
