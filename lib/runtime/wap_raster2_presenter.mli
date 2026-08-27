type t
type error = Invalid_frame of string | Transport of string | Destroyed
type frame = { rgba:bytes; pitch:int; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int }
val create : ?config:Wap.config -> unit -> (t,error) result
val present : t -> frame -> (unit,error) result
val stats : t -> Wap.stats
val port : t -> int
val url : t -> string
val client_count : t -> int
val set_text_input_regions : t -> Wap.text_input_region list -> (unit,error) result
val text_input_regions : t -> Wap.text_input_region list
val register_bytes : t -> ?content_type:string -> bytes -> string option
val remove_asset : t -> string -> unit
val remove_asset_checked : t -> string -> bool
val drain_events : t -> Wap.event list
val send_audio : t -> Wap.audio_command -> (unit,string) result
val download_frame : t -> filename:string -> (unit,string) result
val destroy : t -> unit
