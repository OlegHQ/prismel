type target = Native | Headless | Web
type t
type web_configuration = Runtime_next_web.web_configuration = { interface:string; port:int; title:string; resizable:bool;
  max_events:int; max_clients:int; max_connections:int; max_message_bytes:int;
  max_queued_event_bytes:int; max_frame_pool_bytes:int; compress_frames:bool }
val default_web_configuration : web_configuration
type configuration = { target:target; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int;
  web_configuration:web_configuration option }
type facts = { title:string; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; position:(int*int) option;
  pixel_density:float; display_scale:float; refresh_rate:float option; vsync:bool }
type pacing = { frames:int64; presented:int64; last_presented:bool }
type stats = { frames:int64; presented:int64; logical_draws:int64;
  logical_passes:int64; logical_submissions:int64; uploaded_bytes:int64;
  cache_entries:int; gpu_timing_supported:bool; gpu_duration_seconds:float;
  gpu_sample_count:int64; retained_plan_builds:int64; retained_plan_hits:int64;
  retained_plan_misses:int64; retained_plan_evictions:int64;
  retained_plan_executions:int64; retained_plan_entries:int;
  retained_plan_capacity:int }
type diagnostics = { active:bool; cache_entries:int;
  release_queue_pending:int option; release_queue_live_handles:int option;
  release_queue_total_created:int64 option;
  release_queue_total_released:int64 option }
type family = Scene2 | Scene2_textured | Scene3 | Scene3_textured | Scene3_shadow |
  Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil
type blend = Replace | Alpha | Add | Multiply | Screen | Subtract
type prepared = {
  family : family;
  blend : blend;
  texture : Scene_execution.sampled_texture option;
  auxiliary : Scene_execution.auxiliary_resource option;
  samples : int;
  draw : Scene_execution.draw;
}
type text_input_region = Runtime_next_web.text_input_region = { x:int; y:int; width:int; height:int; focused:bool }
type mouse_button = Runtime_next_web.mouse_button = Left | Middle | Right | X1 | X2
type web_event = Runtime_next_web.web_event = Pointer_moved of int*int | Pointer_pressed of mouse_button*int*int
  | Pointer_released of mouse_button*int*int | Pointer_cancelled of mouse_button
  | Wheel of int*int | Key_pressed of string | Key_released of string
  | Text_input of string | Text_editing of {text:string;start:int;length:int}
  | Resized of int*int | Focus_lost | File_uploaded of {name:string;contents:bytes}
type audio_command = Runtime_next_web.audio_command = Audio_master_volume of float | Audio_stop_all
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
val stats : t -> (stats,Ogpu.Error.t) result
val diagnostics : t -> diagnostics
(** Read-only teardown diagnostics.  The release-queue count is available on
    the native Metal target and absent on deterministic targets. *)
val native_release_queue : unit -> (int * int * int64 * int64) option
(** [(pending, live_handles, total_created, total_released)] when the typed
    Metal counter source is available. *)
val render : t -> Scene_execution.draw list -> (bool,Ogpu.Error.t) result
val render_prepared : t -> prepared list -> (bool,Ogpu.Error.t) result
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
val visible : t -> (bool,Ogpu.Error.t) result
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
