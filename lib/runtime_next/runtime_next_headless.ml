type t = {
  window : Sdl3.Window.t;
  presenter : Sdl3.Rgba_presenter.t;
  renderer : Scene_execution.t;
  control : Ogpu_raster2.control;
  mutable readback : bytes;
  mutable drawable_width : int;
  mutable drawable_height : int;
  mutable dead : bool;
}

let error operation kind message = Error (Ogpu.Error.make operation kind message)
let sdl operation = Result.map_error (fun value ->
    Ogpu.Error.make operation Ogpu.Error.Invalid_state
      (Format.asprintf "%a" Sdl3.pp_error value))

let configuration ~logical_width ~logical_height ~drawable_width ~drawable_height =
  { Ogpu.Surface.logical_width; logical_height; physical_width=drawable_width;
    physical_height=drawable_height; format=Rgba8_unorm; present_mode=Immediate;
    max_acquired=2 }

let valid_dimensions ~logical_width ~logical_height ~drawable_width ~drawable_height =
  logical_width > 0 && logical_height > 0 && drawable_width > 0 && drawable_height > 0

let create ~logical_width ~logical_height ~drawable_width ~drawable_height =
  let operation="Runtime_next_headless.create"in
  if not(valid_dimensions~logical_width~logical_height~drawable_width~drawable_height)
  then error operation Invalid_argument"dimensions must be positive"else
  match sdl operation(Sdl3.Init.init~release:false[Sdl3.Init.Video])with Error _ as e->e|Ok()->
  match sdl operation(Sdl3.Window.create~title:"Prismel headless-next"
      ~width:logical_width~height:logical_height~flags:[Hidden]())with
  |Error e->ignore(Sdl3.Init.quit_subsystems[Video]);Error e
  |Ok window->match sdl operation(Sdl3.Rgba_presenter.create window)with
    |Error e->ignore(Sdl3.Window.destroy window);ignore(Sdl3.Init.quit_subsystems[Video]);Error e
    |Ok presenter->let driver,control=Ogpu_raster2.create()in
      match Scene_execution.create_variants driver(configuration~logical_width~logical_height
          ~drawable_width~drawable_height)with
      |Error e->ignore(Sdl3.Rgba_presenter.destroy presenter);ignore(Sdl3.Window.destroy window);
        ignore(Sdl3.Init.quit_subsystems[Video]);Error e
      |Ok renderer->Ok{window;presenter;renderer;control;
        readback=Bytes.create(drawable_width*drawable_height*4);
        drawable_width;drawable_height;dead=false}

let ensure_live operation value =
  if value.dead then error operation Stale_handle"runtime is destroyed"else Ok()

let render_result operation value submit =
  match ensure_live operation value with Error _ as e->e|Ok()->
  match submit value.renderer with Error _ as e->e|Ok false->Ok false|Ok true->
  let pitch=value.drawable_width*4 in
  match Scene_execution.read_pixels_into value.renderer~bytes_per_row:pitch
    ~destination:value.readback with Error _ as e->e|Ok()->
  match sdl operation(Sdl3.Rgba_presenter.present value.presenter~width:value.drawable_width
      ~height:value.drawable_height~pitch value.readback)with Error _ as e->e|Ok()->Ok true

let render value draws = render_result "Runtime_next_headless.render" value
  (fun renderer->Scene_execution.render renderer draws)
let render_sampled_resources value draws =
  render_result "Runtime_next_headless.render_sampled_resources" value
    (fun renderer->Scene_execution.render_sampled_resources renderer draws)

let resize value ~logical_width ~logical_height ~drawable_width ~drawable_height =
  let operation="Runtime_next_headless.resize"in
  match ensure_live operation value with Error _ as e->e|Ok()->
  if not(valid_dimensions~logical_width~logical_height~drawable_width~drawable_height)
  then error operation Invalid_argument"dimensions must be positive"else
  match sdl operation (Sdl3.Window.size value.window) with
  | Error _ as error -> error
  | Ok (old_width, old_height) ->
      match sdl operation
          (Sdl3.Window.set_size value.window ~width:logical_width
             ~height:logical_height) with
      | Error _ as error -> error
      | Ok () ->
          match sdl operation (Sdl3.Window.sync value.window) with
          | Error _ as error -> error
          | Ok () ->
              match Scene_execution.resize value.renderer
                  (configuration ~logical_width ~logical_height
                     ~drawable_width ~drawable_height) with
              | Ok () ->
                  value.drawable_width <- drawable_width;
                  value.drawable_height <- drawable_height;
                  value.readback<-Bytes.create(drawable_width*drawable_height*4);
                  Ok ()
              | Error _ as error ->
                  ignore (Sdl3.Window.set_size value.window ~width:old_width
                            ~height:old_height);
                  ignore (Sdl3.Window.sync value.window);
                  error

let read_pixels value ~bytes_per_row =
  match ensure_live"Runtime_next_headless.read_pixels"value with
  |Error _ as e->e|Ok()->Scene_execution.read_pixels value.renderer~bytes_per_row

let presented_pixels value =
  match ensure_live"Runtime_next_headless.presented_pixels"value with Error _ as e->e|Ok()->
  sdl"Runtime_next_headless.presented_pixels"(Sdl3.Rgba_presenter.copy_rgba value.presenter)

let backend_live_counts value=Ogpu_raster2.live_counts value.control
let backend_trace_stats value = Ogpu_raster2.trace_stats value.control
let resource_stats value=Scene_execution.upload_bytes value.renderer,Scene_execution.cache_entries value.renderer

let destroy value =
  if value.dead then Ok ()
  else begin
    value.dead <- true;
    let renderer_result = Scene_execution.destroy value.renderer in
    let presenter_result =
      sdl "Runtime_next_headless.destroy"
        (Sdl3.Rgba_presenter.destroy value.presenter)
    in
    let window_result =
      sdl "Runtime_next_headless.destroy" (Sdl3.Window.destroy value.window)
    in
    let video_result =
      sdl "Runtime_next_headless.destroy"
        (Sdl3.Init.quit_subsystems [ Sdl3.Init.Video ])
    in
    match renderer_result, presenter_result, window_result, video_result with
    | Error error, _, _, _
    | _, Error error, _, _
    | _, _, Error error, _
    | _, _, _, Error error -> Error error
    | Ok (), Ok (), Ok (), Ok () -> Ok ()
  end
