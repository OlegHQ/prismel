type scenario = Basic | Pxui | Canvas | Scene3 | Shattered
type visibility = Visible | Hidden

type counters = {
  mutable uploads : int64;
  mutable draws : int;
  mutable passes : int;
  mutable ffi_calls : int;
}

type sample = {
  wall : float;
  cpu : float;
  allocated : float;
  promoted : float;
  major : float;
  rss : int option;
}

let ok = function Ok value -> value | Error error ->
  failwith (Ogpu.Error.to_string error)

let scenario_name = function
  | Basic -> "basic"
  | Pxui -> "pxui-like"
  | Canvas -> "canvas"
  | Scene3 -> "scene3"
  | Shattered -> "shattered-cube"

let parse_scenario = function
  | "basic" -> Basic | "pxui" | "pxui-like" -> Pxui
  | "canvas" -> Canvas | "scene3" -> Scene3
  | "shattered" | "shattered-cube" -> Shattered
  | value -> invalid_arg ("unknown scenario: " ^ value)

let visibility_name = function Visible -> "visible" | Hidden -> "hidden"

let resident_kib () =
  let argv = [| "/bin/ps"; "-o"; "rss="; "-p"; string_of_int (Unix.getpid ()) |] in
  try
    let channel = Unix.open_process_args_in argv.(0) argv in
    Fun.protect ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> match input_line channel |> String.trim with
       | "" -> None | value -> Some (int_of_string value))
  with End_of_file | Failure _ | Unix.Unix_error _ -> None

let percentile fraction values =
  let copy = Array.copy values in
  Array.sort Float.compare copy;
  copy.(max 0 (min (Array.length copy - 1)
    (int_of_float (Float.ceil (fraction *. float (Array.length copy))) - 1)))

let put_f64 bytes offset value = Bytes.set_int64_le bytes offset (Int64.bits_of_float value)

let mesh ~key triangles =
  let vertices = Bytes.make 48 '\000' in
  (* Off-screen geometry keeps this benchmark focused on preparation/batching. *)
  put_f64 vertices 0 (-4.); put_f64 vertices 8 (-4.);
  put_f64 vertices 16 (-3.); put_f64 vertices 24 (-4.);
  put_f64 vertices 32 (-4.); put_f64 vertices 40 (-3.);
  let indices = Bytes.create (triangles * 12) in
  for triangle = 0 to triangles - 1 do
    let base = triangle * 12 in
    Bytes.set_int32_le indices base 0l;
    Bytes.set_int32_le indices (base + 4) 1l;
    Bytes.set_int32_le indices (base + 8) 2l
  done;
  { Scene_execution.key; vertices; vertex_count = 3; indices;
    index_count = triangles * 3 }

let state index =
  let inset = index land 1 in
  { Scene_execution.viewport = (0, 0, 64, 64);
    scissor = (inset, inset, 64 - inset, 64 - inset) }

let draws = function
  | Basic -> [ { Scene_execution.mesh = mesh ~key:"basic" 128; state = state 0 } ]
  | Pxui -> List.init 64 (fun index ->
      { Scene_execution.mesh = mesh ~key:("pxui-" ^ string_of_int index) 2;
        state = state 0 })
  | Canvas -> List.init 8 (fun index ->
      { Scene_execution.mesh = mesh ~key:("canvas-" ^ string_of_int index) 32;
        state = state 0 })
  | Scene3 -> List.init 12 (fun index ->
      { Scene_execution.mesh = mesh ~key:("scene3-" ^ string_of_int index) 9_216;
        state = state 0 })
  | Shattered ->
      let pieces = 18_278 and triangles = 278_368 in
      let base = triangles / pieces and remainder = triangles mod pieces in
      List.init pieces (fun index ->
        let count = base + if index < remainder then 1 else 0 in
        { Scene_execution.mesh = mesh ~key:("shard-" ^ string_of_int index) count;
          state = state 0 })

let instrument counters (driver : Ogpu.Backend.driver) : Ogpu.Backend.driver =
  let create_device () =
    counters.ffi_calls <- counters.ffi_calls + 1;
    Result.map (fun (device : Ogpu.Backend.driver_device) ->
      let create_buffer descriptor =
        counters.ffi_calls <- counters.ffi_calls + 1;
        counters.uploads <- Int64.add counters.uploads descriptor.Ogpu.Types.size;
        Result.map (fun (resource : Ogpu.Backend.driver_resource) ->
          { resource with write = (fun offset bytes ->
              counters.ffi_calls <- counters.ffi_calls + 1;
              resource.write offset bytes) }) (device.create_buffer descriptor)
      in
      let create_queue () =
        Result.map (fun (queue : Ogpu.Backend.driver_queue) ->
          { queue with submit = (fun command ~resources ~pipelines ->
              counters.ffi_calls <- counters.ffi_calls + 1;
              (match command with
               | Ogpu.Backend.Render submission ->
                   counters.passes <- counters.passes + 1;
                   counters.draws <- counters.draws
                     + List.length (Ogpu.Render_pass.submission_draws submission)
               | Transfer _ | Compute _ -> ());
              queue.submit command ~resources ~pipelines) }) (device.create_queue ())
      in
      { device with create_buffer; create_queue }) (driver.create_device ())
  in
  { Ogpu.Backend.create_device }

let configuration =
  { Ogpu.Surface.logical_width = 64; logical_height = 64;
    physical_width = 64; physical_height = 64; format = Rgba8_unorm;
    present_mode = Immediate; max_acquired = 2 }

let measure renderer visibility workload frames =
  Gc.full_major ();
  let gc0 = Gc.quick_stat () and allocated0 = Gc.allocated_bytes () in
  let times0 = Unix.times () and started = Unix.gettimeofday () in
  for _ = 1 to frames do
    match visibility with
    | Hidden -> ()
    | Visible -> ignore (ok (Scene_execution.render renderer workload))
  done;
  let wall = Unix.gettimeofday () -. started and times1 = Unix.times () in
  let gc1 = Gc.quick_stat () in
  { wall;
    cpu = times1.tms_utime +. times1.tms_stime -. times0.tms_utime -. times0.tms_stime;
    allocated = Gc.allocated_bytes () -. allocated0;
    promoted = (gc1.promoted_words -. gc0.promoted_words) *. float (Sys.word_size / 8);
    major = (gc1.major_words -. gc0.major_words) *. float (Sys.word_size / 8);
    rss = resident_kib () }

let () =
  let scenario = ref Basic and visibility = ref Visible and warmup = ref 1
  and samples = ref 5 and frames = ref 60 in
  let options = [
    "--visibility", Arg.Symbol (["visible"; "hidden"], fun value ->
      visibility := if value = "visible" then Visible else Hidden), "scheduling state";
    "--warmup", Arg.Set_int warmup, "warmup iterations";
    "--samples", Arg.Set_int samples, "measured samples";
    "--frames", Arg.Set_int frames, "frames per sample" ] in
  Arg.parse options (fun value -> scenario := parse_scenario value)
    "bench_runtime_next_parity SCENARIO [OPTIONS]";
  if !warmup < 0 || !samples <= 0 || !frames <= 0 then invalid_arg "invalid counts";
  let workload = draws !scenario in
  let counters = { uploads = 0L; draws = 0; passes = 0; ffi_calls = 0 } in
  let raw_driver = if !scenario = Shattered then fst (Ogpu.Backend_mock.create ())
    else fst (Ogpu_raster2.create ()) in
  let renderer = ok (Scene_execution.create (instrument counters raw_driver) configuration) in
  for _ = 1 to !warmup do ignore (measure renderer !visibility workload !frames) done;
  counters.draws <- 0; counters.passes <- 0; counters.ffi_calls <- 0;
  let upload_before = Scene_execution.upload_bytes renderer in
  let measured = Array.init !samples (fun _ -> measure renderer !visibility workload !frames) in
  let upload_after = Scene_execution.upload_bytes renderer in
  ok (Scene_execution.destroy renderer);
  let walls = Array.map (fun value -> value.wall /. float !frames) measured in
  let cpus = Array.map (fun value -> value.cpu) measured in
  let total_wall = Array.fold_left ( +. ) 0. (Array.map (fun value -> value.wall) measured) in
  let total_cpu = Array.fold_left ( +. ) 0. cpus in
  let float_list field = `List (Array.to_list (Array.map (fun value -> `Float (field value)) measured)) in
  let rss = Array.fold_left (fun result value -> match result, value.rss with
    | None, right -> right | left, None -> left | Some left, Some right -> Some (max left right)) None measured in
  let pieces, triangles = if !scenario = Shattered then 18_278, 278_368 else List.length workload,
    List.fold_left (fun total draw -> total + draw.Scene_execution.mesh.index_count / 3) 0 workload in
  let json = `Assoc [
    "schema", `Int 1; "benchmark", `String "runtime-next-parity";
    "engine", `String "runtime-next-prepared-ogpu";
    "backend", `String (if !scenario = Shattered then "backend-mock" else "ogpu-raster2");
    "scenario", `String (scenario_name !scenario); "visibility", `String (visibility_name !visibility);
    "profile", `String "release"; "warmup", `Int !warmup; "samples", `Int !samples;
    "frames_per_sample", `Int !frames; "pieces", `Int pieces; "triangles", `Int triangles;
    "median_frame_seconds", `Float (percentile 0.5 walls);
    "p95_frame_seconds", `Float (percentile 0.95 walls);
    "frames_per_second", `Float (float (!samples * !frames) /. total_wall);
    "cpu_percent", `Float (100. *. total_cpu /. total_wall);
    "allocated_bytes", float_list (fun value -> value.allocated);
    "promoted_bytes", float_list (fun value -> value.promoted);
    "major_bytes", float_list (fun value -> value.major);
    "peak_sampled_rss_kib", (match rss with None -> `Null | Some value -> `Int value);
    "prepared_upload_bytes", `String (Int64.to_string upload_before);
    "upload_bytes_during_measurement", `String (Int64.to_string (Int64.sub upload_after upload_before));
    "draw_count", `Int counters.draws; "pass_count", `Int counters.passes;
    "ffi_boundary_calls", `Int counters.ffi_calls;
    "native_gpu_counters", `Null;
    "machine", `Assoc ["os", `String Sys.os_type; "ocaml", `String Sys.ocaml_version;
      "word_size", `Int Sys.word_size] ] in
  print_endline (Yojson.Safe.to_string json)
