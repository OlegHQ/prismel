type topology_policy = Destroy_touched_primitives | Heal_primitives
exception Delete_error of string
val get_ok : ('a, string) result -> 'a
val run :
  ?grain:int -> ?cancel:Pdk_core.Cancel.t -> int -> (int -> unit) -> unit
type plan = {
  point_map : int array;
  vertex_map : int array;
  primitive_map : int array;
  topology : Pdk_core.Topology.t;
  healed : bool;
  point_identity : bool;
  unchanged : bool;
}
val primitive_partitions :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  piece_count:int ->
  ?point_pieces:int array ->
  primitive_pieces:int array ->
  Pdk_core.Geometry.t -> Pdk_core.Geometry.t array
val delete :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selected:bool ->
  ?compact_points:bool ->
  ?policy:topology_policy ->
  Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val delete_primitives :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selected:bool ->
  ?compact_points:bool ->
  Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result

val delete_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selected:bool ->
  ?compact_points:bool ->
  ?policy:topology_policy ->
  Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
