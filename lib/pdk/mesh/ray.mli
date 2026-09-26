(** Packed projection of selected points onto collision geometry. *)

type method_ = Ray_minimum_distance | Ray_project
type direction =
  | Ray_vector of Prismel_math.Vec3.t
  | Ray_normal
  | Ray_attribute of string
type direction_mode = Pdk_spatial.Surface_index.ray_direction_mode =
  | Ray_forward
  | Ray_reverse
  | Ray_bidirectional_closest
  | Ray_bidirectional_farthest
type surface_hit = Pdk_spatial.Surface_index.ray_surface_hit =
  | Ray_first_surface | Ray_last_surface
type combine = Ray_average | Ray_median | Ray_shortest | Ray_longest

val run :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:Deform.selection ->
  ?collision_primitives:Group.t -> ?method_:method_ -> ?direction:direction ->
  ?direction_mode:direction_mode -> ?surface_hit:surface_hit ->
  ?samples:int -> ?jitter_scale:float -> ?seed:int -> ?combine:combine ->
  ?min_distance:float -> ?max_distance:float -> ?tolerance:float ->
  ?scale:float -> ?lift:float -> ?distance_attribute:string ->
  ?primitive_attribute:string -> ?source_vertex_numbers_attribute:string ->
  ?source_vertex_weights_attribute:string -> ?hit_group:string ->
  ?normal_attribute:string -> ?point_pattern:string ->
  ?vertex_pattern:string -> ?primitive_pattern:string ->
  ?detail_pattern:string -> ?match_groups:bool -> source:Geometry.t ->
  collision:Geometry.t -> unit -> (Geometry.t, Error.t) result
