type shape = Bevel_chamfer | Bevel_round of { convexity : float; }
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?shape:shape ->
  ?divisions:int ->
  ?point_scale_attribute:string ->
  ?ignore_flat_angle:float ->
  ?clamp_overlap:bool ->
  ?edge_group:string ->
  ?corner_group:string ->
  ?offset_group:string ->
  ?recompute_point_normals:bool ->
  distance:float ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Error.t) result
