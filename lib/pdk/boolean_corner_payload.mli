(** Private point/vertex payload interpolation over exact Boolean ancestry. *)

type point_conflict = Reject | Promote_to_vertex

val copy :
  ?cancel:Cancel.t -> grain:int -> point_conflict:point_conflict ->
  point_tolerance:float ->
  Boolean_extract.ancestry -> Geometry.t -> (Geometry.t, Error.t) result
(** Install source point and vertex attributes/groups on a Boolean geometry
    that structurally shares the ancestry topology. Point payload either must
    agree within an explicit non-negative relative/absolute floating tolerance
    at every incident output corner or is explicitly promoted to vertex
    ownership. Discrete payload and groups still require exact agreement. *)
