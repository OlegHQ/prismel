(** Packed restricted-source implementation for [Pdk.Ops.duplicate]. *)

val selected :
  ?cancel:Cancel.t -> grain:int -> primitives:Group.t ->
  transforms:Prismel.Mat4.t array -> Geometry.t ->
  (Geometry.t, string) result
(** Append one transformed copy of the selected primitive topology for every
    transform. The original geometry remains an exact prefix. *)

val add_copy_groups :
  ?cancel:Cancel.t -> grain:int -> prefix:string -> preserve:bool ->
  copies:int -> primitives_per_copy:int -> Geometry.t ->
  (Geometry.t, string) result
(** Add one one-based, prefix-named primitive group per appended copy. *)

val validate_copy_groups :
  prefix:string -> copies:int -> primitive_count:int -> (unit, string) result
(** Validate generated-name, count, and packed-payload bounds before geometry
    materialization begins. *)
