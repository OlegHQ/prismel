type target = Target.t = Native | Headless

type web_mouse_button = Left | Middle | Right | X1 | X2

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

type web_audio_command =
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

type t

val start :
  width:int ->
  height:int ->
  title:string ->
  resizable:bool ->
  (t, string) result
(** Configure and initialize SDL_image/SDL_ttf plus the selected presentation
    target. The web target binds its HTTP/WebSocket server to [0.0.0.0].
    [PRISMEL_WEB_MAX_FPS] defaults to 60, [PRISMEL_WEB_MAX_MBIT] defaults to
    a 2 Mbit/s encoded-frame target, and [PRISMEL_WEB_MAX_PIXELS] defaults to
    921600 backing pixels; [PRISMAL_] aliases are accepted. Web viewports are
    authoritative regardless of native resize opt-in. *)

val stop : t -> unit
val target : t -> target
val selected_target : unit -> target
val target_of_string : string -> (target, string) result
val is_headless : unit -> bool
val is_web : unit -> bool
val is_displayless : unit -> bool
val web_url : t -> string option
val web_client_count : t -> int
(* Select bounded backing-pixel dimensions for a logical web viewport. *)
val web_drawable_size :
  t -> logical_width:int -> logical_height:int -> int * int
val drain_web_events : t -> web_event list
val register_web_file : t -> ?content_type:string -> string -> string option
val register_web_bytes : t -> ?content_type:string -> bytes -> string option
val remove_web_asset : t -> string -> unit
val send_web_audio : t -> web_audio_command -> unit
(* Ask the connected browser to download its current canvas as a PNG. *)
val download_web_frame : t -> filename:string -> (unit, string) result
val set_web_text_input_regions :
  t -> text_input_region list -> unit
(** Replace the logical text-input hit regions advertised to browser clients.
    The boolean marks the region that currently owns text focus. *)

val present :
  t ->
  Tsdl.Sdl.renderer ->
  logical_width:int ->
  logical_height:int ->
  (unit, string) result
(** Present one frame through the selected local SDL target. *)

module Private : sig
  val select_target : (string -> string option) -> (target, string) result
  val next_web_deadline :
    previous:float ->
    now:float ->
    frame_interval:float ->
    traffic_interval:float ->
    float
  val fitted_web_drawable_size :
    max_pixels:int -> logical_width:int -> logical_height:int -> int * int
  val idle_frame_interval : float -> int -> float
end
