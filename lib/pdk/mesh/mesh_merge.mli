val merge : ?cancel:Cancel.t -> ?grain:int -> Geometry.t list ->
  (Geometry.t, string) result
val run : ?cancel:Cancel.t -> ?grain:int -> Geometry.t list ->
  (Geometry.t, Error.t) result
