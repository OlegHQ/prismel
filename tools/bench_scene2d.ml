open Prismel

type model = {
  scene : Scene.t;
  started : float option;
  started_at : float;
  allocated_bytes : float;
  elapsed : float;
}

let profile = ref None
let samples : (string, int) Hashtbl.t = Hashtbl.create 64

let start_profile () =
  if Sys.getenv_opt "PRISMEL_RENDER_MEMPROF" = Some "1" then
    let record (allocation : Gc.Memprof.allocation) =
      let stack = Printexc.raw_backtrace_to_string allocation.callstack in
      Hashtbl.replace samples stack
        (allocation.n_samples + Option.value ~default:0
           (Hashtbl.find_opt samples stack));
      None
    in
    profile := Some (Gc.Memprof.start ~sampling_rate:0.01 ~callstack_size:10
      { Gc.Memprof.null_tracker with alloc_minor = record; alloc_major = record })

let stop_profile () =
  match !profile with
  | None -> ()
  | Some active ->
      Gc.Memprof.stop ();
      Gc.Memprof.discard active;
      Hashtbl.to_seq samples |> List.of_seq
      |> List.sort (fun (_, a) (_, b) -> Int.compare b a)
      |> List.to_seq |> Seq.take 12
      |> Seq.iter (fun (stack, count) ->
        Printf.eprintf "samples=%d\n%s\n%!" count stack)

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let measured_frames = integer_env "PRISMEL_RENDER_BENCH_FRAMES" 120
let size = integer_env "PRISMEL_RENDER_BENCH_SIZE" 128
let columns = integer_env "PRISMEL_2D_BENCH_COLUMNS" 16
let rows = integer_env "PRISMEL_2D_BENCH_ROWS" 16
let warmup_frames = 4

let scene () =
  let cell_width = max 1 (size / columns)
  and cell_height = max 1 (size / rows) in
  Scene.clear Color.black
  :: List.init (columns * rows) (fun index ->
       let column = index mod columns and row = index / columns in
       let x = column * cell_width and y = row * cell_height in
       let w = max 1 (cell_width - 1) and h = max 1 (cell_height - 1) in
       let color =
         Color.rgb ((column * 31) land 255) ((row * 47) land 255)
           ((index * 13) land 255)
       in
       match index land 3 with
       | 0 -> Scene.rect ~at:(x, y) ~w ~h ~fill:color ()
       | 1 ->
           Scene.circle ~at:(x + (w / 2), y + (h / 2))
             ~radius:(max 1 (min w h / 2)) ~fill:color ()
       | 2 ->
           Scene.ellipse ~at:(x + (w / 2), y + (h / 2))
             ~rx:(max 1 (w / 2)) ~ry:(max 1 (h / 3)) ~fill:color ()
       | _ ->
           Scene.rounded_rect ~at:(x, y) ~w ~h
             ~radius:(max 1 (min w h / 4)) ~fill:color ())

let update model (frame : Frame.t) =
  if frame.count = warmup_frames then begin
    Gc.full_major ();
    start_profile ();
    { model with
      started = Some (Gc.allocated_bytes ());
      started_at = Unix.gettimeofday ();
    }
  end else if frame.count = warmup_frames + measured_frames then begin
    let started = Option.get model.started in
    Sketch.quit ();
    stop_profile ();
    { model with
      allocated_bytes = Gc.allocated_bytes () -. started;
      elapsed = Unix.gettimeofday () -. model.started_at;
    }
  end else model

let () =
  if not (Sketch.is_headless ()) then
    failwith "bench_scene2d must run with HEADLESS=1";
  let final =
    Sketch.run_state
      ~config:{ Sketch.default_config with
        width = size;
        height = size;
        fps = None;
        clock = Sketch.Fixed (1. /. 60.);
      }
      ~init:(fun _ -> {
        scene = scene ();
        started = None;
        started_at = 0.;
        allocated_bytes = 0.;
        elapsed = 0.;
      })
      ~update ~view:(fun model _ -> model.scene) ()
  in
  let shapes = columns * rows in
  Printf.printf
    "benchmark,width,height,shapes,frames,total_seconds,seconds_per_frame,total_allocated_bytes,allocated_bytes_per_frame\n";
  Printf.printf "scene2d_primitives,%d,%d,%d,%d,%.6f,%.6f,%.0f,%.0f\n%!"
    size size shapes measured_frames final.elapsed
    (final.elapsed /. float_of_int measured_frames) final.allocated_bytes
    (final.allocated_bytes /. float_of_int measured_frames)
