open Yojson.Safe.Util

let fail format = Printf.ksprintf failwith format
let require condition format = Printf.ksprintf (fun message -> if not condition then failwith message) format

let int64_string value name = value |> member name |> to_string |> Int64.of_string

let source value name =
  let snapshot = value |> member name in
  let commit = snapshot |> member "commit" |> to_string in
  let clean = snapshot |> member "clean" |> to_bool in
  require (String.length commit = 40) "%s commit is not canonical" name;
  require clean "%s source is dirty" name;
  commit

let validate path =
  let value = Yojson.Safe.from_file path in
  require (value |> member "backend" |> to_string = "real-m1-runtime-next-metal")
    "R9 report is not from the real native Metal boundary";
  require (value |> member "profile" |> to_string = "release")
    "R9 report is not release-profile";
  require (value |> member "protocol_r9_requested" |> to_bool)
    "R9 protocol marker is absent";
  require (value |> member "camera_only_changes" |> to_bool)
    "R9 camera-only state changes were not exercised";
  require (value |> member "sample_frames" |> to_int = 600)
    "R9 requires exactly 600 measured frames";
  let before = source value "source_before" in
  let after = source value "source_after" in
  require (before = after && (value |> member "source_stable_clean" |> to_bool))
    "R9 source changed during measurement";
  require (int64_string value "prepared_upload_bytes" > 0L)
    "R9 preparation uploaded no stable mesh";
  require (int64_string value "measurement_upload_bytes" = 0L)
    "R9 logical replacement upload was nonzero";
  [ "native_buffer_creates"; "native_buffer_writes";
    "native_mesh_buffer_creates"; "native_mesh_buffer_writes" ]
  |> List.iter (fun name ->
    require (value |> member name |> to_int = 0)
      "R9 measured native counter %s was nonzero" name);
  [ "native_buffer_create_bytes"; "native_buffer_write_bytes";
    "native_mesh_buffer_create_bytes"; "native_mesh_buffer_write_bytes" ]
  |> List.iter (fun name ->
    require (int64_string value name = 0L)
      "R9 measured native byte counter %s was nonzero" name);
  let frames = value |> member "sample_frames" |> to_int in
  let pieces = value |> member "pieces" |> to_int in
  let draws = value |> member "draws" |> to_int in
  let passes = value |> member "passes" |> to_int in
  let submissions = value |> member "backend_calls" |> to_int in
  require (pieces > 0 && draws = frames * pieces)
    "R9 draw count does not scale with stable draw batches";
  require (passes = frames && submissions = frames)
    "R9 pass/submission count is not exactly one per frame";
  let cache = value |> member "cache_entries" |> to_int in
  require (cache > 0 && cache <= 64) "R9 cache is empty or exceeds capacity 64";
  Printf.printf "R9 native upload/batching evidence passed: %d frames, %d draws\n%!"
    frames draws

let run benchmark output =
  let arguments =
    [| benchmark; "scene3"; "--protocol-r9"; "--visibility"; "hidden";
       "--report"; output |]
  in
  let pid = Unix.create_process benchmark arguments Unix.stdin Unix.stdout Unix.stderr in
  match snd (Unix.waitpid [] pid) with
  | Unix.WEXITED 0 -> validate output
  | Unix.WEXITED code -> fail "R9 benchmark exited %d" code
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
      fail "R9 benchmark was interrupted by signal %d" signal

let () =
  let benchmark = ref None in
  let output = ref None in
  let validate_only = ref None in
  Arg.parse
    [ "--benchmark", Arg.String (fun value -> benchmark := Some value), "EXE native benchmark"
    ; "--output", Arg.String (fun value -> output := Some value), "FILE evidence output"
    ; "--validate", Arg.String (fun value -> validate_only := Some value), "FILE validate existing evidence"
    ]
    (fun value -> fail "unexpected argument %S" value)
    "runtime_next_native_r9_protocol";
  match !validate_only, !benchmark, !output with
  | Some path, None, None -> validate path
  | None, Some benchmark, Some output -> run benchmark output
  | _ -> fail "use --validate FILE or --benchmark EXE --output FILE"
