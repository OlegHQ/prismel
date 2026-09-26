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

val default_curvature_outputs : curvature_outputs

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

val measure_curvature :
  ?cancel:Cancel.t -> ?grain:int -> ?points:Group.t ->
  ?boundary:curvature_boundary -> ?smoothing_iterations:int ->
  ?smoothing_strength:float -> ?outputs:curvature_outputs ->
  Geometry.t -> (Geometry.t, Error.t) result

val attribute_laplacian :
  ?cancel:Cancel.t -> ?grain:int -> ?points:Group.t ->
  ?weighting:laplacian_weighting -> ?normalize:bool -> source:string ->
  ?output:string -> Geometry.t -> (Geometry.t, Error.t) result

val polyframe :
  ?cancel:Cancel.t -> ?grain:int ->
  ?selection:Transform_ops.deform_selection ->
  ?orthogonal:bool -> ?left_handed:bool -> ?normal_attribute:string ->
  ?tangent_attribute:string option -> ?bitangent_attribute:string option ->
  polyframe_style -> Geometry.t -> (Geometry.t, Error.t) result
