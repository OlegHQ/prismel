type t
type view
type capture = { width:int; height:int; pitch:int; pixels:bytes; generation:int }
type counters = { targets:int; views:int }
type error = Surface_error | Depth_error | Consumer_error of Consumer.error | Destroyed | Stale_generation | Released_view | Live_views of int
val create : ?depth:bool -> width:int -> height:int -> unit -> (t,error) result
val resize : t -> width:int -> height:int -> (unit,error) result
val view : t -> (view,error) result
val release_view : view -> (unit,error) result
val render : view -> lookup:(int -> Consumer.resource option) -> Render_ir.t -> (unit,error) result
val capture : view -> (capture,error) result
val destroy : t -> (unit,error) result
val counters : unit -> counters
