type operation = Dissolve_selected | Dissolve_non_selected
type bridge_policy =
    Create_bridged_polygons
  | Create_disjoint_polygons
  | Delete_bridge_polygons
exception Invalid of string
val get_ok : ('a, string) result -> 'a
module Int_buffer :
  sig
    type t = { mutable values : int array; mutable length : int; }
    val create : int -> t
    val add : t -> int -> unit
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
    val add :
      t ->
      source:int ->
      kind:Pdk_core.Topology.primitive_kind -> int array -> int array -> unit
  end
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
