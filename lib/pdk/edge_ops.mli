type incidence = Any_edge | Boundary_edge | Manifold_edge | Non_manifold_edge
type angle_basis = Primitive_dihedral | Incident_edges
type equalize_method = Equalize_average | Equalize_longest | Equalize_shortest

val group :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?primitives:Group.t ->
  ?incidence:incidence ->
  ?min_length:float ->
  ?max_length:float ->
  ?angle_basis:angle_basis ->
  ?min_angle:float ->
  ?max_angle:float ->
  Geometry.t ->
  (Geometry.t, string) result

val straighten :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?output_group:string ->
  Geometry.t ->
  (Geometry.t, string) result

val equalize :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?method_:equalize_method ->
  ?iterations:int ->
  ?tolerance:float ->
  ?output_group:string ->
  Geometry.t ->
  (Geometry.t, string) result
