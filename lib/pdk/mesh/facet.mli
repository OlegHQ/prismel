val max_abs3 : float -> float -> float -> float
val remap_point_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  int array -> Pdk_core.Attribute.t -> (Pdk_core.Attribute.t, string) result
val remap_point_group :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> int array -> Pdk_core.Group.t -> Pdk_core.Group.t
val remap_vertex_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  int array -> Pdk_core.Attribute.t -> (Pdk_core.Attribute.t, string) result
val remap_vertex_group :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> int array -> Pdk_core.Group.t -> Pdk_core.Group.t
val remap_edge_groups_from_index :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  source_index:Pdk_core.Topology_index.t ->
  target_topology:Pdk_core.Topology.t ->
  Pdk_core.Edge_group.t list -> Pdk_core.Edge_group.t list
val remap_edge_groups :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  source_topology:Pdk_core.Topology.t ->
  target_topology:Pdk_core.Topology.t ->
  Pdk_core.Edge_group.t list -> Pdk_core.Edge_group.t list
val remap_healed_edge_groups :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  source_index:Pdk_core.Topology_index.t ->
  target_topology:Pdk_core.Topology.t ->
  vertex_map:int array ->
  Pdk_core.Edge_group.t list -> Pdk_core.Edge_group.t list
val max_abs9 :
  float ->
  float ->
  float -> float -> float -> float -> float -> float -> float -> float
val inline_corner :
  tolerance:float ->
  Pdk_core.Packed.Float3.Private.view ->
  Pdk_core.Topology.Private.view -> int -> int -> int -> int
val remove_inline_points :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  distance:float ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val unique_points_all :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val unique_points_selected :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val unique_points :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val orient_polygons :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val split_points_on_edge_ends :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?primitives:Pdk_core.Group.t ->
  index:Pdk_core.Topology_index.t ->
  split_ends:bytes ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val cusp_polygons :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  angle:float -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val edge_cusp :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?update_point_normals:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val planar_local : float array -> int -> float -> float -> bool -> float
val planar_world : float -> float -> float -> bool -> float
val make_planar :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val validate_normal_view :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Attribute.owner ->
  Pdk_core.Packed.Float3.t ->
  (Pdk_core.Packed.Float3.Private.view, string) result
val scaled_average : float -> float -> float -> float
val consolidate_point_normal :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_spatial.Point_clusters.clusters ->
  Pdk_core.Packed.Float3.Private.view -> Pdk_core.Packed.Float3.t
val consolidate_vertex_normal :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?primitives:Pdk_core.Group.t ->
  Pdk_spatial.Point_clusters.clusters ->
  Pdk_core.Topology_index.Private.view ->
  Pdk_core.Packed.Float3.Private.view -> Pdk_core.Packed.Float3.t
val consolidate_normals :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  distance:float ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val adjust_normal_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?selected:(int -> bool) ->
  unit_length:bool ->
  reverse:bool ->
  Pdk_core.Attribute.t -> (Pdk_core.Attribute.t, string) result
val adjust_normals :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?primitives:Pdk_core.Group.t ->
  unit_length:bool ->
  reverse:bool -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
