(** Selected geometric bounds and generated box or sphere surfaces. *)

type deform_selection = Deform.selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t

type bound_shape =
  | Bound_box of { divisions : int * int * int }
  | Bound_sphere of { segments : int; rings : int; minimum_radius : float }

val run_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:deform_selection ->
  ?shape:bound_shape -> ?lower_padding:Prismel_math.Vec3.t ->
  ?upper_padding:Prismel_math.Vec3.t -> ?bounds_group:string ->
  ?center_attribute:string -> ?radii_attribute:string -> Geometry.t ->
  (Geometry.t, Error.t) result

val bounding_box_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?padding:Prismel_math.Vec3.t ->
  Geometry.t -> (Geometry.t, Error.t) result

module Private : sig
  val selected_bounds :
    ?cancel:Cancel.t -> grain:int -> operation:string ->
    deform_selection option -> Geometry.t -> (Analysis.bounds, string) result
end
