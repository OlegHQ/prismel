(** A compiled Metal library shared by many pipelines. Runtime MSL and
    precompiled metallib artifacts both load here; pipelines are then created
    per entry point with function constants. *)
type t
val create : ?dynamic:Metal.Dynamic_library.t list -> Device.t -> Ogpu_core.Shader.t -> (t,Ogpu_core.Error.t) result
val compile_native : ?dynamic:Metal.Dynamic_library.t list -> string -> Device.t -> Ogpu_core.Shader.t -> (Metal.Library.t,Ogpu_core.Error.t) result
val validate : Device.t -> t -> (unit,Ogpu_core.Error.t) result
val shader : t -> Ogpu_core.Shader.t
val destroyed : t -> bool
val destroy : t -> (unit,Ogpu_core.Error.t) result
module Private : sig
  val metal : t -> Metal.Library.t
  val dynamic : t -> Metal.Dynamic_library.t list
  val attach_pipeline : t -> unit
  val detach_pipeline : t -> unit
end
