val run :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> Geometry.t ->
  (Geometry.t, string) result
