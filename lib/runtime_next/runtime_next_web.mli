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
val port : t -> int
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val backend_live_counts : t -> int * int * int * int * int
val backend_trace_stats : t -> int * int
val destroy : t -> (unit, Ogpu.Error.t) result
