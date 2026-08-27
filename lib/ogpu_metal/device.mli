type t

val system_default : unit -> (t, Ogpu.Error.t) result
val id : t -> int64
val generation : t -> int64
val capabilities : t -> Ogpu.Capabilities.t
val capability_profile : t -> Adapter.profile
val supports : t -> Adapter.operation -> (unit,Ogpu.Error.t) result
val destroyed : t -> bool
val destroy : t -> (unit, Ogpu.Error.t) result

module Private : sig
  val metal : t -> Metal.Device.t
  val handle : t -> Ogpu.Handle.device
  val attach_resource : t -> unit
  val detach_resource : t -> unit
end
