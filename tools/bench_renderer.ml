open Prismel

type scenario = Basic | Pxui | Canvas | Scene3

type canvas_resources = {
  canvas : Canvas.t;
  mutable image : Image.t;
}

type resources =
  | Basic_resources of Image.t
  | Pxui_resources of Pxui.t
  | Canvas_resources of canvas_resources
  | Scene3_resources of Camera.t * Scene3.t

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

type model = {
  resources : resources;
  launched_at : float;
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

let width = integer_environment "PRISMEL_RENDERER_BENCH_WIDTH" 640
let height = integer_environment "PRISMEL_RENDERER_BENCH_HEIGHT" 480
let warmup_seconds = float_environment "PRISMEL_RENDERER_BENCH_WARMUP" 3.
let measure_seconds = float_environment "PRISMEL_RENDERER_BENCH_SECONDS" 30.
let domains = integer_environment "PRISMEL_BENCH_DOMAINS" 1

let scenario =
  if Array.length Sys.argv <> 2 then
    invalid_arg "bench_renderer: expected basic, pxui, canvas, or scene3";
  match String.lowercase_ascii Sys.argv.(1) with
  | "basic" -> Basic
  | "pxui" -> Pxui
  | "canvas" -> Canvas
  | "scene3" -> Scene3
  | value -> invalid_arg ("bench_renderer: unknown scenario " ^ value)

let scenario_name = function
  | Basic -> "basic"
  | Pxui -> "pxui"
  | Canvas -> "canvas"
  | Scene3 -> "scene3"

let target_name () = match Sketch.render_target () with
  | Sketch.Native -> "native"
  | Headless -> "headless"
  | Web -> "web"

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
    let index = int_of_float (Float.ceil (fraction *. float length)) - 1
      |> max 0 |> min (length - 1) in
    copy.(index)
  end

let make_image () =
  let canvas = Canvas.create_exn ~width:96 ~height:96 in
  Canvas.render canvas Scene.[
    clear (Color.hex_exn "#0f172a");
    rounded_rect ~at:(4, 4) ~w:88 ~h:88 ~radius:14
      ~fill:(Color.hex_exn "#155e75") ~stroke:(Color.hex_exn "#67e8f9") ();
    circle ~at:(48, 48) ~radius:30 ~fill:(Color.rgba 251 146 60 220) ();
    line ~from_:(18, 74) ~to_:(78, 22) ~width:5 ~color:Color.white ();
  ];
  let image = result_exn (Canvas.to_image canvas) in
  Canvas.destroy canvas;
  image

let pxui () =
  let ui = ref (Pxui.create ~x:348 ~y:16 ~width:276 ~row_height:29
      ~padding:8 ~max_height:448 ()) in
  for index = 0 to 3 do
    ui := Pxui.accordion ~name:("section-" ^ string_of_int index)
        ~label:("Section " ^ string_of_int (index + 1)) ~expanded:true
        (fun ui -> ui
          |> Pxui.toggle ~name:("toggle-" ^ string_of_int index)
               ~label:"Enabled" ~value:(index land 1 = 0)
          |> Pxui.slider ~name:("slider-" ^ string_of_int index)
               ~label:"Amount" ~min:(-1.) ~max:1.
               ~value:(float_of_int index /. 4.)
          |> Pxui.int_slider ~name:("steps-" ^ string_of_int index)
               ~label:"Steps" ~min:1 ~max:64 ~value:(8 + index)
          |> Pxui.choice ~name:("choice-" ^ string_of_int index)
               ~label:"Mode" ~options:["Solid"; "Wire"; "Points"]
               ~selected:(index mod 3))
        !ui
  done;
  !ui

let scene3 () =
  let mesh = Mesh.sphere ~segments:96 ~rings:48 ~radius:1. () in
  let material = Material.create ~diffuse:(Color.hex_exn "#38bdf8")
      ~ambient:(Color.hex_exn "#082f49") ~specular:Color.white
      ~shininess:42. () in
  let transforms = Array.init 12 (fun index ->
    let angle = float index /. 12. *. Math.two_pi in
    Mat4.mul
      (Mat4.translation (Vec3.create
        (Float.cos angle *. 1.9) (Float.sin angle *. 1.2) 0.))
      (Mat4.scaling (Vec3.create 0.38 0.38 0.38))) in
  let scene = Scene3.create ~samples:4 ~ambient:(Color.rgb 18 22 30)
      ~lights:[
        Light.directional ~direction:(Vec3.create (-0.6) (-1.) (-1.4))
          ~diffuse:Color.white ();
      ]
      [Scene3.instances_array ~material ~cull:Scene3.Cull_back mesh transforms]
  and camera = Camera.perspective ~at:(Vec3.create 0. 0. 5.4)
      ~target:Vec3.zero () in
  camera, scene

let make_resources = function
  | Basic -> Basic_resources (make_image ())
  | Pxui -> Pxui_resources (pxui ())
  | Canvas ->
      let canvas = Canvas.create_exn ~width ~height in
      Canvas.render canvas Scene.[clear Color.black];
      Canvas_resources { canvas; image = result_exn (Canvas.to_image canvas) }
  | Scene3 ->
      let camera, scene = scene3 () in
      Scene3_resources (camera, scene)

let destroy_resources = function
  | Basic_resources image -> Image.destroy image
  | Pxui_resources _ -> ()
  | Canvas_resources resources ->
      Image.destroy resources.image;
      Canvas.destroy resources.canvas
  | Scene3_resources _ -> ()

let update_canvas resources frame =
  let phase = frame.Frame.count mod 240 in
  Canvas.render resources.canvas Scene.[
    clear (Color.hex_exn "#07111f");
    rect ~at:(0, 0) ~w:width ~h:height ~fill:(Color.hex_exn "#0f172a") ();
    circle ~at:(40 + ((phase * 3) mod max 1 (width - 80)), height / 2)
      ~radius:34 ~fill:(Color.hex_exn "#22d3ee") ();
    translate (width / 2) (height / 2) [
      rotate (float phase *. 0.02) [
        rounded_rect ~at:(-90, -28) ~w:180 ~h:56 ~radius:14
          ~fill:(Color.rgba 244 63 94 210) ~stroke:Color.white ();
      ];
    ];
    debug_text ~at:(16, 16) "CANVAS BASELINE";
  ];
  let next = result_exn (Canvas.to_image resources.canvas) in
  Image.destroy resources.image;
  resources.image <- next

let init frame =
  let now = Unix.gettimeofday () in
  {
    resources = make_resources scenario;
    launched_at = now;
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
    drawable_width = frame.Frame.drawable_width;
    drawable_height = frame.drawable_height;
    pixel_scale_x = fst frame.pixel_scale;
    pixel_scale_y = snd frame.pixel_scale;
  }

let finish model now =
  let started_gc = Option.get model.started_gc
  and started_times = Option.get model.started_times in
  let ending_gc = gc_snapshot () and ending_times = Unix.times () in
  let ending_rss_kib = resident_kib () in
  let peak_sampled_rss_kib = maximum_option model.sampled_peak_rss_kib
      ending_rss_kib in
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
    peak_sampled_rss_kib;
    median_frame_seconds = percentile model.frame_times model.frame_count 0.5;
    p95_frame_seconds = percentile model.frame_times model.frame_count 0.95;
    p99_frame_seconds = percentile model.frame_times model.frame_count 0.99;
  } in
  Sketch.quit ();
  { model with result = Some result }

let update model (frame : Frame.t) =
  let now = Unix.gettimeofday () in
  if not model.measuring && now -. model.launched_at >= warmup_seconds then begin
    Gc.full_major ();
    let rss = resident_kib () in
    {
      model with
      measuring = true;
      started_at = now;
      started_times = Some (Unix.times ());
      started_gc = Some (gc_snapshot ());
      started_rss_kib = rss;
      sampled_peak_rss_kib = rss;
      next_rss_sample_at = now +. 1.;
      last_frame_at = now;
      frame_count = 0;
    }
  end else if model.measuring && now -. model.started_at >= measure_seconds then
    finish model now
  else begin
    (match model.resources with
     | Canvas_resources resources -> update_canvas resources frame
     | Basic_resources _ | Pxui_resources _ | Scene3_resources _ -> ());
    if not model.measuring then model
    else begin
      let frame_count = model.frame_count + 1 in
      if frame_count > Array.length model.frame_times then
        failwith "bench_renderer frame sample capacity exceeded";
      model.frame_times.(frame_count - 1) <- now -. model.last_frame_at;
      let sampled_peak_rss_kib, next_rss_sample_at =
        if now >= model.next_rss_sample_at then
          maximum_option model.sampled_peak_rss_kib (resident_kib ()), now +. 1.
        else model.sampled_peak_rss_kib, model.next_rss_sample_at
      in
      { model with frame_count; last_frame_at = now; sampled_peak_rss_kib;
        next_rss_sample_at }
    end
  end

let basic_scene texture frame = Scene.[
  clear (Color.hex_exn "#07111f");
  rounded_rect ~at:(18, 18) ~w:(width - 36) ~h:(height - 36) ~radius:18
    ~fill:(Color.hex_exn "#111827") ~stroke:(Color.hex_exn "#475569") ();
  circle ~at:(120, 150) ~radius:72 ~fill:(Color.hex_exn "#0891b2") ();
  rect ~at:(220, 74) ~w:180 ~h:120 ~fill:(Color.rgba 244 63 94 190) ();
  translate 338 292 [
    rotate (float frame.Frame.count *. 0.01) [
      polygon [-80, -42; 76, -54; 98, 36; 0, 74; -88, 34]
        ~fill:(Color.hex_exn "#a78bfa") ~stroke:Color.white ();
    ];
  ];
  image texture ~at:(470, 92) ~scale:1.15 ~angle:(-0.18) ~center:(48, 48) ();
  bezier [34, 404; 176, 320; 282, 474; 430, 382]
    ~steps:48 ~color:(Color.hex_exn "#fbbf24") ();
  text ~at:(32, 38) ~size:18 "Prismel renderer baseline";
  debug_text ~at:(472, 430) "FIXED 8x8";
]

let view model frame = match model.resources with
  | Basic_resources image -> basic_scene image frame
  | Pxui_resources ui ->
      Scene.[
        clear (Color.hex_exn "#07111f");
        text ~at:(24, 24) ~size:20 "PXUI render baseline";
        rounded_rect ~at:(18, 62) ~w:306 ~h:382 ~radius:12
          ~fill:(Color.hex_exn "#111827") ~stroke:(Color.hex_exn "#334155") ();
        circle ~at:(168, 236) ~radius:94 ~fill:(Color.hex_exn "#155e75") ();
        debug_text ~at:(88, 420) "GRAPH / INSPECTOR";
      ] @ Pxui.scene ui
  | Canvas_resources resources -> Scene.[
      clear Color.black;
      image resources.image ~at:(0, 0) ();
    ]
  | Scene3_resources (camera, scene) -> Scene.[
      clear (Color.hex_exn "#020617");
      view3d ~camera scene;
      text ~at:(22, 18) ~size:16 "Stable Scene3 instance baseline";
    ]

let print_result model result =
  let profile = Option.value ~default:"unknown"
      (Sys.getenv_opt "PRISMEL_BENCH_PROFILE") in
  Printf.printf
    "{\"schema\":1,\"benchmark\":\"renderer\",\"scenario\":\"%s\",\"target\":\"%s\",\"profile\":\"%s\",\"width\":%d,\"height\":%d,\"drawable_width\":%d,\"drawable_height\":%d,\"pixel_scale\":[%.6f,%.6f],\"domains\":%d,\"warmup_seconds\":%.6f,\"requested_measure_seconds\":%.6f,\"frames\":%d,\"wall_seconds\":%.9f,\"frames_per_second\":%.6f,\"median_frame_seconds\":%.9f,\"p95_frame_seconds\":%.9f,\"p99_frame_seconds\":%.9f,\"user_seconds\":%.9f,\"system_seconds\":%.9f,\"cpu_percent\":%.6f,\"allocated_bytes\":%.0f,\"minor_bytes\":%.0f,\"promoted_bytes\":%.0f,\"major_bytes\":%.0f,\"major_collections\":%d,\"ending_heap_bytes\":%d,\"peak_heap_bytes\":%d,\"starting_rss_kib\":%s,\"ending_rss_kib\":%s,\"peak_sampled_rss_kib\":%s,\"legacy_gpu_duration_seconds\":null,\"legacy_gpu_utilization_percent\":null,\"legacy_draw_count\":null,\"legacy_upload_bytes\":null}\n%!"
    (scenario_name scenario) (target_name ()) profile width height
    model.drawable_width model.drawable_height model.pixel_scale_x
    model.pixel_scale_y domains warmup_seconds measure_seconds result.frames
    result.wall_seconds (float result.frames /. result.wall_seconds)
    result.median_frame_seconds result.p95_frame_seconds result.p99_frame_seconds
    result.user_seconds result.system_seconds
    ((result.user_seconds +. result.system_seconds) /. result.wall_seconds *. 100.)
    result.allocated_bytes result.minor_bytes result.promoted_bytes
    result.major_bytes result.major_collections result.ending_heap_bytes
    result.peak_heap_bytes
    (Option.fold ~none:"null" ~some:string_of_int result.starting_rss_kib)
    (Option.fold ~none:"null" ~some:string_of_int result.ending_rss_kib)
    (Option.fold ~none:"null" ~some:string_of_int result.peak_sampled_rss_kib)

let () =
  let final = Sketch.run_state
      ~config:{ Sketch.default_config with width; height;
        title = "Prismel renderer benchmark"; fps = Some 60;
        domains = Some domains; clock = Sketch.Realtime; resizable = false }
      ~init ~update ~view ~on_stop:(fun model -> destroy_resources model.resources)
      () in
  match final.result with
  | None -> failwith "bench_renderer stopped before producing a result"
  | Some result -> print_result final result
