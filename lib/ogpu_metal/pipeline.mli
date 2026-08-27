type t
type cache

val create_cache : capacity:int -> (cache,Ogpu.Error.t) result
val create_compute : cache -> Device.t -> Ogpu.Pipeline.compute_descriptor -> (t,Ogpu.Error.t) result
val create_render : cache -> Device.t -> Ogpu.Pipeline.render_descriptor -> (t,Ogpu.Error.t) result
val key : t -> string
val label : t -> string option
val device_id : t -> int64
val generation : t -> int64
val destroyed : t -> bool
val validate : Device.t -> t -> (unit,Ogpu.Error.t) result
val cache_length : cache -> int
val cache_keys_lru : cache -> string list
val clear_cache : cache -> unit
val destroy : t -> (unit,Ogpu.Error.t) result

module Private : sig
  type native = Compute of Metal.Compute_pipeline.t | Render of Metal.Render_pipeline.t
  val native : t -> native
end
