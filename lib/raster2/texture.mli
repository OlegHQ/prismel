type t
type color_space=Linear|Srgb
type address=Clamp|Repeat|Mirror
type filter=Nearest|Bilinear|Trilinear
type error=Invalid_size|Invalid_capacity|Capacity_exceeded|Invalid_lod of float|Invalid_coordinate
val create : color_space:color_space -> hard_capacity:int -> Surface.t -> (t,error) result
val create_levels : color_space:color_space -> hard_capacity:int -> Surface.t array -> (t,error) result
val width : t -> int
val height : t -> int
val levels : t -> int
val storage_bytes : t -> int
val level : t -> int -> (Surface.t,error) result
val sample : t -> address_u:address -> address_v:address -> filter:filter -> u:float -> v:float -> lod:float -> (int32,error) result
