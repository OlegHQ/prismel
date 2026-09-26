type operation = Crease_add | Crease_set | Crease_delete
val run :
  ?cancel:Pdk_core.Cancel.t -> grain:int -> int -> (int -> unit) -> unit
val crease :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?operation:operation ->
  ?weight:float ->
  ?add_vertex_color:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
