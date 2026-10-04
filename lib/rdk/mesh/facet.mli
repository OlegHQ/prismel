val remove_inline_points :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Rdk_core.Group.t ->
  distance:float ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result
val unique_points :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Rdk_core.Group.t ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result
val orient_polygons :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Rdk_core.Group.t ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result
val cusp_polygons :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Rdk_core.Group.t ->
  angle:float -> Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result
val edge_cusp :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Rdk_core.Edge_group.t ->
  ?update_point_normals:bool ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, Error.t) result
val make_planar :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Rdk_core.Group.t ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result
val consolidate_normals :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Rdk_core.Group.t ->
  distance:float ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result
val adjust_normals :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Rdk_core.Group.t ->
  unit_length:bool ->
  reverse:bool -> Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result

val run :
  ?cancel:Cancel.t -> ?grain:int ->
  ?selection:Deform.selection -> ?primitives:Group.t ->
  ?pre_compute_normals:bool -> ?make_normals_unit_length:bool ->
  ?unique_points:bool -> ?consolidate_distance:float ->
  ?consolidate_normals_distance:float -> ?remove_inline_points:bool ->
  ?inline_distance:float -> ?orient_polygons:bool -> ?cusp_angle:float ->
  ?remove_degenerate:bool -> ?make_planar:bool ->
  ?post_compute_normals:bool -> ?reverse_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result
