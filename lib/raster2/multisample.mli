type t
type compare = Never | Less | Less_equal | Equal | Greater_equal | Greater | Not_equal | Always
type error = Invalid_sample_count of int | Invalid_size | Invalid_pitch | Storage_too_small | Out_of_bounds | Invalid_depth of float | Surface_error
val create : ?pitch:int -> width:int -> height:int -> samples:int -> unit -> (t,error) result
val of_bytes : width:int -> height:int -> samples:int -> pitch:int -> bytes -> (t,error) result
val width : t -> int
val height : t -> int
val samples : t -> int
val pitch : t -> int
val bytes : t -> bytes
val sample_position : samples:int -> int -> ((float * float),error) result
val clear : t -> color:int32 -> depth:float -> (unit,error) result
val test_and_write : t -> compare:compare -> depth_write:bool -> x:int -> y:int -> sample:int -> depth:float -> color:int32 -> (bool,error) result
val get : t -> x:int -> y:int -> sample:int -> ((int32 * float),error) result
val resolve : t -> Surface.t -> (unit,error) result
