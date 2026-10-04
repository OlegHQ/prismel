type weighting =
    Laplacian_cotan
  | Laplacian_positive_cotan
  | Laplacian_uniform
exception Laplacian_error of string
type source = { width : int; planes : float array array; }
val run :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Rdk_core.Group.t ->
  ?weighting:weighting ->
  ?normalize:bool ->
  source:String.t ->
  ?output:String.t ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, Error.t) result
