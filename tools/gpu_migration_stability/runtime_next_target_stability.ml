type target = Headless | Web

type observation = {
  frame : int;
  rss_kib : int;
  heap_words : int;
  font_entries : int;
  backend_trace : int;
  backend_dropped : int;
  wap_submitted : int option;
}

type runtime = {
  render : Scene_execution.draw list -> (bool, Ogpu.Error.t) result;
  resize : logical_width:int -> logical_height:int -> drawable_width:int ->
    drawable_height:int -> (unit, Ogpu.Error.t) result;
  counts : unit -> int * int * int * int * int;
  trace : unit -> int * int;
  wap_stats : unit -> Wap.stats option;
  destroy : unit -> (unit, Ogpu.Error.t) result;
}

let target = ref Headless
let minutes = ref 0.1
let frames = ref None
let sample_every = ref 600
let report = ref None
let set_frames value = frames := Some value

let ok = function Ok value -> value | Error error ->
  failwith (Ogpu.Error.to_string error)

let mixer_ok = function Ok value -> value | Error error ->
  failwith (Format.asprintf "%a" Sdl3_mixer.pp_error error)

let resident_kib () =
  let argv = [| "/bin/ps"; "-o"; "rss="; "-p"; string_of_int (Unix.getpid ()) |] in
  try
    let channel = Unix.open_process_args_in argv.(0) argv in
    Fun.protect ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> input_line channel |> String.trim |> int_of_string)
  with End_of_file | Failure _ | Unix.Unix_error _ -> 0

let make_runtime = function
  | Headless ->
      let value = ok (Runtime_next_headless.create ~logical_width:16
        ~logical_height:16 ~drawable_width:16 ~drawable_height:16) in
      { render = Runtime_next_headless.render value;
        resize = Runtime_next_headless.resize value;
        counts = (fun () -> Runtime_next_headless.backend_live_counts value);
        trace = (fun () -> Runtime_next_headless.backend_trace_stats value);
        wap_stats = (fun () -> None);
        destroy = (fun () -> Runtime_next_headless.destroy value) }
  | Web ->
      let config = { Wap.default_config with interface = "127.0.0.1"; port = 0;
        max_events = 256; max_clients = 2; max_connections = 4;
        max_queued_event_bytes = 64 * 1024; max_frame_pool_bytes = 256 * 1024 } in
      let value = ok (Runtime_next_web.create ~wap_config:config
        ~logical_width:16 ~logical_height:16 ~drawable_width:16
        ~drawable_height:16 ()) in
      { render = Runtime_next_web.render value;
        resize = Runtime_next_web.resize value;
        counts = (fun () -> Runtime_next_web.backend_live_counts value);
        trace = (fun () -> Runtime_next_web.backend_trace_stats value);
        wap_stats = (fun () -> Some (Runtime_next_web.stats value));
        destroy = (fun () -> Runtime_next_web.destroy value) }

let put_vertex bytes index x y =
  Bytes.set_int64_le bytes (index * 16) (Int64.bits_of_float x);
  Bytes.set_int64_le bytes (index * 16 + 8) (Int64.bits_of_float y)

let draw key extent =
  let vertices = Bytes.make 48 '\000' in
  put_vertex vertices 0 0. 0.; put_vertex vertices 1 (float extent) 0.;
  put_vertex vertices 2 0. (float extent);
  let indices = Bytes.make 12 '\000' in
  Bytes.set_int32_le indices 4 1l; Bytes.set_int32_le indices 8 2l;
  { Scene_execution.mesh = { key; vertices; vertex_count = 3; indices;
      index_count = 3 };
    state = { viewport = (0, 0, extent, extent);
      scissor = (0, 0, extent, extent) } }

let sample_to_json value = `Assoc [
  "frame", `Int value.frame; "rss_kib", `Int value.rss_kib;
  "heap_words", `Int value.heap_words; "font_entries", `Int value.font_entries;
  "backend_trace", `Int value.backend_trace;
  "backend_dropped", `Int value.backend_dropped;
  "wap_submitted", (match value.wap_submitted with None -> `Null | Some n -> `Int n) ]

let () =
  Arg.parse [
    "--target", Arg.Symbol (["headless"; "web"], fun value ->
      target := if value = "headless" then Headless else Web), "target";
    "--minutes", Arg.Set_float minutes, "wall-clock run duration";
    "--frames", Arg.Int set_frames, "deterministic frame limit";
    "--sample-every", Arg.Set_int sample_every, "frame sampling interval";
    "--report", Arg.String (fun value -> report := Some value), "JSON report" ]
    (fun value -> raise (Arg.Bad ("unexpected argument: " ^ value)))
    "runtime_next_target_stability";
  if !minutes <= 0. || !sample_every <= 0 then invalid_arg "positive duration/sample required";
  let runtime = make_runtime !target in
  mixer_ok (Sdl3_mixer.Init.init ());
  let memory = mixer_ok (Sdl3_mixer.Mixer.create_memory ~sample_rate:8_000 ~channels:1) in
  let device = mixer_ok (Sdl3_mixer.Mixer.create_device ()) in
  let image = ref (Raster2.Surface.create ~width:2 ~height:2 () |> Result.get_ok) in
  let image_generation = ref 1 and failed_reloads = ref 0 in
  let font = Hashtbl.create 256 in
  let observations = Array.make 256 None and observation_count = ref 0 in
  let min_rss = ref max_int and max_rss = ref 0 and max_font = ref 0 in
  let started = Unix.gettimeofday () and frame = ref 0 and hash = ref 0L in
  let continue () = match !frames with
    | Some limit -> !frame < limit
    | None -> Unix.gettimeofday () -. started < !minutes *. 60. in
  Fun.protect ~finally:(fun () ->
    ignore (Sdl3_mixer.Mixer.stop_all device ());
    ignore (Sdl3_mixer.Mixer.destroy device);
    ignore (Sdl3_mixer.Mixer.destroy memory);
    ignore (Sdl3_mixer.Init.quit ());
    ok (runtime.destroy ())) (fun () ->
    while continue () do
      incr frame;
      if !frame mod 997 = 0 then begin
        let next = Raster2.Surface.create ~width:(2 + (!frame land 1)) ~height:2 ()
          |> Result.get_ok in
        image := next; incr image_generation
      end else if !frame mod 991 = 0 then incr failed_reloads;
      let density = 1 + ((!frame / 4096) land 1) in
      Hashtbl.replace font (density, Printf.sprintf "label-%03d" (!frame mod 300)) !frame;
      if Hashtbl.length font > 256 then Hashtbl.clear font;
      max_font := max !max_font (Hashtbl.length font);
      let canvas = Raster2.Surface.create ~width:4 ~height:4 () |> Result.get_ok in
      Raster2.Surface.clear canvas (if !frame land 1 = 0 then 0x112233ffl else 0x223344ffl);
      ignore (Raster2.Composite.blit ~src:!image
        ~src_rect:{x=0;y=0;width=Raster2.Surface.width !image;
          height=Raster2.Surface.height !image} ~dst:canvas ~dst_x:1 ~dst_y:1
        ~blend:Raster2.Composite.Source_over |> Result.get_ok);
      if !frame mod 2048 = 0 then begin
        let extent = if (!frame / 2048) land 1 = 0 then 16 else 20 in
        ok (runtime.resize ~logical_width:extent ~logical_height:extent
          ~drawable_width:extent ~drawable_height:extent)
      end;
      let extent = if (!frame / 2048) land 1 = 0 then 16 else 20 in
      ignore (ok (runtime.render [draw ("stable-" ^ string_of_int (!frame land 3)) extent]));
      ignore (mixer_ok (Sdl3_mixer.Mixer.generate memory ~frames:8));
      hash := Int64.logxor (Int64.mul !hash 0x100000001b3L) (Int64.of_int !frame);
      if !frame mod !sample_every = 0 then begin
        let rss = resident_kib () and heap = (Gc.quick_stat ()).heap_words in
        min_rss := min !min_rss rss; max_rss := max !max_rss rss;
        let retained, dropped = runtime.trace () in
        let wap_submitted = Option.map (fun (stats : Wap.stats) -> stats.frames_submitted)
          (runtime.wap_stats ()) in
        let value = { frame = !frame; rss_kib = rss; heap_words = heap;
          font_entries = Hashtbl.length font; backend_trace = retained;
          backend_dropped = dropped; wap_submitted } in
        observations.(!observation_count mod 256) <- Some value;
        incr observation_count
      end
    done;
    let live_before = runtime.counts () in
    mixer_ok (Sdl3_mixer.Mixer.stop_all device ());
    mixer_ok (Sdl3_mixer.Mixer.destroy device);
    mixer_ok (Sdl3_mixer.Mixer.destroy memory);
    mixer_ok (Sdl3_mixer.Init.quit ());
    ok (runtime.destroy ());
    let live_after = runtime.counts () in
    let samples = Array.to_list observations |> List.filter_map Fun.id
      |> List.sort (fun left right -> Int.compare left.frame right.frame) in
    let output = `Assoc [
      "schema", `Int 1;
      "target", `String (match !target with Headless -> "headless" | Web -> "web");
      "profile", `String "release"; "frames", `Int !frame;
      "wall_seconds", `Float (Unix.gettimeofday () -. started);
      "hash", `String (Printf.sprintf "%016Lx" !hash);
      "image_generation", `Int !image_generation;
      "failed_reloads", `Int !failed_reloads;
      "font_capacity", `Int 256; "max_font_entries", `Int !max_font;
      "observations", `Int !observation_count;
      "retained_observations", `Int (List.length samples);
      "rss_min_kib", `Int (if !min_rss = max_int then resident_kib () else !min_rss);
      "rss_max_kib", `Int !max_rss;
      "live_before_teardown", `List (let a,b,c,d,e = live_before in
        List.map (fun n -> `Int n) [a;b;c;d;e]);
      "live_after_teardown", `List (let a,b,c,d,e = live_after in
        List.map (fun n -> `Int n) [a;b;c;d;e]);
      "samples", `List (List.map sample_to_json samples) ] in
    match !report with
    | None -> print_endline (Yojson.Safe.pretty_to_string output)
    | Some path ->
        let channel = open_out_bin path in
        Fun.protect ~finally:(fun () -> close_out channel)
          (fun () -> Yojson.Safe.pretty_to_channel channel output; output_char channel '\n'))
