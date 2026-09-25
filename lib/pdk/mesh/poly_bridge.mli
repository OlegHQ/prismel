type pairing = Bridge_by_order | Bridge_by_centroid

val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  source:Edge_group.t ->
  destination:Edge_group.t ->
  ?pairing:pairing ->
  ?connect_closest_ends:bool ->
  ?minimize:Poly_loft.minimize ->
  ?reverse_source:bool ->
  ?reverse_destination:bool ->
  ?pairing_shift:int ->
  ?divisions:int ->
  ?keep_input:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Geometry.t ->
  (Geometry.t, string) result
