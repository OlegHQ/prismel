type clock =
  | Realtime
  | Fixed of float

type render_target = Native | Headless | Web

type config = {
  width : int;
  height : int;
  title : string;
  fps : int option;
  domains : int option;
  clock : clock;
  resizable : bool;
  fullscreen : bool;
}

let default_config = {
  width = 800;
  height = 600;
  title = "Prismel sketch";
  fps = Some 60;
  domains = None;
  clock = Realtime;
  resizable = true;
  fullscreen = false;
}

type 'model runtime = {
  model : 'model;
  frame : Frame.t;
  pending_events_rev : Event.t list;
}

let snapshot ~clock ~count ~events =
  let width, height = Window.size () in
  let drawable_width, drawable_height = Window.drawable_size () in
  let time, dt, fps =
    match clock with
    | Realtime -> Time.now (), Time.get_delta_time (), Time.get_frame_rate ()
    | Fixed dt ->
        if not (Float.is_finite dt) || dt <= 0. then
          invalid_arg "Sketch.Fixed: timestep must be finite and positive";
        float_of_int count *. dt, dt, 1. /. dt
  in
  {
    Frame.width;
    height;
    size = (width, height);
    drawable_width;
    drawable_height;
    drawable_size = (drawable_width, drawable_height);
    pixel_scale =
      ( float_of_int drawable_width /. float_of_int width,
        float_of_int drawable_height /. float_of_int height );
    time;
    dt;
    fps;
    count;
    mouse = Input.mouse_pos ();
    mouse_delta = Input.mouse_delta ();
    keys = Input.keys_down ();
    mouse_buttons = Input.mouse_buttons_down ();
    events;
  }

let window_config config =
  {
    Window.default_config with
    width = config.width;
    height = config.height;
    title = config.title;
    resizable = config.resizable;
    fullscreen = config.fullscreen;
    vsync = Option.is_none config.fps;
  }

let run_state_internal ?(config = default_config) ?max_frames ~init ~update ~view
    ?after_draw ?on_stop () =
  Option.iter
    (fun frames ->
      if frames <= 0 then invalid_arg "Sketch: max_frames must be positive")
    max_frames;
  Time.set_frame_rate (Option.value config.fps ~default:0);
  let init_runtime () =
    let frame = snapshot ~clock:config.clock ~count:0 ~events:[] in
    { model = init frame; frame; pending_events_rev = [] }
  in
  let on_event runtime event =
    { runtime with pending_events_rev = event :: runtime.pending_events_rev }
  in
  let update_runtime runtime _dt =
    let events = List.rev runtime.pending_events_rev in
    let frame =
      snapshot ~clock:config.clock ~count:(runtime.frame.count + 1) ~events
    in
    let next =
    {
      model = update runtime.model frame;
      frame;
      pending_events_rev = [];
    } in
    Option.iter
      (fun limit -> if frame.count >= limit then App.request_quit ())
      max_frames;
    next
  in
  let draw_runtime runtime = Scene.render (view runtime.model runtime.frame) in
  let final =
    Parallel.run ?domains:config.domains (fun () ->
      App.run ~config:(window_config config)
        ~init:init_runtime ~update:update_runtime ~draw:draw_runtime
        ?after_draw:(Option.map
          (fun callback runtime -> callback runtime.model runtime.frame)
          after_draw)
        ~on_event
        ?on_stop:(Option.map
          (fun stop runtime -> stop runtime.model)
          on_stop)
        ())
  in
  final.model

let run_state ?config ?max_frames ~init ~update ~view ?on_stop () =
  run_state_internal ?config ?max_frames ~init ~update ~view ?on_stop ()

let run ?config view =
  ignore
    (run_state ?config
      ~init:(fun _ -> ())
      ~update:(fun () _ -> ())
      ~view:(fun () frame -> view frame)
      ())

type 'model with_assets = {
  assets : Assets.t;
  user_model : 'model;
}

let run_assets ?config ?root ?(watch = false) ~init ~update ~view () =
  let initialize frame =
    let assets = Assets.create ?root ~watch () in
    try { assets; user_model = init assets frame }
    with error ->
      Assets.destroy assets;
      raise error
  in
  let update_model model frame =
    (match Assets.refresh model.assets with
     | Ok _ -> ()
     | Error errors ->
         List.iter
           (fun message ->
             Printf.eprintf "Prismel asset reload warning: %s\n%!" message)
           errors);
    { model with
      user_model = update model.assets model.user_model frame;
    }
  in
  let view_model model frame = view model.assets model.user_model frame in
  let stop model = Assets.destroy model.assets in
  let final =
    run_state ?config ~init:initialize ~update:update_model ~view:view_model
      ~on_stop:stop ()
  in
  final.user_model

let quit = App.request_quit

let resize ~width ~height =
  if width <= 0 || height <= 0 then
    invalid_arg "Sketch.resize: dimensions must be positive";
  if not (Window.exists ()) then invalid_arg "Sketch.resize: no sketch is running";
  Window.set_size width height
let is_headless = Backend.is_headless
let is_web = Backend.is_web
let render_target () =
  match Runtime.selected_target () with
  | Runtime.Native -> Native
  | Headless -> Headless
  | Web -> Web

let rec ensure_directory path =
  if path = "" || path = "." || Sys.file_exists path then ()
  else begin
    let parent = Filename.dirname path in
    if parent <> path then ensure_directory parent;
    try Unix.mkdir path 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let export_state ?(config = default_config) ?(fps = 60) ?(prefix = "frame")
    ~directory ~frames ~init ~update ~view ?on_stop () =
  if frames <= 0 then invalid_arg "Sketch.export_state: frames must be positive";
  if fps <= 0 then invalid_arg "Sketch.export_state: fps must be positive";
  if prefix = "" || prefix = "." || prefix = ".."
     || Filename.basename prefix <> prefix
  then
    invalid_arg "Sketch.export_state: prefix must be a non-empty filename stem";
  ensure_directory directory;
  let index = ref 0 in
  let after_draw _model _frame =
    let filename =
      Filename.concat directory (Printf.sprintf "%s-%06d.png" prefix !index)
    in
    (match Canvas.save_screen_png filename with
     | Ok () -> ()
     | Error message -> failwith ("Frame export failed: " ^ message));
    incr index;
    if !index >= frames then quit ()
  in
  let config = { config with clock = Fixed (1. /. float_of_int fps); fps = None } in
  run_state_internal ~config ~init ~update ~view ~after_draw ?on_stop ()

let export ?config ?fps ?prefix ~directory ~frames view =
  ignore
    (export_state ?config ?fps ?prefix ~directory ~frames
       ~init:(fun _ -> ())
       ~update:(fun () _ -> ())
       ~view:(fun () frame -> view frame)
       ())
