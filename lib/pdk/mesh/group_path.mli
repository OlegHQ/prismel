type mode = Through_each | Start_end_pairs
type ending = Stop_at_end | Close_path
exception Invalid of string
val fail : string -> 'a
val byte_count : int -> int
val bit_mem : bytes -> int -> bool
val bit_set : bytes -> int -> unit
val distance : float -> float -> float -> float -> float -> float -> float
val check_positions :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> Pdk_core.Geometry.t -> Pdk_core.Packed.Float3.Private.view
val checked_edge_lengths :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Geometry.t -> Pdk_core.Topology_index.t -> float array
type primitive_graph = {
  topology : Pdk_core.Topology.Private.view;
  index : Pdk_core.Topology_index.Private.view;
}
type graph =
    Point_graph of Pdk_core.Topology_index.Private.view
  | Primitive_graph of primitive_graph
val graph_owner : graph -> Pdk_core.Group.owner
val graph_count : graph -> int
val graph_relation_count : graph -> int
val checked_primitive_lengths :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Geometry.t -> Pdk_core.Topology_index.t -> graph * float array
val validate_group :
  label:string ->
  owner:Pdk_core.Group.owner -> length:int -> Pdk_core.Group.t -> unit
type scratch = {
  depths : int array;
  distances : float array;
  previous : int array;
  queue : int array;
}
val create_scratch : int -> scratch
val find :
  ?cancel:Pdk_core.Cancel.t ->
  scratch:scratch ->
  graph:graph ->
  lengths:float array ->
  allowed:(int -> bool) ->
  used:bytes option ->
  blocked_elements:bytes option ->
  blocked_edges:bytes option ->
  start:int -> finish:int -> unit -> (int array, string) result
val join_contiguous : int array array -> int array
val close :
  ?cancel:Pdk_core.Cancel.t ->
  scratch:scratch ->
  index:Pdk_core.Topology_index.t ->
  graph:graph ->
  lengths:float array ->
  allowed:(int -> bool) ->
  used:bytes option -> int array -> (int array, string) result
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?mode:mode ->
  ?ending:ending ->
  ?avoid_self_intersection:bool ->
  ?collision:Pdk_core.Group.t ->
  ?contain:bool ->
  base:Pdk_core.Group.t ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
