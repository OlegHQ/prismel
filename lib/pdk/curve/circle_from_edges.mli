val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?radius:float ->
  ?scale:Prismel_math.Vec3.t ->
  ?output_group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
