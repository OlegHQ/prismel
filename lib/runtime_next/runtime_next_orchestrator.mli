type target = Native | Headless | Web
type t
type web_configuration = { interface:string; port:int; title:string; resizable:bool;
  max_events:int; max_clients:int; max_connections:int; max_message_bytes:int;
  max_queued_event_bytes:int; max_frame_pool_bytes:int; compress_frames:bool }
val default_web_configuration : web_configuration
type configuration = { target:target; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; wap_config:Wap.config option }
type facts = { title:string; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; position:(int*int) option;
  pixel_density:float; display_scale:float; refresh_rate:float option; vsync:bool }
type pacing = { frames:int64; presented:int64; last_presented:bool }
type text_input_region = { x:int; y:int; width:int; height:int; focused:bool }
type mouse_button = Left | Middle | Right | X1 | X2
type web_event = Pointer_moved of int*int | Pointer_pressed of mouse_button*int*int
  | Pointer_released of mouse_button*int*int | Pointer_cancelled of mouse_button
  | Wheel of int*int | Key_pressed of string | Key_released of string
  | Text_input of string | Text_editing of {text:string;start:int;length:int}
  | Resized of int*int | Focus_lost | File_uploaded of {name:string;contents:bytes}
type audio_command = Audio_master_volume of float | Audio_stop_all
  | Audio_sample_play of {asset:string;channel:int;loops:int;volume:float}
  | Audio_sample_volume of {asset:string;volume:float}
  | Audio_sample_stop of int | Audio_sample_pause of int | Audio_sample_resume of int
  | Audio_music_play of {asset:string;loops:int;fade_ms:int}
  | Audio_music_volume of float | Audio_music_pause | Audio_music_resume
  | Audio_music_stop of int | Audio_asset_remove of string
val target_of_string : string -> (target,string) result
val select_with : (string -> string option) -> (target,string) result
val selected : unit -> (target,string) result
val create : configuration -> (t,Ogpu.Error.t) result
val target : t -> target
val is_native : t -> bool
val is_headless : t -> bool
val is_web : t -> bool
val is_displayless : t -> bool
val facts : t -> (facts,Ogpu.Error.t) result
val pacing : t -> (pacing,Ogpu.Error.t) result
val render : t -> Scene_execution.draw list -> (bool,Ogpu.Error.t) result
val resize : t -> logical_width:int -> logical_height:int -> drawable_width:int ->
  drawable_height:int -> (unit,Ogpu.Error.t) result
val capture : t -> bytes_per_row:int -> (bytes,Ogpu.Error.t) result
val set_title : t -> string -> (unit,Ogpu.Error.t) result
val set_position : t -> x:int -> y:int -> (unit,Ogpu.Error.t) result
val center : t -> (unit,Ogpu.Error.t) result
val set_bordered : t -> bool -> (unit,Ogpu.Error.t) result
val set_resizable : t -> bool -> (unit,Ogpu.Error.t) result
val set_always_on_top : t -> bool -> (unit,Ogpu.Error.t) result
val set_fullscreen : t -> bool -> (unit,Ogpu.Error.t) result
val show : t -> (unit,Ogpu.Error.t) result
val hide : t -> (unit,Ogpu.Error.t) result
val minimize : t -> (unit,Ogpu.Error.t) result
val maximize : t -> (unit,Ogpu.Error.t) result
val restore : t -> (unit,Ogpu.Error.t) result
val web_url : t -> (string,Ogpu.Error.t) result
val web_client_count : t -> (int,Ogpu.Error.t) result
val drain_web_events : t -> (web_event list,Ogpu.Error.t) result
val register_web_bytes : t -> ?content_type:string -> bytes -> (string,Ogpu.Error.t) result
val remove_web_asset : t -> string -> (bool,Ogpu.Error.t) result
val send_web_audio : t -> audio_command -> (unit,Ogpu.Error.t) result
val download_web_frame : t -> filename:string -> (unit,Ogpu.Error.t) result
val set_text_input_regions : t -> text_input_region list -> (unit,Ogpu.Error.t) result
val destroy : t -> (unit,Ogpu.Error.t) result
