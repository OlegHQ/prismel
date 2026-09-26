type boundary = Smooth_free | Smooth_unshared | Smooth_group_boundary
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  ?constrained_points:Pdk_core.Group.t ->
  ?boundary:boundary ->
  ?iterations:int ->
  ?method_:Pdk_attrib.Attribute_ops.blur_method ->
  ?mode:Pdk_attrib.Attribute_ops.blur_mode ->
  ?weight_attribute:string ->
  ?alpha_attribute:string ->
  ?recompute_normals:bool ->
  ?original_blend:float ->
  ?smoothed_blend:float ->
  attributes:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
