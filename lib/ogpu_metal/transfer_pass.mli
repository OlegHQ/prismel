type t
val buffer : Device.t -> Buffer.t -> (Ogpu.Transfer_pass.buffer,Ogpu.Error.t) result
val texture : Device.t -> Texture.t -> (Ogpu.Transfer_pass.texture,Ogpu.Error.t) result
val create : Device.t -> Ogpu.Transfer_pass.t -> buffers:Buffer.t list ->
  textures:Texture.t list -> (t,Ogpu.Error.t) result
module Private : sig
  val retain : t -> ((unit -> unit) list,Ogpu.Error.t) result
  val encode : Metal.Command_buffer.t -> t -> (unit,Ogpu.Error.t) result
end
