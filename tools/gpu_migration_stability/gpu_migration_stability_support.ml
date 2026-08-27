type config = { minutes : float; frames : int option; sample_every : int; sample_period_seconds : float; report : string option }

let get = function Ok value -> value | Error _ -> failwith "stability harness operation failed"

let rss_kib () =
  let command = Printf.sprintf "ps -o rss= -p %d" (Unix.getpid ()) in
  let input = Unix.open_process_in command in
  let line = try input_line input with End_of_file -> "0" in
  ignore (Unix.close_process_in input);
  try int_of_string (String.trim line) with Failure _ -> 0

let configuration width height : Ogpu.Surface.configuration =
  { logical_width = width; logical_height = height; physical_width = width;
    physical_height = height; format = Rgba8_unorm; present_mode = Fifo;
    max_acquired = 2 }

let ir frame =
  let x = float_of_int (frame mod 23) in
  let geometry : Raster2.Render_ir.geometry =
    { vertices = [| x; 2.; x +. 12.; 3.; x +. 4.; 15. |];
      indices = [| 0; 1; 2 |]; color = 0x44AAEEFFl }
  in
  get (Raster2.Render_ir.create [| Clear 0x102030FFl; Geometry geometry |])

let mesh frame : Scene_execution.mesh =
  let vertices = Bytes.make 48 '\000' in
  Bytes.set_uint8 vertices 0 (frame land 255);
  { key = Printf.sprintf "mesh-%d" (frame mod 17); vertices; vertex_count = 3;
    indices = Bytes.make 12 '\000'; index_count = 3 }

let run config =
  if not (Float.is_finite config.minutes) || config.minutes < 0. then invalid_arg "--minutes must be finite and nonnegative";
  if config.sample_every <= 0 then invalid_arg "--sample-every must be positive";
  let driver, control = Ogpu.Backend_mock.create () in
  let width = ref 64 and height = ref 48 in
  let scene = get (Scene_execution.create driver (configuration !width !height)) in
  let offscreen = ref (get (Raster2.Offscreen.create ~depth:true ~width:!width ~height:!height ())) in
  let cache = get (Raster2.Resource_cache.create ~capacity:8 ~on_destroy:(fun _ _ _ -> ())) in
  let wap_config = { Wap.default_config with interface = "127.0.0.1"; port = 0;
    max_frame_pool_bytes = 2 * 1024 * 1024 } in
  let presenter = get (Runtime_wap_raster2_presenter.Wap_raster2_presenter.create ~config:wap_config ()) in
  let started = Unix.gettimeofday () and frame = ref 0 and generation = ref 0L in
  let sample_capacity = 256 in
  let samples = Array.make sample_capacity None and sample_count = ref 0 in
  let first_sample = ref None and rss_min = ref max_int and rss_max = ref 0 in
  let rolling = ref 0L and last_sample = ref (Unix.gettimeofday () -. 1.) in
  let should_continue () = match config.frames with
    | Some limit -> !frame < limit
    | None -> Unix.gettimeofday () -. started < config.minutes *. 60.
  in
  while should_continue () do
    incr frame;
    if !frame mod 97 = 0 then begin
      width := 48 + (!frame / 97 mod 3) * 16;
      height := 40 + (!frame / 97 mod 2) * 8;
      get (Raster2.Offscreen.resize !offscreen ~width:!width ~height:!height);
      get (Scene_execution.resize scene (configuration !width !height))
    end;
    if !frame mod 31 = 0 then begin
      generation := Int64.succ !generation;
      Raster2.Resource_cache.invalidate_image cache ~id:1L;
      get (Raster2.Resource_cache.insert cache (Image { id = 1L; generation = !generation }) !frame)
    end;
    if !frame mod 53 = 0 then begin
      let transient = get (Raster2.Offscreen.create ~width:8 ~height:8 ()) in
      get (Raster2.Offscreen.destroy transient)
    end;
    let view = get (Raster2.Offscreen.view !offscreen) in
    get (Raster2.Offscreen.render view ~lookup:(fun _ -> None) (ir !frame));
    let capture = get (Raster2.Offscreen.capture view) in
    get (Raster2.Offscreen.release_view view);
    let state : Scene_execution.state = { viewport = (0, 0, !width, !height); scissor = (0, 0, !width, !height) } in
    ignore (get (Scene_execution.render scene [ { mesh = mesh !frame; state } ]));
    get (Runtime_wap_raster2_presenter.Wap_raster2_presenter.present presenter
      { rgba = capture.pixels; pitch = capture.pitch; logical_width = !width;
        logical_height = !height; drawable_width = capture.width; drawable_height = capture.height });
    rolling := Int64.logxor (Int64.mul !rolling 1099511628211L) (Raster2.Render_ir.hash (ir !frame));
    if !frame mod config.sample_every = 0 then begin
      Ogpu.Backend_mock.clear_trace control;
      let now = Unix.gettimeofday () in
      if now -. !last_sample >= config.sample_period_seconds then begin
        last_sample := now;
        let gc = Gc.quick_stat () and counters = Raster2.Offscreen.counters () in
        let sample = `Assoc [ "frame", `Int !frame; "elapsed_seconds", `Float (now -. started);
          "rss_kib", `Int (rss_kib ()); "heap_words", `Int gc.heap_words;
          "live_targets", `Int counters.targets; "live_views", `Int counters.views;
          "cache_entries", `Int (Raster2.Resource_cache.length cache) ] in
        let rss = match sample with `Assoc fields -> (match List.assoc "rss_kib" fields with `Int value -> value | _ -> assert false) | _ -> assert false in
        if !first_sample = None then first_sample := Some sample;
        rss_min := min !rss_min rss; rss_max := max !rss_max rss;
        samples.(!sample_count mod sample_capacity) <- Some sample;
        incr sample_count
      end
    end
  done;
  let wap_stats = Runtime_wap_raster2_presenter.Wap_raster2_presenter.stats presenter in
  let scene_upload_bytes = Scene_execution.upload_bytes scene in
  Runtime_wap_raster2_presenter.Wap_raster2_presenter.destroy presenter;
  Raster2.Resource_cache.clear cache;
  get (Raster2.Offscreen.destroy !offscreen);
  get (Scene_execution.destroy scene);
  let live = Ogpu.Backend_mock.live_counts control in
  if live <> (0, 0, 0, 0, 0) then failwith "scene execution leaked backend objects";
  let counters = Raster2.Offscreen.counters () in
  if counters.targets <> 0 || counters.views <> 0 then failwith "offscreen objects leaked";
  let retained =
    let length = min !sample_count sample_capacity in
    let start = if !sample_count <= sample_capacity then 0 else !sample_count mod sample_capacity in
    List.init length (fun offset -> match samples.((start + offset) mod sample_capacity) with Some sample -> sample | None -> assert false)
  in
  let json = `Assoc [ "schema", `Int 1; "frames", `Int !frame;
    "deterministic_hash", `String (Printf.sprintf "%016Lx" !rolling);
    "image_generation", `String (Int64.to_string !generation);
    "scene_upload_bytes", `String (Int64.to_string scene_upload_bytes);
    "wap_frames_submitted", `Int wap_stats.frames_submitted;
    "sample_observations", `Int !sample_count; "sample_capacity", `Int sample_capacity;
    "first_sample", (match !first_sample with Some sample -> sample | None -> `Null);
    "rss_min_kib", `Int (if !rss_min = max_int then 0 else !rss_min); "rss_max_kib", `Int !rss_max;
    "samples", `List retained; "final_live_targets", `Int counters.targets;
    "final_live_views", `Int counters.views ] in
  let output = Yojson.Safe.pretty_to_string json ^ "\n" in
  (match config.report with None -> print_string output | Some path -> let channel = open_out_bin path in output_string channel output; close_out channel);
  json
