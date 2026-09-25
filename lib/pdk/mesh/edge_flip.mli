val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?cycles:int ->
  ?cycle_vertex_attributes:bool ->
  ?recompute_point_normals:bool ->
  Geometry.t ->
  (Geometry.t, string) result

val run_checked :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?cycles:int ->
  ?cycle_vertex_attributes:bool ->
  ?recompute_point_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
