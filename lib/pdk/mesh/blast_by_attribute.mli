type owner = Blast_points | Blast_primitives
type mode =
    Blast_below of float
  | Blast_range of { minimum : float; maximum : float; }
  | Blast_width of { center : float; width : float; }
type output = Blast_delete | Blast_group of string

val blast_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?base:Pdk_core.Group.t ->
  ?invert:bool ->
  ?remove_unused_points:bool ->
  owner:owner ->
  attribute:string ->
  mode:mode ->
  output:output ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
