type target = Headless | Web

let ok = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let percentile p values =
  let copy = Array.copy values in Array.sort Float.compare copy;
  copy.(max 0 (min (Array.length copy - 1)
    (int_of_float (Float.ceil (p *. float (Array.length copy))) - 1)))
let putf bytes offset value = Bytes.set_int64_le bytes offset (Int64.bits_of_float value)

let mesh ~key triangles =
  let vertices = Bytes.make 48 '\000' and indices = Bytes.create (triangles * 12) in
  List.iteri (fun index (x, y) -> putf vertices (index * 16) x; putf vertices (index * 16 + 8) y)
    [-1., 1.; 1., 1.; -1., -1.];
  for index = 0 to triangles - 1 do
    let offset = index * 12 in Bytes.set_int32_le indices offset 0l;
    Bytes.set_int32_le indices (offset + 4) 1l; Bytes.set_int32_le indices (offset + 8) 2l
  done;
  { Scene_execution.key; vertices; vertex_count = 3; indices; index_count = triangles * 3 }

let state width height : Scene_execution.state =
  { viewport = (0, 0, width, height); scissor = (0, 0, width, height);
    cull = Ogpu.Render_pass.Cull_none; depth_compare = Ogpu.Render_pass.Always;
    depth_write = false; depth_load = Ogpu.Render_pass.Clear; depth_clear = 1.;
    transform_uniforms = None; stencil_state = None;
    stencil_load = Ogpu.Render_pass.Load; stencil_clear = 0 }

let workload scenario width height =
  let make key triangles =
    { Scene_execution.mesh = mesh ~key triangles; state = state width height } in
  match scenario with
  | "basic" -> [make "basic" 128]
  | "pxui" -> List.init 64 (fun i -> make ("pxui-" ^ string_of_int i) 2)
  | "canvas" -> List.init 8 (fun i -> make ("canvas-" ^ string_of_int i) 32)
  | "scene3" -> List.init 12 (fun i -> make ("scene3-" ^ string_of_int i) 9_216)
  | value -> invalid_arg ("unknown scenario " ^ value)

let artifact scenario width height =
  match scenario with
  | "basic" -> R10_scene2_legacy_equivalent.create Basic ~width ~height
  | "pxui" -> R10_scene2_legacy_equivalent.create Pxui ~width ~height
  | "canvas" -> R10_scene2_legacy_equivalent.create Canvas ~width ~height
  | "scene3" ->
      let draws = workload scenario width height in
      { R10_scene2_legacy_equivalent.draws;
        workload_signature =
          Printf.sprintf "scene3-pending-canonical:%dx%d:%d" width height
            (List.length draws);
        work_units = List.fold_left
          (fun total draw -> total + (draw.Scene_execution.mesh.index_count / 3))
          0 draws }
  | value -> invalid_arg ("unknown scenario " ^ value)

let rss_kib () =
  let argv = [| "/bin/ps"; "-o"; "rss="; "-p"; string_of_int (Unix.getpid ()) |] in
  let input = Unix.open_process_args_in argv.(0) argv in
  Fun.protect ~finally:(fun () -> ignore (Unix.close_process_in input))
    (fun () -> int_of_string (String.trim (input_line input)))

let () =
  let target = ref Headless and scenario = ref "" and profile = ref "release"
  and width = ref 64 and height = ref 64 and warmup = ref 3. and seconds = ref 30.
  and frame_rate = ref 120. in
  Arg.parse [
    "--target", Arg.Symbol (["headless"; "web"], fun x -> target := if x = "headless" then Headless else Web), "target";
    "--scenario", Arg.Set_string scenario, "scenario"; "--profile", Arg.Set_string profile, "profile";
    "--width", Arg.Set_int width, "logical width"; "--height", Arg.Set_int height, "logical height";
    "--warmup", Arg.Set_float warmup, "warmup seconds"; "--seconds", Arg.Set_float seconds, "measurement seconds";
    "--frame-rate", Arg.Set_float frame_rate, "fixed frame scheduling rate (default 120 Hz)" ]
    (fun value -> raise (Arg.Bad ("unexpected argument " ^ value))) "R10 runtime-next target benchmark";
  if !scenario = "" || !width <= 0 || !height <= 0 || !warmup <= 0.
     || !seconds <= 0. || !frame_rate <= 0. || not (Float.is_finite !frame_rate) then
    invalid_arg "invalid arguments";
  let artifact = artifact !scenario !width !height in
  let work = artifact.draws in
  let render, capture, destroy = match !target with
    | Headless ->
        let runtime = ok (Runtime_next_headless.create ~logical_width:!width ~logical_height:!height
          ~drawable_width:!width ~drawable_height:!height) in
        (fun () -> Runtime_next_headless.render runtime work),
        (fun () -> Runtime_next_headless.read_pixels runtime ~bytes_per_row:(!width * 4)),
        (fun () -> Runtime_next_headless.destroy runtime)
    | Web ->
        let config = { Wap.default_config with interface = "127.0.0.1"; port = 0 } in
        let runtime = ok (Runtime_next_web.create ~wap_config:config ~logical_width:!width
          ~logical_height:!height ~drawable_width:!width ~drawable_height:!height ()) in
        (fun () -> Runtime_next_web.render runtime work),
        (fun () -> Runtime_next_web.read_pixels runtime ~bytes_per_row:(!width * 4)),
        (fun () -> Runtime_next_web.destroy runtime) in
  let run_for duration collect =
    let count = max 1 (int_of_float (Float.round (duration *. !frame_rate))) in
    let epoch = Unix.gettimeofday () and values = Array.make count 0. in
    for index = 0 to count - 1 do
      let render_started = Unix.gettimeofday () in ignore (ok (render ()));
      if collect then values.(index) <- Unix.gettimeofday () -. render_started;
      let deadline = epoch +. (float (index + 1) /. !frame_rate) in
      let remaining = deadline -. Unix.gettimeofday () in
      if remaining > 0. then Unix.sleepf remaining
    done;
    if collect then values else [||] in
  ignore (run_for !warmup false); Gc.full_major ();
  let rss0 = rss_kib () in
  let gc0 = Gc.quick_stat () and allocated0 = Gc.allocated_bytes ()
  and cpu0 = Unix.times () and started = Unix.gettimeofday () in
  let frames = run_for !seconds true in
  let wall = Unix.gettimeofday () -. started and cpu1 = Unix.times () and gc1 = Gc.quick_stat () in
  let allocated = Gc.allocated_bytes () -. allocated0
  and promoted = (gc1.promoted_words -. gc0.promoted_words) *. float (Sys.word_size / 8) in
  let rss1 = rss_kib () and framebuffer = ok (capture ()) in
  ok (destroy ());
  let count = Array.length frames in
  let draws = count * List.length work in
  let json = `Assoc ["schema", `Int 1; "benchmark", `String "r10-runtime-next-target";
    "scenario", `String !scenario; "target", `String (match !target with Headless -> "headless" | Web -> "web");
    "backend", `String (match !target with Headless -> "runtime-next-raster2" | Web -> "runtime-next-wap-raster2");
    "profile", `String !profile; "width", `Int !width; "height", `Int !height;
    "drawable_width", `Int !width; "drawable_height", `Int !height; "pixel_scale", `Float 1.;
    "warmup_seconds", `Float !warmup; "requested_measure_seconds", `Float !seconds;
    "scheduling", `String "fixed-rate"; "scheduled_frame_rate", `Float !frame_rate;
    "frames", `Int count; "wall_seconds", `Float wall;
    "user_seconds", `Float (cpu1.tms_utime -. cpu0.tms_utime);
    "system_seconds", `Float (cpu1.tms_stime -. cpu0.tms_stime);
    "cpu_percent", `Float (100. *. (cpu1.tms_utime +. cpu1.tms_stime -. cpu0.tms_utime -. cpu0.tms_stime) /. wall);
    "allocated_bytes", `Float allocated; "promoted_bytes", `Float promoted;
    "allocated_bytes_per_frame", `Float (allocated /. float count);
    "promoted_bytes_per_frame", `Float (promoted /. float count);
    "rss_before_kib", `Int rss0; "rss_after_kib", `Int rss1;
    "rss_delta_kib", `Int (rss1 - rss0); "peak_sampled_rss_kib", `Int (max rss0 rss1);
    "workload_signature", `String artifact.workload_signature;
    "work_units", `Int artifact.work_units;
    "framebuffer_digest", `String (Digest.to_hex (Digest.bytes framebuffer));
    "median_frame_seconds", `Float (percentile 0.5 frames);
    "p95_frame_seconds", `Float (percentile 0.95 frames);
    "p99_frame_seconds", `Float (percentile 0.99 frames);
    "upload_bytes_during_measurement", `Null; "draw_count", `Int draws;
    "pass_count", `Int count; "backend_calls", `Int count;
    "native_gpu_counters", `Null; "thermal_state", `Null; "power_state", `Null] in
  print_endline (Yojson.Safe.to_string json)
