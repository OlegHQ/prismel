module Presenter = Runtime_wap_raster2_presenter.Wap_raster2_presenter
type web_configuration={interface:string;port:int;title:string;resizable:bool;
  max_events:int;max_clients:int;max_connections:int;max_message_bytes:int;
  max_queued_event_bytes:int;max_frame_pool_bytes:int;compress_frames:bool}
let default_web_configuration=let x=Wap.default_config in {interface=x.interface;port=x.port;
  title=x.title;resizable=x.resizable;max_events=x.max_events;max_clients=x.max_clients;
  max_connections=x.max_connections;max_message_bytes=x.max_message_bytes;
  max_queued_event_bytes=x.max_queued_event_bytes;max_frame_pool_bytes=x.max_frame_pool_bytes;
  compress_frames=x.compress_frames}
type text_input_region={x:int;y:int;width:int;height:int;focused:bool}
type mouse_button=Left|Middle|Right|X1|X2
type web_event=Pointer_moved of int*int|Pointer_pressed of mouse_button*int*int
  |Pointer_released of mouse_button*int*int|Pointer_cancelled of mouse_button|Wheel of int*int
  |Key_pressed of string|Key_released of string|Text_input of string
  |Text_editing of{text:string;start:int;length:int}|Resized of int*int|Focus_lost
  |File_uploaded of{name:string;contents:bytes}
type audio_command=Audio_master_volume of float|Audio_stop_all
  |Audio_sample_play of{asset:string;channel:int;loops:int;volume:float}
  |Audio_sample_volume of{asset:string;volume:float}|Audio_sample_stop of int
  |Audio_sample_pause of int|Audio_sample_resume of int
  |Audio_music_play of{asset:string;loops:int;fade_ms:int}|Audio_music_volume of float
  |Audio_music_pause|Audio_music_resume|Audio_music_stop of int|Audio_asset_remove of string

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
          Scene_execution.create_variants driver
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

let create_configured ?configuration ~logical_width ~logical_height
    ~drawable_width ~drawable_height () =
  let wap_config=Option.map(fun(x:web_configuration)->({Wap.interface=x.interface;
    port=x.port;title=x.title;resizable=x.resizable;max_events=x.max_events;
    max_clients=x.max_clients;max_connections=x.max_connections;
    max_message_bytes=x.max_message_bytes;max_queued_event_bytes=x.max_queued_event_bytes;
    max_frame_pool_bytes=x.max_frame_pool_bytes;compress_frames=x.compress_frames}:Wap.config))configuration in
  create?wap_config~logical_width~logical_height~drawable_width~drawable_height()

let ensure_live operation value =
  if value.dead then error operation Ogpu.Error.Stale_handle "runtime is destroyed"
  else Ok ()

let render_result operation value submit =
  match ensure_live operation value with
  | Error _ as error_value -> error_value
  | Ok () ->
      match submit value.renderer with
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

let render value draws = render_result "Runtime_next_web.render" value
  (fun renderer -> Scene_execution.render renderer draws)

let render_sampled_resources value draws =
  render_result "Runtime_next_web.render_sampled_resources" value
    (fun renderer -> Scene_execution.render_sampled_resources renderer draws)

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
let target_stats value =
  match ensure_live "Runtime_next_web.target_stats" value with
  | Error _ as failure -> failure
  | Ok () -> Ok (Presenter.stats value.presenter)
let port value = Presenter.port value.presenter
let url value =
  match ensure_live "Runtime_next_web.url" value with
  | Error _ as failure -> failure
  | Ok () -> Ok (Presenter.url value.presenter)
let client_count value =
  match ensure_live "Runtime_next_web.client_count" value with
  | Error _ as failure -> failure
  | Ok () -> Ok (Presenter.client_count value.presenter)
let set_text_input_regions value regions =
  let operation = "Runtime_next_web.set_text_input_regions" in
  match ensure_live operation value with
  | Error _ as error_value -> error_value
  | Ok () ->
      Result.map_error (presenter_error operation)
        (Presenter.set_text_input_regions value.presenter regions)
let text_input_regions value = Presenter.text_input_regions value.presenter
let register_bytes value ?content_type bytes =
  if value.dead then None else Presenter.register_bytes value.presenter ?content_type bytes
let remove_asset value id = if not value.dead then Presenter.remove_asset value.presenter id
let drain_events value = if value.dead then [] else Presenter.drain_events value.presenter
let register_asset_bytes value ?content_type bytes =
  let operation = "Runtime_next_web.register_asset_bytes" in
  match ensure_live operation value with
  | Error _ as failure -> failure
  | Ok () ->
      (match Presenter.register_bytes value.presenter ?content_type bytes with
       | Some id -> Ok id
       | None -> error operation Ogpu.Error.Invalid_argument
           "asset content type or payload is invalid")
let remove_asset_checked value id =
  let operation = "Runtime_next_web.remove_asset_checked" in
  match ensure_live operation value with
  | Error _ as failure -> failure
  | Ok () -> Ok (Presenter.remove_asset_checked value.presenter id)
let drain_events_ordered value =
  match ensure_live "Runtime_next_web.drain_events_ordered" value with
  | Error _ as failure -> failure
  | Ok () -> Ok (Presenter.drain_events value.presenter)
let send_audio value command =
  let operation = "Runtime_next_web.send_audio" in
  match ensure_live operation value with
  | Error _ as failure -> failure
  | Ok () ->
      Result.map_error
        (fun message -> Ogpu.Error.make operation Ogpu.Error.Invalid_argument message)
        (Presenter.send_audio value.presenter command)
let download_frame value ~filename =
  let operation = "Runtime_next_web.download_frame" in
  match ensure_live operation value with
  | Error _ as failure -> failure
  | Ok () ->
      Result.map_error
        (fun message -> Ogpu.Error.make operation Ogpu.Error.Invalid_state message)
        (Presenter.download_frame value.presenter ~filename)
let button=function Wap.Left->Left|Middle->Middle|Right->Right|X1->X1|X2->X2
let typed_event=function Wap.Pointer_moved(x,y)->Pointer_moved(x,y)
  |Pointer_pressed(b,x,y)->Pointer_pressed(button b,x,y)
  |Pointer_released(b,x,y)->Pointer_released(button b,x,y)
  |Pointer_cancelled b->Pointer_cancelled(button b)|Wheel(x,y)->Wheel(x,y)
  |Key_pressed x->Key_pressed x|Key_released x->Key_released x|Text_input x->Text_input x
  |Text_editing{text;start;length}->Text_editing{text;start;length}|Resized(w,h)->Resized(w,h)
  |Focus_lost->Focus_lost|File_uploaded{name;contents}->File_uploaded{name;contents}
let drain_events_typed value=Result.map(List.map typed_event)(drain_events_ordered value)
let wap_audio=function Audio_master_volume x->Wap.Audio_master_volume x|Audio_stop_all->Audio_stop_all
  |Audio_sample_play{asset;channel;loops;volume}->Wap.Audio_sample_play{asset;channel;loops;volume}
  |Audio_sample_volume{asset;volume}->Wap.Audio_sample_volume{asset;volume}
  |Audio_sample_stop x->Audio_sample_stop x|Audio_sample_pause x->Audio_sample_pause x
  |Audio_sample_resume x->Audio_sample_resume x
  |Audio_music_play{asset;loops;fade_ms}->Wap.Audio_music_play{asset;loops;fade_ms}
  |Audio_music_volume x->Audio_music_volume x|Audio_music_pause->Audio_music_pause
  |Audio_music_resume->Audio_music_resume|Audio_music_stop x->Audio_music_stop x
  |Audio_asset_remove x->Audio_asset_remove x
let send_audio_typed value command=send_audio value(wap_audio command)
let set_regions value regions=set_text_input_regions value(List.map(fun(x:text_input_region)->
  ({Wap.x=x.x;y=x.y;width=x.width;height=x.height;focused=x.focused}:Wap.text_input_region))regions)
let read_pixels value ~bytes_per_row =
  match ensure_live "Runtime_next_web.read_pixels" value with
  | Error _ as error_value -> error_value
  | Ok () -> Scene_execution.read_pixels value.renderer ~bytes_per_row
let backend_live_counts value = Ogpu_raster2.live_counts value.control
let backend_trace_stats value = Ogpu_raster2.trace_stats value.control
let resource_stats value=Scene_execution.upload_bytes value.renderer,Scene_execution.cache_entries value.renderer

let destroy value =
  if value.dead then Ok ()
  else begin
    value.dead <- true;
    let renderer_result = Scene_execution.destroy value.renderer in
    Presenter.destroy value.presenter;
    renderer_result
  end
