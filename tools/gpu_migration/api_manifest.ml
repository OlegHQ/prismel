open Support

module String_set = Set.Make (String)

let baseline_relative =
  "specification/evidence/gpu_migration/phase0_baseline.json"

let stable_relative =
  "specification/evidence/gpu_migration/api_stable.json"

let stable_library_directories =
  [ "prismel"; "pdk"; "geom"; "procedural"; "pxui"; "pxui_graph"
  ; "sop_catalog"; "sop_ui"; "sketch"; "sketch_ui"
  ]

let reviewed_native_only_removals =
  [ "prismel.Framebuffer3"; "prismel.Render2"; "prismel.Render3" ]

let mixed_legacy library module_name =
  match library, module_name with
  | "prismel", "Font" -> [ "module:Private"; "value:release_renderer" ]
  | "prismel", "Image" -> [ "module:Private" ]
  | _ -> []

(* Additive staging boundaries are reviewed separately from the frozen API.
   Removing or changing an old declaration still changes [api_sha256]. *)
let approved_additions library module_name =
  match library, module_name with
  | _ -> []

type sexp =
  | Atom of string
  | List of sexp list

let whitespace = function
  | ' ' | '\t' | '\n' | '\r' | '\012' -> true
  | _ -> false

let tokenize_sexp source =
  let length = String.length source in
  let rec string_token index value escaped =
    if index >= length then fail "unterminated string in Dune file"
    else
      let character = source.[index] in
      if escaped then begin
        Buffer.add_char value character;
        string_token (index + 1) value false
      end
      else
        match character with
        | '\\' -> string_token (index + 1) value true
        | '"' -> Buffer.contents value, index + 1
        | character ->
            Buffer.add_char value character;
            string_token (index + 1) value false
  in
  let rec tokens index result =
    if index >= length then List.rev result
    else
      match source.[index] with
      | character when whitespace character -> tokens (index + 1) result
      | ';' ->
          let rec newline cursor =
            if cursor >= length then length
            else if source.[cursor] = '\n' then cursor + 1
            else newline (cursor + 1)
          in
          tokens (newline (index + 1)) result
      | '(' -> tokens (index + 1) ("(" :: result)
      | ')' -> tokens (index + 1) (")" :: result)
      | '"' ->
          let value, next = string_token (index + 1) (Buffer.create 32) false in
          tokens next (value :: result)
      | _ ->
          let rec stop cursor =
            if cursor >= length then cursor
            else
              let character = source.[cursor] in
              if whitespace character || character = '(' || character = ')'
                 || character = ';'
              then cursor
              else stop (cursor + 1)
          in
          let next = stop index in
          tokens next (String.sub source index (next - index) :: result)
  in
  tokens 0 []

let parse_sexps tokens =
  let tokens = Array.of_list tokens in
  let index = ref 0 in
  let rec one () =
    if !index >= Array.length tokens then fail "unexpected end of Dune file";
    let token = tokens.(!index) in
    incr index;
    match token with
    | ")" -> fail "unexpected closing parenthesis in Dune file"
    | "(" ->
        let rec values result =
          if !index >= Array.length tokens then
            fail "unterminated list in Dune file";
          if tokens.(!index) = ")" then begin
            incr index;
            List (List.rev result)
          end
          else values (one () :: result)
        in
        values []
    | value -> Atom value
  in
  let rec forms result =
    if !index = Array.length tokens then List.rev result
    else forms (one () :: result)
  in
  forms []

let stanza_field stanza name =
  let rec find = function
    | [] -> None
    | List (Atom field :: values) :: _ when field = name -> Some values
    | _ :: rest -> find rest
  in
  match stanza with
  | Atom _ -> None
  | List (_ :: fields) -> find fields
  | List [] -> None

let rec flatten_atoms values =
  List.concat_map
    (function
      | Atom value -> [ value ]
      | List values -> flatten_atoms values)
    values

let library_stanza path =
  read_file path |> tokenize_sexp |> parse_sexps
  |> List.find_opt (function
       | List (Atom "library" :: _) -> true
       | Atom _ | List _ -> false)
  |> function
  | Some stanza -> stanza
  | None -> fail "%s: no library stanza" path

let source_stem name = Filename.remove_extension name

let source_file name =
  (Filename.check_suffix name ".ml" || Filename.check_suffix name ".mli")
  && not (String.contains (source_stem name) '.')

let add_directory_stems directory stems =
  Sys.readdir directory |> Array.to_list
  |> List.filter source_file
  |> List.fold_left
       (fun stems name ->
         String_set.add (source_stem name |> String.lowercase_ascii) stems)
       stems

let atoms_set atoms =
  List.fold_left
    (fun values atom -> String_set.add (String.lowercase_ascii atom) values)
    String_set.empty atoms

let module_ordered_set directory values =
  let atoms = flatten_atoms values |> List.map String.lowercase_ascii in
  let rec apply included excluding = function
    | [] -> included
    | "\\" :: rest -> apply included true rest
    | ":standard" :: rest ->
        let standard = add_directory_stems directory String_set.empty in
        let included =
          if excluding then String_set.diff included standard
          else String_set.union included standard
        in
        apply included excluding rest
    | atom :: rest when has_prefix ~prefix:":" atom ->
        apply included excluding rest
    | atom :: rest ->
        let included =
          if excluding then String_set.remove atom included
          else String_set.add atom included
        in
        apply included excluding rest
  in
  apply String_set.empty false atoms

let public_interfaces root directory_name =
  let directory = Filename.concat (Filename.concat root "lib") directory_name in
  let stanza = library_stanza (Filename.concat directory "dune") in
  let stems =
    match stanza_field stanza "modules" with
    | None -> add_directory_stems directory String_set.empty
    | Some values -> module_ordered_set directory values
  in
  let private_modules =
    Option.value (stanza_field stanza "private_modules") ~default:[]
    |> flatten_atoms |> atoms_set
  in
  let interfaces = Hashtbl.create 32 in
  Sys.readdir directory
  |> Array.iter (fun name ->
    if Filename.check_suffix name ".mli"
       && not (String.contains (source_stem name) '.')
    then
      Hashtbl.replace interfaces
        (source_stem name |> String.lowercase_ascii)
        (Filename.concat directory name));
  String_set.diff stems private_modules |> String_set.elements
  |> List.filter_map (fun stem ->
    match Hashtbl.find_opt interfaces stem with
    | Some path -> Some (String.capitalize_ascii (source_stem (Filename.basename path)), path)
    | None ->
        let implementation = Filename.concat directory (stem ^ ".ml") in
        if Sys.file_exists implementation then
          fail "public module %s.%s has no .mli" directory_name
            (String.capitalize_ascii stem);
        None)

type token =
  { text : string
  ; start : int
  ; stop : int
  }

let alphanumeric = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
  | _ -> false

let two_character_operator value =
  List.mem value
    [ "->"; "=>"; ":="; "::"; "<="; ">="; "<>"; "||"; "&&" ]

let lexical_tokens source =
  let length = String.length source in
  let rec comment index depth =
    if index >= length then fail "unterminated OCaml comment"
    else if index + 1 < length && String.sub source index 2 = "(*" then
      comment (index + 2) (depth + 1)
    else if index + 1 < length && String.sub source index 2 = "*)" then
      if depth = 1 then index + 2 else comment (index + 2) (depth - 1)
    else comment (index + 1) depth
  in
  let rec quoted index quote escaped =
    if index >= length then index
    else
      let character = source.[index] in
      if escaped then quoted (index + 1) quote false
      else if character = '\\' then quoted (index + 1) quote true
      else if character = quote then index + 1
      else quoted (index + 1) quote false
  in
  let rec scan index result =
    if index >= length then List.rev result
    else if index + 1 < length && String.sub source index 2 = "(*" then
      scan (comment (index + 2) 1) result
    else if whitespace source.[index] then scan (index + 1) result
    else if source.[index] = '"' || source.[index] = '\'' then
      let stop = quoted (index + 1) source.[index] false in
      scan stop ({ text = String.sub source index (stop - index); start = index; stop } :: result)
    else
      let start = index in
      let stop =
        if alphanumeric source.[index] || source.[index] = '_'
           || source.[index] = '`'
        then
          let rec identifier cursor =
            if cursor < length
               && (alphanumeric source.[cursor] || source.[cursor] = '_'
                   || source.[cursor] = '\'' || source.[cursor] = '.'
                   || source.[cursor] = '`')
            then identifier (cursor + 1)
            else cursor
          in
          identifier (index + 1)
        else
          let one = index + 1 in
          if one < length
             && two_character_operator (String.sub source start 2)
          then one + 1
          else one
      in
      scan stop
        ({ text = String.sub source start (stop - start); start; stop } :: result)
  in
  scan 0 []

let module_range source name =
  let tokens = lexical_tokens source |> Array.of_list in
  let rec find index =
    if index + 3 >= Array.length tokens then fail "module %s not found" name;
    if tokens.(index).text = "module" && tokens.(index + 1).text = name
       && tokens.(index + 2).text = ":" && tokens.(index + 3).text = "sig"
    then begin
      let rec finish cursor depth =
        if cursor >= Array.length tokens then fail "unterminated module %s" name;
        match tokens.(cursor).text with
        | "sig" -> finish (cursor + 1) (depth + 1)
        | "end" when depth = 1 -> tokens.(index).start, tokens.(cursor).stop
        | "end" -> finish (cursor + 1) (depth - 1)
        | _ -> finish (cursor + 1) depth
      in
      finish (index + 4) 1
    end
    else find (index + 1)
  in
  find 0

let value_range source name =
  let starters =
    [ "class"; "exception"; "external"; "include"; "module"; "type"; "val" ]
  in
  let tokens = lexical_tokens source |> Array.of_list in
  let rec find index =
    if index + 1 >= Array.length tokens then fail "value %s not found" name;
    if tokens.(index).text = "val" && tokens.(index + 1).text = name then begin
      let rec finish cursor =
        if cursor >= Array.length tokens then tokens.(index).start, String.length source
        else if List.mem tokens.(cursor).text starters then
          tokens.(index).start, tokens.(cursor).start
        else finish (cursor + 1)
      in
      finish (index + 2)
    end
    else find (index + 1)
  in
  find 0

let selected_range source selector =
  match String.index_opt selector ':' with
  | None -> fail "unknown legacy selector %s" selector
  | Some separator ->
      let kind = String.sub selector 0 separator in
      let name =
        String.sub selector (separator + 1)
          (String.length selector - separator - 1)
      in
      (match kind with
       | "module" -> module_range source name
       | "value" -> value_range source name
       | _ -> fail "unknown legacy selector %s" selector)

let without_ranges source ranges =
  ranges
  |> List.sort (fun (left, _) (right, _) -> compare right left)
  |> List.fold_left
       (fun value (start, stop) ->
         String.sub value 0 start
         ^ String.sub value stop (String.length value - stop))
       source

let normalized_api source =
  lexical_tokens source |> List.map (fun token -> token.text)
  |> String.concat " "

let relative_path root path =
  let prefix = if String.ends_with ~suffix:"/" root then root else root ^ "/" in
  if has_prefix ~prefix path then
    String.sub path (String.length prefix) (String.length path - String.length prefix)
  else fail "%s is outside repository %s" path root

let string_list values = `List (List.map (fun value -> `String value) values)

let source_entry root library module_name path selectors =
  let source = read_file path in
  let ranges = List.map (selected_range source)
      (selectors @ approved_additions library module_name) in
  let filtered = without_ranges source ranges in
  `Assoc
    [ "library", `String library
    ; "module", `String module_name
    ; "source", `String (relative_path root path)
    ; "source_bytes", `Int (String.length source)
    ; "source_sha256", `String (sha256 source)
    ; "api_sha256", `String (sha256 (normalized_api filtered))
    ; "excluded_legacy_symbols", string_list selectors
    ]

let json_sort_field field left right =
  match member_string field left, member_string field right with
  | Some left, Some right -> String.compare left right
  | _ -> fail "manifest entry lacks sorting field %s" field

let baseline root =
  read_file (Filename.concat root baseline_relative) |> Yojson.Safe.from_string

let generate root =
  let baseline = baseline root in
  let stable_entries =
    stable_library_directories
    |> List.concat_map (fun directory_name ->
      public_interfaces root directory_name
      |> List.filter_map (fun (module_name, path) ->
        if directory_name = "prismel" && module_name = "Low" then None
        else
          Some
            (source_entry root directory_name module_name path
               (mixed_legacy directory_name module_name))))
    |> List.sort (fun left right ->
      let library_order = json_sort_field "library" left right in
      if library_order <> 0 then library_order
      else json_sort_field "module" left right)
  in
  let common =
    [ "schema", `Int 1
    ; "baseline_commit", member_exn "baseline_commit" baseline
    ; "baseline_plan_sha256", member_exn "new_gpu_stuff_sha256" baseline
    ; "generator", `String "tools/gpu_migration/api_manifest.exe"
    ]
  in
  `Assoc
    (common
     @ [ "kind", `String "stable_high_level"
       ; "module_count", `Int (List.length stable_entries)
       ; "modules", `List stable_entries
       ])

let entry_key kind entry =
  match kind with
  | "stable_high_level" ->
      Printf.sprintf "%s.%s"
        (Option.value (member_string "library" entry) ~default:"?")
        (Option.value (member_string "module" entry) ~default:"?")
  | "declared_legacy_sdl" ->
      Option.value (member_string "surface" entry) ~default:"?"
  | _ -> "?"

let manifest_entries manifest =
  let kind = Option.value (member_string "kind" manifest) ~default:"?" in
  let field = if kind = "stable_high_level" then "modules" else "surfaces" in
  let values = Option.value (member_list field manifest) ~default:[] in
  kind, List.map (fun entry -> entry_key kind entry, entry) values

let stable_semantic_entry entry =
  `Assoc [
    "library", member_exn "library" entry;
    "module", member_exn "module" entry;
    "api_sha256", member_exn "api_sha256" entry;
    "excluded_legacy_symbols", member_exn "excluded_legacy_symbols" entry;
  ]

let report_manifest_delta path actual expected =
  let actual = Yojson.Safe.from_string actual in
  let actual_kind, actual_entries = manifest_entries actual
  and expected_kind, expected_entries = manifest_entries expected in
  if actual_kind <> expected_kind then
    Printf.eprintf "  kind changed: %s -> %s\n" actual_kind expected_kind
  else begin
    let table entries =
      let values = Hashtbl.create (List.length entries) in
      List.iter (fun (key, entry) -> Hashtbl.replace values key entry) entries;
      values
    in
    let old_values = table actual_entries and new_values = table expected_entries in
    let removed = actual_entries |> List.filter_map (fun (key, _) ->
      if Hashtbl.mem new_values key then None else Some key) in
    let added = expected_entries |> List.filter_map (fun (key, _) ->
      if Hashtbl.mem old_values key then None else Some key) in
    let changed = expected_entries |> List.filter_map (fun (key, value) ->
      match Hashtbl.find_opt old_values key with
      | Some old when
          (if actual_kind = "stable_high_level" then
             stable_semantic_entry old <> stable_semantic_entry value
           else old <> value) -> Some key
      | _ -> None) in
    let print label values = match values with
      | [] -> ()
      | values -> Printf.eprintf "  %s (%d): %s\n" label
          (List.length values) (String.concat ", " values)
    in
    Printf.eprintf "manifest structural delta for %s:\n" path;
    print "removed" removed;
    print "added" added;
    print "changed" changed;
    if removed <> [] then
      Printf.eprintf
        "  refusing silent contraction: restore the public modules or review the final B5 API gate\n"
  end

let manifests_equivalent actual expected =
  match member_string "kind" actual, member_string "kind" expected with
  | Some "stable_high_level", Some "stable_high_level" ->
      let normalize manifest =
        Option.value (member_list "modules" manifest) ~default:[]
        |> List.map stable_semantic_entry
      in
      normalize actual = normalize expected
  | _ -> actual = expected

let self_test_manifest_comparison () =
  let entry ?(api="api") ?(source="source") module_name = `Assoc [
    "library", `String "prismel"; "module", `String module_name;
    "api_sha256", `String api; "source_sha256", `String source;
    "excluded_legacy_symbols", `List [] ] in
  let manifest entries = `Assoc [ "kind", `String "stable_high_level";
    "modules", `List entries ] in
  let baseline = manifest [entry "Scene"] in
  if not (manifests_equivalent baseline
      (manifest [entry ~source:"comment-only" "Scene"])) then
    fail "API manifest comparison treated source-only drift as API drift";
  if manifests_equivalent baseline (manifest []) then
    fail "API manifest comparison accepted a removed module";
  if manifests_equivalent baseline (manifest [entry ~api:"changed" "Scene"])
  then fail "API manifest comparison accepted a changed signature"

let refuse_stable_contraction path expected =
  if Sys.file_exists path then begin
    let actual = read_file path |> Yojson.Safe.from_string in
    let actual_kind, actual_entries = manifest_entries actual
    and expected_kind, expected_entries = manifest_entries expected in
    if actual_kind = "stable_high_level" && expected_kind = actual_kind then begin
      let expected_keys = Hashtbl.create (List.length expected_entries) in
      List.iter (fun (key, _) -> Hashtbl.replace expected_keys key ())
        expected_entries;
      let removed = actual_entries |> List.filter_map (fun (key, _) ->
        if Hashtbl.mem expected_keys key then None else Some key) in
      let unreviewed =
        List.filter
          (fun key -> not (List.mem key reviewed_native_only_removals))
          removed
      in
      if unreviewed <> [] then
        fail "refusing to write a contracted stable API manifest (%d unreviewed removed): %s"
          (List.length unreviewed) (String.concat ", " unreviewed)
    end
  end

let check path expected =
  if not (Sys.file_exists path) then begin
    Printf.eprintf "missing generated manifest: %s\n%!" path;
    false
  end
  else
    let actual_text = read_file path in
    let actual = Yojson.Safe.from_string actual_text
    and expected_json = Yojson.Safe.from_string expected in
    if not (manifests_equivalent actual expected_json) then begin
    report_manifest_delta path actual_text expected_json;
    Printf.eprintf
      "stale generated manifest: %s\nrun dune exec \
       tools/gpu_migration/api_manifest.exe -- --write\n%!"
      path;
    false
  end else true

let main () =
  self_test_manifest_comparison ();
  let root, mode = root_and_mode () in
  let stable = generate root in
  let outputs =
    [ Filename.concat root stable_relative, pretty_json stable ]
  in
  match mode with
  | Write ->
      refuse_stable_contraction (Filename.concat root stable_relative) stable;
      List.iter
        (fun (path, value) ->
          ensure_directory (Filename.dirname path);
          write_file path value)
        outputs;
      let stable_count =
        Option.value (member_int "module_count" stable) ~default:0
      in
      Printf.printf "wrote %d stable native modules\n%!" stable_count
  | Check ->
      if not (List.for_all (fun (path, value) -> check path value) outputs) then
        exit 1

let () = protect_main main
