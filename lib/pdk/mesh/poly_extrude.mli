type divide = Extrude_individual | Extrude_connected_components
val ( let* ) : ('a, 'b) result -> ('a -> ('c, 'b) result) -> ('c, 'b) result
val finite : float -> bool
module Int_builder :
  sig
    type t = { mutable values : int array; mutable length : int; }
    val create : int -> t
    val add : t -> int -> int
    val freeze : t -> int array
  end
module Pair_table :
  sig
    type t = {
      mutable components : int array;
      mutable points : int array;
      mutable values : int array;
      mutable size : int;
    }
    val capacity : int -> int
    val create : int -> t
    val hash : int -> int -> int -> int
    val slot : int array -> int array -> int -> int -> int
    val insert_raw : t -> int -> int -> int -> unit
    val grow : t -> unit
    val find_or_add : t -> component:int -> point:int -> (unit -> int) -> int
    val find : t -> component:int -> point:int -> int
  end
module Edge_lookup = Pdk_core.Topology_edge_lookup
val validate_selection :
  Pdk_core.Geometry.t -> Pdk_core.Group.t option -> (unit, string) result
val validate_name : string -> string option -> (unit, string) result
val checked_array_length : string -> Int64.t -> (int, string) result
val find_root : int array -> int -> int
val union_roots : int array -> int -> int -> unit
val remap_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  int array ->
  int array ->
  int array ->
  Pdk_core.Attribute.t -> (Pdk_core.Attribute.t option, string) result
val remap_group :
  grain:int ->
  int array -> int array -> int array -> Pdk_core.Group.t -> Pdk_core.Group.t
val merge_group :
  Pdk_core.Group.t ->
  Pdk_core.Group.t list -> (Pdk_core.Group.t list, string) result
val merge_edge_group :
  Pdk_core.Edge_group.t ->
  Pdk_core.Edge_group.t list -> (Pdk_core.Edge_group.t list, string) result
val run_default :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  distance:float ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val run_general :
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
