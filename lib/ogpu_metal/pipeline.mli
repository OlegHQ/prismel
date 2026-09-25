type t
type cache

val create_cache : capacity:int -> (cache,Ogpu_core.Error.t) result
val create_compute : cache -> Device.t -> Ogpu_core.Pipeline.compute_descriptor -> (t,Ogpu_core.Error.t) result
val create_render : ?blend:Ogpu_core.Pipeline.blend -> cache -> Device.t -> Ogpu_core.Pipeline.render_descriptor -> (t,Ogpu_core.Error.t) result
val create_compute_runtime_msl : cache -> Device.t -> Ogpu_core.Pipeline.compute_descriptor -> (t,Ogpu_core.Error.t) result
val create_render_runtime_msl : ?primitive_topology:Metal.Render_pipeline.primitive_topology -> ?blend:Ogpu_core.Pipeline.blend -> cache -> Device.t -> Ogpu_core.Pipeline.render_descriptor -> (t,Ogpu_core.Error.t) result
val create_render_argument_buffer : ?blend:Ogpu_core.Pipeline.blend -> cache -> Device.t -> Ogpu_core.Pipeline.render_descriptor -> (t,Ogpu_core.Error.t) result
val key : t -> string
val label : t -> string option
val device_id : t -> int64
val generation : t -> int64
val destroyed : t -> bool
val validate : Device.t -> t -> (unit,Ogpu_core.Error.t) result
val cache_length : cache -> int
val cache_keys_lru : cache -> string list
val clear_cache : cache -> unit
val destroy : t -> (unit,Ogpu_core.Error.t) result

module Private : sig
  type native = Compute of Metal.Compute_pipeline.t | Render of Metal.Render_pipeline.t
  val native : t -> native
  val portable : t -> Ogpu_core.Pipeline.t
  val native_identity : t -> int64 * int64
  val argument_encoder : t -> buffer_index:int64 -> (Metal.Shader_argument_encoder.t,Ogpu_core.Error.t) result
  val argument_function : t -> Metal.Function.t option
  val retain_submission : t -> (unit,Ogpu_core.Error.t) result
  val release_submission : t -> unit
end
