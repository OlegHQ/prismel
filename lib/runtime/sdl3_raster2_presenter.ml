type frame = {
  rgba : bytes;
  pitch : int;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
}

type error =
  | Invalid_frame of string
  | Sdl of Sdl3.error
  | Destroyed

type stats = {
  live_presenters : int;
  live_textures : int;
  texture_recreations : int;
  presented_frames : int;
}

type t = {
  window : Sdl3.Window.t;
  presenter : Sdl3.Rgba_presenter.t;
  mutable texture_size : (int * int) option;
  mutable texture_recreations : int;
  mutable presented_frames : int;
  mutable destroyed : bool;
}

type session = {
  window : Sdl3.Window.t;
  presenter : t;
  mutable destroyed_session : bool;
}

let invalid message = Error (Invalid_frame message)

let create window =
  match Sdl3.Rgba_presenter.create window with
  | Error error -> Error (Sdl error)
  | Ok presenter -> Ok {
      window; presenter; texture_size = None; texture_recreations = 0;
      presented_frames = 0; destroyed = false;
    }

let validate value frame =
  if value.destroyed then
    Error Destroyed
  else if frame.logical_width <= 0 || frame.logical_height <= 0 ||
      frame.drawable_width <= 0 || frame.drawable_height <= 0 then
    invalid "logical and drawable dimensions must be positive"
  else if frame.drawable_width > max_int / 4 then
    invalid "drawable RGBA row size overflows"
  else if frame.pitch < frame.drawable_width * 4 then
    invalid "pitch is smaller than one drawable RGBA row"
  else if frame.drawable_height > max_int / frame.pitch ||
      Bytes.length frame.rgba < frame.pitch * frame.drawable_height then
    invalid "RGBA storage is shorter than pitch multiplied by height"
  else
    match Sdl3.Window.size value.window with
    | Error error -> Error (Sdl error)
    | Ok logical when logical <>
        (frame.logical_width, frame.logical_height) ->
        invalid "declared logical size differs from the SDL3 window"
    | Ok _ -> Ok ()

let present value frame =
  match validate value frame with
  | Error _ as failure -> failure
  | Ok () ->
      match Sdl3.Rgba_presenter.present value.presenter
          ~width:frame.drawable_width ~height:frame.drawable_height
          ~pitch:frame.pitch frame.rgba with
      | Error error -> Error (Sdl error)
      | Ok () ->
          let size = frame.drawable_width, frame.drawable_height in
          if value.texture_size <> Some size then begin
            value.texture_size <- Some size;
            value.texture_recreations <- value.texture_recreations + 1
          end;
          value.presented_frames <- value.presented_frames + 1;
          Ok ()

let copy_rgba value =
  if value.destroyed then
    Error Destroyed
  else Result.map_error (fun error -> Sdl error)
      (Sdl3.Rgba_presenter.copy_rgba value.presenter)

let stats value = {
  live_presenters = (if value.destroyed then 0 else 1);
  live_textures = (if value.destroyed || value.texture_size = None then 0 else 1);
  texture_recreations = value.texture_recreations;
  presented_frames = value.presented_frames;
}

let destroy value =
  if value.destroyed then Ok ()
  else
    match Sdl3.Rgba_presenter.destroy value.presenter with
    | Error error -> Error (Sdl error)
    | Ok () -> value.destroyed <- true; value.texture_size <- None; Ok ()

let create_session ~logical_width ~logical_height =
  if logical_width <= 0 || logical_height <= 0 then
    invalid "session dimensions must be positive"
  else
    match Sdl3.Init.init ~release:false [Video] with
    | Error error -> Error (Sdl error)
    | Ok () ->
        match Sdl3.Window.create ~title:"Prismel Raster2 comparison"
            ~width:logical_width ~height:logical_height ~flags:[Hidden] () with
        | Error error ->
            ignore (Sdl3.Init.quit_subsystems [Video]);
            Error (Sdl error)
        | Ok window ->
            match create window with
            | Ok presenter -> Ok { window; presenter; destroyed_session = false }
            | Error _ as failure ->
                ignore (Sdl3.Window.destroy window);
                ignore (Sdl3.Init.quit_subsystems [Video]);
                failure

let resize_session value ~logical_width ~logical_height =
  if value.destroyed_session then Error Destroyed
  else if logical_width <= 0 || logical_height <= 0 then
    invalid "session dimensions must be positive"
  else
    match Sdl3.Window.set_size value.window ~width:logical_width
        ~height:logical_height with
    | Error error -> Error (Sdl error)
    | Ok () -> Result.map_error (fun error -> Sdl error)
        (Sdl3.Window.sync value.window)

let present_session value frame =
  if value.destroyed_session then Error Destroyed
  else present value.presenter frame

let copy_session_rgba value =
  if value.destroyed_session then Error Destroyed
  else copy_rgba value.presenter

let destroy_session value =
  if value.destroyed_session then Ok ()
  else
    match destroy value.presenter with
    | Error _ as failure -> failure
    | Ok () ->
        begin match Sdl3.Window.destroy value.window with
        | Error error -> Error (Sdl error)
        | Ok () ->
            value.destroyed_session <- true;
            Result.map_error (fun error -> Sdl error)
              (Sdl3.Init.quit_subsystems [Video])
        end
