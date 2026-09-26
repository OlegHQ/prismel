type style =
    First_edge
  | Two_edges
  | Primitive_centroid
  | Texture_uv of string
  | Texture_uv_gradient of string
  | Attribute_gradient of string
type planes = { x : float array; y : float array; z : float array; }
type scalar2 = {
  owner : Pdk_core.Attribute.owner;
  u : float array;
  v : float array;
}
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Deform.selection ->
  ?orthogonal:bool ->
  ?left_handed:bool ->
  ?normal_attribute:String.t ->
  ?tangent_attribute:String.t option ->
  ?bitangent_attribute:String.t option ->
  style -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Error.t) result
