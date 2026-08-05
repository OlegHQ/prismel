open Tsdl
open Tsdl_ttf

type target = Target.t = Native | Headless | Web

type web_mouse_button = Wap.mouse_button = Left | Middle | Right | X1 | X2

type web_event =
  | Pointer_moved of int * int
  | Pointer_pressed of web_mouse_button * int * int
  | Pointer_released of web_mouse_button * int * int
  | Pointer_cancelled of web_mouse_button
  | Wheel of int * int
  | Key_pressed of string
  | Key_released of string
  | Text_input of string
  | Text_editing of { text : string; start : int; length : int }
  | Resized of int * int
  | Focus_lost
  | File_dropped of string

type text_input_region = {
  x : int;
  y : int;
  width : int;
  height : int;
  focused : bool;
}

type web_audio_command = Wap.audio_command =
  | Audio_master_volume of float
  | Audio_stop_all
  | Audio_sample_play of {
      asset : string; channel : int; loops : int; volume : float;
    }
  | Audio_sample_volume of { asset : string; volume : float }
  | Audio_sample_stop of int
  | Audio_sample_pause of int
  | Audio_sample_resume of int
  | Audio_music_play of { asset : string; loops : int; fade_ms : int }
  | Audio_music_volume of float
  | Audio_music_pause
  | Audio_music_resume
  | Audio_music_stop of int
  | Audio_asset_remove of string

type t = {
  target : target;
  web : Wap.t option;
  sdl_environment : (string * string option) list;
  image_initialized : bool;
  ttf_initialized : bool;
  mutable stopped : bool;
  mutable uploaded_files : string list;
  web_frame_interval : float;
  web_max_bytes_per_second : float;
  web_max_frame_pixels : int;
  mutable next_web_publish : float;
  mutable web_duplicate_streak : int;
}

let selected_target () = Target.get ()
let target_of_string = Target.of_string
let is_headless = Target.is_headless
let is_web = Target.is_web
let is_displayless = Target.is_displayless
let target runtime = runtime.target

let environment_int names default =
  match List.find_map Sys.getenv_opt names with
  | None -> Ok default
  | Some value ->
      (match int_of_string_opt (String.trim value) with
       | Some value -> Ok value
       | None -> Error (Printf.sprintf "%s must be an integer"
           (List.hd names)))

let environment_float names default =
  match List.find_map Sys.getenv_opt names with
  | None -> Ok default
  | Some value ->
      (match float_of_string_opt (String.trim value) with
       | Some value -> Ok value
       | None -> Error (Printf.sprintf "%s must be a number" (List.hd names)))

let monotonic_seconds () =
  Int64.to_float (Sdl.get_performance_counter ())
  /. Int64.to_float (Sdl.get_performance_frequency ())

let next_web_deadline ~previous ~now ~frame_interval ~traffic_interval =
  let cadence_deadline =
    if previous <= 0. || now -. previous >= frame_interval
    then now +. frame_interval
    else previous +. frame_interval
  in
  max cadence_deadline (now +. traffic_interval)

let fitted_web_drawable_size ~max_pixels ~logical_width ~logical_height =
  if logical_width <= 0 || logical_height <= 0 then
    invalid_arg "Runtime web dimensions must be positive";
  let pixels = Int64.mul (Int64.of_int logical_width) (Int64.of_int logical_height) in
  if pixels <= Int64.of_int max_pixels then logical_width, logical_height
  else
    let scale =
      sqrt (float_of_int max_pixels /. Int64.to_float pixels)
    in
    max 1 (int_of_float (floor (float_of_int logical_width *. scale))),
    max 1 (int_of_float (floor (float_of_int logical_height *. scale)))

let idle_frame_interval base duplicate_streak =
  let shift = min 2 (max 0 duplicate_streak / 2) in
  base *. float_of_int (1 lsl shift)

let sdl_environment_names =
  ["SDL_VIDEODRIVER"; "SDL_RENDER_DRIVER"; "SDL_AUDIODRIVER"]

external unset_environment : string -> unit = "prismel_runtime_unsetenv"

let capture_sdl_environment target =
  if target = Native then []
  else List.map (fun name -> name, Sys.getenv_opt name) sdl_environment_names

let restore_environment values =
  List.iter (fun (name, value) ->
    match value with
    | Some value -> Unix.putenv name value
    | None -> unset_environment name) values

let start ~width:_ ~height:_ ~title ~resizable:_ =
  match Target.selected () with
  | Error message -> Error ("Prismel runtime: " ^ message)
  | Ok target ->
      let sdl_environment = capture_sdl_environment target in
      Target.configure_sdl_environment target;
      ignore (Sdl.set_hint Sdl.Hint.render_scale_quality "1");
      if target = Native then ignore (Sdl.set_hint Sdl.Hint.render_driver "");
      let init_flags = Sdl.Init.(video + audio + events) in
      (match Sdl.init init_flags with
       | Error (`Msg message) ->
           restore_environment sdl_environment;
           Error ("SDL initialization failed: " ^ message)
       | Ok () ->
           let image_flags = Tsdl_image.Image.Init.(jpg + png) in
           let image_result = Tsdl_image.Image.init image_flags in
           let image_initialized =
             Tsdl_image.Image.Init.test image_result image_flags in
           if not image_initialized then
             Printf.eprintf "Prismel runtime warning: some image formats are unavailable\n%!";
           let ttf_initialized = match Ttf.init () with
             | Ok () -> true
             | Error (`Msg message) ->
                 Printf.eprintf "Prismel runtime warning: TTF disabled: %s\n%!" message;
                 false in
           let web =
             if target <> Web then Ok None
             else
               Result.bind
                 (environment_int ["PRISMEL_WEB_PORT"; "PRISMAL_WEB_PORT"] 8080)
                 (fun port ->
                   Result.bind
                     (environment_int
                        ["PRISMEL_WEB_MAX_FPS"; "PRISMAL_WEB_MAX_FPS"] 60)
                     (fun max_fps ->
                       if max_fps <= 0 || max_fps > 1000 then
                         Error "PRISMEL_WEB_MAX_FPS must be in 1..1000"
                       else
                         Result.bind
                           (environment_float
                              ["PRISMEL_WEB_MAX_MBIT";
                               "PRISMAL_WEB_MAX_MBIT"] 2.)
                           (fun max_mbit ->
                             if not (Float.is_finite max_mbit)
                                || max_mbit <= 0. || max_mbit > 1000.
                             then
                               Error
                                 "PRISMEL_WEB_MAX_MBIT must be finite and in (0,1000]"
                             else
                               Result.bind
                                 (environment_int
                                    ["PRISMEL_WEB_MAX_PIXELS";
                                     "PRISMAL_WEB_MAX_PIXELS"] 921_600)
                                 (fun max_pixels ->
                                   if max_pixels <= 0
                                      || max_pixels > 33_554_432
                                   then Error
                                     "PRISMEL_WEB_MAX_PIXELS must be in 1..33554432"
                                   else
                                     let config : Wap.config = {
                                       Wap.default_config with
                                       interface = "0.0.0.0";
                                       port;
                                       title;
                                       (* Browser viewports are authoritative;
                                          desktop resize opt-in is irrelevant. *)
                                       resizable = true;
                                     } in
                                     Result.map
                                       (fun server ->
                                         Some (server, max_fps,
                                           max_mbit *. 1_000_000. /. 8.,
                                           max_pixels))
                                       (Wap.start ~config ())))))
           in
           match web with
           | Ok web_with_fps ->
               let web, web_frame_interval, web_max_bytes_per_second,
                   web_max_frame_pixels =
                 match web_with_fps with
                 | None -> None, 0., infinity, max_int
                 | Some (server, max_fps, max_bytes_per_second, max_pixels) ->
                     Some server, 1. /. float_of_int max_fps,
                     max_bytes_per_second, max_pixels in
               let runtime = {
                 target; web; sdl_environment;
                 image_initialized; ttf_initialized;
                 stopped = false;
                 uploaded_files = [];
                 web_frame_interval;
                 web_max_bytes_per_second;
                 web_max_frame_pixels;
                 next_web_publish = 0.;
                 web_duplicate_streak = 0;
               } in
               Option.iter (fun server ->
                 Printf.eprintf "Prismel web target listening on %s\n%!"
                   (Wap.url server)) web;
               Ok runtime
           | Error message ->
               if ttf_initialized then Ttf.quit ();
               if image_initialized then Tsdl_image.Image.quit ();
               Sdl.quit ();
               restore_environment sdl_environment;
               Error message)

let stop runtime =
  if not runtime.stopped then begin
    runtime.stopped <- true;
    Option.iter Wap.stop runtime.web;
    List.iter (fun path ->
      try if Sys.file_exists path then Sys.remove path with Sys_error _ -> ())
      runtime.uploaded_files;
    runtime.uploaded_files <- [];
    if runtime.ttf_initialized then Ttf.quit ();
    if runtime.image_initialized then Tsdl_image.Image.quit ();
    Sdl.quit ();
    restore_environment runtime.sdl_environment
  end

let web_url runtime = Option.map Wap.url runtime.web
let web_client_count runtime =
  Option.fold ~none:0 ~some:Wap.client_count runtime.web
let web_drawable_size runtime ~logical_width ~logical_height =
  if runtime.target <> Web then logical_width, logical_height
  else fitted_web_drawable_size ~max_pixels:runtime.web_max_frame_pixels
      ~logical_width ~logical_height
let register_web_file runtime ?content_type path =
  Option.bind runtime.web (fun server ->
    Wap.register_file server ?content_type path)
let register_web_bytes runtime ?content_type bytes =
  Option.bind runtime.web (fun server ->
    Wap.register_bytes server ?content_type bytes)
let remove_web_asset runtime id =
  Option.iter (fun server -> Wap.remove_asset server id) runtime.web
let send_web_audio runtime command =
  Option.iter (fun server -> Wap.broadcast_audio server command) runtime.web
let download_web_frame runtime ~filename =
  match runtime.web with
  | None -> Error "The web target is not active"
  | Some server -> Wap.download_frame server ~filename

let set_web_text_input_regions runtime regions =
  Option.iter (fun server ->
    Wap.set_text_input_regions server
      (List.map (fun region ->
         { Wap.x = region.x;
           y = region.y;
           width = region.width;
           height = region.height;
           focused = region.focused }) regions)) runtime.web
let safe_upload_suffix name =
  let suffix = Filename.extension name in
  if String.length suffix > 0 && String.length suffix <= 16
     && String.for_all (function
       | '.' | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '-' -> true
       | _ -> false) suffix
  then suffix else ".upload"

let materialize_upload runtime name contents =
  try
    let path = Filename.temp_file "prismel-web-drop-" (safe_upload_suffix name) in
    let channel = open_out_bin path in
    (try output_bytes channel contents; close_out channel
     with error -> close_out_noerr channel; raise error);
    runtime.uploaded_files <- path :: runtime.uploaded_files;
    Some (File_dropped path)
  with Sys_error message ->
    Printf.eprintf "Prismel web upload warning: %s\n%!" message;
    None

let drain_web_events runtime =
  let convert = function
    | Wap.Pointer_moved (x, y) -> Some (Pointer_moved (x, y))
    | Wap.Pointer_pressed (button, x, y) ->
        Some (Pointer_pressed (button, x, y))
    | Wap.Pointer_released (button, x, y) ->
        Some (Pointer_released (button, x, y))
    | Wap.Pointer_cancelled button -> Some (Pointer_cancelled button)
    | Wap.Wheel (x, y) -> Some (Wheel (x, y))
    | Wap.Key_pressed key -> Some (Key_pressed key)
    | Wap.Key_released key -> Some (Key_released key)
    | Wap.Text_input text -> Some (Text_input text)
    | Wap.Text_editing { text; start; length } ->
        Some (Text_editing { text; start; length })
    | Wap.Resized (width, height) -> Some (Resized (width, height))
    | Wap.Focus_lost -> Some Focus_lost
    | Wap.File_uploaded { name; contents } ->
        materialize_upload runtime name contents
  in
  let events = Option.fold ~none:[]
    ~some:(fun server -> List.filter_map convert (Wap.drain_events server))
    runtime.web
  in
  if events <> [] then begin
    runtime.web_duplicate_streak <- 0;
    runtime.next_web_publish <- 0.
  end;
  events

let present runtime renderer ~logical_width ~logical_height =
  let publish_result =
    match runtime.web with
    | None -> Ok ()
    | Some server when Wap.client_count server = 0 -> Ok ()
    | Some server ->
        let now = monotonic_seconds () in
        if now < runtime.next_web_publish then
          Ok ()
        else (match Sdl.get_renderer_output_size renderer with
         | Error (`Msg message) ->
             Error ("web framebuffer size query failed: " ^ message)
         | Ok (drawable_width, drawable_height) ->
             let pitch = drawable_width * 4 in
             let pixels =
               Wap.acquire_frame server ~length:(pitch * drawable_height) in
             match Sdl.render_read_pixels renderer None
                 (Some Sdl.Pixel.format_rgba32) pixels pitch with
             | Error (`Msg message) ->
                 Wap.discard_frame server pixels;
                 Error ("web framebuffer readback failed: " ^ message)
             | Ok () ->
                 let before = Wap.stats server in
                 Wap.publish_frame server ~drawable_width ~drawable_height
                   ~logical_width ~logical_height pixels;
                 let after = Wap.stats server in
                 let payload_bytes =
                   Int64.sub after.payload_bytes_published
                     before.payload_bytes_published
                   |> Int64.to_float in
                 if after.frames_suppressed > before.frames_suppressed then
                   runtime.web_duplicate_streak <-
                     runtime.web_duplicate_streak + 1
                 else runtime.web_duplicate_streak <- 0;
                 let traffic_interval =
                   payload_bytes /. runtime.web_max_bytes_per_second in
                 runtime.next_web_publish <-
                   next_web_deadline ~previous:runtime.next_web_publish ~now
                     ~frame_interval:(idle_frame_interval
                       runtime.web_frame_interval runtime.web_duplicate_streak)
                     ~traffic_interval;
                 Ok ())
  in
  Sdl.render_present renderer;
  publish_result

module Private = struct
  let select_target = Target.select_with
  let next_web_deadline = next_web_deadline
  let fitted_web_drawable_size = fitted_web_drawable_size
  let idle_frame_interval = idle_frame_interval
end
