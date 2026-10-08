type t

val system_default : unit -> (t, Ogpu_core.Error.t) result
val of_metal_error : operation:string -> Metal.error -> Ogpu_core.Error.t
val id : t -> int64
val capabilities : t -> Ogpu_core.Caps.t
val destroyed : t -> bool
val destroy : t -> (unit, Ogpu_core.Error.t) result

module Private : sig
  val error_kind : operation:string -> source:string -> Metal.error_kind -> Ogpu_core.Error.kind
  val metal : t -> Metal.Device.t
  val handle : t -> Ogpu_core.Handle.device
  val attach_resource : t -> unit
  val detach_resource : t -> unit
end
