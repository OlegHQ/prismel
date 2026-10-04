val error : string -> ('a, string) result
val run :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Rdk_core.Group.t ->
  ?mask_attribute:string ->
  ?id_attribute:string ->
  ?use_point_scale:bool ->
  seed:Rays_math.Rand.t ->
  scale:float ->
  ?axis_scales:Rays_math.Vec3.t ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, Rdk_core.Error.t) result
