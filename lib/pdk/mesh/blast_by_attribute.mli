type owner = Blast_points | Blast_primitives
type mode =
    Blast_below of float
  | Blast_range of { minimum : float; maximum : float; }
  | Blast_width of { center : float; width : float; }
type output = Blast_delete | Blast_group of string
type classifier = Below of float | Closed of float * float
val fail : string -> ('a, string) result
val group_owner : owner -> Pdk_core.Group.owner
val attribute_owner : owner -> Pdk_core.Attribute.owner
val owner_name : owner -> string
val owner_count : owner -> Pdk_core.Geometry.t -> int
val validate_mode : mode -> (classifier, string) result
val atomic_min : 'a Atomic.t -> 'a -> unit
val validate_base :
  owner:owner ->
  length:int -> Pdk_core.Group.t option -> (unit, string) result
val blast :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?base:Pdk_core.Group.t ->
  ?invert:bool ->
  ?remove_unused_points:bool ->
  owner:owner ->
  attribute:string ->
  mode:mode ->
  output:output ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result

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
