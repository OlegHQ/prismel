type scheme = Subdivide.scheme = Catmull_clark | Loop | Bilinear
type boundary_interpolation = Subdivide.boundary_interpolation =
  | Subdivide_boundary_none
  | Subdivide_boundary_edge_only
  | Subdivide_boundary_edge_and_corner
type face_varying_interpolation = Subdivide.face_varying_interpolation =
  | Subdivide_fvar_none
  | Subdivide_fvar_corners_only
  | Subdivide_fvar_corners_plus1
  | Subdivide_fvar_corners_plus2
  | Subdivide_fvar_boundaries
  | Subdivide_fvar_all
type triangle_policy = Subdivide.triangle_subdivision =
  | Subdivide_triangles_catmull_clark
  | Subdivide_triangles_smooth
type creasing_method = Subdivide.creasing_method =
  | Subdivide_creasing_uniform
  | Subdivide_creasing_chaikin
type crack_policy = Subdivide.crack_policy =
  | Subdivide_do_not_close
  | Subdivide_pull_no_edge_division
  | Subdivide_pull_divide_edges of float
  | Subdivide_pull_triangulate of float
  | Subdivide_stitch_no_edge_division
  | Subdivide_stitch_divide_edges
  | Subdivide_stitch_triangulate

val subdivide_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?scheme:scheme -> ?iterations:int ->
  ?primitives:Group.t -> ?cracks:crack_policy ->
  ?consistent_topology:bool -> ?creases:Geometry.t ->
  ?crease_primitives:Group.t -> ?crease_weight:float ->
  ?generate_resulting_creases:bool -> ?resulting_crease_group:string ->
  ?hole_primitives:Group.t -> ?remove_holes:bool ->
  ?boundary_interpolation:boundary_interpolation ->
  ?face_varying_interpolation:face_varying_interpolation ->
  ?triangle_policy:triangle_policy -> ?creasing_method:creasing_method ->
  ?treat_curves_as_independent:bool -> ?recompute_point_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result
