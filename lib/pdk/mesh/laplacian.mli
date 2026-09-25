type weighting =
    Laplacian_cotan
  | Laplacian_positive_cotan
  | Laplacian_uniform
exception Laplacian_error of string
val fail : string -> 'a
val finite : float -> bool
type source = { width : int; planes : float array array; }
val source :
  ?cancel:Pdk_core.Cancel.t ->
  String.t -> int -> Pdk_core.Geometry.t -> source
val output_planes :
  string -> int -> int -> Pdk_core.Geometry.t -> float array array
val create_attribute : string -> float array array -> Pdk_core.Attribute.t
val validate_point_group : int -> Pdk_core.Group.t option -> unit
val validate_source : ?cancel:Pdk_core.Cancel.t -> source -> int -> unit
val selected : Pdk_core.Group.t option -> int -> bool
val uniform :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  normalize:bool ->
  points:Pdk_core.Group.t option ->
  source -> float array array -> Pdk_core.Topology_index.Private.view -> unit
val cotan :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  positive:bool ->
  normalize:bool ->
  points:Pdk_core.Group.t option ->
  source -> float array array -> Surface_metric.t -> unit
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Pdk_core.Group.t ->
  ?weighting:weighting ->
  ?normalize:bool ->
  source:String.t ->
  ?output:String.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
