type t
type web_configuration = { interface:string; port:int; title:string; resizable:bool;
  max_events:int; max_clients:int; max_connections:int; max_message_bytes:int;
  max_queued_event_bytes:int; max_frame_pool_bytes:int; compress_frames:bool }
val default_web_configuration : web_configuration
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

val create :
  ?wap_config:Wap.config ->
  logical_width:int -> logical_height:int ->
  drawable_width:int -> drawable_height:int ->
  unit ->
  (t, Ogpu.Error.t) result
val create_configured : ?configuration:web_configuration ->
  logical_width:int -> logical_height:int -> drawable_width:int ->
  drawable_height:int -> unit -> (t,Ogpu.Error.t) result

val render : t -> Scene_execution.draw list -> (bool, Ogpu.Error.t) result
val render_sampled_resources : t ->
  (Scene_execution.pipeline_family * Ogpu.Pipeline.blend *
   Scene_execution.sampled_texture option * Scene_execution.auxiliary_resource option *
   int * Scene_execution.draw) list -> (bool, Ogpu.Error.t) result

val resize :
  t ->
  logical_width:int -> logical_height:int ->
  drawable_width:int -> drawable_height:int ->
  (unit, Ogpu.Error.t) result

val stats : t -> Wap.stats
val target_stats : t -> (Wap.stats, Ogpu.Error.t) result
val port : t -> int
val url : t -> (string, Ogpu.Error.t) result
val client_count : t -> (int, Ogpu.Error.t) result
val set_text_input_regions : t -> Wap.text_input_region list ->
  (unit, Ogpu.Error.t) result
val text_input_regions : t -> Wap.text_input_region list
val register_bytes : t -> ?content_type:string -> bytes -> string option
val remove_asset : t -> string -> unit
val drain_events : t -> Wap.event list
val register_asset_bytes : t -> ?content_type:string -> bytes ->
  (string, Ogpu.Error.t) result
val remove_asset_checked : t -> string -> (bool, Ogpu.Error.t) result
val drain_events_ordered : t -> (Wap.event list, Ogpu.Error.t) result
val send_audio : t -> Wap.audio_command -> (unit, Ogpu.Error.t) result
val download_frame : t -> filename:string -> (unit, Ogpu.Error.t) result
val set_regions : t -> text_input_region list -> (unit,Ogpu.Error.t) result
val drain_events_typed : t -> (web_event list,Ogpu.Error.t) result
val send_audio_typed : t -> audio_command -> (unit,Ogpu.Error.t) result
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val backend_live_counts : t -> int * int * int * int * int
val backend_trace_stats : t -> int * int
val destroy : t -> (unit, Ogpu.Error.t) result
