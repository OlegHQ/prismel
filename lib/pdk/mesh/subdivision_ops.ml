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

let subdivide_checked ?cancel ?grain ?scheme ?iterations ?primitives ?cracks
    ?consistent_topology ?creases ?crease_primitives ?crease_weight
    ?generate_resulting_creases ?resulting_crease_group ?hole_primitives
    ?remove_holes ?boundary_interpolation ?face_varying_interpolation
    ?triangle_policy ?creasing_method ?treat_curves_as_independent
    ?recompute_point_normals geometry =
  Error.guard ~operation:"subdivide" ~code:"invalid_topology" (fun () ->
    Subdivide.subdivide ?cancel ?grain ?scheme ?iterations ?primitives ?cracks
      ?consistent_topology ?creases ?crease_primitives ?crease_weight
      ?generate_resulting_creases ?resulting_crease_group ?hole_primitives
      ?remove_holes ?boundary_interpolation ?face_varying_interpolation
      ?triangle_subdivision:triangle_policy ?creasing_method
      ?treat_curves_as_independent ?recompute_point_normals geometry)
