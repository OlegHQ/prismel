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

let template name =
  Printf.sprintf {|open Rays

let view (frame : Frame.t) =
  Scene.[
    clear (Color.hex_exn "#111827");
    circle ~at:frame.mouse ~radius:36 ~fill:(Color.hex_exn "#22d3ee") ();
    text ~at:(12, 12) "%s";
  ]

let () =
  Sketch.run
    ~config:{ Sketch.default_config with title = "%s" }
    view
|} name name

let () =
  let root = ref None in
  let lisp = ref false in
  let name = ref None in
  let specs = [
    "--lisp", Arg.Set lisp, " Create sketches/NAME/sketch.rays from the Bloom fixture";
    "--root", Arg.String (fun r -> root := Some r), "DIR Parent directory (default: examples)";
  ] in
  Arg.parse specs (fun value ->
    match !name with
    | None -> name := Some value
    | Some _ -> fail "expected one example name")
    "Create a Rays sketch: dune exec tools/new_example.exe -- NAME";
  let root = ref (match !root with Some r -> r | None -> if !lisp then "sketches" else "examples") in
  let name = match !name with Some name -> name | None -> fail "missing NAME" in
  if not (valid_name name) then
    fail "NAME must contain only lowercase letters, digits, _ or -";
  let directory = Filename.concat !root name in
  if Sys.file_exists directory then fail "%s already exists" directory;
  if not (Sys.file_exists !root && Sys.is_directory !root) then
    fail "root directory %s does not exist" !root;
  Unix.mkdir directory 0o755;
  if !lisp then begin
    (* ponytail: the fixture is read from the working directory, the repo root *)
    let bloom = In_channel.with_open_bin "specification/workspace/cases/bloom.lisp" In_channel.input_all in
    let bloom = Str.global_replace (Str.regexp_string "bloom_studio") (String.map (function '-' -> '_' | c -> c) name) bloom in
    write (Filename.concat directory "sketch.rays") bloom;
    Printf.printf "Created %s/sketch.rays\nRun: dune build @runtest; dune promote\n%!" directory;
    exit 0
  end;
  write (Filename.concat directory "dune")
    "(executable\n (name main)\n (libraries rays))\n";
  write (Filename.concat directory "main.ml") (template name);
  Printf.printf "Created %s\nRun: dune exec %s/main.exe\n%!" directory directory
