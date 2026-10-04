type keep = Above | Below | All

type selection = Deform.selection =
  | Selected_points of Rdk_core.Group.t
  | Selected_vertices of Rdk_core.Group.t
  | Selected_primitives of Rdk_core.Group.t
  | Selected_edges of Rdk_core.Edge_group.t

val clip :
  ?cancel:Rdk_core.Cancel.t ->
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
  origin:Rays_math.Vec3.t ->
  normal:Rays_math.Vec3.t ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, Rdk_core.Error.t) result

val clip_transform :
  ?cancel:Rdk_core.Cancel.t ->
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
  ?local_normal:Rays_math.Vec3.t ->
  transform:Rays_math.Mat4.t ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, Rdk_core.Error.t) result
