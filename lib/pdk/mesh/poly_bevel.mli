type shape = Bevel_chamfer | Bevel_round of { convexity : float; }
val ( let* ) : ('a, 'b) result -> ('a -> ('c, 'b) result) -> ('c, 'b) result
val finite : float -> bool
val checked_length : string -> Int64.t -> (int, string) result
val validate_name : string -> string option -> (unit, string) result
val length3 : float -> float -> float -> float
val unit_between :
  Pdk_core.Packed.Float3.Private.view ->
  int -> int -> (float * float * float * float) option
val merge_group :
  Pdk_core.Group.t ->
  Pdk_core.Group.t list -> (Pdk_core.Group.t list, string) result
val merge_edge_group :
  Pdk_core.Edge_group.t ->
  Pdk_core.Edge_group.t list -> (Pdk_core.Edge_group.t list, string) result
val nearest_mapping : 'a array -> 'a array -> float array -> 'a array
val select_array :
  ?cancel:Pdk_core.Cancel.t -> grain:int -> int array -> 'a array -> 'a array
val interpolate_float :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  int array -> int array -> float array -> float array -> float array
val interpolate_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  point_map:int array ->
  vertex_left:int array ->
  vertex_right:int array ->
  vertex_weight:float array ->
  primitive_map:int array ->
  Pdk_core.Attribute.t -> (Pdk_core.Attribute.t option, string) result
val remap_group :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  point_map:int array ->
  vertex_left:int array ->
  vertex_right:int array ->
  vertex_weight:float array ->
  primitive_map:int array -> Pdk_core.Group.t -> Pdk_core.Group.t
val add_empty_outputs :
  grain:int ->
  ?edge_group:string ->
  ?corner_group:string ->
  ?offset_group:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?shape:shape ->
  ?divisions:int ->
  ?point_scale_attribute:string ->
  ?ignore_flat_angle:float ->
  ?clamp_overlap:bool ->
  ?edge_group:string ->
  ?corner_group:string ->
  ?offset_group:string ->
  ?recompute_point_normals:bool ->
  distance:float ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
