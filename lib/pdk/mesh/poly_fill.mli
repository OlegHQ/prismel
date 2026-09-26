type mode = Fill_single_polygon | Fill_triangles | Fill_triangle_fan
val ( let* ) : ('a, 'b) result -> ('a -> ('c, 'b) result) -> ('c, 'b) result
type boundary_plan = {
  source_index : Pdk_core.Topology_index.t;
  source_index_view : Pdk_core.Topology_index.Private.view;
  loop_offsets : int array;
  loop_vertices : int array;
  loop_points : int array;
}
val operation : string
val checked_length : string -> Int64.t -> (int, string) result
val find_root : int array -> int -> int
val union_min : int array -> int -> int -> unit
val plan_boundaries :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?boundary:Pdk_core.Edge_group.t ->
  Pdk_core.Geometry.t -> (boundary_plan, string) result
val safe_component_mean : float array -> int array -> int -> int -> float
val analyze_positions :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  boundary_plan ->
  Pdk_core.Packed.Float3.Private.view ->
  (float array * float array * float array, string) result
val triangulate_loops :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  boundary_plan ->
  Pdk_core.Packed.Float3.Private.view -> (int array, string) result
val map_array :
  ?cancel:Pdk_core.Cancel.t -> grain:int -> int array -> 'a array -> 'a array
type center_map =
    No_centers
  | Point_centers of int
  | Vertex_centers of { vertex_points : int array; first_point : int; }
val center_loop : center_map -> int -> int
val map_float :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  loop_offsets:int array ->
  loop_sources:int array ->
  int array -> center_map -> float array -> float array
val remap_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  point_map:int array ->
  point_centers:center_map ->
  vertex_map:int array ->
  vertex_centers:center_map ->
  primitive_map:int array ->
  loop_offsets:int array ->
  loop_points:int array ->
  loop_vertices:int array ->
  Pdk_core.Attribute.t -> (Pdk_core.Attribute.t, string) result
val remap_group :
  grain:int ->
  source_points:int ->
  source_vertices:int ->
  source_primitives:int ->
  point_map:int array ->
  point_center_base:int option ->
  vertex_map:int array ->
  primitive_map:int array -> Pdk_core.Group.t -> Pdk_core.Group.t
val merge_patch_group :
  Pdk_core.Group.t ->
  Pdk_core.Group.t list -> (Pdk_core.Group.t list, string) result
val target_edge_count :
  cancel:Pdk_core.Cancel.t option ->
  mode:mode ->
  unique_points:bool -> plan:boundary_plan -> triangle_local:int array -> int
val remap_edge_groups :
  ?cancel:Pdk_core.Cancel.t ->
  mode:mode ->
  unique_points:bool ->
  plan:boundary_plan ->
  triangle_local:int array ->
  target_topology:Pdk_core.Topology.t ->
  Pdk_core.Edge_group.t list -> (Pdk_core.Edge_group.t list, 'a) result
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
