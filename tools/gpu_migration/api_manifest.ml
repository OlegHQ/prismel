open Support

module String_set = Set.Make (String)

let baseline_relative =
  "specification/evidence/gpu_migration/phase0_baseline.json"

let stable_relative =
  "specification/evidence/gpu_migration/api_stable.json"

let legacy_relative =
  "specification/evidence/gpu_migration/api_legacy_sdl.json"

let stable_library_directories =
  [ "prismel"; "pdk"; "geom"; "procedural"; "pxui"; "pxui_graph"
  ; "sop_catalog"; "sop_ui"; "sketch"; "sketch_ui"; "wap"
  ]

let mixed_legacy library module_name =
  match library, module_name with
  | "prismel", "Font" -> [ "module:Private"; "value:release_renderer" ]
  | "prismel", "Image" -> [ "module:Private" ]
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

let public_interfaces root directory_name =
  let directory = Filename.concat (Filename.concat root "lib") directory_name in
  let stanza = library_stanza (Filename.concat directory "dune") in
  let stems =
    match stanza_field stanza "modules" with
    | None -> add_directory_stems directory String_set.empty
    | Some values ->
        flatten_atoms values
        |> List.filter (fun atom ->
          atom <> ":standard" && atom <> "\\" && not (has_prefix ~prefix:":" atom))
        |> atoms_set
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
  let ranges = List.map (selected_range source) selectors in
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

let legacy_entry root surface path selectors =
  let source = read_file path in
  let selected =
    match selectors with
    | [] -> source
    | selectors ->
        List.map
          (fun selector ->
            let start, stop = selected_range source selector in
            String.sub source start (stop - start))
          selectors
        |> String.concat "\n"
  in
  `Assoc
    [ "surface", `String surface
    ; "source", `String (relative_path root path)
    ; "source_sha256", `String (sha256 source)
    ; "api_sha256", `String (sha256 (normalized_api selected))
    ; "selectors", string_list selectors
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
  let prismel name = Filename.concat root ("lib/prismel/" ^ name ^ ".mli") in
  let legacy_entries =
    [ legacy_entry root "Prismel.Low" (prismel "low") []
    ; legacy_entry root "Prismel.Low.App" (prismel "app") []
    ; legacy_entry root "Prismel.Low.Backend" (prismel "backend") []
    ; legacy_entry root "Prismel.Low.Graphics" (prismel "graphics") []
    ; legacy_entry root "Prismel.Low.Window" (prismel "window") []
    ; legacy_entry root "Prismel.Image.Private" (prismel "image")
        [ "module:Private" ]
    ; legacy_entry root "Prismel.Font.Private" (prismel "font")
        [ "module:Private" ]
    ; legacy_entry root "Prismel.Font.release_renderer" (prismel "font")
        [ "value:release_renderer" ]
    ]
    @ (public_interfaces root "runtime"
       |> List.map (fun (module_name, path) ->
         legacy_entry root ("Runtime." ^ module_name) path []))
    |> List.sort (json_sort_field "surface")
  in
  let common =
    [ "schema", `Int 1
    ; "baseline_commit", member_exn "baseline_commit" baseline
    ; "baseline_plan_sha256", member_exn "new_gpu_stuff_sha256" baseline
    ; "generator", `String "tools/gpu_migration/api_manifest.exe"
    ]
  in
  ( `Assoc
      (common
       @ [ "kind", `String "stable_high_level"
         ; "module_count", `Int (List.length stable_entries)
         ; "modules", `List stable_entries
         ])
  , `Assoc
      (common
       @ [ "kind", `String "declared_legacy_sdl"
         ; "surface_count", `Int (List.length legacy_entries)
         ; "surfaces", `List legacy_entries
         ]) )

let check path expected =
  if not (Sys.file_exists path) then begin
    Printf.eprintf "missing generated manifest: %s\n%!" path;
    false
  end
  else if read_file path <> expected then begin
    Printf.eprintf
      "stale generated manifest: %s\nrun dune exec \
       tools/gpu_migration/api_manifest.exe -- --write\n%!"
      path;
    false
  end
  else true

let main () =
  let root, mode = root_and_mode () in
  let stable, legacy = generate root in
  let outputs =
    [ Filename.concat root stable_relative, pretty_json stable
    ; Filename.concat root legacy_relative, pretty_json legacy
    ]
  in
  match mode with
  | Write ->
      List.iter
        (fun (path, value) ->
          ensure_directory (Filename.dirname path);
          write_file path value)
        outputs;
      let stable_count =
        Option.value (member_int "module_count" stable) ~default:0
      in
      let legacy_count =
        Option.value (member_int "surface_count" legacy) ~default:0
      in
      Printf.printf "wrote %d stable modules and %d legacy surfaces\n%!"
        stable_count legacy_count
  | Check ->
      if not (List.for_all (fun (path, value) -> check path value) outputs) then
        exit 1

let () = protect_main main
