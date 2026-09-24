type sample_position = { x : float; y : float }
type rate_map = { token : int; device : int; screen_width : int; screen_height : int; destroyed : bool }
type attachment_kind = Depth | Stencil
type attachment = { token : int; device : int; kind : attachment_kind; sample_count : int; destroyed : bool }
type t
val callable_ids : string list
val create : available:bool -> device:int -> width:int -> height:int -> sample_count:int -> max_sample_positions:int -> (t, string) result
val set_sample_positions : t -> sample_position array -> (unit, string) result
val sample_positions : t -> sample_position array
val set_rate_map : t -> rate_map option -> (unit, string) result
val rate_map : t -> rate_map option
val set_depth_attachment : t -> attachment option -> (unit, string) result
val set_stencil_attachment : t -> attachment option -> (unit, string) result
val retained_tokens : t -> int list
val reset : t -> unit
val validate_handoff : unit -> unit
