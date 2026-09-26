type keep = Above | Below | All

type selection = Deform.selection =
  | Selected_points of Pdk_core.Group.t
  | Selected_vertices of Pdk_core.Group.t
  | Selected_primitives of Pdk_core.Group.t
  | Selected_edges of Pdk_core.Edge_group.t

val clip_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?keep:keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?clip_attribute:string ->
  ?distance:float ->
  ?selection:selection ->
  ?replace_existing_groups:bool ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  origin:Prismel_math.Vec3.t ->
  normal:Prismel_math.Vec3.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result

val clip_transform_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?keep:keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?clip_attribute:string ->
  ?distance:float ->
  ?selection:selection ->
  ?replace_existing_groups:bool ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  ?local_normal:Prismel_math.Vec3.t ->
  transform:Prismel_math.Mat4.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
