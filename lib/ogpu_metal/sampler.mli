type filter = Ogpu.Types.sampler_filter = Nearest | Linear
type mip_filter = Ogpu.Types.mip_filter = No_mip | Nearest_mip | Linear_mip
type address_mode = Ogpu.Types.address_mode = Clamp_to_edge | Repeat | Mirror_repeat
type descriptor = Ogpu.Types.sampler_descriptor
type t
val default : descriptor
val create : Device.t -> descriptor -> (t,Ogpu.Error.t) result
val id : t -> int64
val generation : t -> int64
val device_id : t -> int64
val descriptor : Device.t -> t -> (descriptor,Ogpu.Error.t) result
val destroyed : t -> bool
val destroy : t -> (unit,Ogpu.Error.t) result
module Private : sig val metal:t->Metal.Sampler.t val retain_submission:t->(unit,Ogpu.Error.t)result val release_submission:t->unit end
