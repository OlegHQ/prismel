exception Poly_path_error of string
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?preserve_source_payload:bool ->
  ?connect_end_points:bool ->
  ?maximum_distance:float ->
  ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
