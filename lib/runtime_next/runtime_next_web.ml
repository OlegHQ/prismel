module Presenter = Runtime_wap_raster2_presenter.Wap_raster2_presenter

type t = {
  presenter : Presenter.t;
  renderer : Scene_execution.t;
  control : Ogpu_raster2.control;
  mutable logical_width : int;
  mutable logical_height : int;
  mutable drawable_width : int;
  mutable drawable_height : int;
  mutable dead : bool;
}

let error operation kind message =
  Error (Ogpu.Error.make operation kind message)

let presenter_error operation = function
  | Presenter.Invalid_frame message ->
      Ogpu.Error.make operation Ogpu.Error.Invalid_argument message
  | Presenter.Transport message ->
      Ogpu.Error.make operation Ogpu.Error.Invalid_state message
  | Presenter.Destroyed ->
      Ogpu.Error.make operation Ogpu.Error.Stale_handle "presenter is destroyed"

let configuration ~logical_width ~logical_height ~drawable_width
    ~drawable_height =
  {
    Ogpu.Surface.logical_width;
    logical_height;
    physical_width = drawable_width;
    physical_height = drawable_height;
    format = Rgba8_unorm;
    present_mode = Immediate;
    max_acquired = 2;
  }

let valid_dimensions ~logical_width ~logical_height ~drawable_width
    ~drawable_height =
  logical_width > 0 && logical_height > 0 && drawable_width > 0
  && drawable_height > 0

let create ?wap_config ~logical_width ~logical_height ~drawable_width
    ~drawable_height () =
  let operation = "Runtime_next_web.create" in
  if
    not
      (valid_dimensions ~logical_width ~logical_height ~drawable_width
         ~drawable_height)
  then error operation Ogpu.Error.Invalid_argument "dimensions must be positive"
  else
    match Presenter.create ?config:wap_config () with
    | Error presenter_error_value ->
        Error (presenter_error operation presenter_error_value)
    | Ok presenter ->
        let driver, control = Ogpu_raster2.create () in
        match
          Scene_execution.create driver
            (configuration ~logical_width ~logical_height ~drawable_width
               ~drawable_height)
        with
        | Error error_value ->
            Presenter.destroy presenter;
            Error error_value
        | Ok renderer ->
            Ok
              {
                presenter;
                renderer;
                control;
                logical_width;
                logical_height;
                drawable_width;
                drawable_height;
                dead = false;
              }

let ensure_live operation value =
  if value.dead then error operation Ogpu.Error.Stale_handle "runtime is destroyed"
  else Ok ()

let render value draws =
  let operation = "Runtime_next_web.render" in
  match ensure_live operation value with
  | Error _ as error_value -> error_value
  | Ok () ->
      match Scene_execution.render value.renderer draws with
      | Error _ as error_value -> error_value
      | Ok false -> Ok false
      | Ok true ->
          let pitch = value.drawable_width * 4 in
          match Scene_execution.read_pixels value.renderer ~bytes_per_row:pitch with
          | Error _ as error_value -> error_value
          | Ok rgba ->
              let frame : Presenter.frame =
                {
                  rgba;
                  pitch;
                  logical_width = value.logical_width;
                  logical_height = value.logical_height;
                  drawable_width = value.drawable_width;
                  drawable_height = value.drawable_height;
                }
              in
              Result.map_error (presenter_error operation)
                (Presenter.present value.presenter frame)
              |> Result.map (fun () -> true)

let resize value ~logical_width ~logical_height ~drawable_width
    ~drawable_height =
  let operation = "Runtime_next_web.resize" in
  match ensure_live operation value with
  | Error _ as error_value -> error_value
  | Ok () ->
      if
        not
          (valid_dimensions ~logical_width ~logical_height ~drawable_width
             ~drawable_height)
      then error operation Ogpu.Error.Invalid_argument "dimensions must be positive"
      else
        match
          Scene_execution.resize value.renderer
            (configuration ~logical_width ~logical_height ~drawable_width
               ~drawable_height)
        with
        | Error _ as error_value -> error_value
        | Ok () ->
            value.logical_width <- logical_width;
            value.logical_height <- logical_height;
            value.drawable_width <- drawable_width;
            value.drawable_height <- drawable_height;
            Ok ()

let stats value = Presenter.stats value.presenter
let port value = Presenter.port value.presenter
let set_text_input_regions value regions =
  let operation = "Runtime_next_web.set_text_input_regions" in
  match ensure_live operation value with
  | Error _ as error_value -> error_value
  | Ok () ->
      Result.map_error (presenter_error operation)
        (Presenter.set_text_input_regions value.presenter regions)
let text_input_regions value = Presenter.text_input_regions value.presenter
let read_pixels value ~bytes_per_row =
  match ensure_live "Runtime_next_web.read_pixels" value with
  | Error _ as error_value -> error_value
  | Ok () -> Scene_execution.read_pixels value.renderer ~bytes_per_row
let backend_live_counts value = Ogpu_raster2.live_counts value.control
let backend_trace_stats value = Ogpu_raster2.trace_stats value.control

let destroy value =
  if value.dead then Ok ()
  else begin
    value.dead <- true;
    let renderer_result = Scene_execution.destroy value.renderer in
    Presenter.destroy value.presenter;
    renderer_result
  end
