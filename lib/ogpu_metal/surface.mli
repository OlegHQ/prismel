type t
type frame
type acquire_result = Acquired of frame | Timeout | Occluded | Device_lost

val create : Device.t -> layer:Metal.Metal_layer.t ->
  Ogpu.Surface.configuration -> (t,Ogpu.Error.t) result
val configure : t -> Ogpu.Surface.configuration -> (unit,Ogpu.Error.t) result
val resize : t -> logical_width:int -> logical_height:int ->
  physical_width:int -> physical_height:int -> (unit,Ogpu.Error.t) result
val set_availability : t -> Ogpu.Surface.availability -> unit
val acquire : t -> (acquire_result,Ogpu.Error.t) result
val frame_id : frame -> int64
val frame_generation : frame -> int64
val frame_texture : frame -> (Metal.Texture.t,Ogpu.Error.t) result
val present : t -> frame -> (unit,Ogpu.Error.t) result
val discard : t -> frame -> (unit,Ogpu.Error.t) result
val generation : t -> int64
val outstanding : t -> int
val destroyed : t -> bool
val destroy : t -> unit
