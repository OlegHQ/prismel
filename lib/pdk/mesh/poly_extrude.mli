type divide = Extrude_individual | Extrude_connected_components
module Int_builder :
  sig
    type t = { mutable values : int array; mutable length : int; }
    val create : int -> t
    val add : t -> int -> int
  end
module Pair_table :
  sig
    type t = {
      mutable components : int array;
      mutable points : int array;
      mutable values : int array;
      mutable size : int;
    }
    val create : int -> t
    val hash : int -> int -> int -> int
    val find : t -> component:int -> point:int -> int
  end
module Edge_lookup = Pdk_core.Topology_edge_lookup
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  ?split_edges:Pdk_core.Edge_group.t ->
  ?divide:divide ->
  ?divisions:int ->
  ?output_front:bool ->
  ?output_back:bool ->
  ?output_side:bool ->
  ?front_group:string ->
  ?back_group:string ->
  ?side_group:string ->
  ?front_boundary_group:string ->
  ?back_boundary_group:string ->
  distance:float ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
