type t
type orientation = Top_down | Bottom_up
type format = Rgba | Bgra
type frame
type metrics = { capacity:int; length:int; growths:int }
type error = Invalid_capacity | Size_overflow | Capacity_exceeded
val create : initial_capacity:int -> hard_capacity:int -> (t,error) result
(* The returned frame borrows storage until the next [read] on the same [t]. *)
val read : t -> orientation:orientation -> format:format -> Surface.t -> (frame,error) result
val width : frame -> int
val height : frame -> int
val pitch : frame -> int
val length : frame -> int
val bytes : frame -> bytes
val hash : frame -> int64
val metrics : t -> metrics
