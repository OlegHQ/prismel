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
type poly_reduce_target =
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
type deform_selection = Deform.selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t

type transform_order =
  | Transform_srt | Transform_str | Transform_rst
  | Transform_rts | Transform_tsr | Transform_trs

type transform_rotation_order =
  | Transform_xyz | Transform_xzy | Transform_yxz
  | Transform_yzx | Transform_zxy | Transform_zyx

type soft_transform_metric =
  | Soft_radius
  | Soft_edge
  | Soft_attribute of { attribute : string; apply_rolloff : bool }

type soft_transform_falloff = Soft_linear | Soft_quadratic | Soft_cubic

type distance_along_radius =
  | Distance_fixed of float
  | Distance_maximum

type distance_from_geometry_reference =
  | Distance_reference_points
  | Distance_reference_primitives

type distance_from_target_projection =
  | Distance_target_spherical
  | Distance_target_cylindrical
  | Distance_target_planar

type distance_from_target_metric =
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

let uv_sphere = Uv_sphere.run

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

let remap_attribute ?cancel ~grain vertex_map primitive_map attribute =
  match Attribute.owner attribute with
  | Attribute.Point | Attribute.Detail -> Ok attribute
  | Attribute.Vertex ->
      Ok (Topology_remap.attribute ?cancel ~grain vertex_map attribute)
  | Attribute.Primitive ->
      Ok (Topology_remap.attribute ?cancel ~grain primitive_map attribute)

let remap_group ~grain vertex_map primitive_map group =
  match Group.owner group with
  | Group.Point -> group
  | Group.Vertex -> Topology_remap.group ~grain vertex_map group
  | Group.Primitive -> Topology_remap.group ~grain primitive_map group

let poly_reduce ?cancel ?(grain = 16_384) ?(target = Reduce_ratio 0.5)
    ?primitives ?hard_points ?hard_edges ?(preserve_boundary = true)
    ?(only_original_positions = false) ?(equalize_lengths = 1e-10)
    ?max_normal_deviation ?output_group ?(recompute_point_normals = true)
    geometry =
  try
    let original_geometry = geometry in
    if grain <= 0 then invalid_arg "Pdk.Ops.poly_reduce: grain must be positive";
    let original_primitives = Geometry.primitive_count geometry
    and original_points = Geometry.point_count geometry
    and original_topology = Geometry.topology geometry in
    (match target with
     | Reduce_ratio ratio when not (finite ratio) || ratio < 0. || ratio > 1. ->
         invalid_arg "Pdk.Ops.poly_reduce: ratio must be finite and in [0, 1]"
     | Reduce_primitive_count count when count < 0 ->
         invalid_arg
           "Pdk.Ops.poly_reduce: target primitive count must be non-negative"
     | Reduce_ratio _ | Reduce_primitive_count _ -> ());
    (match output_group with
     | Some name when String.trim name = "" ->
         invalid_arg "Pdk.Ops.poly_reduce: output group name must not be empty"
     | None | Some _ -> ());
    (match primitives with
     | Some group when Group.owner group <> Group.Primitive
         || Group.length group <> original_primitives ->
         invalid_arg
           "Pdk.Ops.poly_reduce: selection must be a matching primitive group"
     | None | Some _ -> ());
    (match hard_points with
     | Some group when Group.owner group <> Group.Point
         || Group.length group <> original_points ->
         invalid_arg
           "Pdk.Ops.poly_reduce: hard points must be a matching point group"
     | None | Some _ -> ());
    let original_index = Topology_index.create ?cancel original_topology in
    (match hard_edges with
     | Some group when Edge_group.topology_data_id group
         <> Topology.data_id original_topology
         || Edge_group.length group <> Topology_index.edge_count original_index ->
         invalid_arg
           "Pdk.Ops.poly_reduce: hard edges must belong to the input topology"
     | None | Some _ -> ());
    let requested_original = match target with
      | Reduce_ratio ratio ->
          int_of_float (ceil (ratio *. float_of_int original_primitives))
      | Reduce_primitive_count count -> count in
    if requested_original >= original_primitives then Ok geometry
    else begin
      Cancel.check_opt cancel;
      let unique_group_name owner base geometry =
        let rec choose suffix =
          let name = if suffix = 0 then base else base ^ string_of_int suffix in
          if Geometry.find_group ~owner name geometry = None then name
          else choose (suffix + 1) in
        choose 0 in
      let unique_edge_name base geometry =
        let rec choose suffix =
          let name = if suffix = 0 then base else base ^ string_of_int suffix in
          if Geometry.find_edge_group name geometry = None then name
          else choose (suffix + 1) in
        choose 0 in
      let install_group owner base supplied geometry = match supplied with
        | None -> geometry, None
        | Some group ->
            let name = unique_group_name owner base geometry in
            Geometry.with_group (Group.with_name name group) geometry |> get_ok,
            Some name in
      let geometry, primitive_name = install_group Group.Primitive
          "__pdk_poly_reduce_primitives" primitives geometry in
      let geometry, hard_point_name = install_group Group.Point
          "__pdk_poly_reduce_hard_points" hard_points geometry in
      let geometry, hard_edge_name = match hard_edges with
        | None -> geometry, None
        | Some group ->
            let name = unique_edge_name "__pdk_poly_reduce_hard_edges" geometry in
            Geometry.with_edge_group (Edge_group.with_name name group) geometry
              |> get_ok, Some name in
      Result.bind (Triangulate.run ?cancel ~grain geometry) (fun triangulated ->
        let working_count = Geometry.primitive_count triangulated in
        let working_index = Topology_index.create ?cancel
            (Geometry.topology triangulated) in
        let scratch = Poly_reduce.create_scratch
            ~points:(Geometry.point_count triangulated)
            ~primitives:working_count
            ~edges:(Topology_index.edge_count working_index) in
        let target_count = match target with
          | Reduce_ratio ratio ->
              int_of_float (ceil (ratio *. float_of_int working_count))
          | Reduce_primitive_count count -> count in
        let had_point_normals = Geometry.find_attribute ~owner:Attribute.Point
            "N" geometry <> None in
        let rec reduce round current =
          Cancel.check_opt cancel;
          let count = Geometry.primitive_count current in
          if count <= target_count then Ok current
          else if round > 128 then Error
              "Pdk.Ops.poly_reduce: adaptive reduction exceeded 128 rounds"
          else
            let primitive_selection = Option.bind primitive_name (fun name ->
              Geometry.find_group ~owner:Group.Primitive name current)
            and hard_points = Option.bind hard_point_name (fun name ->
              Geometry.find_group ~owner:Group.Point name current)
            and hard_edges = Option.bind hard_edge_name (fun name ->
              Geometry.find_edge_group name current) in
            match Poly_reduce.plan_round ?cancel ~scratch ~grain
                ~primitive_selection ~hard_points ~hard_edges ~preserve_boundary
                ~only_original_positions ~equalize_lengths ~max_normal_deviation
                ~primitive_budget:(count - target_count) current with
            | Error message -> Error message
            | Ok plan when plan.Poly_reduce.removed_primitives = 0 -> Ok current
            | Ok plan ->
                let position = if only_original_positions
                  then Least_point_position else Average_position in
                (match Edge_collapse.raw ?cancel ~grain ~edges:plan.edges
                    ~position ~remove_degenerate_primitives:true
                    ~recompute_point_normals:false current with
                 | Error message -> Error message
                 | Ok next when Geometry.primitive_count next >= count -> Error
                       "Pdk.Ops.poly_reduce: a planned contraction made no progress"
                 | Ok next -> reduce (round + 1) next) in
        Result.bind (reduce 0 triangulated) (fun output ->
          if output == triangulated
              && Geometry.topology triangulated == original_topology then
            match output_group with
            | None -> Ok original_geometry
            | Some name ->
                let group = match primitives with
                  | Some group -> Group.with_name name group
                  | None -> Group.init ~grain ~owner:Group.Primitive ~name
                      original_primitives (fun _ -> true) in
                Geometry.with_group group original_geometry
          else
          let output = match output_group with
            | None -> output
            | Some name ->
                let group = match primitive_name with
                  | Some source_name ->
                      (match Geometry.find_group ~owner:Group.Primitive
                          source_name output with
                       | Some group -> Group.with_name name group
                       | None -> Group.init ~grain ~owner:Group.Primitive ~name
                           (Geometry.primitive_count output) (fun _ -> false))
                  | None -> Group.init ~grain ~owner:Group.Primitive ~name
                      (Geometry.primitive_count output) (fun _ -> true) in
                Geometry.with_group group output |> get_ok in
          let output = match primitive_name with None -> output | Some name ->
              Geometry.without_group ~owner:Group.Primitive name output in
          let output = match hard_point_name with None -> output | Some name ->
              Geometry.without_group ~owner:Group.Point name output in
          let output = match hard_edge_name with None -> output | Some name ->
              Geometry.without_edge_group name output in
          let output = Geometry.without_attribute ~owner:Attribute.Point "N" output
              |> Geometry.without_attribute ~owner:Attribute.Vertex "N" in
          if recompute_point_normals && had_point_normals then
            Deform.normals ?cancel ~grain output
          else Ok output))
    end
  with Invalid_argument message -> Error message

let edge_flip ?cancel ?(grain = 16_384) ?edges ?(cycles = 1)
    ?(cycle_vertex_attributes = true) ?(recompute_point_normals = false)
    geometry =
  try
    if grain <= 0 then invalid_arg "Pdk.Ops.edge_flip: grain must be positive";
    if cycles < 0 then invalid_arg
        "Pdk.Ops.edge_flip: cycles must be non-negative";
    Cancel.check_opt cancel;
    let source_topology = Geometry.topology geometry in
    let source = Topology.Private.view source_topology in
    let source_index_value = Topology_index.create ?cancel source_topology in
    let source_index = Topology_index.Private.view source_index_value in
    let edge_count = Array.length source_index.edge_a
    and primitive_count = Bytes.length source.primitive_kinds
    and point_count = source.point_count in
    (match edges with
     | Some group when Edge_group.topology_data_id group
         <> Topology.data_id source_topology ->
         invalid_arg "Pdk.Ops.edge_flip: edge selection belongs to a different topology"
     | Some group when Edge_group.length group <> edge_count ->
         invalid_arg
           "Pdk.Ops.edge_flip: edge selection length does not match topology edge count"
     | None | Some _ -> ());
    if cycles = 0 || (match edges with None -> true
        | Some group -> Edge_group.cardinality group = 0) then Ok geometry
    else begin
      let selected edge = match edges with
        | None -> false
        | Some group -> Edge_group.mem edge group in
      let plan_vertex_a = Array.make edge_count (-1)
      and plan_vertex_b = Array.make edge_count (-1)
      and plan_primitive_a = Array.make edge_count (-1)
      and plan_primitive_b = Array.make edge_count (-1)
      and plan_size_a = Array.make edge_count 0
      and plan_size_b = Array.make edge_count 0
      and plan_shift = Array.make edge_count 0
      and primitive_owner = Array.make primitive_count (-1)
      and point_stamp = Array.make point_count (-1) in
      let first_error = ref None and changed = ref 0 in
      let fail edge message = match !first_error with
        | None -> first_error := Some (edge, message)
        | Some (known, _) when edge < known -> first_error := Some (edge, message)
        | Some _ -> () in
      let advance first size vertex amount =
        first + (((vertex - first) + amount) mod size) in
      let ring_point vertex_a vertex_b size_a size_b index =
        let primitive_a = source_index.primitive_of_vertex.(vertex_a)
        and primitive_b = source_index.primitive_of_vertex.(vertex_b) in
        let first_a = source.primitive_offsets.(primitive_a)
        and first_b = source.primitive_offsets.(primitive_b) in
        if index = 0 then source.vertex_points.(vertex_a)
        else if index < size_b - 1 then
          source.vertex_points.(advance first_b size_b vertex_b (index + 1))
        else if index = size_b - 1 then
          source.vertex_points.(source_index.next_vertex.(vertex_a))
        else source.vertex_points.(advance first_a size_a vertex_a
            (index - size_b + 2)) in
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      for edge = 0 to edge_count - 1 do
        if edge land 4095 = 0 then Cancel.check_opt cancel;
        if selected edge then begin
          let first_incidence = source_index.edge_offsets.(edge)
          and last_incidence = source_index.edge_offsets.(edge + 1) in
          if last_incidence - first_incidence <> 2 then fail edge
              "selected edge must have exactly two incident polygons"
          else begin
            let vertex_a = source_index.edge_vertices.(first_incidence)
            and vertex_b = source_index.edge_vertices.(first_incidence + 1) in
            let primitive_a = source_index.primitive_of_vertex.(vertex_a)
            and primitive_b = source_index.primitive_of_vertex.(vertex_b) in
            if primitive_a = primitive_b then fail edge
                "selected edge occurs twice in one polygon"
            else if Bytes.get source.primitive_kinds primitive_a <> '\000'
                || Bytes.get source.primitive_kinds primitive_b <> '\000'
            then fail edge "selected edge must join two polygon primitives"
            else begin
              let next_a = source_index.next_vertex.(vertex_a)
              and next_b = source_index.next_vertex.(vertex_b) in
              if next_a < 0 || next_b < 0
                  || source.vertex_points.(vertex_a)
                     <> source.vertex_points.(next_b)
                  || source.vertex_points.(next_a)
                     <> source.vertex_points.(vertex_b)
              then fail edge
                  "selected polygons have inconsistent orientation across their edge"
              else begin
                let size_a = source.primitive_offsets.(primitive_a + 1)
                    - source.primitive_offsets.(primitive_a)
                and size_b = source.primitive_offsets.(primitive_b + 1)
                    - source.primitive_offsets.(primitive_b) in
                if size_a < 3 || size_b < 3 then fail edge
                    "selected edge is incident to an under-cardinality polygon"
                else if size_a > max_int - size_b + 2 then fail edge
                    "joined polygon boundary exceeds integer limits"
                else begin
                  let ring_size = size_a + size_b - 2 in
                  let shift = cycles mod ring_size
                  and attribute_a = cycles mod size_a
                  and attribute_b = cycles mod size_b in
                  let effective = shift <> 0 || cycle_vertex_attributes
                      && (attribute_a <> 0 || attribute_b <> 0) in
                  if effective then begin
                    if primitive_owner.(primitive_a) >= 0
                        || primitive_owner.(primitive_b) >= 0 then fail edge
                        "selected edges may not share an incident polygon; sequence dependent flips as separate nodes"
                    else begin
                      let duplicate = ref (-1) in
                      for index = 0 to ring_size - 1 do
                        let point = ring_point vertex_a vertex_b size_a size_b index in
                        if point_stamp.(point) = edge then duplicate := point
                        else point_stamp.(point) <- edge
                      done;
                      if !duplicate >= 0 then fail edge (Printf.sprintf
                          "joined polygon boundary repeats point %d" !duplicate)
                      else begin
                        let valid_diagonal = ref true in
                        if shift <> 0 then begin
                          let left = ring_point vertex_a vertex_b size_a size_b shift
                          and right = ring_point vertex_a vertex_b size_a size_b
                              ((shift + size_b - 1) mod ring_size) in
                          let existing = Topology_index.find_edge_index
                              source_index_value ~a:left ~b:right in
                          if left = right then begin
                            valid_diagonal := false;
                            fail edge "flipped edge would reference one point twice"
                          end else if existing >= 0 && existing <> edge then begin
                            valid_diagonal := false;
                            fail edge (Printf.sprintf
                              "flipped edge would duplicate source edge %d" existing)
                          end else if not (finite positions.x.(left)
                              && finite positions.y.(left)
                              && finite positions.z.(left)
                              && finite positions.x.(right)
                              && finite positions.y.(right)
                              && finite positions.z.(right)) then begin
                            valid_diagonal := false;
                            fail edge "flipped edge has a non-finite endpoint"
                          end else if positions.x.(left) = positions.x.(right)
                              && positions.y.(left) = positions.y.(right)
                              && positions.z.(left) = positions.z.(right) then begin
                            valid_diagonal := false;
                            fail edge "flipped edge would have zero geometric length"
                          end
                        end;
                        if !valid_diagonal && !first_error = None then begin
                          primitive_owner.(primitive_a) <- edge;
                          primitive_owner.(primitive_b) <- edge;
                          plan_vertex_a.(edge) <- vertex_a;
                          plan_vertex_b.(edge) <- vertex_b;
                          plan_primitive_a.(edge) <- primitive_a;
                          plan_primitive_b.(edge) <- primitive_b;
                          plan_size_a.(edge) <- size_a;
                          plan_size_b.(edge) <- size_b;
                          plan_shift.(edge) <- shift;
                          incr changed
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      done;
      match !first_error with
      | Some (edge, message) -> Error (Printf.sprintf
          "Pdk.Ops.edge_flip: edge %d: %s" edge message)
      | None when !changed = 0 -> Ok geometry
      | None ->
          let vertex_points = Array.copy source.vertex_points
          and vertex_map = Array.init (Array.length source.vertex_points) Fun.id in
          let fill_plan edge =
            let vertex_a = plan_vertex_a.(edge) in
            if vertex_a >= 0 then begin
              let vertex_b = plan_vertex_b.(edge)
              and primitive_a = plan_primitive_a.(edge)
              and primitive_b = plan_primitive_b.(edge)
              and size_a = plan_size_a.(edge)
              and size_b = plan_size_b.(edge)
              and shift = plan_shift.(edge) in
              let ring_size = size_a + size_b - 2
              and first_a = source.primitive_offsets.(primitive_a)
              and first_b = source.primitive_offsets.(primitive_b) in
              let diagonal_b = (shift + size_b - 1) mod ring_size in
              for local = 0 to size_a - 1 do
                let target = advance first_a size_a vertex_a local in
                let ring = if local = 0 then shift
                  else if local = 1 then diagonal_b
                  else (diagonal_b + local - 1) mod ring_size in
                vertex_points.(target) <-
                  ring_point vertex_a vertex_b size_a size_b ring;
                if cycle_vertex_attributes then vertex_map.(target) <-
                    advance first_a size_a vertex_a
                      ((local + (cycles mod size_a)) mod size_a)
              done;
              for local = 0 to size_b - 1 do
                let target = advance first_b size_b vertex_b local in
                let ring = if local = 0 then diagonal_b
                  else if local = 1 then shift
                  else (shift + local - 1) mod ring_size in
                vertex_points.(target) <-
                  ring_point vertex_a vertex_b size_a size_b ring;
                if cycle_vertex_attributes then vertex_map.(target) <-
                    advance first_b size_b vertex_b
                      ((local + (cycles mod size_b)) mod size_b)
              done
            end in
          Parallel.for_ ~chunk_size:(max 1 (grain / 4)) ~start:0
            ~finish:(edge_count - 1) (fun edge ->
              if edge land 4095 = 0 then Cancel.check_opt cancel;
              fill_plan edge);
          let output_topology = Topology.Private.create_validated_owned
              ~point_count ~vertex_points
              ~primitive_offsets:(Array.copy source.primitive_offsets)
              ~primitive_kinds:(Bytes.copy source.primitive_kinds) in
          let output_view = Topology.Private.view output_topology in
          let validation_grain = max 1 (grain / 4) in
          let block_count = (edge_count + validation_grain - 1)
              / validation_grain in
          let first_failure = Atomic.make max_int in
          let rec record_failure edge =
            let known = Atomic.get first_failure in
            if edge < known
                && not (Atomic.compare_and_set first_failure known edge) then
              record_failure edge in
          Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(block_count - 1)
            (fun block ->
              let scratch = Polygon_triangulation.create_scratch () in
              let first = block * validation_grain
              and last = min (edge_count - 1)
                  (((block + 1) * validation_grain) - 1) in
              for edge = first to last do
                if edge land 4095 = 0 then Cancel.check_opt cancel;
                if edge < Atomic.get first_failure
                    && plan_vertex_a.(edge) >= 0 && plan_shift.(edge) <> 0
                then begin
                  let valid primitive =
                    match Polygon_triangulation.primitive ?cancel ~positions
                        ~topology:output_view ~scratch primitive
                        ~emit:(fun _ _ _ _ -> ()) with
                    | Ok () -> true
                    | Error _ -> false in
                  if not (valid plan_primitive_a.(edge))
                      || not (valid plan_primitive_b.(edge)) then
                    record_failure edge
                end
              done);
          let failure = Atomic.get first_failure in
          (if failure <> max_int then
             let scratch = Polygon_triangulation.create_scratch () in
             let rec diagnose = function
               | [] -> Error (Printf.sprintf
                   "Pdk.Ops.edge_flip: edge %d creates an invalid polygon"
                   failure)
               | primitive :: rest ->
                   match Polygon_triangulation.primitive ?cancel ~positions
                       ~topology:output_view ~scratch primitive
                       ~emit:(fun _ _ _ _ -> ()) with
                   | Ok () -> diagnose rest
                   | Error message -> Error (Printf.sprintf
                       "Pdk.Ops.edge_flip: edge %d creates invalid polygon %d: %s"
                       failure primitive message) in
             diagnose [plan_primitive_a.(failure); plan_primitive_b.(failure)]
           else
              let had_point_normals = Geometry.find_attribute
                  ~owner:Attribute.Point "N" geometry <> None in
              let primitive_map = Array.init primitive_count Fun.id in
              let rec remap_attributes result = function
                | [] -> Ok (List.rev result)
                | attribute :: rest ->
                    if String.equal (Attribute.name attribute) "N"
                        && (Attribute.owner attribute = Attribute.Point
                            || Attribute.owner attribute = Attribute.Vertex)
                    then remap_attributes result rest
                    else if cycle_vertex_attributes
                        && Attribute.owner attribute = Attribute.Vertex then
                      Result.bind (remap_attribute ?cancel ~grain vertex_map
                          primitive_map attribute) (fun mapped ->
                        remap_attributes (mapped :: result) rest)
                    else remap_attributes (attribute :: result) rest in
              Result.bind (remap_attributes [] (Geometry.attributes geometry))
                (fun attributes ->
                  let groups = Geometry.groups geometry |> List.map (fun group ->
                    if cycle_vertex_attributes
                        && Group.owner group = Group.Vertex then
                      remap_group ~grain vertex_map primitive_map group
                    else group) in
                  let target_index = Topology_index.create ?cancel output_topology in
                  let target_edge_count = Topology_index.edge_count target_index in
                  let source_of_target = Array.init target_edge_count (fun target ->
                    let a, b = Topology_index.edge_points target_index target in
                    Topology_index.find_edge_index source_index_value ~a ~b) in
                  for edge = 0 to edge_count - 1 do
                    if plan_vertex_a.(edge) >= 0 && plan_shift.(edge) <> 0 then begin
                      let vertex_a = plan_vertex_a.(edge)
                      and vertex_b = plan_vertex_b.(edge)
                      and size_a = plan_size_a.(edge)
                      and size_b = plan_size_b.(edge)
                      and shift = plan_shift.(edge) in
                      let ring_size = size_a + size_b - 2 in
                      let a = ring_point vertex_a vertex_b size_a size_b shift
                      and b = ring_point vertex_a vertex_b size_a size_b
                          ((shift + size_b - 1) mod ring_size) in
                      let target = Topology_index.find_edge_index target_index
                          ~a ~b in
                      if target < 0 then invalid_arg
                          "Pdk.Ops.edge_flip: flipped edge is absent from output";
                      source_of_target.(target) <- edge
                    end
                  done;
                  if Array.exists (( = ) (-1)) source_of_target then Error
                      "Pdk.Ops.edge_flip: output edge has no source ancestry"
                  else begin
                    let edge_groups = Geometry.edge_groups geometry
                        |> List.map (fun group ->
                          Edge_group.init ~grain ~topology:output_topology
                            ~index:target_index ~name:(Edge_group.name group)
                            (fun target -> Edge_group.mem
                              source_of_target.(target) group)) in
                    Result.bind (Geometry.create
                        ~positions:(Geometry.positions geometry)
                        ~topology:output_topology ~attributes ~groups
                        ~edge_groups ()) (fun output ->
                      if not recompute_point_normals || not had_point_normals
                      then Ok output
                      else Deform.normals ?cancel ~grain output)
                  end))
    end
  with Invalid_argument message -> Error message

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

let normalized_direction ?(grain = 16_384) matrix values =
  let source = Packed.Float3.Private.view values in
  let count = Array.length source.x in
  let x = Array.make count 0. and y = Array.make count 0. and z = Array.make count 0. in
  let (m00,m01,m02,_), (m10,m11,m12,_), (m20,m21,m22,_), _ =
    Mat4.to_rows matrix in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun index ->
        let vx = source.x.(index) and vy = source.y.(index)
        and vz = source.z.(index) in
        let ox = m00 *. vx +. m01 *. vy +. m02 *. vz
        and oy = m10 *. vx +. m11 *. vy +. m12 *. vz
        and oz = m20 *. vx +. m21 *. vy +. m22 *. vz in
        let length = sqrt ((ox *. ox) +. (oy *. oy) +. (oz *. oz)) in
        if length > 1e-20 then begin
          x.(index) <- ox /. length;
          y.(index) <- oy /. length;
          z.(index) <- oz /. length
        end);
  Packed.Float3.Private.of_owned_exn ~x ~y ~z

let transform_rotation_matrix order angles =
  let x = Mat4.rotation_x angles.Vec3.x
  and y = Mat4.rotation_y angles.y
  and z = Mat4.rotation_z angles.z in
  let first, second, third = match order with
    | Transform_xyz -> x, y, z | Transform_xzy -> x, z, y
    | Transform_yxz -> y, x, z | Transform_yzx -> y, z, x
    | Transform_zxy -> z, x, y | Transform_zyx -> z, y, x in
  Mat4.mul third (Mat4.mul second first)

let compose_transform_raw ?(order = Transform_srt)
    ?(rotation_order = Transform_xyz) ?(translate = Vec3.zero)
    ?(rotate = Vec3.zero) ?(scale = Vec3.create 1. 1. 1.) ?(shear = Vec3.zero)
    ?(uniform_scale = 1.) ?(pivot = Vec3.zero)
    ?(pivot_rotation = Vec3.zero) ?(invert = false) () =
  let vectors = ["translate", translate; "rotate", rotate; "scale", scale;
    "shear", shear; "pivot", pivot; "pivot_rotation", pivot_rotation] in
  match List.find_opt (fun (_, value) -> not (finite value.Vec3.x
      && finite value.y && finite value.z)) vectors with
  | Some (name, _) -> Error ("Pdk.Ops.compose_transform: non-finite " ^ name)
  | None when not (Float.is_finite uniform_scale) ->
      Error "Pdk.Ops.compose_transform: non-finite uniform scale"
  | None ->
      let scale = Vec3.scale scale uniform_scale in
      let scale_shear = Mat4.mul
          (Mat4.of_rows
            (1., shear.x, shear.y, 0.)
            (0., 1., shear.z, 0.)
            (0., 0., 1., 0.)
            (0., 0., 0., 1.))
          (Mat4.scaling scale)
      and rotation = transform_rotation_matrix rotation_order rotate
      and translation = Mat4.translation translate in
      let first, second, third = match order with
        | Transform_srt -> scale_shear, rotation, translation
        | Transform_str -> scale_shear, translation, rotation
        | Transform_rst -> rotation, scale_shear, translation
        | Transform_rts -> rotation, translation, scale_shear
        | Transform_tsr -> translation, scale_shear, rotation
        | Transform_trs -> translation, rotation, scale_shear in
      let core = Mat4.mul third (Mat4.mul second first) in
      let pivot_rotation = transform_rotation_matrix rotation_order pivot_rotation in
      let pivot_inverse = Mat4.transpose pivot_rotation in
      let matrix = Mat4.mul (Mat4.translation pivot)
          (Mat4.mul pivot_rotation
            (Mat4.mul core
              (Mat4.mul pivot_inverse
                (Mat4.translation (Vec3.scale pivot (-1.)))))) in
      if not invert then Ok matrix
      else match Mat4.inverse matrix with
        | Some inverse -> Ok inverse
        | None -> Error "Pdk.Ops.compose_transform: cannot invert a singular transform"

let transform_matrix_finite matrix =
  let rows = Mat4.to_rows matrix in
  let finite_row (x, y, z, w) = Float.is_finite x && Float.is_finite y
      && Float.is_finite z && Float.is_finite w in
  let a, b, c, d = rows in
  finite_row a && finite_row b && finite_row c && finite_row d

let transform_selected_positions ?cancel ~grain matrix selected geometry =
  let source = Packed.Float3.Private.view (Geometry.positions geometry) in
  let count = Array.length source.x in
  let x = Array.copy source.x and y = Array.copy source.y
  and z = Array.copy source.z in
  let (m00,m01,m02,m03), (m10,m11,m12,m13),
      (m20,m21,m22,m23), (m30,m31,m32,m33) = Mat4.to_rows matrix in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if (match selected with None -> true
            | Some selected -> Group.mem point selected) then begin
          let vx = source.x.(point) and vy = source.y.(point)
          and vz = source.z.(point) in
          let ox = m00*.vx +. m01*.vy +. m02*.vz +. m03
          and oy = m10*.vx +. m11*.vy +. m12*.vz +. m13
          and oz = m20*.vx +. m21*.vy +. m22*.vz +. m23
          and ow = m30*.vx +. m31*.vy +. m32*.vz +. m33 in
          if abs_float ow <= 1e-12 then begin
            x.(point) <- ox; y.(point) <- oy; z.(point) <- oz
          end else begin
            x.(point) <- ox /. ow; y.(point) <- oy /. ow;
            z.(point) <- oz /. ow
          end
        end);
  Geometry.with_positions (Packed.Float3.Private.of_owned_exn ~x ~y ~z) geometry

let transform_selected_normals ?cancel ~grain ~preserve_length matrix selected
    owner geometry =
  match Geometry.find_attribute ~owner "N" geometry with
  | None -> Ok geometry
  | Some attribute ->
      (match Attribute.get (Attribute.normal ~owner) attribute with
       | None -> Ok geometry
       | Some packed ->
           let source = Packed.Float3.Private.view packed in
           let count = Array.length source.x in
           let x = Array.copy source.x and y = Array.copy source.y
           and z = Array.copy source.z in
           let (m00,m01,m02,_), (m10,m11,m12,_), (m20,m21,m22,_), _ =
             Mat4.to_rows matrix in
           let topology = Topology.Private.view (Geometry.topology geometry) in
           let selected_element element = match selected with
             | None -> true
             | Some selected -> match owner with
               | Attribute.Point -> Group.mem element selected
               | Attribute.Vertex ->
                   Group.mem topology.vertex_points.(element) selected
               | Attribute.Primitive | Attribute.Detail -> assert false in
           if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
               ~finish:(count - 1) (fun element ->
                 if element land 4095 = 0 then Cancel.check_opt cancel;
                 if selected_element element then begin
                   let vx = source.x.(element) and vy = source.y.(element)
                   and vz = source.z.(element) in
                   let ox = m00*.vx +. m01*.vy +. m02*.vz
                   and oy = m10*.vx +. m11*.vy +. m12*.vz
                   and oz = m20*.vx +. m21*.vy +. m22*.vz in
                   let output_length = sqrt (ox*.ox +. oy*.oy +. oz*.oz) in
                   if output_length > 1e-20 then begin
                     let target_length = if preserve_length then
                         sqrt (vx*.vx +. vy*.vy +. vz*.vz) else 1. in
                     let factor = target_length /. output_length in
                     x.(element) <- ox *. factor; y.(element) <- oy *. factor;
                     z.(element) <- oz *. factor
                   end else begin
                     x.(element) <- 0.; y.(element) <- 0.; z.(element) <- 0.
                   end
                 end);
           Result.bind (Attribute.create_key_owned (Attribute.normal ~owner)
               (Packed.Float3.Private.of_owned_exn ~x ~y ~z))
             (fun normal -> Geometry.with_attribute normal geometry))

let transform_selected_raw ?cancel ?(grain = 16_384) ?selection
    ?(preserve_normal_length = false) ?(recompute_normals = false)
    matrix geometry =
  if grain <= 0 then Error "Pdk.Ops.transform_selected: grain must be positive"
  else if not (transform_matrix_finite matrix) then
    Error "Pdk.Ops.transform_selected: matrix must be finite"
  else Result.bind (Element_selection.validate ~operation:"Pdk.Ops.transform_selected"
      (Geometry.topology geometry) selection) (fun () ->
    let point_count = Geometry.point_count geometry in
    let selected_result = match selection with
      | None -> Ok None
      | Some selection -> Result.map Option.some
          (Element_selection.promote ?cancel ~grain ~destination:Group.Point
            selection (Geometry.topology geometry)) in
    Result.bind selected_result (fun selected ->
      let selected_count = match selected with
        | None -> point_count | Some group -> Group.cardinality group in
      if selected_count = 0 || Mat4.nearly_equal matrix Mat4.identity ~eps:0.
      then Ok geometry
      else begin
        Cancel.check_opt cancel;
        let positioned = transform_selected_positions ?cancel ~grain matrix
            selected geometry in
        Result.bind positioned (fun positioned ->
          let existing_normal_owners = List.filter (fun owner ->
              Geometry.find_attribute ~owner "N" geometry <> None)
              [Attribute.Point; Attribute.Vertex] in
          if recompute_normals then
            List.fold_left (fun result owner -> Result.bind result (fun output ->
                Normal_ops.run ?cancel ~grain ~owner output))
              (Ok positioned) existing_normal_owners
          else match Mat4.inverse matrix with
            | None -> Ok (positioned
                |> Geometry.without_attribute ~owner:Attribute.Point "N"
                |> Geometry.without_attribute ~owner:Attribute.Vertex "N")
            | Some inverse ->
                let normal_matrix = Mat4.transpose inverse in
                List.fold_left (fun result owner -> Result.bind result
                    (transform_selected_normals ?cancel ~grain
                      ~preserve_length:preserve_normal_length normal_matrix
                      selected owner))
                  (Ok positioned) existing_normal_owners
        )
      end))

let soft_transform_weight falloff distance radius =
  if distance > radius then 0.
  else
    let t = Float.max 0. (Float.min 1. (distance /. radius)) in
    match falloff with
    | Soft_linear -> 1. -. t
    | Soft_quadratic -> 1. -. (t *. t)
    | Soft_cubic ->
        let t2 = t *. t in
        1. -. ((3. *. t2) -. (2. *. t2 *. t))

let validate_finite_positions ?cancel ~grain ~operation geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let count = Array.length positions.x and first_invalid = Atomic.make max_int in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if not (finite positions.x.(point) && finite positions.y.(point)
            && finite positions.z.(point)) then begin
          let rec lower observed =
            if point < observed
                && not (Atomic.compare_and_set first_invalid observed point)
            then lower (Atomic.get first_invalid) in
          lower (Atomic.get first_invalid)
        end);
  let invalid = Atomic.get first_invalid in
  if invalid = max_int then Ok positions
  else Error (Printf.sprintf
      "%s: point %d has a non-finite position" operation invalid)

let soft_radius_weights ?cancel ~grain ~radius ~falloff selected geometry =
  let positions = Geometry.positions geometry in
  Result.bind (Spatial_index.create ?cancel ~grain ?points:selected positions
      |> Result.map_error Error.to_string) (fun index ->
    let count = Geometry.point_count geometry in
    let indices = Array.make count (-1) and distances = Array.make count infinity
    and counts = Array.make count 0 in
    Spatial_index.Private.nearest_k_many_into ?cancel ~grain index
      ~queries:positions ~max_distance_squared:(radius *. radius) ~capacity:1
      ~indices ~distances_squared:distances ~counts;
    let weights = Array.make count 0. in
    if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
        (fun point ->
          if point land 4095 = 0 then Cancel.check_opt cancel;
          if counts.(point) <> 0 then
            weights.(point) <- soft_transform_weight falloff
                (sqrt distances.(point)) radius);
    Ok weights)

let soft_edge_distances ?cancel ~radius selected geometry =
  let count = Geometry.point_count geometry in
  let source_count = match selected with
    | None -> count
    | Some group -> Group.cardinality group in
  if source_count = 0 || count = 0 then Array.make count infinity
  else if source_count = count then Array.make count 0.
  else
  let topology_value = Geometry.topology geometry in
  let reverse = Topology_index.create ?cancel topology_value
      |> Topology_index.Private.view in
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let distances = Array.make count infinity in
  (* An indexed decrease-key heap admits each point at most once. [positions]
     is -1 before insertion, a heap slot while queued, and -2 after pop. *)
  let heap_points = Array.make count 0 and heap_positions = Array.make count (-1)
  and heap_size = ref 0 in
  let less_point left right = distances.(left) < distances.(right)
      || (distances.(left) = distances.(right) && left < right) in
  let assign slot point =
    heap_points.(slot) <- point; heap_positions.(point) <- slot in
  let rec bubble_up slot point =
    if slot = 0 then assign 0 point
    else
      let parent = (slot - 1) / 2 and parent_point = heap_points.((slot - 1) / 2) in
      if less_point point parent_point then begin
        assign slot parent_point;
        bubble_up parent point
      end else assign slot point in
  let enqueue_or_decrease point =
    let slot = heap_positions.(point) in
    if slot = -1 then begin
      let slot = !heap_size in
      incr heap_size;
      bubble_up slot point
    end else if slot >= 0 then bubble_up slot point in
  let rec sift_down slot point =
    let left = (slot * 2) + 1 in
    if left >= !heap_size then assign slot point
    else
      let right = left + 1 in
      let child = if right < !heap_size
          && less_point heap_points.(right) heap_points.(left)
        then right else left in
      let child_point = heap_points.(child) in
      if less_point child_point point then begin
        assign slot child_point;
        sift_down child point
      end else assign slot point in
  let pop () =
    let point = heap_points.(0) in
    heap_positions.(point) <- -2;
    decr heap_size;
    if !heap_size > 0 then sift_down 0 heap_points.(!heap_size);
    point in
  for point = 0 to count - 1 do
    if point land 16_383 = 0 then Cancel.check_opt cancel;
    if match selected with None -> true | Some group -> Group.mem point group
    then begin distances.(point) <- 0.; enqueue_or_decrease point end
  done;
  let visits = ref 0 in
  while !heap_size > 0 do
    if !visits land 16_383 = 0 then Cancel.check_opt cancel;
    incr visits;
    let point = pop () in
    let distance = distances.(point) in
    if distance <= radius then
      for slot = reverse.point_edge_offsets.(point)
          to reverse.point_edge_offsets.(point + 1) - 1 do
        let edge = reverse.point_edges.(slot) in
        let a = reverse.edge_a.(edge) and b = reverse.edge_b.(edge) in
        let neighbor = if a = point then b else a in
        if neighbor <> point then begin
          let dx = positions.x.(neighbor) -. positions.x.(point)
          and dy = positions.y.(neighbor) -. positions.y.(point)
          and dz = positions.z.(neighbor) -. positions.z.(point) in
          let candidate = distance +. sqrt (dx*.dx +. dy*.dy +. dz*.dz) in
          if candidate <= radius && candidate < distances.(neighbor) then begin
            distances.(neighbor) <- candidate;
            enqueue_or_decrease neighbor
          end
        end
      done
  done;
  distances

let point_float_output ~operation ~name ~default geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Ok (Array.make (Geometry.point_count geometry) default)
  | Some attribute -> match Attribute.Private.storage attribute with
    | Attribute.Float values ->
        if Array.length values <> Geometry.point_count geometry then Error
            (Printf.sprintf "%s: point attribute %S length mismatch"
              operation name)
        else Ok (Array.copy values)
    | _ -> Error (Printf.sprintf "%s: point attribute %S must be float"
        operation name)

let valid_output_attribute_name = function
  | None -> true
  | Some name ->
      let name = String.trim name in
      name <> "" && name <> "P"

let distance_along_geometry_raw ?cancel ?(grain = 16_384) ?affected
    ?(falloff = Soft_linear) ?(radius = Distance_maximum)
    ?(distance_attribute = Some "distance") ?mask_attribute ~start geometry =
  let operation = "Pdk.Ops.distance_along_geometry" in
  if grain <= 0 then Error (operation ^ ": grain must be positive")
  else if not (valid_output_attribute_name distance_attribute) then Error
      (operation ^ ": distance attribute name must be non-empty and not P")
  else if not (valid_output_attribute_name mask_attribute) then Error
      (operation ^ ": mask attribute name must be non-empty and not P")
  else if distance_attribute = None && mask_attribute = None then Error
      (operation ^ ": enable at least one distance or mask output")
  else if match distance_attribute, mask_attribute with
      | Some distance, Some mask -> distance = mask
      | _ -> false then Error
      (operation ^ ": distance and mask attributes must have distinct names")
  else if match radius with
      | Distance_fixed value -> not (finite value) || value <= 0.
      | Distance_maximum -> false then Error
      (operation ^ ": fixed radius must be finite and positive")
  else
    let topology = Geometry.topology geometry in
    Result.bind (Element_selection.validate ~operation topology (Some start))
      (fun () ->
    Result.bind (Element_selection.validate ~operation topology affected)
      (fun () ->
    Result.bind (validate_finite_positions ?cancel ~grain ~operation geometry)
      (fun _positions ->
    Result.bind (Element_selection.promote ?cancel ~grain
        ~name:"__distance_start" ~destination:Group.Point start topology)
      (fun start_points ->
    let affected_result = match affected with
      | None -> Ok None
      | Some selection -> Result.map Option.some
          (Element_selection.promote ?cancel ~grain
            ~name:"__distance_affected" ~destination:Group.Point
            selection topology) in
    Result.bind affected_result (fun affected_points ->
      let traversal_radius = match radius, distance_attribute with
        | Distance_maximum, _ | Distance_fixed _, Some _ -> max_float
        | Distance_fixed value, None -> value in
      let distances = soft_edge_distances ?cancel ~radius:traversal_radius
          (Some start_points) geometry in
      let point_count = Array.length distances in
      let affected_point point = match affected_points with
        | None -> true
        | Some group -> Group.mem point group in
      let maximum = match radius with
        | Distance_fixed value -> value
        | Distance_maximum ->
            let maximum = ref 0. in
            for point = 0 to point_count - 1 do
              if point land 16_383 = 0 then Cancel.check_opt cancel;
              let distance = distances.(point) in
              if affected_point point && finite distance && distance > !maximum
              then maximum := distance
            done;
            !maximum in
      let distance_values = match distance_attribute with
        | None -> Ok None
        | Some name -> Result.map Option.some
            (point_float_output ~operation ~name ~default:(-1.) geometry) in
      Result.bind distance_values (fun distance_values ->
      let mask_values = match mask_attribute with
        | None -> Ok None
        | Some name -> Result.map Option.some
            (point_float_output ~operation ~name ~default:0. geometry) in
      Result.bind mask_values (fun mask_values ->
        if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(point_count - 1) (fun point ->
              if point land 4095 = 0 then Cancel.check_opt cancel;
              if affected_point point then begin
                let distance = distances.(point) in
                Option.iter (fun values ->
                    values.(point) <- if finite distance then distance else -1.)
                  distance_values;
                Option.iter (fun values ->
                    values.(point) <- if not (finite distance) then 0.
                      else if maximum = 0. then
                        if distance = 0. then 1. else 0.
                      else soft_transform_weight falloff distance maximum)
                  mask_values
              end);
        let attributes_result = match distance_attribute, distance_values,
            mask_attribute, mask_values with
          | Some distance_name, Some distances, Some mask_name, Some masks ->
              Result.bind (Attribute.create_owned ~owner:Attribute.Point
                  ~name:distance_name (Attribute.Float distances))
                (fun distance -> Result.map (fun mask -> [|distance; mask|])
                  (Attribute.create_owned ~owner:Attribute.Point ~name:mask_name
                    (Attribute.Float masks)))
          | Some name, Some values, None, None
          | None, None, Some name, Some values ->
              Result.map (fun attribute -> [|attribute|])
                (Attribute.create_owned ~owner:Attribute.Point ~name
                  (Attribute.Float values))
          | _ -> assert false in
        Result.bind attributes_result (fun attributes ->
          Geometry.Private.with_merged_attributes_owned attributes geometry)
      )))))))

let distance_from_geometry_raw ?cancel ?(grain = 16_384) ?affected
    ?reference_selection ?(reference_kind = Distance_reference_primitives)
    ?(falloff = Soft_linear) ?(radius = Distance_maximum)
    ?(distance_attribute = Some "distance") ?mask_attribute ~reference source =
  let operation = "Pdk.Ops.distance_from_geometry" in
  if grain <= 0 then Error (operation ^ ": grain must be positive")
  else if not (valid_output_attribute_name distance_attribute) then Error
      (operation ^ ": distance attribute name must be non-empty and not P")
  else if not (valid_output_attribute_name mask_attribute) then Error
      (operation ^ ": mask attribute name must be non-empty and not P")
  else if distance_attribute = None && mask_attribute = None then Error
      (operation ^ ": enable at least one distance or mask output")
  else if match distance_attribute, mask_attribute with
      | Some distance, Some mask -> distance = mask
      | _ -> false then Error
      (operation ^ ": distance and mask attributes must have distinct names")
  else if match radius with
      | Distance_fixed value -> not (finite value) || value <= 0.
      | Distance_maximum -> false then Error
      (operation ^ ": fixed radius must be finite and positive")
  else
    let source_topology = Geometry.topology source
    and reference_topology = Geometry.topology reference in
    Result.bind (Element_selection.validate ~operation source_topology affected)
      (fun () ->
    Result.bind (Element_selection.validate ~operation reference_topology
        reference_selection) (fun () ->
    Result.bind (validate_finite_positions ?cancel ~grain ~operation source)
      (fun _positions ->
    let affected_result = match affected with
      | None -> Ok None
      | Some selection -> Result.map Option.some
          (Element_selection.promote ?cancel ~grain
            ~name:"__distance_from_affected" ~destination:Group.Point
            selection source_topology) in
    Result.bind affected_result (fun affected_points ->
    let reference_owner = match reference_kind with
      | Distance_reference_points -> Group.Point
      | Distance_reference_primitives -> Group.Primitive in
    let reference_result = match reference_selection with
      | None -> Ok None
      | Some selection -> Result.map Option.some
          (Element_selection.promote ?cancel ~grain
            ~name:"__distance_from_reference" ~destination:reference_owner
            selection reference_topology) in
    Result.bind reference_result (fun reference_group ->
      let point_count = Geometry.point_count source in
      let distances_squared = Array.make point_count Float.infinity in
      let maximum_squared = match radius, distance_attribute with
        | Distance_maximum, _ | Distance_fixed _, Some _ -> Float.infinity
        | Distance_fixed value, None -> value *. value in
      let query_result = match reference_kind with
        | Distance_reference_points ->
            Result.bind (Spatial_index.create ?cancel ~grain
                ?points:reference_group (Geometry.positions reference)
                |> Result.map_error Error.to_string) (fun index ->
              Spatial_index.Private.nearest_distances_many_into ?cancel
                ?points:affected_points ~grain index
                ~queries:(Geometry.positions source)
                ~max_distance_squared:maximum_squared
                ~distances_squared;
              Ok ())
        | Distance_reference_primitives ->
            Result.bind (Surface_index.create ?cancel ~grain
                ?primitives:reference_group reference
                |> Result.map_error Error.to_string) (fun index ->
              Surface_index.Private.closest_distances_many_into ?cancel
                ?selection:affected_points ~grain index
                ~queries:(Geometry.positions source)
                ~max_distance_squared:maximum_squared
                ~distances_squared;
              Ok ()) in
      Result.bind query_result (fun () ->
        let affected_point point = match affected_points with
          | None -> true
          | Some group -> Group.mem point group in
        let maximum = match radius with
          | Distance_fixed value -> value
          | Distance_maximum ->
              let maximum = ref 0. in
              for point = 0 to point_count - 1 do
                if point land 16_383 = 0 then Cancel.check_opt cancel;
                let squared = distances_squared.(point) in
                if affected_point point && finite squared then begin
                  let distance = sqrt squared in
                  if distance > !maximum then maximum := distance
                end
              done;
              !maximum in
        let distance_values = match distance_attribute with
          | None -> Ok None
          | Some name -> Result.map Option.some
              (point_float_output ~operation ~name ~default:(-1.) source) in
        Result.bind distance_values (fun distance_values ->
        let mask_values = match mask_attribute with
          | None -> Ok None
          | Some name -> Result.map Option.some
              (point_float_output ~operation ~name ~default:0. source) in
        Result.bind mask_values (fun mask_values ->
          if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(point_count - 1) (fun point ->
                if point land 4095 = 0 then Cancel.check_opt cancel;
                if affected_point point then begin
                  let squared = distances_squared.(point) in
                  let distance = if finite squared then sqrt squared
                    else Float.infinity in
                  Option.iter (fun values -> values.(point) <-
                      if finite distance then distance else -1.) distance_values;
                  Option.iter (fun values -> values.(point) <-
                      if not (finite distance) then 0.
                      else if maximum = 0. then
                        if distance = 0. then 1. else 0.
                      else soft_transform_weight falloff distance maximum)
                    mask_values
                end);
          let attributes_result = match distance_attribute, distance_values,
              mask_attribute, mask_values with
            | Some distance_name, Some distances, Some mask_name, Some masks ->
                Result.bind (Attribute.create_owned ~owner:Attribute.Point
                    ~name:distance_name (Attribute.Float distances))
                  (fun distance -> Result.map (fun mask -> [|distance; mask|])
                    (Attribute.create_owned ~owner:Attribute.Point ~name:mask_name
                      (Attribute.Float masks)))
            | Some name, Some values, None, None
            | None, None, Some name, Some values ->
                Result.map (fun attribute -> [|attribute|])
                  (Attribute.create_owned ~owner:Attribute.Point ~name
                    (Attribute.Float values))
            | _ -> assert false in
          Result.bind attributes_result (fun attributes ->
            Geometry.Private.with_merged_attributes_owned attributes source)
        ))))))))

let distance_from_target_raw ?cancel ?(grain = 16_384) ?affected
    ?(projection = Distance_target_spherical) ?(origin = Vec3.zero)
    ?(direction = Vec3.unit_y) ?(metric = Distance_target_absolute)
    ?(falloff = Soft_linear) ?(radius = Distance_maximum)
    ?(distance_attribute = Some "distance") ?mask_attribute geometry =
  let operation = "Pdk.Ops.distance_from_target" in
  if grain <= 0 then Error (operation ^ ": grain must be positive")
  else if not (valid_output_attribute_name distance_attribute) then Error
      (operation ^ ": distance attribute name must be non-empty and not P")
  else if not (valid_output_attribute_name mask_attribute) then Error
      (operation ^ ": mask attribute name must be non-empty and not P")
  else if distance_attribute = None && mask_attribute = None then Error
      (operation ^ ": enable at least one distance or mask output")
  else if match distance_attribute, mask_attribute with
      | Some distance, Some mask -> distance = mask
      | _ -> false then Error
      (operation ^ ": distance and mask attributes must have distinct names")
  else if match radius with
      | Distance_fixed value -> not (finite value) || value <= 0.
      | Distance_maximum -> false then Error
      (operation ^ ": fixed radius must be finite and positive")
  else if not (finite origin.Vec3.x && finite origin.y && finite origin.z) then
    Error (operation ^ ": origin must be finite")
  else if metric = Distance_target_signed
      && projection <> Distance_target_planar then Error
    (operation ^ ": signed distance is only defined for planar projection")
  else
    let needs_direction = projection <> Distance_target_spherical in
    let direction_squared = direction.Vec3.x *. direction.x
        +. direction.y *. direction.y +. direction.z *. direction.z in
    if needs_direction && (not (finite direction.x && finite direction.y
        && finite direction.z) || not (finite direction_squared)
        || direction_squared <= 0.) then Error
      (operation ^ ": cylindrical and planar direction must be finite and non-zero")
    else
      let topology = Geometry.topology geometry in
      Result.bind (Element_selection.validate ~operation topology affected)
        (fun () ->
      Result.bind (validate_finite_positions ?cancel ~grain ~operation geometry)
        (fun positions ->
      let affected_result = match affected with
        | None -> Ok None
        | Some selection -> Result.map Option.some
            (Element_selection.promote ?cancel ~grain
              ~name:"__distance_target_affected" ~destination:Group.Point
              selection topology) in
      Result.bind affected_result (fun affected_points ->
        let point_count = Geometry.point_count geometry in
        let distance_values = match distance_attribute with
          | None -> Ok None
          | Some name -> Result.map Option.some
              (point_float_output ~operation ~name ~default:(-1.) geometry) in
        Result.bind distance_values (fun distance_values ->
        let mask_values = match mask_attribute with
          | None -> Ok None
          | Some name -> Result.map Option.some
              (point_float_output ~operation ~name ~default:0. geometry) in
        Result.bind mask_values (fun mask_values ->
          let affected_point point = match affected_points with
            | None -> true
            | Some group -> Group.mem point group in
          let inverse_direction_length = if needs_direction then
              1. /. sqrt direction_squared else 0. in
          let nx = direction.x *. inverse_direction_length
          and ny = direction.y *. inverse_direction_length
          and nz = direction.z *. inverse_direction_length
          and ox = origin.x and oy = origin.y and oz = origin.z in
          let raw_distance point =
            let dx = positions.x.(point) -. ox
            and dy = positions.y.(point) -. oy
            and dz = positions.z.(point) -. oz in
            match projection with
            | Distance_target_spherical -> sqrt (dx*.dx +. dy*.dy +. dz*.dz)
            | Distance_target_cylindrical ->
                let axial = dx*.nx +. dy*.ny +. dz*.nz in
                sqrt (max 0. (dx*.dx +. dy*.dy +. dz*.dz -. axial*.axial))
            | Distance_target_planar ->
                let signed = dx*.nx +. dy*.ny +. dz*.nz in
                if metric = Distance_target_signed then signed
                else abs_float signed in
          let maximum_scratch = match radius, mask_values, distance_values with
            | Distance_maximum, Some _, None -> Some (Array.make point_count 0.)
            | _ -> None in
          if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(point_count - 1) (fun point ->
                if point land 4095 = 0 then Cancel.check_opt cancel;
                if affected_point point then begin
                  let raw = raw_distance point in
                  Option.iter (fun values -> values.(point) <- raw)
                    distance_values;
                  Option.iter (fun values -> values.(point) <- raw)
                    maximum_scratch;
                  match radius, mask_values with
                  | Distance_fixed radius, Some values ->
                      values.(point) <- soft_transform_weight falloff
                          (abs_float raw) radius
                  | _ -> ()
                end);
          (match radius, mask_values with
           | Distance_maximum, Some masks ->
               let raw_values = match distance_values, maximum_scratch with
                 | Some values, _ | None, Some values -> values
                 | None, None -> assert false in
               let maximum = ref 0. in
               for point = 0 to point_count - 1 do
                 if point land 16_383 = 0 then Cancel.check_opt cancel;
                 if affected_point point then begin
                   let value = abs_float raw_values.(point) in
                   if value > !maximum then maximum := value
                 end
               done;
               if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                   ~finish:(point_count - 1) (fun point ->
                     if point land 4095 = 0 then Cancel.check_opt cancel;
                     if affected_point point then
                       let value = abs_float raw_values.(point) in
                       masks.(point) <- if !maximum = 0. then 1.
                         else soft_transform_weight falloff value !maximum)
           | _ -> ());
          let attributes_result = match distance_attribute, distance_values,
              mask_attribute, mask_values with
            | Some distance_name, Some distances, Some mask_name, Some masks ->
                Result.bind (Attribute.create_owned ~owner:Attribute.Point
                    ~name:distance_name (Attribute.Float distances))
                  (fun distance -> Result.map (fun mask -> [|distance; mask|])
                    (Attribute.create_owned ~owner:Attribute.Point ~name:mask_name
                      (Attribute.Float masks)))
            | Some name, Some values, None, None
            | None, None, Some name, Some values ->
                Result.map (fun attribute -> [|attribute|])
                  (Attribute.create_owned ~owner:Attribute.Point ~name
                    (Attribute.Float values))
            | _ -> assert false in
          Result.bind attributes_result (fun attributes ->
            Geometry.Private.with_merged_attributes_owned attributes geometry)
        )))))

let soft_attribute_weights ?cancel ~grain ~radius ~falloff ~apply_rolloff
    selected name geometry =
  if String.trim name = "" then
    Error "Pdk.Ops.soft_transform: empty distance attribute name"
  else match Geometry.find_attribute ~owner:Attribute.Point name geometry with
    | None -> Error (Printf.sprintf
        "Pdk.Ops.soft_transform: missing point distance attribute %S" name)
    | Some attribute -> match Attribute.Private.storage attribute with
      | Attribute.Float values ->
          let count = Array.length values in
          let weights = Array.make count 0.
          and first_invalid = Atomic.make max_int in
          if count <> Geometry.point_count geometry then Error
              "Pdk.Ops.soft_transform: distance attribute length mismatch"
          else begin
            if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                ~finish:(count - 1) (fun point ->
                  if point land 4095 = 0 then Cancel.check_opt cancel;
                  let value = values.(point) in
                  if not (finite value) then begin
                    let rec lower observed =
                      if point < observed && not (Atomic.compare_and_set
                          first_invalid observed point)
                      then lower (Atomic.get first_invalid) in
                    lower (Atomic.get first_invalid)
                  end else if match selected with None -> true
                      | Some group -> Group.mem point group then
                    weights.(point) <- if apply_rolloff then
                        soft_transform_weight falloff value radius else value);
            let invalid = Atomic.get first_invalid in
            if invalid = max_int then Ok weights else Error (Printf.sprintf
              "Pdk.Ops.soft_transform: distance attribute %S element %d is non-finite"
              name invalid)
          end
      | _ -> Error (Printf.sprintf
          "Pdk.Ops.soft_transform: point distance attribute %S must be float" name)

let soft_transform_raw ?cancel ?(grain = 16_384) ?selection
    ?(metric = Soft_radius) ?(falloff = Soft_cubic) ?(radius = 1.)
    ?falloff_attribute ?(recompute_normals = true) matrix geometry =
  if grain <= 0 then Error "Pdk.Ops.soft_transform: grain must be positive"
  else if not (finite radius) || radius < 0. then
    Error "Pdk.Ops.soft_transform: radius must be finite and non-negative"
  else if not (transform_matrix_finite matrix) then
    Error "Pdk.Ops.soft_transform: matrix must be finite"
  else if (match falloff_attribute with
      | Some name -> String.trim name = "" | None -> false) then
    Error "Pdk.Ops.soft_transform: empty falloff attribute name"
  else if (match metric with Soft_radius | Soft_edge -> radius <= 0.
      | Soft_attribute { apply_rolloff = true; _ } -> radius <= 0.
      | Soft_attribute { apply_rolloff = false; _ } -> false) then
    Error "Pdk.Ops.soft_transform: rolloff radius must be positive"
  else Result.bind (Element_selection.validate ~operation:"Pdk.Ops.soft_transform"
      (Geometry.topology geometry) selection) (fun () ->
    Result.bind (validate_finite_positions ?cancel ~grain
        ~operation:"Pdk.Ops.soft_transform" geometry)
      (fun positions ->
      let selected_result = match selection with
        | None -> Ok None
        | Some selection -> Result.map Option.some
            (Element_selection.promote ?cancel ~grain ~destination:Group.Point
              selection (Geometry.topology geometry)) in
      Result.bind selected_result (fun selected ->
        let all_selected = match selected with
          | None -> true
          | Some group -> Group.cardinality group = Geometry.point_count geometry in
        let weights_result = match metric with
          | (Soft_radius | Soft_edge) when all_selected ->
              Ok (Array.make (Geometry.point_count geometry) 1.)
          | Soft_radius -> soft_radius_weights ?cancel ~grain ~radius ~falloff
              selected geometry
          | Soft_edge ->
              let distances = soft_edge_distances ?cancel ~radius selected geometry in
              let count = Array.length distances in
              let weights = Array.make count 0. in
              if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                  ~finish:(count - 1) (fun point ->
                    if point land 4095 = 0 then Cancel.check_opt cancel;
                    weights.(point) <- soft_transform_weight falloff
                        distances.(point) radius);
              Ok weights
          | Soft_attribute { attribute; apply_rolloff } ->
              soft_attribute_weights ?cancel ~grain ~radius ~falloff
                ~apply_rolloff selected attribute geometry in
        Result.bind weights_result (fun weights ->
          let count = Array.length weights and changed = Atomic.make false in
          let moves_positions = not (Mat4.nearly_equal matrix Mat4.identity ~eps:0.) in
          let x = Array.copy positions.x and y = Array.copy positions.y
          and z = Array.copy positions.z in
          let (m00,m01,m02,m03), (m10,m11,m12,m13),
              (m20,m21,m22,m23), (m30,m31,m32,m33) = Mat4.to_rows matrix in
          if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(count - 1) (fun point ->
                if point land 4095 = 0 then Cancel.check_opt cancel;
                let weight = weights.(point) in
                if moves_positions && weight <> 0. then begin
                  Atomic.set changed true;
                  let vx = positions.x.(point) and vy = positions.y.(point)
                  and vz = positions.z.(point) in
                  let ox = m00*.vx +. m01*.vy +. m02*.vz +. m03
                  and oy = m10*.vx +. m11*.vy +. m12*.vz +. m13
                  and oz = m20*.vx +. m21*.vy +. m22*.vz +. m23
                  and ow = m30*.vx +. m31*.vy +. m32*.vz +. m33 in
                  let tx, ty, tz = if abs_float ow <= 1e-12
                    then ox, oy, oz else ox /. ow, oy /. ow, oz /. ow in
                  x.(point) <- vx +. weight *. (tx -. vx);
                  y.(point) <- vy +. weight *. (ty -. vy);
                  z.(point) <- vz +. weight *. (tz -. vz)
                end);
          let positioned = if Atomic.get changed then
              Geometry.with_positions
                (Packed.Float3.Private.of_owned_exn ~x ~y ~z) geometry
            else Ok geometry in
          Result.bind positioned (fun output ->
            let output = if not (Atomic.get changed) then output
              else if recompute_normals then output
              else output |> Geometry.without_attribute ~owner:Attribute.Point "N"
                |> Geometry.without_attribute ~owner:Attribute.Vertex "N" in
            let normal_owners = if not (Atomic.get changed) || not recompute_normals
              then [] else List.filter (fun owner ->
                Geometry.find_attribute ~owner "N" geometry <> None)
                [Attribute.Point; Attribute.Vertex] in
            let output = List.fold_left (fun result owner -> Result.bind result
                (fun output -> Normal_ops.run ?cancel ~grain ~owner output))
                (Ok output) normal_owners in
            Result.bind output (fun output -> match falloff_attribute with
              | None -> Ok output
              | Some name -> Result.bind (Attribute.create_owned
                  ~owner:Attribute.Point ~name (Attribute.Float weights))
                  (fun attribute -> Geometry.with_attribute attribute output)))))))

let transform ?grain matrix geometry =
  let transformed = Kernel.transform ?grain matrix geometry in
  match Mat4.inverse matrix with
  | None -> transformed
      |> Geometry.without_attribute ~owner:Attribute.Point "N"
      |> Geometry.without_attribute ~owner:Attribute.Vertex "N"
  | Some inverse ->
      let normal_matrix = Mat4.transpose inverse in
      List.fold_left (fun output owner ->
        match Geometry.find_attribute ~owner "N" geometry with
        | None -> output
        | Some attribute ->
            (match Attribute.get (Attribute.normal ~owner) attribute with
             | None -> output
             | Some normals ->
                 let normals = normalized_direction ?grain normal_matrix normals in
                 let attribute = Attribute.create_key_owned
                     (Attribute.normal ~owner) normals |> get_ok in
                 Geometry.with_attribute attribute output |> get_ok))
        transformed [Attribute.Point; Attribute.Vertex]

let finite_vec3 value = finite value.Vec3.x && finite value.y && finite value.z

type bound_shape =
  | Bound_box of { divisions : int * int * int }
  | Bound_sphere of { segments : int; rings : int; minimum_radius : float }

type bound_face = {
  u_divisions : int;
  v_divisions : int;
  origin_x : float; origin_y : float; origin_z : float;
  u_x : float; u_y : float; u_z : float;
  v_x : float; v_y : float; v_z : float;
  normal_x : float; normal_y : float; normal_z : float;
}

let selected_bounds ?cancel ~grain ~operation selection geometry =
  let topology = Geometry.topology geometry in
  match Deform.validate_selection topology selection with
  | Error message -> Error ("Pdk.Ops." ^ operation ^ ": " ^ message)
  | Ok () ->
      let point_count = Geometry.point_count geometry in
      let needs_index = Deform.selection_needs_index selection in
      let index = if needs_index then
          Some (Topology_index.create ?cancel topology) else None in
      let parallel_work = point_count >= 2_000_000
        || needs_index
           && Topology.vertex_count topology >= max 0 (2_000_000 - point_count) in
      let range_grain = if parallel_work then grain else max 1 point_count in
      let range_count = if point_count = 0 then 0
        else (point_count + range_grain - 1) / range_grain in
      let min_x = Array.make range_count Float.infinity
      and min_y = Array.make range_count Float.infinity
      and min_z = Array.make range_count Float.infinity
      and max_x = Array.make range_count Float.neg_infinity
      and max_y = Array.make range_count Float.neg_infinity
      and max_z = Array.make range_count Float.neg_infinity
      and found = Array.make range_count false
      and errors = Array.make range_count (-1) in
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      if range_count > 0 then Parallel.for_ ~chunk_size:1 ~start:0
          ~finish:(range_count - 1) (fun range ->
        let first = range * range_grain
        and last = min point_count ((range + 1) * range_grain) in
        for point = first to last - 1 do
          if point land 4095 = 0 then Cancel.check_opt cancel;
          if Deform.point_selected selection index point then begin
            let x = positions.x.(point) and y = positions.y.(point)
            and z = positions.z.(point) in
            if not (finite x && finite y && finite z) then
              errors.(range) <- if errors.(range) < 0 then point
                else errors.(range)
            else begin
              found.(range) <- true;
              min_x.(range) <- Float.min min_x.(range) x;
              min_y.(range) <- Float.min min_y.(range) y;
              min_z.(range) <- Float.min min_z.(range) z;
              max_x.(range) <- Float.max max_x.(range) x;
              max_y.(range) <- Float.max max_y.(range) y;
              max_z.(range) <- Float.max max_z.(range) z
            end
          end
        done);
      let invalid = Array.fold_left (fun first point ->
          if point < 0 then first else if first < 0 then point
          else min first point) (-1) errors in
      if invalid >= 0 then Error (Printf.sprintf
          "Pdk.Ops.%s: selected point %d has a non-finite position"
          operation invalid)
      else begin
        let xmin = ref Float.infinity and ymin = ref Float.infinity
        and zmin = ref Float.infinity and xmax = ref Float.neg_infinity
        and ymax = ref Float.neg_infinity and zmax = ref Float.neg_infinity
        and any = ref false in
        for range = 0 to range_count - 1 do
          if found.(range) then begin
            any := true;
            xmin := Float.min !xmin min_x.(range);
            ymin := Float.min !ymin min_y.(range);
            zmin := Float.min !zmin min_z.(range);
            xmax := Float.max !xmax max_x.(range);
            ymax := Float.max !ymax max_y.(range);
            zmax := Float.max !zmax max_z.(range)
          end
        done;
        if not !any then Error
            ("Pdk.Ops." ^ operation ^ ": selection contains no points")
        else
          let sx = !xmax -. !xmin and sy = !ymax -. !ymin
          and sz = !zmax -. !zmin in
          let cx = !xmin +. (sx *. 0.5) and cy = !ymin +. (sy *. 0.5)
          and cz = !zmin +. (sz *. 0.5) in
          if not (finite sx && finite sy && finite sz && finite cx && finite cy
              && finite cz) then Error
              ("Pdk.Ops." ^ operation ^ ": selected bounds overflow")
          else Ok Analysis.{
            min = Vec3.create !xmin !ymin !zmin;
            max = Vec3.create !xmax !ymax !zmax;
            center = Vec3.create cx cy cz;
            size = Vec3.create sx sy sz;
          }
      end

let divided_box ?cancel ~minimum ~maximum ~divisions () =
  let dx, dy, dz = divisions in
  let sx = maximum.Vec3.x -. minimum.Vec3.x
  and sy = maximum.y -. minimum.y and sz = maximum.z -. minimum.z in
  let faces = [|
    { u_divisions = dy; v_divisions = dz;
      origin_x = maximum.x; origin_y = minimum.y; origin_z = minimum.z;
      u_x = 0.; u_y = sy; u_z = 0.; v_x = 0.; v_y = 0.; v_z = sz;
      normal_x = 1.; normal_y = 0.; normal_z = 0. };
    { u_divisions = dz; v_divisions = dy;
      origin_x = minimum.x; origin_y = minimum.y; origin_z = minimum.z;
      u_x = 0.; u_y = 0.; u_z = sz; v_x = 0.; v_y = sy; v_z = 0.;
      normal_x = -1.; normal_y = 0.; normal_z = 0. };
    { u_divisions = dz; v_divisions = dx;
      origin_x = minimum.x; origin_y = maximum.y; origin_z = minimum.z;
      u_x = 0.; u_y = 0.; u_z = sz; v_x = sx; v_y = 0.; v_z = 0.;
      normal_x = 0.; normal_y = 1.; normal_z = 0. };
    { u_divisions = dx; v_divisions = dz;
      origin_x = minimum.x; origin_y = minimum.y; origin_z = minimum.z;
      u_x = sx; u_y = 0.; u_z = 0.; v_x = 0.; v_y = 0.; v_z = sz;
      normal_x = 0.; normal_y = -1.; normal_z = 0. };
    { u_divisions = dx; v_divisions = dy;
      origin_x = minimum.x; origin_y = minimum.y; origin_z = maximum.z;
      u_x = sx; u_y = 0.; u_z = 0.; v_x = 0.; v_y = sy; v_z = 0.;
      normal_x = 0.; normal_y = 0.; normal_z = 1. };
    { u_divisions = dy; v_divisions = dx;
      origin_x = minimum.x; origin_y = minimum.y; origin_z = minimum.z;
      u_x = 0.; u_y = sy; u_z = 0.; v_x = sx; v_y = 0.; v_z = 0.;
      normal_x = 0.; normal_y = 0.; normal_z = -1. };
  |] in
  let point_offsets = Array.make 7 0 and primitive_offsets_by_face = Array.make 7 0 in
  let overflow = ref false in
  let point_limit = Sys.max_array_length
  and primitive_limit = (Sys.max_array_length - 1) / 3 in
  for face = 0 to 5 do
    let value = faces.(face) in
    let points = if value.u_divisions >= point_limit
        || value.v_divisions >= point_limit
        || value.u_divisions + 1 > point_limit / (value.v_divisions + 1)
      then None else Some ((value.u_divisions + 1) * (value.v_divisions + 1))
    and primitives = if value.u_divisions > primitive_limit / 2
        || value.v_divisions > primitive_limit / (2 * value.u_divisions)
      then None else Some (2 * value.u_divisions * value.v_divisions) in
    match points, primitives with
    | Some points, Some primitives
      when points <= point_limit - point_offsets.(face)
        && primitives <= primitive_limit - primitive_offsets_by_face.(face) ->
      point_offsets.(face + 1) <- point_offsets.(face) + points;
      primitive_offsets_by_face.(face + 1) <-
        primitive_offsets_by_face.(face) + primitives
    | _ -> overflow := true
  done;
  if !overflow then Error "Pdk.Ops.bound: divided box output is too large"
  else begin
    let point_count = point_offsets.(6)
    and primitive_count = primitive_offsets_by_face.(6) in
    let px = Array.make point_count 0. and py = Array.make point_count 0.
    and pz = Array.make point_count 0. and nx = Array.make point_count 0.
    and ny = Array.make point_count 0. and nz = Array.make point_count 0.
    and vertex_points = Array.make (primitive_count * 3) 0 in
    let fill_face face_index =
      Cancel.check_opt cancel;
      let face = faces.(face_index) and first_point = point_offsets.(face_index)
      and first_primitive = primitive_offsets_by_face.(face_index) in
      let width = face.v_divisions + 1 in
      for u = 0 to face.u_divisions do
        if u land 255 = 0 then Cancel.check_opt cancel;
        let fu = float_of_int u /. float_of_int face.u_divisions in
        for v = 0 to face.v_divisions do
          let fv = float_of_int v /. float_of_int face.v_divisions in
          let point = first_point + (u * width) + v in
          px.(point) <- face.origin_x +. (fu *. face.u_x) +. (fv *. face.v_x);
          py.(point) <- face.origin_y +. (fu *. face.u_y) +. (fv *. face.v_y);
          pz.(point) <- face.origin_z +. (fu *. face.u_z) +. (fv *. face.v_z);
          nx.(point) <- face.normal_x; ny.(point) <- face.normal_y;
          nz.(point) <- face.normal_z
        done
      done;
      for u = 0 to face.u_divisions - 1 do
        if u land 255 = 0 then Cancel.check_opt cancel;
        for v = 0 to face.v_divisions - 1 do
          let a = first_point + (u * width) + v in
          let b = a + width and d = a + 1 and c = a + width + 1 in
          let primitive = first_primitive
              + (2 * ((u * face.v_divisions) + v)) in
          let at = primitive * 3 in
          vertex_points.(at) <- a; vertex_points.(at + 1) <- b;
          vertex_points.(at + 2) <- c;
          vertex_points.(at + 3) <- a; vertex_points.(at + 4) <- c;
          vertex_points.(at + 5) <- d
        done
      done in
    if point_count + primitive_count < 500_000 then
      for face = 0 to 5 do fill_face face done
    else Parallel.for_ ~chunk_size:1 ~start:0 ~finish:5 fill_face;
    let primitive_offsets = Array.make (primitive_count + 1) 0
    and primitive_kinds = Bytes.make primitive_count '\000' in
    let fill_offset primitive = primitive_offsets.(primitive) <- primitive * 3 in
    if primitive_count < 500_000 then
      for primitive = 0 to primitive_count do fill_offset primitive done
    else Parallel.for_ ~chunk_size:16_384 ~start:0 ~finish:primitive_count
        fill_offset;
    let topology = Topology.Private.create_validated_owned ~point_count
        ~vertex_points ~primitive_offsets ~primitive_kinds in
    let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
    let normals = Packed.Float3.Private.of_owned_exn ~x:nx ~y:ny ~z:nz in
    let normal = Attribute.create_key_owned (Attribute.normal ~owner:Attribute.Point)
        normals |> get_ok in
    Geometry.create ~positions ~topology ~attributes:[normal] ()
  end

let bound ?cancel ?(grain = 16_384) ?selection
    ?(shape = Bound_box { divisions = 1, 1, 1 })
    ?(lower_padding = Vec3.zero) ?(upper_padding = Vec3.zero) ?bounds_group
    ?center_attribute ?radii_attribute geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.bound: grain must be positive";
  let valid_padding value = finite_vec3 value && value.Vec3.x >= 0.
      && value.y >= 0. && value.z >= 0. in
  let output_names = List.filter_map Fun.id [center_attribute; radii_attribute] in
  if not (valid_padding lower_padding && valid_padding upper_padding) then
    Error "Pdk.Ops.bound: lower and upper padding must be finite and non-negative"
  else if List.exists (fun name -> String.trim name = "" || String.equal name "P")
      output_names then Error "Pdk.Ops.bound: output attribute names must be non-empty and cannot be P"
  else if List.length output_names <> List.length (List.sort_uniq String.compare output_names)
  then Error "Pdk.Ops.bound: output attribute names must be distinct"
  else if match bounds_group with Some name -> String.trim name = "" | None -> false
  then Error "Pdk.Ops.bound: bounds group name must not be empty"
  else
    let shape_valid = match shape with
      | Bound_box { divisions = dx, dy, dz } -> dx > 0 && dy > 0 && dz > 0
      | Bound_sphere { segments; rings; minimum_radius } ->
          segments >= 3 && rings >= 2 && finite minimum_radius
          && minimum_radius >= 0. in
    if not shape_valid then Error
        "Pdk.Ops.bound: box divisions must be positive; sphere segments/rings/minimum radius are invalid"
    else Result.bind
        (selected_bounds ?cancel ~grain ~operation:"bound" selection geometry)
      (fun source_bounds ->
        let create, center, radii = match shape with
          | Bound_box { divisions } ->
              let minimum = Vec3.create
                  (source_bounds.min.x -. lower_padding.x)
                  (source_bounds.min.y -. lower_padding.y)
                  (source_bounds.min.z -. lower_padding.z)
              and maximum = Vec3.create
                  (source_bounds.max.x +. upper_padding.x)
                  (source_bounds.max.y +. upper_padding.y)
                  (source_bounds.max.z +. upper_padding.z) in
              let size = Vec3.sub maximum minimum in
              let center = Vec3.add minimum (Vec3.scale size 0.5)
              and radii = Vec3.scale size 0.5 in
              (fun () -> if not (finite_vec3 size && finite_vec3 center)
                    || size.x <= 0. || size.y <= 0. || size.z <= 0. then
                    Error "Pdk.Ops.bound: box output must have finite positive extent on every axis"
                  else divided_box ?cancel ~minimum ~maximum ~divisions ()),
              center, radii
          | Bound_sphere { segments; rings; minimum_radius } ->
              let base_radius = Float.hypot (source_bounds.size.x *. 0.5)
                  (Float.hypot (source_bounds.size.y *. 0.5)
                    (source_bounds.size.z *. 0.5)) in
              let center = Vec3.create
                  (source_bounds.center.x
                    +. ((upper_padding.x -. lower_padding.x) *. 0.5))
                  (source_bounds.center.y
                    +. ((upper_padding.y -. lower_padding.y) *. 0.5))
                  (source_bounds.center.z
                    +. ((upper_padding.z -. lower_padding.z) *. 0.5)) in
              let radius lower upper = Float.max minimum_radius
                  (base_radius +. ((lower +. upper) *. 0.5)) in
              let radii = Vec3.create
                  (radius lower_padding.x upper_padding.x)
                  (radius lower_padding.y upper_padding.y)
                  (radius lower_padding.z upper_padding.z) in
              (fun () -> if not (finite base_radius && finite_vec3 center
                    && finite_vec3 radii) || radii.x <= 0. || radii.y <= 0.
                    || radii.z <= 0. then
                    Error "Pdk.Ops.bound: sphere output radii must be finite and positive"
                  else Result.map (transform ~grain
                      (Mat4.mul (Mat4.translation center) (Mat4.scaling radii)))
                      (uv_sphere ?cancel ~grain ~segments ~rings ~radius:1. ())),
              center, radii in
        Result.bind (create ()) (fun output ->
          let detail_float3 name value output =
            let values = Packed.Float3.Private.of_owned_exn ~x:[|value.Vec3.x|]
                ~y:[|value.y|] ~z:[|value.z|] in
            let attribute = Attribute.create_owned ~name ~owner:Attribute.Detail
                (Attribute.Float3 values) |> get_ok in
            Geometry.with_attribute attribute output |> get_ok in
          let output = match center_attribute with
            | None -> output | Some name -> detail_float3 name center output in
          let output = match radii_attribute with
            | None -> output | Some name -> detail_float3 name radii output in
          let output = match bounds_group with
            | None -> output
            | Some name ->
                let group = Group.init ~grain ~owner:Group.Primitive ~name
                    (Geometry.primitive_count output) (fun _ -> true) in
                Geometry.with_group group output |> get_ok in
          Ok output))

let bounding_box ?cancel ?grain ?(padding = Vec3.zero) geometry =
  bound ?cancel ?grain ~shape:(Bound_box { divisions = 1, 1, 1 })
    ~lower_padding:padding ~upper_padding:padding geometry

type match_size_fit =
  | Translate_only
  | Stretch
  | Contain
  | Cover
  | Match_x
  | Match_y
  | Match_z
  | Match_perimeter
  | Match_area
  | Match_volume

let match_axis ?grain ~from ~into geometry =
  if not (finite_vec3 from && finite_vec3 into)
     || Vec3.length_sq from <= 1e-30 || Vec3.length_sq into <= 1e-30 then
    Error "Pdk.Ops.match_axis: vectors must be finite and non-zero"
  else
    let from = Vec3.normalize from and into = Vec3.normalize into in
    let dot = max (-1.) (min 1. (Vec3.dot from into)) in
    let cross = Vec3.cross from into in
    let cross_length = Vec3.length cross in
    let matrix = if cross_length > 1e-15 then
        Mat4.rotation ~axis:(Vec3.scale cross (1. /. cross_length))
          (atan2 cross_length dot)
      else if dot >= 0. then Mat4.identity
      else
        let basis = if abs_float from.x <= abs_float from.y
            && abs_float from.x <= abs_float from.z then Vec3.unit_x
          else if abs_float from.y <= abs_float from.z then Vec3.unit_y
          else Vec3.unit_z in
        Mat4.rotation ~axis:(Vec3.normalize (Vec3.cross from basis)) Float.pi in
    Ok (transform ?grain matrix geometry)

let match_size_metric_primitives operation selection = match selection with
  | None -> Ok None
  | Some (Selected_primitives group) -> Ok (Some group)
  | Some _ -> Error (Printf.sprintf
      "Pdk.Ops.match_size: %s must be primitive-owned for metric fitting"
      operation)

let match_size_measure ?cancel ~grain fit selection geometry =
  Result.bind (match_size_metric_primitives "bounds selection" selection)
    (fun primitives ->
  let measured = match fit with
    | Match_perimeter -> Analysis.perimeter ?cancel ~grain ?primitives geometry
    | Match_area -> Analysis.surface_area ?cancel ~grain ?primitives geometry
    | Match_volume -> Analysis.signed_volume ?cancel ~grain ?primitives geometry
    | Translate_only | Stretch | Contain | Cover | Match_x | Match_y | Match_z ->
        assert false in
  Result.bind measured (fun value ->
    let value = abs_float value in
    if not (finite value) then Error
        "Pdk.Ops.match_size: metric measurement is not finite"
    else if value <= 1e-20 then Error
        "Pdk.Ops.match_size: metric fitting requires a positive measurement"
    else Ok value))

let match_size_bounds ~center ~size =
  if not (finite_vec3 center && finite_vec3 size)
     || size.x < 0. || size.y < 0. || size.z < 0. then
    Error "Pdk.Ops.match_size: target center must be finite and target size finite and non-negative"
  else
    let hx = size.x *. 0.5 and hy = size.y *. 0.5 and hz = size.z *. 0.5 in
    let minimum = Vec3.create (center.x -. hx) (center.y -. hy) (center.z -. hz)
    and maximum = Vec3.create (center.x +. hx) (center.y +. hy) (center.z +. hz) in
    if not (finite_vec3 minimum && finite_vec3 maximum) then Error
        "Pdk.Ops.match_size: numeric target bounds overflow"
    else Ok Analysis.{ min = minimum; max = maximum; center; size }

let match_size_transform ?cancel ~grain ?selection ~scale ~translation geometry =
  let topology = Geometry.topology geometry in
  Result.bind (Deform.validate_selection topology selection) (fun () ->
  let point_count = Geometry.point_count geometry in
  let selection_empty = match selection with
    | None -> point_count = 0
    | Some (Selected_points group | Selected_vertices group
        | Selected_primitives group) -> Group.cardinality group = 0
    | Some (Selected_edges group) -> Edge_group.cardinality group = 0 in
  if scale.Vec3.x = 1. && scale.y = 1. && scale.z = 1.
     && translation.Vec3.x = 0. && translation.y = 0. && translation.z = 0.
     || selection_empty then Ok geometry
  else begin
    let topology_view = Topology.Private.view topology in
    let needs_index = Deform.selection_needs_index selection in
    let index = if needs_index then Some (Topology_index.create ?cancel topology)
      else None in
    let selected_mask = if not needs_index then None else begin
        let mask = Bytes.make point_count '\000' in
        if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(point_count - 1) (fun point ->
          if point land 4095 = 0 then Cancel.check_opt cancel;
          if Deform.point_selected selection index point then
            Bytes.unsafe_set mask point '\001');
        Some mask
      end in
    let[@inline] selected point = match selected_mask with
      | Some mask -> Bytes.unsafe_get mask point <> '\000'
      | None -> Deform.point_selected selection index point in
    let source = Packed.Float3.Private.view (Geometry.positions geometry) in
    let x = Array.copy source.x and y = Array.copy source.y
    and z = Array.copy source.z in
    let range_count = if point_count = 0 then 0
      else (point_count + grain - 1) / grain in
    let errors = Array.make range_count (-1) in
    if range_count > 0 then Parallel.for_ ~chunk_size:1 ~start:0
        ~finish:(range_count - 1) (fun range ->
      let first = range * grain and last = min point_count ((range + 1) * grain) in
      for point = first to last - 1 do
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if selected point then begin
          let ox = (scale.x *. source.x.(point)) +. translation.x
          and oy = (scale.y *. source.y.(point)) +. translation.y
          and oz = (scale.z *. source.z.(point)) +. translation.z in
          if finite ox && finite oy && finite oz then begin
            x.(point) <- ox; y.(point) <- oy; z.(point) <- oz
          end else if errors.(range) < 0 then errors.(range) <- point
        end
      done);
    let invalid = Array.fold_left (fun first point ->
        if point < 0 then first else if first < 0 then point else min first point)
        (-1) errors in
    if invalid >= 0 then Error (Printf.sprintf
        "Pdk.Ops.match_size: transformed point %d is not finite" invalid)
    else
      let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
      let output = Geometry.with_positions positions geometry |> get_ok in
      if scale.x = 1. && scale.y = 1. && scale.z = 1. then Ok output
      else if abs_float scale.x <= 1e-20 || abs_float scale.y <= 1e-20
          || abs_float scale.z <= 1e-20 then
        Ok (output
          |> Geometry.without_attribute ~owner:Attribute.Point "N"
          |> Geometry.without_attribute ~owner:Attribute.Vertex "N")
      else
        let transform_normals owner output =
          match Geometry.find_attribute ~owner "N" geometry with
          | None -> Ok output
          | Some attribute ->
              (match Attribute.get (Attribute.normal ~owner) attribute with
               | None -> Ok output
               | Some packed ->
                   let source = Packed.Float3.Private.view packed in
                   let count = Array.length source.x in
                   let x = Array.copy source.x and y = Array.copy source.y
                   and z = Array.copy source.z in
                   let range_count = if count = 0 then 0
                     else (count + grain - 1) / grain in
                   let errors = Array.make range_count (-1) in
                   if range_count > 0 then Parallel.for_ ~chunk_size:1 ~start:0
                       ~finish:(range_count - 1) (fun range ->
                     let first = range * grain
                     and last = min count ((range + 1) * grain) in
                     for element = first to last - 1 do
                       if element land 4095 = 0 then Cancel.check_opt cancel;
                       let point = match owner with
                         | Attribute.Point -> element
                         | Attribute.Vertex ->
                             topology_view.vertex_points.(element)
                         | Attribute.Primitive | Attribute.Detail -> assert false in
                       if selected point then begin
                         let ox = source.x.(element) /. scale.x
                         and oy = source.y.(element) /. scale.y
                         and oz = source.z.(element) /. scale.z in
                         let length = sqrt ((ox *. ox) +. (oy *. oy) +. (oz *. oz)) in
                         if finite length then begin
                           if length > 1e-20 then begin
                             x.(element) <- ox /. length;
                             y.(element) <- oy /. length;
                             z.(element) <- oz /. length
                           end else begin
                             x.(element) <- 0.; y.(element) <- 0.; z.(element) <- 0.
                           end
                         end else if errors.(range) < 0 then
                           errors.(range) <- element
                       end
                     done);
                   let invalid = Array.fold_left (fun first element ->
                       if element < 0 then first else if first < 0 then element
                       else min first element) (-1) errors in
                   if invalid >= 0 then Error (Printf.sprintf
                       "Pdk.Ops.match_size: transformed %s normal %d is not finite"
                       (match owner with Attribute.Point -> "point"
                        | Attribute.Vertex -> "vertex"
                        | Attribute.Primitive | Attribute.Detail -> assert false)
                       invalid)
                   else
                     let packed = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
                     let attribute = Attribute.create_key_owned
                         (Attribute.normal ~owner) packed |> get_ok in
                     Geometry.with_attribute attribute output) in
        Result.bind (transform_normals Attribute.Point output)
          (transform_normals Attribute.Vertex)
  end)

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

let match_size ?cancel ?(grain = 16_384) ?selection ?source_selection
    ?target_selection ?(fit = Contain) ?(translate_axes = true, true, true)
    ?(scale_axes = true, true, true) ?(justify = Vec3.zero) ?target_justify
    ?(offset = Vec3.zero) ?(scale = 1.) ?target_center ?target_size ?target
    geometry =
  let target_justify = Option.value ~default:justify target_justify in
  let tx_enabled, ty_enabled, tz_enabled = translate_axes
  and sx_enabled, sy_enabled, sz_enabled = scale_axes in
  if grain <= 0 then Error "Pdk.Ops.match_size: grain must be positive"
  else if not (finite_vec3 justify && finite_vec3 target_justify)
      || abs_float justify.x > 1. || abs_float justify.y > 1.
      || abs_float justify.z > 1. || abs_float target_justify.x > 1.
      || abs_float target_justify.y > 1. || abs_float target_justify.z > 1. then
    Error "Pdk.Ops.match_size: justification components must be finite and between -1 and 1"
  else if not (finite_vec3 offset && finite scale) || scale < 0. then
    Error "Pdk.Ops.match_size: offset must be finite and scale finite and non-negative"
  else if Option.is_some target &&
      (Option.is_some target_center || Option.is_some target_size) then
    Error "Pdk.Ops.match_size: geometry and numeric targets are mutually exclusive"
  else if Option.is_none target && Option.is_some target_selection then
    Error "Pdk.Ops.match_size: target selection requires target geometry"
  else
    Result.bind (selected_bounds ?cancel ~grain ~operation:"match_size source"
        source_selection geometry) (fun source_bounds ->
    let target_bounds_result = match target with
      | Some target -> selected_bounds ?cancel ~grain
          ~operation:"match_size target" target_selection target
      | None -> match_size_bounds
          ~center:(Option.value ~default:Vec3.zero target_center)
          ~size:(Option.value ~default:(Vec3.create 1. 1. 1.) target_size) in
    Result.bind target_bounds_result (fun target_bounds ->
    let ratio source target = if source <= 1e-20 then 1. else target /. source in
    let rx = ratio source_bounds.size.x target_bounds.size.x
    and ry = ratio source_bounds.size.y target_bounds.size.y
    and rz = ratio source_bounds.size.z target_bounds.size.z in
    let uniform choose =
      let value = ref None in
      let consider source ratio = if source > 1e-20 then
        value := Some (match !value with None -> ratio
          | Some current -> choose current ratio) in
      consider source_bounds.size.x rx;
      consider source_bounds.size.y ry;
      consider source_bounds.size.z rz;
      Option.value ~default:1. !value in
    let uniform_scale value =
      let value = value *. scale in Vec3.create value value value in
    let computed_scale = match fit with
      | Translate_only -> Ok (Vec3.create 1. 1. 1.)
      | Stretch -> Ok (Vec3.create
          (if sx_enabled then rx *. scale else 1.)
          (if sy_enabled then ry *. scale else 1.)
          (if sz_enabled then rz *. scale else 1.))
      | Contain -> Ok (uniform_scale (uniform Float.min))
      | Cover -> Ok (uniform_scale (uniform Float.max))
      | Match_x when source_bounds.size.x <= 1e-20 -> Error
          "Pdk.Ops.match_size: X-axis fitting requires non-degenerate source bounds"
      | Match_y when source_bounds.size.y <= 1e-20 -> Error
          "Pdk.Ops.match_size: Y-axis fitting requires non-degenerate source bounds"
      | Match_z when source_bounds.size.z <= 1e-20 -> Error
          "Pdk.Ops.match_size: Z-axis fitting requires non-degenerate source bounds"
      | Match_x -> Ok (uniform_scale rx)
      | Match_y -> Ok (uniform_scale ry)
      | Match_z -> Ok (uniform_scale rz)
      | Match_perimeter | Match_area | Match_volume ->
          (match target with
           | None -> Error
               "Pdk.Ops.match_size: metric fitting requires target geometry"
           | Some target ->
               Result.bind (match_size_measure ?cancel ~grain fit
                   source_selection geometry) (fun source_measure ->
               Result.map (fun target_measure ->
                 let ratio = target_measure /. source_measure in
                 let linear = match fit with
                   | Match_perimeter -> ratio
                   | Match_area -> sqrt ratio
                   | Match_volume -> ratio ** (1. /. 3.)
                   | _ -> assert false in
                 uniform_scale linear)
                 (match_size_measure ?cancel ~grain fit target_selection target))) in
    Result.bind computed_scale (fun computed_scale ->
    if not (finite_vec3 computed_scale) then Error
        "Pdk.Ops.match_size: computed scale is not finite"
    else
      let anchor (bounds : Analysis.bounds) justification = Vec3.create
          (bounds.center.x +. (justification.Vec3.x *. bounds.size.x *. 0.5))
          (bounds.center.y +. (justification.y *. bounds.size.y *. 0.5))
          (bounds.center.z +. (justification.z *. bounds.size.z *. 0.5)) in
      let source_anchor = anchor source_bounds justify
      and target_anchor = anchor target_bounds target_justify in
      let translation = Vec3.create
          (if tx_enabled then target_anchor.x +. offset.x
             -. (source_anchor.x *. computed_scale.x) else 0.)
          (if ty_enabled then target_anchor.y +. offset.y
             -. (source_anchor.y *. computed_scale.y) else 0.)
          (if tz_enabled then target_anchor.z +. offset.z
             -. (source_anchor.z *. computed_scale.z) else 0.) in
      if not (finite_vec3 translation) then Error
          "Pdk.Ops.match_size: computed translation is not finite"
      else match_size_transform ?cancel ~grain ?selection
          ~scale:computed_scale ~translation geometry)))

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
        edge_flip ?cancel ~grain ~edges ~cycles:1
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

let poly_reduce_raw = poly_reduce
let poly_reduce ?cancel ?grain ?target ?primitives ?hard_points ?hard_edges
    ?preserve_boundary ?only_original_positions ?equalize_lengths
    ?max_normal_deviation ?output_group ?recompute_point_normals geometry =
  protected "poly_reduce" "invalid_topology" (fun () ->
    poly_reduce_raw ?cancel ?grain ?target ?primitives ?hard_points ?hard_edges
      ?preserve_boundary ?only_original_positions ?equalize_lengths
      ?max_normal_deviation ?output_group ?recompute_point_normals geometry)

let edge_flip_raw = edge_flip
let edge_flip ?cancel ?grain ?edges ?cycles ?cycle_vertex_attributes
    ?recompute_point_normals geometry =
  protected "edge_flip" "invalid_topology" (fun () ->
    edge_flip_raw ?cancel ?grain ?edges ?cycles ?cycle_vertex_attributes
      ?recompute_point_normals geometry)

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

let bound_raw = bound
let bound ?cancel ?grain ?selection ?shape ?lower_padding ?upper_padding
    ?bounds_group ?center_attribute ?radii_attribute geometry =
  protected "bound" "invalid_geometry" (fun () ->
    bound_raw ?cancel ?grain ?selection ?shape ?lower_padding ?upper_padding
      ?bounds_group ?center_attribute ?radii_attribute geometry)

let bounding_box_raw = bounding_box
let bounding_box ?cancel ?grain ?padding geometry =
  protected "bounding_box" "invalid_geometry"
    (fun () -> bounding_box_raw ?cancel ?grain ?padding geometry)

let match_axis_raw = match_axis
let match_axis ?grain ~from ~into geometry =
  protected "match_axis" "invalid_axis"
    (fun () -> match_axis_raw ?grain ~from ~into geometry)

let sort = Ordering.sort_checked

let match_size_raw = match_size
let match_size ?cancel ?grain ?selection ?source_selection ?target_selection
    ?fit ?translate_axes ?scale_axes ?justify ?target_justify ?offset ?scale
    ?target_center ?target_size ?target geometry =
  protected "match_size" "invalid_geometry"
    (fun () -> match_size_raw ?cancel ?grain ?selection ?source_selection
      ?target_selection ?fit ?translate_axes ?scale_axes ?justify
      ?target_justify ?offset ?scale ?target_center ?target_size ?target geometry)

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

let compose_transform ?order ?rotation_order ?translate ?rotate ?scale ?shear
    ?uniform_scale ?pivot ?pivot_rotation ?invert () =
  detailed "compose_transform" "invalid_transform"
    (compose_transform_raw ?order ?rotation_order ?translate ?rotate ?scale
      ?shear ?uniform_scale ?pivot ?pivot_rotation ?invert ())

let transform_selected ?cancel ?grain ?selection ?preserve_normal_length
    ?recompute_normals matrix geometry =
  protected "transform_selected" "invalid_transform" (fun () ->
    transform_selected_raw ?cancel ?grain ?selection ?preserve_normal_length
      ?recompute_normals matrix geometry)

let soft_transform ?cancel ?grain ?selection ?metric ?falloff ?radius
    ?falloff_attribute ?recompute_normals matrix geometry =
  protected "soft_transform" "invalid_transform" (fun () ->
    soft_transform_raw ?cancel ?grain ?selection ?metric ?falloff ?radius
      ?falloff_attribute ?recompute_normals matrix geometry)

let distance_along_geometry ?cancel ?grain ?affected ?falloff ?radius
    ?distance_attribute ?mask_attribute ~start geometry =
  protected "distance_along_geometry" "invalid_distance" (fun () ->
    distance_along_geometry_raw ?cancel ?grain ?affected ?falloff ?radius
      ?distance_attribute ?mask_attribute ~start geometry)

let distance_from_geometry ?cancel ?grain ?affected ?reference_selection
    ?reference_kind ?falloff ?radius ?distance_attribute ?mask_attribute
    ~reference source =
  protected "distance_from_geometry" "invalid_distance" (fun () ->
    distance_from_geometry_raw ?cancel ?grain ?affected ?reference_selection
      ?reference_kind ?falloff ?radius ?distance_attribute ?mask_attribute
      ~reference source)

let distance_from_target ?cancel ?grain ?affected ?projection ?origin ?direction
    ?metric ?falloff ?radius ?distance_attribute ?mask_attribute geometry =
  protected "distance_from_target" "invalid_distance" (fun () ->
    distance_from_target_raw ?cancel ?grain ?affected ?projection ?origin
      ?direction ?metric ?falloff ?radius ?distance_attribute ?mask_attribute
      geometry)

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
