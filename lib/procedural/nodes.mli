(** Editor factories of the SOP nodes declared once in this library: each
    [parameters] record derives its schema, this factory and the typed [Sop]
    constructor of the same operation, so the three never drift. *)
module Group_non_planar : sig val factory : Edit_graph.factory end
module Group_backface : sig val factory : Edit_graph.factory end
module Group_unshared : sig val factory : Edit_graph.factory end
module Group_edges : sig val factory : Edit_graph.factory end
module Group_random : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string -> ?seed:int -> probability:float ->
    owner:Rdk.Group_ops.owner -> name:string ->
    Node.t -> Node.t
end
module Group_edge_depth : sig val factory : Edit_graph.factory end
module Group_boundary_components : sig val factory : Edit_graph.factory end
module Group_from_attribute_boundary : sig val factory : Edit_graph.factory end
module Groups_from_name : sig val factory : Edit_graph.factory end
module Name_from_groups : sig val factory : Edit_graph.factory end
module Group_promote_boundary : sig val factory : Edit_graph.factory end
module Group_delete : sig val factory : Edit_graph.factory end
module Group_rename : sig val factory : Edit_graph.factory end
module Group_copy : sig val factory : Edit_graph.factory end
module Group_transfer : sig val factory : Edit_graph.factory end
module Group_find_path : sig val factory : Edit_graph.factory end
module Delete_edge_group : sig val factory : Edit_graph.factory end
module Rename_edge_group : sig val factory : Edit_graph.factory end
module Edge_divide : sig val factory : Edit_graph.factory end
module Edge_collapse : sig val factory : Edit_graph.factory end
module Dissolve : sig val factory : Edit_graph.factory end
module Triangulate : sig val factory : Edit_graph.factory end
module Edge_flip : sig val factory : Edit_graph.factory end
module Edge_cusp : sig val factory : Edit_graph.factory end
module Edge_straighten : sig val factory : Edit_graph.factory end
module Poly_extrude : sig val factory : Edit_graph.factory end
module Poly_fill : sig val factory : Edit_graph.factory end
module Convert_line : sig val factory : Edit_graph.factory end
module Blast : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string -> ?selected:bool -> ?compact_points:bool ->
    owner:Rdk.Group.owner -> group:string ->
    Node.t -> Node.t
end
module Uv_flatten : sig val factory : Edit_graph.factory end
module Uv_relax : sig val factory : Edit_graph.factory end
module Rename_attributes : sig val factory : Edit_graph.factory end
module Line : sig val factory : Edit_graph.factory end
module Mirror : sig val factory : Edit_graph.factory end
module Match_axis : sig val factory : Edit_graph.factory end
module Noise_displace : sig val factory : Edit_graph.factory end
module Crease : sig val factory : Edit_graph.factory end
module Poly_path : sig val factory : Edit_graph.factory end
module Ends : sig val factory : Edit_graph.factory end
module Measure : sig val factory : Edit_graph.factory end
module Uv_unitize : sig val factory : Edit_graph.factory end
module Swap_attributes : sig val factory : Edit_graph.factory end
module Group_invert : sig val factory : Edit_graph.factory end
module Separate_pieces : sig val factory : Edit_graph.factory end
module Group_combine : sig val factory : Edit_graph.factory end
module Group_promotions : sig val factory : Edit_graph.factory end
module Group_ranges : sig val factory : Edit_graph.factory end
module Box : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string ->
    ?size:Rays_math.Vec3.t ->
    ?connectivity:Rdk.Box_generator.box_connectivity ->
    ?consolidate_points:bool ->
    ?normals:Rdk.Box_generator.box_normals ->
    ?center:Rays_math.Vec3.t -> ?rotation:Rays_math.Vec3.t ->
    ?rotation_order:Rdk.Box_generator.box_rotation_order -> ?uniform_scale:float ->
    ?x_divisions:int -> ?y_divisions:int -> ?z_divisions:int ->
    ?uv_attribute:string -> ?face_groups:string ->
    unit -> Node.t
end
module Reverse : sig val factory : Edit_graph.factory end
module Material : sig val factory : Edit_graph.factory end
module Group_bounds : sig val factory : Edit_graph.factory end
module Sort : sig val factory : Edit_graph.factory end
module Group_range : sig val factory : Edit_graph.factory end
module Null : sig val factory : Edit_graph.factory end
module Switch : sig val factory : Edit_graph.factory end
module Compact_points : sig val factory : Edit_graph.factory end
module Extract_centroid : sig val factory : Edit_graph.factory end
module Ordered_group : sig val factory : Edit_graph.factory end
module Group_normal : sig val factory : Edit_graph.factory end
module Delete_attributes : sig val factory : Edit_graph.factory end
module Edge_transport_curves : sig val factory : Edit_graph.factory end
module Edge_transport_parent : sig val factory : Edit_graph.factory end
module Edge_equalize : sig val factory : Edit_graph.factory end
module Remesh : sig val factory : Edit_graph.factory end
module Resample : sig val factory : Edit_graph.factory end
module Carve : sig val factory : Edit_graph.factory end
module Poly_loft : sig val factory : Edit_graph.factory end
module Skin : sig val factory : Edit_graph.factory end
module Poly_bridge : sig val factory : Edit_graph.factory end
module Circle_from_edges : sig val factory : Edit_graph.factory end
module Convex_hull : sig val factory : Edit_graph.factory end
module Edge_relax : sig val factory : Edit_graph.factory end
module Point_split : sig val factory : Edit_graph.factory end
module Uv_auto_seam : sig val factory : Edit_graph.factory end
module Attribute_laplacian : sig val factory : Edit_graph.factory end
module Measure_curvature : sig val factory : Edit_graph.factory end
module Group_expand : sig val factory : Edit_graph.factory end
module Normal : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string -> ?owner:Rdk.Attribute.owner ->
    ?weighting:Rdk.Normal_ops.weighting -> ?cusp_angle:float ->
    ?keep_original_zero:bool -> ?reverse:bool -> ?attribute:string ->
    Node.t -> Node.t
end
module Peak : sig val factory : Edit_graph.factory end
module Bend : sig val factory : Edit_graph.factory end
module Clip : sig val factory : Edit_graph.factory end
module Uv_transform : sig val factory : Edit_graph.factory end
module Uv_project : sig val factory : Edit_graph.factory end
module Color_by_height : sig val factory : Edit_graph.factory end
module Graph_color : sig val factory : Edit_graph.factory end
module Set_float : sig val factory : Edit_graph.factory end
module Set_int : sig val factory : Edit_graph.factory end
module Set_vector : sig val factory : Edit_graph.factory end
module Connectivity : sig val factory : Edit_graph.factory end
module Set_orient : sig val factory : Edit_graph.factory end
module Set_transform : sig val factory : Edit_graph.factory end
module Rest_position : sig val factory : Edit_graph.factory end
module Merge : sig val factory : Edit_graph.factory end
module Set_color : sig val factory : Edit_graph.factory end
module Enumerate : sig val factory : Edit_graph.factory end
module Attribute_blur : sig val factory : Edit_graph.factory end
module Smooth : sig val factory : Edit_graph.factory end
module Promote_attributes : sig val factory : Edit_graph.factory end
module Polyframe : sig val factory : Edit_graph.factory end
module Bound : sig val factory : Edit_graph.factory end
module Match_size : sig val factory : Edit_graph.factory end
module Point_generate : sig
  val factory : Edit_graph.factory
  val origin : ?label:string -> points:int -> unit -> Node.t
end
module Rewire_vertices : sig val factory : Edit_graph.factory end
module Distance_along_geometry : sig val factory : Edit_graph.factory end
module Distance_from_target : sig val factory : Edit_graph.factory end
module Distance_from_geometry : sig val factory : Edit_graph.factory end
module Revolve : sig val factory : Edit_graph.factory end
module Platonic : sig
  val factory : Edit_graph.factory
end
module Edge_transport : sig val factory : Edit_graph.factory end
module Clean : sig val factory : Edit_graph.factory end
module Snap_to_grid : sig val factory : Edit_graph.factory end
module Point_jitter : sig
  val factory : Edit_graph.factory
end
module Join_curves : sig val factory : Edit_graph.factory end
module Exploded_view : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string -> ?amount:float -> ?scale:Rays_math.Vec3.t ->
    ?piece_attribute:string -> ?noise_amount:float ->
    ?noise_frequency:float -> ?noise_seed:int ->
    Node.t -> Node.t
end
module Copy_to_points : sig
  val factory : Edit_graph.factory
end
module Attribute_remap : sig val factory : Edit_graph.factory end
module Attribute_mirror : sig val factory : Edit_graph.factory end
module Attribute_fade : sig val factory : Edit_graph.factory end

module Point_velocity : sig val factory : Edit_graph.factory end
module Spiral : sig val factory : Edit_graph.factory end
module Circle : sig val factory : Edit_graph.factory end
module Grid : sig
  val factory : Edit_graph.factory
end
module Blast_by_attribute : sig val factory : Edit_graph.factory end
module Facet : sig val factory : Edit_graph.factory end
module Attribute_transfer_all : sig val factory : Edit_graph.factory end
module Uv_sphere : sig val factory : Edit_graph.factory end
module Torus : sig val factory : Edit_graph.factory end
module Tube : sig val factory : Edit_graph.factory end
module Mountain : sig val factory : Edit_graph.factory end
module Extract_point_from_curve : sig val factory : Edit_graph.factory end
module Point_generate_from_input : sig val factory : Edit_graph.factory end
module Poly_cut : sig val factory : Edit_graph.factory end
module Poly_reduce : sig val factory : Edit_graph.factory end
module Soft_transform : sig val factory : Edit_graph.factory end
module Scatter : sig val factory : Edit_graph.factory end
module Sweep : sig val factory : Edit_graph.factory end
module Boolean_seam : sig val factory : Edit_graph.factory end
module Attribute_transfer_surface : sig val factory : Edit_graph.factory end
module Attribute_copy : sig val factory : Edit_graph.factory end
module Ray : sig val factory : Edit_graph.factory end
module Poly_bevel : sig
  val factory : Edit_graph.factory
  type shape = Chamfer | Round
  val create :
    ?label:string -> ?shape:shape -> ?divisions:int -> distance:float ->
    Node.t -> Node.t
end
module Point_replicate : sig val factory : Edit_graph.factory end
module Boolean_fracture : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string ->
    ?resolve_cutter_self_intersections:bool ->
    ?detriangulation:Rdk.Boolean.detriangulation ->
    ?require_closed:bool ->
    ?piece_attribute:string ->
    cutters:Node.t ->
    Node.t ->
    Node.t
end
module Intersection_analysis : sig val factory : Edit_graph.factory end
module Fuse : sig val factory : Edit_graph.factory end
module Subdivide : sig val factory : Edit_graph.factory end
module Boolean : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string ->
    ?operation:Rdk.Boolean.operation ->
    ?resolve_right_self_intersections:bool ->
    ?detriangulation:Rdk.Boolean.detriangulation ->
    right:Node.t -> Node.t -> Node.t
end
module Boolean_detect : sig val factory : Edit_graph.factory end
module Duplicate : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string -> ?copies:int -> ?cumulative:bool ->
    ?transform:Rays_math.Mat4.t -> Node.t -> Node.t
end
module Triangulate_2d : sig val factory : Edit_graph.factory end
module Polywire : sig val factory : Edit_graph.factory end

module Sweep_circle : sig val factory : Edit_graph.factory end
module Attribute_noise_quaternion : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string ->
    ?group:string ->
    ?location:Rdk.Attribute_ops.noise_location ->
    ?range:Rdk.Attribute_ops.noise_range ->
    owner:Rdk.Attribute.owner ->
    name:string ->
    seed:int -> frequency:Rays_math.Vec3.t -> octaves:int ->
    Node.t -> Node.t
end
module Transform : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string -> ?translate:Rays_math.Vec3.t -> ?rotate:Rays_math.Vec3.t ->
    ?scale:Rays_math.Vec3.t -> ?uniform_scale:float ->
    Node.t -> Node.t
end
module Attribute_noise : sig val factory : Edit_graph.factory end
module Attribute_randomize : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string -> ?owner:Rdk.Attribute.owner -> ?seed:int -> name:string ->
    minimum:float -> maximum:float -> Node.t -> Node.t
end
module Attribute_interpolate : sig val factory : Edit_graph.factory end
module Attribute_transfer : sig val factory : Edit_graph.factory end

module Attribute_composite : sig val factory : Edit_graph.factory end

module Blend_shapes : sig val factory : Edit_graph.factory end
