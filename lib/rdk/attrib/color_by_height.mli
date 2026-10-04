(** Create or replace point [Cd] by normalized Y extent. *)
val run :
  ?cancel:Cancel.t -> ?grain:int -> low:(float * float * float * float) ->
  high:(float * float * float * float) -> Geometry.t ->
  (Geometry.t, Error.t) result
