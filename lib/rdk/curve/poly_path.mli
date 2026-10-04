exception Poly_path_error of string
val run :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Rdk_core.Edge_group.t ->
  ?preserve_source_payload:bool ->
  ?connect_end_points:bool ->
  ?maximum_distance:float ->
  ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result
