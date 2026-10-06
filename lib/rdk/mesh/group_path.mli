type mode = Through_each | Start_end_pairs
type ending = Stop_at_end | Close_path
exception Invalid of string
type primitive_graph = {
  topology : Rdk_core.Topology.Private.view;
  index : Rdk_core.Topology_index.Private.view;
}
type graph =
    Point_graph of Rdk_core.Topology_index.Private.view
  | Primitive_graph of primitive_graph
type scratch = {
  depths : int array;
  distances : float array;
  previous : int array;
  queue : int array;
}
val run :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?mode:mode ->
  ?ending:ending ->
  ?avoid_self_intersection:bool ->
  ?collision:Rdk_core.Group.t ->
  ?contain:bool ->
  base:Rdk_core.Group.t ->
  name:string -> Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, string) result
