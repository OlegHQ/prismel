type t
type error = Invalid_frame of string | Transport of string | Destroyed
type frame = { rgba:bytes; pitch:int; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int }
val create : ?config:Wap.config -> unit -> (t,error) result
val present : t -> frame -> (unit,error) result
val stats : t -> Wap.stats
val port : t -> int
val set_text_input_regions : t -> Wap.text_input_region list -> (unit,error) result
val text_input_regions : t -> Wap.text_input_region list
val destroy : t -> unit
