module Next = Prismel_next_low

let error_to_string = function
  | Next.Invalid_argument message | Unavailable message | Backend message -> message

let get = function Ok value -> value | Error error -> failwith (error_to_string error)

module Window = struct
  type config = Next.Window.config = {
    width:int; height:int; title:string; resizable:bool; fullscreen:bool;
    x:int option; y:int option; vsync:bool; highdpi:bool;
    multisampling:int option;
  }
  type t = Next.Window.t
  let default_config = Next.Window.default_config
  let current : t option ref = ref None
  let current_window = current
  let create ?config () =
    let value = get (Next.Window.create ?config ()) in
    current := Some value;
    value
  let get_current () = match !current with Some value -> value | None -> failwith "Window is not initialized"
  let width () = Next.Window.width (get_current ())
  let height () = Next.Window.height (get_current ())
  let size () = Next.Window.size (get_current ())
  let drawable_size () = Next.Window.drawable_size (get_current ())
  let pixel_scale () = Next.Window.pixel_scale (get_current ())
  let title () = Next.Window.title (get_current ())
  let is_resizable () = Next.Window.is_resizable (get_current ())
  let is_fullscreen () = Next.Window.is_fullscreen (get_current ())
  let set_title value = get (Next.Window.set_title (get_current ()) value)
  let set_size width height = get (Next.Window.set_size (get_current ()) width height)
  let set_web_size = set_size
  let set_position x y = get (Next.Window.set_position (get_current ()) x y)
  let center () = get (Next.Window.center (get_current ()))
  let set_fullscreen value = get (Next.Window.set_fullscreen (get_current ()) value)
  let show () = get (Next.Window.show (get_current ()))
  let hide () = get (Next.Window.hide (get_current ()))
  let minimize () = get (Next.Window.minimize (get_current ()))
  let maximize () = get (Next.Window.maximize (get_current ()))
  let restore () = get (Next.Window.restore (get_current ()))
  let update_dimensions = set_size
  let destroy () = match !current with
    | None -> ()
    | Some value -> get (Next.Window.destroy value); current := None
  let exists () = match !current with Some value -> Next.Window.exists value | None -> false
end

let packed color =
  Int32.logor (Int32.shift_left (Int32.of_int color.Color.r) 24)
    (Int32.logor (Int32.shift_left (Int32.of_int color.g) 16)
      (Int32.logor (Int32.shift_left (Int32.of_int color.b) 8)
        (Int32.of_int color.a)))

let unpack value =
  let channel shift = Int32.(to_int (logand (shift_right_logical value shift) 0xffl)) in
  Color.rgba (channel 24) (channel 16) (channel 8) (channel 0)

module Graphics = struct
  type state = {
    renderer : Window.t option;
    current_color : Color.t;
    transform_stack : Mat3.t Stack.t;
    current_transform : Mat3.t;
    current_clip : (int*int*int*int) option;
  }
  let graphics_state = ref { renderer=None; current_color=Color.white;
    transform_stack=Stack.create (); current_transform=Mat3.identity;
    current_clip=None }
  let current : Next.Graphics.t option ref = ref None
  let state () = match !current with Some value -> value | None -> failwith "Graphics is not initialized"
  let init (window : Window.t) =
    current := Some (get (Next.Graphics.create ()));
    graphics_state := { !graphics_state with renderer=Some window }
  let result value = get value
  let color_to_sdl (color : Color.t) = color.r, color.g, color.b, color.a
  let transform_point point = point
  let clear color = result (Next.Graphics.clear (state ()) (packed color))
  let set_color color =
    Next.Graphics.set_color (state ()) (packed color);
    graphics_state := { !graphics_state with current_color=color }
  let get_color ?color () = unpack (Next.Graphics.get_color (state ()) ?color:(Option.map packed color) ())
  let point ~x ~y ?color () = result (Next.Graphics.point (state ()) ~x ~y ?color:(Option.map packed color) ())
  let line ~x1 ~y1 ~x2 ~y2 ?color () = result (Next.Graphics.line (state ()) ~x1 ~y1 ~x2 ~y2 ?color:(Option.map packed color) ())
  let rect ~pos ~w ~h ?filled ?color () = result (Next.Graphics.rect (state ()) ~pos ~w ~h ?filled ?color:(Option.map packed color) ())
  let circle ~center ~radius ?filled ?color () = result (Next.Graphics.circle (state ()) ~center ~radius ?filled ?color:(Option.map packed color) ())
  let triangle ~p1 ~p2 ~p3 ?filled ?color () = result (Next.Graphics.triangle (state ()) ~p1 ~p2 ~p3 ?filled ?color:(Option.map packed color) ())
  let polygon ~points ?filled ?color () = result (Next.Graphics.polygon (state ()) ~points ?filled ?color:(Option.map packed color) ())
  let fill_contours contours ~rule ~color =
    let rule = match rule with Path.Even_odd -> Raster2.Path.Even_odd | Non_zero -> Non_zero in
    result (Next.Graphics.fill_contours (state ()) contours ~rule ~color:(packed color))
  let draw_image image ~pos = result (Next.Graphics.draw_image (state ()) image ~pos)
  let draw_sub_image image ~src_rect ~dst_rect = result (Next.Graphics.draw_sub_image (state ()) image ~src_rect ~dst_rect)
  let draw_image_ex image ~pos ?scale ?angle ?center ?flip () = result (Next.Graphics.draw_image_ex (state ()) image ~pos ?scale ?angle ?center ?flip ())
  let draw_text font ~pos ~text ?color ?wrap ?align () =
    let color = Option.value color ~default:(get_color ()) in
    match Font.cached_text ?wrap ?align font text (Font.Blended color) with
    | Error (`Msg message) -> failwith message
    | Ok image -> draw_image image ~pos
  let push_matrix () = result (Next.Graphics.push_matrix (state ()))
  let pop_matrix () = result (Next.Graphics.pop_matrix (state ()))
  let translate ~dx ~dy = Next.Graphics.translate (state ()) ~dx ~dy
  let rotate ~angle = Next.Graphics.rotate (state ()) ~angle
  let scale ~sx ~sy = Next.Graphics.scale (state ()) ~sx ~sy
  let reset_transform () = Next.Graphics.reset_transform (state ())
  let get_clip () = Next.Graphics.get_clip (state ())
  let set_clip value =
    result (Next.Graphics.set_clip (state ()) value);
    graphics_state := { !graphics_state with current_clip=value }
  let polyline ~points ?color () = result (Next.Graphics.polyline (state ()) ~points ?color:(Option.map packed color) ())
  let ellipse ~center ~rx ~ry ?filled ?color () = result (Next.Graphics.ellipse (state ()) ~center ~rx ~ry ?filled ?color:(Option.map packed color) ())
  let rounded_rect ~pos ~w ~h ~radius ?filled ?color () = result (Next.Graphics.rounded_rect (state ()) ~pos ~w ~h ~radius ?filled ?color:(Option.map packed color) ())
  let thick_line ~x1 ~y1 ~x2 ~y2 ~width ?color () = result (Next.Graphics.thick_line (state ()) ~x1 ~y1 ~x2 ~y2 ~width ?color:(Option.map packed color) ())
  let arc ~center ~radius ~start_angle ~end_angle ?color () = result (Next.Graphics.arc (state ()) ~center ~radius ~start_angle ~end_angle ?color:(Option.map packed color) ())
  let pie ~center ~radius ~start_angle ~end_angle ?filled ?color () = result (Next.Graphics.pie (state ()) ~center ~radius ~start_angle ~end_angle ?filled ?color:(Option.map packed color) ())
  let bezier ~points ~steps ?color () = result (Next.Graphics.bezier (state ()) ~points ~steps ?color:(Option.map packed color) ())
  let draw_gfx_text ~pos ~text ?color () = result (Next.Graphics.draw_gfx_text (state ()) ~pos ~text ?color:(Option.map packed color) ())
  let set_gfx_font_rotation value = result (Next.Graphics.set_gfx_font_rotation (state ()) value)
end

module App = struct
  type config = Window.config
  type 'a framework_state = { window:Window.t; running:bool; user_state:'a }
  let framework_running = ref false
  let quit_requested = ref false
  let request_quit () = quit_requested := true
  let is_running () = !framework_running && not !quit_requested
  let init_sdl ?config () =
    let window = Window.create ?config () in
    Graphics.init window;
    framework_running := true;
    quit_requested := false;
    Time.init ()
  let cleanup_graphics () = match !(Graphics.current) with None -> () | Some value -> Next.Graphics.destroy value; Graphics.current := None
  let cleanup_sdl () = cleanup_graphics (); Window.destroy (); framework_running := false
  let present window =
    let ir = get (Next.Graphics.flush (Graphics.state ())) in
    ignore (get (Next.Window.present window ir))
  let process_frame window state update draw after_draw on_event =
    Time.update ();
    let state = List.fold_left (fun state event -> match on_event with None -> state | Some f -> f state event) state (Event.poll_events ()) in
    let state = update state (Time.get_delta_time ()) in
    draw state;
    Option.iter (fun f -> f state) after_draw;
    present window;
    { window; running=is_running (); user_state=state }
  let rec main_loop frame update draw after_draw on_event =
    if not frame.running then frame.user_state
    else main_loop (process_frame frame.window frame.user_state update draw after_draw on_event) update draw after_draw on_event
  let run ?config ~init ~update ~draw ?after_draw ?on_event ?on_stop () =
    init_sdl ?config ();
    let state = init () in
    Fun.protect ~finally:cleanup_sdl (fun () ->
      let result = main_loop {window=Window.get_current ();running=true;user_state=state} update draw after_draw on_event in
      Option.iter (fun f -> f result) on_stop;
      result)
  let run_simple ?(width=800) ?(height=600) ?(title="Prismel") ~init ~update ~draw ?after_draw ?on_event ?on_stop () =
    let config = {Window.default_config with width;height;title} in
    run ~config ~init ~update ~draw ?after_draw ?on_event ?on_stop ()
  let get_window = Window.get_current
  let get_renderer = Window.get_current
  module Utils = struct
    let window_size = Window.size
    let window_width = Window.width
    let window_height = Window.height
    let time = Time.elapsed
    let delta_time = Time.get_delta_time
    let frame_rate = Time.get_frame_rate
    let set_frame_rate = Time.set_frame_rate
    let set_vsync = Time.set_vsync
  end
end

module Backend = struct
  type web_event = Runtime_next_orchestrator.web_event
  type web_audio_command = Runtime_next_orchestrator.audio_command
  let selected () = Runtime_next_compat.selected_target ()
  let is_headless () = selected () = Ok Runtime_next_compat.Headless
  let is_web () = selected () = Ok Runtime_next_compat.Web
  let is_displayless () = not (selected () = Ok Runtime_next_compat.Native)
  let start ~width ~height ~title ~resizable =
    try Ok (Window.create ~config:{Window.default_config with width;height;title;resizable} ())
    with exn -> Error (Printexc.to_string exn)
  let stop = Window.destroy
  let present window ~logical_width ~logical_height =
    ignore (logical_width, logical_height);
    try App.present window; Ok () with exn -> Error (Printexc.to_string exn)
  let drain_web_events () = []
  let web_url () = None
  let web_drawable_size ~logical_width ~logical_height = logical_width, logical_height
  let register_web_file ?content_type:_ _ = None
  let register_web_bytes ?content_type:_ _ = None
  let remove_web_asset _ = ()
  let send_web_audio _ = ()
  let download_web_frame ~filename:_ = Error "web frame download unavailable without an active typed web session"
  let add_web_text_input_region ~x:_ ~y:_ ~width:_ ~height:_ ~focused:_ = ()
end
