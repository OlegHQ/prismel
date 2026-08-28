module Strings = Set.Make (String)

let require condition format =
  Printf.ksprintf (fun message -> if not condition then failwith message) format

let read_file path =
  let input = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr input)
    (fun () -> really_input_string input (in_channel_length input))

let words contents =
  let normalized = Bytes.of_string contents in
  Bytes.iteri
    (fun index character ->
      if not
           ((character >= 'a' && character <= 'z')
            || (character >= 'A' && character <= 'Z')
            || (character >= '0' && character <= '9')
            || character = '_')
      then Bytes.set normalized index ' ')
    normalized;
  Bytes.to_string normalized
  |> String.split_on_char ' '
  |> List.filter (fun value -> value <> "")
  |> List.fold_left (fun result value -> Strings.add value result) Strings.empty

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

let set values =
  List.fold_left (fun result value -> Strings.add value result) Strings.empty values

let expect_set label expected actual =
  let missing = Strings.diff expected actual |> Strings.elements in
  let extra = Strings.diff actual expected |> Strings.elements in
  require (missing = [] && extra = []) "%s drift: missing=[%s] extra=[%s]" label
    (String.concat "," missing) (String.concat "," extra)

let render_candidate ~public_modules ~private_modules ~dependencies =
  Printf.sprintf
    "; Validated B5 candidate only. Do not copy into lib/prismel_next_api until the\n\
     ; atomic switch owns deletion of the old lib/prismel and lib/runtime owners.\n\
     (library\n\
     \ (name prismel)\n\
     \ (public_name prismel)\n\
     \ (modules\n\
     \  %s\n\
     \  %s)\n\
     \ (private_modules %s)\n\
     \ (libraries %s))\n"
    (public_modules |> List.filteri (fun index _ -> index < 10) |> String.concat " ")
    ((public_modules |> List.filteri (fun index _ -> index >= 10)) @ private_modules
     |> String.concat " ")
    (String.concat " " private_modules) (String.concat " " dependencies)

let () =
  let root = ref "." in
  let candidate = ref "tools/phase5_switch/prismel_owner_candidate.dune" in
  let map_path = ref "specification/evidence/gpu_migration/phase5_prismel_api_map.json" in
  Arg.parse
    [ "--root", Arg.Set_string root, "repository root"
    ; "--candidate", Arg.Set_string candidate, "candidate Dune template"
    ; "--map", Arg.Set_string map_path, "public API map"
    ]
    (fun value -> raise (Arg.Bad value)) "B5 Prismel owner candidate gate";
  let root = Unix.realpath !root in
  let absolute path = if Filename.is_relative path then Filename.concat root path else path in
  let mapping = Yojson.Safe.from_file (absolute !map_path) in
  let open Yojson.Safe.Util in
  let public_modules =
    mapping |> member "modules" |> to_list
    |> List.map (fun row -> row |> member "module" |> to_string |> String.lowercase_ascii)
    |> List.sort String.compare
  in
  let private_modules = [ "scene3_raster2_lowering"; "scene3_raster2_resources" ] in
  let dependencies =
    [ "domainslib"; "prismel_next_resources"; "runtime_next_input";
      "unix"; "prismel_next_execution"; "runtime_next_compat" ]
  in
  require (List.length public_modules = 40) "candidate public module count is not 40";
  expect_set "public/private overlap" Strings.empty
    (Strings.inter (set public_modules) (set private_modules));
  let source_directory = Filename.concat root "lib/prismel_next_api" in
  List.iter
    (fun name ->
      List.iter
        (fun suffix ->
          let path = Filename.concat source_directory (name ^ suffix) in
          require (Sys.file_exists path) "candidate source missing: %s" path)
        [ ".ml"; ".mli" ])
    public_modules;
  List.iter
    (fun name ->
      let path = Filename.concat source_directory (name ^ ".ml") in
      require (Sys.file_exists path) "candidate private source missing: %s" path)
    private_modules;
  let forbidden = set [ "prismel"; "prismel_next_api"; "runtime"; "tsdl";
                        "tsdl_gfx"; "tsdl_image"; "tsdl_ttf"; "tsdl_mixer" ] in
  expect_set "candidate forbidden dependency co-link" Strings.empty
    (Strings.inter forbidden (set dependencies));
  let sibling_consumers =
    Sys.readdir (Filename.concat root "lib") |> Array.to_list
    |> List.filter_map (fun directory ->
      let path = Filename.concat root ("lib/" ^ directory ^ "/dune") in
      if directory = "prismel" || directory = "prismel_next_api" || not (Sys.file_exists path)
      then None
      else
        let tokens = dune_library_dependencies (read_file path) in
        if Strings.mem "prismel" tokens then begin
          require (not (Strings.mem "prismel_next_api" tokens))
            "%s co-links prismel and prismel_next_api" path;
          require (not (Strings.mem "runtime" tokens))
            "%s still co-links legacy runtime with prismel" path;
          Some directory
        end else None)
    |> List.sort String.compare
  in
  expect_set "sibling prismel consumers"
    (set [ "geom"; "pdk"; "prismel_runtime_next"; "procedural"; "pxui";
           "pxui_graph"; "sketch"; "sketch_ui"; "sop_catalog" ])
    (set sibling_consumers);
  let expected = render_candidate ~public_modules ~private_modules ~dependencies in
  require (read_file (absolute !candidate) = expected)
    "candidate Dune template drift; regenerate from checked module/dependency sets";
  Printf.printf
    "B5 Prismel owner candidate passed: name/public_name prismel, %d public + %d private modules, %d dependencies, %d sibling consumers, no legacy co-link\n"
    (List.length public_modules) (List.length private_modules)
    (List.length dependencies) (List.length sibling_consumers)
