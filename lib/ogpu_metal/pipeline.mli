type t
type cache

val create_cache : capacity:int -> (cache,Ogpu.Error.t) result
val create_compute : cache -> Device.t -> Ogpu.Pipeline.compute_descriptor -> (t,Ogpu.Error.t) result
val create_render : ?blend:Ogpu.Pipeline.blend -> cache -> Device.t -> Ogpu.Pipeline.render_descriptor -> (t,Ogpu.Error.t) result
val create_compute_runtime_msl : cache -> Device.t -> Ogpu.Pipeline.compute_descriptor -> (t,Ogpu.Error.t) result
val create_render_runtime_msl : ?blend:Ogpu.Pipeline.blend -> cache -> Device.t -> Ogpu.Pipeline.render_descriptor -> (t,Ogpu.Error.t) result
val create_render_argument_buffer : ?blend:Ogpu.Pipeline.blend -> cache -> Device.t -> Ogpu.Pipeline.render_descriptor -> (t,Ogpu.Error.t) result
val create_compute_offline : cache -> Device.t -> Shader_artifact.t -> Ogpu.Pipeline.compute_descriptor -> (t,Ogpu.Error.t) result
val create_render_offline : ?blend:Ogpu.Pipeline.blend -> cache -> Device.t -> Shader_artifact.t -> Ogpu.Pipeline.render_descriptor -> (t,Ogpu.Error.t) result
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
  val portable : t -> Ogpu.Pipeline.t
  val native_identity : t -> int64 * int64
  val argument_encoder : t -> buffer_index:int64 -> (Metal.Shader_argument_encoder.t,Ogpu.Error.t) result
  val argument_function : t -> Metal.Function.t option
  val retain_submission : t -> (unit,Ogpu.Error.t) result
  val release_submission : t -> unit
end
