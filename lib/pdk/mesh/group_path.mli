type mode = Through_each | Start_end_pairs
type ending = Stop_at_end | Close_path
exception Invalid of string
type primitive_graph = {
  topology : Pdk_core.Topology.Private.view;
  index : Pdk_core.Topology_index.Private.view;
}
type graph =
    Point_graph of Pdk_core.Topology_index.Private.view
  | Primitive_graph of primitive_graph
type scratch = {
  depths : int array;
  distances : float array;
  previous : int array;
  queue : int array;
}
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
