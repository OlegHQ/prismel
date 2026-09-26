type mode = Fill_single_polygon | Fill_triangles | Fill_triangle_fan
type boundary_plan = {
  source_index : Pdk_core.Topology_index.t;
  source_index_view : Pdk_core.Topology_index.Private.view;
  loop_offsets : int array;
  loop_vertices : int array;
  loop_points : int array;
}
type center_map =
    No_centers
  | Point_centers of int
  | Vertex_centers of { vertex_points : int array; first_point : int; }
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?boundary:Pdk_core.Edge_group.t ->
  ?mode:mode ->
  ?reverse_patches:bool ->
  ?unique_points:bool ->
  ?update_point_normals:bool ->
  ?patch_group:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result

val run_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?boundary:Pdk_core.Edge_group.t ->
  ?mode:mode ->
  ?reverse_patches:bool ->
  ?unique_points:bool ->
  ?update_point_normals:bool ->
  ?patch_group:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
