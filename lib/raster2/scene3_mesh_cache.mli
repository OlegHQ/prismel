type key = { id : int64; version : int64; layout : int64 }
type counters = { preparation_bytes : int64; upload_intent_bytes : int64; replacements : int64; evictions : int64 }
type prepared_mesh
type t
type error = Invalid_capacity | Invalid_key | Invalid_mesh | Geometry_error of Scene3.error

val create : capacity:int -> (t, error) result
val prepare : t -> key:key -> topology:Scene3.topology -> vertices:Scene3.vertex array ->
  indices:int array -> (prepared_mesh, error) result
val prepare_view : prepared_mesh -> matrix:float array -> viewport:Scene3.viewport ->
  scissor:Triangle.clip -> (Scene3.prepared, error) result
val invalidate : t -> key -> unit
val invalidate_mesh : t -> id:int64 -> unit
val clear : t -> unit
val length : t -> int
val keys_lru : t -> key list
val counters : t -> counters
