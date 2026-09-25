(** Packed instance materialization, duplication, and copy-to-points. *)

type copy_target_owner = Copy_target_points | Copy_target_vertices
  | Copy_target_primitives
type copy_target_operation = Copy_target_nothing | Copy_target_copy
  | Copy_target_add | Copy_target_subtract | Copy_target_multiply
type copy_target_attribute_rule = {
  copy_target_pattern : string;
  copy_target_owner : copy_target_owner;
  copy_target_operation : copy_target_operation;
}

val copy_to_points :
  ?cancel:Cancel.t -> ?grain:int -> ?source_primitives:Group.t ->
  ?target_points:Group.t -> ?piece_attribute:string ->
  ?target_attributes:copy_target_attribute_rule list ->
  source:Geometry.t -> targets:Geometry.t -> unit ->
  (Geometry.t, Error.t) result
(** Copy source geometry once per target point with stable payload ancestry. *)

val materialize_instances :
  ?cancel:Cancel.t -> ?grain:int -> ?apply_transform:bool ->
  transforms:Prismel_math.Mat4.t array -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Materialize transform-major copies with exact topology and group ancestry. *)

val duplicate :
  ?cancel:Cancel.t -> ?grain:int -> ?copies:int -> ?cumulative:bool ->
  ?transform:Prismel_math.Mat4.t -> ?primitives:Group.t ->
  ?copy_group_prefix:string -> ?preserve_groups:bool -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Append transformed copies, optionally restricted to selected primitives. *)

module Private : sig
  val copy_to_points :
    ?cancel:Cancel.t -> ?grain:int -> ?source_primitives:Group.t ->
    ?target_points:Group.t -> ?piece_attribute:string ->
    ?target_attributes:copy_target_attribute_rule list ->
    source:Geometry.t -> targets:Geometry.t -> unit ->
    (Geometry.t, string) result
end
