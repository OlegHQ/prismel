type owner = Group_points | Group_vertices | Group_primitives | Group_edges
type promote_mode = Include_any | Include_all | Include_shared_edge
type boundary_attribute = {
  boundary_attribute_owner : Pdk_core.Attribute.owner;
  boundary_attribute_pattern : string;
}
type promote_boundary_options = {
  promote_boundary_attributes : boundary_attribute list;
  promote_boundary_tolerance : float;
  promote_include_unshared_edges : bool;
  promote_include_all_unshared_curve_edges : bool;
  promote_include_all_primitives_sharing_boundary_points : bool;
}
and promote_operation =
    Promote_elements of promote_mode
  | Promote_boundary of promote_boundary_options
and promotion_rule = {
  promotion_source : owner;
  promotion_destination : owner;
  promotion_pattern : string;
  promotion_new_name : string option;
  promotion_keep_original : bool;
  promotion_output_as_attribute : bool;
  promotion_operation : promote_operation;
}
val promotion_rule :
  ?new_name:string ->
  ?keep_original:bool ->
  ?output_as_attribute:bool ->
  ?mode:promote_mode ->
  source:owner ->
  destination:owner -> pattern:string -> unit -> promotion_rule
val boundary_promotion_rule :
  ?new_name:string ->
  ?keep_original:bool ->
  ?output_as_attribute:bool ->
  ?attributes:boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  source:owner ->
  destination:owner -> pattern:string -> unit -> promotion_rule
type primitive_connectivity = Primitive_share_points | Primitive_share_edges
type expand_normal_attribute = {
  expand_normal_owner : Pdk_core.Attribute.owner;
  expand_normal_name : string;
}
type expand_collision = {
  expand_collision_owner : owner;
  expand_collision_group : string;
  expand_collision_contain : bool;
  expand_collision_allow_boundary : bool;
}
type boolean_operation =
    Group_replace
  | Group_union
  | Group_intersection
  | Group_subtract
  | Group_xor
type operand = { pattern : string; inverted : bool; }
type combine_step = { operation : boolean_operation; operand : operand; }
type range =
    Range_start_end of { start : int; end_ : int; }
  | Range_from_ends of { start : int; end_offset : int; }
  | Range_start_length of { start : int; length : int; }
  | Range_partition of { partition : int; partitions : int; }
type range_filter = { select : int; of_ : int; offset : int; }
type range_collision = {
  collision_owner : owner;
  collision_pattern : string;
  keep_boundary : bool;
}
type range_connectivity =
    Range_disconnected of { region : int option; }
  | Range_connected of { connectivity_attributes : string option;
      connectivity_tolerance : float; collision : range_collision option;
      region : int option; remove_other_regions : bool;
    }
type range_rule = {
  range_owner : owner;
  range_name : string;
  range_base : string option;
  range_invert : bool;
  range_filter : range_filter option;
  range_connectivity : range_connectivity option;
  range_merge : boolean_operation;
  range_specification : range;
}
val range_rule :
  ?base:string ->
  ?invert:bool ->
  ?filter:range_filter ->
  ?connectivity:range_connectivity ->
  ?merge:boolean_operation ->
  owner:owner -> name:string -> range -> range_rule
type rename_conflict =
    Rename_skip
  | Rename_error
  | Rename_overwrite
  | Rename_union
type rename_rule = {
  rename_owner : owner option;
  rename_pattern : string;
  rename_replacement : string;
  rename_conflict : rename_conflict;
}
type delete_rule = { delete_owner : owner option; delete_pattern : string; }
type copy_conflict = Copy_skip | Copy_overwrite | Copy_add_suffix
type copy_rule = {
  copy_owner : owner;
  copy_pattern : string;
  copy_prefix : string;
  match_attribute : string option;
}
type transfer_rule = {
  transfer_owner : owner;
  transfer_pattern : string;
  transfer_prefix : string;
}
type name_conflict = Name_replace | Name_union
type invalid_name_policy = Ignore_invalid | Force_valid
type name_overlap = First_group | Last_group | Error_on_overlap
type bounds =
    Bounds_box of { minimum : Prismel_math.Vec3.t;
      maximum : Prismel_math.Vec3.t;
    }
  | Bounds_sphere of { center : Prismel_math.Vec3.t; radius : float; }
type containment = Fully_contained | Partially_contained
type selection =
    Ordinary of Pdk_core.Group.t
  | Native_edges of Pdk_core.Edge_group.t
val byte_count : int -> int
val bit_mem : bytes -> int -> bool
val bit_set : bytes -> int -> unit
val byte_member_bits : int array array
val packed_init :
  ?cancel:Pdk_core.Cancel.t -> grain:int -> int -> (int -> bool) -> bytes
val owner_name : owner -> string
val ordinary_owner : owner -> Pdk_core.Group.owner option
val owner_count :
  Pdk_core.Geometry.t -> Pdk_core.Topology_index.t -> owner -> int
val find_selection :
  owner -> string -> Pdk_core.Geometry.t -> selection option
val selection_mem : selection -> int -> bool
val selection_length : selection -> int
val selection_cardinality : selection -> int
val renamed_selection :
  string ->
  selection -> Pdk_core.Group.t option * Pdk_core.Edge_group.t option
val remove_group :
  owner -> string -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val install_group :
  owner ->
  Pdk_core.Group.t option ->
  Pdk_core.Edge_group.t option ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val promote_predicate :
  source:owner ->
  destination:owner ->
  mode:promote_mode ->
  Pdk_core.Topology.t ->
  Pdk_core.Topology_index.t -> selection -> int -> bool
val promoted_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  source:owner ->
  destination:owner ->
  mode:promote_mode ->
  name:string -> selection -> Pdk_core.Geometry.t -> selection
val promote :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?keep_original:bool ->
  ?output_attribute:string ->
  ?mode:promote_mode ->
  source:owner ->
  destination:owner ->
  group:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
type boundary_storage =
    Boundary_selection of selection
  | Boundary_position of Pdk_core.Packed.Float3.Private.view
  | Boundary_float of float array
  | Boundary_int of int array
  | Boundary_int_array of Pdk_core.Packed.Int_array.Private.view
  | Boundary_float_array of Pdk_core.Packed.Float_array.Private.view
  | Boundary_float2 of Pdk_core.Packed.Float2.Private.view
  | Boundary_float3 of Pdk_core.Packed.Float3.Private.view
  | Boundary_float4 of Pdk_core.Packed.Float4.Private.view
  | Boundary_text of string array
type boundary_plane = {
  boundary_owner : Pdk_core.Attribute.owner;
  boundary_name : string;
  boundary_storage : boundary_storage;
}
val boundary_storage_of_attribute : Pdk_core.Attribute.t -> boundary_storage
val boundary_storage_length : boundary_storage -> int
val boundary_storage_finite : boundary_storage -> int -> bool
val boundary_float_differs : float -> float -> float -> bool
val boundary_storage_differs :
  float -> boundary_storage -> int -> int -> bool
val group_from_attribute_boundary :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?membership_boundary:Pdk_core.Attribute.owner * selection ->
  ?attributes:boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  owner:owner ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val fresh_edge_group_name : Pdk_core.Geometry.t -> string -> string
val ordinary_attribute_owner : owner -> Pdk_core.Attribute.owner
val integer_attribute_of_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  destination:owner ->
  name:string -> selection -> (Pdk_core.Attribute.t, string) result
val promote_boundary_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  attributes:boundary_attribute list ->
  tolerance:float ->
  include_unshared_edges:bool ->
  include_all_unshared_curve_edges:bool ->
  include_all_primitives_sharing_boundary_points:bool ->
  source:owner ->
  destination:owner ->
  output_name:string ->
  selection -> Pdk_core.Geometry.t -> (selection, string) result
val group_promote_boundary :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?keep_original:bool ->
  ?output_attribute:string ->
  ?attributes:boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  source:owner ->
  destination:owner ->
  group:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
type expand_normals = {
  expand_nx : float array;
  expand_ny : float array;
  expand_nz : float array;
  expand_minimum_dot : float;
}
type expand_constraints = {
  expand_seams : Pdk_core.Edge_group.t option;
  expand_containment : selection option;
  expand_collision_boundary : selection option;
  expand_shrink_boundary : selection option;
  expand_normals : expand_normals option;
}
val expand_attribute_owner_count :
  Pdk_core.Geometry.t -> Pdk_core.Attribute.owner -> int
val expand_normal_source :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:owner ->
  normal_attribute:expand_normal_attribute option ->
  Pdk_core.Geometry.t ->
  (Pdk_core.Attribute.owner * Pdk_core.Packed.Float3.Private.view, string)
  result
val expand_normal_planes :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:owner ->
  spread:float ->
  normal_attribute:expand_normal_attribute option ->
  Pdk_core.Geometry.t -> (expand_normals, string) result
val expand_extract_edge_group :
  string -> Pdk_core.Geometry.t -> (Pdk_core.Edge_group.t, string) result
val expand_attribute_edges :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  boundary_attribute list ->
  float ->
  Pdk_core.Geometry.t -> (Pdk_core.Edge_group.t option, string) result
val expand_collision_edges :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  expand_collision ->
  Pdk_core.Geometry.t -> (selection * Pdk_core.Edge_group.t, string) result
val expand_promote_edges :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:owner ->
  name:string -> Pdk_core.Edge_group.t -> Pdk_core.Geometry.t -> selection
val compile_expand_constraints :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:owner ->
  normal_spread:float option ->
  normal_attribute:expand_normal_attribute option ->
  connectivity_attributes:boundary_attribute list ->
  connectivity_tolerance:float ->
  collision:expand_collision option ->
  growing:bool -> Pdk_core.Geometry.t -> (expand_constraints, string) result
val expand_candidate_allowed :
  expand_constraints -> expand_collision option -> int -> bool
val expand_transition_allowed :
  expand_constraints -> int -> int -> int -> bool
val expand_forced_boundary : expand_constraints -> int -> bool
val neighbor_matches :
  owner:owner ->
  primitive_connectivity:primitive_connectivity ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view -> bytes -> bool -> int -> bool
val enqueue_new :
  bytes -> int array -> int ref -> int array option -> int -> int -> unit
val flood_neighbors :
  owner:owner ->
  primitive_connectivity:primitive_connectivity ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  bytes -> int array -> int ref -> int array option -> int -> unit
val flood_bits :
  ?cancel:Pdk_core.Cancel.t ->
  owner:owner ->
  primitive_connectivity:primitive_connectivity ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  int -> bytes -> int array option -> bytes
val stepped_bits :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:owner ->
  primitive_connectivity:primitive_connectivity ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  int -> int -> Bytes.t -> int array option -> Bytes.t
val grow_point_depth_bits :
  ?cancel:Pdk_core.Cancel.t ->
  Pdk_core.Topology_index.Private.view ->
  bytes -> int -> int -> int array option -> bytes
val constrained_neighbor_matches :
  owner:owner ->
  primitive_connectivity:primitive_connectivity ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  expand_constraints -> bytes -> bool -> int -> bool
val constrained_stepped_bits :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:owner ->
  primitive_connectivity:primitive_connectivity ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  expand_constraints ->
  expand_collision option ->
  int -> int -> Bytes.t -> int array option -> Bytes.t
val constrained_enqueue :
  expand_constraints ->
  expand_collision option ->
  bytes ->
  int array -> int ref -> int array option -> int -> int -> int -> unit
val constrained_flood_bits :
  ?cancel:Pdk_core.Cancel.t ->
  owner:owner ->
  primitive_connectivity:primitive_connectivity ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  expand_constraints ->
  expand_collision option -> int -> bytes -> int array option -> bytes
val constrained_grow_point_depth_bits :
  ?cancel:Pdk_core.Cancel.t ->
  Pdk_core.Topology_index.Private.view ->
  expand_constraints ->
  expand_collision option -> bytes -> int -> int -> int array option -> bytes
val expand :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?steps:int ->
  ?flood:bool ->
  ?step_attribute:string ->
  ?primitive_connectivity:primitive_connectivity ->
  ?normal_spread:float ->
  ?normal_attribute:expand_normal_attribute ->
  ?connectivity_attributes:boundary_attribute list ->
  ?connectivity_tolerance:float ->
  ?collision:expand_collision ->
  owner:owner ->
  group:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
type named_entry = {
  owner : owner;
  mutable entry_name : string;
  mutable value : selection;
  mutable alive : bool;
}
type group_store = {
  table : (owner * string, named_entry) Hashtbl.t;
  initial : named_entry array;
  mutable added_rev : named_entry list;
  mutable dirty : bool;
}
val owner_of_group : Pdk_core.Group.owner -> owner
val selection_with_name : string -> selection -> selection
val store_of_geometry : Pdk_core.Geometry.t -> group_store
val store_entries : group_store -> named_entry list
val store_find : group_store -> owner -> string -> named_entry option
val store_remove : group_store -> named_entry -> unit
val store_replace : group_store -> named_entry -> selection -> unit
val store_add : group_store -> owner -> string -> selection -> named_entry
val store_rename : group_store -> named_entry -> string -> selection -> unit
val store_commit :
  group_store -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val validate_promotion_operation : promotion_rule -> (unit, string) result
val promotions :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?max_outputs:int ->
  ?max_payload_bytes:int ->
  promotion_rule list ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result

val promote_checked :
  ?cancel:Pdk_core.Cancel.t -> ?grain:int -> ?name:string ->
  ?keep_original:bool -> ?output_attribute:string -> ?mode:promote_mode ->
  source:owner -> destination:owner -> group:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
val expand_checked :
  ?cancel:Pdk_core.Cancel.t -> ?grain:int -> ?name:string -> ?steps:int ->
  ?flood:bool -> ?step_attribute:string ->
  ?primitive_connectivity:primitive_connectivity -> ?normal_spread:float ->
  ?normal_attribute:expand_normal_attribute ->
  ?connectivity_attributes:boundary_attribute list ->
  ?connectivity_tolerance:float -> ?collision:expand_collision ->
  owner:owner -> group:string -> Pdk_core.Geometry.t ->
  (Pdk_core.Geometry.t, Pdk_core.Error.t) result
val promotions_checked :
  ?cancel:Pdk_core.Cancel.t -> ?grain:int -> ?max_outputs:int ->
  ?max_payload_bytes:int -> rules:promotion_rule list ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
val valid_group_name : string -> bool
val force_valid_group_name : string -> string
val groups_from_name :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?prefix:string ->
  ?conflict:name_conflict ->
  ?invalid_names:invalid_name_policy ->
  ?max_groups:int ->
  ?max_payload_bytes:int ->
  owner:Pdk_core.Attribute.owner ->
  attribute:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
(* Typed boundary with the former Ops error and cancellation behavior. *)
val groups_from_name_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?prefix:string ->
  ?conflict:name_conflict ->
  ?invalid_names:invalid_name_policy ->
  ?max_groups:int ->
  ?max_payload_bytes:int ->
  owner:Pdk_core.Attribute.owner ->
  attribute:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
val name_from_groups :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?attribute:string ->
  ?pattern:string ->
  ?default:string ->
  ?overlap:name_overlap ->
  ?delete_groups:bool ->
  owner:Pdk_core.Attribute.owner ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
(* Typed boundary with the former Ops error and cancellation behavior. *)
val name_from_groups_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?attribute:string ->
  ?pattern:string ->
  ?default:string ->
  ?overlap:name_overlap ->
  ?delete_groups:bool ->
  owner:Pdk_core.Attribute.owner ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
val selection_complement : selection -> selection
val selection_boolean :
  boolean_operation -> selection -> selection -> (selection, string) result
val empty_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> owner -> Pdk_core.Geometry.t -> selection
val publish_merged_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  merge:boolean_operation ->
  owner:owner ->
  name:string ->
  selection -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val unshared_edge_bits :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  surface_only:bool ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view -> bytes
val unshared_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  surface_only:bool ->
  owner:owner -> name:string -> Pdk_core.Geometry.t -> selection
val group_unshared :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?merge:boolean_operation ->
  owner:owner ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val group_boundary_components :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?prefix:string ->
  ?conflict:name_conflict ->
  ?max_groups:int ->
  ?max_payload_bytes:int ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val compile_nonblank :
  string -> string -> (Pdk_core.Attribute_pattern.t, string) result
val resolve_pattern :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  group_store ->
  owner -> string -> Pdk_core.Geometry.t -> (selection, string) result
val mixed_pair_identity : int -> int -> int
val group_edge_depth :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?merge:boolean_operation ->
  depth:int ->
  point_group:string ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val group_random :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?seed:Prismel_math.Rand.t ->
  ?seed_attribute:string ->
  ?base:string ->
  ?merge:boolean_operation ->
  probability:float ->
  owner:owner ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
(* Typed boundary with the former Ops error and cancellation behavior. *)
val group_random_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?seed:Prismel_math.Rand.t ->
  ?seed_attribute:string ->
  ?base:string ->
  ?merge:boolean_operation ->
  probability:float ->
  owner:owner ->
  name:string -> Pdk_core.Geometry.t ->
  (Pdk_core.Geometry.t, Pdk_core.Error.t) result
val finite_vec3 : Prismel_math.Vec3.t -> bool
val float_max : float -> float -> float
val float_min : float -> float -> float
val point_in_sphere_at :
  Prismel_math.Vec3.t ->
  float -> Pdk_core.Packed.Float3.Private.view -> int -> bool
val point_in_box_at :
  Prismel_math.Vec3.t ->
  Prismel_math.Vec3.t -> Pdk_core.Packed.Float3.Private.view -> int -> bool
val segment_intersects_box_at :
  Prismel_math.Vec3.t ->
  Prismel_math.Vec3.t ->
  Pdk_core.Packed.Float3.Private.view -> int -> int -> bool
val segment_intersects_sphere_at :
  Prismel_math.Vec3.t ->
  float -> Pdk_core.Packed.Float3.Private.view -> int -> int -> bool
val group_bounds :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?base:string ->
  ?containment:containment ->
  ?merge:boolean_operation ->
  bounds ->
  owner:owner ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
(* Typed boundary with the former Ops error and cancellation behavior. *)
val group_bounds_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?base:string ->
  ?containment:containment ->
  ?merge:boolean_operation ->
  bounds ->
  owner:owner ->
  name:string -> Pdk_core.Geometry.t ->
  (Pdk_core.Geometry.t, Pdk_core.Error.t) result
val combine :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  owner:owner ->
  name:string ->
  base:operand ->
  steps:combine_step list ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val clamp_index : int -> int -> int
val range_bounds : int -> range -> int * int
val finite_positions :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  operation:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Packed.Float3.Private.view, string) result
val geometric_face_directions :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Topology.t ->
  Pdk_core.Packed.Float3.Private.view ->
  float array * float array * float array * bytes
val corner_angle_at :
  Pdk_core.Packed.Float3.Private.view -> int -> int -> int -> float
val geometric_point_directions :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Topology.t ->
  Pdk_core.Topology_index.t ->
  Pdk_core.Packed.Float3.Private.view ->
  float array ->
  float array ->
  float array -> bytes -> float array * float array * float array
val direction_matches :
  float -> bool -> float -> float -> float -> float -> float -> float -> bool
val point_geometric_direction_matches :
  float ->
  bool ->
  float ->
  float ->
  float ->
  Pdk_core.Packed.Float3.Private.view ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  float array -> float array -> float array -> bytes -> int -> bool
val primitive_geometric_direction_matches :
  float ->
  bool ->
  float ->
  float ->
  float ->
  Pdk_core.Packed.Float3.Private.view ->
  Pdk_core.Topology.Private.view -> int -> bool
val group_normal :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?normal_attribute:string ->
  ?use_existing_normal:bool ->
  ?base:string ->
  ?include_opposite:bool ->
  ?merge:boolean_operation ->
  direction:Prismel_math.Vec3.t ->
  spread_angle:float ->
  owner:owner ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val primitive_is_non_planar :
  float ->
  Pdk_core.Packed.Float3.Private.view ->
  Pdk_core.Topology.Private.view -> int -> bool
val group_non_planar :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?base:string ->
  ?merge:boolean_operation ->
  tolerance:float ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val primitive_is_backface :
  Prismel_math.Vec3.t ->
  Pdk_core.Packed.Float3.Private.view ->
  Pdk_core.Topology.Private.view -> int -> bool
val group_backface :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?base:string ->
  ?merge:boolean_operation ->
  viewpoint:Prismel_math.Vec3.t ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val positive_mod : int -> int -> int
type range_connectivity_configuration = {
  range_attributes : string option;
  range_tolerance : float;
  range_collision : range_collision option;
  range_region : int option;
  range_remove_other_regions : bool;
}
val range_connectivity_configuration :
  range_connectivity -> range_connectivity_configuration
val range_boundary_edges :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  store:group_store ->
  owner:owner ->
  range_connectivity_configuration ->
  Pdk_core.Geometry.t ->
  (Pdk_core.Edge_group.t option * Pdk_core.Group.t option, string) result
val range :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?base:string ->
  ?invert:bool ->
  ?filter:range_filter ->
  ?connectivity:range_connectivity ->
  ?merge:boolean_operation ->
  owner:owner ->
  name:string ->
  range -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val ranges :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  range_rule list ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val owner_selected : 'a option -> 'a -> bool
val rename_entry :
  group_store ->
  conflict:rename_conflict ->
  named_entry -> String.t -> selection -> (unit, string) result
val rename :
  rules:rename_rule list ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val invert :
  ?conflict:rename_conflict ->
  ?owner:owner ->
  pattern:string ->
  ?new_name:string ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val delete :
  rules:delete_rule list ->
  ?delete_unused:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
type element_map =
    Identity of int
  | Explicit of int array
  | Proximity of { indices : int array; distances_squared : float array; }
val mapped_source : element_map -> int -> int
val attribute_owner : owner -> Pdk_core.Attribute.owner
val hash_capacity : int -> (int, string) result
val integer_hash : int -> int -> int
val integer_first_map : int array -> (int -> int, string) result
val string_first_map : String.t array -> (String.t -> int, string) result
val attribute_match_map :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner ->
  string ->
  Pdk_core.Geometry.t -> Pdk_core.Geometry.t -> (element_map, string) result
val default_copy_map :
  ?cancel:Pdk_core.Cancel.t ->
  owner -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t -> element_map
val target_owner_count :
  ?cancel:Pdk_core.Cancel.t -> owner -> Pdk_core.Geometry.t -> int
val copied_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner -> element_map -> selection -> Pdk_core.Geometry.t -> selection
val unique_suffix : group_store -> owner -> string -> string
val default_copy_rules : copy_rule list
val copy :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?rules:copy_rule list ->
  ?conflict:copy_conflict ->
  ?copy_empty:bool ->
  source:Pdk_core.Geometry.t ->
  target:Pdk_core.Geometry.t -> unit -> (Pdk_core.Geometry.t, string) result
val default_transfer_rules : transfer_rule list
val point_proximity_map :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  maximum_squared:float ->
  Pdk_core.Geometry.t -> Pdk_core.Geometry.t -> (element_map, string) result
val feature_proximity_map :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  distance:float ->
  source_features:(unit ->
                   (Pdk_spatial.Proximity_index.features, string) result) ->
  target_features:(unit ->
                   (Pdk_spatial.Proximity_index.features, string) result) ->
  unit -> (element_map, string) result
val transfer_mapping :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  distance:float ->
  maximum_squared:float ->
  owner ->
  Pdk_core.Geometry.t -> Pdk_core.Geometry.t -> (element_map, string) result
val transfer :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?rules:transfer_rule list ->
  ?conflict:copy_conflict ->
  ?create_empty:bool ->
  ?distance:float ->
  source:Pdk_core.Geometry.t ->
  target:Pdk_core.Geometry.t -> unit -> (Pdk_core.Geometry.t, string) result
