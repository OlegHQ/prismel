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
val finite : float -> bool
val owner_name : Pdk_core.Attribute.owner -> string
val max_abs3 : float -> float -> float -> float
val output_owner : style -> Pdk_core.Attribute.owner
val texture_attribute_name : string -> string
val validate_name : string -> string option -> (unit, string) result
val validate_names :
  normal_attribute:String.t ->
  tangent_attribute:String.t option ->
  bitangent_attribute:String.t option -> (unit, string) result
val existing_planes :
  owner:Pdk_core.Attribute.owner ->
  count:int -> string -> Pdk_core.Geometry.t -> (planes, string) result
val scalar2_attribute :
  string -> Pdk_core.Geometry.t -> (scalar2, string) result
val validate_scalar2 : scalar2 -> (unit, string) result
val selected_vertex :
  Deform.selection option ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view -> int -> bool
val normalize_selected :
  orthogonal:bool ->
  left_handed:bool ->
  normal:planes ->
  tangent:planes option ->
  bitangent:planes option ->
  selected:(int -> bool) ->
  count:int ->
  grain:int -> ?cancel:Pdk_core.Cancel.t -> unit -> (unit, string) result
val face_normals :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> Pdk_core.Geometry.t -> (planes, string) result
val point_normals :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> Pdk_core.Geometry.t -> (planes, string) result
val centroids :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> Pdk_core.Geometry.t -> (planes, string) result
val point_style :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  selection:Deform.selection option ->
  orthogonal:bool ->
  left_handed:bool ->
  normal:planes ->
  tangent:planes option ->
  bitangent:planes option ->
  style -> Pdk_core.Geometry.t -> (unit, string) result
val gradient_frames :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  selection:Deform.selection option ->
  compute_bitangent:bool ->
  scalar2 ->
  Pdk_core.Geometry.t ->
  (Pdk_core.Topology_index.t * Pdk_core.Topology_index.Private.view *
   planes * planes option, string)
  result
val vertex_gradient :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  selection:Deform.selection option ->
  orthogonal:bool ->
  left_handed:bool ->
  normal:planes ->
  tangent:planes option ->
  bitangent:planes option ->
  scalar2 -> Pdk_core.Geometry.t -> (unit, string) result
val point_texture :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  selection:Deform.selection option ->
  orthogonal:bool ->
  left_handed:bool ->
  normal:planes ->
  tangent:planes option ->
  bitangent:planes option ->
  scalar2 -> Pdk_core.Geometry.t -> (unit, string) result
val add_attribute :
  Pdk_core.Geometry.t ->
  Pdk_core.Attribute.owner ->
  string -> planes -> (Pdk_core.Geometry.t, string) result
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Deform.selection ->
  ?orthogonal:bool ->
  ?left_handed:bool ->
  ?normal_attribute:String.t ->
  ?tangent_attribute:String.t option ->
  ?bitangent_attribute:String.t option ->
  style -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
