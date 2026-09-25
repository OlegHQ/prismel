(** Shared exact-ancestry remapping for topology-changing PDK kernels. *)

val select :
  ?cancel:Cancel.t -> grain:int -> int array -> 'a array -> 'a array

val select_float :
  ?cancel:Cancel.t -> grain:int -> int array -> float array -> float array

val attribute :
  ?cancel:Cancel.t -> grain:int -> int array -> Attribute.t -> Attribute.t

val drop_point_vertex_normals : (Attribute.owner * string) list

val mapped_attribute :
  ?cancel:Cancel.t -> grain:int -> point_map:int array ->
  vertex_map:int array -> primitive_map:int array ->
  drop:(Attribute.owner * string) list -> Attribute.t ->
  (Attribute.t option, string) result
(** Remap by owner and omit attributes named in [drop]. *)

val group :
  ?cancel:Cancel.t -> grain:int -> int array -> Group.t -> Group.t

val mapped_group :
  ?cancel:Cancel.t -> grain:int -> point_map:int array ->
  vertex_map:int array -> primitive_map:int array -> Group.t -> Group.t

val attributes :
  ?cancel:Cancel.t -> grain:int -> point_map:int array ->
  vertex_map:int array -> primitive_map:int array -> Geometry.t ->
  Attribute.t list

val groups :
  ?cancel:Cancel.t -> grain:int -> point_map:int array -> vertex_map:int array ->
  primitive_map:int array -> Geometry.t -> Group.t list

val edge_groups :
  ?cancel:Cancel.t -> source_topology:Topology.t ->
  target_topology:Topology.t -> point_map:int array -> Edge_group.t list ->
  (Edge_group.t list, string) result

val preserving_points :
  ?cancel:Cancel.t -> grain:int -> topology:Topology.t ->
  vertex_map:int array -> primitive_map:int array -> Geometry.t ->
  (Geometry.t, string) result
(** Install [topology] while sharing positions, point/detail attributes, and
    point groups. Vertex/primitive payload follows exact source ancestry;
    native edge groups follow unchanged point endpoints. *)

val split_point_edge_groups :
  ?cancel:Cancel.t -> grain:int -> source_index:Topology_index.t ->
  target_topology:Topology.t -> Edge_group.t list ->
  (Edge_group.t list, string) result
(** Replicate topology-affine membership when a topology edit changes only
    corner-to-point indices and preserves corner order/cardinality. Every
    target edge records its unique source edge through corresponding source
    corners. The implementation retains a lightweight target endpoint table
    and one integer ancestry plane, not a complete target reverse CSR index. *)
