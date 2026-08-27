type format = Rgba8_unorm | Bgra8_unorm
type present_mode = Fifo | Immediate
type configuration = { logical_width:int; logical_height:int; physical_width:int; physical_height:int; format:format; present_mode:present_mode; max_acquired:int }
type t
type frame
type acquire_result = Acquired of frame | Timeout | Occluded | Device_lost
type availability = Available | Force_timeout | Force_occluded | Force_device_lost
val create : Handle.device -> configuration -> (t,Error.t) result
val configure : t -> configuration -> (unit,Error.t) result
val resize : t -> logical_width:int -> logical_height:int -> physical_width:int -> physical_height:int -> (unit,Error.t) result
val set_availability : t -> availability -> unit
val acquire : t -> (acquire_result,Error.t) result
val present : t -> frame -> (unit,Error.t) result
val discard : t -> frame -> (unit,Error.t) result
val generation : t -> int64
val outstanding : t -> int
val frame_id : frame -> int64
val destroy : t -> unit
val destroyed : t -> bool
