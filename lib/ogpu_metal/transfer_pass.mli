type t
val buffer : Device.t -> Buffer.t -> (Ogpu_core.Transfer_pass.buffer,Ogpu_core.Error.t) result
val texture : Device.t -> Texture.t -> (Ogpu_core.Transfer_pass.texture,Ogpu_core.Error.t) result
val create : Device.t -> Ogpu_core.Transfer_pass.t -> buffers:Buffer.t list ->
  textures:Texture.t list -> (t,Ogpu_core.Error.t) result
module Private : sig
  val retain : t -> ((unit -> unit) list,Ogpu_core.Error.t) result
  val encode : Metal.Command_buffer.t -> t -> (unit,Ogpu_core.Error.t) result
end
