open Sop_support

type group_invert_owner = Sop_support.group_invert_owner =
  | Any
  | Owner of Rdk.Group_ops.owner

type element_owner = Sop_support.element_owner =
  Element_point | Element_vertex | Element_primitive | Element_edge

type uv_projection = Sop_support.uv_projection = Planar | Cylindrical | Spherical
type connectivity_output = Sop_support.connectivity_output = Integer | Text
type enumerate_storage = Sop_support.enumerate_storage = Enumerate_integer | Enumerate_text
type smoothing_mode = Sop_support.smoothing_mode = Laplacian | Custom
type polyframe_style = Sop_support.polyframe_style = Style_first_edge | Style_two_edges | Style_centroid
  | Style_texture_uv | Style_texture_uv_gradient | Style_attribute_gradient

type element_group = Sop_support.element_group =
  Point_group of string | Vertex_group of string
  | Primitive_group of string | Edge_group of string

let snapshot ?label geometry =
  let parameters = Printf.sprintf "data_id=%d;bytes=%d"
      (Rdk.Geometry.data_id geometry) (Rdk.Geometry.payload_bytes geometry) in
  Node.Private.make_geometry ?label ~operation:"snapshot" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ _context _inputs -> cooked geometry)

let points ?label values =
  let values = Array.copy values in
  let parameters = Printf.sprintf "count=%d" (Array.length values) in
  Node.Private.make_geometry ?label ~operation:"points" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ _context _inputs ->
      if Array.exists (fun (x, y, z) -> not (finite x && finite y && finite z)) values
      then Error (Diagnostic.error ~code:"non_finite_position"
        "points requires finite x, y, and z coordinates")
      else cooked (Rdk.Line_geometry.points values))

let point_generate_origin = Sop_shapes.Point_generate.fn

let line = Sop_shapes.Line.fn

let polyline ?label ?(closed = false) values =
  let values = Array.copy values in
  let parameters = Printf.sprintf "count=%d;closed=%b" (Array.length values) closed in
  Node.Private.make_geometry ?label ~operation:"polyline" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ _context _inputs ->
      match Rdk.Line_geometry.polyline ~closed values with
      | Ok geometry -> cooked geometry
      | Error error -> structured_rdk_error error)

type circle_arc = Sop_support.circle_arc = Circle_closed | Circle_open | Circle_chord | Circle_sliced
type plane_orientation = Sop_support.plane_orientation = Plane_xy | Plane_xz | Plane_yz | Plane_axes
let circle = Sop_shapes.Circle.fn

let grid = Sop_shapes.Grid.fn

let box = Sop_shapes.Box.fn

let uv_sphere = Sop_shapes.Uv_sphere.fn

let torus = Sop_shapes.Torus.fn

let tube = Sop_shapes.Tube.fn

type axis_orientation = Sop_support.axis_orientation = Axis_x | Axis_y | Axis_z | Axis_custom

let platonic = Sop_shapes.Platonic.fn

type spiral_extent_mode = Sop_support.spiral_extent_mode = Spiral_turns_height | Spiral_height_pitch
type spiral_radius_mode = Sop_support.spiral_radius_mode = Spiral_archimedean_change | Spiral_archimedean_end | Spiral_logarithmic_change | Spiral_logarithmic_end
type spiral_divisions_mode = Sop_support.spiral_divisions_mode = Spiral_per_curve | Spiral_per_turn
let spiral = Sop_shapes.Spiral.fn

type transform_mode = Sop_support.transform_mode = Transform_trs | Transform_matrix

let transform = Sop_shapes.Transform.fn

let transform_trs = transform

type soft_transform_metric = Sop_support.soft_transform_metric = Soft_radius | Soft_edge | Soft_attribute
let soft_transform_trs = Sop_shapes.Soft_transform.fn

type distance_radius_mode = Sop_support.distance_radius_mode = Radius_fixed | Radius_maximum

let distance_along_geometry = Sop_attributes.Distance_along_geometry.fn

let distance_from_geometry = Sop_attributes.Distance_from_geometry.fn

let distance_from_target = Sop_attributes.Distance_from_target.fn

let merge = Sop_shapes.Merge.fn

type fuse_targeting = Sop_support.fuse_targeting = Fuse_near_points | Fuse_specified_points
let fuse = Sop_topology.Fuse.fn

let snap_to_grid = Sop_shapes.Snap_to_grid.fn

let mirror = Sop_shapes.Mirror.fn

let clip = Sop_shapes.Clip.fn

let crease = Sop_topology.Crease.fn

let attribute_fade = Sop_attributes.Attribute_fade.fn

type poly_cut_detection = Sop_support.poly_cut_detection = Cut_all | Cut_crossing | Cut_change
let poly_cut = Sop_topology.Poly_cut.fn

let separate_pieces = Sop_shapes.Separate_pieces.fn

type subdivision_cracks = Sop_support.subdivision_cracks = Cracks_do_not_close | Cracks_pull_no_division | Cracks_pull_divide | Cracks_pull_triangulate
  | Cracks_stitch_no_division | Cracks_stitch_divide | Cracks_stitch_triangulate
let subdivide = Sop_topology.Subdivide.fn

let edge_divide = Sop_topology.Edge_divide.fn

let edge_collapse = Sop_topology.Edge_collapse.fn

let dissolve = Sop_topology.Dissolve.fn

type poly_bevel_shape = Sop_support.poly_bevel_shape = Poly_chamfer | Poly_round
let poly_bevel = Sop_topology.Poly_bevel.fn

let point_split = Sop_topology.Point_split.fn

let poly_loft = Sop_topology.Poly_loft.fn

let skin = Sop_topology.Skin.fn

let poly_bridge = Sop_topology.Poly_bridge.fn

let edge_flip = Sop_topology.Edge_flip.fn

let edge_cusp = Sop_topology.Edge_cusp.fn

let edge_straighten = Sop_topology.Edge_straighten.fn

let circle_from_edges = Sop_topology.Circle_from_edges.fn

let graph_color = Sop_attributes.Graph_color.fn

let edge_equalize = Sop_topology.Edge_equalize.fn

let edge_relax = Sop_topology.Edge_relax.fn

let blend_shapes = Sop_attributes.Blend_shapes.fn

let attribute_composite = Sop_attributes.Attribute_composite.fn

type mirror_method = Sop_support.mirror_method = Mirror_plane | Mirror_mapping
type mirror_transform = Sop_support.mirror_transform = Mirror_copy | Mirror_uv | Mirror_vector | Mirror_point

let attribute_mirror = Sop_attributes.Attribute_mirror.fn

let rewire_vertices = Sop_topology.Rewire_vertices.fn

type transport_roots = Sop_support.transport_roots = Transport_first | Transport_last | Transport_group

let edge_transport = Sop_attributes.Edge_transport.fn

let edge_transport_curves = Sop_attributes.Edge_transport_curves.fn

let edge_transport_parent = Sop_attributes.Edge_transport_parent.fn

let copy_to_points = Sop_shapes.Copy_to_points.fn

let duplicate = Sop_shapes.Duplicate.fn

let switch = Sop_shapes.Switch.fn

let null = Sop_shapes.Null.fn

let triangulate = Sop_topology.Triangulate.fn

type triangulate_2d_projection = Sop_support.triangulate_2d_projection = Triangulate_best_fit | Triangulate_xy | Triangulate_yz | Triangulate_zx | Triangulate_plane | Triangulate_attribute
let triangulate_2d = Sop_topology.Triangulate_2d.fn

let remesh = Sop_topology.Remesh.fn

type boolean_closed_policy = Sop_support.boolean_closed_policy = Closed_default | Closed_required | Closed_not_required
let boolean = Sop_topology.Boolean.fn

let boolean_fracture = Sop_topology.Boolean_fracture.fn

let boolean_seam = Sop_topology.Boolean_seam.fn

let boolean_detect = Sop_topology.Boolean_detect.fn

let intersection_analysis = Sop_topology.Intersection_analysis.fn

type poly_reduce_target = Sop_support.poly_reduce_target = Reduce_ratio | Reduce_primitive_count
let poly_reduce = Sop_topology.Poly_reduce.fn

type reverse_operation = Sop_support.reverse_operation = Reverse | Shift

let reverse = Sop_topology.Reverse.fn

let normals = Sop_attributes.Normal.fn

let measure_curvature = Sop_attributes.Measure_curvature.fn

let attribute_laplacian = Sop_attributes.Attribute_laplacian.fn

let polyframe = Sop_attributes.Polyframe.fn

let smooth = Sop_shapes.Smooth.fn

type kernel_mode = Sop_support.kernel_mode = Kernel_explicit | Kernel_auto
type clean_overlap = Sop_support.clean_overlap = Clean_keep_first | Clean_delete_pairs | Clean_overlap_auto

let clean = Sop_topology.Clean.fn

type facet_consolidation = Sop_support.facet_consolidation =
  Consolidation_none | Consolidation_points | Consolidation_normals
let facet = Sop_topology.Facet.fn

let poly_extrude = Sop_topology.Poly_extrude.fn

let poly_fill = Sop_topology.Poly_fill.fn

let resample = Sop_topology.Resample.fn

type extract_point_cut = Sop_support.extract_point_cut =
  Extract_point_constant | Extract_point_primitive_attribute | Extract_point_current_time
let extract_point_from_curve = Sop_shapes.Extract_point_from_curve.fn

let convert_line = Sop_topology.Convert_line.fn

let carve = Sop_topology.Carve.fn

let ends = Sop_topology.Ends.fn

let join_curves = Sop_topology.Join_curves.fn

let poly_path = Sop_topology.Poly_path.fn

let revolve = Sop_topology.Revolve.fn

let sweep = Sop_topology.Sweep.fn

let polywire = Sop_topology.Polywire.fn

let sweep_circle = Sop_topology.Polywire.sweep_fn

let measure = Sop_attributes.Measure.fn

let connectivity = Sop_attributes.Connectivity.fn

let uv_project = Sop_attributes.Uv_project.fn

let uv_transform = Sop_attributes.Uv_transform.fn

let uv_auto_seam = Sop_attributes.Uv_auto_seam.fn

let group_edges = Sop_groups.Group_edges.fn

let group_from_attribute_boundary = Sop_groups.Group_from_attribute_boundary.fn

let groups_from_name = Sop_groups.Groups_from_name.fn

let name_from_groups = Sop_groups.Name_from_groups.fn

let uv_unitize = Sop_attributes.Uv_unitize.fn

let uv_flatten = Sop_attributes.Uv_flatten.fn

let uv_relax = Sop_attributes.Uv_relax.fn

let promote_attributes = Sop_attributes.Promote_attributes.fn

let enumerate = Sop_attributes.Enumerate.fn

let attribute_blur = Sop_attributes.Attribute_blur.fn

type copy_match = Sop_support.copy_match = Copy_cyclic | Copy_by_values | Copy_to_element
let attribute_copy = Sop_attributes.Attribute_copy.fn

type interpolate_driver = Sop_support.interpolate_driver = Interpolate_primitive_uvw | Interpolate_point_weights | Interpolate_vertex_weights | Interpolate_primitive_weights
let attribute_interpolate = Sop_attributes.Attribute_interpolate.fn

type transfer_falloff = Sop_support.transfer_falloff = Transfer_linear | Transfer_smoothstep | Transfer_uniform
type transfer_mode = Sop_support.transfer_mode = Transfer_nearest | Transfer_inverse | Transfer_links
  | Transfer_renderman | Transfer_hart
let attribute_transfer = Sop_attributes.Attribute_transfer.fn

let attribute_transfer_surface = Sop_attributes.Attribute_transfer_surface.fn

let attribute_transfer_all = Sop_attributes.Attribute_transfer_all.fn

let set_float = Sop_attributes.Set_float.fn

let material = Sop_attributes.Material.fn

let set_int = Sop_attributes.Set_int.fn

let set_vector = Sop_attributes.Set_vector.fn

let set_orient = Sop_attributes.Set_orient.fn

let set_transform = Sop_attributes.Set_transform.fn
let rest_position = Sop_attributes.Rest_position.fn

let set_color = Sop_attributes.Set_color.fn

let set_color_float = set_color

let delete_attributes = Sop_attributes.Delete_attributes.fn

let rename_attributes = Sop_attributes.Rename_attributes.fn

let swap_attributes = Sop_attributes.Swap_attributes.fn

let delete_edge_group = Sop_groups.Delete_edge_group.fn

let rename_edge_group = Sop_groups.Rename_edge_group.fn

let group ?label ~name selection input =
  if String.trim name = "" then invalid_arg "Sop.group: empty name";
  Node.Private.make_geometry ?label ~operation:"group" ~version:1
    ~parameters:(Printf.sprintf "name=%S;selection=%s" name
      (Select.fingerprint selection))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      match Select.evaluate ~name selection inputs.(0) with
      | Error message -> rdk_error "group" message
      | Ok group ->
          match Rdk.Geometry.with_group group inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error message -> rdk_error "group" message)

let ordered_group = Sop_groups.Ordered_group.fn

let group_promotions = Sop_groups.Group_promotions.fn

let group_promote_boundary = Sop_groups.Group_promote_boundary.fn

let group_expand = Sop_groups.Group_expand.fn

let group_combine = Sop_groups.Group_combine.fn

type group_range_mode = Sop_support.group_range_mode =
  Start_end | From_ends | Start_length | Partition
type group_range_connectivity = Sop_support.group_range_connectivity =
  No_connectivity | Disconnected | Connected

let group_range = Sop_groups.Group_range.fn

let group_ranges = Sop_groups.Group_ranges.fn

let group_invert = Sop_groups.Group_invert.fn

let group_delete = Sop_groups.Group_delete.fn

let group_rename = Sop_groups.Group_rename.fn

let group_copy = Sop_groups.Group_copy.fn

let group_transfer = Sop_groups.Group_transfer.fn

let group_find_path = Sop_groups.Group_find_path.fn

type blast_attribute_mode = Sop_support.blast_attribute_mode = Blast_below | Blast_range | Blast_width
type blast_attribute_output = Sop_support.blast_attribute_output = Blast_delete | Blast_group
let blast_by_attribute = Sop_topology.Blast_by_attribute.fn

let blast = Sop_topology.Blast.fn

let compact_points = Sop_topology.Compact_points.fn

let match_axis = Sop_shapes.Match_axis.fn

type sort_key = Sop_support.sort_key = Sort_x | Sort_y | Sort_z | Sort_distance
  | Sort_vector | Sort_attribute | Sort_vertex_order | Sort_primitive_index
  | Sort_spatial | Sort_random | Sort_index_attribute | Sort_reverse | Sort_shift

let sort = Sop_shapes.Sort.fn

type target_justify_mode = Sop_support.target_justify_mode = Justify_explicit | Justify_auto

let match_size = Sop_shapes.Match_size.fn

let custom ?label ?(version = 1) ?(parameters = "")
    ?(cook_mode = Node.Generic) ?(dependencies = Context.Dependencies.static)
    ~operation inputs cook =
  let inputs = Array.of_list inputs in
  Node.Private.make_geometry ?label ~operation ~version ~parameters ~cook_mode
    ~dependencies ~inputs (fun ~node_id:_ context geometries ->
      if Context.cancelled context then
        Error (Diagnostic.error ~code:"cancelled"
          "custom procedural node was cancelled before cooking")
      else match cook ~context (Array.copy geometries) with
        | Ok geometry -> cooked geometry
        | Error message -> rdk_error operation message)

let group_random = Sop_groups.Group_random.fn

type group_bounds_shape = Sop_support.group_bounds_shape = Box | Sphere

let group_bounds = Sop_groups.Group_bounds.fn

let group_normal = Sop_groups.Group_normal.fn

let group_non_planar = Sop_groups.Group_non_planar.fn

let group_backface = Sop_groups.Group_backface.fn

let group_edge_depth = Sop_groups.Group_edge_depth.fn

let group_unshared = Sop_groups.Group_unshared.fn

let group_boundary_components = Sop_groups.Group_boundary_components.fn

let convex_hull = Sop_topology.Convex_hull.fn

type centroid_run_mode = Sop_support.centroid_run_mode =
  Detail | Primitives | Point_pieces | Primitive_pieces

let extract_centroid = Sop_shapes.Extract_centroid.fn

let bound = Sop_shapes.Bound.fn

type ray_direction = Sop_support.ray_direction = Direction_vector | Direction_normal | Direction_attribute
let ray = Sop_shapes.Ray.fn

let peak = Sop_shapes.Peak.fn

let bend = Sop_shapes.Bend.fn

let mountain = Sop_shapes.Mountain.fn

type point_generation_mode = Sop_support.point_generation_mode = Point_generate_total | Point_generate_per_point | Point_generate_probability
let point_generate = Sop_shapes.Point_generate_from_input.fn

let point_replicate = Sop_shapes.Point_replicate.fn

let point_jitter = Sop_shapes.Point_jitter.fn

let exploded_view = Sop_shapes.Exploded_view.fn

type numeric_kind = Sop_support.numeric_kind = Numeric_scalar | Numeric_vec2 | Numeric_vec3 | Numeric_vec4
type random_distribution = Sop_support.random_distribution =
  Random_constant | Random_two_values | Random_uniform | Random_uniform_discrete | Random_normal | Random_exponential | Random_log_normal | Random_cauchy | Random_direction | Random_inside_sphere | Random_inside_sphere_cone | Random_custom_ramp | Random_custom_discrete | Random_custom_discrete_text

let attribute_randomize = Sop_attributes.Attribute_randomize.fn

let attribute_noise_quaternion = Sop_attributes.Attribute_noise_quaternion.fn

type noise_location = Sop_support.noise_location = Noise_position | Noise_element_number | Noise_attribute
type noise_range = Sop_support.noise_range = Noise_positive | Noise_zero_centered | Noise_min_max

let attribute_noise = Sop_attributes.Attribute_noise.fn

type remap_range = Sop_support.remap_range = Remap_automatic | Remap_explicit

let attribute_remap = Sop_attributes.Attribute_remap.fn

let noise_displace = Sop_shapes.Noise_displace.fn

let color_by_height = Sop_attributes.Color_by_height.fn

let scatter = Sop_shapes.Scatter.fn

type velocity_initialization = Sop_support.velocity_initialization = Velocity_compute | Velocity_keep | Velocity_set | Velocity_from_attribute
let point_velocity = Sop_attributes.Point_velocity.fn
