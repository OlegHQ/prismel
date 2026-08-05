type end_mode = Open | Close | Close_straight | Unroll | Unroll_new
type cut_mode = Inside | Outside | Inside_and_outside
type parameter_attribute_mode = Replace | Scale

type curve_join_end = Join_curve_start | Join_curve_end

type curve_join_pick = {
  primitive : int;
  end_ : curve_join_end;
}

val interpolate_attribute :
  ?cancel:Cancel.t ->
  ?grain:int ->
  int array -> int array -> float array ->
  int array -> int array -> float array ->
  Attribute.t -> Attribute.t
(** Shared packed linear interpolation for point/vertex topology generators.
    Integer, text, and ragged payload use the nearest endpoint. *)

val convert_line :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?length_attribute:string ->
  Geometry.t ->
  (Geometry.t, string) result
(** Replace each selected unique, non-degenerate topology edge with one open
    two-point polygon curve. Output primitives are ordered lexicographically by
    their canonical point pair. Point/detail attributes, point groups, and
    native edge groups are preserved; vertex/primitive payloads are discarded
    because the output primitives are newly constructed. *)

val with_length_attribute :
  ?cancel:Cancel.t ->
  ?grain:int ->
  name:string ->
  Geometry.t ->
  (Geometry.t, string) result
(** Add a primitive float attribute containing the robust total arc length of
    each polygon curve. Existing topology and payload are shared unchanged. *)

val ends :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?allow_polygons:bool ->
  end_mode ->
  Geometry.t ->
  (Geometry.t, string) result

val join :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?picked_ends:curve_join_pick array ->
  ?orient_closest:bool ->
  ?connect_closest_ends:bool ->
  ?only_connected:bool ->
  ?group_size:int ->
  ?keep_originals:bool ->
  ?tolerance:float ->
  ?wrap:bool ->
  Geometry.t ->
  (Geometry.t, string) result

val carve :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?relative_arc_length:bool ->
  ?first:float ->
  ?last:float ->
  ?first_attribute:string -> ?last_attribute:string ->
  ?attribute_mode:parameter_attribute_mode ->
  ?only_at_breakpoints:bool -> ?cut_at_all_internal_breakpoints:bool ->
  ?divisions:int ->
  ?mode:cut_mode ->
  Geometry.t ->
  (Geometry.t, string) result

val extract_points :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?relative_arc_length:bool -> ?first:float -> ?last:float ->
  ?first_attribute:string -> ?last_attribute:string ->
  ?attribute_mode:parameter_attribute_mode ->
  ?only_at_breakpoints:bool -> ?cut_at_all_internal_breakpoints:bool ->
  ?divisions:int -> ?keep_original:bool -> Geometry.t ->
  (Geometry.t, string) result
