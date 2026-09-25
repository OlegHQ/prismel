type operation = Crease_add | Crease_set | Crease_delete
val fail : string -> ('a, string) result
val atomic_min : 'a Atomic.t -> 'a -> unit
val block_count : int -> int -> int
val block_bounds : int -> int -> int -> int * int
val run :
  ?cancel:Pdk_core.Cancel.t -> grain:int -> int -> (int -> unit) -> unit
val validate_edges :
  Pdk_core.Topology.t ->
  int -> Pdk_core.Edge_group.t option -> (unit, string) result
val selected : Pdk_core.Edge_group.t option -> int -> bool
val existing_weights :
  Pdk_core.Geometry.t -> (float array option, string) result
val validate_weights :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> float array -> (unit, string) result
val edge_max :
  Pdk_core.Topology_index.Private.view -> float array -> int -> float
val add_edge_values :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  edges:Pdk_core.Edge_group.t option ->
  Pdk_core.Topology_index.Private.view ->
  float -> float array option -> (float array, string) result
val update_weights :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  edges:Pdk_core.Edge_group.t option ->
  operation:operation ->
  weight:float ->
  Pdk_core.Topology_index.Private.view ->
  float array option -> (float array * bool, string) result
val effective_edge_weights :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Topology_index.Private.view -> float array -> float array
val validate_color :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Packed.Float4.t ->
  (Pdk_core.Packed.Float4.Private.view, string) result
val visualization_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Geometry.t ->
  Pdk_core.Topology.t ->
  Pdk_core.Topology_index.Private.view ->
  float array -> (Pdk_core.Attribute.t option, string) result
val crease :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?operation:operation ->
  ?weight:float ->
  ?add_vertex_color:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
