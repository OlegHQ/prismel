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
  seed:int -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Error.t) result
