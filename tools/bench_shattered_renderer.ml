open Prismel
open Procedural

type ui_mode = Visible | Hidden
type preview = Pieces of Sketch_support.Packed_pieces.t | Mesh of Mesh.t

type gc_snapshot = {
  allocated_bytes : float;
  minor_words : float;
  promoted_words : float;
  major_words : float;
  major_collections : int;
  heap_words : int;
  top_heap_words : int;
}

type result = {
  frames : int;
  wall_seconds : float;
  user_seconds : float;
  system_seconds : float;
  allocated_bytes : float;
  minor_bytes : float;
  promoted_bytes : float;
  major_bytes : float;
  major_collections : int;
  ending_heap_bytes : int;
  peak_heap_bytes : int;
  starting_rss_kib : int option;
  ending_rss_kib : int option;
  peak_sampled_rss_kib : int option;
  median_frame_seconds : float;
  p95_frame_seconds : float;
  p99_frame_seconds : float;
}

module Allocation_profile = struct
  let enabled = Sys.getenv_opt "PRISMEL_RENDERER_MEMPROF" = Some "1"
  let sampling_rate = 1e-4
  let samples : (string, int) Hashtbl.t = Hashtbl.create 128
  let lock = Mutex.create ()
  let profile = ref None

  let name allocation =
    match Printexc.backtrace_slots allocation.Gc.Memprof.callstack with
    | None -> "unknown"
    | Some slots ->
        Array.to_list slots
        |> List.filter_map Printexc.Slot.name
        |> List.find_opt (fun name ->
          not (String.starts_with ~prefix:"camlGc__Memprof" name))
        |> Option.value ~default:"unknown"

  let record allocation =
    let name = name allocation in
    Mutex.lock lock;
    Hashtbl.replace samples name
      (allocation.Gc.Memprof.n_samples
       + Option.value (Hashtbl.find_opt samples name) ~default:0);
    Mutex.unlock lock;
    None

  let start () = if enabled && Option.is_none !profile then
    profile := Some (Gc.Memprof.start ~sampling_rate ~callstack_size:24 {
      Gc.Memprof.null_tracker with alloc_minor = record; alloc_major = record })

  let stop () = match !profile with
    | None -> ()
    | Some value ->
        Gc.Memprof.stop ();
        Gc.Memprof.discard value;
        profile := None;
        let entries = Hashtbl.fold (fun name count values ->
          (count, name) :: values) samples []
          |> List.sort (fun (left, _) (right, _) -> Int.compare right left) in
        List.iteri (fun index (count, name) -> if index < 20 then
          Printf.eprintf "memprof %.1f MiB %s\n%!"
            (float_of_int count /. sampling_rate
             *. float_of_int (Sys.word_size / 8) /. 1_048_576.) name) entries
end

module Phase_profile = struct
  let enabled = Sys.getenv_opt "PRISMEL_RENDERER_PHASE_PROFILE" = Some "1"
  let calls = ref 0
  let bytes = ref 0.

  let measure operation =
    if not enabled then operation () else
    let before = Gc.allocated_bytes () in
    let result = operation () in
    bytes := !bytes +. Gc.allocated_bytes () -. before;
    incr calls;
    result

  let report () = if enabled && !calls > 0 then
    Printf.eprintf "phase-profile view %.1f B/call (%d calls)\n%!"
      (!bytes /. float_of_int !calls) !calls
end

type model = {
  environment : preview Sketch_ui.Environment3.t;
  launched_at : float;
  hidden_toggled : bool;
  ready_at : float option;
  measuring : bool;
  started_at : float;
  started_times : Unix.process_times option;
  started_gc : gc_snapshot option;
  started_rss_kib : int option;
  sampled_peak_rss_kib : int option;
  next_rss_sample_at : float;
  last_frame_at : float;
  frame_times : float array;
  frame_count : int;
  result : result option;
  pieces : int option;
  triangles : int option;
  render_vertices : int option;
  drawable_width : int;
  drawable_height : int;
  pixel_scale_x : float;
  pixel_scale_y : float;
}

let integer_environment name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let float_environment name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value ->
      let value = float_of_string value in
      if not (Float.is_finite value) || value <= 0. then
        invalid_arg (name ^ " must be finite and positive");
      value

let ui_mode =
  if Array.length Sys.argv <> 2 then
    invalid_arg "bench_shattered_renderer: expected visible or hidden";
  match String.lowercase_ascii Sys.argv.(1) with
  | "visible" -> Visible
  | "hidden" -> Hidden
  | value -> invalid_arg ("bench_shattered_renderer: unknown mode " ^ value)

let ui_mode_name = function Visible -> "visible" | Hidden -> "hidden"
let domains = integer_environment "PRISMEL_SHATTER_DOMAINS" 1
let grain = integer_environment "PRISMEL_SHATTER_GRAIN" 2
let warmup_seconds = float_environment "PRISMEL_RENDERER_BENCH_WARMUP" 3.
let measure_seconds = float_environment "PRISMEL_RENDERER_BENCH_SECONDS" 30.
let cook_timeout_seconds = float_environment "PRISMEL_SHATTER_COOK_TIMEOUT" 180.

let result_exn = function
  | Ok value -> value
  | Error message -> failwith message

let gc_snapshot () =
  let quick = Gc.quick_stat () in
  {
    allocated_bytes = Gc.allocated_bytes ();
    minor_words = quick.minor_words;
    promoted_words = quick.promoted_words;
    major_words = quick.major_words;
    major_collections = quick.major_collections;
    heap_words = quick.heap_words;
    top_heap_words = quick.top_heap_words;
  }

let bytes_of_words words = words *. float_of_int (Sys.word_size / 8)
let int_bytes_of_words words = words * (Sys.word_size / 8)

let resident_kib () =
  let arguments = [|"/bin/ps"; "-o"; "rss="; "-p";
    string_of_int (Unix.getpid ())|] in
  try
    let channel = Unix.open_process_args_in arguments.(0) arguments in
    Fun.protect ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () ->
        let value = input_line channel |> String.trim in
        if value = "" then None else Some (int_of_string value))
  with End_of_file | Failure _ | Unix.Unix_error _ -> None

let maximum_option left right = match left, right with
  | None, value | value, None -> value
  | Some left, Some right -> Some (max left right)

let percentile values length fraction =
  if length = 0 then 0.
  else begin
    let copy = Array.sub values 0 length in
    Array.sort Float.compare copy;
    let index = int_of_float (Float.ceil (fraction *. float_of_int length)) - 1
      |> max 0 |> min (length - 1) in
    copy.(index)
  end

let graph () =
  let cube = Sop_catalog.Box.create ~label:"cube"
      ~size:(Vec3.create 2.6 2.6 2.6) ~connectivity:Pdk.Ops.Box_quads
      ~consolidate_points:true ~normals:Pdk.Ops.Box_vertex_normals ()
  and dodecahedron = Sop_catalog.Platonic.create ~label:"dodecahedron"
      ~kind:Pdk.Ops.Platonic_dodecahedron
      ~normals:Pdk.Ops.Platonic_vertex_normals
      ~rotation:(Vec3.create 0.173 0.291 0.113) ~radius:2.25 () in
  let source = Sop_catalog.Switch.create ~label:"source-switch"
      [cube; dodecahedron] in
  let cutter_grid = Sop_catalog.Grid.create ~label:"cutter-grid"
      ~counts:Pdk.Ops.Grid_divisions ~connectivity:Pdk.Ops.Grid_triangles
      ~columns:2 ~rows:2 ~size:4.8 ()
    |> Sop_catalog.Mountain.create ~label:"cutter-mountain" ~seed:0
         ~height:0.35 ~frequency:(Vec3.create 0.27 1. 0.27)
         ~octaves:1 ~lacunarity:2. ~roughness:0.5
         ~recompute_normals:true
    |> Sop_catalog.Normal.create ~label:"cutter-normals"
         ~owner:Pdk.Attribute.Vertex ~cusp_angle:Float.pi in
  let cutter_points = Sop_catalog.Point_generate.origin
      ~label:"cutter-points" ~points:50 ()
    |> Sop_catalog.Attribute_noise_quaternion.create
         ~label:"orient-noise" ~seed:7349 ~owner:Pdk.Attribute.Point
         ~name:"orient" ~location:Pdk.Attribute_ops.Noise_element_number
         ~range:Pdk.Attribute_ops.Noise_zero_centered
         ~frequency:(Vec3.create 0.173 0.173 0.173) ~octaves:2
    |> Sop_catalog.Point_jitter.create ~label:"position-jitter" ~seed:7350
         ~id_attribute:"sourceindex" ~scale:0.45 in
  Sop_catalog.Copy_to_points.create ~label:"copy-cutters" ~source:cutter_grid
    ~targets:cutter_points ()
  |> fun cutters -> Sop_catalog.Boolean_fracture.create
       ~label:"boolean-fracture" ~resolve_cutter_self_intersections:true
       ~detriangulation:Pdk.Boolean.Triangles ~require_closed:true
       ~piece_attribute:"piece" ~cutters source
  |> Sop_catalog.Normal.create ~label:"fracture-normals"
       ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.65
  |> Sop_catalog.Exploded_view.create ~label:"exploded-view"

let material = Material.create ~diffuse:(Color.hex_exn "#f2b36d")
    ~ambient:(Color.hex_exn "#422006") ~specular:Color.white ~shininess:48. ()

let lights = [
  Light.directional ~direction:(Vec3.create (-1.) (-1.5) (-2.))
    ~diffuse:(Color.hex_exn "#fff7ed") ~ambient:(Color.hex_exn "#1c1917") ();
  Light.directional ~direction:(Vec3.create 1.2 0.4 (-0.8))
    ~diffuse:(Color.hex_exn "#7dd3fc") ~intensity:0.55 ();
]

let prepare output =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive "piece"
      output.Session.geometry with
  | Some attribute ->
      (match Pdk.Attribute.Private.storage attribute with
       | Pdk.Attribute.Int _ | Text _ ->
           Sketch_support.Packed_pieces.of_geometry ~piece_attribute:"piece"
             output.geometry
           |> Result.map (fun pieces -> Pieces pieces)
       | _ -> Bridge.to_mesh output.geometry
           |> Result.map (fun mesh -> Mesh mesh)
           |> Result.map_error Pdk.Error.to_string)
  | None -> Bridge.to_mesh output.geometry
      |> Result.map (fun mesh -> Mesh mesh)
      |> Result.map_error Pdk.Error.to_string

let scene3 node preview =
  let mesh = match preview with
    | Pieces pieces -> Sketch_support.Packed_pieces.mesh_for_node node pieces
    | Mesh mesh -> mesh in
  let primitive_mode = Mesh.mode mesh in
  let shading = match Node.operation node with
    | "box" | "grid" | "platonic" -> Scene3.Flat
    | _ -> Scene3.Smooth in
  let preview_material = match primitive_mode with
    | Mesh.Points | Lines | Line_strip | Line_loop ->
        Material.unlit (Color.hex_exn "#fbbf74")
    | Triangles | Triangle_strip | Triangle_fan -> material in
  let cull = match preview, primitive_mode with
    | Pieces _, (Mesh.Triangles | Triangle_strip | Triangle_fan) ->
        Scene3.Cull_back
    | _ -> Scene3.Cull_none in
  let drawing = Scene3.mesh ~cull ~shading
      ~material:preview_material mesh in
  let drawing = match primitive_mode with
    | Mesh.Points ->
        Scene3.with_raster (Scene3.raster_state ~point_size:11. ()) [drawing]
    | Lines | Line_strip | Line_loop ->
        Scene3.with_raster (Scene3.raster_state ~line_width:2. ()) [drawing]
    | Triangles | Triangle_strip | Triangle_fan -> drawing in
  Scene3.create ~samples:1 ~lights [drawing]

let overlay graph preview frame =
  let pieces = match preview with
    | None -> "waiting for first cook"
    | Some (Pieces pieces) -> Printf.sprintf "%d closed pieces"
        (Sketch_support.Packed_pieces.piece_count pieces)
    | Some (Mesh mesh) -> Printf.sprintf "%d preview vertices"
        (Mesh.vertex_count mesh) in
  Scene.[
    text ~at:(20, 18) "SOP Shattered Cube";
    text ~at:(20, 43) (Printf.sprintf "%d nodes · %s"
      (List.length (Graph.inspect graph)) pieces);
    text ~at:(20, frame.Frame.height - 82)
      "Select source-switch for Cube / Dodecahedron · VIEW displays any SOP";
  ]

let cardinality environment =
  match Sketch_ui.Environment3.prepared environment with
  | None -> None
  | Some (Mesh _) -> failwith "shattered-cube fixture lost its piece attribute"
  | Some (Pieces pieces) ->
      let mesh = Sketch_support.Packed_pieces.mesh_for_node
          (Sketch_ui.Environment3.displayed_node environment) pieces in
      let piece_count = Sketch_support.Packed_pieces.piece_count pieces
      and triangles = Mesh.Private.triangle_count mesh
      and render_vertices = Mesh.vertex_count mesh in
      if piece_count <> 18_278 || triangles <> 278_368
          || render_vertices <> 835_104 then
        failwith (Printf.sprintf
          "shattered-cube cardinality changed: pieces=%d triangles=%d render_vertices=%d"
          piece_count triangles render_vertices);
      Some (piece_count, triangles, render_vertices)

let init frame =
  let environment = Sketch_ui.Environment3.create
      ~camera:(Easy_camera.create ~target:Vec3.zero ~distance:6.8
        ~azimuth:0.72 ~elevation:0.42 ())
      ~seed:7349L ~grain ~domains ~max_entries:24
      ~max_payload_bytes:(256 * 1024 * 1024)
      ~factories:Sop_catalog.Editor.factories ~graph:(graph ()) ~prepare
      ~scene3 ~overlay () |> result_exn in
  let now = Unix.gettimeofday () in
  {
    environment;
    launched_at = now;
    hidden_toggled = false;
    ready_at = None;
    measuring = false;
    started_at = 0.;
    started_times = None;
    started_gc = None;
    started_rss_kib = None;
    sampled_peak_rss_kib = None;
    next_rss_sample_at = 0.;
    last_frame_at = now;
    frame_times = Array.make 16_384 0.;
    frame_count = 0;
    result = None;
    pieces = None;
    triangles = None;
    render_vertices = None;
    drawable_width = frame.Frame.drawable_width;
    drawable_height = frame.drawable_height;
    pixel_scale_x = fst frame.pixel_scale;
    pixel_scale_y = snd frame.pixel_scale;
  }

let finish model now =
  Allocation_profile.stop ();
  let started_gc = Option.get model.started_gc
  and started_times = Option.get model.started_times in
  let ending_gc = gc_snapshot () and ending_times = Unix.times () in
  let ending_rss_kib = resident_kib () in
  let result = {
    frames = model.frame_count;
    wall_seconds = now -. model.started_at;
    user_seconds = ending_times.tms_utime -. started_times.tms_utime;
    system_seconds = ending_times.tms_stime -. started_times.tms_stime;
    allocated_bytes = ending_gc.allocated_bytes -. started_gc.allocated_bytes;
    minor_bytes = bytes_of_words (ending_gc.minor_words -. started_gc.minor_words);
    promoted_bytes = bytes_of_words
        (ending_gc.promoted_words -. started_gc.promoted_words);
    major_bytes = bytes_of_words (ending_gc.major_words -. started_gc.major_words);
    major_collections = ending_gc.major_collections - started_gc.major_collections;
    ending_heap_bytes = int_bytes_of_words ending_gc.heap_words;
    peak_heap_bytes = int_bytes_of_words ending_gc.top_heap_words;
    starting_rss_kib = model.started_rss_kib;
    ending_rss_kib;
    peak_sampled_rss_kib = maximum_option model.sampled_peak_rss_kib
        ending_rss_kib;
    median_frame_seconds = percentile model.frame_times model.frame_count 0.5;
    p95_frame_seconds = percentile model.frame_times model.frame_count 0.95;
    p99_frame_seconds = percentile model.frame_times model.frame_count 0.99;
  } in
  Sketch.quit ();
  { model with result = Some result }

let update model frame =
  let now = Unix.gettimeofday () in
  if Option.is_none model.ready_at
      && now -. model.launched_at > cook_timeout_seconds then
    failwith "shattered-cube benchmark cook timed out";
  let frame, hidden_toggled = match ui_mode, model.hidden_toggled with
    | Hidden, false ->
        { frame with Frame.events = Event.KeyPressed (Input.KeyChar 'h')
            :: frame.Frame.events }, true
    | (Visible, _ | Hidden, true) -> frame, model.hidden_toggled in
  let environment = Sketch_ui.Environment3.update model.environment frame in
  let model = { model with environment; hidden_toggled } in
  let model = match model.ready_at with
    | Some _ -> model
    | None ->
        (match cardinality environment with
         | None -> model
         | Some (pieces, triangles, render_vertices) ->
             { model with ready_at = Some now; pieces = Some pieces;
               triangles = Some triangles; render_vertices = Some render_vertices }) in
  match model.ready_at with
  | None -> model
  | Some ready_at when not model.measuring
      && now -. ready_at >= warmup_seconds ->
      Gc.full_major ();
      Allocation_profile.start ();
      let rss = resident_kib () in
      { model with measuring = true; started_at = now;
        started_times = Some (Unix.times ()); started_gc = Some (gc_snapshot ());
        started_rss_kib = rss; sampled_peak_rss_kib = rss;
        next_rss_sample_at = now +. 1.; last_frame_at = now; frame_count = 0 }
  | Some _ when model.measuring
      && now -. model.started_at >= measure_seconds -> finish model now
  | Some _ when model.measuring ->
      let frame_count = model.frame_count + 1 in
      if frame_count > Array.length model.frame_times then
        failwith "shattered renderer frame sample capacity exceeded";
      model.frame_times.(frame_count - 1) <- now -. model.last_frame_at;
      let sampled_peak_rss_kib, next_rss_sample_at =
        if now >= model.next_rss_sample_at then
          maximum_option model.sampled_peak_rss_kib (resident_kib ()), now +. 1.
        else model.sampled_peak_rss_kib, model.next_rss_sample_at in
      { model with frame_count; last_frame_at = now; sampled_peak_rss_kib;
        next_rss_sample_at }
  | Some _ -> model

let target_name () = "native"

let option_int_json = Option.fold ~none:"null" ~some:string_of_int

let print_result model result =
  Phase_profile.report ();
  let profile = Option.value ~default:"unknown"
      (Sys.getenv_opt "PRISMEL_BENCH_PROFILE") in
  Printf.printf
    "{\"schema\":1,\"benchmark\":\"shattered_renderer\",\"scenario\":\"shattered-%s\",\"target\":\"%s\",\"profile\":\"%s\",\"width\":1200,\"height\":760,\"drawable_width\":%d,\"drawable_height\":%d,\"pixel_scale\":[%.6f,%.6f],\"domains\":%d,\"grain\":%d,\"warmup_seconds\":%.6f,\"requested_measure_seconds\":%.6f,\"pieces\":%s,\"triangles\":%s,\"render_vertices\":%s,\"frames\":%d,\"wall_seconds\":%.9f,\"frames_per_second\":%.6f,\"median_frame_seconds\":%.9f,\"p95_frame_seconds\":%.9f,\"p99_frame_seconds\":%.9f,\"user_seconds\":%.9f,\"system_seconds\":%.9f,\"cpu_percent\":%.6f,\"allocated_bytes\":%.0f,\"minor_bytes\":%.0f,\"promoted_bytes\":%.0f,\"major_bytes\":%.0f,\"major_collections\":%d,\"ending_heap_bytes\":%d,\"peak_heap_bytes\":%d,\"starting_rss_kib\":%s,\"ending_rss_kib\":%s,\"peak_sampled_rss_kib\":%s,\"legacy_gpu_duration_seconds\":null,\"legacy_gpu_utilization_percent\":null,\"legacy_draw_count\":null,\"legacy_upload_bytes\":null}\n%!"
    (ui_mode_name ui_mode) (target_name ()) profile model.drawable_width
    model.drawable_height model.pixel_scale_x model.pixel_scale_y domains grain
    warmup_seconds measure_seconds (option_int_json model.pieces)
    (option_int_json model.triangles) (option_int_json model.render_vertices)
    result.frames result.wall_seconds
    (float_of_int result.frames /. result.wall_seconds)
    result.median_frame_seconds result.p95_frame_seconds result.p99_frame_seconds
    result.user_seconds result.system_seconds
    ((result.user_seconds +. result.system_seconds) /. result.wall_seconds *. 100.)
    result.allocated_bytes result.minor_bytes result.promoted_bytes
    result.major_bytes result.major_collections result.ending_heap_bytes
    result.peak_heap_bytes (option_int_json result.starting_rss_kib)
    (option_int_json result.ending_rss_kib)
    (option_int_json result.peak_sampled_rss_kib)

let () =
  let final = Sketch.run_state
      ~config:{ Sketch.default_config with width = 1200; height = 760;
        title = "Prismel shattered-cube renderer benchmark"; domains = Some domains;
        resizable = false }
      ~init ~update
      ~view:(fun model frame -> Phase_profile.measure (fun () ->
        Sketch_ui.Environment3.scene model.environment frame))
      ~on_stop:(fun model -> Sketch_ui.Environment3.close model.environment) () in
  match final.result with
  | None -> failwith "shattered renderer stopped before producing a result"
  | Some result -> print_result final result
