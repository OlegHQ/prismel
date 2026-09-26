type roots = Edge_transport.roots =
  | Transport_first_point
  | Transport_last_point
  | Transport_root_group of Group.t
type operation = Edge_transport.operation =
  | Transport
  | Transport_from_root
  | Transport_total
  | Transport_maximum
  | Transport_minimum
type root_value = Edge_transport.root_value =
  | Transport_root_zero
  | Transport_root_hold
type split = Edge_transport.split = Transport_copy | Transport_split
type normalization = Edge_transport.normalization =
  | Transport_no_normalization
  | Transport_normalize_components
  | Transport_normalize_global
type direction = Edge_transport.direction = Transport_forward | Transport_backward
type merge = Edge_transport.merge =
  | Transport_merge_add
  | Transport_merge_maximum
  | Transport_merge_minimum

val run_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?points:Group.t -> ?roots:roots ->
  ?operation:operation -> ?root_value:root_value ->
  ?integrate_constant:bool -> ?scale_by_edge_length:bool -> ?split:split ->
  ?direction:direction -> ?merge:merge -> ?normalization:normalization ->
  attribute:string -> Geometry.t -> (Geometry.t, Error.t) result

val run_curves_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?owner:Attribute.owner -> ?direction:direction -> ?operation:operation ->
  ?root_value:root_value -> ?integrate_constant:bool ->
  ?scale_by_edge_length:bool -> ?normalization:normalization ->
  attribute:string -> Geometry.t -> (Geometry.t, Error.t) result

val run_parent_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?points:Group.t ->
  ?parent_attribute:string -> ?direction:direction -> ?operation:operation ->
  ?root_value:root_value -> ?integrate_constant:bool ->
  ?scale_by_edge_length:bool -> ?split:split -> ?merge:merge ->
  ?normalization:normalization -> attribute:string -> Geometry.t ->
  (Geometry.t, Error.t) result
