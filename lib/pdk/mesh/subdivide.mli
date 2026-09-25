type scheme = Catmull_clark | Loop | Bilinear
type boundary_interpolation =
    Subdivide_boundary_none
  | Subdivide_boundary_edge_only
  | Subdivide_boundary_edge_and_corner
type face_varying_interpolation =
    Subdivide_fvar_none
  | Subdivide_fvar_corners_only
  | Subdivide_fvar_corners_plus1
  | Subdivide_fvar_corners_plus2
  | Subdivide_fvar_boundaries
  | Subdivide_fvar_all
type triangle_subdivision =
    Subdivide_triangles_catmull_clark
  | Subdivide_triangles_smooth
type creasing_method =
    Subdivide_creasing_uniform
  | Subdivide_creasing_chaikin
type crack_policy =
    Subdivide_do_not_close
  | Subdivide_pull_no_edge_division
  | Subdivide_pull_divide_edges of float
  | Subdivide_pull_triangulate of float
  | Subdivide_stitch_no_edge_division
  | Subdivide_stitch_divide_edges
  | Subdivide_stitch_triangulate
val edge_ancestry_prefix : string
exception Subdivide_error of string
val fail : string -> 'a
val get_ok : ('a, string) result -> 'a
val checked_add : string -> int -> int -> int
val checked_mul : string -> int -> int -> int
val run :
  ?grain:int -> ?cancel:Pdk_core.Cancel.t -> int -> (int -> unit) -> unit
type plan = {
  scheme : scheme;
  source : Pdk_core.Geometry.t;
  source_topology : Pdk_core.Topology.Private.view;
  index : Pdk_core.Topology_index.Private.view;
  source_points : int;
  source_vertices : int;
  source_primitives : int;
  edge_count : int;
  face_offset : int;
  output_points : int;
  point_offsets : int array;
  point_sources : int array;
  point_weights : float array;
  point_representative : int array;
  edge_ancestry_attribute : string option;
  boundary_interpolation : boundary_interpolation;
  triangle_subdivision : triangle_subdivision;
  creasing_method : creasing_method;
  holes : Pdk_core.Group.t option;
  creases : crease_plan option;
  vertex_kind : bytes;
  vertex_a : int array;
  vertex_b : int array;
  vertex_primitive : int array;
  vertex_edge_source : int array;
  primitive_source : int array;
  topology : Pdk_core.Topology.t;
}
and crease_plan = {
  method_ : creasing_method;
  edge_sharpness : float array;
  child_edge_sharpness : float array;
  has_edge_creases : bool;
  has_corner_creases : bool;
  vertex_masks : vertex_mask_plan;
}
and vertex_mask_plan = {
  parent_kind : bytes;
  child_kind : bytes;
  transition_factor : float array;
  parent_a : int array;
  parent_b : int array;
  child_a : int array;
  child_b : int array;
}
val float_attribute :
  Pdk_core.Attribute.owner ->
  string -> Pdk_core.Geometry.t -> float array option
val validate_sharpness : string -> float array -> unit
val crease_data :
  ?edge_override:float ->
  Pdk_core.Geometry.t ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  (float array * float array * bool * bool) option
val same_topology :
  Pdk_core.Topology.Private.view -> Pdk_core.Topology.Private.view -> bool
val validate_crease_selection :
  Pdk_core.Group.t -> Pdk_core.Geometry.t -> unit
val validate_hole_group : Pdk_core.Group.t -> Pdk_core.Geometry.t -> unit
val apply_crease_input :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  ?override:float ->
  Pdk_core.Geometry.t -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val clamp_sharpness : float -> float
val build_child_edge_sharpness :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  creasing_method ->
  Pdk_core.Topology_index.Private.view -> int -> float array -> float array
val build_vertex_sharp_plan :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  creasing_method ->
  Pdk_core.Topology_index.Private.view ->
  float array -> float array -> float array -> vertex_mask_plan
val primitive_size : Pdk_core.Topology.Private.view -> int -> int
val not_finite : float -> bool
val validate :
  ?cancel:Pdk_core.Cancel.t ->
  scheme ->
  Pdk_core.Geometry.t ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view -> unit
val boundary_neighbors :
  Pdk_core.Topology_index.Private.view -> int -> int * int * int
val boundary_corner :
  boundary_interpolation ->
  Pdk_core.Topology_index.Private.view -> int -> bool
val point_term_count :
  boundary_interpolation ->
  scheme ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view -> int -> int -> int -> int
val fill_point_stencil :
  boundary_interpolation ->
  triangle_subdivision ->
  scheme ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  int ->
  int -> int array -> int array -> float array -> int array -> int -> unit
val make_topology :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?holes:Pdk_core.Group.t ->
  scheme ->
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  int ->
  int ->
  int ->
  bytes * int array * int array * int array * int array * int array *
  Pdk_core.Topology.t
val make_plan :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edge_ancestry_attribute:string ->
  ?edge_crease_override:float ->
  ?holes:Pdk_core.Group.t ->
  boundary_interpolation ->
  triangle_subdivision ->
  creasing_method -> scheme -> Pdk_core.Geometry.t -> plan
val creased_vertex_value :
  crease_plan -> float array -> int -> float -> float
val creased_edge_factor : crease_plan -> int -> float
val point_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> float array -> float array
type fvar_point_plan = {
  fvar_scheme : scheme;
  fvar_source_points : int;
  fvar_edge_count : int;
  fvar_output_points : int;
  fvar_point_offsets : int array;
  fvar_point_sources : int array;
  fvar_point_weights : float array;
  fvar_index : Pdk_core.Topology_index.Private.view;
  fvar_creases : crease_plan option;
}
type fvar_refinement =
    Linear_fvar of plan
  | Isolated_fvar of { geometry_refinement : plan;
      corner_sharpness : float array;
    }
  | Continuous_fvar of { geometry_refinement : plan;
      source_vertex_of_point : int array; pinned_points : bytes;
      output_point_of_vertex : int array;
    }
  | Split_fvar of { refinement : fvar_point_plan;
      source_vertex_of_point : int array; output_point_of_vertex : int array;
    }
val fvar_refinement :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  face_varying_interpolation ->
  plan -> (int -> int -> bool) -> fvar_refinement
val fvar_point_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> fvar_point_plan -> float array -> float array
val linear_vertex_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> float array -> float array
val isolated_vertex_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> float array -> float array -> float array
val fvar_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> fvar_refinement -> float array -> float array
val vertex_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> float array -> float array
val primitive_float :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> float array -> float array
val discrete_map :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> Pdk_core.Attribute.owner -> 'a array -> 'a array
val vertex_edge_discrete_map :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> 'a array -> 'a -> 'a array
val numeric_map :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  plan -> Pdk_core.Attribute.owner -> float array -> float array
val remap_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?generate_resulting_creases:bool ->
  ?face_varying_interpolation:face_varying_interpolation ->
  plan -> Pdk_core.Attribute.t -> Pdk_core.Attribute.t option
val child_crease_sharpness : plan -> float array option
val output_child_slot : plan -> int -> int -> int
val resulting_crease_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> float array option -> Pdk_core.Attribute.t option
type output_edge_plan = { child_edges : int array; output_edge_count : int; }
val output_edge_plan : ?cancel:Pdk_core.Cancel.t -> plan -> output_edge_plan
val set_edge_bit : bytes -> int -> unit
val edge_group_from_source :
  ?cancel:Pdk_core.Cancel.t ->
  plan ->
  output_edge_plan -> name:string -> (int -> bool) -> Pdk_core.Edge_group.t
val resulting_crease_group :
  ?cancel:Pdk_core.Cancel.t ->
  name:string ->
  plan -> output_edge_plan -> float array option -> Pdk_core.Edge_group.t
val remap_group :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> plan -> Pdk_core.Group.t -> Pdk_core.Group.t
val owner_count : Pdk_core.Geometry.t -> Pdk_core.Attribute.owner -> int
val same_attribute_slot :
  Pdk_core.Attribute.t -> Pdk_core.Attribute.t -> bool
val same_attribute_schema :
  Pdk_core.Attribute.t -> Pdk_core.Attribute.t -> bool
val find_attribute_like :
  Pdk_core.Attribute.t -> Pdk_core.Geometry.t -> Pdk_core.Attribute.t option
val checked_total : string -> int list -> int
val concatenate_part_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?extra_sources:int array ->
  Pdk_core.Attribute.t ->
  Pdk_core.Geometry.t list -> Pdk_core.Attribute.t option
type triangle_append = {
  triangle_points : int array;
  triangle_vertex_sources : int array;
  triangle_primitive_sources : int array;
}
type point_weld = {
  old_to_output : int array;
  output_source : int array;
  merge_offsets : int array;
  merge_members : int array;
  bias : float;
}
val locate_part : int array -> int -> int * int
val welded_float_plane :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  point_weld -> int array -> float array option array -> float array
val welded_representatives : point_weld -> int array
val concatenate_welded_point_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  Pdk_core.Attribute.t ->
  Pdk_core.Geometry.t list -> int array -> point_weld -> Pdk_core.Attribute.t
val combine_parts :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?append:triangle_append ->
  ?weld:point_weld ->
  source:Pdk_core.Geometry.t ->
  Pdk_core.Geometry.t list -> Pdk_core.Geometry.t
val once :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edge_ancestry_attribute:string ->
  ?edge_crease_override:float ->
  ?generate_resulting_creases:bool ->
  ?resulting_crease_group_name:String.t ->
  ?remove_holes:bool ->
  ?boundary_interpolation:boundary_interpolation ->
  ?face_varying_interpolation:face_varying_interpolation ->
  ?triangle_subdivision:triangle_subdivision ->
  ?creasing_method:creasing_method ->
  scheme -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val validate_primitive_selection :
  Pdk_core.Group.t -> Pdk_core.Geometry.t -> unit
val find_root : int array -> int -> int
val union_roots : int array -> int array -> int -> int -> unit
val select_point_array :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> int array -> 'a array -> 'a array
val duplicate_point_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> int array -> Pdk_core.Attribute.t -> Pdk_core.Attribute.t
val split_disconnected_point_fans :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
type pull_plan = {
  ancestry_attribute : string;
  source_topology : Pdk_core.Topology.t;
  source_index : Pdk_core.Topology_index.t;
  source_positions : Pdk_core.Packed.Float3.t;
  selected_edge_start : int array;
  unselected_primitive_of_edge : int array;
  unselected_point_of_source : int array;
  unselected_primitive_of_source : int array;
}
val fresh_edge_ancestry_name : Pdk_core.Geometry.t -> string
val annotate_pull_interfaces :
  ?cancel:Pdk_core.Cancel.t ->
  Pdk_core.Group.t ->
  Pdk_core.Geometry.t -> Pdk_core.Geometry.t * pull_plan option
type interface_chains = {
  edge_offsets : int array;
  points : int array;
  vertices : int array;
}
val interface_chains :
  ?cancel:Pdk_core.Cancel.t ->
  pull_plan -> Pdk_core.Geometry.t -> interface_chains
val interpolate_array :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  int array -> int array -> float array -> float array -> float array
val representative_map : 'a array -> 'a array -> float array -> 'a array
val interpolate_owned_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  point_left:int array ->
  point_right:int array ->
  point_weight:float array ->
  vertex_left:int array ->
  vertex_right:int array ->
  vertex_weight:float array ->
  primitive_source:int array -> Pdk_core.Attribute.t -> Pdk_core.Attribute.t
type divided_boundary = {
  geometry : Pdk_core.Geometry.t;
  edge_offsets : int array;
  points : int array;
  vertices : int array;
  source_primitive_to_output : int array;
}
val divide_unselected_edges :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  pull_plan -> interface_chains -> Pdk_core.Geometry.t -> divided_boundary
val remap_divided_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  int array -> int array -> Pdk_core.Attribute.t -> Pdk_core.Attribute.t
val remap_divided_group :
  ?grain:int ->
  int array -> int array -> Pdk_core.Group.t -> Pdk_core.Group.t
val triangulate_divided_boundary :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?pull_bias:float ->
  consistent_topology:bool ->
  pull_plan ->
  interface_chains ->
  divided_boundary -> refined:Pdk_core.Geometry.t -> divided_boundary
val shared_edge_endpoint :
  Pdk_core.Topology_index.Private.view -> int -> int -> int
val project_to_source_edge :
  Pdk_core.Packed.Float3.Private.view ->
  Pdk_core.Topology_index.Private.view ->
  int -> float -> float -> float -> float * float * float
val pull_boundary_no_edge_division :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> pull_plan -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val stitch_boundary_no_edge_division :
  ?cancel:Pdk_core.Cancel.t ->
  pull_plan ->
  unselected:Pdk_core.Geometry.t ->
  free_points:int -> refined:Pdk_core.Geometry.t -> triangle_append
val stitch_boundary_divide_edges :
  ?cancel:Pdk_core.Cancel.t ->
  consistent_topology:bool ->
  pull_plan ->
  interface_chains ->
  divided_boundary ->
  free_points:int ->
  free_vertices:int -> Pdk_core.Geometry.t -> triangle_append
val make_boundary_weld :
  ?cancel:Pdk_core.Cancel.t ->
  bias:float ->
  only_equal:bool ->
  interface_chains ->
  divided_boundary ->
  free_points:int -> total_points:int -> Pdk_core.Geometry.t -> point_weld
val extract_primitive_part :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  selected:bool ->
  Pdk_core.Group.t -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val free_point_part :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t option
val iterate :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edge_ancestry_attribute:string ->
  ?initial_edge_crease_override:float ->
  ?generate_resulting_creases:bool ->
  ?resulting_crease_group_name:String.t ->
  ?remove_holes:bool ->
  ?boundary_interpolation:boundary_interpolation ->
  ?face_varying_interpolation:face_varying_interpolation ->
  ?triangle_subdivision:triangle_subdivision ->
  ?creasing_method:creasing_method ->
  scheme -> int -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val with_empty_edge_group :
  ?cancel:Pdk_core.Cancel.t ->
  string -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val without_resulting_creases : Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val automatic_boundary_holes :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> Pdk_core.Geometry.t -> Pdk_core.Group.t option
type detail_overrides = {
  osd_scheme : Pdk_core.Attribute.t option;
  osd_vtxboundaryinterpolation : Pdk_core.Attribute.t option;
  osd_fvarlinearinterpolation : Pdk_core.Attribute.t option;
  osd_creasingmethod : Pdk_core.Attribute.t option;
  osd_trianglesubdiv : Pdk_core.Attribute.t option;
}
val detail_overrides : Pdk_core.Geometry.t -> detail_overrides
val detail_int : string -> Pdk_core.Attribute.t -> int
val resolve_scheme : scheme -> Pdk_core.Attribute.t option -> scheme
val resolve_boundary_interpolation :
  boundary_interpolation ->
  Pdk_core.Attribute.t option -> boundary_interpolation
val resolve_face_varying_interpolation :
  face_varying_interpolation ->
  Pdk_core.Attribute.t option -> face_varying_interpolation
val resolve_creasing_method :
  creasing_method -> Pdk_core.Attribute.t option -> creasing_method
val resolve_triangle_subdivision :
  triangle_subdivision -> Pdk_core.Attribute.t option -> triangle_subdivision
val subdivide_polygons :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?scheme:scheme ->
  ?iterations:int ->
  ?primitives:Pdk_core.Group.t ->
  ?cracks:crack_policy ->
  ?consistent_topology:bool ->
  ?creases:Pdk_core.Geometry.t ->
  ?crease_primitives:Pdk_core.Group.t ->
  ?crease_weight:float ->
  ?generate_resulting_creases:bool ->
  ?resulting_crease_group:String.t ->
  ?hole_primitives:Pdk_core.Group.t ->
  ?remove_holes:bool ->
  ?boundary_interpolation:boundary_interpolation ->
  ?face_varying_interpolation:face_varying_interpolation ->
  ?triangle_subdivision:triangle_subdivision ->
  ?creasing_method:creasing_method ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val primitive_kind_counts : Pdk_core.Geometry.t -> int * int
val internal_attribute_name : Pdk_core.Geometry.t -> string -> string
val primitive_kind_group :
  ?grain:int -> polygon:bool -> Pdk_core.Geometry.t -> Pdk_core.Group.t
val extract_kind :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int -> polygon:bool -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val selection_for_kind :
  ?grain:int ->
  polygon:bool ->
  Pdk_core.Group.t option -> Pdk_core.Geometry.t -> Pdk_core.Group.t option
val refine_curves :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  independent:bool ->
  scheme -> int -> Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val subdivide :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?scheme:scheme ->
  ?iterations:int ->
  ?primitives:Pdk_core.Group.t ->
  ?cracks:crack_policy ->
  ?consistent_topology:bool ->
  ?creases:Pdk_core.Geometry.t ->
  ?crease_primitives:Pdk_core.Group.t ->
  ?crease_weight:float ->
  ?generate_resulting_creases:bool ->
  ?resulting_crease_group:String.t ->
  ?hole_primitives:Pdk_core.Group.t ->
  ?remove_holes:bool ->
  ?boundary_interpolation:boundary_interpolation ->
  ?face_varying_interpolation:face_varying_interpolation ->
  ?triangle_subdivision:triangle_subdivision ->
  ?creasing_method:creasing_method ->
  ?treat_curves_as_independent:bool ->
  ?recompute_point_normals:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val edge_divide :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?edges:Pdk_core.Edge_group.t ->
  ?divisions:int ->
  ?share_points:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
