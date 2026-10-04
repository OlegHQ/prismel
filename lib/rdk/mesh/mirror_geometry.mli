val run :
  ?cancel:Cancel.t -> ?grain:int -> ?keep_original:bool ->
  origin:Rays_math.Vec3.t -> normal:Rays_math.Vec3.t -> Geometry.t ->
  (Geometry.t, Error.t) result
