type weighting =
    Laplacian_cotan
  | Laplacian_positive_cotan
  | Laplacian_uniform
exception Laplacian_error of string
type source = { width : int; planes : float array array; }
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Pdk_core.Group.t ->
  ?weighting:weighting ->
  ?normalize:bool ->
  source:String.t ->
  ?output:String.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
