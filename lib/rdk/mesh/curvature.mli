type boundary = Curvature_boundary_zero | Curvature_boundary_one_sided
type outputs = {
  mean : string option;
  gaussian : string option;
  minimum : string option;
  maximum : string option;
  curvedness : string option;
  shape_index : string option;
}
exception Curvature_error of string
val run :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Rdk_core.Group.t ->
  ?boundary:boundary ->
  ?smoothing_iterations:int ->
  ?smoothing_strength:float ->
  ?outputs:outputs ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, Error.t) result
