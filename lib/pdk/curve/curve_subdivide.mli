type scheme = Catmull_clark | Bilinear
exception Error of string
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
val iterate :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  independent:bool ->
  scheme -> int -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
