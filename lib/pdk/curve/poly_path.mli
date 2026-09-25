exception Poly_path_error of string
val fail : string -> 'a
val finite : float -> bool
val run_ranges : ?grain:int -> int -> (int -> int -> unit) -> unit
val next_power_of_two : int -> int
val hash_pair : int -> int -> int
val remap_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> int array -> Pdk_core.Attribute.t -> Pdk_core.Attribute.t
val set_bit : bytes -> int -> unit
val source_degrees :
  ?edges:Pdk_core.Edge_group.t ->
  Pdk_core.Topology_index.Private.view -> int -> int array
val endpoint_point_map :
  ?cancel:Pdk_core.Cancel.t ->
  ?edges:Pdk_core.Edge_group.t ->
  only_end_points:bool ->
  maximum_distance:float ->
  Pdk_core.Geometry.t ->
  Pdk_core.Topology_index.Private.view -> int array option
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?preserve_source_payload:bool ->
  ?connect_end_points:bool ->
  ?maximum_distance:float ->
  ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
