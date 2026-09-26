(** Checked triangulation and remeshing operations. *)

type deform_selection = Deform.selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t

val triangulate :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
type triangulate_2d_projection =
  | Triangulate_2d_best_fit
  | Triangulate_2d_xy
  | Triangulate_2d_yz
  | Triangulate_2d_zx
  | Triangulate_2d_plane of {
      origin : Prismel_math.Vec3.t;
      normal : Prismel_math.Vec3.t;
    }
  | Triangulate_2d_point_attribute of string

val triangulate_2d :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?constraint_edges:Edge_group.t ->
  ?constraint_primitives:Group.t ->
  ?projection:triangulate_2d_projection ->
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
  ?restore_original_point_positions:bool ->
  ?keep_primitives:bool ->
  ?remove_unused_points:bool ->
  ?recompute_point_normals:bool ->
  ?split_point_group:string ->
  ?refinement_point_group:string ->
  ?triangle_group:string ->
  ?constraint_group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
val remesh :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?iterations:int ->
  ?smoothing:float ->
  ?project:bool ->
  ?use_input_points_only:bool ->
  ?hard_points:Group.t ->
  ?hard_edges:Edge_group.t ->
  ?target_size_attribute:string ->
  ?preserve_uv_seams:bool ->
  ?uv_attribute:string ->
  ?output_hard_edges:string ->
  ?output_mesh_size:string ->
  ?output_quality:string ->
  ?recompute_point_normals:bool ->
  target_length:float ->
  Geometry.t ->
  (Geometry.t, Error.t) result
