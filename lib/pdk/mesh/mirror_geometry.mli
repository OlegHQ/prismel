val run :
  ?cancel:Cancel.t -> ?grain:int -> ?keep_original:bool ->
  origin:Prismel_math.Vec3.t -> normal:Prismel_math.Vec3.t -> Geometry.t ->
  (Geometry.t, string) result
