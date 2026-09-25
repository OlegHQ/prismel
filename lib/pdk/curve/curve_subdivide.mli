type scheme = Catmull_clark | Bilinear
exception Error of string
val fail : string -> 'a
val checked_add : string -> int -> int -> int
val run :
  ?grain:int -> ?cancel:Pdk_core.Cancel.t -> int -> (int -> unit) -> unit
type plan = {
  source : Pdk_core.Geometry.t;
  source_topology : Pdk_core.Topology.Private.view;
  scheme : scheme;
  output_topology : Pdk_core.Topology.t;
  output_index : Pdk_core.Topology_index.t option;
  point_offsets : int array;
  point_sources : int array;
  point_weights : float array;
  point_representative : int array;
  point_old : bytes;
  vertex_left : int array;
  vertex_right : int array;
  vertex_weight : float array;
  vertex_old : bytes;
  primitive_source : int array;
  source_edge_of_output_vertex : int array;
}
val primitive_size : Pdk_core.Topology.Private.view -> int -> int
val validate : ?cancel:Pdk_core.Cancel.t -> Pdk_core.Geometry.t -> unit
val other_endpoint :
  Pdk_core.Topology_index.Private.view -> int -> int -> int
val shared_plan :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  scheme ->
  Pdk_core.Geometry.t ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view -> plan
val independent_plan :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  scheme ->
  Pdk_core.Geometry.t ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view -> plan
val make_plan :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> independent:bool -> scheme -> Pdk_core.Geometry.t -> plan
val point_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> float array -> float array
val vertex_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> float array -> float array
val primitive_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> float array -> float array
val discrete_mapping : plan -> Pdk_core.Attribute.owner -> int array
val discrete :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> Pdk_core.Attribute.owner -> 'a array -> 'a array
val numeric :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  plan -> Pdk_core.Attribute.owner -> float array -> float array
val remap_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> Pdk_core.Attribute.t -> Pdk_core.Attribute.t option
val remap_group :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> Pdk_core.Group.t -> Pdk_core.Group.t
val remap_edge_group :
  ?cancel:Pdk_core.Cancel.t ->
  plan -> Pdk_core.Edge_group.t -> Pdk_core.Edge_group.edge_group
val once :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  independent:bool -> scheme -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val iterate :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  independent:bool ->
  scheme -> int -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
