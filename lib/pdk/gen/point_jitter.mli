val error : string -> ('a, string) result
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Pdk_core.Group.t ->
  ?mask_attribute:string ->
  ?id_attribute:string ->
  ?use_point_scale:bool ->
  seed:Prismel_math.Rand.t ->
  scale:float ->
  ?axis_scales:Prismel_math.Vec3.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
