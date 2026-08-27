type target = Headless | Web
type artifact = { draws : Scene_execution.draw list; workload_signature : string;
  work_units : int }

let ok = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let percentile p values =
  let copy = Array.copy values in Array.sort Float.compare copy;
  copy.(max 0 (min (Array.length copy - 1)
    (int_of_float (Float.ceil (p *. float (Array.length copy))) - 1)))

external monotonic_seconds : unit -> float = "prismel_r10_monotonic_seconds"
let artifact scenario width height =
  match scenario with
  | ("basic" | "pxui" | "canvas") as value ->
      let scenario = match value with "basic" -> R10_scene2_legacy_equivalent.Basic
        | "pxui" -> Pxui | _ -> Canvas in
      let descriptor=R10_scene2_legacy_equivalent.describe scenario ~width ~height in
      {draws=[];workload_signature=descriptor.semantic_signature;
        work_units=descriptor.work_units}
  | "scene3" ->
      let canonical = R10_scene3_legacy_equivalent.create ~width ~height in
      let proof =
        match R10_scene3_equivalence_bridge.prove ~width ~height canonical with
        | Ok proof -> proof
        | Error message ->
            invalid_arg ("non-equivalent canonical Scene3 artifact: " ^ message)
      in
      let descriptor=R10_scene2_legacy_equivalent.describe Scene3~width~height in
      { draws = canonical.software_draws;
        workload_signature = descriptor.semantic_signature;
        work_units = proof.triangles }
  | value -> invalid_arg ("unknown scenario " ^ value)

let rss_kib () =
  let argv = [| "/bin/ps"; "-o"; "rss="; "-p"; string_of_int (Unix.getpid ()) |] in
  let input = Unix.open_process_args_in argv.(0) argv in
  Fun.protect ~finally:(fun () -> ignore (Unix.close_process_in input))
    (fun () -> int_of_string (String.trim (input_line input)))

let () =
  let target = ref Headless and scenario = ref "" and profile = ref "release"
  and width = ref 64 and height = ref 64 and warmup = ref 3. and seconds = ref 30. in
  Arg.parse [
    "--target", Arg.Symbol (["headless"; "web"], fun x -> target := if x = "headless" then Headless else Web), "target";
    "--scenario", Arg.Set_string scenario, "scenario"; "--profile", Arg.Set_string profile, "profile";
    "--width", Arg.Set_int width, "logical width"; "--height", Arg.Set_int height, "logical height";
    "--warmup", Arg.Set_float warmup, "warmup seconds"; "--seconds", Arg.Set_float seconds, "measurement seconds" ]
    (fun value -> raise (Arg.Bad ("unexpected argument " ^ value))) "R10 runtime-next target benchmark";
  if !scenario = "" || !width <= 0 || !height <= 0 || !warmup <= 0.
     || !seconds <= 0. then
    invalid_arg "invalid arguments";
  let artifact = artifact !scenario !width !height in
  let work = artifact.draws in
  let candidate = match !scenario with
    |"basic"->Some(Result.get_ok(R10_scene2_candidate.create ~target:(match!target with Headless->`Headless|Web->`Web)~width:!width~height:!height Basic))
    |"canvas"->Some(Result.get_ok(R10_scene2_candidate.create ~target:(match!target with Headless->`Headless|Web->`Web)~width:!width~height:!height Canvas))
    |"pxui"->Some(Result.get_ok(R10_scene2_candidate.create ~target:(match!target with Headless->`Headless|Web->`Web)~width:!width~height:!height Pxui))
    |_->None in
  let sampled_scene3 =
    List.map
      (fun draw ->
        ( Scene_execution.Scene3,
          Ogpu.Pipeline.Replace,
          None,
          None,
          4,
          draw ))
      work
  in
  let render, capture, destroy = match candidate with
    |Some candidate->(fun()->R10_scene2_candidate.render candidate~width:!width~height:!height;Ok true),
      (fun()->Ok(R10_scene2_candidate.capture candidate)),
      (fun()->Ok(R10_scene2_candidate.destroy candidate))
    |None->match !target with
    | Headless ->
        let runtime = ok (Runtime_next_headless.create ~logical_width:!width ~logical_height:!height
          ~drawable_width:!width ~drawable_height:!height) in
        (if !scenario = "scene3" then
           fun () ->
             Runtime_next_headless.render_sampled_resources runtime sampled_scene3
         else fun () -> Runtime_next_headless.render runtime work),
        (fun () -> Runtime_next_headless.read_pixels runtime ~bytes_per_row:(!width * 4)),
        (fun () -> Runtime_next_headless.destroy runtime)
    | Web ->
        let config = { Wap.default_config with interface = "127.0.0.1"; port = 0 } in
        let runtime = ok (Runtime_next_web.create ~wap_config:config ~logical_width:!width
          ~logical_height:!height ~drawable_width:!width ~drawable_height:!height ()) in
        (if !scenario = "scene3" then
           fun () ->
             Runtime_next_web.render_sampled_resources runtime sampled_scene3
         else fun () -> Runtime_next_web.render runtime work),
        (fun () -> Runtime_next_web.read_pixels runtime ~bytes_per_row:(!width * 4)),
        (fun () -> Runtime_next_web.destroy runtime) in
  let run_for duration collect =
    let now = monotonic_seconds in
    let smoke = collect && duration <= 0.1 in
    let minimum = if smoke then 3 else if collect then 1 else 5 in
    let capacity = ref 256 and values = ref (Array.make 256 0.)
    and count = ref 0 in
    let append value =
      if !count = !capacity then begin
        let next = Array.make (!capacity * 2) 0. in
        Array.blit !values 0 next 0 !count; values := next;
        capacity := !capacity * 2
      end;
      (!values).(!count) <- value; incr count
    in
    let epoch = now () and previous = ref (now ()) in
    let continue () =
      if smoke then !count < 3
      else !count < minimum || now () -. epoch < duration in
    while continue () do
      ignore (ok (render ()));
      let completed = now () in
      if collect then append (completed -. !previous) else incr count;
      previous:=completed
    done;
    (if collect then Array.sub !values 0 !count else [||]), now () -. epoch, !count in
  let _,warmup_wall,warmup_frames=run_for !warmup false in Gc.full_major ();
  let rss0 = rss_kib () in
  let gc0 = Gc.quick_stat () and allocated0 = Gc.allocated_bytes ()
  and cpu0 = Unix.times () in
  let frames,wall,_ = run_for !seconds true in
  let cpu1 = Unix.times () and gc1 = Gc.quick_stat () in
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
    "warmup_frames",`Int warmup_frames;"warmup_elapsed_seconds",`Float warmup_wall;
    "scheduling", `String (if !seconds <= 0.1 then "fixed-count" else "duration-bounded");
    "scheduled_frame_rate", `Null;
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
    "semantics_supported", `Bool true;
    "pixel_authority", `String(Printf.sprintf"phase0/%s/%s"
      (match!target with Headless->"headless"|Web->"web")!scenario);
    "pixel_tolerance", `Int 3;
    "work_units", `Int artifact.work_units;
    "framebuffer_digest", `String (Digest.to_hex (Digest.bytes framebuffer));
    "median_frame_seconds", `Float (percentile 0.5 frames);
    "p95_frame_seconds", `Float (percentile 0.95 frames);
    "p99_frame_seconds", `Float (percentile 0.99 frames);
    "upload_bytes_during_measurement", `Null; "draw_count", `Int draws;
    "pass_count", `Int count; "backend_calls", `Int count;
    "native_gpu_counters", `Null; "thermal_state", `Null; "power_state", `Null] in
  print_endline (Yojson.Safe.to_string json)
