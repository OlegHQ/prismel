val error : string -> ('a, string) result
val point_float :
  ?missing:bool ->
  string -> Pdk_core.Geometry.t -> (float array option, string) result
val point_int :
  string -> Pdk_core.Geometry.t -> (int array option, string) result
val finite_vec3 : Prismel_math.Vec3.t -> bool
val empty_name : string option -> bool
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Pdk_core.Group.t ->
  ?mask_attribute:string ->
  ?id_attribute:string ->
  ?use_point_scale:bool ->
  seed:Prismel_math.Rand.t ->
  scale:float ->
  axis_scales:Prismel_math.Vec3.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
