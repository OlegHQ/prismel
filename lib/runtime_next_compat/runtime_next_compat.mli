(** SDL2-free staging compatibility facade. *)

type target = Native | Headless | Web
type t
type facts = Runtime_next_orchestrator.facts
type pacing = Runtime_next_orchestrator.pacing
type web_mouse_button = Runtime_next_orchestrator.mouse_button = Left | Middle | Right | X1 | X2
type web_event = Runtime_next_orchestrator.web_event =
  | Pointer_moved of int * int | Pointer_pressed of web_mouse_button * int * int
  | Pointer_released of web_mouse_button * int * int | Pointer_cancelled of web_mouse_button
  | Wheel of int * int | Key_pressed of string | Key_released of string
  | Text_input of string | Text_editing of { text:string; start:int; length:int }
  | Resized of int * int | Focus_lost | File_uploaded of { name:string; contents:bytes }
type text_input_region = Runtime_next_orchestrator.text_input_region =
  { x:int; y:int; width:int; height:int; focused:bool }
type web_audio_command = Runtime_next_orchestrator.audio_command =
  | Audio_master_volume of float | Audio_stop_all
  | Audio_sample_play of {asset:string;channel:int;loops:int;volume:float}
  | Audio_sample_volume of {asset:string;volume:float}
  | Audio_sample_stop of int | Audio_sample_pause of int | Audio_sample_resume of int
  | Audio_music_play of {asset:string;loops:int;fade_ms:int}
  | Audio_music_volume of float | Audio_music_pause | Audio_music_resume
  | Audio_music_stop of int | Audio_asset_remove of string

val start : width:int -> height:int -> title:string -> resizable:bool -> (t,string) result
val stop : t -> unit
val target : t -> target
val selected_target : unit -> (target,string) result
val target_of_string : string -> (target,string) result
val is_headless : unit -> bool
val is_web : unit -> bool
val is_displayless : unit -> bool
val facts : t -> (facts,string) result
val pacing : t -> (pacing,string) result
val render : t -> Scene_execution.draw list -> (bool,string) result
val capture : t -> bytes_per_row:int -> (bytes,string) result
val resize : t -> logical_width:int -> logical_height:int ->
  drawable_width:int -> drawable_height:int -> (unit,string) result
val set_title : t -> string -> (unit,string) result
val set_position : t -> x:int -> y:int -> (unit,string) result
val center : t -> (unit,string) result
val set_bordered : t -> bool -> (unit,string) result
val set_resizable : t -> bool -> (unit,string) result
val set_always_on_top : t -> bool -> (unit,string) result
val set_fullscreen : t -> bool -> (unit,string) result
val show : t -> (unit,string) result
val hide : t -> (unit,string) result
val minimize : t -> (unit,string) result
val maximize : t -> (unit,string) result
val restore : t -> (unit,string) result
val web_url : t -> string option
val web_client_count : t -> int
val web_drawable_size : t -> logical_width:int -> logical_height:int -> int * int
val drain_web_events : t -> web_event list
val register_web_file : t -> ?content_type:string -> string -> string option
val register_web_bytes : t -> ?content_type:string -> bytes -> string option
val remove_web_asset : t -> string -> unit
val send_web_audio : t -> web_audio_command -> unit
val download_web_frame : t -> filename:string -> (unit,string) result
val set_web_text_input_regions : t -> text_input_region list -> unit

(** Public legacy names deliberately omitted because they expose SDL values or
    backend flags. Stable and suitable for the B5 deletion gate. *)
val omitted_raw_api : string list
