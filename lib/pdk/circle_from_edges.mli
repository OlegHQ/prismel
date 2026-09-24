val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?radius:float ->
  ?scale:Prismel.Vec3.t ->
  ?output_group:string ->
  Geometry.t ->
  (Geometry.t, string) result
