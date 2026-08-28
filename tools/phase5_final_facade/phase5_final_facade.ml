let require condition format =
  Printf.ksprintf (fun message -> if not condition then failwith message) format

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let contains text needle =
  let rec loop offset =
    offset + String.length needle <= String.length text
    && (String.sub text offset (String.length needle) = needle
        || loop (offset + 1))
  in
  loop 0

let () =
  let root = ref "." in
  Arg.parse [ "--root", Arg.Set_string root, "repository root" ]
    (fun value -> raise (Arg.Bad value)) "phase5_final_facade";
  let root = Unix.realpath !root in
  let path value = Filename.concat root value in
  let retired =
    [ "lib/runtime_next_headless"; "lib/runtime_next_web";
      "tools/phase5_switch/runtime_owner_candidate.dune";
      "tools/phase5_switch/runtime_owner_candidate.json";
      "tools/phase5_switch/test_runtime_owner_candidate.ml";
      "tools/phase5_switch/prismel_owner_candidate.dune";
      "tools/phase5_switch/test_prismel_owner_candidate.ml" ]
  in
  List.iter
    (fun value -> require (not (Sys.file_exists (path value)))
      "retired target candidate remains: %s" value)
    retired;
  let runtime_dune = read (path "lib/runtime_next/dune") in
  List.iter
    (fun dependency -> require (not (contains runtime_dune dependency))
      "native runtime still references retired dependency %s" dependency)
    [ "runtime_next_headless"; "runtime_next_web"; " wap" ];
  let sketch_mli = read (path "lib/prismel_next_api/sketch.mli") in
  require (contains sketch_mli "type render_target = Native")
    "public render target is not exactly Native";
  require (not (contains sketch_mli "Headless"))
    "public render target still exposes Headless";
  require (not (contains sketch_mli "Web"))
    "public render target still exposes Web";
  print_endline
    "Phase5 final facade passed: one native target; Headless/Web/Wap candidates absent"
