type t

val system_default : unit -> (t, Ogpu_core.Error.t) result
val of_metal_error : operation:string -> Metal.error -> Ogpu_core.Error.t
val id : t -> int64
val generation : t -> int64
val capabilities : t -> Ogpu_core.Caps.t
val capability_profile : t -> Ogpu_core.Caps.t
val supports : t -> Ogpu_core.Caps.feature -> (unit,Ogpu_core.Error.t) result
val destroyed : t -> bool
val destroy : t -> (unit, Ogpu_core.Error.t) result

module Private : sig
  val metal : t -> Metal.Device.t
  val handle : t -> Ogpu_core.Handle.device
  val attach_resource : t -> unit
  val detach_resource : t -> unit
end
