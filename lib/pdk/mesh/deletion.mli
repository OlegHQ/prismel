type topology_policy = Destroy_touched_primitives | Heal_primitives
exception Delete_error of string
val fail : string -> 'a
val get_ok : ('a, string) result -> 'a
val run :
  ?grain:int -> ?cancel:Pdk_core.Cancel.t -> int -> (int -> unit) -> unit
val minimum_vertices : Pdk_core.Topology.primitive_kind -> int
val selected : Pdk_core.Group.t -> bool -> int -> bool
type plan = {
  point_map : int array;
  vertex_map : int array;
  primitive_map : int array;
  topology : Pdk_core.Topology.t;
  healed : bool;
  point_identity : bool;
  unchanged : bool;
}
val validate_selection : Pdk_core.Group.t -> Pdk_core.Geometry.t -> unit
val corner_deleted :
  Pdk_core.Group.owner ->
  Pdk_core.Group.t -> bool -> Pdk_core.Topology.Private.view -> int -> bool
val primitive_retained_count :
  Pdk_core.Group.owner ->
  Pdk_core.Group.t ->
  bool -> topology_policy -> Pdk_core.Topology.Private.view -> int -> int
val build_plan :
  ?cancel:Pdk_core.Cancel.t ->
  selected:bool ->
  compact_points:bool ->
  policy:topology_policy -> Pdk_core.Group.t -> Pdk_core.Geometry.t -> plan
val remap_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> Pdk_core.Attribute.t -> Pdk_core.Attribute.t option
val remap_group :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> Pdk_core.Group.t -> Pdk_core.Group.t
val materialize_plan :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?remap_edges:bool -> plan -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val lower_bound : 'a array -> 'a -> int
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
