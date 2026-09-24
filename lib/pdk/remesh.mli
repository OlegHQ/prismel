type kernels = {
  triangulate : Geometry.t -> (Geometry.t, string) result;
  collapse : Edge_group.t -> Geometry.t -> (Geometry.t, string) result;
  flip : Edge_group.t -> Geometry.t -> (Geometry.t, string) result;
}

val run :
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
  kernels:kernels ->
  Geometry.t ->
  (Geometry.t, string) result
