(** Checked packed curve topology operations. *)

type centroid_piece_owner =
  | Centroid_piece_points
  | Centroid_piece_primitives

type centroid_run_over =
  | Centroid_detail
  | Centroid_primitives
  | Centroid_pieces of {
      owner : centroid_piece_owner;
      attribute : string;
    }

type centroid_method =
  | Centroid_point_mass
  | Centroid_bounding_box
  | Centroid_convex_hull

val extract_centroid :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?run_over:centroid_run_over ->
  ?method_:centroid_method ->
  ?source_primitive_attribute:string ->
  ?piece_output_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result

type extract_curve_cut =
  | Extract_cut_constant of float
  | Extract_cut_primitive_attribute of string

val extract_point_from_curve :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?cut:extract_curve_cut ->
  ?point_attributes:string ->
  ?copy_primitive_attributes:bool ->
  ?primitive_attributes:string ->
  ?curve_u_attribute:string ->
  ?number_cuts_attribute:string ->
  ?curve_number_attribute:string ->
  distance_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
val convert_line :
  ?cancel:Cancel.t -> ?grain:int -> ?edges:Edge_group.t ->
  ?connect_path:bool -> ?maximum_distance:float ->
  ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool ->
  ?remove_unused_points:bool -> ?length_attribute:string -> Geometry.t ->
  (Geometry.t, Error.t) result
type curve_end_mode = Open_curve | Close_curve | Unroll_curve

val curve_ends :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> curve_end_mode ->
  Geometry.t -> (Geometry.t, Error.t) result
type ends_mode =
  | Ends_open
  | Ends_close_straight
  | Ends_unroll_shared
  | Ends_unroll_new

val ends :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> ends_mode ->
  Geometry.t -> (Geometry.t, Error.t) result
type curve_join_end =
  | Join_curve_start
  | Join_curve_end

type curve_join_pick = {
  primitive : int;
  end_ : curve_join_end;
}

val join_curves :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?picked_ends:curve_join_pick array ->
  ?orient_closest:bool -> ?connect_closest_ends:bool ->
  ?only_connected:bool -> ?group_size:int -> ?keep_originals:bool ->
  ?tolerance:float -> ?wrap:bool -> Geometry.t -> (Geometry.t, Error.t) result
val poly_path :
  ?cancel:Cancel.t -> ?grain:int -> ?connect_end_points:bool ->
  ?maximum_distance:float -> ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool -> Geometry.t ->
  (Geometry.t, Error.t) result
