type owner = Points | Primitives
type key =
    X
  | Y
  | Z
  | Distance_to of Prismel_math.Vec3.t
  | Along_vector of Prismel_math.Vec3.t
  | Attribute_component of { name : string; component : int; }
  | By_vertex_order
  | By_primitive_index
  | Spatial_locality
  | Random of int64
  | Index_attribute of string
  | Reverse
  | Shift of int
exception Sort_error of string
val get_ok : ('a, string) result -> 'a
val apply_points :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> int array -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val apply_primitives :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> int array -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val sort :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  ?descending:bool ->
  ?output_indices:string ->
  ?combine_indices:bool ->
  owner:owner ->
  key:key -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
