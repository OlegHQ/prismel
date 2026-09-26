type operation = Reverse_faces.operation =
  | Reverse_vertices
  | Shift_vertices of int

val run_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?operation:operation -> Geometry.t -> (Geometry.t, Error.t) result
