type layer = { token : int; device : int; destroyed : bool }
type schedule = Immediate | At_time of float | After_minimum_duration of float
type t
val callable_ids : string list
val create : layer:layer -> drawable_id:int -> max_handlers:int -> (t, string) result
val drawable_id : t -> int
val parent_layer : t -> layer
val device : t -> int
val add_presented_handler : t -> (float -> unit) -> (unit, string) result
val present : now:float -> t -> schedule -> (unit, string) result
val mark_presented : t -> time:float -> (unit, string) result
val presented_time : t -> float option
val rooted_handler_count : t -> int
val callback_error_count : t -> int
val destroy : t -> (unit, string) result
val validate_handoff : unit -> unit
