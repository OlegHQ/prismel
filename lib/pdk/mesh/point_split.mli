(** Split shared points by selected corners and attribute seams. *)

type deform_selection = Deform.selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t

val run_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:deform_selection ->
  ?attributes:string -> ?tolerance:float -> ?promote_attributes:bool ->
  Geometry.t -> (Geometry.t, Error.t) result
