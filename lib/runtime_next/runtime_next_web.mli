type t

val create :
  ?wap_config:Wap.config ->
  logical_width:int -> logical_height:int ->
  drawable_width:int -> drawable_height:int ->
  unit ->
  (t, Ogpu.Error.t) result

val render : t -> Scene_execution.draw list -> (bool, Ogpu.Error.t) result

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
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val backend_live_counts : t -> int * int * int * int * int
val backend_trace_stats : t -> int * int
val destroy : t -> (unit, Ogpu.Error.t) result
