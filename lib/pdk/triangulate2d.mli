(** Geometry adapter for the shared packed planar Delaunay kernel. *)

type projection =
  | Best_fit
  | Plane_xy
  | Plane_yz
  | Plane_zx
  | Plane of { origin : Prismel.Vec3.t; normal : Prismel.Vec3.t }
  | Point_attribute of string

val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:Element_selection.t ->
  ?constraint_edges:Edge_group.t ->
  ?constraint_primitives:Group.t ->
  ?projection:projection ->
  ?seed:int64 ->
  ?split_crossing_constraints:bool ->
  ?flood_from_hull_boundary:bool ->
  ?remove_outside_constraint_polygons:bool ->
  ?silhouette_constraints:bool ->
  ?remove_outside_silhouette:bool ->
  ?ignore_non_constraint_points:bool ->
  ?remove_duplicate_points:bool ->
  ?refine:bool ->
  ?allow_constraint_splitting:bool ->
  ?minimum_angle:float ->
  ?maximum_area:float ->
  ?target_edge_length:float ->
  ?minimum_edge_length:float ->
  ?maximum_new_points:int ->
  ?regularization_steps:int ->
  ?allow_movement_of_interior_input_points:bool ->
  ?preserve_point_payload:bool ->
  ?split_point_group:string ->
  ?refinement_point_group:string ->
  ?triangle_group:string ->
  ?constraint_group:string ->
  Geometry.t ->
  (Geometry.t, string) result
