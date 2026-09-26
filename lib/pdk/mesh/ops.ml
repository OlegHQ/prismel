open Prismel_math

type clip_keep = Plane_clip.keep = Above | Below | All
type subdivision_scheme = Subdivide.scheme = Catmull_clark | Loop | Bilinear
type subdivision_boundary_interpolation = Subdivide.boundary_interpolation =
  | Subdivide_boundary_none
  | Subdivide_boundary_edge_only
  | Subdivide_boundary_edge_and_corner
type subdivision_face_varying_interpolation = Subdivide.face_varying_interpolation =
  | Subdivide_fvar_none
  | Subdivide_fvar_corners_only
  | Subdivide_fvar_corners_plus1
  | Subdivide_fvar_corners_plus2
  | Subdivide_fvar_boundaries
  | Subdivide_fvar_all
type subdivision_triangle_policy = Subdivide.triangle_subdivision =
  | Subdivide_triangles_catmull_clark
  | Subdivide_triangles_smooth
type subdivision_creasing_method = Subdivide.creasing_method =
  | Subdivide_creasing_uniform
  | Subdivide_creasing_chaikin
type subdivision_crack_policy = Subdivide.crack_policy =
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
type smooth_boundary = Smooth.boundary =
  | Smooth_free
  | Smooth_unshared
  | Smooth_group_boundary
type ray_method = Ray.method_ = Ray_minimum_distance | Ray_project
type ray_direction = Ray.direction =
  | Ray_vector of Vec3.t
  | Ray_normal
  | Ray_attribute of string
type ray_direction_mode = Ray.direction_mode =
  | Ray_forward
  | Ray_reverse
  | Ray_bidirectional_closest
  | Ray_bidirectional_farthest
type ray_surface_hit = Ray.surface_hit = Ray_first_surface | Ray_last_surface
type ray_combine = Ray.combine =
  | Ray_average
  | Ray_median
  | Ray_shortest
  | Ray_longest
type delete_topology_policy = Deletion.topology_policy =
  | Destroy_touched_primitives
  | Heal_primitives
type blast_attribute_owner = Blast_by_attribute.owner =
  | Blast_points
  | Blast_primitives
type blast_attribute_mode = Blast_by_attribute.mode =
  | Blast_below of float
  | Blast_range of { minimum : float; maximum : float }
  | Blast_width of { center : float; width : float }
type blast_attribute_output = Blast_by_attribute.output =
  | Blast_delete
  | Blast_group of string
type crease_operation = Crease.operation =
  | Crease_add
  | Crease_set
  | Crease_delete
type poly_loft_minimize = Poly_loft.minimize =
  | Two_point_distance
  | Three_point_distance
type poly_bridge_pairing = Poly_bridge.pairing =
  | Bridge_by_order
  | Bridge_by_centroid
type poly_reduce_target = Poly_reduce.target =
  | Reduce_ratio of float
  | Reduce_primitive_count of int
type poly_bevel_shape = Poly_bevel.shape =
  | Bevel_chamfer
  | Bevel_round of { convexity : float }
type poly_extrude_divide = Poly_extrude.divide =
  | Extrude_individual
  | Extrude_connected_components
type poly_fill_mode = Poly_fill.mode =
  | Fill_single_polygon
  | Fill_triangles
  | Fill_triangle_fan
type clean_overlap_policy =
  | Keep_first_overlap
  | Delete_overlap_pairs
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
type uv_projection = Uv_ops.projection =
  | Planar of { origin : Vec3.t; u_axis : Vec3.t; v_axis : Vec3.t }
  | Cylindrical of {
      origin : Vec3.t; axis : Vec3.t; seam : Vec3.t; height : float;
    }
  | Spherical of { origin : Vec3.t; axis : Vec3.t; seam : Vec3.t }
type uv_unitize_mode = Uv_ops.unitize_mode = Per_face | Islands
type edge_incidence = Edge_ops.incidence =
  | Any_edge | Boundary_edge | Manifold_edge | Non_manifold_edge
type edge_angle_basis = Edge_ops.angle_basis =
  | Primitive_dihedral | Incident_edges
type group_owner = Group_ops.owner =
  | Group_points | Group_vertices | Group_primitives | Group_edges
type group_promote_mode = Group_ops.promote_mode =
  | Include_any | Include_all | Include_shared_edge
type group_boundary_attribute = Group_ops.boundary_attribute = {
  boundary_attribute_owner : Attribute.owner;
  boundary_attribute_pattern : string;
}
type group_promote_boundary_options = Group_ops.promote_boundary_options = {
  promote_boundary_attributes : group_boundary_attribute list;
  promote_boundary_tolerance : float;
  promote_include_unshared_edges : bool;
  promote_include_all_unshared_curve_edges : bool;
  promote_include_all_primitives_sharing_boundary_points : bool;
}
type group_promote_operation = Group_ops.promote_operation =
  | Promote_elements of group_promote_mode
  | Promote_boundary of group_promote_boundary_options
type group_promotion_rule = Group_ops.promotion_rule = {
  promotion_source : group_owner;
  promotion_destination : group_owner;
  promotion_pattern : string;
  promotion_new_name : string option;
  promotion_keep_original : bool;
  promotion_output_as_attribute : bool;
  promotion_operation : group_promote_operation;
}
type primitive_group_connectivity = Group_ops.primitive_connectivity =
  | Primitive_share_points | Primitive_share_edges
type group_expand_normal_attribute = Group_ops.expand_normal_attribute = {
  expand_normal_owner : Attribute.owner;
  expand_normal_name : string;
}
type group_expand_collision = Group_ops.expand_collision = {
  expand_collision_owner : group_owner;
  expand_collision_group : string;
  expand_collision_contain : bool;
  expand_collision_allow_boundary : bool;
}
type group_boolean_operation = Group_ops.boolean_operation =
  | Group_replace | Group_union | Group_intersection | Group_subtract | Group_xor
type group_operand = Group_ops.operand = { pattern : string; inverted : bool }
type group_combine_step = Group_ops.combine_step = {
  operation : group_boolean_operation;
  operand : group_operand;
}
type group_range = Group_ops.range =
  | Range_start_end of { start : int; end_ : int }
  | Range_from_ends of { start : int; end_offset : int }
  | Range_start_length of { start : int; length : int }
  | Range_partition of { partition : int; partitions : int }
type group_range_filter = Group_ops.range_filter = {
  select : int; of_ : int; offset : int;
}
type group_range_collision = Group_ops.range_collision = {
  collision_owner : group_owner;
  collision_pattern : string;
  keep_boundary : bool;
}
type group_range_connectivity = Group_ops.range_connectivity =
  | Range_disconnected of { region : int option }
  | Range_connected of {
      connectivity_attributes : string option;
      connectivity_tolerance : float;
      collision : group_range_collision option;
      region : int option;
      remove_other_regions : bool;
    }
type group_range_rule = Group_ops.range_rule = {
  range_owner : group_owner;
  range_name : string;
  range_base : string option;
  range_invert : bool;
  range_filter : group_range_filter option;
  range_connectivity : group_range_connectivity option;
  range_merge : group_boolean_operation;
  range_specification : group_range;
}
type group_rename_conflict = Group_ops.rename_conflict =
  | Rename_skip | Rename_error | Rename_overwrite | Rename_union
type group_rename_rule = Group_ops.rename_rule = {
  rename_owner : group_owner option;
  rename_pattern : string;
  rename_replacement : string;
  rename_conflict : group_rename_conflict;
}
type group_delete_rule = Group_ops.delete_rule = {
  delete_owner : group_owner option;
  delete_pattern : string;
}
type group_copy_conflict = Group_ops.copy_conflict =
  | Copy_skip | Copy_overwrite | Copy_add_suffix
type group_copy_rule = Group_ops.copy_rule = {
  copy_owner : group_owner;
  copy_pattern : string;
  copy_prefix : string;
  match_attribute : string option;
}
type group_transfer_rule = Group_ops.transfer_rule = {
  transfer_owner : group_owner;
  transfer_pattern : string;
  transfer_prefix : string;
}
type group_name_conflict = Group_ops.name_conflict = Name_replace | Name_union
type invalid_group_name_policy = Group_ops.invalid_name_policy =
  | Ignore_invalid | Force_valid
type group_name_overlap = Group_ops.name_overlap =
  | First_group | Last_group | Error_on_overlap
type group_bounds = Group_ops.bounds =
  | Bounds_box of { minimum : Vec3.t; maximum : Vec3.t }
  | Bounds_sphere of { center : Vec3.t; radius : float }
type group_containment = Group_ops.containment =
  | Fully_contained | Partially_contained
type group_path_mode = Group_path.mode = Through_each | Start_end_pairs
type group_path_ending = Group_path.ending = Stop_at_end | Close_path
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
type revolve_type = Revolve.revolve_type = Revolve_closed | Revolve_open_arc
type sweep_tangent =
  | Sweep_average_edges
  | Sweep_central_difference
  | Sweep_previous_edge
  | Sweep_next_edge
  | Sweep_z_axis

let finite value = Float.is_finite value
let get_ok = function Ok value -> value | Error message -> invalid_arg message

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

let fuse_attribute_rule ?weight_attribute ~pattern method_ =
  let weight_attribute = match method_ with
    | Attribute_weighted_average | Attribute_weighted_sum
    | Attribute_minimum_weight | Attribute_maximum_weight
    | Attribute_concatenate_weight_order -> weight_attribute
    | Attribute_average | Attribute_least_point | Attribute_greatest_point
    | Attribute_maximum | Attribute_minimum | Attribute_mode
    | Attribute_median | Attribute_sum | Attribute_sum_squares
    | Attribute_root_mean_square | Attribute_concatenate -> None in
  { pattern; method_; weight_attribute }

let fuse_group_rule ~pattern group_method = { group_pattern = pattern; group_method }
type fuse_metric = Euclidean | Componentwise
type fuse_using = Point_snap.using =
  | Least_target_point
  | Closest_target_point
type fuse_match_condition = Point_snap.match_condition =
  | Equal_attribute_values
  | Unequal_attribute_values
type fuse_targeting = Point_snap.targeting =
  | Near_points
  | Specified_points of string
type grid_rounding = Grid_nearest | Grid_down | Grid_up
type fuse_attribute_view =
  | Fuse_float of float array
  | Fuse_int of int array
  | Fuse_float2 of Packed.Float2.Private.view
  | Fuse_float3 of Packed.Float3.Private.view
  | Fuse_float4 of Packed.Float4.Private.view
  | Fuse_int_array of Packed.Int_array.Private.view
  | Fuse_float_array of Packed.Float_array.Private.view
  | Fuse_text of string array

let fuse_clusters ?cancel ?(grain = 16_384) ?selection ?(tolerance = 1e-6)
    ?(position = Average_position) ?weight_attribute ?(attributes = Keep_first)
    ?(attribute_rules = []) ?(group_rules = [])
    ?(metric = Euclidean) ?(inclusive = true) ?(match_attributes = false)
    ?(keep_fused_points = false) geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.fuse: grain must be positive";
  let count = Geometry.point_count geometry in
  if match selection with
    | Some group -> Group.owner group <> Group.Point
        || Group.length group <> count
    | None -> false
  then Error "Pdk.Ops.fuse: selection must be a matching point group"
  else if not (finite tolerance) || tolerance < 0. then
    Error "Pdk.Ops.fuse: tolerance must be finite and non-negative"
  else
    let exact = tolerance = 0. in
    let point_attributes = if match_attributes then
              Geometry.attributes geometry
              |> List.filter_map (fun attribute ->
                if Attribute.owner attribute <> Attribute.Point then None
                else Some (match Attribute.Private.storage attribute with
                  | Attribute.Float values -> Fuse_float values
                  | Attribute.Int values -> Fuse_int values
                  | Attribute.Text values -> Fuse_text values
                  | Attribute.Float2 values ->
                      Fuse_float2 (Packed.Float2.Private.view values)
                  | Attribute.Float3 values ->
                      Fuse_float3 (Packed.Float3.Private.view values)
                  | Attribute.Float4 values ->
                      Fuse_float4 (Packed.Float4.Private.view values)
                  | Attribute.Int_array values ->
                      Fuse_int_array (Packed.Int_array.Private.view values)
                  | Attribute.Float_array values ->
                      Fuse_float_array (Packed.Float_array.Private.view values)))
              |> Array.of_list
      else [||] in
    let within value = if exact then value = 0.
      else if inclusive then value <= tolerance else value < tolerance in
    let near left right = within (abs_float (left -. right)) in
    let same_row offsets left right equal values =
      let left_first = offsets.(left) and left_last = offsets.(left + 1)
      and right_first = offsets.(right) and right_last = offsets.(right + 1) in
      let length = left_last - left_first in
      if length <> right_last - right_first then false
      else begin
        let local = ref 0 and result = ref true in
        while !result && !local < length do
          result := equal values.(left_first + !local)
              values.(right_first + !local);
          incr local
        done;
        !result
      end in
    let compatible left right =
      let index = ref 0 and result = ref true in
      while !result && !index < Array.length point_attributes do
        result := (match point_attributes.(!index) with
                | Fuse_float values -> near values.(left) values.(right)
                | Fuse_int values -> values.(left) = values.(right)
                | Fuse_text values -> String.equal values.(left) values.(right)
                | Fuse_float2 view -> near view.x.(left) view.x.(right)
                    && near view.y.(left) view.y.(right)
                | Fuse_float3 view -> near view.x.(left) view.x.(right)
                    && near view.y.(left) view.y.(right)
                    && near view.z.(left) view.z.(right)
                | Fuse_float4 view -> near view.x.(left) view.x.(right)
                    && near view.y.(left) view.y.(right)
                    && near view.z.(left) view.z.(right)
                    && near view.w.(left) view.w.(right)
                | Fuse_int_array view -> same_row view.offsets left right ( = )
                    view.values
                | Fuse_float_array view -> same_row view.offsets left right near
                    view.values);
        incr index
      done;
      !result in
    let cluster_metric = match metric with
      | Euclidean -> Point_clusters.Euclidean
      | Componentwise -> Point_clusters.Componentwise in
    Result.bind (Point_clusters.create ?cancel ?selection ~metric:cluster_metric
        ~inclusive ~operation:"Pdk.Ops.fuse" ~tolerance ~compatible geometry)
      (function
      | Point_clusters.Identity -> Ok geometry
      | Point_clusters.Clusters clusters ->
          Fuse_reduce.apply ?cancel ~grain ~position ?weight_attribute ~attributes
            ~attribute_rules ~group_rules
            ~compact:(not keep_fused_points) ~rewire:true clusters geometry)

let fuse ?cancel ?(grain = 16_384) ?selection ?target_selection
    ?(targeting = Near_points) ?(using = Least_target_point)
    ?(tolerance = 1e-6) ?(position = Average_position)
    ?weight_attribute ?(attributes = Keep_first) ?(attribute_rules = [])
    ?(group_rules = []) ?(metric = Euclidean)
    ?(inclusive = true)
    ?(match_attributes = false) ?radius_attribute ?match_attribute
    ?(match_condition = Equal_attribute_values) ?(match_tolerance = 0.)
    ?(modify_target = false) ?(fuse_points = true)
    ?(keep_fused_points = false) ?snapped_group
    ?snapped_destination_attribute ?(remove_degenerate_primitives = false)
    ?(remove_unused_points_from_degenerate_primitives = false)
    ?(remove_all_unused_points = false) ?target geometry =
  match Fuse_rules.validate ~attribute_rules ~group_rules geometry with
  | Error message -> Error message
  | Ok () ->
  let advanced = target <> None || target_selection <> None
      || targeting <> Near_points || using <> Least_target_point
      || radius_attribute <> None || match_attribute <> None
      || match_condition <> Equal_attribute_values || match_tolerance <> 0.
      || modify_target || not fuse_points || snapped_group <> None
      || snapped_destination_attribute <> None in
  let cleanup result = Result.bind result (Fuse_cleanup.apply ?cancel ~grain
      ~remove_degenerate_primitives
      ~remove_unused_points_from_degenerate_primitives
      ~remove_all_unused_points) in
  if not advanced then cleanup (fuse_clusters ?cancel ~grain ?selection
      ~tolerance ~position ?weight_attribute ~attributes ~metric ~inclusive
      ~attribute_rules ~group_rules ~match_attributes ~keep_fused_points geometry)
  else cleanup (begin
    let invalid_name label = function
      | Some name when String.trim name = "" ->
          Some (Printf.sprintf "Pdk.Ops.fuse: %s name must not be empty" label)
      | _ -> None in
    match invalid_name "snapped group" snapped_group with
    | Some message -> Error message
    | None ->
      (match invalid_name "snapped destination attribute"
          snapped_destination_attribute with
       | Some message -> Error message
       | None ->
        let target_geometry = Option.value ~default:geometry target in
        let same = Geometry.data_id geometry
            = Geometry.data_id target_geometry in
        if keep_fused_points && not fuse_points then Error
            "Pdk.Ops.fuse: Keep Fused Points requires Fuse Snapped Points"
        else if modify_target && not same then Error
            "Pdk.Ops.fuse: Modify Target is unavailable with a second input"
        else
        let effective_targets = match target_selection, same with
          | Some group, _ -> Some group
          | None, true -> selection
          | None, false -> None in
        let effective_modify_target = modify_target
            || (same && target_selection = None) in
        let cluster_metric = match metric with
          | Euclidean -> Point_clusters.Euclidean
          | Componentwise -> Point_clusters.Componentwise in
        Result.bind (Point_snap.plan ?cancel ~grain ?queries:selection
            ?targets:effective_targets ~targeting ~using ~tolerance
            ~metric:cluster_metric ~inclusive ?radius_attribute
            ?match_attribute ~match_condition ~match_tolerance
            ~source:geometry ~target:target_geometry ())
          (fun destinations ->
            let count = Geometry.point_count geometry in
            let mapped = ref 0 and moved = ref 0 in
            let source = Packed.Float3.Private.view
                (Geometry.positions geometry)
            and target_positions = Packed.Float3.Private.view
                (Geometry.positions target_geometry) in
            for point = 0 to count - 1 do
              let destination = destinations.(point) in
              if destination >= 0 then begin
                incr mapped;
                if source.x.(point) <> target_positions.x.(destination)
                    || source.y.(point) <> target_positions.y.(destination)
                    || source.z.(point) <> target_positions.z.(destination)
                then incr moved
              end
            done;
            let destination_bits = if same && fuse_points && !mapped > 0 then
                let bits = Bytes.make ((count + 7) / 8) '\000' in
                for point = 0 to count - 1 do
                  let destination = destinations.(point) in
                  if destination >= 0 then begin
                    let byte = destination lsr 3
                    and mask = 1 lsl (destination land 7) in
                    Bytes.unsafe_set bits byte (Char.chr
                      (Char.code (Bytes.unsafe_get bits byte) lor mask))
                  end
                done;
                Some bits
              else None in
            let install_outputs output =
              let output = match snapped_destination_attribute with
                | None -> output
                | Some name ->
                    let values = Array.copy destinations in
                    (match destination_bits with
                     | None -> ()
                     | Some bits ->
                         for point = 0 to count - 1 do
                           if values.(point) < 0
                               && Char.code (Bytes.unsafe_get bits (point lsr 3))
                                  land (1 lsl (point land 7)) <> 0
                           then values.(point) <- point
                         done);
                    let attribute = Attribute.create_owned ~owner:Attribute.Point
                        ~name (Attribute.Int values) |> get_ok in
                    Geometry.with_attribute attribute output |> get_ok in
              match snapped_group with
              | None -> output
              | Some name ->
                  let group = Group.init ~grain ~owner:Group.Point ~name count
                      (fun point -> destinations.(point) >= 0) in
                  Geometry.with_group group output |> get_ok in
            let install_reduced_outputs clusters ~compact output =
              let output_count = Geometry.point_count output in
              let source_point output_point = if compact then
                  let first = clusters.Point_clusters.offsets.(output_point)
                  and last = clusters.offsets.(output_point + 1) in
                  let slot = ref first and selected = ref (-1) in
                  while !slot < last && !selected < 0 do
                    let point = clusters.members.(!slot) in
                    if destinations.(point) >= 0 then selected := point;
                    incr slot
                  done;
                  !selected
                else output_point in
              let output = match snapped_destination_attribute with
                | None -> output
                | Some name ->
                    let values = Array.init output_count (fun output_point ->
                      let point = source_point output_point in
                      if point < 0 then -1 else destinations.(point)) in
                    let attribute = Attribute.create_owned ~owner:Attribute.Point
                        ~name (Attribute.Int values) |> get_ok in
                    Geometry.with_attribute attribute output |> get_ok in
              match snapped_group with
              | None -> output
              | Some name ->
                  let group = Group.init ~grain ~owner:Group.Point ~name
                      output_count (fun output_point ->
                        source_point output_point >= 0) in
                  Geometry.with_group group output |> get_ok in
            if same && effective_modify_target && !mapped > 0 then
              Result.bind (Point_clusters.of_links ?cancel
                  ~operation:"Pdk.Ops.fuse" destinations) (function
                | Point_clusters.Identity -> Ok (install_outputs geometry)
                | Point_clusters.Clusters clusters ->
                    let compact = fuse_points && not keep_fused_points in
                    Result.map (install_reduced_outputs clusters ~compact)
                      (Fuse_reduce.apply ?cancel ~grain ~position ?weight_attribute
                        ~attributes ~attribute_rules ~group_rules ~compact
                        ~rewire:fuse_points clusters geometry))
            else
            let output = if !moved = 0 then geometry else begin
              let x = Array.copy source.x and y = Array.copy source.y
              and z = Array.copy source.z in
              if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                  ~finish:(count - 1) (fun point ->
                    if point land 4095 = 0 then Cancel.check_opt cancel;
                    let destination = destinations.(point) in
                    if destination >= 0 then begin
                      x.(point) <- target_positions.x.(destination);
                      y.(point) <- target_positions.y.(destination);
                      z.(point) <- target_positions.z.(destination)
                    end);
              Geometry.with_positions
                (Packed.Float3.Private.of_owned_exn ~x ~y ~z) geometry
                |> get_ok
                |> Geometry.without_attribute ~owner:Attribute.Point "N"
                |> Geometry.without_attribute ~owner:Attribute.Vertex "N"
            end in
            Result.bind (Fuse_target_rules.apply ?cancel ~grain ~attribute_rules
                ~group_rules ~destinations ~source:output ~target:target_geometry ())
              (fun output ->
            let output = install_outputs output in
            if not fuse_points || !mapped = 0 then Ok output
            else begin
              let selected = Group.init ~grain ~owner:Group.Point
                  ~name:"__pdk_fuse_snapped" count (fun point ->
                    destinations.(point) >= 0
                    || match destination_bits with
                       | None -> false
                       | Some bits -> Char.code
                           (Bytes.unsafe_get bits (point lsr 3))
                           land (1 lsl (point land 7)) <> 0) in
              fuse_clusters ?cancel ~grain ~selection:selected ~tolerance:0.
                ~position:First_position ~attributes ~metric:Euclidean
                ~attribute_rules:[] ~group_rules:[] ~inclusive:true ~match_attributes
                ~keep_fused_points output
            end)
            ))
  end)

let snap_to_grid ?cancel ?(grain = 16_384) ?selection
    ?(spacing = Vec3.create 1. 1. 1.) ?(offset = Vec3.zero)
    ?(rounding = Grid_nearest) ?max_distance ?(fuse_points = false)
    ?(position = Average_position) ?weight_attribute
    ?(attributes = Keep_first) ?(attribute_rules = []) ?(group_rules = [])
    ?snapped_group geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.snap_to_grid: grain must be positive";
  let count = Geometry.point_count geometry in
  let finite3 value = finite value.Vec3.x && finite value.y && finite value.z in
  if not (finite3 spacing) || spacing.x <= 0. || spacing.y <= 0.
      || spacing.z <= 0. then
    Error "Pdk.Ops.snap_to_grid: spacing must be finite and positive on every axis"
  else if not (finite3 offset) || offset.x < 0. || offset.x > 1.
      || offset.y < 0. || offset.y > 1. || offset.z < 0. || offset.z > 1.
  then Error "Pdk.Ops.snap_to_grid: offset fractions must be finite and in [0, 1]"
  else if match max_distance with
    | Some distance -> not (finite distance) || distance < 0.
    | None -> false
  then Error "Pdk.Ops.snap_to_grid: maximum distance must be finite and non-negative"
  else if match selection with
    | Some group -> Group.owner group <> Group.Point
        || Group.length group <> count
    | None -> false
  then Error "Pdk.Ops.snap_to_grid: selection must be a matching point group"
  else if match snapped_group with
    | Some name -> String.trim name = ""
    | None -> false
  then Error "Pdk.Ops.snap_to_grid: snapped group name must not be empty"
  else begin
    let source = Packed.Float3.Private.view (Geometry.positions geometry) in
    let x = Array.copy source.x and y = Array.copy source.y
    and z = Array.copy source.z in
    let byte_count = (count + 7) / 8 and byte_grain = max 1 (grain / 8) in
    let changed = Bytes.make byte_count '\000' in
    let range_count = if byte_count = 0 then 0
      else (byte_count + byte_grain - 1) / byte_grain in
    let errors = Array.make range_count (-1)
    and changed_counts = Array.make range_count 0 in
    let round = match rounding with
      | Grid_nearest -> fun value -> floor (value +. 0.5)
      | Grid_down -> floor
      | Grid_up -> ceil in
    let origin_x = spacing.x *. offset.x
    and origin_y = spacing.y *. offset.y
    and origin_z = spacing.z *. offset.z in
    if range_count > 0 then Parallel.for_ ~chunk_size:1 ~start:0
        ~finish:(range_count - 1) (fun range ->
      let first_byte = range * byte_grain
      and last_byte = min byte_count ((range + 1) * byte_grain) in
      let first = first_byte * 8 and last = min count (last_byte * 8) in
      for point = first to last - 1 do
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if (match selection with None -> true
            | Some group -> Group.mem point group) then begin
          let sx = source.x.(point) and sy = source.y.(point)
          and sz = source.z.(point) in
          let qx = (sx -. origin_x) /. spacing.x
          and qy = (sy -. origin_y) /. spacing.y
          and qz = (sz -. origin_z) /. spacing.z in
          let nx = origin_x +. (spacing.x *. round qx)
          and ny = origin_y +. (spacing.y *. round qy)
          and nz = origin_z +. (spacing.z *. round qz) in
          if not (finite sx && finite sy && finite sz && finite qx && finite qy
              && finite qz && finite nx && finite ny && finite nz) then
            errors.(range) <- if errors.(range) < 0 then point else errors.(range)
          else begin
            let dx = nx -. sx and dy = ny -. sy and dz = nz -. sz in
            let within = match max_distance with
              | None -> true
              | Some distance -> Float.hypot dx (Float.hypot dy dz) <= distance in
            if within && (nx <> sx || ny <> sy || nz <> sz) then begin
              x.(point) <- nx; y.(point) <- ny; z.(point) <- nz;
              let byte = point lsr 3 and bit = 1 lsl (point land 7) in
              Bytes.unsafe_set changed byte
                (Char.chr (Char.code (Bytes.unsafe_get changed byte) lor bit));
              changed_counts.(range) <- changed_counts.(range) + 1
            end
          end
        end
      done);
    let invalid = Array.fold_left (fun earliest point ->
        if point < 0 then earliest else if earliest < 0 then point
        else min earliest point) (-1) errors in
    if invalid >= 0 then Error (Printf.sprintf
        "Pdk.Ops.snap_to_grid: selected point %d cannot be snapped to this grid"
        invalid)
    else
      let changed_count = Array.fold_left ( + ) 0 changed_counts in
      if changed_count = 0 && snapped_group = None && not fuse_points then
        Ok geometry
      else
        let output = if changed_count = 0 then geometry else
            Geometry.with_positions
              (Packed.Float3.Private.of_owned_exn ~x ~y ~z) geometry |> get_ok
            |> Geometry.without_attribute ~owner:Attribute.Point "N"
            |> Geometry.without_attribute ~owner:Attribute.Vertex "N" in
        let output = match snapped_group with
          | None -> output
          | Some name ->
              let group = Group.Private.of_owned_bits ~owner:Group.Point ~name
                  ~length:count changed in
              Geometry.with_group group output |> get_ok in
        if not fuse_points then Ok output
        else fuse ?cancel ~grain ?selection ~tolerance:0. ~position
            ?weight_attribute ~attributes ~attribute_rules ~group_rules output
  end

type reverse_operation = Reverse_faces.operation =
  | Reverse_vertices
  | Shift_vertices of int

let normals ?cancel ?(grain = 16_384) ?selection ?owner ?weighting ?cusp_angle
    ?keep_original_zero ?reverse ?attribute geometry =
  Normal_ops.run ?cancel ~grain ?selection ?owner ?weighting ?cusp_angle
    ?keep_original_zero ?reverse ?attribute geometry

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

let smooth ?cancel ?grain ?primitives ?constrained_points ?boundary ?iterations
    ?method_ ?mode ?weight_attribute ?alpha_attribute ?recompute_normals
    ?original_blend ?smoothed_blend ~attributes geometry =
  Smooth.run ?cancel ?grain ?primitives ?constrained_points ?boundary ?iterations
    ?method_ ?mode ?weight_attribute ?alpha_attribute ?recompute_normals
    ?original_blend ?smoothed_blend ~attributes geometry

let ray ?cancel ?grain ?selection ?collision_primitives ?method_ ?direction
    ?direction_mode ?surface_hit ?samples ?jitter_scale ?seed ?combine
    ?min_distance ?max_distance ?tolerance ?scale ?lift
    ?distance_attribute ?primitive_attribute
    ?source_vertex_numbers_attribute ?source_vertex_weights_attribute ?hit_group
    ?normal_attribute ?point_pattern ?vertex_pattern ?primitive_pattern
    ?detail_pattern ?match_groups ~source ~collision () =
  Ray.run ?cancel ?grain ?selection ?collision_primitives ?method_ ?direction
    ?direction_mode ?surface_hit ?samples ?jitter_scale ?seed ?combine
    ?min_distance ?max_distance ?tolerance ?scale ?lift
    ?distance_attribute ?primitive_attribute
    ?source_vertex_numbers_attribute ?source_vertex_weights_attribute ?hit_group
    ?normal_attribute ?point_pattern ?vertex_pattern ?primitive_pattern
    ?detail_pattern ?match_groups ~source ~collision ()

let compact_points ?cancel ?(grain = 16_384) geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.compact_points: grain must be positive";
  Cancel.check_opt cancel;
  let point_count = Geometry.point_count geometry
  and source_topology_value = Geometry.topology geometry in
  let source_topology = Topology.Private.view source_topology_value in
  let used = Array.make point_count false in
  Array.iteri (fun vertex point ->
    if vertex land 16_383 = 0 then Cancel.check_opt cancel;
    used.(point) <- true) source_topology.vertex_points;
  let old_to_new = Array.make point_count (-1) and retained = ref 0 in
  for point = 0 to point_count - 1 do
    if point land 16_383 = 0 then Cancel.check_opt cancel;
    if used.(point) then begin
      old_to_new.(point) <- !retained;
      incr retained
    end
  done;
  if !retained = point_count then Ok geometry
  else begin
    let new_to_old = Array.make !retained 0 and at = ref 0 in
    for point = 0 to point_count - 1 do
      if used.(point) then begin new_to_old.(!at) <- point; incr at end
    done;
    let source_positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let px = Topology_remap.select_float ?cancel ~grain new_to_old source_positions.x
    and py = Topology_remap.select_float ?cancel ~grain new_to_old source_positions.y
    and pz = Topology_remap.select_float ?cancel ~grain new_to_old source_positions.z in
    let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
    let vertex_points = Array.make (Array.length source_topology.vertex_points) 0 in
    if Array.length vertex_points > 0 then
      Parallel.for_ ~chunk_size:grain ~start:0
        ~finish:(Array.length vertex_points - 1) (fun vertex ->
          if vertex land 16_383 = 0 then Cancel.check_opt cancel;
          vertex_points.(vertex) <- old_to_new.(source_topology.vertex_points.(vertex)));
    let topology = Topology.Private.create_validated_owned ~point_count:!retained
        ~vertex_points ~primitive_offsets:(Array.copy source_topology.primitive_offsets)
        ~primitive_kinds:(Bytes.copy source_topology.primitive_kinds) in
    let remap_point_attribute attribute =
      if Attribute.owner attribute <> Attribute.Point then Ok attribute
      else Ok (Topology_remap.attribute ?cancel ~grain new_to_old attribute) in
    let rec remap_attributes result = function
      | [] -> Ok (List.rev result)
      | attribute :: rest -> Result.bind (remap_point_attribute attribute)
          (fun attribute -> remap_attributes (attribute :: result) rest) in
    Result.bind (remap_attributes [] (Geometry.attributes geometry))
      (fun attributes ->
        let groups = List.map (fun group ->
          if Group.owner group <> Group.Point then group
          else Topology_remap.group ?cancel ~grain new_to_old group)
            (Geometry.groups geometry) in
        let edge_groups = Topology_remap.edge_groups ?cancel
            ~source_topology:source_topology_value ~target_topology:topology
            ~point_map:old_to_new (Geometry.edge_groups geometry) |> get_ok in
        Geometry.create ~positions ~topology ~attributes ~groups ~edge_groups ())
  end

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

let copy_to_points = Instance_copy.Private.copy_to_points

let transform = Transform_ops.transform

type bound_shape = Bound.bound_shape =
  | Bound_box of { divisions : int * int * int }
  | Bound_sphere of { segments : int; rings : int; minimum_radius : float }

type match_size_fit = Match_size.match_size_fit =
  | Translate_only | Stretch | Contain | Cover
  | Match_x | Match_y | Match_z
  | Match_perimeter | Match_area | Match_volume

let poly_bevel ?cancel ?grain ?edges ?shape ?divisions ?point_scale_attribute
    ?ignore_flat_angle ?clamp_overlap ?edge_group ?corner_group ?offset_group
    ?recompute_point_normals ~distance geometry =
  Poly_bevel.run ?cancel ?grain ?edges ?shape ?divisions ?point_scale_attribute
    ?ignore_flat_angle ?clamp_overlap ?edge_group ?corner_group ?offset_group
    ?recompute_point_normals ~distance geometry

let poly_loft ?cancel ?grain ?primitives ?rest ?connect_closest_ends
    ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
    ?collinearity_tolerance ?recompute_normals geometry =
  Poly_loft.run ?cancel ?grain ?primitives ?rest ?connect_closest_ends
    ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
    ?collinearity_tolerance ?recompute_normals geometry

let skin ?cancel ?grain ?primitives ?rest ?connect_closest_ends
    ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
    ?collinearity_tolerance ?recompute_normals geometry =
  Poly_loft.run ?cancel ?grain ?primitives ?rest ?connect_closest_ends
    ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
    ?collinearity_tolerance ?recompute_normals ~output:Poly_loft.Polygons
    ~operation:"skin" geometry

let poly_bridge ?cancel ?grain ~source ~destination ?pairing
    ?connect_closest_ends ?minimize ?reverse_source ?reverse_destination
    ?pairing_shift ?divisions ?keep_input ?output_group ?collinearity_tolerance
    ?recompute_normals geometry =
  Poly_bridge.run ?cancel ?grain ~source ~destination ?pairing
    ?connect_closest_ends ?minimize ?reverse_source ?reverse_destination
    ?pairing_shift ?divisions ?keep_input ?output_group ?collinearity_tolerance
    ?recompute_normals geometry

let noise_displace ?cancel ?grain ~amplitude ~frequency ~seed geometry =
  if not (finite amplitude && finite frequency) then
    Error "Pdk.Ops.noise_displace: amplitude and frequency must be finite"
  else
    let noise = Noise.create seed in
    let samples = Array.make (Geometry.point_count geometry) 0. in
    let displaced = Kernel.edit_point_ranges ?grain
        (fun ~first ~last ~x ~y ~z ->
          Cancel.check_opt cancel;
          Noise.Private.sample2_into noise ~first ~last ~frequency
            ~x ~y:z ~output:samples;
          for index = first to last - 1 do
            y.(index) <- y.(index) +. amplitude *. ((samples.(index) *. 2.) -. 1.)
          done) geometry in
    Ok (displaced
        |> Geometry.without_attribute ~owner:Attribute.Point "N"
        |> Geometry.without_attribute ~owner:Attribute.Vertex "N")

let peak ?cancel ?(grain = 16_384) ?selection ?direction_attribute
    ?(normalize_direction = true) ?mask_attribute ~distance
    ?(recompute_normals = false) geometry =
  Deform.peak ?cancel ~grain ?selection ?direction_attribute
    ~normalize_direction ?mask_attribute ~distance ~recompute_normals geometry

let bend ?cancel ?(grain = 16_384) ?selection ?mask_attribute
    ?(origin = Vec3.zero) ?(direction = Vec3.unit_z) ?(up = Vec3.unit_y)
    ~length ?(bend_angle = 0.) ?(twist_angle = 0.) ?(limit = true)
    ?(both_directions = false) ?(continuous_twist = true) ?capture_attribute
    ?(recompute_normals = false) geometry =
  Deform.bend ?cancel ~grain ?selection ?mask_attribute ~origin ~direction ~up
    ~length ~bend_angle ~twist_angle ~limit ~both_directions ~continuous_twist
    ?capture_attribute ~recompute_normals geometry

let mountain ?cancel ?(grain = 16_384) ?selection ?direction_attribute
    ?(normalize_direction = true) ?mask_attribute ?(seed = 0) ~height
    ?(frequency = Vec3.create 1. 1. 1.) ?(offset = Vec3.zero) ?(octaves = 4)
    ?(lacunarity = 2.) ?(roughness = 0.5) ?height_attribute
    ?(recompute_normals = false) geometry =
  Deform.mountain ?cancel ~grain ?selection ?direction_attribute
    ~normalize_direction ?mask_attribute ~seed ~height ~frequency ~offset
    ~octaves ~lacunarity ~roughness ?height_attribute ~recompute_normals geometry

let point_jitter ?cancel ?(grain = 16_384) ?points ?mask_attribute ?id_attribute
    ?(use_point_scale = false) ~seed ~scale
    ?(axis_scales = Vec3.create 1. 1. 1.) geometry =
  Point_jitter.run ?cancel ~grain ?points ?mask_attribute ?id_attribute
    ~use_point_scale ~seed ~scale ~axis_scales geometry

type point_generate_mode = Point_generate.mode =
  | Generate_total of int
  | Generate_per_point of {
      points_per_point : float;
      scale_attribute : string option;
    }
  | Generate_probability of { attribute : string }

type point_replicate_shape = Point_replicate.shape =
  | Replicate_point
  | Replicate_box
  | Replicate_sphere
  | Replicate_disk
  | Replicate_line
  | Replicate_custom

type point_replicate_velocity_stretch = Point_replicate.velocity_stretch =
  | Replicate_no_velocity_stretch
  | Replicate_scaled_velocity
  | Replicate_velocity_only

let point_replicate ?cancel ?(grain = 16_384) ?points ?keep_input ?seed
    ?id_attribute ?generated_group ?copy_point_attributes
    ?keep_source_attributes ?transform_attributes ?source_point_attribute
    ?source_index_attribute
    ?shape ?custom_shape ?center ?size ?orientation ?uniform_scale
    ?quasi_stratified ?velocity_stretch ?velocity_scale ?inherit_velocity
    ?radial_velocity ?noise_amplitude ?noise_frequency ?noise_offset
    ?noise_roughness ?noise_attenuation ?noise_turbulence ?noise_seed
    ~points_per_point ?scale_attribute geometry =
  Point_replicate.run ?cancel ~grain ?points ?keep_input ?seed ?id_attribute
    ?generated_group ?copy_point_attributes ?keep_source_attributes
    ?transform_attributes
    ?source_point_attribute ?source_index_attribute ?shape ?custom_shape
    ?center ?size ?orientation ?uniform_scale ?quasi_stratified
    ?velocity_stretch ?velocity_scale ?inherit_velocity ?radial_velocity
    ?noise_amplitude ?noise_frequency ?noise_offset ?noise_roughness
    ?noise_attenuation ?noise_turbulence ?noise_seed
    ~copy_basis:(fun source targets ->
      copy_to_points ?cancel ~grain ~source ~targets ())
    ~points_per_point ?scale_attribute geometry

let clean ?cancel ?(grain = 16_384) ?epsilon ?remove_degenerate
    ?consolidate_distance ?overlaps ?reverse_winding ?remove_nan_points
    ?remove_unused_points ?delete_unused_groups ?point_attributes
    ?vertex_attributes ?primitive_attributes ?detail_attributes ?point_groups
    ?vertex_groups ?primitive_groups ?edge_groups geometry =
  Clean.run ?cancel ~grain ?epsilon ?remove_degenerate ?consolidate_distance
    ?overlaps:(Option.map (fun policy -> policy = Delete_overlap_pairs) overlaps)
    ?reverse_winding ?remove_nan_points ?remove_unused_points
    ?delete_unused_groups ?point_attributes ?vertex_attributes
    ?primitive_attributes ?detail_attributes ?point_groups ?vertex_groups
    ?primitive_groups ?edge_groups
    ~consolidate:(fun tolerance geometry ->
      fuse ?cancel ~grain ~tolerance geometry)
    ~compact:(fun geometry -> compact_points ?cancel ~grain geometry)
    geometry

let facet_point_selection ?cancel ~grain primitives geometry =
  let topology = Geometry.topology geometry in
  let index = Topology_index.create ?cancel topology in
  let view = Topology_index.Private.view index in
  Group.init ~grain ~owner:Group.Point ~name:"__facet_selected_points"
    (Topology.point_count topology) (fun point ->
      let found = ref false and at = ref view.point_offsets.(point) in
      let finish = view.point_offsets.(point + 1) in
      while not !found && !at < finish do
        found := Group.mem view.primitive_of_vertex.(view.point_vertices.(!at))
            primitives;
        incr at
      done;
      !found)

let facet_primitives_of_selection ?cancel ~grain selection geometry =
  let topology = Geometry.topology geometry in
  Cancel.check_opt cancel;
  Result.bind (Deform.validate_selection topology (Some selection)) (fun () ->
  match selection with
  | Selected_primitives group -> Ok group
  | Selected_points points ->
      let view = Topology.Private.view topology in
      Ok (Group.init ~grain ~owner:Group.Primitive
        ~name:"__facet_from_points" (Topology.primitive_count topology)
        (fun primitive ->
          if primitive land 4095 = 0 then Cancel.check_opt cancel;
          let found = ref false
          and vertex = ref view.primitive_offsets.(primitive) in
          let last = view.primitive_offsets.(primitive + 1) in
          while not !found && !vertex < last do
            found := Group.mem view.vertex_points.(!vertex) points;
            incr vertex
          done;
          !found))
  | Selected_vertices vertices ->
      let view = Topology.Private.view topology in
      Ok (Group.init ~grain ~owner:Group.Primitive
        ~name:"__facet_from_vertices" (Topology.primitive_count topology)
        (fun primitive ->
          if primitive land 4095 = 0 then Cancel.check_opt cancel;
          let found = ref false
          and vertex = ref view.primitive_offsets.(primitive) in
          let last = view.primitive_offsets.(primitive + 1) in
          while not !found && !vertex < last do
            found := Group.mem !vertex vertices;
            incr vertex
          done;
          !found))
  | Selected_edges edges ->
      let view = Topology.Private.view topology in
      let index = Topology_index.create ?cancel topology in
      let incidence = Topology_index.Private.view index in
      Ok (Group.init ~grain ~owner:Group.Primitive
        ~name:"__facet_from_edges" (Topology.primitive_count topology)
        (fun primitive ->
          if primitive land 4095 = 0 then Cancel.check_opt cancel;
          let found = ref false
          and vertex = ref view.primitive_offsets.(primitive) in
          let last = view.primitive_offsets.(primitive + 1) in
          while not !found && !vertex < last do
            let edge = incidence.edge_of_vertex.(!vertex) in
            found := edge >= 0 && Edge_group.mem edge edges;
            incr vertex
          done;
          !found)))

let facet ?cancel ?(grain = 16_384) ?primitives
    ?(pre_compute_normals = false)
    ?(make_normals_unit_length = false) ?(unique_points = false)
    ?consolidate_distance ?consolidate_normals_distance
    ?(remove_inline_points = false)
    ?(inline_distance = 0.) ?(orient_polygons = false) ?cusp_angle
    ?(remove_degenerate = false) ?(make_planar = false)
    ?(post_compute_normals = false) ?(reverse_normals = false) geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.facet: grain must be positive";
  let primitive_count = Geometry.primitive_count geometry in
  if match primitives with
    | Some group -> Group.owner group <> Group.Primitive
        || Group.length group <> primitive_count
    | None -> false
  then Error "Facet selection must be a matching primitive group"
  else if match consolidate_distance with Some value ->
      not (finite value) || value < 0. | None -> false
  then Error "Facet consolidation distance must be finite and non-negative"
  else if match consolidate_normals_distance with Some value ->
      not (finite value) || value < 0. | None -> false
  then Error "Facet normal consolidation distance must be finite and non-negative"
  else if consolidate_distance <> None && consolidate_normals_distance <> None
  then Error "Facet point and normal consolidation modes are mutually exclusive"
  else if remove_inline_points
      && (not (finite inline_distance) || inline_distance < 0.)
  then Error "Facet inline distance must be finite and non-negative"
  else if match primitives with Some group -> Group.cardinality group = 0
      | None -> false then Ok geometry
  else
    let original_geometry = geometry in
    let selection_name, geometry = match primitives with
      | None -> None, geometry
      | Some group when Group.cardinality group = primitive_count ->
          None, geometry
      | Some group ->
          let rec available suffix =
            let name = Printf.sprintf "__pdk_facet_selection_%d"
                suffix in
            if Geometry.find_group ~owner:Group.Primitive name geometry = None
            then name else available (suffix + 1) in
          let name = available 0 in
          let private_group = Group.init ~grain ~owner:Group.Primitive ~name
              primitive_count (fun primitive -> Group.mem primitive group) in
          Some name, Geometry.with_group private_group geometry |> Result.get_ok in
    let selection_geometry = geometry in
    let current_selection geometry = match selection_name with
      | None -> None
      | Some name -> Geometry.find_group ~owner:Group.Primitive name geometry in
    let result = if pre_compute_normals then
        Deform.normals ?cancel ~grain
          ?primitives:(current_selection geometry) geometry
      else Ok geometry in
    let result = Result.bind result (fun geometry ->
      Facet.adjust_normals ?cancel ~grain
        ?primitives:(current_selection geometry)
        ~unit_length:(make_normals_unit_length && not pre_compute_normals)
        ~reverse:false geometry) in
    let result = Result.bind result (fun geometry ->
      if unique_points then Facet.unique_points ?cancel ~grain
        ?primitives:(current_selection geometry) geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      match consolidate_distance, consolidate_normals_distance with
      | None, None -> Ok geometry
      | Some tolerance, None ->
          let selection = Option.map (fun primitives ->
            facet_point_selection ?cancel ~grain primitives geometry)
              (current_selection geometry) in
          fuse ?cancel ~grain ?selection ~tolerance geometry
      | None, Some distance ->
          Facet.consolidate_normals ?cancel ~grain
            ?primitives:(current_selection geometry) ~distance geometry
      | Some _, Some _ -> assert false) in
    let result = Result.bind result (fun geometry ->
      if remove_inline_points then
        Facet.remove_inline_points ?cancel ~grain
          ?primitives:(current_selection geometry) ~distance:inline_distance geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      if orient_polygons then Facet.orient_polygons ?cancel ~grain
          ?primitives:(current_selection geometry) geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry -> match cusp_angle with
      | None -> Ok geometry
      | Some angle -> Facet.cusp_polygons ?cancel ~grain
          ?primitives:(current_selection geometry) ~angle geometry) in
    let result = Result.bind result (fun geometry ->
      if remove_degenerate then
        Clean.delete_degenerate ?cancel ~grain
          ?primitives:(current_selection geometry) ~epsilon:1e-12 geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      if make_planar then Facet.make_planar ?cancel ~grain
          ?primitives:(current_selection geometry) geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      if post_compute_normals then Deform.normals ?cancel ~grain
          ?primitives:(current_selection geometry) geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      Facet.adjust_normals ?cancel ~grain ~unit_length:false
        ?primitives:(current_selection geometry)
        ~reverse:reverse_normals geometry) in
    Result.map (fun geometry -> match selection_name with
      | None -> geometry
      | Some _ when geometry == selection_geometry -> original_geometry
      | Some name -> Geometry.without_group ~owner:Group.Primitive name geometry)
      result

let poly_fill ?cancel ?grain ?boundary ?mode ?reverse_patches ?unique_points
    ?update_point_normals ?patch_group geometry =
  Poly_fill.run ?cancel ?grain ?boundary ?mode ?reverse_patches ?unique_points
    ?update_point_normals ?patch_group geometry

(* Public result boundaries carry stable codes while the implementation above
   remains free to compose the lower-level validation functions that still
   report strings. Keep these wrappers last so internal operator composition
   uses the raw result without repeatedly wrapping and unwrapping failures. *)
let detailed operation code result =
  Result.map_error (Error.of_string ~operation ~code) result

let protected operation code work =
  try detailed operation code (work ()) with
  | Cancel.Cancelled -> Error (Error.make ~operation ~code:"cancelled"
      "geometry operation was cancelled")

let polyline = Line_geometry.polyline_checked
let line = Line_geometry.line_checked
let circle = Plane_generators.circle_checked
let grid = Plane_generators.grid_checked
let box = Box_generator.box_checked
let uv_sphere = Uv_sphere.run_checked

let torus = Parametric_generators.torus_checked
let tube = Parametric_generators.tube_checked
let platonic = Parametric_generators.platonic_checked

let spiral = Spiral.run

let merge = Mesh_merge.run

let fuse_raw = fuse
let fuse ?cancel ?grain ?selection ?target_selection ?targeting ?using
    ?tolerance ?position ?weight_attribute ?attributes ?metric ?inclusive
    ?attribute_rules ?group_rules ?match_attributes
    ?radius_attribute ?match_attribute ?match_condition ?match_tolerance
    ?modify_target ?fuse_points ?keep_fused_points ?snapped_group
    ?snapped_destination_attribute ?remove_degenerate_primitives
    ?remove_unused_points_from_degenerate_primitives ?remove_all_unused_points
    ?target geometry =
  protected "fuse" "invalid_geometry" (fun () ->
    fuse_raw ?cancel ?grain ?selection ?target_selection ?targeting ?using
      ?tolerance ?position ?weight_attribute ?attributes ?metric ?inclusive
      ?attribute_rules ?group_rules ?match_attributes
      ?radius_attribute ?match_attribute ?match_condition ?match_tolerance
      ?modify_target ?fuse_points ?keep_fused_points ?snapped_group
      ?snapped_destination_attribute ?remove_degenerate_primitives
      ?remove_unused_points_from_degenerate_primitives ?remove_all_unused_points
      ?target geometry)

let edge_collapse = Edge_collapse.run

let dissolve = Dissolve.run_checked

let poly_bevel_raw = poly_bevel
let poly_bevel ?cancel ?grain ?edges ?shape ?divisions ?point_scale_attribute
    ?ignore_flat_angle ?clamp_overlap ?edge_group ?corner_group ?offset_group
    ?recompute_point_normals ~distance geometry =
  protected "poly_bevel" "invalid_topology" (fun () ->
    poly_bevel_raw ?cancel ?grain ?edges ?shape ?divisions
      ?point_scale_attribute ?ignore_flat_angle ?clamp_overlap ?edge_group
      ?corner_group ?offset_group ?recompute_point_normals ~distance geometry)

let point_split ?cancel ?grain ?selection ?attributes ?tolerance
    ?promote_attributes geometry =
  let selection = Option.map (function
    | Selected_points group -> Element_selection.Selected_points group
    | Selected_vertices group -> Element_selection.Selected_vertices group
    | Selected_primitives group -> Element_selection.Selected_primitives group
    | Selected_edges group -> Element_selection.Selected_edges group) selection in
  protected "point_split" "invalid_geometry" (fun () ->
    Point_split.run ?cancel ?grain ?selection ?attributes ?tolerance
      ?promote_attributes geometry)

let poly_loft_raw = poly_loft
let poly_loft ?cancel ?grain ?primitives ?rest ?connect_closest_ends
    ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
    ?collinearity_tolerance ?recompute_normals geometry =
  protected "poly_loft" "invalid_topology" (fun () ->
    poly_loft_raw ?cancel ?grain ?primitives ?rest ?connect_closest_ends
      ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
      ?collinearity_tolerance ?recompute_normals geometry)

let skin_raw = skin
let skin ?cancel ?grain ?primitives ?rest ?connect_closest_ends
    ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
    ?collinearity_tolerance ?recompute_normals geometry =
  protected "skin" "invalid_topology" (fun () ->
    skin_raw ?cancel ?grain ?primitives ?rest ?connect_closest_ends
      ?minimize ?u_wrap ?v_wrap ?keep_primitives ?output_group
      ?collinearity_tolerance ?recompute_normals geometry)

let poly_bridge_raw = poly_bridge
let poly_bridge ?cancel ?grain ~source ~destination ?pairing
    ?connect_closest_ends ?minimize ?reverse_source ?reverse_destination
    ?pairing_shift ?divisions ?keep_input ?output_group ?collinearity_tolerance
    ?recompute_normals geometry =
  protected "poly_bridge" "invalid_topology" (fun () ->
    poly_bridge_raw ?cancel ?grain ~source ~destination ?pairing
      ?connect_closest_ends ?minimize ?reverse_source ?reverse_destination
      ?pairing_shift ?divisions ?keep_input ?output_group ?collinearity_tolerance
      ?recompute_normals geometry)

let snap_to_grid_raw = snap_to_grid
let snap_to_grid ?cancel ?grain ?selection ?spacing ?offset ?rounding
    ?max_distance ?fuse_points ?position ?weight_attribute ?attributes
    ?attribute_rules ?group_rules ?snapped_group geometry =
  protected "snap_to_grid" "invalid_geometry" (fun () ->
    snap_to_grid_raw ?cancel ?grain ?selection ?spacing ?offset ?rounding
      ?max_distance ?fuse_points ?position ?weight_attribute ?attributes
      ?attribute_rules ?group_rules ?snapped_group geometry)

let triangulate ?cancel ?grain ?primitives geometry =
  protected "triangulate" "invalid_topology"
    (fun () -> Triangulate.run ?cancel ?grain ?primitives geometry)

type triangulate_2d_projection =
  | Triangulate_2d_best_fit
  | Triangulate_2d_xy
  | Triangulate_2d_yz
  | Triangulate_2d_zx
  | Triangulate_2d_plane of { origin : Vec3.t; normal : Vec3.t }
  | Triangulate_2d_point_attribute of string

let triangulate_2d ?cancel ?grain ?selection ?constraint_edges
    ?constraint_primitives
    ?(projection = Triangulate_2d_best_fit) ?seed ?split_crossing_constraints
    ?flood_from_hull_boundary ?remove_outside_constraint_polygons
    ?silhouette_constraints ?remove_outside_silhouette
    ?ignore_non_constraint_points
    ?remove_duplicate_points
    ?refine ?allow_constraint_splitting ?minimum_angle ?maximum_area
    ?target_edge_length ?minimum_edge_length ?maximum_new_points
    ?regularization_steps ?allow_movement_of_interior_input_points
    ?preserve_point_payload ?restore_original_point_positions ?keep_primitives
    ?(remove_unused_points = false)
    ?(recompute_point_normals = false) ?split_point_group
    ?refinement_point_group ?triangle_group ?constraint_group geometry =
  let selection = Option.map (function
    | Selected_points group -> Element_selection.Selected_points group
    | Selected_vertices group -> Element_selection.Selected_vertices group
    | Selected_primitives group -> Element_selection.Selected_primitives group
    | Selected_edges group -> Element_selection.Selected_edges group) selection in
  let projection = match projection with
    | Triangulate_2d_best_fit -> Triangulate2d.Best_fit
    | Triangulate_2d_xy -> Triangulate2d.Plane_xy
    | Triangulate_2d_yz -> Triangulate2d.Plane_yz
    | Triangulate_2d_zx -> Triangulate2d.Plane_zx
    | Triangulate_2d_plane { origin; normal } ->
        Triangulate2d.Plane { origin; normal }
    | Triangulate_2d_point_attribute name ->
        Triangulate2d.Point_attribute name in
  protected "triangulate_2d" "invalid_triangulation" (fun () ->
    Result.bind (Triangulate2d.run ?cancel ?grain ?selection ?constraint_edges
      ?constraint_primitives ~projection ?seed ?split_crossing_constraints
      ?flood_from_hull_boundary ?remove_outside_constraint_polygons
      ?silhouette_constraints ?remove_outside_silhouette
      ?ignore_non_constraint_points
      ?remove_duplicate_points
      ?refine ?allow_constraint_splitting ?minimum_angle ?maximum_area
      ?target_edge_length ?minimum_edge_length ?maximum_new_points
      ?regularization_steps ?allow_movement_of_interior_input_points
      ?preserve_point_payload ?restore_original_point_positions ?keep_primitives
      ?split_point_group ?triangle_group
      ?refinement_point_group ?constraint_group geometry) (fun output ->
      Result.bind (if remove_unused_points then compact_points ?cancel
          ?grain output else Ok output) (fun output ->
        if recompute_point_normals
            && Option.is_some (Geometry.find_attribute
              ~owner:Attribute.Point "N" geometry) then
          normals ?cancel ?grain ~owner:Attribute.Point ~attribute:"N" output
        else Ok output)))

let remesh ?cancel ?(grain = 16_384) ?iterations ?smoothing ?project
    ?use_input_points_only ?hard_points ?hard_edges ?target_size_attribute
    ?preserve_uv_seams ?uv_attribute ?output_hard_edges ?output_mesh_size
    ?output_quality ?recompute_point_normals ~target_length geometry =
  protected "remesh" "invalid_remesh" (fun () ->
    let kernels : Remesh.kernels = {
      triangulate = (fun geometry -> Triangulate.run ?cancel ~grain geometry);
      collapse = (fun edges geometry ->
        Edge_collapse.raw ?cancel ~grain ~edges ~position:Average_position
          ~remove_degenerate_primitives:true ~recompute_point_normals:false
          geometry);
      flip = (fun edges geometry ->
        Edge_flip.run ?cancel ~grain ~edges ~cycles:1
          ~cycle_vertex_attributes:true ~recompute_point_normals:false geometry);
    } in
    Remesh.run ?cancel ~grain ?iterations ?smoothing ?project
      ?use_input_points_only ?hard_points ?hard_edges ?target_size_attribute
      ?preserve_uv_seams ?uv_attribute ?output_hard_edges ?output_mesh_size
      ?output_quality ?recompute_point_normals ~target_length ~kernels geometry)

let boolean_detect ?cancel ?(grain = 16_384) ?source_primitives
    ?collision_primitives ?(tolerance = 0.) ?(include_coplanar = true)
    ?(intersecting_group = Some "boolean_intersections")
    ?intersections_attribute ?count_attribute ?self_intersecting_group
    ?self_intersections_attribute ?self_count_attribute ~collision geometry =
  Boolean_detect.run ?cancel ~grain ?source_primitives ?collision_primitives
    ~tolerance ~include_coplanar ~intersecting_group ~intersections_attribute
    ~count_attribute ~self_intersecting_group ~self_intersections_attribute
    ~self_count_attribute ~collision geometry

let intersection_analysis ?cancel ?(grain = 16_384) ?source_primitives
    ?collision_primitives ?(tolerance = 0.) ?(include_coplanar = true)
    ?(input_attribute = Some "sourceinput")
    ?(primitive_attribute = Some "sourceprim")
    ?(primitive_uvw_attribute = Some "sourceprimuv")
    ?(point_attribute = Some "sourcepoint") ?collision geometry =
  Intersection_analysis.run ?cancel ~grain ?source_primitives
    ?collision_primitives ~tolerance ~include_coplanar ~input_attribute
    ~primitive_attribute ~primitive_uvw_attribute ~point_attribute ~collision
    geometry

let poly_reduce = Poly_reduce.run_checked
let edge_flip = Edge_flip.run_checked

let edge_cusp ?cancel ?grain ?edges ?update_point_normals geometry =
  protected "edge_cusp" "invalid_topology" (fun () ->
    Facet.edge_cusp ?cancel ?grain ?edges ?update_point_normals geometry)

let edge_straighten ?cancel ?grain ?edges ?output_group geometry =
  protected "edge_straighten" "invalid_geometry" (fun () ->
    Edge_ops.straighten ?cancel ?grain ?edges ?output_group geometry)

let circle_from_edges ?cancel ?grain ?edges ?radius ?scale ?output_group geometry =
  protected "circle_from_edges" "invalid_circle" (fun () ->
    Circle_from_edges.run ?cancel ?grain ?edges ?radius ?scale ?output_group
      geometry)

type graph_color_connectivity = Graph_color.connectivity =
  | Graph_primitives_by_point
  | Graph_points_by_primitive
  | Graph_primitives_by_edge

type graph_color_worksets = Graph_color.worksets = {
  begin_attribute : string;
  length_attribute : string;
}

let graph_color ?cancel ?grain ?selection ?connectivity ?color_attribute
    ?sort_output ?worksets geometry =
  let selection = Option.map (function
    | Selected_points group -> Element_selection.Selected_points group
    | Selected_vertices group -> Element_selection.Selected_vertices group
    | Selected_primitives group -> Element_selection.Selected_primitives group
    | Selected_edges group -> Element_selection.Selected_edges group) selection in
  protected "graph_color" "invalid_graph" (fun () ->
    Graph_color.run ?cancel ?grain ?selection ?connectivity ?color_attribute
      ?sort_output ?worksets geometry)

type edge_equalize_method = Edge_ops.equalize_method =
  | Equalize_average
  | Equalize_longest
  | Equalize_shortest

let edge_equalize ?cancel ?grain ?edges ?method_ ?iterations ?tolerance
    ?output_group geometry =
  protected "edge_equalize" "invalid_edge_equalize" (fun () ->
    Edge_ops.equalize ?cancel ?grain ?edges ?method_ ?iterations ?tolerance
      ?output_group geometry)

type edge_relax_selection = Edge_relax.selection =
  | Relax_points of Group.t
  | Relax_primitives of Group.t

type edge_relax_target_mode = Edge_relax.target_mode =
  | Individual_lengths
  | Scale_independent_distribution

let edge_relax ?cancel ?grain ?selection ?pin_points ?iterations ?step_size
    ?target_mode ?only_shorten ?tolerance ~reference geometry =
  protected "edge_relax" "invalid_edge_relax" (fun () ->
    Edge_relax.relax ?cancel ?grain ?selection ?pin_points ?iterations
      ?step_size ?target_mode ?only_shorten ?tolerance ~reference geometry)

type edge_transport_roots = Edge_transport.roots =
  | Transport_first_point
  | Transport_last_point
  | Transport_root_group of Group.t

type edge_transport_operation = Edge_transport.operation =
  | Transport
  | Transport_from_root
  | Transport_total
  | Transport_maximum
  | Transport_minimum

type edge_transport_root_value = Edge_transport.root_value =
  | Transport_root_zero
  | Transport_root_hold

type edge_transport_split = Edge_transport.split =
  | Transport_copy
  | Transport_split

type edge_transport_normalization = Edge_transport.normalization =
  | Transport_no_normalization
  | Transport_normalize_components
  | Transport_normalize_global

type edge_transport_direction = Edge_transport.direction =
  | Transport_forward
  | Transport_backward

type edge_transport_merge = Edge_transport.merge =
  | Transport_merge_add
  | Transport_merge_maximum
  | Transport_merge_minimum

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

let rewire_vertices ?cancel ?grain ?selection ?recursive
    ?delete_target_attribute ?keep_unused_points ?original_point_attribute
    ~owner ~target_attribute geometry =
  let selection = Option.map (function
    | Selected_points group -> Element_selection.Selected_points group
    | Selected_vertices group -> Element_selection.Selected_vertices group
    | Selected_primitives group -> Element_selection.Selected_primitives group
    | Selected_edges group -> Element_selection.Selected_edges group) selection in
  protected "rewire_vertices" "invalid_rewire_vertices" (fun () ->
    Rewire_vertices.run ?cancel ?grain ?selection ?recursive
      ?delete_target_attribute ?keep_unused_points ?original_point_attribute
      ~owner ~target_attribute geometry)

let edge_transport ?cancel ?grain ?points ?roots ?operation ?root_value
    ?integrate_constant ?scale_by_edge_length ?split ?direction ?merge
    ?normalization ~attribute geometry =
  protected "edge_transport" "invalid_edge_transport" (fun () ->
    Edge_transport.run ?cancel ?grain ?points ?roots ?operation ?root_value
      ?integrate_constant ?scale_by_edge_length ?split ?direction ?merge
      ?normalization
      ~attribute geometry)

let edge_transport_curves ?cancel ?grain ?primitives ?owner ?direction
    ?operation ?root_value ?integrate_constant ?scale_by_edge_length
    ?normalization ~attribute geometry =
  protected "edge_transport_curves" "invalid_edge_transport" (fun () ->
    Edge_transport.run_curves ?cancel ?grain ?primitives ?owner ?direction
      ?operation ?root_value ?integrate_constant ?scale_by_edge_length
      ?normalization ~attribute geometry)

let edge_transport_parent ?cancel ?grain ?points ?parent_attribute ?direction
    ?operation ?root_value ?integrate_constant ?scale_by_edge_length ?split
    ?merge ?normalization ~attribute geometry =
  protected "edge_transport_parent" "invalid_edge_transport" (fun () ->
    Edge_transport.run_parent ?cancel ?grain ?points ?parent_attribute
      ?direction ?operation ?root_value ?integrate_constant
      ?scale_by_edge_length ?split ?merge ?normalization ~attribute geometry)

let reverse ?cancel ?grain ?primitives ?operation geometry =
  protected "reverse" "invalid_topology"
    (fun () -> Reverse_faces.run ?cancel ?grain ?primitives ?operation geometry)

let mirror ?cancel ?grain ?keep_original ~origin ~normal geometry =
  protected "mirror" "invalid_parameter" (fun () ->
    Mirror_geometry.run ?cancel ?grain ?keep_original ~origin ~normal geometry)

let clip ?cancel ?grain ?keep ?snapping_tolerance ?fill ?split_connectivity
    ?clip_attribute ?distance ?selection ?replace_existing_groups
    ?clipped_edge_group ?cap_group ?clipped_group ?above_group ?below_group
    ~origin ~normal geometry =
  let selection = Option.map (function
    | Selected_points group -> Element_selection.Selected_points group
    | Selected_vertices group -> Element_selection.Selected_vertices group
    | Selected_primitives group -> Element_selection.Selected_primitives group
    | Selected_edges group -> Element_selection.Selected_edges group) selection in
  protected "clip" "invalid_geometry" (fun () ->
    Plane_clip.clip ?cancel ?grain ?keep ?snapping_tolerance ?fill
      ?split_connectivity ?clip_attribute ?distance ?selection
      ?replace_existing_groups ?clipped_edge_group ?cap_group ?clipped_group
      ?above_group ?below_group ~origin ~normal geometry)

let clip_transform ?cancel ?grain ?keep ?snapping_tolerance ?fill
    ?split_connectivity ?clip_attribute ?distance ?selection
    ?replace_existing_groups ?clipped_edge_group ?cap_group ?clipped_group
    ?above_group ?below_group ?(local_normal = Vec3.unit_y) ~transform geometry =
  let origin = Mat4.transform_point transform Vec3.zero
  and normal = Mat4.transform_direction transform local_normal in
  clip ?cancel ?grain ?keep ?snapping_tolerance ?fill ?split_connectivity
    ?clip_attribute ?distance ?selection ?clipped_edge_group ?cap_group
    ?replace_existing_groups ?clipped_group ?above_group ?below_group
    ~origin ~normal geometry

let crease ?cancel ?grain ?edges ?operation ?weight ?add_vertex_color geometry =
  protected "crease" "invalid_crease" (fun () ->
    Crease.crease ?cancel ?grain ?edges ?operation ?weight ?add_vertex_color
      geometry)

let attribute_fade ?cancel ?grain ?points ?start_source ?hold_source
    ?fade_attribute ?start_attribute ?start_retime ?hold_scale_attribute ~frame
    ?frame_offset ?fade_in ?fade_hold ?fade_out ?fade_in_ramp ?fade_out_ramp
    ?visualize geometry =
  Attribute_fade.fade_checked ?cancel ?grain ?points ?start_source ?hold_source
    ?fade_attribute ?start_attribute ?start_retime ?hold_scale_attribute
    ~frame ?frame_offset ?fade_in ?fade_hold ?fade_out ?fade_in_ramp
    ?fade_out_ramp ?visualize geometry

type poly_cut_element = Poly_cut.element = Poly_cut_points | Poly_cut_edges
type poly_cut_strategy = Poly_cut.strategy = Poly_cut_remove | Poly_cut_cut
type poly_cut_detection = Poly_cut.detection =
  | Poly_cut_all
  | Poly_cut_crossing of { attribute : string; value : float }
  | Poly_cut_change of { attribute : string; threshold : float }

let poly_cut ?cancel ?grain ?primitives ?cut_points ?cut_edges ?element
    ?strategy ?detection ?keep_closed geometry =
  protected "poly_cut" "invalid_poly_cut" (fun () ->
    Poly_cut.cut ?cancel ?grain ?primitives ?cut_points ?cut_edges ?element
      ?strategy ?detection ?keep_closed geometry)

type separate_pieces_mode = Separate_pieces.mode =
  | Separate_pieces_separate
  | Separate_pieces_move_back

let separate_pieces ?cancel ?grain ?owner ?translation_attribute ?axis ?gap
    ~mode ~piece_attribute geometry =
  protected "separate_pieces" "invalid_separate_pieces" (fun () ->
    Separate_pieces.run ?cancel ?grain ?owner ?translation_attribute ?axis ?gap
      ~mode ~piece_attribute geometry)

let subdivide ?cancel ?grain ?scheme ?iterations ?primitives ?cracks
    ?consistent_topology ?creases ?crease_primitives ?crease_weight
    ?generate_resulting_creases ?resulting_crease_group ?hole_primitives
    ?remove_holes ?boundary_interpolation ?face_varying_interpolation
    ?triangle_policy ?creasing_method ?treat_curves_as_independent
    ?recompute_point_normals geometry =
  protected "subdivide" "invalid_topology" (fun () ->
    Subdivide.subdivide ?cancel ?grain ?scheme ?iterations ?primitives ?cracks
      ?consistent_topology ?creases ?crease_primitives ?crease_weight
      ?generate_resulting_creases ?resulting_crease_group ?hole_primitives
      ?remove_holes ?boundary_interpolation ?face_varying_interpolation
      ?triangle_subdivision:triangle_policy ?creasing_method
      ?treat_curves_as_independent ?recompute_point_normals geometry)

let edge_divide ?cancel ?grain ?edges ?divisions ?share_points geometry =
  protected "edge_divide" "invalid_topology" (fun () ->
    Subdivide.edge_divide ?cancel ?grain ?edges ?divisions ?share_points
      geometry)

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

let compact_points_raw = compact_points
let delete ?cancel ?grain ?selected ?compact_points ?policy group geometry =
  protected "delete" "invalid_selection" (fun () ->
    Deletion.delete ?cancel ?grain ?selected ?compact_points ?policy group geometry)

let blast_by_attribute ?cancel ?grain ?base ?invert ?remove_unused_points
    ~owner ~attribute ~mode ~output geometry =
  protected "blast_by_attribute" "invalid_blast" (fun () ->
    Blast_by_attribute.blast ?cancel ?grain ?base ?invert ?remove_unused_points
      ~owner ~attribute ~mode ~output geometry)

let delete_primitives = Deletion.delete_primitives

let compact_points ?cancel ?grain geometry =
  protected "compact_points" "invalid_geometry"
    (fun () -> compact_points_raw ?cancel ?grain geometry)

let convex_hull ?cancel ?grain ?selection ?preserve_point_payload
    ?source_point_attribute ?hull_group geometry =
  protected "convex_hull" "invalid_geometry" (fun () ->
    Convex_hull.run ?cancel ?grain ?selection ?preserve_point_payload
      ?source_point_attribute ?hull_group geometry)

type centroid_piece_owner = Extract_centroid.piece_owner =
  | Centroid_piece_points
  | Centroid_piece_primitives

type centroid_run_over = Extract_centroid.run_over =
  | Centroid_detail
  | Centroid_primitives
  | Centroid_pieces of {
      owner : centroid_piece_owner;
      attribute : string;
    }

type centroid_method = Extract_centroid.method_ =
  | Centroid_point_mass
  | Centroid_bounding_box
  | Centroid_convex_hull

let extract_centroid ?cancel ?grain ?run_over ?method_
    ?source_primitive_attribute ?piece_output_attribute geometry =
  protected "extract_centroid" "invalid_geometry" (fun () ->
    Extract_centroid.run ?cancel ?grain ?run_over ?method_
      ?source_primitive_attribute ?piece_output_attribute geometry)

type extract_curve_cut = Extract_point_curve.cut =
  | Extract_cut_constant of float
  | Extract_cut_primitive_attribute of string

let extract_point_from_curve ?cancel ?grain ?primitives ?cut ?point_attributes
    ?copy_primitive_attributes ?primitive_attributes ?curve_u_attribute
    ?number_cuts_attribute ?curve_number_attribute ~distance_attribute geometry =
  protected "extract_point_from_curve" "invalid_curve" (fun () ->
    Extract_point_curve.run ?cancel ?grain ?primitives ?cut ?point_attributes
      ?copy_primitive_attributes ?primitive_attributes ?curve_u_attribute
      ?number_cuts_attribute ?curve_number_attribute ~distance_attribute geometry)

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

let noise_displace_raw = noise_displace
let noise_displace ?cancel ?grain ~amplitude ~frequency ~seed geometry =
  protected "noise_displace" "invalid_parameter"
    (fun () -> noise_displace_raw ?cancel ?grain ~amplitude ~frequency ~seed geometry)

let peak_raw = peak
let peak ?cancel ?grain ?selection ?direction_attribute ?normalize_direction
    ?mask_attribute ~distance ?recompute_normals geometry =
  protected "peak" "invalid_deformation" (fun () ->
    peak_raw ?cancel ?grain ?selection ?direction_attribute ?normalize_direction
      ?mask_attribute ~distance ?recompute_normals geometry)

let bend_raw = bend
let bend ?cancel ?grain ?selection ?mask_attribute ?origin ?direction ?up
    ~length ?bend_angle ?twist_angle ?limit ?both_directions ?continuous_twist
    ?capture_attribute ?recompute_normals geometry =
  protected "bend" "invalid_deformation" (fun () ->
    bend_raw ?cancel ?grain ?selection ?mask_attribute ?origin ?direction ?up
      ~length ?bend_angle ?twist_angle ?limit ?both_directions ?continuous_twist
      ?capture_attribute ?recompute_normals geometry)

let mountain_raw = mountain
let mountain ?cancel ?grain ?selection ?direction_attribute ?normalize_direction
    ?mask_attribute ?seed ~height ?frequency ?offset ?octaves ?lacunarity
    ?roughness ?height_attribute ?recompute_normals geometry =
  protected "mountain" "invalid_deformation" (fun () ->
    mountain_raw ?cancel ?grain ?selection ?direction_attribute
      ?normalize_direction ?mask_attribute ?seed ~height ?frequency ?offset
      ?octaves ?lacunarity ?roughness ?height_attribute ?recompute_normals
      geometry)

let point_jitter_raw = point_jitter
let point_jitter ?cancel ?grain ?points ?mask_attribute ?id_attribute
    ?use_point_scale ~seed ~scale ?axis_scales geometry =
  let selection_error = match points with
    | Some group when Group.owner group <> Group.Point ->
        Some "selection must own points"
    | Some group when Group.length group <> Geometry.point_count geometry ->
        Some "selection length does not match point count"
    | None | Some _ -> None in
  match selection_error with
  | Some message -> detailed "point_jitter" "invalid_selection" (Error message)
  | None -> protected "point_jitter" "invalid_attribute" (fun () ->
      point_jitter_raw ?cancel ?grain ?points ?mask_attribute ?id_attribute
        ?use_point_scale ~seed ~scale ?axis_scales geometry)

let point_generate = Point_generate.run_checked

let point_replicate_raw = point_replicate
let point_replicate ?cancel ?grain ?points ?keep_input ?seed ?id_attribute
    ?generated_group ?copy_point_attributes ?keep_source_attributes
    ?transform_attributes ?source_point_attribute ?source_index_attribute
    ?shape ?custom_shape
    ?center ?size ?orientation ?uniform_scale ?quasi_stratified
    ?velocity_stretch ?velocity_scale ?inherit_velocity ?radial_velocity
    ?noise_amplitude ?noise_frequency ?noise_offset ?noise_roughness
    ?noise_attenuation ?noise_turbulence ?noise_seed ~points_per_point
    ?scale_attribute geometry =
  protected "point_replicate" "invalid_geometry" (fun () ->
    point_replicate_raw ?cancel ?grain ?points ?keep_input ?seed ?id_attribute
      ?generated_group ?copy_point_attributes ?keep_source_attributes
      ?transform_attributes
      ?source_point_attribute ?source_index_attribute ?shape ?custom_shape
      ?center ?size ?orientation ?uniform_scale ?quasi_stratified
      ?velocity_stretch ?velocity_scale ?inherit_velocity ?radial_velocity
      ?noise_amplitude ?noise_frequency ?noise_offset ?noise_roughness
      ?noise_attenuation ?noise_turbulence ?noise_seed
      ~points_per_point ?scale_attribute geometry)

let color_by_height = Pdk_attrib.Color_by_height.run

let clean_raw = clean
let clean ?cancel ?grain ?epsilon ?remove_degenerate ?consolidate_distance
    ?overlaps ?reverse_winding ?remove_nan_points ?remove_unused_points
    ?delete_unused_groups ?point_attributes ?vertex_attributes
    ?primitive_attributes ?detail_attributes ?point_groups ?vertex_groups
    ?primitive_groups ?edge_groups geometry =
  protected "clean" "invalid_geometry"
    (fun () -> clean_raw ?cancel ?grain ?epsilon ?remove_degenerate
      ?consolidate_distance ?overlaps ?reverse_winding ?remove_nan_points
      ?remove_unused_points ?delete_unused_groups ?point_attributes
      ?vertex_attributes ?primitive_attributes ?detail_attributes ?point_groups
      ?vertex_groups ?primitive_groups ?edge_groups geometry)

let facet_raw = facet
let facet ?cancel ?grain ?selection ?primitives ?pre_compute_normals ?make_normals_unit_length
    ?unique_points ?consolidate_distance ?consolidate_normals_distance
    ?remove_inline_points ?inline_distance ?orient_polygons ?cusp_angle
    ?remove_degenerate ?make_planar
    ?post_compute_normals ?reverse_normals geometry =
  protected "facet" "invalid_geometry" (fun () ->
    let resolved = match selection, primitives with
      | Some _, Some _ -> Error
          "Facet selection and primitive selection are mutually exclusive"
      | None, primitives -> Ok primitives
      | Some selection, None -> Result.map Option.some
          (facet_primitives_of_selection ?cancel
            ~grain:(Option.value ~default:16_384 grain) selection geometry) in
    Result.bind resolved (fun primitives ->
      facet_raw ?cancel ?grain ?primitives ?pre_compute_normals
        ?make_normals_unit_length ?unique_points ?consolidate_distance
        ?consolidate_normals_distance ?remove_inline_points ?inline_distance
        ?orient_polygons ?remove_degenerate ?make_planar ?cusp_angle
        ?post_compute_normals ?reverse_normals geometry))

let poly_extrude ?cancel ?grain ?primitives ?split_edges ?divide ?divisions
    ?output_front ?output_back ?output_side ?front_group ?back_group ?side_group
    ?front_boundary_group ?back_boundary_group ~distance geometry =
  protected "poly_extrude" "invalid_geometry"
    (fun () -> Poly_extrude.run ?cancel ?grain ?primitives ?split_edges ?divide
      ?divisions ?output_front ?output_back ?output_side ?front_group ?back_group
      ?side_group ?front_boundary_group ?back_boundary_group ~distance geometry)

let poly_fill_raw = poly_fill
let poly_fill ?cancel ?grain ?boundary ?mode ?reverse_patches ?unique_points
    ?update_point_normals ?patch_group geometry =
  protected "poly_fill" "invalid_geometry"
    (fun () -> poly_fill_raw ?cancel ?grain ?boundary ?mode ?reverse_patches
      ?unique_points ?update_point_normals ?patch_group geometry)

let resample_curves ?cancel ?grain ?primitives ?segments ?maximum_segment_length
    ?segment_length_attribute ?segments_attribute ?even_last_segment
    ?curve_u_attribute ?curve_number_attribute ?distance_attribute
    ?tangent_attribute geometry =
  protected "resample_curves" "invalid_geometry"
    (fun () -> Resample_curves.run ?cancel ?grain ?primitives ?segments
      ?maximum_segment_length ?segment_length_attribute ?segments_attribute
      ?even_last_segment ?curve_u_attribute ?curve_number_attribute
      ?distance_attribute ?tangent_attribute geometry)

let convert_line ?cancel ?grain ?edges ?(connect_path = false)
    ?(maximum_distance = 0.001)
    ?(connect_only_to_other_end_points = false)
    ?(make_isolated_loops_closed = false) ?(remove_unused_points = false)
    ?length_attribute geometry =
  protected "convert_line" "invalid_geometry" (fun () ->
    let generated = if connect_path then
        Poly_path.run ?cancel ?grain ?edges ~preserve_source_payload:false
          ~connect_end_points:true ~maximum_distance
          ~connect_only_to_other_end_points ~make_isolated_loops_closed geometry
      else Curve_ops.convert_line ?cancel ?grain ?edges ?length_attribute geometry in
    Result.bind generated (fun output ->
      let compacted = if remove_unused_points
        then compact_points_raw ?cancel ?grain output else Ok output in
      Result.bind compacted (fun output ->
        if connect_path then match length_attribute with
          | None -> Ok output
          | Some name -> Curve_ops.with_length_attribute ?cancel ?grain ~name output
        else Ok output)) )

type curve_end_mode = Open_curve | Close_curve | Unroll_curve

let curve_ends ?cancel ?grain ?primitives mode geometry =
  let mode = match mode with
    | Open_curve -> Curve_ops.Open
    | Close_curve -> Curve_ops.Close
    | Unroll_curve -> Curve_ops.Unroll in
  protected "curve_ends" "invalid_geometry" (fun () ->
    Curve_ops.ends ?cancel ?grain ?primitives mode geometry)

type ends_mode =
  | Ends_open
  | Ends_close_straight
  | Ends_unroll_shared
  | Ends_unroll_new

type curve_join_end = Curve_ops.curve_join_end =
  | Join_curve_start
  | Join_curve_end

type curve_join_pick = Curve_ops.curve_join_pick = {
  primitive : int;
  end_ : curve_join_end;
}

let ends ?cancel ?grain ?primitives mode geometry =
  let mode = match mode with
    | Ends_open -> Curve_ops.Open
    | Ends_close_straight -> Curve_ops.Close_straight
    | Ends_unroll_shared -> Curve_ops.Unroll
    | Ends_unroll_new -> Curve_ops.Unroll_new in
  protected "ends" "invalid_geometry" (fun () ->
    Curve_ops.ends ?cancel ?grain ?primitives ~allow_polygons:true mode geometry)

let join_curves ?cancel ?grain ?primitives ?picked_ends ?orient_closest
    ?connect_closest_ends ?only_connected ?group_size ?keep_originals
    ?tolerance ?wrap geometry =
  protected "join_curves" "invalid_geometry" (fun () ->
    Curve_ops.join ?cancel ?grain ?primitives ?picked_ends ?orient_closest
      ?connect_closest_ends ?only_connected ?group_size ?keep_originals
      ?tolerance ?wrap geometry)

let poly_path ?cancel ?grain ?connect_end_points ?maximum_distance
    ?connect_only_to_other_end_points ?make_isolated_loops_closed geometry =
  protected "poly_path" "invalid_geometry" (fun () ->
    Poly_path.run ?cancel ?grain ?connect_end_points ?maximum_distance
      ?connect_only_to_other_end_points ?make_isolated_loops_closed geometry)

type carve_keep = Keep_inside | Keep_outside | Keep_inside_and_outside
type carve_attribute_mode = Attribute_replace | Attribute_scale

let carve_curves ?cancel ?grain ?primitives ?relative_arc_length ?first ?last
    ?first_attribute ?last_attribute ?(attribute_mode = Attribute_replace)
    ?(only_at_breakpoints = false) ?(cut_at_all_internal_breakpoints = false)
    ?(keep = Keep_inside) ?(extract_points = false) ?divisions ?keep_original geometry =
  protected "carve_curves" "invalid_geometry" (fun () ->
    let attribute_mode = match attribute_mode with
      | Attribute_replace -> Curve_ops.Replace
      | Attribute_scale -> Curve_ops.Scale in
    if extract_points then
      Curve_ops.extract_points ?cancel ?grain ?primitives ?relative_arc_length
        ?first ?last ?first_attribute ?last_attribute ~attribute_mode
        ~only_at_breakpoints ~cut_at_all_internal_breakpoints
        ?divisions ?keep_original geometry
    else
      let mode = match keep with
        | Keep_inside -> Curve_ops.Inside
        | Keep_outside -> Curve_ops.Outside
        | Keep_inside_and_outside -> Curve_ops.Inside_and_outside in
      Curve_ops.carve ?cancel ?grain ?primitives ?relative_arc_length ?first
        ?last ?first_attribute ?last_attribute ~attribute_mode
        ~only_at_breakpoints ~cut_at_all_internal_breakpoints ?divisions ~mode geometry)

let revolve_raw = Revolve.run
let revolve ?cancel ?grain ?primitives ?revolve_type ?connectivity ?start_angle
    ?end_angle ?reverse_cross_sections ?caps ?cap_group ?uv_attribute ~divisions
    ~origin ~axis geometry =
  protected "revolve" "invalid_geometry" (fun () ->
    revolve_raw ?cancel ?grain ?primitives ?revolve_type ?connectivity
      ?start_angle ?end_angle ?reverse_cross_sections ?caps ?cap_group
      ?uv_attribute ~divisions ~origin ~axis geometry)

let sweep ?cancel ?(grain = 16_384) ?backbones ?cross_sections
    ?(connectivity = Grid_quads) ?(tangent = Sweep_average_edges)
    ?(continuous_closed = true) ?(transform_attributes = true)
    ?(reverse_cross_sections = false) ?(scale = 1.) ?(roll = 0.) ?(twist = 0.)
    ?(caps = false) ?cap_group ?(uv_attribute = Some "uv")
    ?(cross_section_prefix = "cross_section_") ~backbone ~cross_section () =
  let connectivity = match connectivity with
    | Grid_points -> Sweep.Points
    | Grid_rows -> Sweep.Rows
    | Grid_columns -> Sweep.Columns
    | Grid_rows_and_columns -> Sweep.Rows_and_columns
    | Grid_quads -> Sweep.Quads
    | Grid_triangles -> Sweep.Triangles
    | Grid_alternating_triangles -> Sweep.Alternating_triangles
    | Grid_reverse_triangles -> Sweep.Reverse_triangles in
  let tangent = match tangent with
    | Sweep_average_edges -> Sweep.Average_edges
    | Sweep_central_difference -> Sweep.Central_difference
    | Sweep_previous_edge -> Sweep.Previous_edge
    | Sweep_next_edge -> Sweep.Next_edge
    | Sweep_z_axis -> Sweep.Z_axis in
  protected "sweep" "invalid_geometry" (fun () ->
    Sweep.run ?cancel ~grain ?backbones ?cross_sections ~connectivity ~tangent
      ~continuous_closed ~transform_attributes ~reverse_cross_sections ~scale
      ~roll ~twist ~caps ?cap_group ~uv_attribute ~cross_section_prefix
      ~backbone ~cross_section ())

let sweep_circle_raw = Sweep_circle.run
let sweep_circle ?cancel ?grain ?primitives ?sides ?divisions_attribute
    ?segments ?segments_attribute ?segment_scales ?segment_scales_attribute
    ?(prevent_joint_buckling = false) ?(maximum_joint_scale = 10.)
    ?maximum_joint_scale_attribute
    ?(smooth_point = true) ?smooth_attribute ?max_valence
    ?scale_attribute ?seam_offset ?seam_attribute ?segment_seam_attribute
    ?v_attribute
    ?(generate_uv = true) ?u_range ?v_range ?uv_range_attribute ?up_attribute
    ?caps ?cap_group ~radius geometry =
  protected "sweep_circle" "invalid_geometry"
    (fun () ->
      let grain = Option.value ~default:16_384 grain
      and sides = Option.value ~default:12 sides
      and segments = Option.value ~default:1 segments
      and seam_offset = Option.value ~default:0 seam_offset
      and caps = Option.value ~default:false caps in
      if Option.is_none primitives && Option.is_none divisions_attribute
          && segments = 1 && Option.is_none segments_attribute
          && Option.is_none segment_scales
          && Option.is_none segment_scales_attribute
          && not prevent_joint_buckling
          && Float.is_finite maximum_joint_scale && maximum_joint_scale >= 1.
          && Option.is_none maximum_joint_scale_attribute && generate_uv
          && smooth_point && Option.is_none smooth_attribute
          && Option.is_none max_valence
          && Option.is_none segment_seam_attribute
          && Option.is_none u_range && Option.is_none v_range
          && Option.is_none uv_range_attribute then
        sweep_circle_raw ?cancel ~grain ~sides ?scale_attribute ~seam_offset
          ?seam_attribute ?v_attribute ?up_attribute ~caps ?cap_group ~radius geometry
      else Polywire.run ?cancel ~grain ~primitives ~sides ~divisions_attribute
          ~segments ~segments_attribute ~segment_scales
          ~segment_scales_attribute ~prevent_joint_buckling
          ~maximum_joint_scale ~maximum_joint_scale_attribute ~scale_attribute
          ~smooth_point ~smooth_attribute ~max_valence
          ~seam_offset
          ~seam_attribute ~segment_seam_attribute ~v_attribute ~generate_uv
          ~u_range ~v_range
          ~uv_range_attribute ~up_attribute ~caps ~cap_group ~radius geometry)

let uv_project ?cancel ?grain ?name ?primitives ?u_range ?v_range
    ?fix_seams ?fix_poles projection geometry =
  protected "uv_project" "invalid_projection" (fun () ->
    Uv_ops.project ?cancel ?grain ?name ?primitives ?u_range ?v_range
      ?fix_seams ?fix_poles projection geometry)

let uv_transform ?cancel ?grain ?name ?selection ~owner ?translate ?scale
    ?angle ?pivot geometry =
  protected "uv_transform" "invalid_attribute" (fun () ->
    Uv_ops.transform ?cancel ?grain ?name ?selection ~owner ?translate ?scale
      ?angle ?pivot geometry)

let uv_auto_seam ?cancel ?grain ?name ?primitives ?angle ?include_boundaries
    ?include_non_manifold ?partition_attribute ?existing_uv ?uv_tolerance
    ?island_attribute geometry =
  protected "uv_auto_seam" "invalid_topology" (fun () ->
    Uv_ops.auto_seam ?cancel ?grain ?name ?primitives ?angle
      ?include_boundaries ?include_non_manifold ?partition_attribute
      ?existing_uv ?uv_tolerance ?island_attribute geometry)

let group_edges ?cancel ?grain ?name ?primitives ?incidence ?min_length
    ?max_length ?angle_basis ?min_angle ?max_angle geometry =
  protected "group_edges" "invalid_edge_group" (fun () ->
    Edge_ops.group ?cancel ?grain ?name ?primitives ?incidence ?min_length
      ?max_length ?angle_basis ?min_angle ?max_angle geometry)

let group_from_attribute_boundary ?cancel ?grain ?attributes ?tolerance
    ?include_unshared_edges ?include_all_unshared_curve_edges
    ?include_all_primitives_sharing_boundary_points ~owner ~name geometry =
  protected "group_from_attribute_boundary" "invalid_group" (fun () ->
    Group_ops.group_from_attribute_boundary ?cancel ?grain ?attributes ?tolerance
      ?include_unshared_edges ?include_all_unshared_curve_edges
      ?include_all_primitives_sharing_boundary_points ~owner ~name geometry)

let groups_from_name ?cancel ?grain ?prefix ?conflict ?invalid_names
    ?max_groups ?max_payload_bytes ~owner ~attribute geometry =
  Group_ops.groups_from_name_checked ?cancel ?grain ?prefix ?conflict
    ?invalid_names ?max_groups ?max_payload_bytes ~owner ~attribute geometry

let name_from_groups ?cancel ?grain ?attribute ?pattern ?default ?overlap
    ?delete_groups ~owner geometry =
  Group_ops.name_from_groups_checked ?cancel ?grain ?attribute ?pattern
    ?default ?overlap ?delete_groups ~owner geometry

let group_random ?cancel ?grain ?seed ?seed_attribute ?base ?merge
    ~probability ~owner ~name geometry =
  protected "group_random" "invalid_group" (fun () ->
    Group_ops.group_random ?cancel ?grain ?seed ?seed_attribute ?base ?merge
      ~probability ~owner ~name geometry)

let group_bounds ?cancel ?grain ?base ?containment ?merge bounds ~owner ~name
    geometry =
  protected "group_bounds" "invalid_group" (fun () ->
    Group_ops.group_bounds ?cancel ?grain ?base ?containment ?merge bounds
      ~owner ~name geometry)

let group_normal ?cancel ?grain ?normal_attribute ?use_existing_normal ?base
    ?include_opposite ?merge ~direction ~spread_angle ~owner ~name geometry =
  protected "group_normal" "invalid_group" (fun () ->
    Group_ops.group_normal ?cancel ?grain ?normal_attribute
      ?use_existing_normal ?base ?include_opposite ?merge ~direction
      ~spread_angle ~owner ~name geometry)

let group_non_planar ?cancel ?grain ?base ?merge ~tolerance ~name geometry =
  protected "group_non_planar" "invalid_group" (fun () ->
    Group_ops.group_non_planar ?cancel ?grain ?base ?merge ~tolerance ~name
      geometry)

let group_backface ?cancel ?grain ?base ?merge ~viewpoint ~name geometry =
  protected "group_backface" "invalid_group" (fun () ->
    Group_ops.group_backface ?cancel ?grain ?base ?merge ~viewpoint ~name
      geometry)

let group_edge_depth ?cancel ?grain ?merge ~depth ~point_group ~name geometry =
  protected "group_edge_depth" "invalid_group" (fun () ->
    Group_ops.group_edge_depth ?cancel ?grain ?merge ~depth ~point_group ~name
      geometry)

let group_unshared ?cancel ?grain ?merge ~owner ~name geometry =
  protected "group_unshared" "invalid_group" (fun () ->
    Group_ops.group_unshared ?cancel ?grain ?merge ~owner ~name geometry)

let group_boundary_components ?cancel ?grain ?prefix ?conflict ?max_groups
    ?max_payload_bytes geometry =
  protected "group_boundary_components" "invalid_group" (fun () ->
    Group_ops.group_boundary_components ?cancel ?grain ?prefix ?conflict
      ?max_groups ?max_payload_bytes geometry)

let group_promote ?cancel ?grain ?name ?keep_original ?output_attribute ?mode
    ~source ~destination ~group geometry =
  Group_ops.promote_checked ?cancel ?grain ?name ?keep_original
    ?output_attribute ?mode ~source ~destination ~group geometry

let group_promote_rule ?new_name ?keep_original ?output_as_attribute ?mode
    ~source ~destination ~pattern () =
  Group_ops.promotion_rule ?new_name ?keep_original ?output_as_attribute ?mode
    ~source ~destination ~pattern ()

let group_promote_boundary_rule ?new_name ?keep_original ?output_as_attribute
    ?attributes ?tolerance ?include_unshared_edges
    ?include_all_unshared_curve_edges
    ?include_all_primitives_sharing_boundary_points
    ~source ~destination ~pattern () =
  Group_ops.boundary_promotion_rule ?new_name ?keep_original
    ?output_as_attribute ?attributes ?tolerance ?include_unshared_edges
    ?include_all_unshared_curve_edges
    ?include_all_primitives_sharing_boundary_points
    ~source ~destination ~pattern ()

let group_promotions ?cancel ?grain ?max_outputs ?max_payload_bytes ~rules
    geometry =
  Group_ops.promotions_checked ?cancel ?grain ?max_outputs
    ?max_payload_bytes ~rules geometry

let group_promote_boundary ?cancel ?grain ?name ?keep_original
    ?output_attribute ?attributes ?tolerance ?include_unshared_edges
    ?include_all_unshared_curve_edges
    ?include_all_primitives_sharing_boundary_points
    ~source ~destination ~group geometry =
  protected "group_promote_boundary" "invalid_group" (fun () ->
    Group_ops.group_promote_boundary ?cancel ?grain ?name ?keep_original
      ?output_attribute ?attributes ?tolerance ?include_unshared_edges
      ?include_all_unshared_curve_edges
      ?include_all_primitives_sharing_boundary_points
      ~source ~destination ~group geometry)

let group_expand ?cancel ?grain ?name ?steps ?flood ?step_attribute
    ?primitive_connectivity ?normal_spread ?normal_attribute
    ?connectivity_attributes ?connectivity_tolerance ?collision
    ~owner ~group geometry =
  Group_ops.expand_checked ?cancel ?grain ?name ?steps ?flood ?step_attribute
    ?primitive_connectivity ?normal_spread ?normal_attribute
    ?connectivity_attributes ?connectivity_tolerance ?collision
    ~owner ~group geometry

let group_combine ?cancel ?grain ~owner ~name ~base ~steps geometry =
  protected "group_combine" "invalid_group" (fun () ->
    Group_ops.combine ?cancel ?grain ~owner ~name ~base ~steps geometry)

let group_range ?cancel ?grain ?base ?invert ?filter ?connectivity ?merge ~owner ~name
    range geometry =
  protected "group_range" "invalid_group" (fun () ->
    Group_ops.range ?cancel ?grain ?base ?invert ?filter ?connectivity ?merge
      ~owner ~name range geometry)

let group_range_rule ?base ?invert ?filter ?connectivity ?merge ~owner ~name
    range =
  Group_ops.range_rule ?base ?invert ?filter ?connectivity ?merge
    ~owner ~name range

let group_ranges ?cancel ?grain ~rules geometry =
  protected "group_ranges" "invalid_group" (fun () ->
    Group_ops.ranges ?cancel ?grain rules geometry)

let group_invert ?conflict ?owner ~pattern ?new_name geometry =
  protected "group_invert" "invalid_group" (fun () ->
    Group_ops.invert ?conflict ?owner ~pattern ?new_name geometry)

let group_delete ~rules ?delete_unused geometry =
  protected "group_delete" "invalid_group" (fun () ->
    Group_ops.delete ~rules ?delete_unused geometry)

let group_rename ~rules geometry =
  protected "group_rename" "invalid_group" (fun () ->
    Group_ops.rename ~rules geometry)

let group_copy ?cancel ?grain ?rules ?conflict ?copy_empty ~source ~target () =
  protected "group_copy" "invalid_group" (fun () ->
    Group_ops.copy ?cancel ?grain ?rules ?conflict ?copy_empty ~source ~target ())

let group_transfer ?cancel ?grain ?rules ?conflict ?create_empty ?distance
    ~source ~target () =
  protected "group_transfer" "invalid_group" (fun () ->
    Group_ops.transfer ?cancel ?grain ?rules ?conflict ?create_empty ?distance
      ~source ~target ())

let group_find_path ?cancel ?grain ?mode ?ending ?avoid_self_intersection
    ?collision ?contain ~base ~name geometry =
  protected "group_find_path" "invalid_group" (fun () ->
    Group_path.run ?cancel ?grain ?mode ?ending ?avoid_self_intersection
      ?collision ?contain ~base ~name geometry)

let uv_unitize ?cancel ?grain ?name ?primitives ?seams ?edge_seams ?tolerance
    ?uniform mode geometry =
  protected "uv_unitize" "invalid_uv" (fun () ->
    Uv_ops.unitize ?cancel ?grain ?name ?primitives ?seams ?edge_seams
      ?tolerance ?uniform mode geometry)

let uv_flatten ?cancel ?grain ?name ?seams ?edge_seams ?iterations ?tolerance
    geometry =
  protected "uv_flatten" "invalid_uv" (fun () ->
    Uv_ops.flatten ?cancel ?grain ?name ?seams ?edge_seams ?iterations
      ?tolerance geometry)

let uv_relax ?cancel ?grain ?name ?seams ?edge_seams ?uv_tolerance ?iterations
    ?tolerance geometry =
  protected "uv_relax" "invalid_uv" (fun () ->
    Uv_ops.relax ?cancel ?grain ?name ?seams ?edge_seams ?uv_tolerance
      ?iterations ?tolerance geometry)
