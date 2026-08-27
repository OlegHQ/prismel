type filter = Nearest | Bilinear
type rect = { x:int; y:int; width:int; height:int }
type error = Invalid_extent | Invalid_pitch | Storage_too_small
(** Stored and sampled colors are straight-alpha RGBA. *)
val alpha_mask : dst:Surface.t -> dst_x:int -> dst_y:int -> width:int -> height:int -> pitch:int -> bytes -> color:int32 -> (unit,error) result
val alpha_mask_blend : blend:Composite.blend -> dst:Surface.t -> dst_x:int -> dst_y:int -> width:int -> height:int -> pitch:int -> bytes -> color:int32 -> (unit,error) result
val blit_scaled : src:Surface.t -> src_rect:rect -> dst:Surface.t -> dst_rect:rect -> filter:filter -> (unit,error) result
val blit_scaled_blend : blend:Composite.blend -> src:Surface.t -> src_rect:rect -> dst:Surface.t -> dst_rect:rect -> filter:filter -> (unit,error) result
val blit_affine_blend : blend:Composite.blend -> src:Surface.t -> src_rect:rect -> dst:Surface.t -> dst_rect:rect -> xx:float -> xy:float -> yx:float -> yy:float -> tx:float -> ty:float -> filter:filter -> (unit,error) result
