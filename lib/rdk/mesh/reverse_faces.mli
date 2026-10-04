type operation = Reverse_vertices | Shift_vertices of int

val run :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?operation:operation -> Geometry.t -> (Geometry.t, Error.t) result
