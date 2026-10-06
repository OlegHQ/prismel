type operation = Crease_add | Crease_set | Crease_delete
val crease :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Rdk_core.Edge_group.t ->
  ?operation:operation ->
  ?weight:float ->
  ?add_vertex_color:bool ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, Error.t) result
