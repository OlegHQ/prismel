type piece_owner = Centroid_piece_points | Centroid_piece_primitives

type run_over =
  | Centroid_detail
  | Centroid_primitives
  | Centroid_pieces of { owner : piece_owner; attribute : string }

type method_ = Centroid_point_mass | Centroid_bounding_box | Centroid_convex_hull

val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?run_over:run_over ->
  ?method_:method_ ->
  ?source_primitive_attribute:string ->
  ?piece_output_attribute:string ->
  Geometry.t ->
  (Geometry.t, string) result
