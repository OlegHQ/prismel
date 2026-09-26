type t = {
  point_count : int;
  scale : float;
  scaled_x : float array;
  scaled_y : float array;
  scaled_z : float array;
  triangle_a : int array;
  triangle_b : int array;
  triangle_c : int array;
  double_area : float array;
  cotangent_a : float array;
  cotangent_b : float array;
  cotangent_c : float array;
  point_offsets : int array;
  incidence : int array;
  boundary_points : bytes;
  topology_index : Pdk_core.Topology_index.Private.view;
}
exception Surface_metric_error of string
val create :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> Pdk_core.Geometry.t -> (t, string) result
val mixed_area_contribution :
  double_area:float ->
  cotangent_a:float ->
  cotangent_b:float ->
  cotangent_c:float ->
  corner_cotangent:float ->
  edge_a_squared:float ->
  edge_b_squared:float ->
  cotangent_neighbor_a:float -> cotangent_neighbor_b:float -> float
