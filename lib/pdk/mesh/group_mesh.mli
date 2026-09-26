type incidence = Edge_ops.incidence =
  | Any_edge
  | Boundary_edge
  | Manifold_edge
  | Non_manifold_edge

type angle_basis = Edge_ops.angle_basis =
  | Primitive_dihedral
  | Incident_edges

type path_mode = Group_path.mode = Through_each | Start_end_pairs
type path_ending = Group_path.ending = Stop_at_end | Close_path

val group_edges :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?primitives:Pdk_core.Group.t ->
  ?incidence:incidence ->
  ?min_length:float ->
  ?max_length:float ->
  ?angle_basis:angle_basis ->
  ?min_angle:float ->
  ?max_angle:float ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result

val group_find_path :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?mode:path_mode ->
  ?ending:path_ending ->
  ?avoid_self_intersection:bool ->
  ?collision:Pdk_core.Group.t ->
  ?contain:bool ->
  base:Pdk_core.Group.t ->
  name:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
