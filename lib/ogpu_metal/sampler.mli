type filter = Nearest | Linear
type address_mode = Clamp_to_edge | Repeat | Mirror_repeat
type descriptor = { min_filter:filter; mag_filter:filter; address_mode:address_mode; max_anisotropy:int; lod_min:float; lod_max:float; label:string option }
type t
val default : descriptor
val create : Device.t -> descriptor -> (t,Ogpu.Error.t) result
val id : t -> int64
val generation : t -> int64
val device_id : t -> int64
val descriptor : Device.t -> t -> (descriptor,Ogpu.Error.t) result
val destroyed : t -> bool
val destroy : t -> (unit,Ogpu.Error.t) result
