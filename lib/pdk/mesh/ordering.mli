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
val fail : string -> 'a
val get_ok : ('a, string) result -> 'a
val count : Pdk_core.Geometry.t -> owner -> int
val group_owner : owner -> Pdk_core.Group.owner
val remap_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  int array ->
  int array -> int array -> Pdk_core.Attribute.t -> Pdk_core.Attribute.t
val remap_group :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  int array -> int array -> int array -> Pdk_core.Group.t -> Pdk_core.Group.t
val apply_points :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> int array -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val apply_primitives :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> int array -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val primitive_centers :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> Pdk_core.Geometry.t -> float array * float array * float array
val finite_vec3 : Prismel_math.Vec3.t -> bool
val point_vertex_order :
  ?cancel:Pdk_core.Cancel.t -> Pdk_core.Geometry.t -> int array
val point_primitive_index :
  ?cancel:Pdk_core.Cancel.t -> Pdk_core.Geometry.t -> int array
val morton_spread : int -> int64
val spatial_locality_values :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> float array -> float array -> float array -> int64 array
val component_values :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner ->
  key ->
  Pdk_core.Geometry.t ->
  [> `Float of float array
   | `Int of int array
   | `Int64 of int64 array
   | `Text of string array ]
val reverse_in_place : 'a array -> unit
val integer_attribute : owner -> string -> Pdk_core.Geometry.t -> int array
val order_from_indices :
  ?selection:'a -> count:int -> sources:int array -> int array -> int array
val install_order : 'a array -> 'a array -> unit
val randomize_in_place :
  ?cancel:Pdk_core.Cancel.t -> int64 -> 'a array -> unit
val sort :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  ?descending:bool ->
  ?output_indices:string ->
  ?combine_indices:bool ->
  owner:owner ->
  key:key -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
