type boundary = Smooth_free | Smooth_unshared | Smooth_group_boundary
val fail : string -> string -> ('a, Pdk_core.Error.t) result
val validate_primitive_group :
  Pdk_core.Geometry.t ->
  Pdk_core.Group.t option -> (unit, Pdk_core.Error.t) result
val validate_point_group :
  string ->
  Pdk_core.Geometry.t ->
  Pdk_core.Group.t option -> (unit, Pdk_core.Error.t) result
val point_selected :
  Pdk_core.Topology_index.Private.view ->
  Pdk_core.Group.t option -> int -> bool
val point_on_unshared_edge :
  Pdk_core.Topology_index.Private.view -> int -> bool
val point_on_group_boundary :
  Pdk_core.Topology_index.Private.view -> Pdk_core.Group.t -> int -> bool
val make_update_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  boundary:boundary ->
  index:Pdk_core.Topology_index.t ->
  primitives:Pdk_core.Group.t option ->
  constrained_points:Pdk_core.Group.t option ->
  Pdk_core.Geometry.t -> Pdk_core.Group.t option
val remap_error : Pdk_core.Error.t -> Pdk_core.Error.t
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
