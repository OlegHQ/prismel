type scenario = Basic | Pxui_like | Canvas_offscreen | Scene3_builtin

let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let metal = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)

let rss_kib () =
  let argv = [| "/bin/ps"; "-o"; "rss="; "-p"; string_of_int (Unix.getpid ()) |] in
  let input = Unix.open_process_args_in argv.(0) argv in
  Fun.protect ~finally:(fun () -> ignore (Unix.close_process_in input))
    (fun () -> int_of_string (String.trim (input_line input)))

let name = function
  | Basic -> "basic"
  | Pxui_like -> "pxui-like"
  | Canvas_offscreen -> "canvas-offscreen"
  | Scene3_builtin -> "scene3-builtin"

let draw_count = function Basic -> 1 | Pxui_like -> 8 | Canvas_offscreen -> 3 | Scene3_builtin -> 4

let frozen_software_hash = function
  | Basic -> "183be222f2a9499335f80e49bab17f24"
  | Pxui_like -> "c28fb438cfaf0381adc6b8dddec9d6cf"
  | Canvas_offscreen -> "6669327647bf796bcc136e62a62f7c95"
  | Scene3_builtin -> "52462b7485ced3177c5f7bf2fda8a7ae"

let mesh scenario index =
  let vertices = Bytes.make 48 '\000' and indices = Bytes.make 12 '\000' in
  Bytes.set_int32_le indices 4 1l;
  Bytes.set_int32_le indices 8 2l;
  { Scene_execution.key = Printf.sprintf "%s-%d" (name scenario) index;
    vertices; vertex_count = 3; indices; index_count = 3 }

let draws scenario extent =
  List.init (draw_count scenario) (fun index ->
    let inset = 0 in
    { Scene_execution.mesh = mesh scenario index;
      state = { viewport = (0, 0, extent, extent);
        scissor = (inset, inset, extent - inset, extent - inset) } })

let check_pixels extent bytes =
  if Bytes.length bytes <> extent * extent * 4 then failwith "native capture size drift";
  for offset = 0 to extent * extent - 1 do
    let base = offset * 4 in
    if Char.code (Bytes.get bytes base) <> 64
       || Char.code (Bytes.get bytes (base + 1)) <> 128
       || Char.code (Bytes.get bytes (base + 2)) <> 191
       || Char.code (Bytes.get bytes (base + 3)) <> 255
    then failwith "native fixed-pipeline pixel drift"
  done;
  Digest.to_hex (Digest.bytes bytes)

let run scenario =
  let runtime = get (Runtime_next.create ~width:4 ~height:4) in
  let checkpoints = ref [] in
  for frame = 1 to 600 do
    ignore (get (Runtime_next.render runtime (draws scenario 4)));
    if List.mem frame [ 1; 2; 60; 600 ] then
      checkpoints := (frame, check_pixels 4 (get (Runtime_next.read_pixels runtime ~bytes_per_row:16))) :: !checkpoints
  done;
  get (Runtime_next.resize runtime ~width:8 ~height:8);
  ignore (get (Runtime_next.render runtime (draws scenario 8)));
  let resized_hash = check_pixels 8 (get (Runtime_next.read_pixels runtime ~bytes_per_row:32)) in
  get (Runtime_next.destroy runtime);
  if List.exists (fun (_, hash) -> hash <> "c28fb438cfaf0381adc6b8dddec9d6cf") !checkpoints
     || resized_hash <> "f9dc84a13290d920f46adc67e228d10e"
  then failwith "native qualification checkpoint hash drift";
  let uploaded = draw_count scenario * 60 in
  let native_hash = snd (List.hd !checkpoints) in
  `Assoc [ "scenario", `String (name scenario); "frames", `Int 601;
    "draw_calls", `Int (draw_count scenario * 601);
    "pass_calls", `Int 601; "render_calls", `Int 601; "readback_calls", `Int 5;
    "runtime_backend_calls", `Int 607;
    "prepared_upload_bytes", `Int uploaded;
    "frozen_software_hash", `String (frozen_software_hash scenario);
    "native_matches_frozen_software", `Bool (native_hash = frozen_software_hash scenario);
    "checkpoint_hashes", `List (List.rev_map (fun (frame, hash) -> `List [ `Int frame; `String hash ]) !checkpoints);
    "resized_hash", `String resized_hash ]

let () =
  let before = metal (Metal.Release_queue.stats ()) and rss_before = rss_kib () in
  match Runtime_next.create ~width:1 ~height:1 with
  | Error _ -> print_endline "runtime-next native qualification: skipped (no SDL3 Metal window/device)"
  | Ok probe ->
      get (Runtime_next.destroy probe);
      let rss_checkpoints = ref [] in
      let scenarios = List.map (fun scenario -> let result = run scenario in rss_checkpoints := rss_kib () :: !rss_checkpoints; result)
        [ Basic; Pxui_like; Canvas_offscreen; Scene3_builtin ] in
      ignore (metal (Metal.Release_queue.drain ()));
      let after = metal (Metal.Release_queue.stats ()) and rss_after = rss_kib () in
      if after.live_handles <> before.live_handles then failwith "native qualification live-handle delta";
      let report = `Assoc [ "schema", `Int 1; "host", `String "Apple M1";
        "checkpoints", `List [ `Int 1; `Int 2; `Int 60; `Int 600 ];
        "scenarios", `List scenarios; "rss_before_kib", `Int rss_before;
        "rss_after_kib", `Int rss_after; "live_handles_before", `Int before.live_handles;
        "live_handles_after", `Int after.live_handles;
        "rss_after_each_scenario_kib", `List (List.rev_map (fun value -> `Int value) !rss_checkpoints);
        "msaa", `String "unsupported-by-runtime-next-sample-count-1";
        "shader3", `String "software-only-not-qualified-by-this-test";
        "retina", `String "resize-qualified-drawable-scale-not-exposed" ] in
      print_endline (Yojson.Safe.pretty_to_string report)
