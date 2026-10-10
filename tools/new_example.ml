let fail format =
  Printf.ksprintf (fun message ->
    prerr_endline ("rays-new: " ^ message);
    exit 2) format

let valid_name name =
  String.length name > 0
  && String.for_all
       (function
         | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true
         | _ -> false)
       name

let write path contents =
  let channel = open_out path in
  Fun.protect ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel contents)

(* An example owns its executable; a sketch is only its sketch.rays, which
   sketches/dune turns into one. *)
let example_dune =
  "(rule\n (target lisp.ml)\n (deps sketch.rays)\n (action (chdir %{workspace_root}\n\
  \  (with-stdout-to %{target} (run %{bin:rays-lisp} ml %{dep:sketch.rays})))))\n\
   (executable (name lisp) (modules lisp) (libraries rays_editor))\n\
   (rule\n (alias smoke-all)\n (locks ../../smoke_window)\n\
  \ (action (setenv RAYS_MAX_FRAMES 30 (run %{exe:lisp.exe}))))\n"

let () =
  let root = ref None in
  let sketch = ref false in
  let name = ref None in
  let specs = [
    "--sketch", Arg.Set sketch, " Create sketches/NAME/sketch.rays (no dune file)";
    "--root", Arg.String (fun r -> root := Some r), "DIR Parent directory (default: examples, or sketches with --sketch)";
  ] in
  Arg.parse specs (fun value ->
    match !name with
    | None -> name := Some value
    | Some _ -> fail "expected one example name")
    "Create a Rays Lisp example: dune exec tools/new_example.exe -- NAME";
  let root = match !root with Some r -> r | None -> if !sketch then "sketches" else "examples" in
  let name = match !name with Some name -> name | None -> fail "missing NAME" in
  if not (valid_name name) then
    fail "NAME must contain only lowercase letters, digits, _ or -";
  let directory = Filename.concat root name in
  if Sys.file_exists directory then fail "%s already exists" directory;
  if not (Sys.file_exists root && Sys.is_directory root) then
    fail "root directory %s does not exist" root;
  Unix.mkdir directory 0o755;
  (* ponytail: the fixture is read from the working directory, the repo root *)
  let bloom = In_channel.with_open_bin "specification/workspace/cases/bloom.lisp" In_channel.input_all in
  let bloom = Str.global_replace (Str.regexp_string "bloom_studio") (String.map (function '-' -> '_' | c -> c) name) bloom in
  write (Filename.concat directory "sketch.rays") bloom;
  if !sketch then
    Printf.printf "Created %s/sketch.rays\nRun: dune build @runtest; dune promote\n%!" directory
  else begin
    write (Filename.concat directory "dune") example_dune;
    Printf.printf "Created %s\nRun: dune exec %s/lisp.exe\n%!" directory directory
  end
