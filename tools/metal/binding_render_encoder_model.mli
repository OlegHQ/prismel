type error = Wrong_state | Device_mismatch | Out_of_range | Missing_pipeline
type buffer = { id : int64; device : int64; length : int64 }
type pipeline = { id : int64; device : int64 }
type command
type t

val create : device:int64 -> t
val set_pipeline : t -> pipeline -> (t, error) result
val set_vertex_buffer : t -> index:int -> offset:int64 -> buffer option -> (t, error) result
val set_fragment_buffer : t -> index:int -> offset:int64 -> buffer option -> (t, error) result
val draw : t -> first:int -> count:int -> instances:int -> (t, error) result
val finish : t -> (t, error) result
val retained_resource_count : t -> int
val commands : t -> command list
