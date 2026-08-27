type t
type slice
type metrics = { capacity:int; used:int; high_water:int; growths:int }
type error = Invalid_capacity | Invalid_reservation | Capacity_exceeded
val create : initial_capacity:int -> hard_capacity:int -> (t,error) result
val reserve : t -> alignment:int -> length:int -> (slice,error) result
val reset : t -> unit
val metrics : t -> metrics
val slice_offset : slice -> int
val slice_length : slice -> int
val fill : slice -> char -> unit
val set : slice -> int -> char -> (unit,error) result
val get : slice -> int -> (char,error) result
val snapshot : slice -> bytes
