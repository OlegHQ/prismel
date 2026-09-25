type method_ = Ray_minimum_distance | Ray_project
type direction =
    Ray_vector of Prismel_math.Vec3.t
  | Ray_normal
  | Ray_attribute of string
type direction_mode =
  Pdk_spatial.Surface_index.ray_direction_mode =
    Ray_forward
  | Ray_reverse
  | Ray_bidirectional_closest
  | Ray_bidirectional_farthest
type surface_hit =
  Pdk_spatial.Surface_index.ray_surface_hit =
    Ray_first_surface
  | Ray_last_surface
type combine = Ray_average | Ray_median | Ray_shortest | Ray_longest
exception Ray_error of string * string
exception Ray_pdk_error of Pdk_core.Error.t
val fail : string -> string -> 'a
val get_string : ('a, string) result -> 'a
val get_pdk : ('a, Pdk_core.Error.t) result -> 'a
val finite : float -> bool
val validate_name : string -> string option -> unit
val unique_attribute_name :
  Pdk_core.Geometry.t ->
  Pdk_core.Geometry.t -> String.t list -> String.t -> String.t
val point_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Geometry.t ->
  Deform.selection option -> Pdk_core.Group.t option
val direction_planes :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Geometry.t ->
  direction -> Pdk_spatial.Surface_index.Private.ray_directions
val existing_point_float :
  string -> int -> Pdk_core.Geometry.t -> float -> float array
val existing_point_int :
  string -> int -> Pdk_core.Geometry.t -> int -> int array
val existing_point_float3 :
  string ->
  int -> Pdk_core.Geometry.t -> float array * float array * float array
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Deform.selection ->
  ?collision_primitives:Pdk_core.Group.t ->
  ?method_:method_ ->
  ?direction:direction ->
  ?direction_mode:direction_mode ->
  ?surface_hit:surface_hit ->
  ?samples:int ->
  ?jitter_scale:float ->
  ?seed:int ->
  ?combine:combine ->
  ?min_distance:float ->
  ?max_distance:float ->
  ?tolerance:float ->
  ?scale:float ->
  ?lift:float ->
  ?distance_attribute:String.t ->
  ?primitive_attribute:String.t ->
  ?source_vertex_numbers_attribute:String.t ->
  ?source_vertex_weights_attribute:String.t ->
  ?hit_group:string ->
  ?normal_attribute:String.t ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  ?match_groups:bool ->
  source:Pdk_core.Geometry.t ->
  collision:Pdk_core.Geometry.t ->
  unit -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
