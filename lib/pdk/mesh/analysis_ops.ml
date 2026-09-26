type curvature_boundary = Curvature.boundary =
  | Curvature_boundary_zero
  | Curvature_boundary_one_sided

type curvature_outputs = Curvature.outputs = {
  mean : string option;
  gaussian : string option;
  minimum : string option;
  maximum : string option;
  curvedness : string option;
  shape_index : string option;
}

let default_curvature_outputs = Curvature.default_outputs

type laplacian_weighting = Laplacian.weighting =
  | Laplacian_cotan
  | Laplacian_positive_cotan
  | Laplacian_uniform

type polyframe_style = Polyframe.style =
  | First_edge
  | Two_edges
  | Primitive_centroid
  | Texture_uv of string
  | Texture_uv_gradient of string
  | Attribute_gradient of string

let measure_curvature ?cancel ?grain ?points ?boundary ?smoothing_iterations
    ?smoothing_strength ?outputs geometry =
  Error.guard ~operation:"measure_curvature" ~code:"invalid_curvature" (fun () ->
    Curvature.run ?cancel ?grain ?points ?boundary ?smoothing_iterations
      ?smoothing_strength ?outputs geometry)

let attribute_laplacian ?cancel ?grain ?points ?weighting ?normalize ~source
    ?output geometry =
  Error.guard ~operation:"attribute_laplacian" ~code:"invalid_laplacian" (fun () ->
    Laplacian.run ?cancel ?grain ?points ?weighting ?normalize ~source ?output
      geometry)

let polyframe ?cancel ?grain ?selection ?orthogonal ?left_handed
    ?normal_attribute ?tangent_attribute ?bitangent_attribute style geometry =
  Error.guard ~operation:"polyframe" ~code:"invalid_geometry" (fun () ->
    Polyframe.run ?cancel ?grain ?selection ?orthogonal ?left_handed
      ?normal_attribute ?tangent_attribute ?bitangent_attribute style geometry)
