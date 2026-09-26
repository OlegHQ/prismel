type selection = Transform_ops.deform_selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t
type crease_operation = Crease.operation = Crease_add | Crease_set | Crease_delete

val rewire_vertices_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:selection ->
  ?recursive:bool -> ?delete_target_attribute:bool ->
  ?keep_unused_points:bool -> ?original_point_attribute:string ->
  owner:Attribute.owner -> target_attribute:string -> Geometry.t ->
  (Geometry.t, Error.t) result
val mirror_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?keep_original:bool ->
  origin:Prismel_math.Vec3.t -> normal:Prismel_math.Vec3.t -> Geometry.t ->
  (Geometry.t, Error.t) result
val crease_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?edges:Edge_group.t ->
  ?operation:crease_operation -> ?weight:float -> ?add_vertex_color:bool ->
  Geometry.t -> (Geometry.t, Error.t) result
val convex_hull_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:selection ->
  ?preserve_point_payload:bool -> ?source_point_attribute:string ->
  ?hull_group:string -> Geometry.t -> (Geometry.t, Error.t) result
