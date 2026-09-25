type operation = Dissolve_selected | Dissolve_non_selected
type bridge_policy =
    Create_bridged_polygons
  | Create_disjoint_polygons
  | Delete_bridge_polygons
exception Invalid of string
val fail : string -> 'a
val get_ok : ('a, string) result -> 'a
module Int_buffer :
  sig
    type t = { mutable values : int array; mutable length : int; }
    val create : int -> t
    val ensure : t -> int -> unit
    val add : t -> int -> unit
    val freeze : t -> int array
  end
module Output :
  sig
    type t = {
      points : Int_buffer.t;
      vertices : Int_buffer.t;
      offsets : Int_buffer.t;
      primitives : Int_buffer.t;
      mutable kinds : Pdk_core.Topology.primitive_kind array;
      mutable primitive_count : int;
    }
    val create : int -> int -> t
    val ensure_primitives : t -> int -> unit
    val add :
      t ->
      source:int ->
      kind:Pdk_core.Topology.primitive_kind -> int array -> int array -> unit
    val freeze :
      t ->
      int array * int array * int array * int array *
      Pdk_core.Topology.primitive_kind array
  end
val selected : bytes -> int -> bool
val set_selected : bytes -> int -> unit
val point_of_vertex : Pdk_core.Topology.Private.view -> int -> int
val simplify :
  ?cancel:Pdk_core.Cancel.t ->
  tolerance:float ->
  affected:bytes ->
  closed:bool ->
  Pdk_core.Packed.Float3.Private.view ->
  Pdk_core.Topology.Private.view -> int array -> int array
val rotate : 'a array -> int -> 'a array
val find_point : Pdk_core.Topology.Private.view -> int array -> int -> int
val bridge_loops :
  ?cancel:Pdk_core.Cancel.t ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  bytes -> int array list -> int array
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?operation:operation ->
  ?bridge_policy:bridge_policy ->
  ?remove_inline_points:bool ->
  ?collinearity_tolerance:float ->
  ?remove_unused_points:bool ->
  ?create_boundary_curves:bool ->
  ?recompute_normals:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val run_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?operation:operation ->
  ?bridge_policy:bridge_policy ->
  ?remove_inline_points:bool ->
  ?collinearity_tolerance:float ->
  ?remove_unused_points:bool ->
  ?create_boundary_curves:bool ->
  ?recompute_normals:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
