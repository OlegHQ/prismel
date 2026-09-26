val run :
  ?cancel:Cancel.t -> ?grain:int -> Geometry.t -> (Geometry.t, string) result

val run_checked :
  ?cancel:Cancel.t -> ?grain:int -> Geometry.t -> (Geometry.t, Error.t) result
