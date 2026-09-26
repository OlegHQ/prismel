type density = {
  density_owner : Pdk_core.Attribute.owner;
  density_attribute : string;
}
val density : owner:Pdk_core.Attribute.owner -> string -> density
type density_values =
    Uniform
  | Point_density of float array
  | Vertex_density of float array
  | Primitive_density of float array
  | Detail_density of float
type vec3_source =
    Point_vec3 of Pdk_core.Packed.Float3.t
  | Vertex_vec3 of Pdk_core.Packed.Float3.t
type vec4_source =
    Point_vec4 of Pdk_core.Packed.Float4.t
  | Vertex_vec4 of Pdk_core.Packed.Float4.t
type plan = {
  triangle_count : int;
  direct_triangles : bool;
  triangle_primitives : int array;
  triangle_a : int array;
  triangle_b : int array;
  triangle_c : int array;
}
val selected : Pdk_core.Group.t option -> int -> bool
val validate_selection :
  Pdk_core.Geometry.t -> Pdk_core.Group.t option -> (unit, string) result
val optional_vec3 :
  Pdk_core.Geometry.t -> string -> (vec3_source option, string) result
val optional_vec4 :
  Pdk_core.Geometry.t -> string -> (vec4_source option, string) result
val resolve_density :
  Pdk_core.Geometry.t ->
  density option -> (density_values * float, string) result
val triangle_primitive : plan -> int -> int
val triangle_vertex :
  Pdk_core.Topology.Private.view -> plan -> int -> int -> int
val create_plan :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (plan, string) result
val coordinate_scale :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Topology.Private.view ->
  plan -> Pdk_core.Packed.Float3.Private.view -> (float, string) result
val varying_density : density_values -> bool
val triangle_distribution :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Topology.Private.view ->
  plan ->
  Pdk_core.Packed.Float3.Private.view ->
  density_values -> float -> float -> (float array * float, string) result
val build_alias : float array -> float -> float array * int array
val mix_index : int -> int
val random_float_into : float array -> int -> int -> int -> int -> unit
val unique_attribute_name :
  Pdk_core.Geometry.t -> String.t list -> String.t -> String.t
val validate_name : string -> string option -> (unit, string) result
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  ?density:density ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  ?match_groups:bool ->
  ?source_primitive_attribute:String.t ->
  ?source_vertex_numbers_attribute:String.t ->
  ?source_vertex_weights_attribute:String.t ->
  count:int ->
  seed:int -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result

val run_checked :
  ?cancel:Pdk_core.Cancel.t -> ?grain:int ->
  ?primitives:Pdk_core.Group.t -> ?density:density ->
  ?point_pattern:string -> ?vertex_pattern:string ->
  ?primitive_pattern:string -> ?detail_pattern:string ->
  ?match_groups:bool -> ?source_primitive_attribute:string ->
  ?source_vertex_numbers_attribute:string ->
  ?source_vertex_weights_attribute:string ->
  count:int -> seed:int -> Pdk_core.Geometry.t ->
  (Pdk_core.Geometry.t, Pdk_core.Error.t) result
