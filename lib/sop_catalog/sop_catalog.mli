(** Inspectable SOP catalog nodes. Constructors retain the ordinary immutable
    Procedural graph API while attaching PPX-derived parameter metadata and a
    pure stable-id rebuild function to each node. *)

module Box : sig
  val create :
    ?label:string ->
    ?size:Prismel.Vec3.t ->
    ?connectivity:Pdk.Ops.box_connectivity ->
    ?consolidate_points:bool ->
    ?normals:Pdk.Ops.box_normals ->
    ?center:Prismel.Vec3.t -> ?rotation:Prismel.Vec3.t ->
    ?rotation_order:Pdk.Ops.box_rotation_order -> ?uniform_scale:float ->
    ?x_divisions:int -> ?y_divisions:int -> ?z_divisions:int ->
    ?uv_attribute:string -> ?face_groups:string ->
    unit -> Procedural.Node.t
end

module Platonic : sig
  val create :
    ?label:string ->
    ?kind:Pdk.Ops.platonic_kind ->
    ?normals:Pdk.Ops.platonic_normals ->
    ?orientation:Pdk.Ops.platonic_orientation ->
    ?center:Prismel.Vec3.t -> ?rotation:Prismel.Vec3.t ->
    ?rotation_order:Pdk.Ops.platonic_rotation_order ->
    ?face_groups:string ->
    radius:float -> unit -> Procedural.Node.t
end

module Spiral : sig
  val create : ?label:string -> unit -> Procedural.Node.t
end

module Switch : sig
  val create :
    ?label:string -> ?index:int -> Procedural.Node.t list -> Procedural.Node.t
  (** Inspectable standard SOP switch. The generated choice uses stable input
      order and node labels; only the selected input branch is cooked. *)
end

module Line : sig
  val create :
    ?label:string -> ?kind:Pdk.Ops.line_kind -> ?points:int ->
    ?origin:Prismel.Vec3.t -> ?direction:Prismel.Vec3.t -> ?length:float ->
    unit -> Procedural.Node.t
end

module Circle : sig
  val create : ?label:string -> unit -> Procedural.Node.t
end

module Grid : sig
  val create :
    ?label:string ->
    ?counts:Pdk.Ops.grid_counts ->
    ?connectivity:Pdk.Ops.grid_connectivity ->
    ?orientation:Pdk.Ops.grid_orientation ->
    ?center:Prismel.Vec3.t -> ?width:float -> ?height:float ->
    ?rotation:float -> ?uv_attribute:string ->
    columns:int -> rows:int -> size:float -> unit -> Procedural.Node.t
end

module Uv_sphere : sig
  val create : ?label:string -> unit -> Procedural.Node.t
end

module Torus : sig
  val create : ?label:string -> unit -> Procedural.Node.t
end

module Tube : sig
  val create : ?label:string -> unit -> Procedural.Node.t
end

module Transform : sig
  val create :
    ?label:string ->
    ?translate:Prismel.Vec3.t ->
    ?rotate:Prismel.Vec3.t ->
    ?scale:Prismel.Vec3.t ->
    ?preserve_normal_length:bool ->
    ?recompute_normals:bool ->
    Procedural.Node.t -> Procedural.Node.t
end

module Match_size : sig
  val create :
    ?label:string -> ?target:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Mirror : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Clip : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Crease : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Subdivide : sig
  val create :
    ?label:string -> ?creases:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Edge_divide : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Edge_collapse : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Dissolve : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Poly_bevel : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Triangulate : sig
  val create :
    ?label:string -> ?group:string ->
    Procedural.Node.t -> Procedural.Node.t
end

module Copy_to_points : sig
  val create :
    ?label:string ->
    ?source_group:string ->
    ?target_group:string ->
    ?piece_attribute:string ->
    source:Procedural.Node.t ->
    targets:Procedural.Node.t ->
    unit ->
    Procedural.Node.t
end

module Mountain : sig
  val create :
    ?label:string ->
    ?group:string ->
    ?direction_attribute:string ->
    ?mask_attribute:string ->
    ?height_attribute:string ->
    ?recompute_normals:bool ->
    seed:int -> height:float -> frequency:Prismel.Vec3.t ->
    octaves:int -> lacunarity:float -> roughness:float ->
    Procedural.Node.t -> Procedural.Node.t
end

module Peak : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Bend : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Smooth : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Reverse : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Clean : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Facet : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Separate_pieces : sig
  val create :
    ?label:string -> ?owner:Pdk.Attribute.owner ->
    ?translation_attribute:string -> ?axis:Prismel.Vec3.t -> ?gap:float ->
    ?mode:Pdk.Ops.separate_pieces_mode -> piece_attribute:string ->
    Procedural.Node.t -> Procedural.Node.t
end

module Edge_flip : sig
  val create :
    ?label:string -> ?group:string -> ?cycles:int ->
    ?cycle_vertex_attributes:bool -> ?recompute_point_normals:bool ->
    Procedural.Node.t -> Procedural.Node.t
end

module Edge_cusp : sig
  val create : ?label:string -> ?group:string -> ?update_point_normals:bool ->
    Procedural.Node.t -> Procedural.Node.t
end

module Edge_straighten : sig
  val create : ?label:string -> ?group:string -> ?output_group:string ->
    Procedural.Node.t -> Procedural.Node.t
end

module Circle_from_edges : sig
  val create :
    ?label:string -> ?group:string -> ?radius:float -> ?scale:Prismel.Vec3.t ->
    ?output_group:string -> Procedural.Node.t -> Procedural.Node.t
end

module Edge_equalize : sig
  val create :
    ?label:string -> ?group:string -> ?method_:Pdk.Ops.edge_equalize_method ->
    ?iterations:int -> ?tolerance:float -> ?output_group:string ->
    Procedural.Node.t -> Procedural.Node.t
end

module Snap_to_grid : sig
  val create :
    ?label:string -> ?group:string -> ?spacing:Prismel.Vec3.t ->
    ?offset:Prismel.Vec3.t -> ?rounding:Pdk.Ops.grid_rounding ->
    ?max_distance:float -> ?fuse_points:bool ->
    ?position:Pdk.Ops.fuse_position -> ?weight_attribute:string ->
    ?attributes:Pdk.Ops.fuse_attributes -> ?snapped_group:string ->
    Procedural.Node.t -> Procedural.Node.t
end

module Remesh : sig
  val create : ?label:string -> ?target_length:float ->
    Procedural.Node.t -> Procedural.Node.t
end

module Poly_extrude : sig
  val create : ?label:string -> ?distance:float ->
    Procedural.Node.t -> Procedural.Node.t
end

module Poly_fill : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Convert_line : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Resample : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Carve : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Ends : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Join_curves : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Poly_path : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Point_generate : sig
  val origin : ?label:string -> points:int -> unit -> Procedural.Node.t
end

module Attribute_noise_quaternion : sig
  val create :
    ?label:string ->
    ?group:string ->
    ?location:Pdk.Attribute_ops.noise_location ->
    ?range:Pdk.Attribute_ops.noise_range ->
    owner:Pdk.Attribute.owner ->
    name:string ->
    seed:int -> frequency:Prismel.Vec3.t -> octaves:int ->
    Procedural.Node.t -> Procedural.Node.t
end

module Point_jitter : sig
  val create :
    ?label:string ->
    ?group:string ->
    ?mask_attribute:string ->
    ?id_attribute:string ->
    seed:int -> scale:float ->
    ?axis_scales:Prismel.Vec3.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Boolean_fracture : sig
  val create :
    ?label:string ->
    ?resolve_cutter_self_intersections:bool ->
    ?detriangulation:Pdk.Boolean.detriangulation ->
    ?require_closed:bool ->
    ?piece_attribute:string ->
    cutters:Procedural.Node.t ->
    Procedural.Node.t ->
    Procedural.Node.t
end

module Boolean : sig
  val create : ?label:string -> right:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Boolean_seam : sig
  val create : ?label:string -> right:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Boolean_detect : sig
  val create : ?label:string -> ?collision:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Intersection_analysis : sig
  val create : ?label:string -> ?collision:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Poly_reduce : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Measure_curvature : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Attribute_laplacian : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Polyframe : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Duplicate : sig
  val create :
    ?label:string -> ?copies:int -> ?cumulative:bool ->
    ?transform:Prismel.Mat4.t -> ?group:string -> ?copy_group_prefix:string ->
    ?preserve_groups:bool -> Procedural.Node.t -> Procedural.Node.t
end

module Match_axis : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Convex_hull : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Extract_centroid : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Bound : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Fuse : sig
  val create : ?label:string -> ?target:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Ray : sig
  val create : ?label:string -> collision:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Distance_along_geometry : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Distance_from_geometry : sig
  val create : ?label:string -> reference:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Distance_from_target : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Point_split : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Poly_bridge : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Graph_color : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Edge_relax : sig
  val create : ?label:string -> reference:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Poly_loft : sig
  val create : ?label:string -> ?rest:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Revolve : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Sweep : sig
  val create : ?label:string -> backbone:Procedural.Node.t ->
    cross_section:Procedural.Node.t -> unit -> Procedural.Node.t
end

module Polywire : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Uv_project : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Uv_transform : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Uv_auto_seam : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Uv_unitize : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Uv_flatten : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Uv_relax : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end


module Group_edges : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_random : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_bounds : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_normal : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_non_planar : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_backface : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_edge_depth : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_unshared : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_boundary_components : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_from_attribute_boundary : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Groups_from_name : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Name_from_groups : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_promote : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_promote_boundary : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_promotions : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_invert : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_delete : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_rename : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_copy : sig
  val create : ?label:string -> source:Procedural.Node.t ->
    target:Procedural.Node.t -> unit -> Procedural.Node.t
end

module Group_transfer : sig
  val create : ?label:string -> source:Procedural.Node.t ->
    target:Procedural.Node.t -> unit -> Procedural.Node.t
end

module Group_combine : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_expand : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_range : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_ranges : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Group_find_path : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Poly_cut : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Sort : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Noise_displace : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Color_by_height : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Scatter : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Attribute_noise : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Attribute_remap : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Attribute_randomize : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Attribute_mirror : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Rewire_vertices : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Edge_transport : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Edge_transport_curves : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Edge_transport_parent : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Blast_by_attribute : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Blast : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Compact_points : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Bounding_box : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Rename_group : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Delete_edge_group : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Rename_edge_group : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Delete_attributes : sig
  val create : ?label:string -> ?reference:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Rename_attributes : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Swap_attributes : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Triangulate_2d : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Extract_point_from_curve : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Soft_transform : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Point_generate_from_input : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Point_replicate : sig
  val create : ?label:string -> ?custom_shape:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Attribute_fade : sig
  val create : ?label:string -> ?start_source:Procedural.Node.t ->
    ?hold_source:Procedural.Node.t -> Procedural.Node.t -> Procedural.Node.t
end

module Point_velocity : sig
  val create : ?label:string -> ?previous:Procedural.Node.t ->
    ?next:Procedural.Node.t -> Procedural.Node.t -> Procedural.Node.t
end

module Attribute_transfer : sig
  val create : ?label:string -> source:Procedural.Node.t ->
    target:Procedural.Node.t -> unit -> Procedural.Node.t
end

module Attribute_transfer_surface : sig
  val create : ?label:string -> source:Procedural.Node.t ->
    target:Procedural.Node.t -> unit -> Procedural.Node.t
end

module Attribute_copy : sig
  val create : ?label:string -> source:Procedural.Node.t ->
    target:Procedural.Node.t -> unit -> Procedural.Node.t
end

module Attribute_interpolate : sig
  val create : ?label:string -> source:Procedural.Node.t ->
    target:Procedural.Node.t -> unit -> Procedural.Node.t
end

module Attribute_transfer_all : sig
  val create : ?label:string -> source:Procedural.Node.t ->
    target:Procedural.Node.t -> unit -> Procedural.Node.t
end

module Promote_attribute : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Promote_attributes : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Measure : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Connectivity : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Set_float : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Set_int : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Set_vector : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Set_orient : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Set_transform : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Set_color : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Delete_attribute : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Rename_attribute : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Rest_position : sig
  val create : ?label:string -> ?reference:Procedural.Node.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Enumerate : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Attribute_blur : sig
  val create : ?label:string -> Procedural.Node.t -> Procedural.Node.t
end

module Normal : sig
  val create :
    ?label:string -> ?owner:Pdk.Attribute.owner ->
    ?weighting:Pdk.Ops.normal_weighting -> ?cusp_angle:float ->
    ?keep_original_zero:bool -> ?reverse:bool -> ?attribute:string ->
    Procedural.Node.t -> Procedural.Node.t
end

module Exploded_view : sig
  val create :
    ?label:string -> ?amount:float -> ?scale:Prismel.Vec3.t ->
    ?piece_attribute:string -> ?noise_amount:float ->
    ?noise_frequency:float -> ?noise_seed:int ->
    Procedural.Node.t -> Procedural.Node.t
end

(** Deterministic PPX-generated manifest for the interactive SOP network
    editor. A module marked [[@@sop.register]] contributes its local [factory]
    in source order; there is no second hand-maintained registry. Factories
    declare exact input arity and build ordinary immutable nodes, while the
    editor document remains the topology authority. *)
module Editor : sig
  val factories : Procedural.Edit_graph.factory list
end
