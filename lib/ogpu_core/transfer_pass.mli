type buffer
type texture
type origin={x:int;y:int;z:int}
type extent={width:int;height:int;depth:int}
type description=Copy_buffer of int64*int64*int64*int64*int64|Fill_buffer of int64*int64*int64*int|Buffer_to_texture of int64*int64*int64*int64*int64*int*origin*extent|Texture_to_buffer of int64*int*origin*extent*int64*int64*int64*int64|Copy_texture of int64*int*origin*int64*int*origin*extent
type t
val buffer : device:Handle.device -> 'a Handle.t -> Types.buffer_descriptor -> buffer
val texture : device:Handle.device -> 'a Handle.t -> Types.texture_descriptor -> texture
val create : Handle.device -> t
val copy_buffer : t -> src:buffer -> src_offset:int64 -> dst:buffer -> dst_offset:int64 -> length:int64 -> (unit,Error.t) result
val fill_buffer : t -> buffer -> offset:int64 -> length:int64 -> value:int -> (unit,Error.t) result
val buffer_to_texture : t -> src:buffer -> offset:int64 -> bytes_per_row:int64 -> bytes_per_image:int64 -> dst:texture -> mip:int -> origin:origin -> extent:extent -> (unit,Error.t) result
val texture_to_buffer : t -> src:texture -> mip:int -> origin:origin -> extent:extent -> dst:buffer -> offset:int64 -> bytes_per_row:int64 -> bytes_per_image:int64 -> (unit,Error.t) result
val copy_texture : t -> src:texture -> src_mip:int -> src_origin:origin -> dst:texture -> dst_mip:int -> dst_origin:origin -> extent:extent -> (unit,Error.t) result
val finish : t -> (description array,Error.t) result
