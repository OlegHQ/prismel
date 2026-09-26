open Prismel_math

type clip_keep = Plane_clip.keep = Above | Below | All
type subdivision_scheme = Subdivision_ops.scheme = Catmull_clark | Loop | Bilinear
type subdivision_boundary_interpolation = Subdivision_ops.boundary_interpolation =
  | Subdivide_boundary_none
  | Subdivide_boundary_edge_only
  | Subdivide_boundary_edge_and_corner
type subdivision_face_varying_interpolation = Subdivision_ops.face_varying_interpolation =
  | Subdivide_fvar_none
  | Subdivide_fvar_corners_only
  | Subdivide_fvar_corners_plus1
  | Subdivide_fvar_corners_plus2
  | Subdivide_fvar_boundaries
  | Subdivide_fvar_all
type subdivision_triangle_policy = Subdivision_ops.triangle_policy =
  | Subdivide_triangles_catmull_clark
  | Subdivide_triangles_smooth
type subdivision_creasing_method = Subdivision_ops.creasing_method =
  | Subdivide_creasing_uniform
  | Subdivide_creasing_chaikin
type subdivision_crack_policy = Subdivision_ops.crack_policy =
  | Subdivide_do_not_close
  | Subdivide_pull_no_edge_division
  | Subdivide_pull_divide_edges of float
  | Subdivide_pull_triangulate of float
  | Subdivide_stitch_no_edge_division
  | Subdivide_stitch_divide_edges
  | Subdivide_stitch_triangulate
type scatter_density = Scatter.density = {
  density_owner : Attribute.owner;
  density_attribute : string;
}
type poly_reduce_target = Poly_reduce.target =
  | Reduce_ratio of float
  | Reduce_primitive_count of int
type poly_fill_mode = Poly_fill.mode =
  | Fill_single_polygon
  | Fill_triangles
  | Fill_triangle_fan
type sort_owner = Ordering.owner = Points | Primitives
type sort_key = Ordering.key =
  | X | Y | Z
  | Distance_to of Vec3.t
  | Along_vector of Vec3.t
  | Attribute_component of { name : string; component : int }
  | By_vertex_order
  | By_primitive_index
  | Spatial_locality
  | Random of int64
  | Index_attribute of string
  | Reverse
  | Shift of int
type deform_selection = Transform_ops.deform_selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t

type transform_order = Transform_ops.transform_order =
  | Transform_srt | Transform_str | Transform_rst
  | Transform_rts | Transform_tsr | Transform_trs

type transform_rotation_order = Transform_ops.transform_rotation_order =
  | Transform_xyz | Transform_xzy | Transform_yxz
  | Transform_yzx | Transform_zxy | Transform_zyx

type soft_transform_metric = Transform_ops.soft_transform_metric =
  | Soft_radius
  | Soft_edge
  | Soft_attribute of { attribute : string; apply_rolloff : bool }

type soft_transform_falloff = Transform_ops.soft_transform_falloff =
  Soft_linear | Soft_quadratic | Soft_cubic

type distance_along_radius = Transform_ops.distance_along_radius =
  | Distance_fixed of float
  | Distance_maximum

type distance_from_geometry_reference = Transform_ops.distance_from_geometry_reference =
  | Distance_reference_points
  | Distance_reference_primitives

type distance_from_target_projection = Transform_ops.distance_from_target_projection =
  | Distance_target_spherical
  | Distance_target_cylindrical
  | Distance_target_planar

type distance_from_target_metric = Transform_ops.distance_from_target_metric =
  | Distance_target_absolute
  | Distance_target_signed
type dissolve_operation = Dissolve.operation =
  | Dissolve_selected | Dissolve_non_selected
type dissolve_bridge_policy = Dissolve.bridge_policy =
  | Create_bridged_polygons
  | Create_disjoint_polygons
  | Delete_bridge_polygons
type normal_weighting = Normal_ops.weighting =
  | Vertex_angle
  | Each_vertex
  | Face_area
type curvature_boundary = Curvature.boundary =
  | Curvature_boundary_zero
  | Curvature_boundary_one_sided
type curvature_outputs = Curvature.outputs = {
  mean : string option;
  gaussian : string option;
  minimum : string option;
  maximum : string option;
  curvedness : string option;
  shape_index : string option;
}
let default_curvature_outputs = Curvature.default_outputs
type laplacian_weighting = Laplacian.weighting =
  | Laplacian_cotan
  | Laplacian_positive_cotan
  | Laplacian_uniform
type polyframe_style = Polyframe.style =
  | First_edge
  | Two_edges
  | Primitive_centroid
  | Texture_uv of string
  | Texture_uv_gradient of string
  | Attribute_gradient of string
type line_kind = Line_geometry.kind = Line_curve | Line_points
type circle_arc = Plane_generators.circle_arc =
  | Circle_closed
  | Circle_open_arc of { start_angle : float; end_angle : float }
  | Circle_closed_arc of { start_angle : float; end_angle : float }
  | Circle_sliced_arc of { start_angle : float; end_angle : float }
type circle_orientation = Plane_generators.circle_orientation =
  | Circle_xy | Circle_xz | Circle_yz
  | Circle_axes of { horizontal : Vec3.t; vertical : Vec3.t }
type box_connectivity = Box_generator.box_connectivity =
  | Box_triangles
  | Box_quads
  | Box_surface_points
  | Box_lattice_points
type box_normals = Box_generator.box_normals = Box_no_normals | Box_point_normals | Box_vertex_normals
type box_rotation_order = Box_generator.box_rotation_order =
  | Box_xyz | Box_xzy | Box_yxz | Box_yzx | Box_zxy | Box_zyx
type sphere_connectivity = Uv_sphere.sphere_connectivity =
  | Sphere_triangles
  | Sphere_alternating_triangles
  | Sphere_quads
  | Sphere_rows
  | Sphere_columns
  | Sphere_rows_and_columns
  | Sphere_points
type sphere_normals = Uv_sphere.sphere_normals =
  | Sphere_no_normals | Sphere_point_normals | Sphere_vertex_normals
type sphere_orientation = Uv_sphere.sphere_orientation =
  | Sphere_x | Sphere_y | Sphere_z | Sphere_axis of Vec3.t
type sphere_rotation_order = Uv_sphere.sphere_rotation_order =
  | Sphere_xyz | Sphere_xzy | Sphere_yxz
  | Sphere_yzx | Sphere_zxy | Sphere_zyx
type torus_connectivity = Parametric_generators.torus_connectivity =
  | Torus_triangles
  | Torus_alternating_triangles
  | Torus_quads
  | Torus_rows
  | Torus_columns
  | Torus_rows_and_columns
  | Torus_points
type torus_normals = Parametric_generators.torus_normals =
  | Torus_no_normals | Torus_point_normals | Torus_vertex_normals
type torus_orientation = Parametric_generators.torus_orientation =
  | Torus_x | Torus_y | Torus_z | Torus_axis of Vec3.t
type torus_rotation_order = Parametric_generators.torus_rotation_order =
  | Torus_xyz | Torus_xzy | Torus_yxz
  | Torus_yzx | Torus_zxy | Torus_zyx
type tube_connectivity = Parametric_generators.tube_connectivity =
  | Tube_triangles
  | Tube_alternating_triangles
  | Tube_quads
  | Tube_rows
  | Tube_columns
  | Tube_rows_and_columns
  | Tube_points
type tube_normals = Parametric_generators.tube_normals =
  | Tube_no_normals | Tube_point_normals | Tube_vertex_normals
type tube_orientation = Parametric_generators.tube_orientation =
  | Tube_x | Tube_y | Tube_z | Tube_axis of Vec3.t
type tube_rotation_order = Parametric_generators.tube_rotation_order =
  | Tube_xyz | Tube_xzy | Tube_yxz
  | Tube_yzx | Tube_zxy | Tube_zyx
type platonic_kind = Parametric_generators.platonic_kind =
  | Platonic_tetrahedron
  | Platonic_cube
  | Platonic_octahedron
  | Platonic_icosahedron
  | Platonic_dodecahedron
  | Platonic_soccer_ball
type platonic_normals = Parametric_generators.platonic_normals =
  | Platonic_no_normals | Platonic_point_normals | Platonic_vertex_normals
type platonic_orientation = Parametric_generators.platonic_orientation =
  | Platonic_x | Platonic_y | Platonic_z | Platonic_axis of Vec3.t
type platonic_rotation_order = Parametric_generators.platonic_rotation_order =
  | Platonic_xyz | Platonic_xzy | Platonic_yxz
  | Platonic_yzx | Platonic_zxy | Platonic_zyx
type spiral_extent = Spiral.extent =
  | Spiral_turns of { turns : float; height : float }
  | Spiral_height_pitch of { height : float; pitch : float }
type spiral_radius = Spiral.radius =
  | Spiral_archimedean_change of {
      start_radius : float; increase_per_turn : float;
    }
  | Spiral_archimedean_end of { start_radius : float; end_radius : float }
  | Spiral_logarithmic_change of {
      start_radius : float; scale_per_turn : float;
    }
  | Spiral_logarithmic_end of { start_radius : float; end_radius : float }
type spiral_direction = Spiral.direction =
  | Spiral_counterclockwise | Spiral_clockwise
type spiral_divisions = Spiral.divisions =
  | Spiral_divisions_per_curve of int
  | Spiral_divisions_per_turn of int
type spiral_orientation = Spiral.orientation =
  | Spiral_x | Spiral_y | Spiral_z | Spiral_axis of Vec3.t
type spiral_rotation_order = Spiral.rotation_order =
  | Spiral_xyz | Spiral_xzy | Spiral_yxz
  | Spiral_yzx | Spiral_zxy | Spiral_zyx
type grid_counts = Plane_generators.grid_counts =
  Grid_divisions | Grid_point_counts
type grid_orientation = Plane_generators.grid_orientation =
  | Grid_xy | Grid_xz | Grid_yz
  | Grid_axes of { horizontal : Vec3.t; vertical : Vec3.t }
type grid_connectivity = Plane_generators.grid_connectivity =
  | Grid_points | Grid_rows | Grid_columns | Grid_rows_and_columns
  | Grid_quads | Grid_triangles | Grid_alternating_triangles
  | Grid_reverse_triangles
let points = Line_geometry.points


type fuse_position = Fuse_reduce.position =
  | First_position
  | Least_point_position
  | Greatest_point_position
  | Average_position
  | Minimum_position
  | Maximum_position
  | Mode_position
  | Median_position
  | Sum_position
  | Sum_squares_position
  | Root_mean_square_position
  | Weighted_average_position
  | Weighted_sum_position
  | Minimum_weight_position
  | Maximum_weight_position
type fuse_attributes = Fuse_reduce.attributes = Keep_first | Average_numeric
type fuse_attribute_method = Fuse_reduce.attribute_method =
  | Attribute_average
  | Attribute_least_point
  | Attribute_greatest_point
  | Attribute_maximum
  | Attribute_minimum
  | Attribute_mode
  | Attribute_median
  | Attribute_sum
  | Attribute_sum_squares
  | Attribute_root_mean_square
  | Attribute_concatenate
  | Attribute_weighted_average
  | Attribute_weighted_sum
  | Attribute_minimum_weight
  | Attribute_maximum_weight
  | Attribute_concatenate_weight_order
type fuse_attribute_rule = Fuse_reduce.attribute_rule = {
  pattern : string;
  method_ : fuse_attribute_method;
  weight_attribute : string option;
}
type fuse_group_method = Fuse_reduce.group_method =
  | Group_least_point
  | Group_greatest_point
  | Group_union
  | Group_intersection
  | Group_most_common
type fuse_group_rule = Fuse_reduce.group_rule = {
  group_pattern : string;
  group_method : fuse_group_method;
}

let fuse_attribute_rule = Fuse_grid.fuse_attribute_rule
let fuse_group_rule = Fuse_grid.fuse_group_rule
type fuse_metric = Fuse_grid.fuse_metric = Euclidean | Componentwise
type fuse_using = Fuse_grid.fuse_using =
  | Least_target_point
  | Closest_target_point
type fuse_match_condition = Fuse_grid.fuse_match_condition =
  | Equal_attribute_values
  | Unequal_attribute_values
type fuse_targeting = Fuse_grid.fuse_targeting =
  | Near_points
  | Specified_points of string
type grid_rounding = Fuse_grid.grid_rounding = Grid_nearest | Grid_down | Grid_up

let measure_curvature ?cancel ?grain ?points ?boundary ?smoothing_iterations
    ?smoothing_strength ?outputs geometry =
  Curvature.run ?cancel ?grain ?points ?boundary ?smoothing_iterations
    ?smoothing_strength ?outputs geometry

let attribute_laplacian ?cancel ?grain ?points ?weighting ?normalize ~source
    ?output geometry =
  Laplacian.run ?cancel ?grain ?points ?weighting ?normalize ~source ?output
    geometry

let polyframe ?cancel ?grain ?selection ?orthogonal ?left_handed ?normal_attribute
    ?tangent_attribute ?bitangent_attribute style geometry =
  Polyframe.run ?cancel ?grain ?selection ?orthogonal ?left_handed ?normal_attribute
    ?tangent_attribute ?bitangent_attribute style geometry

type copy_target_owner = Instance_copy.copy_target_owner =
  | Copy_target_points | Copy_target_vertices | Copy_target_primitives
type copy_target_operation = Instance_copy.copy_target_operation =
  | Copy_target_nothing | Copy_target_copy | Copy_target_add
  | Copy_target_subtract | Copy_target_multiply
type copy_target_attribute_rule = Instance_copy.copy_target_attribute_rule = {
  copy_target_pattern : string;
  copy_target_owner : copy_target_owner;
  copy_target_operation : copy_target_operation;
}

let transform = Transform_ops.transform

type bound_shape = Bound.bound_shape =
  | Bound_box of { divisions : int * int * int }
  | Bound_sphere of { segments : int; rings : int; minimum_radius : float }

type match_size_fit = Match_size.match_size_fit =
  | Translate_only | Stretch | Contain | Cover
  | Match_x | Match_y | Match_z
  | Match_perimeter | Match_area | Match_volume

type point_generate_mode = Point_generate.mode =
  | Generate_total of int
  | Generate_per_point of {
      points_per_point : float;
      scale_attribute : string option;
    }
  | Generate_probability of { attribute : string }

let detailed operation code result =
  Result.map_error (Error.of_string ~operation ~code) result

let protected operation code work =
  try detailed operation code (work ()) with
  | Cancel.Cancelled -> Error (Error.make ~operation ~code:"cancelled"
      "geometry operation was cancelled")

let polyline = Line_geometry.polyline_checked
let line = Line_geometry.line_checked
let circle = Plane_generators.circle_checked
let box = Box_generator.box_checked
let uv_sphere = Uv_sphere.run_checked

let torus = Parametric_generators.torus_checked
let tube = Parametric_generators.tube_checked
let platonic = Parametric_generators.platonic_checked

let spiral = Spiral.run

let merge = Mesh_merge.run

let fuse = Fuse_grid.fuse_checked

let edge_collapse = Edge_collapse.run

let dissolve = Dissolve.run_checked

let snap_to_grid = Fuse_grid.snap_to_grid_checked

let boolean_detect ?cancel ?(grain = 16_384) ?source_primitives
    ?collision_primitives ?(tolerance = 0.) ?(include_coplanar = true)
    ?(intersecting_group = Some "boolean_intersections")
    ?intersections_attribute ?count_attribute ?self_intersecting_group
    ?self_intersections_attribute ?self_count_attribute ~collision geometry =
  Boolean_detect.run ?cancel ~grain ?source_primitives ?collision_primitives
    ~tolerance ~include_coplanar ~intersecting_group ~intersections_attribute
    ~count_attribute ~self_intersecting_group ~self_intersections_attribute
    ~self_count_attribute ~collision geometry


let poly_reduce = Poly_reduce.run_checked
let edge_flip = Edge_flip.run_checked

type blend_shapes_mode = Blend_shapes.mode =
  | Blend_normalized
  | Blend_differencing

type blend_shapes_masking = Blend_shapes.masking =
  | Blend_no_mask
  | Blend_set_from_attribute
  | Blend_scale_from_attribute

type blend_shape_mask_source = Blend_shapes.mask_source =
  | Blend_mask_first_input
  | Blend_mask_shape

type blend_shape = Blend_shapes.shape

let blend_shape = Blend_shapes.shape

let blend_shapes ?cancel ?grain ?points ?mode ?masking ?mask_attribute
    ?point_id_attribute ?attributes ~shapes geometry =
  Blend_shapes.run_checked ?cancel ?grain ?points ?mode ?masking
    ?mask_attribute ?point_id_attribute ?attributes ~shapes geometry

type attribute_composite_operation = Attribute_composite.operation =
  | Composite_mean
  | Composite_maximum
  | Composite_minimum
  | Composite_over
  | Composite_under

type attribute_composite_input = Attribute_composite.input

let attribute_composite_input = Attribute_composite.input

let attribute_composite ?cancel ?grain ?operation ?weight ?detail_attributes
    ?primitive_attributes ?point_attributes ?vertex_attributes ?allow_position
    ?alpha_attribute ~inputs geometry =
  Attribute_composite.run_checked ?cancel ?grain ?operation ?weight
    ?detail_attributes ?primitive_attributes ?point_attributes
    ?vertex_attributes ?allow_position ?alpha_attribute ~inputs geometry

type attribute_mirror_owner = Attribute_mirror.owner =
  | Mirror_point_attributes
  | Mirror_vertex_attributes
  | Mirror_primitive_attributes

type attribute_mirror_group_use = Attribute_mirror.group_use =
  | Mirror_group_as_source
  | Mirror_group_as_destination

type attribute_mirror_method = Attribute_mirror.method_ =
  | Mirror_by_plane of {
      origin : Vec3.t;
      normal : Vec3.t;
      distance : float;
      tolerance : float;
    }
  | Mirror_by_mapping of {
      mapping_attribute : string;
      destination_group : Group.t;
    }

type attribute_mirror_transform = Attribute_mirror.transform =
  | Mirror_copy
  | Mirror_uv of {
      origin_u : float;
      origin_v : float;
      direction_u : float;
      direction_v : float;
    }
  | Mirror_vector
  | Mirror_point

let attribute_mirror ?cancel ?grain ?group ?group_use ?attributes ?transform
    ?string_replace ?output_mapping ?source_group ?destination_group ~owner
    ~method_ geometry =
  Attribute_mirror.run_checked ?cancel ?grain ?group ?group_use ?attributes
    ?transform ?string_replace ?output_mapping ?source_group
    ?destination_group ~owner ~method_ geometry

let clip = Plane_clip.clip_checked
let clip_transform = Plane_clip.clip_transform_checked

let attribute_fade ?cancel ?grain ?points ?start_source ?hold_source
    ?fade_attribute ?start_attribute ?start_retime ?hold_scale_attribute ~frame
    ?frame_offset ?fade_in ?fade_hold ?fade_out ?fade_in_ramp ?fade_out_ramp
    ?visualize geometry =
  Attribute_fade.fade_checked ?cancel ?grain ?points ?start_source ?hold_source
    ?fade_attribute ?start_attribute ?start_retime ?hold_scale_attribute
    ~frame ?frame_offset ?fade_in ?fade_hold ?fade_out ?fade_in_ramp
    ?fade_out_ramp ?visualize geometry

let subdivide = Subdivision_ops.subdivide_checked

let normals ?cancel ?grain ?selection ?owner ?weighting ?cusp_angle
    ?keep_original_zero ?reverse ?attribute geometry =
  Normal_ops.run_checked ?cancel ?grain ?selection ?owner ?weighting
    ?cusp_angle ?keep_original_zero ?reverse ?attribute geometry

let measure_curvature_raw = measure_curvature
let measure_curvature ?cancel ?grain ?points ?boundary ?smoothing_iterations
    ?smoothing_strength ?outputs geometry =
  protected "measure_curvature" "invalid_curvature" (fun () ->
    measure_curvature_raw ?cancel ?grain ?points ?boundary
      ?smoothing_iterations ?smoothing_strength ?outputs geometry)

let attribute_laplacian_raw = attribute_laplacian
let attribute_laplacian ?cancel ?grain ?points ?weighting ?normalize ~source
    ?output geometry =
  protected "attribute_laplacian" "invalid_laplacian" (fun () ->
    attribute_laplacian_raw ?cancel ?grain ?points ?weighting ?normalize
      ~source ?output geometry)

let polyframe_raw = polyframe
let polyframe ?cancel ?grain ?selection ?orthogonal ?left_handed ?normal_attribute
    ?tangent_attribute ?bitangent_attribute style geometry =
  protected "polyframe" "invalid_geometry" (fun () ->
    polyframe_raw ?cancel ?grain ?selection ?orthogonal ?left_handed
      ?normal_attribute ?tangent_attribute ?bitangent_attribute style geometry)

let delete_primitives = Deletion.delete_primitives

let compact_points = Compact_points.run_checked

let bound = Bound.run_checked
let bounding_box = Bound.bounding_box_checked
let match_axis = Match_size.match_axis_checked

let sort = Ordering.sort_checked

let match_size = Match_size.run_checked

let scatter_density ~owner density_attribute = { density_owner = owner;
  density_attribute }

let scatter_surface ?cancel ?grain ?primitives ?density ?point_pattern
    ?vertex_pattern ?primitive_pattern ?detail_pattern ?match_groups
    ?source_primitive_attribute ?source_vertex_numbers_attribute
    ?source_vertex_weights_attribute ~count ~seed geometry =
  protected "scatter_surface" "invalid_geometry"
    (fun () -> Scatter.run ?cancel ?grain ?primitives ?density ?point_pattern
      ?vertex_pattern ?primitive_pattern ?detail_pattern ?match_groups
      ?source_primitive_attribute ?source_vertex_numbers_attribute
      ?source_vertex_weights_attribute ~count ~seed geometry)

let copy_to_points = Instance_copy.copy_to_points
let materialize_instances = Instance_copy.materialize_instances
let duplicate = Instance_copy.duplicate

let compose_transform = Transform_ops.compose_transform
let transform_selected = Transform_ops.transform_selected
let soft_transform = Transform_ops.soft_transform
let distance_along_geometry = Transform_ops.distance_along_geometry
let distance_from_geometry = Transform_ops.distance_from_geometry
let distance_from_target = Transform_ops.distance_from_target

let noise_displace = Deform_ops.noise_displace_checked
let peak = Deform_ops.peak_checked
let bend = Deform_ops.bend_checked
let mountain = Deform_ops.mountain_checked
let point_jitter = Deform_ops.point_jitter_checked

let point_generate = Point_generate.run_checked

let color_by_height = Pdk_attrib.Color_by_height.run

let facet = Facet_ops.run_checked

let poly_fill = Poly_fill.run_checked

let resample_curves = Curve_modeling.resample_curves_checked

type carve_keep = Curve_modeling.carve_keep =
  | Keep_inside | Keep_outside | Keep_inside_and_outside
type carve_attribute_mode = Curve_modeling.carve_attribute_mode =
  | Attribute_replace | Attribute_scale

let carve_curves = Curve_modeling.carve_curves_checked


let sweep_circle = Curve_modeling.sweep_circle_checked
