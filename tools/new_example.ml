let fail format =
  Printf.ksprintf (fun message ->
    prerr_endline ("prismel-new: " ^ message);
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
  Printf.sprintf {|open Prismel

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
  let root = ref "examples" in
  let name = ref None in
  let specs = [
    "--root", Arg.Set_string root, "DIR Parent directory (default: examples)";
  ] in
  Arg.parse specs (fun value ->
    match !name with
    | None -> name := Some value
    | Some _ -> fail "expected one example name")
    "Create a Prismel sketch: dune exec tools/new_example.exe -- NAME";
  let name = match !name with Some name -> name | None -> fail "missing NAME" in
  if not (valid_name name) then
    fail "NAME must contain only lowercase letters, digits, _ or -";
  let directory = Filename.concat !root name in
  if Sys.file_exists directory then fail "%s already exists" directory;
  if not (Sys.file_exists !root && Sys.is_directory !root) then
    fail "root directory %s does not exist" !root;
  Unix.mkdir directory 0o755;
  write (Filename.concat directory "dune")
    "(executable\n (name main)\n (libraries prismel))\n";
  write (Filename.concat directory "main.ml") (template name);
  Printf.printf "Created %s\nRun: dune exec %s/main.exe\n%!" directory directory
