open Prismel

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
type polyframe_style = Polyframe.style =
  | First_edge
  | Two_edges
  | Primitive_centroid
  | Texture_uv of string
  | Texture_uv_gradient of string
  | Attribute_gradient of string
type line_kind = Line_curve | Line_points
type circle_arc =
  | Circle_closed
  | Circle_open_arc of { start_angle : float; end_angle : float }
  | Circle_closed_arc of { start_angle : float; end_angle : float }
  | Circle_sliced_arc of { start_angle : float; end_angle : float }
type circle_orientation =
  | Circle_xy
  | Circle_xz
  | Circle_yz
  | Circle_axes of { horizontal : Vec3.t; vertical : Vec3.t }
type box_connectivity =
  | Box_triangles
  | Box_quads
  | Box_surface_points
  | Box_lattice_points
type box_normals = Box_no_normals | Box_point_normals | Box_vertex_normals
type box_rotation_order =
  | Box_xyz | Box_xzy | Box_yxz | Box_yzx | Box_zxy | Box_zyx
type sphere_connectivity =
  | Sphere_triangles
  | Sphere_alternating_triangles
  | Sphere_quads
  | Sphere_rows
  | Sphere_columns
  | Sphere_rows_and_columns
  | Sphere_points
type sphere_normals =
  | Sphere_no_normals | Sphere_point_normals | Sphere_vertex_normals
type sphere_orientation =
  | Sphere_x | Sphere_y | Sphere_z | Sphere_axis of Vec3.t
type sphere_rotation_order =
  | Sphere_xyz | Sphere_xzy | Sphere_yxz
  | Sphere_yzx | Sphere_zxy | Sphere_zyx
type torus_connectivity =
  | Torus_triangles
  | Torus_alternating_triangles
  | Torus_quads
  | Torus_rows
  | Torus_columns
  | Torus_rows_and_columns
  | Torus_points
type torus_normals =
  | Torus_no_normals | Torus_point_normals | Torus_vertex_normals
type torus_orientation =
  | Torus_x | Torus_y | Torus_z | Torus_axis of Vec3.t
type torus_rotation_order =
  | Torus_xyz | Torus_xzy | Torus_yxz
  | Torus_yzx | Torus_zxy | Torus_zyx
type tube_connectivity =
  | Tube_triangles
  | Tube_alternating_triangles
  | Tube_quads
  | Tube_rows
  | Tube_columns
  | Tube_rows_and_columns
  | Tube_points
type tube_normals =
  | Tube_no_normals | Tube_point_normals | Tube_vertex_normals
type tube_orientation =
  | Tube_x | Tube_y | Tube_z | Tube_axis of Vec3.t
type tube_rotation_order =
  | Tube_xyz | Tube_xzy | Tube_yxz
  | Tube_yzx | Tube_zxy | Tube_zyx
type platonic_kind =
  | Platonic_tetrahedron
  | Platonic_cube
  | Platonic_octahedron
  | Platonic_icosahedron
  | Platonic_dodecahedron
  | Platonic_soccer_ball
type platonic_normals =
  | Platonic_no_normals | Platonic_point_normals | Platonic_vertex_normals
type platonic_orientation =
  | Platonic_x | Platonic_y | Platonic_z | Platonic_axis of Vec3.t
type platonic_rotation_order =
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
type grid_counts = Grid_divisions | Grid_point_counts
type grid_orientation =
  | Grid_xy
  | Grid_xz
  | Grid_yz
  | Grid_axes of { horizontal : Vec3.t; vertical : Vec3.t }
type grid_connectivity =
  | Grid_points
  | Grid_rows
  | Grid_columns
  | Grid_rows_and_columns
  | Grid_quads
  | Grid_triangles
  | Grid_alternating_triangles
  | Grid_reverse_triangles
type revolve_type = Revolve_closed | Revolve_open_arc
type sweep_tangent =
  | Sweep_average_edges
  | Sweep_central_difference
  | Sweep_previous_edge
  | Sweep_next_edge
  | Sweep_z_axis

let finite value = Float.is_finite value
let get_ok = function Ok value -> value | Error message -> invalid_arg message

let points values =
  let count = Array.length values in
  let builder = Packed.Float3.Builder.create count in
  Array.iteri (fun index (x, y, z) ->
    Packed.Float3.Builder.set builder index x y z) values;
  let positions = Packed.Float3.Builder.freeze builder in
  Geometry.create ~positions ~topology:(Topology.empty ~point_count:count) ()
  |> get_ok

let line ?cancel ?(grain = 16_384) ?(kind = Line_curve) ?(points = 2)
    ~origin ~direction ~length () =
  let minimum = match kind with Line_curve -> 2 | Line_points -> 1 in
  if grain <= 0 then Error "Pdk.Ops.line: grain must be positive"
  else if points < minimum then Error (Printf.sprintf
      "Pdk.Ops.line: %s output requires at least %d points"
      (match kind with Line_curve -> "curve" | Line_points -> "point") minimum)
  else if not (finite origin.Vec3.x && finite origin.y && finite origin.z
      && finite direction.Vec3.x && finite direction.y && finite direction.z
      && finite length && length >= 0.) then
    Error "Pdk.Ops.line: origin/direction must be finite and length finite and non-negative"
  else
    let scale = max (abs_float direction.x)
        (max (abs_float direction.y) (abs_float direction.z)) in
    if scale = 0. then Error "Pdk.Ops.line: direction must be non-zero"
    else
      let sx = direction.x /. scale and sy = direction.y /. scale
      and sz = direction.z /. scale in
      let magnitude = sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
      let dx = (sx /. magnitude) *. length
      and dy = (sy /. magnitude) *. length
      and dz = (sz /. magnitude) *. length in
      let end_x = origin.x +. dx and end_y = origin.y +. dy
      and end_z = origin.z +. dz in
      if not (finite end_x && finite end_y && finite end_z) then
        Error "Pdk.Ops.line: endpoint is not finite"
      else begin
        let x = Array.make points 0. and y = Array.make points 0.
        and z = Array.make points 0.
        and vertex_points = match kind with
          | Line_curve -> Some (Array.make points 0)
          | Line_points -> None in
        Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(points - 1)
          (fun point ->
            if point land 16_383 = 0 then Cancel.check_opt cancel;
            let t = if points = 1 then 0.
              else float_of_int point /. float_of_int (points - 1) in
            x.(point) <- origin.x +. (dx *. t);
            y.(point) <- origin.y +. (dy *. t);
            z.(point) <- origin.z +. (dz *. t);
            match vertex_points with
            | None -> () | Some values -> values.(point) <- point);
        x.(0) <- origin.x; y.(0) <- origin.y; z.(0) <- origin.z;
        if points > 1 then begin
          x.(points - 1) <- end_x;
          y.(points - 1) <- end_y;
          z.(points - 1) <- end_z
        end;
        let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
        let topology = match kind with
          | Line_points -> Topology.empty ~point_count:points
          | Line_curve -> Topology.Private.create_validated_owned
              ~point_count:points ~vertex_points:(Option.get vertex_points)
              ~primitive_offsets:[|0; points|]
              ~primitive_kinds:(Bytes.make 1 '\001') in
        Geometry.create ~positions ~topology ()
      end

let polyline ?(closed = false) values =
  let count = Array.length values in
  let minimum = if closed then 3 else 2 in
  if count < minimum then Error (Printf.sprintf
      "Pdk.Ops.polyline: %s polylines require at least %d points"
      (if closed then "closed" else "open") minimum)
  else if Array.exists (fun (x, y, z) -> not (finite x && finite y && finite z)) values
  then Error "Pdk.Ops.polyline: positions must be finite"
  else
    let geometry = points values in
    let topology = Topology.Builder.create ~point_count:count
        ~vertex_capacity:count ~primitive_capacity:1 () in
    let indices = Array.init count Fun.id in
    if closed then Topology.Builder.add_closed_polyline topology indices
    else Topology.Builder.add_open_polyline topology indices;
    Geometry.create ~positions:(Geometry.positions geometry)
      ~topology:(Topology.Builder.freeze topology) ()

let normal_attribute owner count nx ny nz =
  let x = Array.make count nx and y = Array.make count ny
  and z = Array.make count nz in
  let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  Attribute.create_key_owned (Attribute.normal ~owner) values |> get_ok

let normalize_plane_axis operation label value =
  if not (finite value.Vec3.x && finite value.y && finite value.z) then
    Error (operation ^ ": " ^ label ^ " axis must be finite")
  else
    let scale = max (abs_float value.x)
        (max (abs_float value.y) (abs_float value.z)) in
    if scale = 0. then Error (operation ^ ": " ^ label ^ " axis must be non-zero")
    else
      let x = value.x /. scale and y = value.y /. scale
      and z = value.z /. scale in
      let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
      if not (finite length) || length <= 1e-15 then
        Error (operation ^ ": " ^ label ^ " axis cannot be normalized")
      else Ok (Vec3.create (x /. length) (y /. length) (z /. length))

let plane_frame operation ~horizontal ~vertical rotation =
  Result.bind (normalize_plane_axis operation "horizontal" horizontal)
    (fun horizontal ->
  Result.bind (normalize_plane_axis operation "vertical" vertical)
    (fun vertical ->
  let projection = Vec3.dot vertical horizontal in
  let vertical = Vec3.create
      (vertical.x -. (projection *. horizontal.x))
      (vertical.y -. (projection *. horizontal.y))
      (vertical.z -. (projection *. horizontal.z)) in
  Result.bind (normalize_plane_axis operation "vertical" vertical)
    (fun vertical ->
    let horizontal, vertical = if rotation = 0. then horizontal, vertical
      else
        let cosine = cos rotation and sine = sin rotation in
        Vec3.create
          ((cosine *. horizontal.x) +. (sine *. vertical.x))
          ((cosine *. horizontal.y) +. (sine *. vertical.y))
          ((cosine *. horizontal.z) +. (sine *. vertical.z)),
        Vec3.create
          ((-.sine *. horizontal.x) +. (cosine *. vertical.x))
          ((-.sine *. horizontal.y) +. (cosine *. vertical.y))
          ((-.sine *. horizontal.z) +. (cosine *. vertical.z)) in
    Result.map (fun normal -> horizontal, vertical, normal)
      (normalize_plane_axis operation "normal"
         (Vec3.cross vertical horizontal)))))

let grid_frame orientation rotation =
  let horizontal, vertical = match orientation with
    | Grid_xy -> Vec3.unit_x, Vec3.neg Vec3.unit_y
    | Grid_xz -> Vec3.unit_x, Vec3.unit_z
    | Grid_yz -> Vec3.unit_z, Vec3.unit_y
    | Grid_axes { horizontal; vertical } -> horizontal, vertical in
  plane_frame "Pdk.Ops.grid" ~horizontal ~vertical rotation

let circle_frame orientation rotation =
  let horizontal, vertical = match orientation with
    | Circle_xy -> Vec3.unit_x, Vec3.unit_y
    | Circle_xz -> Vec3.unit_x, Vec3.unit_z
    | Circle_yz -> Vec3.unit_y, Vec3.unit_z
    | Circle_axes { horizontal; vertical } -> horizontal, vertical in
  plane_frame "Pdk.Ops.circle" ~horizontal ~vertical rotation

let circle ?cancel ?(grain = 16_384) ?(arc = Circle_closed)
    ?(orientation = Circle_xz) ?(reverse = false) ?(center = Vec3.zero)
    ?radius_x ?radius_y ?(rotation = 0.) ?(uniform_scale = 1.)
    ?(segments = 64) ~radius () =
  let radius_x = Option.value ~default:radius radius_x *. uniform_scale
  and radius_y = Option.value ~default:radius radius_y *. uniform_scale in
  let minimum_segments = match arc with
    | Circle_closed -> 3
    | Circle_open_arc _ -> 1
    | Circle_closed_arc _ -> 2
    | Circle_sliced_arc _ -> 1 in
  let arc_angles = match arc with
    | Circle_closed -> Ok (0., Float.pi *. 2.)
    | Circle_open_arc { start_angle; end_angle }
    | Circle_closed_arc { start_angle; end_angle }
    | Circle_sliced_arc { start_angle; end_angle } ->
        if not (finite start_angle && finite end_angle) then
          Error "Pdk.Ops.circle: arc angles must be finite"
        else
          let sweep = end_angle -. start_angle in
          if not (finite sweep) || sweep = 0. then
            Error "Pdk.Ops.circle: arc angles must span a finite non-zero interval"
          else Ok (start_angle, end_angle) in
  if grain <= 0 then Error "Pdk.Ops.circle: grain must be positive"
  else if segments < minimum_segments then Error (Printf.sprintf
      "Pdk.Ops.circle: this arc mode requires at least %d segments"
      minimum_segments)
  else if not (finite radius && finite radius_x && finite radius_y
      && finite uniform_scale && radius > 0. && radius_x > 0. && radius_y > 0.
      && uniform_scale > 0.) then
    Error "Pdk.Ops.circle: radii and uniform scale must be finite and positive"
  else if not (finite center.x && finite center.y && finite center.z
      && finite rotation) then
    Error "Pdk.Ops.circle: center and rotation must be finite"
  else Result.bind arc_angles (fun (start_angle, end_angle) ->
    Result.bind (circle_frame orientation rotation)
      (fun (horizontal, vertical, _normal) ->
    let arc_points, add_center, closed, full_circle = match arc with
      | Circle_closed -> segments, false, true, true
      | Circle_open_arc _ -> segments + 1, false, false, false
      | Circle_closed_arc _ -> segments + 1, false, true, false
      | Circle_sliced_arc _ -> segments + 1, true, true, false in
    let point_limit = Sys.max_array_length in
    if segments = max_int || arc_points > point_limit
       || add_center && arc_points = point_limit then
      Error "Pdk.Ops.circle: point cardinality exceeds OCaml array limits"
    else
      let point_count = arc_points + if add_center then 1 else 0 in
      let px = Array.make point_count 0. and py = Array.make point_count 0.
      and pz = Array.make point_count 0.
      and vertex_points = Array.make point_count 0 in
      let step = (end_angle -. start_angle) /. float_of_int segments in
      let range_count = ((arc_points - 1) / grain) + 1 in
      let errors = Array.make range_count (-1) in
      Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
        (fun range ->
          let first = range * grain
          and last = min arc_points ((range + 1) * grain) in
          for local = first to last - 1 do
            if local land 4095 = 0 then Cancel.check_opt cancel;
            let sample = if reverse then arc_points - 1 - local else local in
            let angle = if not full_circle && sample = arc_points - 1
                then end_angle
              else start_angle +. (float_of_int sample *. step) in
            let u = radius_x *. cos angle and v = radius_y *. sin angle in
            let x = center.x +. (horizontal.x *. u) +. (vertical.x *. v)
            and y = center.y +. (horizontal.y *. u) +. (vertical.y *. v)
            and z = center.z +. (horizontal.z *. u) +. (vertical.z *. v) in
            if finite x && finite y && finite z then begin
              px.(local) <- x; py.(local) <- y; pz.(local) <- z;
              vertex_points.(local) <- local
            end else if errors.(range) < 0 then errors.(range) <- local
          done);
      let invalid = Array.fold_left (fun first point ->
          if point < 0 then first else if first < 0 then point
          else min first point) (-1) errors in
      if invalid >= 0 then Error (Printf.sprintf
          "Pdk.Ops.circle: generated point %d is not finite" invalid)
      else begin
        if add_center then begin
          px.(arc_points) <- center.x; py.(arc_points) <- center.y;
          pz.(arc_points) <- center.z;
          vertex_points.(arc_points) <- arc_points
        end;
        let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
        let primitive_offsets = [|0; point_count|]
        and primitive_kinds = Bytes.make 1 (if closed then '\002' else '\001') in
        let topology = Topology.Private.create_validated_owned ~point_count
            ~vertex_points ~primitive_offsets ~primitive_kinds in
        Geometry.create ~positions ~topology ()
      end))

let grid ?cancel ?(grain = 16_384) ?(counts = Grid_divisions)
    ?(connectivity = Grid_triangles) ?(orientation = Grid_xz)
    ?(center = Vec3.zero) ?width ?height ?(rotation = 0.) ?uv_attribute
    ~columns ~rows ~size () =
  let width = Option.value ~default:size width
  and height = Option.value ~default:size height in
  let minimum_columns, minimum_rows = match counts, connectivity with
    | Grid_divisions, _ -> 1, 1
    | Grid_point_counts, Grid_points -> 1, 1
    | Grid_point_counts, Grid_rows -> 2, 1
    | Grid_point_counts, Grid_columns -> 1, 2
    | Grid_point_counts, (Grid_rows_and_columns | Grid_quads | Grid_triangles
        | Grid_alternating_triangles | Grid_reverse_triangles) -> 2, 2 in
  if grain <= 0 then Error "Pdk.Ops.grid: grain must be positive"
  else if columns < minimum_columns || rows < minimum_rows then Error
      (Printf.sprintf "Pdk.Ops.grid: this count/connectivity mode requires at least %d columns and %d rows"
         minimum_columns minimum_rows)
  else if counts = Grid_divisions && (columns = max_int || rows = max_int) then
    Error "Pdk.Ops.grid: point cardinality overflows"
  else if not (finite size && size > 0. && finite width && width > 0.
      && finite height && height > 0.) then
    Error "Pdk.Ops.grid: size, width, and height must be finite and positive"
  else if not (finite center.x && finite center.y && finite center.z
      && finite rotation) then
    Error "Pdk.Ops.grid: center and rotation must be finite"
  else if match uv_attribute with
    | Some name -> String.trim name = "" || String.equal name "P"
        || String.equal name "N"
    | None -> false then
    Error "Pdk.Ops.grid: UV attribute name must be non-empty and cannot be P or N"
  else Result.bind (grid_frame orientation rotation)
      (fun (horizontal, vertical, normal) ->
    let u_points, v_points = match counts with
      | Grid_divisions -> columns + 1, rows + 1
      | Grid_point_counts -> columns, rows in
    let u_divisions = u_points - 1 and v_divisions = v_points - 1 in
    let checked_product left right limit =
      if left = 0 || right <= limit / left then Some (left * right) else None in
    let point_limit = Sys.max_array_length
    and primitive_limit = min (Sys.max_array_length - 1) Sys.max_string_length in
    match checked_product u_points v_points point_limit with
    | None -> Error "Pdk.Ops.grid: point cardinality exceeds OCaml array limits"
    | Some point_count ->
        let topology_cardinality =
          let cells = match checked_product u_divisions v_divisions point_limit with
            | Some cells -> cells | None -> -1 in
          match connectivity with
          | Grid_points -> Some (0, 0)
          | Grid_rows -> if v_points <= primitive_limit then
                Some (point_count, v_points) else None
          | Grid_columns -> if u_points <= primitive_limit then
                Some (point_count, u_points) else None
          | Grid_rows_and_columns ->
              if point_count <= point_limit / 2
                 && u_points <= primitive_limit - v_points
              then Some (point_count * 2, u_points + v_points) else None
          | Grid_quads ->
              if cells >= 0 && cells <= point_limit / 4
                 && cells <= primitive_limit
              then Some (cells * 4, cells) else None
          | Grid_triangles | Grid_alternating_triangles
          | Grid_reverse_triangles ->
              if cells >= 0 && cells <= point_limit / 6
                 && cells <= primitive_limit / 2
              then Some (cells * 6, cells * 2) else None in
        (match topology_cardinality with
         | None -> Error
             "Pdk.Ops.grid: topology cardinality exceeds OCaml array limits"
         | Some (vertex_count, primitive_count) ->
             let px = Array.make point_count 0. and py = Array.make point_count 0.
             and pz = Array.make point_count 0. in
             let uv_x, uv_y = match uv_attribute with
               | None -> None, None
               | Some _ -> Some (Array.make point_count 0.),
                   Some (Array.make point_count 0.) in
             let row_grain = max 1 (grain / u_points) in
             let range_count = ((v_points - 1) / row_grain) + 1 in
             let errors = Array.make range_count (-1) in
             Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
               (fun range ->
                 let first_row = range * row_grain
                 and last_row = min v_points ((range + 1) * row_grain) in
                 for row = first_row to last_row - 1 do
                   let v = if v_points = 1 then 0.5
                     else float_of_int row /. float_of_int v_divisions in
                   let dv = (v -. 0.5) *. height in
                   let base_x = center.x +. (vertical.x *. dv)
                   and base_y = center.y +. (vertical.y *. dv)
                   and base_z = center.z +. (vertical.z *. dv)
                   and at = row * u_points in
                   for column = 0 to u_points - 1 do
                     let point = at + column in
                     if point land 4095 = 0 then Cancel.check_opt cancel;
                     let u = if u_points = 1 then 0.5
                       else float_of_int column /. float_of_int u_divisions in
                     let du = (u -. 0.5) *. width in
                     let x = base_x +. (horizontal.x *. du)
                     and y = base_y +. (horizontal.y *. du)
                     and z = base_z +. (horizontal.z *. du) in
                     if finite x && finite y && finite z then begin
                       px.(point) <- x; py.(point) <- y; pz.(point) <- z;
                       (match uv_x, uv_y with
                        | Some uv_x, Some uv_y ->
                            uv_x.(point) <- u; uv_y.(point) <- v
                        | None, None -> ()
                        | _ -> assert false)
                     end else if errors.(range) < 0 then errors.(range) <- point
                   done
                 done);
             let invalid = Array.fold_left (fun first point ->
                 if point < 0 then first else if first < 0 then point
                 else min first point) (-1) errors in
             if invalid >= 0 then Error (Printf.sprintf
                 "Pdk.Ops.grid: generated point %d is not finite" invalid)
             else
               let positions = Packed.Float3.Private.of_owned_exn
                   ~x:px ~y:py ~z:pz in
               let line_topology mode =
                 let vertex_points = Array.make vertex_count 0
                 and primitive_offsets = Array.make (primitive_count + 1) 0
                 and primitive_kinds = Bytes.make primitive_count '\001' in
                 let primitive_grain =
                   max 1 (grain / max 1 (max u_points v_points)) in
                 let fill_row at =
                   for column = 0 to u_points - 1 do
                     vertex_points.(at + column) <- at + column
                   done
                 and fill_column column at =
                   for row = 0 to v_points - 1 do
                     vertex_points.(at + row) <- (row * u_points) + column
                   done in
                 Parallel.for_ ~chunk_size:primitive_grain ~start:0
                   ~finish:(primitive_count - 1) (fun primitive ->
                     if primitive land 1023 = 0 then Cancel.check_opt cancel;
                     match mode with
                     | `Rows ->
                         let at = primitive * u_points in
                         fill_row at
                     | `Columns ->
                         fill_column primitive (primitive * v_points)
                     | `Both ->
                         if primitive < v_points then
                           fill_row (primitive * u_points)
                         else
                           let column = primitive - v_points in
                           fill_column column
                             (point_count + (column * v_points)));
                 (match mode with
                  | `Rows ->
                      for primitive = 0 to primitive_count do
                        primitive_offsets.(primitive) <- primitive * u_points
                      done
                  | `Columns ->
                      for primitive = 0 to primitive_count do
                        primitive_offsets.(primitive) <- primitive * v_points
                      done
                  | `Both ->
                      for row = 0 to v_points do
                        primitive_offsets.(row) <- row * u_points
                      done;
                      for column = 0 to u_points do
                        primitive_offsets.(v_points + column) <-
                          point_count + (column * v_points)
                      done);
                 Topology.Private.create_validated_owned ~point_count
                   ~vertex_points ~primitive_offsets ~primitive_kinds in
               let polygon_topology slots reverse_mode =
                 let vertex_points = Array.make vertex_count 0
                 and primitive_offsets = Array.make (primitive_count + 1) 0
                 and primitive_kinds = Bytes.make primitive_count '\000' in
                 let cell_count = u_divisions * v_divisions in
                 Parallel.for_ ~chunk_size:(max 1 (grain / slots)) ~start:0
                   ~finish:(cell_count - 1) (fun cell ->
                     if cell land 4095 = 0 then Cancel.check_opt cancel;
                     let row = cell / u_divisions
                     and column = cell mod u_divisions in
                     let a = (row * u_points) + column in
                     let b = a + 1 and d = a + u_points in
                     let c = d + 1 and at = cell * slots in
                     if slots = 4 then begin
                       vertex_points.(at) <- a; vertex_points.(at + 1) <- d;
                       vertex_points.(at + 2) <- c; vertex_points.(at + 3) <- b
                     end else
                       let reverse = reverse_mode = 1
                         || reverse_mode = 2 && ((row + column) land 1 = 1) in
                       if reverse then begin
                         vertex_points.(at) <- a; vertex_points.(at + 1) <- d;
                         vertex_points.(at + 2) <- b; vertex_points.(at + 3) <- b;
                         vertex_points.(at + 4) <- d; vertex_points.(at + 5) <- c
                       end else begin
                         vertex_points.(at) <- a; vertex_points.(at + 1) <- d;
                         vertex_points.(at + 2) <- c; vertex_points.(at + 3) <- a;
                         vertex_points.(at + 4) <- c; vertex_points.(at + 5) <- b
                       end);
                 let primitive_size = if slots = 4 then 4 else 3 in
                 Parallel.for_ ~chunk_size:grain ~start:0 ~finish:primitive_count
                   (fun primitive ->
                     if primitive land 4095 = 0 then Cancel.check_opt cancel;
                     primitive_offsets.(primitive) <- primitive * primitive_size);
                 Topology.Private.create_validated_owned ~point_count
                   ~vertex_points ~primitive_offsets ~primitive_kinds in
               let topology = match connectivity with
                 | Grid_points -> Topology.empty ~point_count
                 | Grid_rows -> line_topology `Rows
                 | Grid_columns -> line_topology `Columns
                 | Grid_rows_and_columns -> line_topology `Both
                 | Grid_quads -> polygon_topology 4 0
                 | Grid_triangles -> polygon_topology 6 0
                 | Grid_reverse_triangles -> polygon_topology 6 1
                 | Grid_alternating_triangles -> polygon_topology 6 2 in
               let normal_attribute = normal_attribute Attribute.Point point_count
                   normal.x normal.y normal.z in
               let attributes = match uv_attribute, uv_x, uv_y with
                 | None, None, None -> [normal_attribute]
                 | Some name, Some x, Some y ->
                     let uv = Packed.Float2.of_owned ~x ~y |> get_ok in
                     let uv = Attribute.create_owned ~name ~owner:Attribute.Point
                         (Attribute.Float2 uv) |> get_ok in
                     [normal_attribute; uv]
                 | _ -> assert false in
               Geometry.create ~positions ~topology ~attributes ()))

let box_rotation_matrix order rotation =
  let x = Mat4.rotation_x rotation.Vec3.x
  and y = Mat4.rotation_y rotation.y
  and z = Mat4.rotation_z rotation.z in
  match order with
  | Box_xyz -> Mat4.mul z (Mat4.mul y x)
  | Box_xzy -> Mat4.mul y (Mat4.mul z x)
  | Box_yxz -> Mat4.mul z (Mat4.mul x y)
  | Box_yzx -> Mat4.mul x (Mat4.mul z y)
  | Box_zxy -> Mat4.mul y (Mat4.mul x z)
  | Box_zyx -> Mat4.mul x (Mat4.mul y z)

let box ?cancel ?(grain = 16_384) ?(connectivity = Box_triangles)
    ?(consolidate_points = false) ?normals ?(center = Vec3.zero)
    ?(rotation = Vec3.zero) ?(rotation_order = Box_xyz)
    ?(uniform_scale = 1.) ?(x_divisions = 1) ?(y_divisions = 1)
    ?(z_divisions = 1) ?uv_attribute ?face_groups ~size () =
  let polygon_mode = match connectivity with
    | Box_triangles | Box_quads -> true
    | Box_surface_points | Box_lattice_points -> false in
  let normal_mode = match normals with
    | Some mode -> mode
    | None -> if polygon_mode then Box_point_normals else Box_no_normals in
  let sx = size.Vec3.x *. uniform_scale
  and sy = size.y *. uniform_scale
  and sz = size.z *. uniform_scale in
  if grain <= 0 then Error "Pdk.Ops.box: grain must be positive"
  else if x_divisions <= 0 || y_divisions <= 0 || z_divisions <= 0 then
    Error "Pdk.Ops.box: axis divisions must be positive"
  else if x_divisions = max_int || y_divisions = max_int
      || z_divisions = max_int then
    Error "Pdk.Ops.box: point cardinality overflows"
  else if not (finite size.x && finite size.y && finite size.z
      && finite uniform_scale && uniform_scale > 0.
      && finite sx && finite sy && finite sz
      && sx > 0. && sy > 0. && sz > 0.) then
    Error "Pdk.Ops.box: dimensions and uniform scale must be finite and positive"
  else if not (finite center.x && finite center.y && finite center.z
      && finite rotation.x && finite rotation.y && finite rotation.z) then
    Error "Pdk.Ops.box: center and rotation must be finite"
  else if (match uv_attribute with
      | Some name -> String.trim name = "" || String.equal name "P"
          || String.equal name "N"
      | None -> false) then
    Error "Pdk.Ops.box: UV attribute name must be non-empty and cannot be P or N"
  else if (match face_groups with
      | Some prefix -> String.trim prefix = ""
      | None -> false) then
    Error "Pdk.Ops.box: face-group prefix must be non-empty"
  else if not polygon_mode && Option.is_some uv_attribute then
    Error "Pdk.Ops.box: point output cannot carry vertex UVs"
  else if not polygon_mode && Option.is_some face_groups then
    Error "Pdk.Ops.box: point output cannot carry primitive face groups"
  else if not polygon_mode && normal_mode = Box_vertex_normals then
    Error "Pdk.Ops.box: point output cannot carry vertex normals"
  else if connectivity = Box_lattice_points
      && normal_mode <> Box_no_normals then
    Error "Pdk.Ops.box: volume lattice points do not have surface normals"
  else if connectivity = Box_triangles && not consolidate_points
      && normal_mode = Box_point_normals
      && center.x = 0. && center.y = 0. && center.z = 0.
      && rotation.x = 0. && rotation.y = 0. && rotation.z = 0.
      && uniform_scale = 1. && x_divisions = 1 && y_divisions = 1
      && z_divisions = 1 && Option.is_none uv_attribute
      && Option.is_none face_groups then begin
    Cancel.check_opt cancel;
    let hx = sx *. 0.5 and hy = sy *. 0.5 and hz = sz *. 0.5 in
    let positions = Packed.Float3.Private.of_owned_exn
        ~x:[|hx;hx;hx;hx; -.hx;-.hx;-.hx;-.hx;
             -.hx;-.hx;hx;hx; -.hx;-.hx;hx;hx;
             -.hx;hx;hx;-.hx; hx;-.hx;-.hx;hx|]
        ~y:[|-.hy;hy;hy;-.hy; -.hy;hy;hy;-.hy;
             hy;hy;hy;hy; -.hy;-.hy;-.hy;-.hy;
             -.hy;-.hy;hy;hy; -.hy;-.hy;hy;hy|]
        ~z:[|-.hz;-.hz;hz;hz; hz;hz;-.hz;-.hz;
             -.hz;hz;hz;-.hz; hz;-.hz;-.hz;hz;
             hz;hz;hz;hz; -.hz;-.hz;-.hz;-.hz|] in
    let normals = Packed.Float3.Private.of_owned_exn
        ~x:[|1.;1.;1.;1.; -1.;-1.;-1.;-1.;
             0.;0.;0.;0.; 0.;0.;0.;0.; 0.;0.;0.;0.; 0.;0.;0.;0.|]
        ~y:[|0.;0.;0.;0.; 0.;0.;0.;0.;
             1.;1.;1.;1.; -1.;-1.;-1.;-1.;
             0.;0.;0.;0.; 0.;0.;0.;0.|]
        ~z:[|0.;0.;0.;0.; 0.;0.;0.;0.; 0.;0.;0.;0.; 0.;0.;0.;0.;
             1.;1.;1.;1.; -1.;-1.;-1.;-1.|] in
    let vertex_points = Array.init 36 (fun vertex ->
      let face = vertex / 6 and local = vertex mod 6 in
      (face * 4) + (match local with
        | 0 | 3 -> 0 | 1 -> 1 | 2 | 4 -> 2 | _ -> 3)) in
    let topology = Topology.Private.create_validated_owned ~point_count:24
        ~vertex_points ~primitive_offsets:(Array.init 13 (fun index -> index * 3))
        ~primitive_kinds:(Bytes.make 12 '\000') in
    let normal = Attribute.create_key_owned
        (Attribute.normal ~owner:Attribute.Point) normals |> get_ok in
    Geometry.create ~positions ~topology ~attributes:[normal] ()
  end
  else
    let point_limit = Sys.max_array_length
    and primitive_limit = min (Sys.max_array_length - 1) Sys.max_string_length in
    let checked_mul left right limit =
      if left = 0 || right <= limit / left then Some (left * right) else None
    and checked_add left right limit =
      if right <= limit - left then Some (left + right) else None in
    let nxp = x_divisions + 1 and nyp = y_divisions + 1
    and nzp = z_divisions + 1 in
    let pair left right = checked_mul left right point_limit in
    let sum3 a b c = match checked_add a b point_limit with
      | None -> None
      | Some value -> checked_add value c point_limit in
    let xy_points = pair nxp nyp and yz_points = pair nyp nzp
    and zx_points = pair nzp nxp in
    let xy_cells = pair x_divisions y_divisions
    and yz_cells = pair y_divisions z_divisions
    and zx_cells = pair z_divisions x_divisions in
    let face_local_points = match xy_points, yz_points, zx_points with
      | Some xy, Some yz, Some zx ->
          Option.bind (sum3 xy yz zx) (fun half -> checked_mul 2 half point_limit)
      | _ -> None in
    let boundary_points = match xy_points with
      | None -> None
      | Some plane ->
          (match checked_mul 2 nxp point_limit,
                 checked_mul 2 (y_divisions - 1) point_limit with
           | Some a, Some b ->
               Option.bind (checked_add a b point_limit) (fun ring ->
               Option.bind (checked_mul (z_divisions - 1) ring point_limit)
                 (fun middle ->
               Option.bind (checked_mul 2 plane point_limit)
                 (fun caps -> checked_add caps middle point_limit)))
           | _ -> None) in
    let lattice_points = match xy_points with
      | Some xy -> checked_mul xy nzp point_limit
      | None -> None in
    let surface_cells = match xy_cells, yz_cells, zx_cells with
      | Some xy, Some yz, Some zx ->
          Option.bind (sum3 xy yz zx) (fun half -> checked_mul 2 half point_limit)
      | _ -> None in
    let point_count = match connectivity, consolidate_points with
      | Box_lattice_points, _ -> lattice_points
      | (Box_triangles | Box_quads | Box_surface_points), true -> boundary_points
      | (Box_triangles | Box_quads | Box_surface_points), false ->
          face_local_points in
    let topology_cardinality = match connectivity, surface_cells with
      | (Box_surface_points | Box_lattice_points), _ -> Some (0, 0)
      | _, None -> None
      | Box_quads, Some cells ->
          if cells <= primitive_limit && cells <= point_limit / 4
          then Some (cells * 4, cells) else None
      | Box_triangles, Some cells ->
          if cells <= primitive_limit / 2 && cells <= point_limit / 6
          then Some (cells * 6, cells * 2) else None in
    match point_count, topology_cardinality with
    | None, _ -> Error "Pdk.Ops.box: point cardinality exceeds OCaml array limits"
    | _, None -> Error "Pdk.Ops.box: topology cardinality exceeds OCaml array limits"
    | Some point_count, Some (vertex_count, primitive_count) ->
        let hx = sx *. 0.5 and hy = sy *. 0.5 and hz = sz *. 0.5 in
        let rotated = rotation.x <> 0. || rotation.y <> 0. || rotation.z <> 0. in
        let matrix = box_rotation_matrix rotation_order rotation in
        let m00 = Mat4.get matrix ~row:0 ~column:0
        and m01 = Mat4.get matrix ~row:0 ~column:1
        and m02 = Mat4.get matrix ~row:0 ~column:2
        and m10 = Mat4.get matrix ~row:1 ~column:0
        and m11 = Mat4.get matrix ~row:1 ~column:1
        and m12 = Mat4.get matrix ~row:1 ~column:2
        and m20 = Mat4.get matrix ~row:2 ~column:0
        and m21 = Mat4.get matrix ~row:2 ~column:1
        and m22 = Mat4.get matrix ~row:2 ~column:2 in
        let[@inline always] rotate x y z =
          if rotated then
            (m00 *. x) +. (m01 *. y) +. (m02 *. z),
            (m10 *. x) +. (m11 *. y) +. (m12 *. z),
            (m20 *. x) +. (m21 *. y) +. (m22 *. z)
          else x, y, z in
        let[@inline always] axis half extent index divisions =
          if index = 0 then -.half
          else if index = divisions then half
          else -.half +. (extent *. float_of_int index /. float_of_int divisions) in
        let x_axis = Array.init nxp (fun index ->
          axis hx sx index x_divisions)
        and y_axis = Array.init nyp (fun index ->
          axis hy sy index y_divisions)
        and z_axis = Array.init nzp (fun index ->
          axis hz sz index z_divisions) in
        let face_u_div face = match face with
          | 0 | 1 -> y_divisions | 2 | 3 -> z_divisions | _ -> x_divisions
        and face_v_div face = match face with
          | 0 | 1 -> z_divisions | 2 | 3 -> x_divisions | _ -> y_divisions in
        let face_point_offsets = Array.make 7 0
        and face_cell_offsets = Array.make 7 0 in
        for face = 0 to 5 do
          let u = face_u_div face and v = face_v_div face in
          face_point_offsets.(face + 1) <- face_point_offsets.(face)
            + ((u + 1) * (v + 1));
          face_cell_offsets.(face + 1) <- face_cell_offsets.(face) + (u * v)
        done;
        let face_normal face = match face with
          | 0 -> 1., 0., 0. | 1 -> -1., 0., 0.
          | 2 -> 0., 1., 0. | 3 -> 0., -1., 0.
          | 4 -> 0., 0., 1. | _ -> 0., 0., -1. in
        let face_normals = Array.init 6 (fun face ->
          let x, y, z = face_normal face in rotate x y z) in
        let plane = nxp * nyp and ring = (2 * nxp) + (2 * (y_divisions - 1)) in
        let top_base = plane + ((z_divisions - 1) * ring) in
        let[@inline always] boundary_index x y z =
          if z = 0 then (y * nxp) + x
          else if z = z_divisions then top_base + (y * nxp) + x
          else
            let base = plane + ((z - 1) * ring) in
            if y = 0 then base + x
            else if y = y_divisions then
              base + nxp + (2 * (y_divisions - 1)) + x
            else base + nxp + (2 * (y - 1))
                + if x = 0 then 0 else 1 in
        let[@inline always] face_point_index face row column =
          if consolidate_points then
            match face with
            | 0 -> boundary_index x_divisions column row
            | 1 -> boundary_index 0 column (z_divisions - row)
            | 2 -> boundary_index row y_divisions column
            | 3 -> boundary_index row 0 (z_divisions - column)
            | 4 -> boundary_index column row z_divisions
            | _ -> boundary_index (x_divisions - column) row 0
          else
            let u_points = face_u_div face + 1 in
            face_point_offsets.(face) + (row * u_points)
              + if row land 1 = 0 then column else u_points - 1 - column in
        let px = Array.make point_count 0. and py = Array.make point_count 0.
        and pz = Array.make point_count 0. in
        let point_normals = match normal_mode with
          | Box_point_normals -> Some (Array.make point_count 0.,
              Array.make point_count 0., Array.make point_count 0.)
          | Box_no_normals | Box_vertex_normals -> None in
        let[@inline always] write_grid_position point x_index y_index z_index =
          let local_x = x_axis.(x_index) and local_y = y_axis.(y_index)
          and local_z = z_axis.(z_index) in
          let x = center.x +. if rotated then
              (m00 *. local_x) +. (m01 *. local_y) +. (m02 *. local_z)
            else local_x
          and y = center.y +. if rotated then
              (m10 *. local_x) +. (m11 *. local_y) +. (m12 *. local_z)
            else local_y
          and z = center.z +. if rotated then
              (m20 *. local_x) +. (m21 *. local_y) +. (m22 *. local_z)
            else local_z in
          if finite x && finite y && finite z then begin
            px.(point) <- x; py.(point) <- y; pz.(point) <- z;
            true
          end else false in
        let[@inline always] write_boundary point x y z =
          let valid = write_grid_position point x y z in
          if valid then (
            match point_normals with
            | Some (nx, ny, nz) ->
                let qx = if x = 0 then -1. else if x = x_divisions then 1.
                  else 0.
                and qy = if y = 0 then -1. else if y = y_divisions then 1.
                  else 0.
                and qz = if z = 0 then -1. else if z = z_divisions then 1.
                  else 0. in
                let length = sqrt ((qx *. qx) +. (qy *. qy) +. (qz *. qz)) in
                let qx = qx /. length and qy = qy /. length
                and qz = qz /. length in
                if rotated then begin
                  nx.(point) <- (m00 *. qx) +. (m01 *. qy) +. (m02 *. qz);
                  ny.(point) <- (m10 *. qx) +. (m11 *. qy) +. (m12 *. qz);
                  nz.(point) <- (m20 *. qx) +. (m21 *. qy) +. (m22 *. qz)
                end else begin
                  nx.(point) <- qx; ny.(point) <- qy; nz.(point) <- qz
                end
            | None -> ());
          valid in
        let invalid_point = ref (-1) in
        let note_errors errors =
          Array.iter (fun point -> if point >= 0
              && (!invalid_point < 0 || point < !invalid_point)
            then invalid_point := point) errors in
        (match connectivity, consolidate_points with
         | Box_lattice_points, _ ->
             let range_count = ((point_count - 1) / grain) + 1 in
             let errors = Array.make range_count (-1) in
             Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
               (fun range ->
                 let first = range * grain
                 and last = min point_count ((range + 1) * grain) in
                 for point = first to last - 1 do
                   if point land 4095 = 0 then Cancel.check_opt cancel;
                   let x = point mod nxp in
                   let yz = point / nxp in
                   let y = yz mod nyp and z = yz / nyp in
                   if not (write_grid_position point x y z)
                      && errors.(range) < 0 then errors.(range) <- point
                 done);
             note_errors errors
         | _, true ->
             let range_count = ((point_count - 1) / grain) + 1 in
             let errors = Array.make range_count (-1) in
             Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
               (fun range ->
                 let first = range * grain
                 and last = min point_count ((range + 1) * grain) in
                 for point = first to last - 1 do
                   if point land 4095 = 0 then Cancel.check_opt cancel;
                   let valid =
                     if point < plane then
                       write_boundary point (point mod nxp) (point / nxp) 0
                     else if point >= top_base then
                       let local = point - top_base in
                       write_boundary point (local mod nxp) (local / nxp)
                         z_divisions
                     else
                       let local = point - plane in
                       let z = 1 + (local / ring)
                       and within = local mod ring in
                       if within < nxp then write_boundary point within 0 z
                       else if within < nxp + (2 * (y_divisions - 1)) then
                         let pair = within - nxp in
                         write_boundary point
                           (if pair land 1 = 0 then 0 else x_divisions)
                           (1 + (pair / 2)) z
                       else write_boundary point
                           (within - nxp - (2 * (y_divisions - 1)))
                           y_divisions z in
                   if not valid && errors.(range) < 0 then
                     errors.(range) <- point
                 done);
             note_errors errors
         | _, false ->
             for face = 0 to 5 do
               let u_div = face_u_div face and v_div = face_v_div face in
               let u_points = u_div + 1 in
               let row_grain = max 1 (grain / u_points) in
               let range_count = (v_div / row_grain) + 1 in
               let errors = Array.make range_count (-1) in
               let nnx, nny, nnz = face_normals.(face) in
               Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
                 (fun range ->
                   let first_row = range * row_grain
                   and last_row = min (v_div + 1) ((range + 1) * row_grain) in
                   for row = first_row to last_row - 1 do
                     for column = 0 to u_div do
                       let point = face_point_index face row column in
                       if point land 4095 = 0 then Cancel.check_opt cancel;
                       let valid = match face with
                         | 0 -> write_grid_position point x_divisions column row
                         | 1 -> write_grid_position point 0 column
                             (z_divisions - row)
                         | 2 -> write_grid_position point row y_divisions column
                         | 3 -> write_grid_position point row 0
                             (z_divisions - column)
                         | 4 -> write_grid_position point column row z_divisions
                         | _ -> write_grid_position point
                             (x_divisions - column) row 0 in
                       if valid then
                         (match point_normals with
                          | Some (nx, ny, nz) ->
                              nx.(point) <- nnx; ny.(point) <- nny;
                              nz.(point) <- nnz
                          | None -> ())
                       else if errors.(range) < 0 then errors.(range) <- point
                     done
                   done);
               note_errors errors
             done);
        if !invalid_point >= 0 then Error (Printf.sprintf
            "Pdk.Ops.box: generated point %d is not finite" !invalid_point)
        else
          let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
          let topology, vertex_normals, uv = if not polygon_mode then
              Topology.empty ~point_count, None, None
            else
              let slots = if connectivity = Box_quads then 4 else 6 in
              let primitive_per_cell = if slots = 4 then 1 else 2 in
              let vertex_points = Array.make vertex_count 0
              and primitive_offsets = Array.make (primitive_count + 1) 0
              and primitive_kinds = Bytes.make primitive_count '\000' in
              let vertex_normals = match normal_mode with
                | Box_vertex_normals -> Some (Array.make vertex_count 0.,
                    Array.make vertex_count 0., Array.make vertex_count 0.)
                | Box_no_normals | Box_point_normals -> None in
              let uv = match uv_attribute with
                | Some _ -> Some (Array.make vertex_count 0.,
                    Array.make vertex_count 0.)
                | None -> None in
              for face = 0 to 5 do
                let u_div = face_u_div face and v_div = face_v_div face in
                let cell_count = u_div * v_div in
                let cell_base = face_cell_offsets.(face) in
                let nnx, nny, nnz = face_normals.(face) in
                let[@inline always] write_vertex at slot point u_index v_index =
                  let vertex = at + slot in
                  vertex_points.(vertex) <- point;
                  (match vertex_normals with
                   | Some (x, y, z) ->
                       x.(vertex) <- nnx; y.(vertex) <- nny; z.(vertex) <- nnz
                   | None -> ());
                  match uv with
                  | Some (x, y) ->
                      x.(vertex) <- float_of_int u_index /. float_of_int u_div;
                      y.(vertex) <- float_of_int v_index /. float_of_int v_div
                  | None -> () in
                Parallel.for_ ~chunk_size:(max 1 (grain / slots)) ~start:0
                  ~finish:(cell_count - 1) (fun local_cell ->
                    if local_cell land 4095 = 0 then Cancel.check_opt cancel;
                    let row = local_cell / u_div and column = local_cell mod u_div in
                    let a = face_point_index face row column
                    and b = face_point_index face row (column + 1)
                    and c = face_point_index face (row + 1) (column + 1)
                    and d = face_point_index face (row + 1) column in
                    let at = (cell_base + local_cell) * slots in
                    if slots = 4 then begin
                      write_vertex at 0 a column row;
                      write_vertex at 1 b (column + 1) row;
                      write_vertex at 2 c (column + 1) (row + 1);
                      write_vertex at 3 d column (row + 1)
                    end else begin
                      write_vertex at 0 a column row;
                      write_vertex at 1 b (column + 1) row;
                      write_vertex at 2 c (column + 1) (row + 1);
                      write_vertex at 3 a column row;
                      write_vertex at 4 c (column + 1) (row + 1);
                      write_vertex at 5 d column (row + 1)
                    end)
              done;
              Parallel.for_ ~chunk_size:grain ~start:0 ~finish:primitive_count
                (fun primitive ->
                  if primitive land 4095 = 0 then Cancel.check_opt cancel;
                  primitive_offsets.(primitive) <- primitive
                    * (slots / primitive_per_cell));
              Topology.Private.create_validated_owned ~point_count
                ~vertex_points ~primitive_offsets ~primitive_kinds,
              vertex_normals, uv in
          let attributes = ref [] in
          (match point_normals with
           | Some (x, y, z) ->
               let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
               attributes := (Attribute.create_key_owned
                   (Attribute.normal ~owner:Attribute.Point) values |> get_ok)
                 :: !attributes
           | None -> ());
          (match vertex_normals with
           | Some (x, y, z) ->
               let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
               attributes := (Attribute.create_key_owned
                   (Attribute.normal ~owner:Attribute.Vertex) values |> get_ok)
                 :: !attributes
           | None -> ());
          (match uv_attribute, uv with
           | Some name, Some (x, y) ->
               let values = Packed.Float2.of_owned ~x ~y |> get_ok in
               attributes := (Attribute.create_owned ~name ~owner:Attribute.Vertex
                   (Attribute.Float2 values) |> get_ok) :: !attributes
           | None, None -> ()
           | _ -> assert false);
          let groups = match face_groups with
            | None -> []
            | Some prefix ->
                let names = [|"right"; "left"; "top"; "bottom";
                  "front"; "back"|] in
                Array.to_list (Array.init 6 (fun face ->
                  let first = face_cell_offsets.(face)
                      * (if connectivity = Box_triangles then 2 else 1)
                  and last = face_cell_offsets.(face + 1)
                      * (if connectivity = Box_triangles then 2 else 1) in
                  let builder = Group.Builder.create ~owner:Group.Primitive
                      ~name:(prefix ^ "__" ^ names.(face)) primitive_count in
                  for primitive = first to last - 1 do
                    if primitive land 4095 = 0 then Cancel.check_opt cancel;
                    Group.Builder.set builder primitive true
                  done;
                  Group.Builder.freeze builder)) in
          Geometry.create ~positions ~topology ~attributes:(List.rev !attributes)
            ~groups ()

let sphere_rotation_matrix order rotation =
  let x = Mat4.rotation_x rotation.Vec3.x
  and y = Mat4.rotation_y rotation.y
  and z = Mat4.rotation_z rotation.z in
  match order with
  | Sphere_xyz -> Mat4.mul z (Mat4.mul y x)
  | Sphere_xzy -> Mat4.mul y (Mat4.mul z x)
  | Sphere_yxz -> Mat4.mul z (Mat4.mul x y)
  | Sphere_yzx -> Mat4.mul x (Mat4.mul z y)
  | Sphere_zxy -> Mat4.mul y (Mat4.mul x z)
  | Sphere_zyx -> Mat4.mul x (Mat4.mul y z)

let sphere_frame orientation rotation_order (rotation : Vec3.t) =
  let oriented = match orientation with
    | Sphere_x -> Ok (Vec3.unit_y, Vec3.unit_x,
        Vec3.create 0. 0. (-1.))
    | Sphere_y -> Ok (Vec3.unit_x, Vec3.unit_y, Vec3.unit_z)
    | Sphere_z -> Ok (Vec3.unit_x, Vec3.unit_z,
        Vec3.create 0. (-1.) 0.)
    | Sphere_axis axis ->
        Result.bind (normalize_plane_axis "Pdk.Ops.uv_sphere" "pole" axis)
          (fun pole ->
            let ax = abs_float pole.x and ay = abs_float pole.y
            and az = abs_float pole.z in
            let reference = if ax <= ay && ax <= az then Vec3.unit_x
              else if ay <= az then Vec3.unit_y else Vec3.unit_z in
            let projection = Vec3.dot reference pole in
            let radial = Vec3.create
                (reference.x -. (projection *. pole.x))
                (reference.y -. (projection *. pole.y))
                (reference.z -. (projection *. pole.z)) in
            Result.bind (normalize_plane_axis "Pdk.Ops.uv_sphere" "radial"
                radial) (fun radial ->
              Result.map (fun tangent -> radial, pole, tangent)
                (normalize_plane_axis "Pdk.Ops.uv_sphere" "tangent"
                   (Vec3.cross radial pole)))) in
  Result.map (fun (radial, pole, tangent) ->
    if rotation.x = 0. && rotation.y = 0. && rotation.z = 0. then
      radial, pole, tangent
    else
      let matrix = sphere_rotation_matrix rotation_order rotation in
      Mat4.transform_direction matrix radial,
      Mat4.transform_direction matrix pole,
      Mat4.transform_direction matrix tangent) oriented

let uv_sphere ?cancel ?(grain = 16_384)
    ?(connectivity = Sphere_triangles) ?(unique_points_per_pole = false)
    ?(triangular_poles = true) ?normals ?(orientation = Sphere_y)
    ?(center = Vec3.zero) ?(rotation = Vec3.zero)
    ?(rotation_order = Sphere_xyz) ?(uniform_scale = 1.)
    ?radius_x ?radius_y ?radius_z ?uv_attribute ?(segments = 48) ?(rings = 24)
    ~radius () =
  let point_mode = connectivity = Sphere_points in
  let normal_mode = match normals with
    | Some mode -> mode
    | None -> Sphere_point_normals in
  let rx = Option.value ~default:radius radius_x *. uniform_scale
  and ry = Option.value ~default:radius radius_y *. uniform_scale
  and rz = Option.value ~default:radius radius_z *. uniform_scale in
  if grain <= 0 then Error "Pdk.Ops.uv_sphere: grain must be positive"
  else if segments < 3 then
    Error "Pdk.Ops.uv_sphere: segments must be at least 3"
  else if rings < 2 then Error "Pdk.Ops.uv_sphere: rings must be at least 2"
  else if segments = max_int || rings = max_int then
    Error "Pdk.Ops.uv_sphere: output cardinality overflows"
  else if not (finite radius && radius > 0. && finite uniform_scale
      && uniform_scale > 0. && finite rx && finite ry && finite rz
      && rx > 0. && ry > 0. && rz > 0.) then
    Error "Pdk.Ops.uv_sphere: radii and uniform scale must be finite and positive"
  else if not (finite center.x && finite center.y && finite center.z
      && finite rotation.x && finite rotation.y && finite rotation.z) then
    Error "Pdk.Ops.uv_sphere: center and rotation must be finite"
  else if (match uv_attribute with
      | Some name -> String.trim name = "" || String.equal name "P"
          || String.equal name "N"
      | None -> false) then
    Error "Pdk.Ops.uv_sphere: UV attribute name must be non-empty and cannot be P or N"
  else if point_mode && normal_mode = Sphere_vertex_normals then
    Error "Pdk.Ops.uv_sphere: point output cannot carry vertex normals"
  else Result.bind (sphere_frame orientation rotation_order rotation)
      (fun (radial_axis, pole_axis, tangent_axis) ->
    let point_limit = Sys.max_array_length
    and primitive_limit = min (Sys.max_array_length - 1) Sys.max_string_length in
    let checked_mul left right limit =
      if left = 0 || right <= limit / left then Some (left * right) else None
    and checked_add left right limit =
      if right <= limit - left then Some (left + right) else None in
    let include_poles = connectivity <> Sphere_rows in
    let pole_count = if include_poles then
        if unique_points_per_pole then segments else 1
      else 0 in
    let interior_count = checked_mul (rings - 1) segments point_limit in
    let point_count = match interior_count,
        checked_mul 2 pole_count point_limit with
      | Some interior, Some poles -> checked_add interior poles point_limit
      | _ -> None in
    let row_vertices = interior_count in
    let column_vertices = checked_mul segments (rings + 1) point_limit in
    let middle_cells = checked_mul (rings - 2) segments point_limit in
    let surface_bands = checked_mul (rings - 1) segments point_limit in
    let topology_cardinality = match connectivity with
      | Sphere_points -> Some (0, 0)
      | Sphere_rows -> Option.bind row_vertices (fun vertices ->
          if rings - 1 <= primitive_limit then Some (vertices, rings - 1)
          else None)
      | Sphere_columns -> Option.bind column_vertices (fun vertices ->
          if segments <= primitive_limit then Some (vertices, segments)
          else None)
      | Sphere_rows_and_columns ->
          (match row_vertices, column_vertices with
           | Some rows, Some columns ->
               Option.bind (checked_add rows columns point_limit) (fun vertices ->
                 if segments <= primitive_limit - (rings - 1) then
                   Some (vertices, segments + rings - 1) else None)
           | _ -> None)
      | Sphere_triangles | Sphere_alternating_triangles ->
          Option.bind surface_bands (fun bands ->
            match checked_mul 2 bands primitive_limit with
            | None -> None
            | Some primitives -> Option.bind
                (checked_mul 3 primitives point_limit)
                (fun vertices -> Some (vertices, primitives)))
      | Sphere_quads ->
          (match checked_mul segments rings primitive_limit, middle_cells with
           | Some primitives, Some middle ->
               let vertices = if triangular_poles then
                   Option.bind (checked_mul 4 middle point_limit)
                     (fun middle_vertices ->
                       Option.bind (checked_mul 6 segments point_limit)
                         (fun pole_vertices -> checked_add middle_vertices
                             pole_vertices point_limit))
                 else checked_mul 4 primitives point_limit in
               Option.map (fun vertices -> vertices, primitives) vertices
           | _ -> None) in
    match point_count, topology_cardinality, interior_count, middle_cells with
    | None, _, _, _ ->
        Error "Pdk.Ops.uv_sphere: point cardinality exceeds OCaml array limits"
    | _, None, _, _ ->
        Error "Pdk.Ops.uv_sphere: topology cardinality exceeds OCaml array limits"
    | _, _, None, _ | _, _, _, None ->
        Error "Pdk.Ops.uv_sphere: output cardinality exceeds OCaml array limits"
    | Some point_count, Some (vertex_count, primitive_count),
      Some interior_count, Some middle_cells ->
        let identity_frame = orientation = Sphere_y
          && rotation.x = 0. && rotation.y = 0. && rotation.z = 0.
          && center.x = 0. && center.y = 0. && center.z = 0. in
        let compatible_normals = identity_frame
          && connectivity = Sphere_triangles && not unique_points_per_pole
          && triangular_poles && normal_mode = Sphere_point_normals
          && Option.is_none uv_attribute && uniform_scale = 1.
          && rx = radius && ry = radius && rz = radius in
        let theta_sine = Array.make (rings + 1) 0.
        and theta_cosine = Array.make (rings + 1) 0.
        and phi_sine = Array.make segments 0.
        and phi_cosine = Array.make segments 0. in
        Parallel.for_ ~chunk_size:grain ~start:0 ~finish:rings (fun ring ->
          if ring land 4095 = 0 then Cancel.check_opt cancel;
          let theta = Float.pi *. float_of_int ring /. float_of_int rings in
          theta_sine.(ring) <- sin theta;
          theta_cosine.(ring) <- cos theta);
        Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(segments - 1)
          (fun segment ->
            if segment land 4095 = 0 then Cancel.check_opt cancel;
            let phi = Float.pi *. 2. *. float_of_int segment
                /. float_of_int segments in
            phi_sine.(segment) <- sin phi;
            phi_cosine.(segment) <- cos phi);
        let top_count = pole_count and interior_base = pole_count in
        let bottom_base = interior_base + interior_count in
        let[@inline always] point_of ring segment =
          let segment = if segment = segments then 0 else segment in
          if ring = 0 then if unique_points_per_pole then segment else 0
          else if ring = rings then bottom_base
              + if unique_points_per_pole then segment else 0
          else interior_base + ((ring - 1) * segments) + segment in
        let px = Array.make point_count 0. and py = Array.make point_count 0.
        and pz = Array.make point_count 0. in
        let point_normals = match normal_mode with
          | Sphere_point_normals -> Some (Array.make point_count 0.,
              Array.make point_count 0., Array.make point_count 0.)
          | Sphere_no_normals | Sphere_vertex_normals -> None in
        let point_uv = match uv_attribute, point_mode with
          | Some _, true -> Some (Array.make point_count 0.,
              Array.make point_count 0.)
          | _ -> None in
        let minimum_radius = min rx (min ry rz) in
        let inverse_weight_x = minimum_radius /. rx
        and inverse_weight_y = minimum_radius /. ry
        and inverse_weight_z = minimum_radius /. rz in
        let[@inline always] write_normal nx ny nz at ring segment =
          let segment = if segment = segments then 0 else segment in
          if compatible_normals then begin
            nx.(at) <- px.(at) /. radius;
            ny.(at) <- py.(at) /. radius;
            nz.(at) <- pz.(at) /. radius
          end else begin
            let sine_theta = theta_sine.(ring)
            and cosine_theta = theta_cosine.(ring)
            and sine_phi = phi_sine.(segment)
            and cosine_phi = phi_cosine.(segment) in
            let tx = sine_theta *. cosine_phi and ty = cosine_theta
            and tz = sine_theta *. sine_phi in
            let gx = tx *. inverse_weight_x
            and gy = ty *. inverse_weight_y
            and gz = tz *. inverse_weight_z in
            let length = sqrt ((gx *. gx) +. (gy *. gy) +. (gz *. gz)) in
            let gx, gy, gz = if length > 0. then
                gx /. length, gy /. length, gz /. length
              else
                let score value radius = if value = 0. then neg_infinity
                  else log (abs_float value) -. log radius in
                let sx = score tx rx and sy = score ty ry
                and sz = score tz rz in
                let maximum = Float.max sx (Float.max sy sz) in
                let component value score = if value = 0. then 0.
                  else
                    let magnitude = exp (score -. maximum) in
                    if value < 0. then -.magnitude else magnitude in
                let gx = component tx sx and gy = component ty sy
                and gz = component tz sz in
                let length = sqrt ((gx *. gx) +. (gy *. gy) +. (gz *. gz)) in
                gx /. length, gy /. length, gz /. length in
            if identity_frame then begin
              nx.(at) <- gx; ny.(at) <- gy; nz.(at) <- gz
            end else begin
              nx.(at) <- (radial_axis.x *. gx) +. (pole_axis.x *. gy)
                  +. (tangent_axis.x *. gz);
              ny.(at) <- (radial_axis.y *. gx) +. (pole_axis.y *. gy)
                  +. (tangent_axis.y *. gz);
              nz.(at) <- (radial_axis.z *. gx) +. (pole_axis.z *. gy)
                  +. (tangent_axis.z *. gz)
            end
          end in
        let[@inline always] write_point point ring segment =
          let segment = if segment = segments then 0 else segment in
          let local_x, local_y, local_z = if ring = 0 then 0., ry, 0.
            else if ring = rings then 0., -.ry, 0.
            else
              let radial = theta_sine.(ring) in
              (rx *. radial) *. phi_cosine.(segment),
              ry *. theta_cosine.(ring),
              (rz *. radial) *. phi_sine.(segment) in
          let x, y, z = if identity_frame then local_x, local_y, local_z
            else
              center.x +. (radial_axis.x *. local_x)
                +. (pole_axis.x *. local_y) +. (tangent_axis.x *. local_z),
              center.y +. (radial_axis.y *. local_x)
                +. (pole_axis.y *. local_y) +. (tangent_axis.y *. local_z),
              center.z +. (radial_axis.z *. local_x)
                +. (pole_axis.z *. local_y) +. (tangent_axis.z *. local_z) in
          if finite x && finite y && finite z then begin
            px.(point) <- x; py.(point) <- y; pz.(point) <- z;
            (match point_normals with
             | Some (nx, ny, nz) -> write_normal nx ny nz point ring segment
             | None -> ());
            (match point_uv with
             | Some (u, v) ->
                 u.(point) <- float_of_int segment /. float_of_int segments;
                 v.(point) <- float_of_int ring /. float_of_int rings
             | None -> ());
            true
          end else false in
        let range_count = ((point_count - 1) / grain) + 1 in
        let errors = Array.make range_count (-1) in
        Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
          (fun range ->
            let first = range * grain
            and last = min point_count ((range + 1) * grain) in
            for point = first to last - 1 do
              if point land 4095 = 0 then Cancel.check_opt cancel;
              let ring, segment = if not include_poles then
                  1 + (point / segments), point mod segments
                else if point < top_count then 0,
                  if unique_points_per_pole then point else 0
                else if point < bottom_base then
                  let local = point - interior_base in
                  1 + (local / segments), local mod segments
                else rings, if unique_points_per_pole
                    then point - bottom_base else 0 in
              if not (write_point point ring segment) && errors.(range) < 0 then
                errors.(range) <- point
            done);
        let invalid = Array.fold_left (fun first point ->
            if point < 0 then first else if first < 0 || point < first
            then point else first) (-1) errors in
        if invalid >= 0 then Error (Printf.sprintf
            "Pdk.Ops.uv_sphere: generated point %d is not finite" invalid)
        else
          let vertex_normals = match normal_mode with
            | Sphere_vertex_normals -> Some (Array.make vertex_count 0.,
                Array.make vertex_count 0., Array.make vertex_count 0.)
            | Sphere_no_normals | Sphere_point_normals -> None in
          let vertex_uv = match uv_attribute, point_mode with
            | Some _, false -> Some (Array.make vertex_count 0.,
                Array.make vertex_count 0.)
            | _ -> None in
          let[@inline always] write_vertex vertex point ring segment u_twice =
            let points = point in
            (match vertex_normals with
             | Some (nx, ny, nz) -> write_normal nx ny nz vertex ring segment
             | None -> ());
            (match vertex_uv with
             | Some (u, v) ->
                 u.(vertex) <- float_of_int u_twice
                     /. float_of_int (2 * segments);
                 v.(vertex) <- float_of_int ring /. float_of_int rings
             | None -> ());
            points in
          let topology = match connectivity with
            | Sphere_points -> Topology.empty ~point_count
            | Sphere_rows | Sphere_columns | Sphere_rows_and_columns ->
                let vertex_points = Array.make vertex_count 0
                and primitive_offsets = Array.make (primitive_count + 1) 0
                and primitive_kinds = Bytes.make primitive_count '\001' in
                let row_count = match connectivity with
                  | Sphere_rows | Sphere_rows_and_columns -> rings - 1
                  | _ -> 0 in
                let row_vertex_count = row_count * segments in
                Parallel.for_ ~chunk_size:(max 1 (grain / (rings + segments)))
                  ~start:0 ~finish:(primitive_count - 1) (fun primitive ->
                    if primitive land 1023 = 0 then Cancel.check_opt cancel;
                    if primitive < row_count then begin
                      let ring = primitive + 1 and at = primitive * segments in
                      for segment = 0 to segments - 1 do
                        let vertex = at + segment in
                        vertex_points.(vertex) <- write_vertex vertex
                            (point_of ring segment) ring segment (2 * segment)
                      done
                    end else begin
                      let column = primitive - row_count in
                      let at = row_vertex_count + (column * (rings + 1)) in
                      for ring = 0 to rings do
                        let vertex = at + ring in
                        vertex_points.(vertex) <- write_vertex vertex
                            (point_of ring column) ring column (2 * column)
                      done
                    end);
                Parallel.for_ ~chunk_size:grain ~start:0 ~finish:primitive_count
                  (fun primitive ->
                    if primitive land 4095 = 0 then Cancel.check_opt cancel;
                    primitive_offsets.(primitive) <- if primitive <= row_count
                      then primitive * segments
                      else row_vertex_count
                        + ((primitive - row_count) * (rings + 1)));
                Topology.Private.create_validated_owned ~point_count
                  ~vertex_points ~primitive_offsets ~primitive_kinds
            | Sphere_triangles | Sphere_alternating_triangles | Sphere_quads ->
                let vertex_points = Array.make vertex_count 0
                and primitive_offsets = Array.make (primitive_count + 1) 0
                and primitive_kinds = Bytes.make primitive_count '\000' in
                let triangle_mode = connectivity <> Sphere_quads in
                let bottom_first = if triangle_mode then primitive_count - segments
                  else segments + middle_cells in
                let vertex_offset primitive =
                  if triangle_mode then primitive * 3
                  else if not triangular_poles then primitive * 4
                  else if primitive <= segments then primitive * 3
                  else if primitive <= bottom_first then
                    (segments * 3) + ((primitive - segments) * 4)
                  else
                    (segments * 3) + (middle_cells * 4)
                      + ((primitive - bottom_first) * 3) in
                Parallel.for_ ~chunk_size:(max 1 (grain / 6)) ~start:0
                  ~finish:(primitive_count - 1) (fun primitive ->
                    if primitive land 4095 = 0 then Cancel.check_opt cancel;
                    let at = vertex_offset primitive in
                    if primitive < segments then begin
                      let segment = primitive and next = primitive + 1 in
                      if triangle_mode || triangular_poles then begin
                        vertex_points.(at) <- write_vertex at
                            (point_of 0 segment) 0 segment ((2 * segment) + 1);
                        vertex_points.(at + 1) <- write_vertex (at + 1)
                            (point_of 1 next) 1 next (2 * next);
                        vertex_points.(at + 2) <- write_vertex (at + 2)
                            (point_of 1 segment) 1 segment (2 * segment)
                      end else begin
                        vertex_points.(at) <- write_vertex at
                            (point_of 0 segment) 0 segment (2 * segment);
                        vertex_points.(at + 1) <- write_vertex (at + 1)
                            (point_of 0 next) 0 next (2 * next);
                        vertex_points.(at + 2) <- write_vertex (at + 2)
                            (point_of 1 next) 1 next (2 * next);
                        vertex_points.(at + 3) <- write_vertex (at + 3)
                            (point_of 1 segment) 1 segment (2 * segment)
                      end
                    end else if primitive >= bottom_first then begin
                      let segment = primitive - bottom_first
                      and next = primitive - bottom_first + 1 in
                      if triangle_mode || triangular_poles then begin
                        vertex_points.(at) <- write_vertex at
                            (point_of rings segment) rings segment
                            ((2 * segment) + 1);
                        vertex_points.(at + 1) <- write_vertex (at + 1)
                            (point_of (rings - 1) segment) (rings - 1) segment
                            (2 * segment);
                        vertex_points.(at + 2) <- write_vertex (at + 2)
                            (point_of (rings - 1) next) (rings - 1) next
                            (2 * next)
                      end else begin
                        vertex_points.(at) <- write_vertex at
                            (point_of (rings - 1) segment) (rings - 1) segment
                            (2 * segment);
                        vertex_points.(at + 1) <- write_vertex (at + 1)
                            (point_of (rings - 1) next) (rings - 1) next
                            (2 * next);
                        vertex_points.(at + 2) <- write_vertex (at + 2)
                            (point_of rings next) rings next (2 * next);
                        vertex_points.(at + 3) <- write_vertex (at + 3)
                            (point_of rings segment) rings segment (2 * segment)
                      end
                    end else begin
                      let local = if triangle_mode
                          then (primitive - segments) / 2
                        else primitive - segments in
                      let half = if triangle_mode
                          then (primitive - segments) land 1 else 0 in
                      let ring = 1 + (local / segments)
                      and segment = local mod segments in
                      let next = segment + 1 in
                      let a = point_of ring segment and b = point_of ring next
                      and c = point_of (ring + 1) next
                      and d = point_of (ring + 1) segment in
                      if not triangle_mode then begin
                        vertex_points.(at) <- write_vertex at a ring segment
                            (2 * segment);
                        vertex_points.(at + 1) <- write_vertex (at + 1) b ring
                            next (2 * next);
                        vertex_points.(at + 2) <- write_vertex (at + 2) c
                            (ring + 1) next (2 * next);
                        vertex_points.(at + 3) <- write_vertex (at + 3) d
                            (ring + 1) segment (2 * segment)
                      end else
                        let alternate = connectivity
                            = Sphere_alternating_triangles
                          && ((ring - 1 + segment) land 1 = 1) in
                        if not alternate && half = 0 then begin
                          vertex_points.(at) <- write_vertex at a ring segment
                              (2 * segment);
                          vertex_points.(at + 1) <- write_vertex (at + 1) c
                              (ring + 1) next (2 * next);
                          vertex_points.(at + 2) <- write_vertex (at + 2) d
                              (ring + 1) segment (2 * segment)
                        end else if not alternate then begin
                          vertex_points.(at) <- write_vertex at a ring segment
                              (2 * segment);
                          vertex_points.(at + 1) <- write_vertex (at + 1) b ring
                              next (2 * next);
                          vertex_points.(at + 2) <- write_vertex (at + 2) c
                              (ring + 1) next (2 * next)
                        end else if half = 0 then begin
                          vertex_points.(at) <- write_vertex at a ring segment
                              (2 * segment);
                          vertex_points.(at + 1) <- write_vertex (at + 1) b ring
                              next (2 * next);
                          vertex_points.(at + 2) <- write_vertex (at + 2) d
                              (ring + 1) segment (2 * segment)
                        end else begin
                          vertex_points.(at) <- write_vertex at b ring next
                              (2 * next);
                          vertex_points.(at + 1) <- write_vertex (at + 1) c
                              (ring + 1) next (2 * next);
                          vertex_points.(at + 2) <- write_vertex (at + 2) d
                              (ring + 1) segment (2 * segment)
                        end
                    end);
                Parallel.for_ ~chunk_size:grain ~start:0 ~finish:primitive_count
                  (fun primitive ->
                    if primitive land 4095 = 0 then Cancel.check_opt cancel;
                    primitive_offsets.(primitive) <- vertex_offset primitive);
                Topology.Private.create_validated_owned ~point_count
                  ~vertex_points ~primitive_offsets ~primitive_kinds in
          let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
          let attributes = ref [] in
          (match point_normals with
           | Some (x, y, z) ->
               let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
               attributes := (Attribute.create_key_owned
                   (Attribute.normal ~owner:Attribute.Point) values |> get_ok)
                 :: !attributes
           | None -> ());
          (match vertex_normals with
           | Some (x, y, z) ->
               let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
               attributes := (Attribute.create_key_owned
                   (Attribute.normal ~owner:Attribute.Vertex) values |> get_ok)
                 :: !attributes
           | None -> ());
          (match uv_attribute, point_uv, vertex_uv with
           | Some name, Some (x, y), None ->
               let values = Packed.Float2.of_owned ~x ~y |> get_ok in
               attributes := (Attribute.create_owned ~name ~owner:Attribute.Point
                   (Attribute.Float2 values) |> get_ok) :: !attributes
           | Some name, None, Some (x, y) ->
               let values = Packed.Float2.of_owned ~x ~y |> get_ok in
               attributes := (Attribute.create_owned ~name ~owner:Attribute.Vertex
                   (Attribute.Float2 values) |> get_ok) :: !attributes
           | None, None, None -> ()
           | _ -> assert false);
          Geometry.create ~positions ~topology ~attributes:(List.rev !attributes)
            ())

let torus_rotation_matrix order rotation =
  let x = Mat4.rotation_x rotation.Vec3.x
  and y = Mat4.rotation_y rotation.y
  and z = Mat4.rotation_z rotation.z in
  match order with
  | Torus_xyz -> Mat4.mul z (Mat4.mul y x)
  | Torus_xzy -> Mat4.mul y (Mat4.mul z x)
  | Torus_yxz -> Mat4.mul z (Mat4.mul x y)
  | Torus_yzx -> Mat4.mul x (Mat4.mul z y)
  | Torus_zxy -> Mat4.mul y (Mat4.mul x z)
  | Torus_zyx -> Mat4.mul x (Mat4.mul y z)

let torus_frame orientation rotation_order (rotation : Vec3.t) =
  let oriented = match orientation with
    | Torus_x -> Ok (Vec3.unit_y, Vec3.unit_x, Vec3.create 0. 0. (-1.))
    | Torus_y -> Ok (Vec3.unit_x, Vec3.unit_y, Vec3.unit_z)
    | Torus_z -> Ok (Vec3.unit_x, Vec3.unit_z, Vec3.create 0. (-1.) 0.)
    | Torus_axis axis ->
        Result.bind (normalize_plane_axis "Pdk.Ops.torus" "hole" axis)
          (fun pole ->
            let ax = abs_float pole.x and ay = abs_float pole.y
            and az = abs_float pole.z in
            let reference = if ax <= ay && ax <= az then Vec3.unit_x
              else if ay <= az then Vec3.unit_y else Vec3.unit_z in
            let projection = Vec3.dot reference pole in
            let radial = Vec3.create
                (reference.x -. (projection *. pole.x))
                (reference.y -. (projection *. pole.y))
                (reference.z -. (projection *. pole.z)) in
            Result.bind (normalize_plane_axis "Pdk.Ops.torus" "radial" radial)
              (fun radial ->
                Result.map (fun tangent -> radial, pole, tangent)
                  (normalize_plane_axis "Pdk.Ops.torus" "tangent"
                     (Vec3.cross radial pole)))) in
  Result.map (fun (radial, pole, tangent) ->
    if rotation.x = 0. && rotation.y = 0. && rotation.z = 0. then
      radial, pole, tangent
    else
      let matrix = torus_rotation_matrix rotation_order rotation in
      Mat4.transform_direction matrix radial,
      Mat4.transform_direction matrix pole,
      Mat4.transform_direction matrix tangent) oriented

let torus ?cancel ?(grain = 16_384) ?(connectivity = Torus_triangles)
    ?normals ?(orientation = Torus_y) ?(center = Vec3.zero)
    ?(rotation = Vec3.zero) ?(rotation_order = Torus_xyz)
    ?(uniform_scale = 1.) ?(u_start = 0.) ?(u_end = 2. *. Float.pi)
    ?(v_start = 0.) ?(v_end = 2. *. Float.pi) ?(u_wrap = true)
    ?(v_wrap = true) ?(u_end_caps = false) ?(v_end_cap = false)
    ?uv_attribute ?(rows = 48) ?(columns = 24) ~major_radius ~minor_radius () =
  let point_mode = connectivity = Torus_points in
  let polygon_mode = match connectivity with
    | Torus_triangles | Torus_alternating_triangles | Torus_quads -> true
    | Torus_rows | Torus_columns | Torus_rows_and_columns | Torus_points -> false
  in
  let normal_mode = Option.value ~default:Torus_point_normals normals in
  let major_radius_scaled = major_radius *. uniform_scale
  and minor_radius_scaled = minor_radius *. uniform_scale in
  let u_span = u_end -. u_start and v_span = v_end -. v_start in
  let minimum_u = if u_wrap then 3 else 2
  and minimum_v = if v_wrap then 3 else 2 in
  if grain <= 0 then Error "Pdk.Ops.torus: grain must be positive"
  else if rows < minimum_u then Error (Printf.sprintf
      "Pdk.Ops.torus: rows must be at least %d for the selected U wrap" minimum_u)
  else if columns < minimum_v then Error (Printf.sprintf
      "Pdk.Ops.torus: columns must be at least %d for the selected V wrap" minimum_v)
  else if not (finite major_radius && major_radius > 0.
      && finite minor_radius && minor_radius > 0.
      && finite uniform_scale && uniform_scale > 0.
      && finite major_radius_scaled && major_radius_scaled > 0.
      && finite minor_radius_scaled && minor_radius_scaled > 0.) then
    Error "Pdk.Ops.torus: radii and uniform scale must be finite and positive"
  else if not (finite u_start && finite u_end && finite v_start && finite v_end
      && finite u_span && finite v_span && u_span <> 0. && v_span <> 0.) then
    Error "Pdk.Ops.torus: angle endpoints must define finite non-zero spans"
  else if not (finite center.x && finite center.y && finite center.z
      && finite rotation.x && finite rotation.y && finite rotation.z) then
    Error "Pdk.Ops.torus: center and rotation must be finite"
  else if (match uv_attribute with
      | Some name -> String.trim name = "" || String.equal name "P"
          || String.equal name "N"
      | None -> false) then
    Error "Pdk.Ops.torus: UV attribute name must be non-empty and cannot be P or N"
  else if point_mode && normal_mode = Torus_vertex_normals then
    Error "Pdk.Ops.torus: point output cannot carry vertex normals"
  else if (u_end_caps || v_end_cap) && not polygon_mode then
    Error "Pdk.Ops.torus: end caps require triangle or quad connectivity"
  else if u_end_caps && u_wrap then
    Error "Pdk.Ops.torus: U end caps require an open U sweep"
  else if v_end_cap && v_wrap then
    Error "Pdk.Ops.torus: a V end cap requires an open V sweep"
  else if u_end_caps && columns < 3 then
    Error "Pdk.Ops.torus: U end caps require at least three columns"
  else
    let v_chord_x = cos v_end -. cos v_start
    and v_chord_y = sin v_end -. sin v_start in
    let v_chord_scale = Float.max (abs_float v_chord_x) (abs_float v_chord_y) in
    if v_end_cap && v_chord_scale <= 64. *. Float.epsilon then
      Error "Pdk.Ops.torus: V end cap endpoints are geometrically coincident"
    else Result.bind (torus_frame orientation rotation_order rotation)
      (fun (radial_axis, pole_axis, tangent_axis) ->
      let point_limit = Sys.max_array_length
      and primitive_limit = min (Sys.max_array_length - 1) Sys.max_string_length in
      let checked_mul left right limit =
        if left = 0 || right <= limit / left then Some (left * right) else None
      and checked_add left right limit =
        if right <= limit - left then Some (left + right) else None in
      let u_cells = if u_wrap then rows else rows - 1
      and v_cells = if v_wrap then columns else columns - 1 in
      let reverse_surface = (u_span < 0.) <> (v_span < 0.)
      and u_direction = if u_span < 0. then -1. else 1. in
      let point_count = checked_mul rows columns point_limit in
      let topology_cardinality = match point_count with
        | None -> None
        | Some points ->
            (match connectivity with
             | Torus_points -> Some (0, 0, 0, 0, 0)
             | Torus_rows -> Some (points, columns, 0, 0, 0)
             | Torus_columns -> Some (points, rows, 0, 0, 0)
             | Torus_rows_and_columns ->
                 Option.bind (checked_mul 2 points point_limit) (fun vertices ->
                   Option.map (fun primitives -> vertices, primitives, 0, 0, 0)
                     (checked_add rows columns primitive_limit))
             | Torus_triangles | Torus_alternating_triangles | Torus_quads ->
                 Option.bind (checked_mul u_cells v_cells primitive_limit)
                   (fun cells ->
                     let primitives_per_cell = if connectivity = Torus_quads
                       then 1 else 2 in
                     let vertices_per_cell = primitives_per_cell * 3
                         + if primitives_per_cell = 1 then 1 else 0 in
                     Option.bind (checked_mul cells primitives_per_cell
                         primitive_limit) (fun surface_primitives ->
                     Option.bind (checked_mul cells vertices_per_cell point_limit)
                       (fun surface_vertices ->
                     let v_cap_primitives = if v_end_cap
                         then u_cells * primitives_per_cell else 0
                     and v_cap_vertices = if v_end_cap
                         then u_cells * vertices_per_cell else 0 in
                     Option.bind (checked_add surface_primitives v_cap_primitives
                         primitive_limit) (fun fixed_primitives ->
                     Option.bind (checked_add surface_vertices v_cap_vertices
                         point_limit) (fun fixed_vertices ->
                     let u_cap_primitives = if u_end_caps then 2 else 0
                     and u_cap_vertices = if u_end_caps then 2 * columns else 0 in
                     Option.bind (checked_add fixed_primitives u_cap_primitives
                         primitive_limit) (fun primitives ->
                     Option.map (fun vertices -> vertices, primitives,
                         cells, fixed_primitives, fixed_vertices)
                       (checked_add fixed_vertices u_cap_vertices point_limit)))))))) in
      match point_count, topology_cardinality with
      | None, _ | _, None ->
          Error "Pdk.Ops.torus: output cardinality exceeds OCaml array limits"
      | Some point_count,
        Some (vertex_count, primitive_count, surface_cells,
          fixed_primitive_count, fixed_vertex_count) ->
          let u_sine = Array.make rows 0. and u_cosine = Array.make rows 0.
          and u_parameter = Array.make rows 0.
          and v_sine = Array.make columns 0. and v_cosine = Array.make columns 0.
          and v_parameter = Array.make columns 0. in
          let angle start span wrap count index =
            if not wrap && index = count - 1 then start +. span
            else
              let divisor = if wrap then count else count - 1 in
              start +. (span *. float_of_int index /. float_of_int divisor) in
          Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(rows - 1)
            (fun row ->
              if row land 4095 = 0 then Cancel.check_opt cancel;
              let value = angle u_start u_span u_wrap rows row in
              u_sine.(row) <- sin value; u_cosine.(row) <- cos value;
              u_parameter.(row) <- float_of_int row
                  /. float_of_int (if u_wrap then rows else rows - 1));
          Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(columns - 1)
            (fun column ->
              if column land 4095 = 0 then Cancel.check_opt cancel;
              let value = angle v_start v_span v_wrap columns column in
              v_sine.(column) <- sin value; v_cosine.(column) <- cos value;
              v_parameter.(column) <- float_of_int column
                  /. float_of_int (if v_wrap then columns else columns - 1));
          let identity_axes = orientation = Torus_y
              && rotation.x = 0. && rotation.y = 0. && rotation.z = 0. in
          let px = Array.make point_count 0. and py = Array.make point_count 0.
          and pz = Array.make point_count 0. in
          let point_normals = match normal_mode with
            | Torus_point_normals -> Some (Array.make point_count 0.,
                Array.make point_count 0., Array.make point_count 0.)
            | Torus_no_normals | Torus_vertex_normals -> None in
          let point_uv = match uv_attribute, point_mode with
            | Some _, true -> Some (Array.make point_count 0.,
                Array.make point_count 0.)
            | _ -> None in
          let[@inline always] write_direction x_out y_out z_out at x y z =
            if identity_axes then begin
              x_out.(at) <- x; y_out.(at) <- y; z_out.(at) <- z
            end else begin
              x_out.(at) <- (radial_axis.x *. x) +. (pole_axis.x *. y)
                  +. (tangent_axis.x *. z);
              y_out.(at) <- (radial_axis.y *. x) +. (pole_axis.y *. y)
                  +. (tangent_axis.y *. z);
              z_out.(at) <- (radial_axis.z *. x) +. (pole_axis.z *. y)
                  +. (tangent_axis.z *. z)
            end in
          let[@inline always] write_smooth_normal nx ny nz at row column =
            write_direction nx ny nz at
              (v_cosine.(column) *. u_cosine.(row))
              v_sine.(column)
              (v_cosine.(column) *. u_sine.(row)) in
          let[@inline always] write_point point row column =
            let ring_radius = major_radius_scaled
                +. (minor_radius_scaled *. v_cosine.(column)) in
            let local_x = ring_radius *. u_cosine.(row)
            and local_y = minor_radius_scaled *. v_sine.(column)
            and local_z = ring_radius *. u_sine.(row) in
            let x, y, z = if identity_axes then
                center.x +. local_x, center.y +. local_y, center.z +. local_z
              else
                center.x +. (radial_axis.x *. local_x)
                  +. (pole_axis.x *. local_y) +. (tangent_axis.x *. local_z),
                center.y +. (radial_axis.y *. local_x)
                  +. (pole_axis.y *. local_y) +. (tangent_axis.y *. local_z),
                center.z +. (radial_axis.z *. local_x)
                  +. (pole_axis.z *. local_y) +. (tangent_axis.z *. local_z) in
            if finite x && finite y && finite z then begin
              px.(point) <- x; py.(point) <- y; pz.(point) <- z;
              (match point_normals with
               | Some (nx, ny, nz) ->
                   write_smooth_normal nx ny nz point row column
               | None -> ());
              (match point_uv with
               | Some (u, v) ->
                   u.(point) <- u_parameter.(row);
                   v.(point) <- v_parameter.(column)
               | None -> ());
              true
            end else false in
          let row_grain = max 1 (grain / columns) in
          let range_count = ((rows - 1) / row_grain) + 1 in
          let errors = Array.make range_count (-1) in
          Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
            (fun range ->
              let first_row = range * row_grain
              and last_row = min rows ((range + 1) * row_grain) in
              for row = first_row to last_row - 1 do
                let at = row * columns in
                for column = 0 to columns - 1 do
                  let point = at + column in
                  if point land 4095 = 0 then Cancel.check_opt cancel;
                  if not (write_point point row column) && errors.(range) < 0 then
                    errors.(range) <- point
                done
              done);
          let invalid = Array.fold_left (fun first point ->
              if point < 0 then first else if first < 0 || point < first
              then point else first) (-1) errors in
          if invalid >= 0 then Error (Printf.sprintf
              "Pdk.Ops.torus: generated point %d is not finite" invalid)
          else
            let vertex_normals = match normal_mode with
              | Torus_vertex_normals -> Some (Array.make vertex_count 0.,
                  Array.make vertex_count 0., Array.make vertex_count 0.)
              | Torus_no_normals | Torus_point_normals -> None in
            let vertex_uv = match uv_attribute, point_mode with
              | Some _, false -> Some (Array.make vertex_count 0.,
                  Array.make vertex_count 0.)
              | _ -> None in
            let[@inline always] point_of row column =
              let row = if row = rows then 0 else row
              and column = if column = columns then 0 else column in
              (row * columns) + column in
            let[@inline always] write_surface_vertex vertex point row column =
              (match vertex_normals with
               | Some (nx, ny, nz) ->
                   write_smooth_normal nx ny nz vertex
                     (if row = rows then 0 else row)
                     (if column = columns then 0 else column)
               | None -> ());
              (match vertex_uv with
               | Some (u, v) ->
                   u.(vertex) <- if row = rows then 1. else u_parameter.(row);
                   v.(vertex) <- if column = columns then 1.
                     else v_parameter.(column)
               | None -> ());
              point in
            let topology = match connectivity with
              | Torus_points -> Topology.empty ~point_count
              | Torus_rows | Torus_columns | Torus_rows_and_columns ->
                  let vertex_points = Array.make vertex_count 0
                  and primitive_offsets = Array.make (primitive_count + 1) 0
                  and primitive_kinds = Bytes.make primitive_count '\001' in
                  let row_primitive_count = match connectivity with
                    | Torus_rows | Torus_rows_and_columns -> columns
                    | _ -> 0 in
                  let row_vertex_count = row_primitive_count * rows in
                  Parallel.for_ ~chunk_size:(max 1 (grain / max rows columns))
                    ~start:0 ~finish:(primitive_count - 1) (fun primitive ->
                      if primitive land 1023 = 0 then Cancel.check_opt cancel;
                      if primitive < row_primitive_count then begin
                        let column = primitive and at = primitive * rows in
                        Bytes.set primitive_kinds primitive
                          (if u_wrap then '\002' else '\001');
                        for row = 0 to rows - 1 do
                          let vertex = at + row in
                          vertex_points.(vertex) <- write_surface_vertex vertex
                              (point_of row column) row column
                        done
                      end else begin
                        let row = primitive - row_primitive_count in
                        let at = row_vertex_count + (row * columns) in
                        Bytes.set primitive_kinds primitive
                          (if v_wrap then '\002' else '\001');
                        for column = 0 to columns - 1 do
                          let vertex = at + column in
                          vertex_points.(vertex) <- write_surface_vertex vertex
                              (point_of row column) row column
                        done
                      end);
                  Parallel.for_ ~chunk_size:grain ~start:0 ~finish:primitive_count
                    (fun primitive ->
                      if primitive land 4095 = 0 then Cancel.check_opt cancel;
                      primitive_offsets.(primitive) <-
                        if primitive <= row_primitive_count
                        then primitive * rows
                        else row_vertex_count
                          + ((primitive - row_primitive_count) * columns));
                  Topology.Private.create_validated_owned ~point_count
                    ~vertex_points ~primitive_offsets ~primitive_kinds
              | Torus_triangles | Torus_alternating_triangles | Torus_quads ->
                  let triangle_mode = connectivity <> Torus_quads in
                  let vertices_per_cell = if triangle_mode then 6 else 4 in
                  let surface_vertex_count = surface_cells * vertices_per_cell in
                  let vertex_points = Array.make vertex_count 0
                  and primitive_offsets = Array.make (primitive_count + 1) 0
                  and primitive_kinds = Bytes.make primitive_count '\000' in
                  let[@inline always] set_surface vertex point row column =
                    vertex_points.(vertex) <- write_surface_vertex vertex point
                        row column in
                  Parallel.for_ ~chunk_size:(max 1 (grain / vertices_per_cell))
                    ~start:0 ~finish:(surface_cells - 1) (fun cell ->
                      if cell land 4095 = 0 then Cancel.check_opt cancel;
                      let row = cell / v_cells and column = cell mod v_cells in
                      let next_row = row + 1 and next_column = column + 1 in
                      let a = point_of row column
                      and b = point_of next_row column
                      and c = point_of next_row next_column
                      and d = point_of row next_column in
                      let at = cell * vertices_per_cell in
                      if not triangle_mode then begin
                        if not reverse_surface then begin
                          set_surface at a row column;
                          set_surface (at + 1) d row next_column;
                          set_surface (at + 2) c next_row next_column;
                          set_surface (at + 3) b next_row column
                        end else begin
                          set_surface at a row column;
                          set_surface (at + 1) b next_row column;
                          set_surface (at + 2) c next_row next_column;
                          set_surface (at + 3) d row next_column
                        end
                      end else
                        let alternate = connectivity = Torus_alternating_triangles
                            && ((row + column) land 1 = 1) in
                        if not alternate && not reverse_surface then begin
                          set_surface at a row column;
                          set_surface (at + 1) d row next_column;
                          set_surface (at + 2) c next_row next_column;
                          set_surface (at + 3) a row column;
                          set_surface (at + 4) c next_row next_column;
                          set_surface (at + 5) b next_row column
                        end else if not alternate then begin
                          set_surface at a row column;
                          set_surface (at + 1) c next_row next_column;
                          set_surface (at + 2) d row next_column;
                          set_surface (at + 3) a row column;
                          set_surface (at + 4) b next_row column;
                          set_surface (at + 5) c next_row next_column
                        end else if not reverse_surface then begin
                          set_surface at a row column;
                          set_surface (at + 1) d row next_column;
                          set_surface (at + 2) b next_row column;
                          set_surface (at + 3) d row next_column;
                          set_surface (at + 4) c next_row next_column;
                          set_surface (at + 5) b next_row column
                        end else begin
                          set_surface at a row column;
                          set_surface (at + 1) b next_row column;
                          set_surface (at + 2) d row next_column;
                          set_surface (at + 3) d row next_column;
                          set_surface (at + 4) b next_row column;
                          set_surface (at + 5) c next_row next_column
                        end);
                  let v_cap_vertex_base = surface_vertex_count in
                  let[@inline always] write_v_cap_vertex vertex point row side =
                    vertex_points.(vertex) <- point;
                    (match vertex_normals with
                     | Some (nx, ny, nz) ->
                         let row = if row = rows then 0 else row in
                         let x = u_direction *. -.v_chord_y *. u_cosine.(row)
                         and y = u_direction *. v_chord_x
                         and z = u_direction *. -.v_chord_y *. u_sine.(row) in
                         let scale = Float.max (abs_float x)
                             (Float.max (abs_float y) (abs_float z)) in
                         let x = x /. scale and y = y /. scale
                         and z = z /. scale in
                         let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
                         write_direction nx ny nz vertex
                           (x /. length) (y /. length) (z /. length)
                     | None -> ());
                    match vertex_uv with
                    | Some (u, v) ->
                        u.(vertex) <- if row = rows then 1.
                          else u_parameter.(row);
                        v.(vertex) <- float_of_int side
                    | None -> () in
                  if v_end_cap then
                    Parallel.for_
                      ~chunk_size:(max 1 (grain / vertices_per_cell))
                      ~start:0 ~finish:(u_cells - 1) (fun row ->
                        if row land 4095 = 0 then Cancel.check_opt cancel;
                        let next_row = row + 1 in
                        let a = point_of row 0 and b = point_of next_row 0
                        and c = point_of next_row (columns - 1)
                        and d = point_of row (columns - 1) in
                        let at = v_cap_vertex_base + (row * vertices_per_cell) in
                        if not triangle_mode then begin
                          write_v_cap_vertex at a row 0;
                          write_v_cap_vertex (at + 1) b next_row 0;
                          write_v_cap_vertex (at + 2) c next_row 1;
                          write_v_cap_vertex (at + 3) d row 1
                        end else
                          let alternate = connectivity
                              = Torus_alternating_triangles && (row land 1 = 1) in
                          if not alternate then begin
                            write_v_cap_vertex at a row 0;
                            write_v_cap_vertex (at + 1) b next_row 0;
                            write_v_cap_vertex (at + 2) c next_row 1;
                            write_v_cap_vertex (at + 3) a row 0;
                            write_v_cap_vertex (at + 4) c next_row 1;
                            write_v_cap_vertex (at + 5) d row 1
                          end else begin
                            write_v_cap_vertex at a row 0;
                            write_v_cap_vertex (at + 1) b next_row 0;
                            write_v_cap_vertex (at + 2) d row 1;
                            write_v_cap_vertex (at + 3) b next_row 0;
                            write_v_cap_vertex (at + 4) c next_row 1;
                            write_v_cap_vertex (at + 5) d row 1
                          end);
                  let[@inline always] write_u_cap_vertex vertex point start column =
                    vertex_points.(vertex) <- point;
                    (match vertex_normals with
                     | Some (nx, ny, nz) ->
                         let row = if start then 0 else rows - 1 in
                         let sign = u_direction
                             *. if start then -1. else 1. in
                         write_direction nx ny nz vertex
                           (sign *. -.u_sine.(row)) 0.
                           (sign *. u_cosine.(row))
                     | None -> ());
                    match vertex_uv with
                    | Some (u, v) ->
                        u.(vertex) <- 0.5 +. (0.5 *. v_cosine.(column));
                        v.(vertex) <- 0.5 +. (0.5 *. v_sine.(column))
                    | None -> () in
                  if u_end_caps then begin
                    let start_base = fixed_vertex_count
                    and end_base = fixed_vertex_count + columns in
                    Parallel.for_ ~chunk_size:grain ~start:0
                      ~finish:((2 * columns) - 1) (fun local ->
                        if local land 4095 = 0 then Cancel.check_opt cancel;
                        if local < columns then begin
                          let column = if reverse_surface then local
                            else columns - 1 - local in
                          write_u_cap_vertex (start_base + local)
                            (point_of 0 column) true column
                        end else begin
                          let index = local - columns in
                          let column = if reverse_surface
                            then columns - 1 - index else index in
                          write_u_cap_vertex (end_base + index)
                            (point_of (rows - 1) column) false column
                        end)
                  end;
                  Parallel.for_ ~chunk_size:grain ~start:0
                    ~finish:fixed_primitive_count (fun primitive ->
                      if primitive land 4095 = 0 then Cancel.check_opt cancel;
                      primitive_offsets.(primitive) <- primitive
                          * (if triangle_mode then 3 else 4));
                  if u_end_caps then begin
                    primitive_offsets.(fixed_primitive_count + 1) <-
                      fixed_vertex_count + columns;
                    primitive_offsets.(fixed_primitive_count + 2) <-
                      fixed_vertex_count + (2 * columns)
                  end;
                  Topology.Private.create_validated_owned ~point_count
                    ~vertex_points ~primitive_offsets ~primitive_kinds in
            let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
            let attributes = ref [] in
            (match point_normals with
             | Some (x, y, z) ->
                 let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
                 attributes := (Attribute.create_key_owned
                     (Attribute.normal ~owner:Attribute.Point) values |> get_ok)
                   :: !attributes
             | None -> ());
            (match vertex_normals with
             | Some (x, y, z) ->
                 let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
                 attributes := (Attribute.create_key_owned
                     (Attribute.normal ~owner:Attribute.Vertex) values |> get_ok)
                   :: !attributes
             | None -> ());
            (match uv_attribute, point_uv, vertex_uv with
             | Some name, Some (x, y), None ->
                 let values = Packed.Float2.of_owned ~x ~y |> get_ok in
                 attributes := (Attribute.create_owned ~name ~owner:Attribute.Point
                     (Attribute.Float2 values) |> get_ok) :: !attributes
             | Some name, None, Some (x, y) ->
                 let values = Packed.Float2.of_owned ~x ~y |> get_ok in
                 attributes := (Attribute.create_owned ~name
                     ~owner:Attribute.Vertex (Attribute.Float2 values) |> get_ok)
                   :: !attributes
             | None, None, None -> ()
             | _ -> assert false);
            Geometry.create ~positions ~topology ~attributes:(List.rev !attributes)
              ())

let tube_rotation_matrix order rotation =
  let x = Mat4.rotation_x rotation.Vec3.x
  and y = Mat4.rotation_y rotation.y
  and z = Mat4.rotation_z rotation.z in
  match order with
  | Tube_xyz -> Mat4.mul z (Mat4.mul y x)
  | Tube_xzy -> Mat4.mul y (Mat4.mul z x)
  | Tube_yxz -> Mat4.mul z (Mat4.mul x y)
  | Tube_yzx -> Mat4.mul x (Mat4.mul z y)
  | Tube_zxy -> Mat4.mul y (Mat4.mul x z)
  | Tube_zyx -> Mat4.mul x (Mat4.mul y z)

let tube_frame orientation rotation_order (rotation : Vec3.t) =
  let oriented = match orientation with
    | Tube_x -> Ok (Vec3.unit_y, Vec3.unit_x, Vec3.create 0. 0. (-1.))
    | Tube_y -> Ok (Vec3.unit_x, Vec3.unit_y, Vec3.unit_z)
    | Tube_z -> Ok (Vec3.unit_x, Vec3.unit_z, Vec3.create 0. (-1.) 0.)
    | Tube_axis axis ->
        Result.bind (normalize_plane_axis "Pdk.Ops.tube" "primary" axis)
          (fun pole ->
            let ax = abs_float pole.x and ay = abs_float pole.y
            and az = abs_float pole.z in
            let reference = if ax <= ay && ax <= az then Vec3.unit_x
              else if ay <= az then Vec3.unit_y else Vec3.unit_z in
            let projection = Vec3.dot reference pole in
            let radial = Vec3.create
                (reference.x -. (projection *. pole.x))
                (reference.y -. (projection *. pole.y))
                (reference.z -. (projection *. pole.z)) in
            Result.bind (normalize_plane_axis "Pdk.Ops.tube" "radial" radial)
              (fun radial ->
                Result.map (fun tangent -> radial, pole, tangent)
                  (normalize_plane_axis "Pdk.Ops.tube" "tangent"
                     (Vec3.cross radial pole)))) in
  Result.map (fun (radial, pole, tangent) ->
    if rotation.x = 0. && rotation.y = 0. && rotation.z = 0. then
      radial, pole, tangent
    else
      let matrix = tube_rotation_matrix rotation_order rotation in
      Mat4.transform_direction matrix radial,
      Mat4.transform_direction matrix pole,
      Mat4.transform_direction matrix tangent) oriented

let tube ?cancel ?(grain = 16_384) ?(connectivity = Tube_quads)
    ?(end_caps = false) ?(consolidate_cap_points = true) ?normals
    ?(orientation = Tube_y) ?(center = Vec3.zero) ?(rotation = Vec3.zero)
    ?(rotation_order = Tube_xyz) ?(radius_scale = 1.) ?uv_attribute ?cap_group
    ?(rows = 2) ?(columns = 32) ~top_radius ~bottom_radius ~height () =
  let point_mode = connectivity = Tube_points in
  let polygon_mode = match connectivity with
    | Tube_triangles | Tube_alternating_triangles | Tube_quads -> true
    | Tube_rows | Tube_columns | Tube_rows_and_columns | Tube_points -> false in
  let normal_mode = Option.value ~default:Tube_point_normals normals in
  let top_radius_scaled = top_radius *. radius_scale
  and bottom_radius_scaled = bottom_radius *. radius_scale in
  if grain <= 0 then Error "Pdk.Ops.tube: grain must be positive"
  else if rows < 2 then Error "Pdk.Ops.tube: rows must be at least two"
  else if columns < 3 then Error "Pdk.Ops.tube: columns must be at least three"
  else if not (finite top_radius && top_radius >= 0.
      && finite bottom_radius && bottom_radius >= 0.
      && finite radius_scale && radius_scale > 0.
      && finite top_radius_scaled && top_radius_scaled >= 0.
      && finite bottom_radius_scaled && bottom_radius_scaled >= 0.
      && (top_radius_scaled > 0. || bottom_radius_scaled > 0.)) then
    Error "Pdk.Ops.tube: radii must be finite/non-negative, at least one positive, and radius scale positive"
  else if not (finite height && height > 0.) then
    Error "Pdk.Ops.tube: height must be finite and positive"
  else if not (finite center.x && finite center.y && finite center.z
      && finite rotation.x && finite rotation.y && finite rotation.z) then
    Error "Pdk.Ops.tube: center and rotation must be finite"
  else if (match uv_attribute with
      | Some name -> String.trim name = "" || String.equal name "P"
          || String.equal name "N"
      | None -> false) then
    Error "Pdk.Ops.tube: UV attribute name must be non-empty and cannot be P or N"
  else if (match cap_group with Some name -> String.trim name = "" | None -> false)
  then Error "Pdk.Ops.tube: cap group name must be non-empty"
  else if point_mode && normal_mode = Tube_vertex_normals then
    Error "Pdk.Ops.tube: point output cannot carry vertex normals"
  else if end_caps && not polygon_mode then
    Error "Pdk.Ops.tube: end caps require triangle or quad connectivity"
  else if Option.is_some cap_group && not end_caps then
    Error "Pdk.Ops.tube: cap group requires end caps"
  else Result.bind (tube_frame orientation rotation_order rotation)
      (fun (radial_axis, pole_axis, tangent_axis) ->
      let point_limit = Sys.max_array_length
      and primitive_limit = min (Sys.max_array_length - 1) Sys.max_string_length in
      let checked_mul left right limit =
        if left = 0 || right <= limit / left then Some (left * right) else None
      and checked_add left right limit =
        if right <= limit - left then Some (left + right) else None in
      let bottom_tip = bottom_radius_scaled = 0.
      and top_tip = top_radius_scaled = 0. in
      let tip_count = (if bottom_tip then 1 else 0) + if top_tip then 1 else 0 in
      let cap_count = if not end_caps then 0 else
          (if bottom_tip then 0 else 1) + if top_tip then 0 else 1 in
      let ring_points = match checked_mul rows columns point_limit with
        | Some value -> Some (value - (tip_count * (columns - 1)))
        | None -> None in
      let duplicate_cap_points = if end_caps && not consolidate_cap_points
        then cap_count * columns else 0 in
      let point_count = Option.bind ring_points (fun count ->
          checked_add count duplicate_cap_points point_limit) in
      let bands = rows - 1 in
      let ordinary_bands = bands - tip_count in
      let ring_curve_count = rows - tip_count in
      let topology_cardinality = match point_count with
        | None -> None
        | Some _ ->
            (match connectivity with
             | Tube_points -> Some (0, 0, 0, 0)
             | Tube_rows ->
                 Option.map (fun vertices -> vertices, columns, 0, 0)
                   (checked_mul rows columns point_limit)
             | Tube_columns ->
                 Option.map (fun vertices -> vertices, ring_curve_count, 0, 0)
                   (checked_mul ring_curve_count columns point_limit)
             | Tube_rows_and_columns ->
                 Option.bind (checked_mul rows columns point_limit)
                   (fun row_vertices ->
                     Option.bind (checked_mul ring_curve_count columns point_limit)
                       (fun column_vertices ->
                         Option.bind (checked_add row_vertices column_vertices
                             point_limit) (fun vertices ->
                           Option.map (fun primitives -> vertices, primitives, 0, 0)
                             (checked_add columns ring_curve_count
                                primitive_limit))))
             | Tube_triangles | Tube_alternating_triangles | Tube_quads ->
                 let triangle_mode = connectivity <> Tube_quads in
                 let ordinary_primitives_per_cell = if triangle_mode then 2 else 1
                 and ordinary_vertices_per_cell = if triangle_mode then 6 else 4 in
                 (match checked_mul ordinary_bands columns primitive_limit with
                  | None -> None
                  | Some ordinary_cells ->
                      let ordinary_primitives = checked_mul ordinary_cells
                          ordinary_primitives_per_cell primitive_limit
                      and tip_primitives = checked_mul tip_count columns
                          primitive_limit
                      and ordinary_vertices = checked_mul ordinary_cells
                          ordinary_vertices_per_cell point_limit
                      and tip_vertices = checked_mul (tip_count * columns) 3
                          point_limit in
                      (match ordinary_primitives, tip_primitives,
                          ordinary_vertices, tip_vertices with
                       | Some ordinary_primitives, Some tip_primitives,
                         Some ordinary_vertices, Some tip_vertices ->
                           Option.bind (checked_add ordinary_primitives
                               tip_primitives primitive_limit)
                             (fun side_primitives ->
                               Option.bind (checked_add ordinary_vertices
                                   tip_vertices point_limit)
                                 (fun side_vertices ->
                                   Option.bind (checked_add side_primitives
                                       cap_count primitive_limit)
                                     (fun primitives ->
                                       Option.map (fun vertices ->
                                           vertices, primitives, side_vertices,
                                           side_primitives)
                                         (checked_add side_vertices
                                            (cap_count * columns)
                                            point_limit))))
                       | _ -> None))) in
      match ring_points, point_count, topology_cardinality with
      | None, _, _ | _, None, _ | _, _, None ->
          Error "Pdk.Ops.tube: output cardinality exceeds OCaml array limits"
      | Some side_point_count, Some point_count,
        Some (vertex_count, primitive_count, side_vertex_count,
          side_primitive_count) ->
          let ring_offsets = Array.make (rows + 1) 0 in
          for row = 0 to rows - 1 do
            let tip = row = 0 && bottom_tip || row = rows - 1 && top_tip in
            ring_offsets.(row + 1) <- ring_offsets.(row)
                + if tip then 1 else columns
          done;
          let bottom_cap_point_base = if end_caps && not consolidate_cap_points
              && not bottom_tip then side_point_count else -1 in
          let top_cap_point_base = if end_caps && not consolidate_cap_points
              && not top_tip then side_point_count
                + if bottom_cap_point_base >= 0 then columns else 0
            else -1 in
          let sine = Array.make columns 0. and cosine = Array.make columns 0.
          and u_parameter = Array.make columns 0.
          and row_radius = Array.make rows 0. and row_height = Array.make rows 0.
          and v_parameter = Array.make rows 0. in
          Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(columns - 1)
            (fun column ->
              if column land 4095 = 0 then Cancel.check_opt cancel;
              let angle = 2. *. Float.pi *. float_of_int column
                  /. float_of_int columns in
              sine.(column) <- sin angle; cosine.(column) <- cos angle;
              u_parameter.(column) <- float_of_int column /. float_of_int columns);
          Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(rows - 1)
            (fun row ->
              if row land 4095 = 0 then Cancel.check_opt cancel;
              let t = float_of_int row /. float_of_int (rows - 1) in
              row_radius.(row) <- if row = 0 then bottom_radius_scaled
                else if row = rows - 1 then top_radius_scaled
                else (bottom_radius_scaled *. (1. -. t))
                  +. (top_radius_scaled *. t);
              row_height.(row) <- height *. (t -. 0.5);
              v_parameter.(row) <- t);
          let normal_scale = Float.max height
              (abs_float (bottom_radius_scaled -. top_radius_scaled)) in
          let scaled_radial = height /. normal_scale
          and scaled_axial = (bottom_radius_scaled -. top_radius_scaled)
              /. normal_scale in
          let normal_length = sqrt ((scaled_radial *. scaled_radial)
              +. (scaled_axial *. scaled_axial)) in
          let side_radial = scaled_radial /. normal_length
          and side_axial = scaled_axial /. normal_length in
          let identity_axes = orientation = Tube_y
              && rotation.x = 0. && rotation.y = 0. && rotation.z = 0. in
          let px = Array.make point_count 0. and py = Array.make point_count 0.
          and pz = Array.make point_count 0. in
          let point_normals = match normal_mode with
            | Tube_point_normals -> Some (Array.make point_count 0.,
                Array.make point_count 0., Array.make point_count 0.)
            | Tube_no_normals | Tube_vertex_normals -> None in
          let point_uv = match uv_attribute, point_mode with
            | Some _, true -> Some (Array.make point_count 0.,
                Array.make point_count 0.)
            | _ -> None in
          let[@inline always] point_of row column =
            let tip = row = 0 && bottom_tip || row = rows - 1 && top_tip in
            ring_offsets.(row) + if tip then 0
              else if column = columns then 0 else column in
          let[@inline always] write_point_normal nx ny nz point row column =
            if row = 0 && bottom_tip then begin
              nx.(point) <- -.pole_axis.x; ny.(point) <- -.pole_axis.y;
              nz.(point) <- -.pole_axis.z
            end else if row = rows - 1 && top_tip then begin
              nx.(point) <- pole_axis.x; ny.(point) <- pole_axis.y;
              nz.(point) <- pole_axis.z
            end else
              let local_x = side_radial *. cosine.(column)
              and local_y = side_axial
              and local_z = side_radial *. sine.(column) in
              if identity_axes then begin
                nx.(point) <- local_x; ny.(point) <- local_y;
                nz.(point) <- local_z
              end else begin
                nx.(point) <- (radial_axis.x *. local_x)
                    +. (pole_axis.x *. local_y) +. (tangent_axis.x *. local_z);
                ny.(point) <- (radial_axis.y *. local_x)
                    +. (pole_axis.y *. local_y) +. (tangent_axis.y *. local_z);
                nz.(point) <- (radial_axis.z *. local_x)
                    +. (pole_axis.z *. local_y) +. (tangent_axis.z *. local_z)
              end in
          let[@inline always] write_side_point point row column =
            let radius = row_radius.(row) and local_y = row_height.(row) in
            let local_x = radius *. cosine.(column)
            and local_z = radius *. sine.(column) in
            let x, y, z = if identity_axes then
                center.x +. local_x, center.y +. local_y, center.z +. local_z
              else
                center.x +. (radial_axis.x *. local_x)
                  +. (pole_axis.x *. local_y) +. (tangent_axis.x *. local_z),
                center.y +. (radial_axis.y *. local_x)
                  +. (pole_axis.y *. local_y) +. (tangent_axis.y *. local_z),
                center.z +. (radial_axis.z *. local_x)
                  +. (pole_axis.z *. local_y) +. (tangent_axis.z *. local_z) in
            if finite x && finite y && finite z then begin
              px.(point) <- x; py.(point) <- y; pz.(point) <- z;
              (match point_normals with
               | Some (nx, ny, nz) ->
                   write_point_normal nx ny nz point row column
               | None -> ());
              (match point_uv with
               | Some (u, v) ->
                   u.(point) <- if row = 0 && bottom_tip
                       || row = rows - 1 && top_tip then 0.5
                     else u_parameter.(column);
                   v.(point) <- v_parameter.(row)
               | None -> ());
              true
            end else false in
          let row_grain = max 1 (grain / columns) in
          let range_count = ((rows - 1) / row_grain) + 1 in
          let errors = Array.make range_count (-1) in
          Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
            (fun range ->
              let first_row = range * row_grain
              and last_row = min rows ((range + 1) * row_grain) in
              for row = first_row to last_row - 1 do
                let tip = row = 0 && bottom_tip || row = rows - 1 && top_tip in
                let count = if tip then 1 else columns in
                for column = 0 to count - 1 do
                  let point = ring_offsets.(row) + column in
                  if point land 4095 = 0 then Cancel.check_opt cancel;
                  if not (write_side_point point row column)
                      && errors.(range) < 0 then errors.(range) <- point
                done
              done);
          let invalid = Array.fold_left (fun first point ->
              if point < 0 then first else if first < 0 || point < first
              then point else first) (-1) errors in
          if invalid >= 0 then Error (Printf.sprintf
              "Pdk.Ops.tube: generated point %d is not finite" invalid)
          else begin
            let copy_cap_points source base sign =
              if base >= 0 then begin
                Array.blit px source px base columns;
                Array.blit py source py base columns;
                Array.blit pz source pz base columns;
                match point_normals with
                | Some (nx, ny, nz) ->
                    for column = 0 to columns - 1 do
                      let point = base + column in
                      nx.(point) <- sign *. pole_axis.x;
                      ny.(point) <- sign *. pole_axis.y;
                      nz.(point) <- sign *. pole_axis.z
                    done
                | None -> ()
              end in
            copy_cap_points ring_offsets.(0) bottom_cap_point_base (-1.);
            copy_cap_points ring_offsets.(rows - 1) top_cap_point_base 1.;
            let vertex_normals = match normal_mode with
              | Tube_vertex_normals -> Some (Array.make vertex_count 0.,
                  Array.make vertex_count 0., Array.make vertex_count 0.)
              | Tube_no_normals | Tube_point_normals -> None in
            let vertex_uv = match uv_attribute, point_mode with
              | Some _, false -> Some (Array.make vertex_count 0.,
                  Array.make vertex_count 0.)
              | _ -> None in
            let[@inline always] write_side_vertex vertex point row column =
              (match vertex_normals with
               | Some (nx, ny, nz) ->
                   let column = if column = columns then 0 else column in
                   let local_x = side_radial *. cosine.(column)
                   and local_y = side_axial
                   and local_z = side_radial *. sine.(column) in
                   if identity_axes then begin
                     nx.(vertex) <- local_x; ny.(vertex) <- local_y;
                     nz.(vertex) <- local_z
                   end else begin
                     nx.(vertex) <- (radial_axis.x *. local_x)
                         +. (pole_axis.x *. local_y)
                         +. (tangent_axis.x *. local_z);
                     ny.(vertex) <- (radial_axis.y *. local_x)
                         +. (pole_axis.y *. local_y)
                         +. (tangent_axis.y *. local_z);
                     nz.(vertex) <- (radial_axis.z *. local_x)
                         +. (pole_axis.z *. local_y)
                         +. (tangent_axis.z *. local_z)
                   end
               | None -> ());
              (match vertex_uv with
               | Some (u, v) ->
                   u.(vertex) <- if column = columns then 1.
                     else u_parameter.(column);
                   v.(vertex) <- v_parameter.(row)
               | None -> ());
              point in
            let topology = match connectivity with
              | Tube_points -> Topology.empty ~point_count
              | Tube_rows | Tube_columns | Tube_rows_and_columns ->
                  let vertex_points = Array.make vertex_count 0
                  and primitive_offsets = Array.make (primitive_count + 1) 0
                  and primitive_kinds = Bytes.make primitive_count '\001' in
                  let row_primitive_count = match connectivity with
                    | Tube_rows | Tube_rows_and_columns -> columns
                    | _ -> 0 in
                  let row_vertex_count = row_primitive_count * rows in
                  Parallel.for_ ~chunk_size:(max 1 (grain / max rows columns))
                    ~start:0 ~finish:(primitive_count - 1) (fun primitive ->
                      if primitive land 1023 = 0 then Cancel.check_opt cancel;
                      if primitive < row_primitive_count then begin
                        let column = primitive and at = primitive * rows in
                        for row = 0 to rows - 1 do
                          let vertex = at + row in
                          vertex_points.(vertex) <- write_side_vertex vertex
                              (point_of row column) row column
                        done
                      end else begin
                        let curve = primitive - row_primitive_count in
                        let row = curve + if bottom_tip then 1 else 0 in
                        let at = row_vertex_count + (curve * columns) in
                        Bytes.set primitive_kinds primitive '\002';
                        for column = 0 to columns - 1 do
                          let vertex = at + column in
                          vertex_points.(vertex) <- write_side_vertex vertex
                              (point_of row column) row column
                        done
                      end);
                  Parallel.for_ ~chunk_size:grain ~start:0 ~finish:primitive_count
                    (fun primitive ->
                      if primitive land 4095 = 0 then Cancel.check_opt cancel;
                      primitive_offsets.(primitive) <-
                        if primitive <= row_primitive_count
                        then primitive * rows
                        else row_vertex_count
                          + ((primitive - row_primitive_count) * columns));
                  Topology.Private.create_validated_owned ~point_count
                    ~vertex_points ~primitive_offsets ~primitive_kinds
              | Tube_triangles | Tube_alternating_triangles | Tube_quads ->
                  let triangle_mode = connectivity <> Tube_quads in
                  let band_primitive_offsets = Array.make (bands + 1) 0
                  and band_vertex_offsets = Array.make (bands + 1) 0 in
                  for band = 0 to bands - 1 do
                    let tip_band = band = 0 && bottom_tip
                        || band = bands - 1 && top_tip in
                    band_primitive_offsets.(band + 1) <-
                      band_primitive_offsets.(band)
                        + (columns * if tip_band || not triangle_mode then 1 else 2);
                    band_vertex_offsets.(band + 1) <-
                      band_vertex_offsets.(band)
                        + (columns * if tip_band then 3
                           else if triangle_mode then 6 else 4)
                  done;
                  let vertex_points = Array.make vertex_count 0
                  and primitive_offsets = Array.make (primitive_count + 1) 0
                  and primitive_kinds = Bytes.make primitive_count '\000' in
                  let[@inline always] set_side vertex point row radial =
                    vertex_points.(vertex) <- write_side_vertex vertex point
                        row radial in
                  Parallel.for_ ~chunk_size:(max 1 (grain / columns)) ~start:0
                    ~finish:(bands - 1) (fun band ->
                      Cancel.check_opt cancel;
                      let bottom_band = band = 0 && bottom_tip
                      and top_band = band = bands - 1 && top_tip in
                      let tip_band = bottom_band || top_band in
                      for column = 0 to columns - 1 do
                      if column land 4095 = 0 then Cancel.check_opt cancel;
                      let next_column = column + 1 in
                      let primitive = band_primitive_offsets.(band)
                          + (column * if tip_band || not triangle_mode then 1 else 2)
                      and at = band_vertex_offsets.(band)
                          + (column * if tip_band then 3
                             else if triangle_mode then 6 else 4) in
                      let a = point_of band column
                      and b = point_of (band + 1) column
                      and c = point_of (band + 1) next_column
                      and d = point_of band next_column in
                      if bottom_band then begin
                        primitive_offsets.(primitive) <- at;
                        set_side at a band column;
                        set_side (at + 1) b (band + 1) column;
                        set_side (at + 2) c (band + 1) next_column
                      end else if top_band then begin
                        primitive_offsets.(primitive) <- at;
                        set_side at a band column;
                        set_side (at + 1) b (band + 1) column;
                        set_side (at + 2) d band next_column
                      end else if not triangle_mode then begin
                        primitive_offsets.(primitive) <- at;
                        set_side at a band column;
                        set_side (at + 1) b (band + 1) column;
                        set_side (at + 2) c (band + 1) next_column;
                        set_side (at + 3) d band next_column
                      end else
                        let alternate = connectivity = Tube_alternating_triangles
                            && ((band + column) land 1 = 1) in
                        primitive_offsets.(primitive) <- at;
                        primitive_offsets.(primitive + 1) <- at + 3;
                        if not alternate then begin
                          set_side at a band column;
                          set_side (at + 1) b (band + 1) column;
                          set_side (at + 2) c (band + 1) next_column;
                          set_side (at + 3) a band column;
                          set_side (at + 4) c (band + 1) next_column;
                          set_side (at + 5) d band next_column
                        end else begin
                          set_side at a band column;
                          set_side (at + 1) b (band + 1) column;
                          set_side (at + 2) d band next_column;
                          set_side (at + 3) b (band + 1) column;
                          set_side (at + 4) c (band + 1) next_column;
                          set_side (at + 5) d band next_column
                        end
                      done);
                  primitive_offsets.(side_primitive_count) <- side_vertex_count;
                  let cap_vertex_base = side_vertex_count in
                  let write_cap_vertex vertex point sign column =
                    vertex_points.(vertex) <- point;
                    (match vertex_normals with
                     | Some (nx, ny, nz) ->
                         nx.(vertex) <- sign *. pole_axis.x;
                         ny.(vertex) <- sign *. pole_axis.y;
                         nz.(vertex) <- sign *. pole_axis.z
                     | None -> ());
                    match vertex_uv with
                    | Some (u, v) ->
                        u.(vertex) <- 0.5 +. (0.5 *. cosine.(column));
                        v.(vertex) <- 0.5 +. (0.5 *. sine.(column))
                    | None -> () in
                  if cap_count > 0 then
                    Parallel.for_ ~chunk_size:grain ~start:0
                      ~finish:((cap_count * columns) - 1) (fun local ->
                        if local land 4095 = 0 then Cancel.check_opt cancel;
                        let cap = local / columns and index = local mod columns in
                        let bottom = not bottom_tip && (cap = 0) in
                        let column = if bottom then index else columns - 1 - index in
                        let base = if bottom then
                            if bottom_cap_point_base >= 0
                            then bottom_cap_point_base else ring_offsets.(0)
                          else if top_cap_point_base >= 0 then top_cap_point_base
                          else ring_offsets.(rows - 1) in
                        write_cap_vertex (cap_vertex_base + local)
                          (base + column) (if bottom then -1. else 1.) column);
                  for cap = 0 to cap_count do
                    primitive_offsets.(side_primitive_count + cap) <-
                      side_vertex_count + (cap * columns)
                  done;
                  Topology.Private.create_validated_owned ~point_count
                    ~vertex_points ~primitive_offsets ~primitive_kinds in
            let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
            let attributes = ref [] in
            (match point_normals with
             | Some (x, y, z) ->
                 let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
                 attributes := (Attribute.create_key_owned
                     (Attribute.normal ~owner:Attribute.Point) values |> get_ok)
                   :: !attributes
             | None -> ());
            (match vertex_normals with
             | Some (x, y, z) ->
                 let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
                 attributes := (Attribute.create_key_owned
                     (Attribute.normal ~owner:Attribute.Vertex) values |> get_ok)
                   :: !attributes
             | None -> ());
            (match uv_attribute, point_uv, vertex_uv with
             | Some name, Some (x, y), None ->
                 let values = Packed.Float2.of_owned ~x ~y |> get_ok in
                 attributes := (Attribute.create_owned ~name ~owner:Attribute.Point
                     (Attribute.Float2 values) |> get_ok) :: !attributes
             | Some name, None, Some (x, y) ->
                 let values = Packed.Float2.of_owned ~x ~y |> get_ok in
                 attributes := (Attribute.create_owned ~name
                     ~owner:Attribute.Vertex (Attribute.Float2 values) |> get_ok)
                   :: !attributes
             | None, None, None -> ()
             | _ -> assert false);
            let groups = match cap_group with
              | None -> []
              | Some name ->
                  let builder = Group.Builder.create ~owner:Group.Primitive
                      ~name primitive_count in
                  for primitive = side_primitive_count to primitive_count - 1 do
                    Group.Builder.set builder primitive true
                  done;
                  [Group.Builder.freeze builder] in
            Geometry.create ~positions ~topology ~attributes:(List.rev !attributes)
              ~groups ()
          end)

type platonic_data = {
  platonic_x : float array;
  platonic_y : float array;
  platonic_z : float array;
  platonic_vertex_points : int array;
  platonic_primitive_offsets : int array;
  platonic_face_nx : float array;
  platonic_face_ny : float array;
  platonic_face_nz : float array;
  platonic_face_sizes : int array;
  platonic_soccer_pentagons : int;
}

let platonic_data ?(soccer_pentagons = 0) raw_points raw_faces =
  let point_count = Array.length raw_points in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  Array.iteri (fun point (px, py, pz) ->
    let length = sqrt ((px *. px) +. (py *. py) +. (pz *. pz)) in
    x.(point) <- px /. length; y.(point) <- py /. length;
    z.(point) <- pz /. length) raw_points;
  let primitive_count = Array.length raw_faces in
  let faces = Array.mapi (fun _primitive source ->
    let face = Array.copy source and count = Array.length source in
    let cx = ref 0. and cy = ref 0. and cz = ref 0. in
    Array.iter (fun point ->
      cx := !cx +. x.(point); cy := !cy +. y.(point);
      cz := !cz +. z.(point)) face;
    let a = face.(0) and b = face.(1) and c = face.(2) in
    let abx = x.(b) -. x.(a) and aby = y.(b) -. y.(a)
    and abz = z.(b) -. z.(a) and acx = x.(c) -. x.(a)
    and acy = y.(c) -. y.(a) and acz = z.(c) -. z.(a) in
    let nx = (aby *. acz) -. (abz *. acy)
    and ny = (abz *. acx) -. (abx *. acz)
    and nz = (abx *. acy) -. (aby *. acx) in
    if (nx *. !cx) +. (ny *. !cy) +. (nz *. !cz) < 0. then
      for left = 0 to (count / 2) - 1 do
        let right = count - 1 - left and value = face.(left) in
        face.(left) <- face.(right); face.(right) <- value
      done;
    face) raw_faces in
  let primitive_offsets = Array.make (primitive_count + 1) 0
  and face_sizes = Array.make primitive_count 0 in
  for primitive = 0 to primitive_count - 1 do
    let size = Array.length faces.(primitive) in
    face_sizes.(primitive) <- size;
    primitive_offsets.(primitive + 1) <- primitive_offsets.(primitive) + size
  done;
  let vertex_points = Array.make primitive_offsets.(primitive_count) 0
  and face_nx = Array.make primitive_count 0.
  and face_ny = Array.make primitive_count 0.
  and face_nz = Array.make primitive_count 0. in
  Array.iteri (fun primitive face ->
    Array.blit face 0 vertex_points primitive_offsets.(primitive)
      (Array.length face);
    let a = face.(0) and b = face.(1) and c = face.(2) in
    let abx = x.(b) -. x.(a) and aby = y.(b) -. y.(a)
    and abz = z.(b) -. z.(a) and acx = x.(c) -. x.(a)
    and acy = y.(c) -. y.(a) and acz = z.(c) -. z.(a) in
    let nx = (aby *. acz) -. (abz *. acy)
    and ny = (abz *. acx) -. (abx *. acz)
    and nz = (abx *. acy) -. (aby *. acx) in
    let length = sqrt ((nx *. nx) +. (ny *. ny) +. (nz *. nz)) in
    face_nx.(primitive) <- nx /. length;
    face_ny.(primitive) <- ny /. length;
    face_nz.(primitive) <- nz /. length) faces;
  { platonic_x = x; platonic_y = y; platonic_z = z;
    platonic_vertex_points = vertex_points;
    platonic_primitive_offsets = primitive_offsets;
    platonic_face_nx = face_nx; platonic_face_ny = face_ny;
    platonic_face_nz = face_nz; platonic_face_sizes = face_sizes;
    platonic_soccer_pentagons = soccer_pentagons }

let platonic_tetrahedron_data = platonic_data [|
    1., 1., 1.; -1., -1., 1.; -1., 1., -1.; 1., -1., -1.
  |] [|[|0;2;1|]; [|0;1;3|]; [|0;3;2|]; [|1;2;3|]|]

let platonic_cube_data = platonic_data [|
    -1., -1., -1.; 1., -1., -1.; 1., 1., -1.; -1., 1., -1.;
    -1., -1., 1.; 1., -1., 1.; 1., 1., 1.; -1., 1., 1.
  |] [|
    [|0;1;2;3|]; [|4;7;6;5|]; [|0;4;5;1|];
    [|1;5;6;2|]; [|2;6;7;3|]; [|3;7;4;0|]
  |]

let platonic_octahedron_data = platonic_data [|
    1., 0., 0.; -1., 0., 0.; 0., 1., 0.;
    0., -1., 0.; 0., 0., 1.; 0., 0., -1.
  |] [|
    [|0;2;4|]; [|4;2;1|]; [|1;2;5|]; [|5;2;0|];
    [|4;3;0|]; [|1;3;4|]; [|5;3;1|]; [|0;3;5|]
  |]

let platonic_icosahedron_points =
  let phi = (1. +. sqrt 5.) /. 2. in [|
    -1., phi, 0.; 1., phi, 0.; -1., -.phi, 0.; 1., -.phi, 0.;
    0., -1., phi; 0., 1., phi; 0., -1., -.phi; 0., 1., -.phi;
    phi, 0., -1.; phi, 0., 1.; -.phi, 0., -1.; -.phi, 0., 1.
  |]

let platonic_icosahedron_faces = [|
  [|0;11;5|]; [|0;5;1|]; [|0;1;7|]; [|0;7;10|]; [|0;10;11|];
  [|1;5;9|]; [|5;11;4|]; [|11;10;2|]; [|10;7;6|]; [|7;1;8|];
  [|3;9;4|]; [|3;4;2|]; [|3;2;6|]; [|3;6;8|]; [|3;8;9|];
  [|4;9;5|]; [|2;4;11|]; [|6;2;10|]; [|8;6;7|]; [|9;8;1|]
|]

let platonic_icosahedron_data =
  platonic_data platonic_icosahedron_points platonic_icosahedron_faces

let platonic_dodecahedron_data =
  let phi = (1. +. sqrt 5.) /. 2. and inv = 2. /. (1. +. sqrt 5.) in
  platonic_data [|
    1., 1., 1.; 1., 1., -1.; 1., -1., 1.; 1., -1., -1.;
    -1., 1., 1.; -1., 1., -1.; -1., -1., 1.; -1., -1., -1.;
    0., inv, phi; 0., inv, -.phi; 0., -.inv, phi; 0., -.inv, -.phi;
    inv, phi, 0.; inv, -.phi, 0.; -.inv, phi, 0.; -.inv, -.phi, 0.;
    phi, 0., inv; phi, 0., -.inv; -.phi, 0., inv; -.phi, 0., -.inv
  |] [|
    [|0;8;10;2;16|]; [|0;16;17;1;12|]; [|0;12;14;4;8|];
    [|8;4;18;6;10|]; [|10;6;15;13;2|]; [|2;13;3;17;16|];
    [|1;9;5;14;12|]; [|1;17;3;11;9|]; [|4;14;5;19;18|];
    [|6;18;19;7;15|]; [|3;13;15;7;11|]; [|5;9;11;7;19|]
  |]

let platonic_soccer_ball_data =
  let directed = Array.make (12 * 12) (-1)
  and points = Array.make 60 (0., 0., 0.) and count = ref 0 in
  let ensure a b =
    let key = (a * 12) + b in
    if directed.(key) < 0 then begin
      let ax, ay, az = platonic_icosahedron_points.(a)
      and bx, by, bz = platonic_icosahedron_points.(b) in
      directed.(key) <- !count;
      points.(!count) <- ((2. *. ax +. bx) /. 3.,
        (2. *. ay +. by) /. 3., (2. *. az +. bz) /. 3.);
      incr count
    end;
    directed.(key) in
  Array.iter (fun face ->
    let a = face.(0) and b = face.(1) and c = face.(2) in
    ignore (ensure a b); ignore (ensure b a);
    ignore (ensure b c); ignore (ensure c b);
    ignore (ensure c a); ignore (ensure a c)) platonic_icosahedron_faces;
  assert (!count = 60);
  let successor = Array.make (12 * 12) (-1) in
  Array.iter (fun face ->
    let a = face.(0) and b = face.(1) and c = face.(2) in
    successor.((a * 12) + b) <- c;
    successor.((b * 12) + c) <- a;
    successor.((c * 12) + a) <- b) platonic_icosahedron_faces;
  let faces = Array.init 32 (fun face ->
    if face < 12 then begin
      let start = ref (-1) in
      for neighbor = 0 to 11 do
        if !start < 0 && directed.((face * 12) + neighbor) >= 0 then
          start := neighbor
      done;
      let neighbor = ref !start in
      Array.init 5 (fun _ ->
        let point = directed.((face * 12) + !neighbor) in
        neighbor := successor.((face * 12) + !neighbor);
        point)
    end else begin
      let triangle = platonic_icosahedron_faces.(face - 12) in
      let a = triangle.(0) and b = triangle.(1) and c = triangle.(2) in
      [|ensure a b; ensure b a; ensure b c; ensure c b; ensure c a; ensure a c|]
    end) in
  platonic_data ~soccer_pentagons:12 points faces

let platonic ?cancel ?(kind = Platonic_tetrahedron)
    ?(normals = Platonic_point_normals) ?(orientation = Platonic_y)
    ?(center = Vec3.zero) ?(rotation = Vec3.zero)
    ?(rotation_order = Platonic_xyz) ?face_groups ~radius () =
  Cancel.check_opt cancel;
  if not (finite radius && radius > 0.) then
    Error "Pdk.Ops.platonic: radius must be finite and positive"
  else if not (finite center.x && finite center.y && finite center.z
      && finite rotation.x && finite rotation.y && finite rotation.z) then
    Error "Pdk.Ops.platonic: center and rotation must be finite"
  else if (match face_groups with
      | Some name -> String.trim name = "" | None -> false) then
    Error "Pdk.Ops.platonic: face group prefix must be non-empty"
  else
    let tube_orientation = match orientation with
      | Platonic_x -> Tube_x | Platonic_y -> Tube_y | Platonic_z -> Tube_z
      | Platonic_axis axis -> Tube_axis axis in
    let tube_rotation_order = match rotation_order with
      | Platonic_xyz -> Tube_xyz | Platonic_xzy -> Tube_xzy
      | Platonic_yxz -> Tube_yxz | Platonic_yzx -> Tube_yzx
      | Platonic_zxy -> Tube_zxy | Platonic_zyx -> Tube_zyx in
    Result.bind (tube_frame tube_orientation tube_rotation_order rotation)
      (fun (x_axis, y_axis, z_axis) ->
      let data = match kind with
        | Platonic_tetrahedron -> platonic_tetrahedron_data
        | Platonic_cube -> platonic_cube_data
        | Platonic_octahedron -> platonic_octahedron_data
        | Platonic_icosahedron -> platonic_icosahedron_data
        | Platonic_dodecahedron -> platonic_dodecahedron_data
        | Platonic_soccer_ball -> platonic_soccer_ball_data in
      let point_count = Array.length data.platonic_x
      and vertex_count = Array.length data.platonic_vertex_points
      and primitive_count = Array.length data.platonic_face_sizes in
      let px = Array.make point_count 0. and py = Array.make point_count 0.
      and pz = Array.make point_count 0. in
      let point_normal = match normals with
        | Platonic_point_normals -> Some (Array.make point_count 0.,
            Array.make point_count 0., Array.make point_count 0.)
        | Platonic_no_normals | Platonic_vertex_normals -> None in
      let identity_axes = orientation = Platonic_y
          && rotation.x = 0. && rotation.y = 0. && rotation.z = 0. in
      let invalid = ref (-1) in
      for point = 0 to point_count - 1 do
        if point land 15 = 0 then Cancel.check_opt cancel;
        let x = data.platonic_x.(point) and y = data.platonic_y.(point)
        and z = data.platonic_z.(point) in
        let tx, ty, tz = if identity_axes then
            center.x +. (radius *. x), center.y +. (radius *. y),
            center.z +. (radius *. z)
          else
            center.x +. (radius *. ((x_axis.x *. x) +. (y_axis.x *. y)
              +. (z_axis.x *. z))),
            center.y +. (radius *. ((x_axis.y *. x) +. (y_axis.y *. y)
              +. (z_axis.y *. z))),
            center.z +. (radius *. ((x_axis.z *. x) +. (y_axis.z *. y)
              +. (z_axis.z *. z))) in
        if finite tx && finite ty && finite tz then begin
          px.(point) <- tx; py.(point) <- ty; pz.(point) <- tz;
          match point_normal with
          | None -> ()
          | Some (nx, ny, nz) when identity_axes ->
              nx.(point) <- x; ny.(point) <- y; nz.(point) <- z
          | Some (nx, ny, nz) ->
              nx.(point) <- (x_axis.x *. x) +. (y_axis.x *. y)
                  +. (z_axis.x *. z);
              ny.(point) <- (x_axis.y *. x) +. (y_axis.y *. y)
                  +. (z_axis.y *. z);
              nz.(point) <- (x_axis.z *. x) +. (y_axis.z *. y)
                  +. (z_axis.z *. z)
        end else if !invalid < 0 then invalid := point
      done;
      if !invalid >= 0 then Error (Printf.sprintf
          "Pdk.Ops.platonic: generated point %d is not finite" !invalid)
      else begin
        let topology = Topology.Private.create_validated_owned ~point_count
            ~vertex_points:(Array.copy data.platonic_vertex_points)
            ~primitive_offsets:(Array.copy data.platonic_primitive_offsets)
            ~primitive_kinds:(Bytes.make primitive_count '\000') in
        let attributes = ref [] in
        (match point_normal with
         | Some (x, y, z) ->
             let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
             attributes := (Attribute.create_key_owned
                 (Attribute.normal ~owner:Attribute.Point) values |> get_ok)
               :: !attributes
         | None -> ());
        (match normals with
         | Platonic_vertex_normals ->
             let nx = Array.make vertex_count 0.
             and ny = Array.make vertex_count 0.
             and nz = Array.make vertex_count 0. in
             for primitive = 0 to primitive_count - 1 do
               let x = data.platonic_face_nx.(primitive)
               and y = data.platonic_face_ny.(primitive)
               and z = data.platonic_face_nz.(primitive) in
               let tx, ty, tz = if identity_axes then x, y, z else
                   (x_axis.x *. x) +. (y_axis.x *. y) +. (z_axis.x *. z),
                   (x_axis.y *. x) +. (y_axis.y *. y) +. (z_axis.y *. z),
                   (x_axis.z *. x) +. (y_axis.z *. y) +. (z_axis.z *. z) in
               for vertex = data.platonic_primitive_offsets.(primitive)
                   to data.platonic_primitive_offsets.(primitive + 1) - 1 do
                 nx.(vertex) <- tx; ny.(vertex) <- ty; nz.(vertex) <- tz
               done
             done;
             let values = Packed.Float3.Private.of_owned_exn ~x:nx ~y:ny ~z:nz in
             attributes := (Attribute.create_key_owned
                 (Attribute.normal ~owner:Attribute.Vertex) values |> get_ok)
               :: !attributes
         | Platonic_no_normals | Platonic_point_normals -> ());
        if kind = Platonic_soccer_ball then begin
          let x = Array.make primitive_count 1.
          and y = Array.make primitive_count 1.
          and z = Array.make primitive_count 1. in
          for primitive = 0 to data.platonic_soccer_pentagons - 1 do
            x.(primitive) <- 0.; y.(primitive) <- 0.; z.(primitive) <- 0.
          done;
          let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
          attributes := (Attribute.create_owned ~owner:Attribute.Primitive
              ~name:"Cd" (Attribute.Float3 values) |> get_ok) :: !attributes
        end;
        let groups = match face_groups with
          | None -> []
          | Some prefix ->
              let group size suffix =
                if not (Array.exists (( = ) size) data.platonic_face_sizes)
                then None
                else
                  let builder = Group.Builder.create ~owner:Group.Primitive
                      ~name:(prefix ^ "_" ^ suffix) primitive_count in
                  Array.iteri (fun primitive actual ->
                    if actual = size then Group.Builder.set builder primitive true)
                    data.platonic_face_sizes;
                  Some (Group.Builder.freeze builder) in
              [group 3 "triangles"; group 4 "quads";
               group 5 "pentagons"; group 6 "hexagons"]
              |> List.filter_map Fun.id in
        let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
        Geometry.create ~positions ~topology ~attributes:(List.rev !attributes)
          ~groups ()
      end)

let spiral ?cancel ?grain ?extent ?radius ?height_ramp ?radius_scale
    ?radius_ramp ?direction ?start_angle ?divisions ?uniform_angle
    ?spiral_count ?orientation ?center ?rotation ?rotation_order ?uniform_scale
    ?angle_attribute ?x_axis_attribute ?y_axis_attribute ?tangent_attribute
    ?orient_attribute ?distance_attribute () =
  try Spiral.generate ?cancel ?grain ?extent ?radius ?height_ramp ?radius_scale
      ?radius_ramp ?direction ?start_angle ?divisions ?uniform_angle
      ?spiral_count ?orientation ?center ?rotation ?rotation_order ?uniform_scale
      ?angle_attribute ?x_axis_attribute ?y_axis_attribute ?tangent_attribute
      ?orient_attribute ?distance_attribute ()
  with Spiral.Invalid_spiral message -> Error message

let same_attribute_schema left right =
  Attribute.owner left = Attribute.owner right
  && String.equal (Attribute.name left) (Attribute.name right)
  && String.equal (Attribute.kind_name left) (Attribute.kind_name right)

let find_matching attribute geometry =
  Geometry.attributes geometry
  |> List.find_opt (same_attribute_schema attribute)

let same_group_schema left right =
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)

let find_matching_group group geometry =
  Geometry.groups geometry |> List.find_opt (same_group_schema group)

let find_matching_edge_group group geometry =
  Geometry.find_edge_group (Edge_group.name group) geometry

let concat_float2 attributes =
  let views = Array.map (fun attribute -> match Attribute.Private.storage attribute with
    | Attribute.Float2 values -> Packed.Float2.Private.view values
    | _ -> assert false) attributes in
  Packed.Float2.of_owned ~x:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float2.Private.x) views)))
    ~y:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float2.Private.y) views)))
  |> get_ok

let concat_float3 attributes =
  let views = Array.map (fun attribute -> match Attribute.Private.storage attribute with
    | Attribute.Float3 values -> Packed.Float3.Private.view values
    | _ -> assert false) attributes in
  Packed.Float3.Private.of_owned_exn
    ~x:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float3.Private.x) views)))
    ~y:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float3.Private.y) views)))
    ~z:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float3.Private.z) views)))

let concat_float4 attributes =
  let views = Array.map (fun attribute -> match Attribute.Private.storage attribute with
    | Attribute.Float4 values -> Packed.Float4.Private.view values
    | _ -> assert false) attributes in
  Packed.Float4.of_owned
    ~x:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float4.Private.x) views)))
    ~y:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float4.Private.y) views)))
    ~z:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float4.Private.z) views)))
    ~w:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float4.Private.w) views)))
  |> get_ok

let concatenate_attribute template attributes =
  let storage = match Attribute.Private.storage template with
    | Attribute.Float _ -> Attribute.Float (Array.concat (Array.to_list
        (Array.map (fun a -> match Attribute.Private.storage a with Attribute.Float x -> x | _ -> assert false) attributes)))
    | Attribute.Int _ -> Attribute.Int (Array.concat (Array.to_list
        (Array.map (fun a -> match Attribute.Private.storage a with Attribute.Int x -> x | _ -> assert false) attributes)))
    | Attribute.Text _ -> Attribute.Text (Array.concat (Array.to_list
        (Array.map (fun a -> match Attribute.Private.storage a with Attribute.Text x -> x | _ -> assert false) attributes)))
    | Attribute.Float2 _ -> Attribute.Float2 (concat_float2 attributes)
    | Attribute.Float3 _ -> Attribute.Float3 (concat_float3 attributes)
    | Attribute.Float4 _ -> Attribute.Float4 (concat_float4 attributes)
    | Attribute.Int_array _ -> Attribute.Int_array (Ragged_ops.concat_int
        (Array.map (fun attribute -> match Attribute.Private.storage attribute with
          | Attribute.Int_array values -> values | _ -> assert false) attributes))
    | Attribute.Float_array _ -> Attribute.Float_array (Ragged_ops.concat_float
        (Array.map (fun attribute -> match Attribute.Private.storage attribute with
          | Attribute.Float_array values -> values | _ -> assert false) attributes)) in
  Attribute.create_owned ~name:(Attribute.name template)
    ~owner:(Attribute.owner template) storage

let merge ?cancel ?(grain = 16_384) geometries =
  if grain <= 0 then invalid_arg "Pdk.Ops.merge: grain must be positive";
  match geometries with
  | [] -> Ok (points [||])
  | first :: _ ->
      let first_attributes = Geometry.attributes first in
      let first_groups = Geometry.groups first in
      let first_edge_groups = Geometry.edge_groups first in
      let exact_schema geometry =
        let attributes = Geometry.attributes geometry in
        List.length attributes = List.length first_attributes
        && List.for_all (fun template -> find_matching template geometry <> None)
             first_attributes in
      let exact_group_schema geometry =
        let groups = Geometry.groups geometry in
        List.length groups = List.length first_groups
        && List.for_all (fun template -> find_matching_group template geometry <> None)
             first_groups in
      let exact_edge_group_schema geometry =
        let groups = Geometry.edge_groups geometry in
        List.length groups = List.length first_edge_groups
        && List.for_all (fun template ->
          find_matching_edge_group template geometry <> None) first_edge_groups in
      if not (List.for_all exact_schema geometries) then
        Error "Pdk.Ops.merge: attribute schemas must match exactly"
      else if not (List.for_all exact_group_schema geometries) then
        Error "Pdk.Ops.merge: group schemas must match exactly"
      else if not (List.for_all exact_edge_group_schema geometries) then
        Error "Pdk.Ops.merge: edge group schemas must match exactly"
      else if List.exists (fun attribute -> Attribute.owner attribute = Attribute.Detail)
          first_attributes then
        Error "Pdk.Ops.merge: detail attributes need an explicit merge policy"
      else
        let point_count = List.fold_left (fun n g -> n + Geometry.point_count g) 0 geometries
        and vertex_count = List.fold_left (fun n g -> n + Geometry.vertex_count g) 0 geometries
        and primitive_count = List.fold_left (fun n g -> n + Geometry.primitive_count g) 0 geometries in
        let px = Array.make point_count 0. and py = Array.make point_count 0.
        and pz = Array.make point_count 0. in
        let vertex_points = Array.make vertex_count 0
        and primitive_offsets = Array.make (primitive_count + 1) 0
        and primitive_kinds = Bytes.make primitive_count '\000' in
        let point_at = ref 0 and vertex_at = ref 0 and primitive_at = ref 0 in
        List.iter (fun geometry ->
          Cancel.check_opt cancel;
          let positions = Packed.Float3.Private.view (Geometry.positions geometry)
          and topology = Topology.Private.view (Geometry.topology geometry) in
          let points_here = Geometry.point_count geometry
          and vertices_here = Geometry.vertex_count geometry
          and primitives_here = Geometry.primitive_count geometry in
          Array.blit positions.x 0 px !point_at points_here;
          Array.blit positions.y 0 py !point_at points_here;
          Array.blit positions.z 0 pz !point_at points_here;
          let point_offset = !point_at and vertex_offset = !vertex_at
          and primitive_offset = !primitive_at in
          if vertices_here > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(vertices_here - 1) (fun index ->
                if index land 16383 = 0 then Cancel.check_opt cancel;
                vertex_points.(vertex_offset + index) <-
                  topology.vertex_points.(index) + point_offset);
          if primitives_here > 0 then Parallel.for_ ~chunk_size:grain ~start:1
              ~finish:primitives_here (fun index ->
                if index land 16383 = 0 then Cancel.check_opt cancel;
                primitive_offsets.(primitive_offset + index) <-
                  topology.primitive_offsets.(index) + vertex_offset);
          Bytes.blit topology.primitive_kinds 0 primitive_kinds !primitive_at primitives_here;
          point_at := !point_at + points_here;
          vertex_at := !vertex_at + vertices_here;
          primitive_at := !primitive_at + primitives_here) geometries;
        let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
        let topology = Topology.Private.create_validated_owned ~point_count
            ~vertex_points ~primitive_offsets ~primitive_kinds in
        let topology_result = Ok topology in
        Result.bind topology_result (fun topology ->
          let rec build result = function
            | [] -> Ok (List.rev result)
            | template :: rest ->
                let values = Array.of_list (List.map (fun geometry ->
                  Option.get (find_matching template geometry)) geometries) in
                Result.bind (concatenate_attribute template values)
                  (fun attribute -> build (attribute :: result) rest) in
          Result.bind (build [] first_attributes) (fun attributes ->
            let owner_count geometry = function
              | Group.Point -> Geometry.point_count geometry
              | Group.Vertex -> Geometry.vertex_count geometry
              | Group.Primitive -> Geometry.primitive_count geometry in
            let groups = List.map (fun template ->
              let total = List.fold_left (fun count geometry ->
                count + owner_count geometry (Group.owner template)) 0 geometries in
              let builder = Group.Builder.create ~owner:(Group.owner template)
                  ~name:(Group.name template) total in
              let offset = ref 0 in
              let sources = List.map (fun geometry ->
                let group = Option.get (find_matching_group template geometry) in
                Group.iter (fun index -> Group.Builder.set builder (!offset + index) true) group;
                let source_offset = !offset in
                offset := !offset + owner_count geometry (Group.owner template);
                source_offset, group) geometries in
              let target = Group.Builder.freeze builder in
              if not (List.exists (fun (_, group) -> Group.is_ordered group) sources)
              then target
              else begin
                let order = Array.make (Group.cardinality target) 0
                and output = ref 0 in
                List.iter (fun (source_offset, group) ->
                  Group.iter_ordered (fun element ->
                    order.(!output) <- source_offset + element;
                    incr output) group) sources;
                Group.Private.with_owned_order order target
              end) first_groups in
            let edge_groups = match first_edge_groups with
              | [] -> []
              | templates ->
                  let target_index = Topology_index.create ?cancel topology in
                  List.map (fun template ->
                    let builder = Edge_group.Builder.create ~topology
                        ~index:target_index ~name:(Edge_group.name template) in
                    let point_offset = ref 0 in
                    List.iter (fun geometry ->
                      let source_index = Topology_index.create ?cancel
                          (Geometry.topology geometry) in
                      let group = Option.get
                          (find_matching_edge_group template geometry) in
                      Edge_group.iter (fun edge ->
                        let a, b = Topology_index.edge_points source_index edge in
                        match Topology_index.find_edge target_index
                            ~a:(a + !point_offset) ~b:(b + !point_offset) with
                        | None -> ()
                        | Some target -> Edge_group.Builder.set builder target true)
                        group;
                      point_offset := !point_offset + Geometry.point_count geometry)
                      geometries;
                    Edge_group.Builder.freeze builder) templates in
            Geometry.create ~positions ~topology ~attributes ~groups ~edge_groups ()))

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

let edge_collapse ?cancel ?(grain = 16_384) ?edges
    ?connectivity_attribute ?(position = Average_position)
    ?(remove_degenerate_primitives = true)
    ?(recompute_point_normals = true) geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.edge_collapse: grain must be positive";
  let topology_value = Geometry.topology geometry in
  let index_value = Topology_index.create ?cancel topology_value in
  let index = Topology_index.Private.view index_value in
  let edge_count = Array.length index.edge_a
  and point_count = Geometry.point_count geometry in
  let selected edge = match edges with
    | None -> true
    | Some group -> Edge_group.mem edge group in
  let invalid_selection = match edges with
    | Some group when Edge_group.topology_data_id group
        <> Topology.data_id topology_value ->
        Some "edge selection belongs to a different topology"
    | Some group when Edge_group.length group <> edge_count ->
        Some "edge selection length does not match topology edge count"
    | None | Some _ -> None in
  match invalid_selection with
  | Some message -> Error ("Pdk.Ops.edge_collapse: " ^ message)
  | None ->
      let connectivity = match connectivity_attribute with
        | None -> Ok None
        | Some name when String.trim name = "" ->
            Error "Pdk.Ops.edge_collapse: connectivity attribute name must not be empty"
        | Some name ->
            (match Geometry.find_attribute ~owner:Attribute.Point name geometry with
             | None -> Error (Printf.sprintf
                 "Pdk.Ops.edge_collapse: point connectivity attribute %S is missing"
                 name)
             | Some attribute -> Ok (Some attribute)) in
      Result.bind connectivity (fun connectivity ->
        let same_ragged offsets values equal left right =
          let left_first = offsets.(left) and left_last = offsets.(left + 1)
          and right_first = offsets.(right) and right_last = offsets.(right + 1) in
          let length = left_last - left_first in
          if length <> right_last - right_first then false
          else begin
            let local = ref 0 and same = ref true in
            while !same && !local < length do
              same := equal values.(left_first + !local)
                  values.(right_first + !local);
              incr local
            done;
            !same
          end in
        let same_connectivity = match connectivity with
          | None -> fun _ _ -> true
          | Some attribute ->
              (match Attribute.Private.storage attribute with
               | Attribute.Float values -> fun a b -> values.(a) = values.(b)
               | Attribute.Int values -> fun a b -> values.(a) = values.(b)
               | Attribute.Text values -> fun a b -> String.equal values.(a) values.(b)
               | Attribute.Float2 values ->
                   let values = Packed.Float2.Private.view values in
                   fun a b -> values.x.(a) = values.x.(b)
                     && values.y.(a) = values.y.(b)
               | Attribute.Float3 values ->
                   let values = Packed.Float3.Private.view values in
                   fun a b -> values.x.(a) = values.x.(b)
                     && values.y.(a) = values.y.(b)
                     && values.z.(a) = values.z.(b)
               | Attribute.Float4 values ->
                   let values = Packed.Float4.Private.view values in
                   fun a b -> values.x.(a) = values.x.(b)
                     && values.y.(a) = values.y.(b)
                     && values.z.(a) = values.z.(b)
                     && values.w.(a) = values.w.(b)
               | Attribute.Int_array values ->
                   let values = Packed.Int_array.Private.view values in
                   fun a b -> same_ragged values.offsets values.values ( = ) a b
               | Attribute.Float_array values ->
                   let values = Packed.Float_array.Private.view values in
                   fun a b -> same_ragged values.offsets values.values ( = ) a b) in
        let parent = Array.init point_count Fun.id
        and rank = Bytes.make point_count '\000' in
        let rec find point =
          let ancestor = parent.(point) in
          if ancestor = point then point
          else begin
            let root = find ancestor in
            parent.(point) <- root;
            root
          end in
        let union left right =
          let left_root = find left and right_root = find right in
          if left_root = right_root then false
          else begin
            let left_rank = Char.code (Bytes.unsafe_get rank left_root)
            and right_rank = Char.code (Bytes.unsafe_get rank right_root) in
            if left_rank < right_rank then parent.(left_root) <- right_root
            else if right_rank < left_rank then parent.(right_root) <- left_root
            else begin
              parent.(right_root) <- left_root;
              Bytes.unsafe_set rank left_root (Char.chr (left_rank + 1))
            end;
            true
          end in
        let merged = ref 0 and selected_self_edge = ref false in
        for edge = 0 to edge_count - 1 do
          if edge land 4095 = 0 then Cancel.check_opt cancel;
          if selected edge then begin
            let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
            if a = b then selected_self_edge := true
            else if same_connectivity a b then begin
              if union a b then incr merged
            end
          end
        done;
        if !merged = 0 then
          if !selected_self_edge && remove_degenerate_primitives then
            Fuse_cleanup.apply ?cancel ~grain ~remove_degenerate_primitives:true
              ~remove_unused_points_from_degenerate_primitives:true
              ~remove_all_unused_points:false geometry
          else Ok geometry
        else begin
          let root_to_cluster = Array.make point_count (-1)
          and of_point = Array.make point_count 0
          and cluster_count = ref 0 in
          for point = 0 to point_count - 1 do
            let root = find point in
            if root_to_cluster.(root) < 0 then begin
              root_to_cluster.(root) <- !cluster_count;
              incr cluster_count
            end;
            of_point.(point) <- root_to_cluster.(root)
          done;
          let sizes = Array.make !cluster_count 0 in
          for point = 0 to point_count - 1 do
            sizes.(of_point.(point)) <- sizes.(of_point.(point)) + 1
          done;
          let offsets = Array.make (!cluster_count + 1) 0 in
          for cluster = 0 to !cluster_count - 1 do
            offsets.(cluster + 1) <- offsets.(cluster) + sizes.(cluster)
          done;
          let members = Array.make point_count 0
          and cursors = Array.copy offsets in
          for point = 0 to point_count - 1 do
            let cluster = of_point.(point) in
            let slot = cursors.(cluster) in
            members.(slot) <- point;
            cursors.(cluster) <- slot + 1
          done;
          let representatives = Array.init !cluster_count (fun cluster ->
            members.(offsets.(cluster))) in
          let clusters : Point_clusters.clusters = {
            count = !cluster_count; of_point; offsets; members;
            representatives;
          } in
          let had_point_normals = Geometry.find_attribute
              ~owner:Attribute.Point "N" geometry <> None in
          let source_edge_groups = Geometry.edge_groups geometry in
          let result = Fuse_reduce.apply ?cancel ~grain
              ~position ~attributes:Keep_first
              ~attribute_rules:[] ~group_rules:[] ~compact:true ~rewire:true
              ~remap_edge_groups:false
              clusters geometry
            |> fun reduced -> Result.bind reduced (fun output ->
                 Fuse_cleanup.apply_with_mapping ?cancel ~grain
                   ~remove_degenerate_primitives
                   ~remove_unused_points_from_degenerate_primitives:
                     remove_degenerate_primitives
                   ~remove_all_unused_points:false output)
            |> fun cleaned -> Result.bind cleaned (fun (output, fused_to_output) ->
                 match source_edge_groups with
                 | [] -> Ok output
                 | groups ->
                     let target_topology = Geometry.topology output in
                     let target_index = Topology_index.create ?cancel
                         target_topology in
                     let source_to_output = Array.init point_count (fun point ->
                       let fused = clusters.of_point.(point) in
                       if fused < 0 || fused >= Array.length fused_to_output
                       then -1 else fused_to_output.(fused)) in
                     let rec remap output = function
                       | [] -> Ok output
                       | group :: rest ->
                           Result.bind (Edge_group.remap ?cancel
                             ~source_index:index_value ~target_topology
                             ~target_index ~point_map:source_to_output group)
                             (fun group ->
                               Result.bind (Geometry.with_edge_group group output)
                                 (fun output -> remap output rest)) in
                     remap output groups)
            |> Result.map (fun output ->
                 Geometry.without_attribute ~owner:Attribute.Point "N" output
                 |> Geometry.without_attribute ~owner:Attribute.Vertex "N") in
          if not recompute_point_normals || not had_point_normals then result
          else Result.bind result (fun output ->
            Deform.normals ?cancel ~grain output)
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

let select_array ?cancel ?(grain = 16_384) mapping source =
  let length = Array.length mapping in
  if length = 0 then [||]
  else begin
    let output = Array.make length source.(mapping.(0)) in
    Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(length - 1) (fun i ->
      if i land 4095 = 0 then Cancel.check_opt cancel;
      output.(i) <- source.(mapping.(i)));
    output
  end

let remap_attribute ?cancel ~grain vertex_map primitive_map attribute =
  let mapping = match Attribute.owner attribute with
    | Attribute.Point | Attribute.Detail -> None
    | Attribute.Vertex -> Some vertex_map
    | Attribute.Primitive -> Some primitive_map in
  match mapping with
  | None -> Ok attribute
  | Some mapping ->
      let storage = match Attribute.Private.storage attribute with
        | Attribute.Float values ->
            Attribute.Float (select_array ?cancel ~grain mapping values)
        | Attribute.Int values ->
            Attribute.Int (select_array ?cancel ~grain mapping values)
        | Attribute.Text values ->
            Attribute.Text (select_array ?cancel ~grain mapping values)
        | Attribute.Float2 values ->
            let view = Packed.Float2.Private.view values in
            Attribute.Float2 (Packed.Float2.of_owned
              ~x:(select_array ?cancel ~grain mapping view.x)
              ~y:(select_array ?cancel ~grain mapping view.y) |> get_ok)
        | Attribute.Float3 values ->
            let view = Packed.Float3.Private.view values in
            Attribute.Float3 (Packed.Float3.Private.of_owned_exn
              ~x:(select_array ?cancel ~grain mapping view.x)
              ~y:(select_array ?cancel ~grain mapping view.y)
              ~z:(select_array ?cancel ~grain mapping view.z))
        | Attribute.Float4 values ->
            let view = Packed.Float4.Private.view values in
            Attribute.Float4 (Packed.Float4.of_owned
              ~x:(select_array ?cancel ~grain mapping view.x)
              ~y:(select_array ?cancel ~grain mapping view.y)
              ~z:(select_array ?cancel ~grain mapping view.z)
              ~w:(select_array ?cancel ~grain mapping view.w)
              |> get_ok)
        | Attribute.Int_array values ->
            Attribute.Int_array (Ragged_ops.remap_int ?cancel ~grain mapping values)
        | Attribute.Float_array values ->
            Attribute.Float_array
              (Ragged_ops.remap_float ?cancel ~grain mapping values) in
      Attribute.create_owned ~name:(Attribute.name attribute)
        ~owner:(Attribute.owner attribute) storage

let remap_group ~grain vertex_map primitive_map group =
  let mapping = match Group.owner group with
    | Group.Point -> None
    | Group.Vertex -> Some vertex_map
    | Group.Primitive -> Some primitive_map in
  match mapping with
  | None -> group
  | Some mapping ->
      let target = Group.init ~grain ~owner:(Group.owner group)
          ~name:(Group.name group) (Array.length mapping)
          (fun index -> Group.mem mapping.(index) group) in
      Group.Private.remap_order ~source:group ~source_of_target:mapping target

let remap_edge_groups ?cancel ~source_topology ~target_topology ~point_map groups =
  match groups with
  | [] -> []
  | groups ->
      let source_index = Topology_index.create ?cancel source_topology
      and target_index = Topology_index.create ?cancel target_topology in
      List.map (fun group -> Edge_group.remap ?cancel ~source_index
        ~target_topology ~target_index ~point_map group |> get_ok) groups

let remap_edge_groups_identity ?cancel ~source_topology ~target_topology
    ~point_count groups =
  remap_edge_groups ?cancel ~source_topology ~target_topology
    ~point_map:(Array.init point_count Fun.id) groups

let triangulate ?cancel ?(grain = 16_384) ?primitives geometry =
  try
  if grain <= 0 then invalid_arg "Pdk.Ops.triangulate: grain must be positive";
  Cancel.check_opt cancel;
  let topology = Geometry.topology geometry in
  let primitive_count = Topology.primitive_count topology in
  (match primitives with
   | Some group when Group.owner group <> Group.Primitive ->
       invalid_arg "Pdk.Ops.triangulate: selection must own primitives"
   | Some group when Group.length group <> primitive_count ->
       invalid_arg
         "Pdk.Ops.triangulate: selection length does not match primitive count"
   | None | Some _ -> ());
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let topology_view = Topology.Private.view topology in
  let selected primitive = match primitives with
    | None -> true
    | Some group -> Group.mem primitive group in
  let full_selection = match primitives with
    | None -> true
    | Some group -> Group.cardinality group = primitive_count in
  let collapsed_quad_removed primitive =
    let first = topology_view.primitive_offsets.(primitive)
    and last = topology_view.primitive_offsets.(primitive + 1) in
    if last - first <> 4 then -1
    else
      let removed = ref (-1) and collapsed = ref 0 in
      for local = 0 to 3 do
        let next = (local + 1) land 3 in
        let a = topology_view.vertex_points.(first + local)
        and b = topology_view.vertex_points.(first + next) in
        if positions.x.(a) = positions.x.(b)
           && positions.y.(a) = positions.y.(b)
           && positions.z.(a) = positions.z.(b) then begin
          incr collapsed;
          removed := next
        end
      done;
      if !collapsed <> 1 then -1
      else
        let remaining ordinal = if ordinal < !removed then ordinal
          else ordinal + 1 in
        let a = topology_view.vertex_points.(first + remaining 0)
        and b = topology_view.vertex_points.(first + remaining 1)
        and c = topology_view.vertex_points.(first + remaining 2) in
        let ux = positions.x.(b) -. positions.x.(a)
        and uy = positions.y.(b) -. positions.y.(a)
        and uz = positions.z.(b) -. positions.z.(a)
        and vx = positions.x.(c) -. positions.x.(a)
        and vy = positions.y.(c) -. positions.y.(a)
        and vz = positions.z.(c) -. positions.z.(a) in
        let scale = Float.max (abs_float ux) (abs_float uy) in
        let scale = Float.max scale (abs_float uz) in
        let scale = Float.max scale (abs_float vx) in
        let scale = Float.max scale (abs_float vy) in
        let scale = Float.max scale (abs_float vz) in
        if scale = 0. || not (finite scale) then -1
        else
          let ux = ux /. scale and uy = uy /. scale and uz = uz /. scale
          and vx = vx /. scale and vy = vy /. scale and vz = vz /. scale in
          let nx = (uy *. vz) -. (uz *. vy)
          and ny = (uz *. vx) -. (ux *. vz)
          and nz = (ux *. vy) -. (uy *. vx) in
          if nx = 0. && ny = 0. && nz = 0. then -1 else !removed in
  let record_min target value =
    let rec loop current =
      if value >= current then ()
      else if not (Atomic.compare_and_set target current value) then
        loop (Atomic.get target) in
    loop (Atomic.get target) in
  let collapsed_removals = Bytes.make primitive_count '\000'
  and primitive_bases = Array.make (primitive_count + 1) 1
  and vertex_bases = if full_selection then [||]
      else Array.make (primitive_count + 1) 0
  and first_selected_curve = Atomic.make max_int
  and changes = Atomic.make false in
  primitive_bases.(0) <- 0;
  let average_size = if primitive_count = 0 then 1 else
      max 1 (Topology.vertex_count topology / primitive_count) in
  let primitive_grain = max 1 (grain / average_size) in
  Parallel.for_ ~chunk_size:primitive_grain ~start:0
    ~finish:(primitive_count - 1) (fun primitive ->
      if primitive land 1023 = 0 then Cancel.check_opt cancel;
      let size = topology_view.primitive_offsets.(primitive + 1)
          - topology_view.primitive_offsets.(primitive) in
      if not (selected primitive) then vertex_bases.(primitive + 1) <- size
      else if Bytes.get topology_view.primitive_kinds primitive <> '\000' then begin
        if not full_selection then vertex_bases.(primitive + 1) <- size;
        record_min first_selected_curve primitive
      end else if size = 3 then begin
        if not full_selection then vertex_bases.(primitive + 1) <- 3
      end
      else begin
        Atomic.set changes true;
        let removed = collapsed_quad_removed primitive in
        Bytes.set collapsed_removals primitive (Char.chr (removed + 1));
        let triangles = if removed >= 0 then 1 else size - 2 in
        primitive_bases.(primitive + 1) <- triangles;
        if not full_selection then vertex_bases.(primitive + 1) <- triangles * 3
      end);
  let curve = Atomic.get first_selected_curve in
  if curve <> max_int then Error (Printf.sprintf
      "Pdk.Ops.triangulate: primitive %d is a curve, not a polygon" curve)
  else if not (Atomic.get changes) then Ok geometry
  else begin
    let cardinality_error = ref None in
    for primitive = 0 to primitive_count - 1 do
      if primitive land 4095 = 0 then Cancel.check_opt cancel;
      let next_primitives = primitive_bases.(primitive + 1) in
      let next_vertices = if full_selection then next_primitives * 3
        else vertex_bases.(primitive + 1) in
      if primitive_bases.(primitive) > Sys.max_array_length - next_primitives
         || (not full_selection
             && vertex_bases.(primitive) > Sys.max_array_length - next_vertices)
         || (full_selection && primitive_bases.(primitive)
             > (Sys.max_array_length / 3) - next_primitives) then
        cardinality_error := Some
          "Pdk.Ops.triangulate: output cardinality exceeds array limits"
      else begin
        primitive_bases.(primitive + 1) <-
          primitive_bases.(primitive) + next_primitives;
        if not full_selection then vertex_bases.(primitive + 1) <-
          vertex_bases.(primitive) + next_vertices
      end
    done;
    let output_primitives = primitive_bases.(primitive_count)
    and output_vertex_count = if full_selection then
        primitive_bases.(primitive_count) * 3
      else vertex_bases.(primitive_count) in
    if output_primitives >= Sys.max_array_length then cardinality_error := Some
        "Pdk.Ops.triangulate: output cardinality exceeds array limits";
    match !cardinality_error with
    | Some message -> Error message
    | None ->
      let output_vertices = Array.make output_vertex_count 0
      and vertex_map = Array.make output_vertex_count 0
      and output_offsets = Array.make (output_primitives + 1) 0
      and output_kinds = Bytes.make output_primitives '\000'
      and primitive_map = Array.make output_primitives 0
      and first_failure = Atomic.make max_int in
      let block_count = if primitive_count = 0 then 0
        else (primitive_count + primitive_grain - 1) / primitive_grain in
      Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(block_count - 1) (fun block ->
        let scratch = Polygon_triangulation.create_scratch () in
        let current_primitive = ref 0
        and current_output_primitive = ref 0
        and current_output_vertex = ref 0 in
        let emit triangle old_a old_b old_c =
          let vertex = !current_output_vertex + (triangle * 3)
          and target_primitive = !current_output_primitive + triangle in
          output_vertices.(vertex) <- topology_view.vertex_points.(old_a);
          output_vertices.(vertex + 1) <- topology_view.vertex_points.(old_b);
          output_vertices.(vertex + 2) <- topology_view.vertex_points.(old_c);
          vertex_map.(vertex) <- old_a;
          vertex_map.(vertex + 1) <- old_b;
          vertex_map.(vertex + 2) <- old_c;
          output_offsets.(target_primitive) <- vertex;
          primitive_map.(target_primitive) <- !current_primitive
        in
        let first_primitive = block * primitive_grain
        and last_primitive = min (primitive_count - 1)
            (((block + 1) * primitive_grain) - 1) in
        for primitive = first_primitive to last_primitive do
          if primitive land 1023 = 0 then Cancel.check_opt cancel;
          let source_first = topology_view.primitive_offsets.(primitive)
          and source_last = topology_view.primitive_offsets.(primitive + 1)
          and output_primitive = primitive_bases.(primitive)
          and output_vertex = if full_selection then primitive_bases.(primitive) * 3
            else vertex_bases.(primitive) in
          let source_size = source_last - source_first in
          current_primitive := primitive;
          current_output_primitive := output_primitive;
          current_output_vertex := output_vertex;
          if not (selected primitive) || source_size = 3 then begin
            output_offsets.(output_primitive) <- output_vertex;
            Bytes.set output_kinds output_primitive
              (Bytes.get topology_view.primitive_kinds primitive);
            primitive_map.(output_primitive) <- primitive;
            Array.blit topology_view.vertex_points source_first output_vertices
              output_vertex source_size;
            for local = 0 to source_size - 1 do
              vertex_map.(output_vertex + local) <- source_first + local
            done
          end else if Bytes.get collapsed_removals primitive <> '\000' then begin
            let removed = Char.code (Bytes.get collapsed_removals primitive) - 1 in
            let remaining ordinal = if ordinal < removed then ordinal
              else ordinal + 1 in
            emit 0 (source_first + remaining 0) (source_first + remaining 1)
              (source_first + remaining 2)
          end else if primitive < Atomic.get first_failure then
            match Polygon_triangulation.primitive ?cancel ~positions
                ~topology:topology_view ~scratch primitive ~emit with
            | Ok () -> ()
            | Error _ -> record_min first_failure primitive
        done);
      output_offsets.(output_primitives) <- output_vertex_count;
      let failure = Atomic.get first_failure in
      if failure <> max_int then
        let scratch = Polygon_triangulation.create_scratch () in
        (match Polygon_triangulation.primitive ?cancel ~positions
            ~topology:topology_view ~scratch failure
            ~emit:(fun _ _ _ _ -> ()) with
         | Error message -> Error ("Pdk.Ops.triangulate: " ^ message)
         | Ok () -> Error (Printf.sprintf
             "Pdk.Ops.triangulate: primitive %d failed triangulation" failure))
      else begin
        let output_topology = Topology.Private.create_validated_owned
            ~point_count:(Geometry.point_count geometry)
            ~vertex_points:output_vertices ~primitive_offsets:output_offsets
            ~primitive_kinds:output_kinds in
            let rec attributes result = function
              | [] -> Ok (List.rev result)
              | attribute :: rest -> Result.bind
                  (remap_attribute ?cancel ~grain vertex_map primitive_map attribute)
                  (fun attribute -> attributes (attribute :: result) rest) in
            Result.bind (attributes [] (Geometry.attributes geometry)) (fun attributes ->
              let groups = List.map (remap_group ~grain vertex_map primitive_map)
                  (Geometry.groups geometry)
              and edge_groups = remap_edge_groups_identity ?cancel
                  ~source_topology:topology ~target_topology:output_topology
                  ~point_count:(Geometry.point_count geometry)
                  (Geometry.edge_groups geometry) in
              Geometry.create ~positions:(Geometry.positions geometry)
                ~topology:output_topology
                ~attributes ~groups ~edge_groups ())
      end
  end
  with Invalid_argument message -> Error message

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
      Result.bind (triangulate ?cancel ~grain geometry) (fun triangulated ->
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
                (match edge_collapse ?cancel ~grain ~edges:plan.edges
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

type reverse_operation =
  | Reverse_vertices
  | Shift_vertices of int

let reverse ?cancel ?(grain = 16_384) ?primitives
    ?(operation = Reverse_vertices) geometry =
  try
  if grain <= 0 then invalid_arg "Pdk.Ops.reverse: grain must be positive";
  Cancel.check_opt cancel;
  let topology = Geometry.topology geometry in
  let source = Topology.Private.view topology in
  let vertex_count = Topology.vertex_count topology in
  let primitive_count = Topology.primitive_count topology in
  (match primitives with
   | Some group when Group.owner group <> Group.Primitive ->
       invalid_arg "Pdk.Ops.reverse: selection must own primitives"
   | Some group when Group.length group <> primitive_count ->
       invalid_arg "Pdk.Ops.reverse: selection length does not match primitive count"
   | None | Some _ -> ());
  let selected primitive = match primitives with
    | None -> true | Some group -> Group.mem primitive group in
  let normalized_shift count offset =
    let shift = offset mod count in
    if shift < 0 then shift + count else shift in
  let changes = match operation with
    | Reverse_vertices ->
        (match primitives with
         | None -> primitive_count > 0
         | Some group -> Group.cardinality group > 0)
    | Shift_vertices 0 -> false
    | Shift_vertices offset ->
        let primitive = ref 0 and changed = ref false in
        while not !changed && !primitive < primitive_count do
          if selected !primitive then begin
            let count = source.primitive_offsets.(!primitive + 1)
                - source.primitive_offsets.(!primitive) in
            changed := normalized_shift count offset <> 0
          end;
          incr primitive
        done;
        !changed in
  if not changes then Ok geometry else
  let full_selection = match primitives with
    | None -> true
    | Some group -> Group.cardinality group = primitive_count in
  let vertex_points = if full_selection then Array.make vertex_count 0
    else Array.copy source.vertex_points
  and vertex_map = if full_selection then Array.make vertex_count 0
    else Array.init vertex_count Fun.id in
  let average_primitive_size = if primitive_count = 0 then 1
    else max 1 (vertex_count / primitive_count) in
  let primitive_grain = max 1 (grain / average_primitive_size) in
  Parallel.for_ ~chunk_size:primitive_grain ~start:0
    ~finish:(primitive_count - 1) (fun primitive ->
      if primitive land 1023 = 0 then Cancel.check_opt cancel;
      if selected primitive then begin
        let first = source.primitive_offsets.(primitive)
        and last = source.primitive_offsets.(primitive + 1) in
        let count = last - first in
        let shift = match operation with
          | Reverse_vertices -> 0
          | Shift_vertices offset -> normalized_shift count offset in
        for local = 0 to count - 1 do
          let old_local = match operation with
            | Reverse_vertices -> count - local - 1
            | Shift_vertices _ -> (local + shift) mod count in
          let vertex = first + local and old_vertex = first + old_local in
          vertex_points.(vertex) <- source.vertex_points.(old_vertex);
          vertex_map.(vertex) <- old_vertex
        done
      end);
  let reversed_topology = Topology.Private.create_validated_owned
      ~point_count:(Geometry.point_count geometry)
      ~vertex_points ~primitive_offsets:(Array.copy source.primitive_offsets)
      ~primitive_kinds:(Bytes.copy source.primitive_kinds) in
  let map_array source =
    if Array.length vertex_map = 0 then [||] else begin
      let output = Array.make (Array.length vertex_map) source.(vertex_map.(0)) in
      Parallel.for_ ~chunk_size:grain ~start:0
        ~finish:(Array.length vertex_map - 1) (fun vertex ->
          if vertex land 4095 = 0 then Cancel.check_opt cancel;
          output.(vertex) <- source.(vertex_map.(vertex)));
      output
    end in
  let remap_vertex_attribute attribute =
    if Attribute.owner attribute <> Attribute.Vertex then Ok attribute
    else
      let storage = match Attribute.Private.storage attribute with
        | Attribute.Float values -> Attribute.Float (map_array values)
        | Attribute.Int values -> Attribute.Int (map_array values)
        | Attribute.Text values -> Attribute.Text (map_array values)
        | Attribute.Float2 values ->
            let values = Packed.Float2.Private.view values in
            Attribute.Float2 (Packed.Float2.of_owned
              ~x:(map_array values.x) ~y:(map_array values.y) |> get_ok)
        | Attribute.Float3 values ->
            let values = Packed.Float3.Private.view values in
            Attribute.Float3 (Packed.Float3.Private.of_owned_exn
              ~x:(map_array values.x) ~y:(map_array values.y)
              ~z:(map_array values.z))
        | Attribute.Float4 values ->
            let values = Packed.Float4.Private.view values in
            Attribute.Float4 (Packed.Float4.of_owned
              ~x:(map_array values.x) ~y:(map_array values.y)
              ~z:(map_array values.z) ~w:(map_array values.w) |> get_ok)
        | Attribute.Int_array values -> Attribute.Int_array
            (Ragged_ops.remap_int ?cancel ~grain vertex_map values)
        | Attribute.Float_array values -> Attribute.Float_array
            (Ragged_ops.remap_float ?cancel ~grain vertex_map values) in
      Attribute.create_owned ~name:(Attribute.name attribute)
        ~owner:Attribute.Vertex storage in
  Result.bind (Ok reversed_topology) (fun topology ->
    let rec attributes result = function
      | [] -> Ok (List.rev result)
      | attribute :: rest ->
          if operation = Reverse_vertices
             && String.equal (Attribute.name attribute) "N"
             && (Attribute.owner attribute = Attribute.Point
                 || Attribute.owner attribute = Attribute.Vertex)
          then attributes result rest
          else Result.bind (remap_vertex_attribute attribute)
              (fun attribute -> attributes (attribute :: result) rest) in
    Result.bind (attributes [] (Geometry.attributes geometry)) (fun attributes ->
      let groups = List.map (fun group ->
        if Group.owner group <> Group.Vertex then group
        else
          let target = Group.init ~grain ~owner:Group.Vertex
              ~name:(Group.name group) vertex_count (fun vertex ->
                Group.mem vertex_map.(vertex) group) in
          Group.Private.remap_order ~source:group
            ~source_of_target:vertex_map target) (Geometry.groups geometry)
      and edge_groups = remap_edge_groups_identity ?cancel
          ~source_topology:(Geometry.topology geometry) ~target_topology:topology
          ~point_count:(Geometry.point_count geometry)
          (Geometry.edge_groups geometry) in
      Geometry.create ~positions:(Geometry.positions geometry) ~topology
        ~attributes ~groups ~edge_groups ()))
  with Invalid_argument message -> Error message

let mirror ?cancel ?(grain = 16_384) ?(keep_original = true) ~origin ~normal
    geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.mirror: grain must be positive";
  let ox = origin.Vec3.x and oy = origin.y and oz = origin.z
  and supplied_nx = normal.Vec3.x and supplied_ny = normal.y
  and supplied_nz = normal.z in
  if not (finite ox && finite oy && finite oz && finite supplied_nx
          && finite supplied_ny && finite supplied_nz) then
    Error "Pdk.Ops.mirror: plane origin and normal must be finite"
  else
    let length = sqrt ((supplied_nx *. supplied_nx)
        +. (supplied_ny *. supplied_ny) +. (supplied_nz *. supplied_nz)) in
    if length <= 1e-20 then Error "Pdk.Ops.mirror: plane normal must be non-zero"
    else
      let nx = supplied_nx /. length and ny = supplied_ny /. length
      and nz = supplied_nz /. length in
      let source_points = Geometry.point_count geometry
      and source_vertices = Geometry.vertex_count geometry
      and source_primitives = Geometry.primitive_count geometry in
      let copies = if keep_original then 2 else 1 in
      if source_points > max_int / copies || source_vertices > max_int / copies
         || source_primitives > max_int / copies then
        Error "Pdk.Ops.mirror: output cardinality exceeds OCaml array limits"
      else
        let output_points = source_points * copies
        and output_vertices = source_vertices * copies
        and output_primitives = source_primitives * copies in
        let source_positions = Packed.Float3.Private.view
            (Geometry.positions geometry) in
        let px = Array.make output_points 0. and py = Array.make output_points 0.
        and pz = Array.make output_points 0. in
        if keep_original then begin
          Array.blit source_positions.x 0 px 0 source_points;
          Array.blit source_positions.y 0 py 0 source_points;
          Array.blit source_positions.z 0 pz 0 source_points
        end;
        let reflected_point_base = if keep_original then source_points else 0 in
        if source_points > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(source_points - 1) (fun point ->
              if point land 16383 = 0 then Cancel.check_opt cancel;
              let x = source_positions.x.(point)
              and y = source_positions.y.(point)
              and z = source_positions.z.(point) in
              let distance = ((x -. ox) *. nx) +. ((y -. oy) *. ny)
                  +. ((z -. oz) *. nz) in
              let output = reflected_point_base + point in
              px.(output) <- x -. (2. *. distance *. nx);
              py.(output) <- y -. (2. *. distance *. ny);
              pz.(output) <- z -. (2. *. distance *. nz));
        let source_topology = Topology.Private.view (Geometry.topology geometry) in
        let vertex_points = Array.make output_vertices 0
        and vertex_map = Array.make output_vertices 0
        and primitive_offsets = Array.make (output_primitives + 1) 0
        and primitive_map = Array.make output_primitives 0
        and primitive_kinds = Bytes.make output_primitives '\000' in
        if keep_original then begin
          Array.blit source_topology.vertex_points 0 vertex_points 0 source_vertices;
          for vertex = 0 to source_vertices - 1 do vertex_map.(vertex) <- vertex done;
          Array.blit source_topology.primitive_offsets 0 primitive_offsets 0
            (source_primitives + 1);
          for primitive = 0 to source_primitives - 1 do
            primitive_map.(primitive) <- primitive
          done;
          Bytes.blit source_topology.primitive_kinds 0 primitive_kinds 0
            source_primitives
        end;
        let reflected_vertex_base = if keep_original then source_vertices else 0
        and reflected_primitive_base = if keep_original then source_primitives else 0 in
        if source_primitives > 0 then Parallel.for_ ~chunk_size:(max 1 (grain / 8))
            ~start:0 ~finish:(source_primitives - 1) (fun primitive ->
              if primitive land 1023 = 0 then Cancel.check_opt cancel;
              let first = source_topology.primitive_offsets.(primitive)
              and last = source_topology.primitive_offsets.(primitive + 1) in
              let count = last - first
              and output_first = reflected_vertex_base + first
              and output_primitive = reflected_primitive_base + primitive in
              primitive_offsets.(output_primitive) <- output_first;
              primitive_map.(output_primitive) <- primitive;
              let polygon = Bytes.get source_topology.primitive_kinds primitive = '\000' in
              for local = 0 to count - 1 do
                let source_vertex = if polygon then first + count - local - 1
                  else first + local in
                let output_vertex = output_first + local in
                vertex_points.(output_vertex) <- reflected_point_base
                    + source_topology.vertex_points.(source_vertex);
                vertex_map.(output_vertex) <- source_vertex
              done;
              Bytes.set primitive_kinds output_primitive
                (Bytes.get source_topology.primitive_kinds primitive));
        primitive_offsets.(output_primitives) <- output_vertices;
        let reflect_normal_arrays owner mapping values =
          let source = Packed.Float3.Private.view values in
          let count = Array.length mapping in
          let x = Array.make count 0. and y = Array.make count 0.
          and z = Array.make count 0. in
          let original_count = match owner with
            | Attribute.Point -> source_points
            | Attribute.Vertex -> source_vertices
            | Attribute.Primitive | Attribute.Detail -> 0 in
          if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(count - 1) (fun output ->
                let input = mapping.(output) in
                let vx = source.x.(input) and vy = source.y.(input)
                and vz = source.z.(input) in
                if keep_original && output < original_count then begin
                  x.(output) <- vx; y.(output) <- vy; z.(output) <- vz
                end else begin
                  let projection = (vx *. nx) +. (vy *. ny) +. (vz *. nz) in
                  x.(output) <- vx -. (2. *. projection *. nx);
                  y.(output) <- vy -. (2. *. projection *. ny);
                  z.(output) <- vz -. (2. *. projection *. nz)
                end);
          Attribute.Float3 (Packed.Float3.Private.of_owned_exn ~x ~y ~z)
        in
        let point_map = Array.init output_points (fun output ->
            if keep_original && output < source_points then output
            else output - reflected_point_base) in
        let map_attribute attribute =
          let owner = Attribute.owner attribute in
          let mapping = match owner with
            | Attribute.Point -> Some point_map
            | Attribute.Vertex -> Some vertex_map
            | Attribute.Primitive -> Some primitive_map
            | Attribute.Detail -> None in
          match mapping with
          | None -> Ok attribute
          | Some mapping ->
              let remap_storage = function
                | Attribute.Float values -> Attribute.Float (select_array mapping values)
                | Attribute.Int values -> Attribute.Int (select_array mapping values)
                | Attribute.Text values -> Attribute.Text (select_array mapping values)
                | Attribute.Float2 values ->
                    let view = Packed.Float2.Private.view values in
                    Attribute.Float2 (Packed.Float2.of_owned
                      ~x:(select_array mapping view.x) ~y:(select_array mapping view.y)
                      |> get_ok)
                | Attribute.Float3 values ->
                    let view = Packed.Float3.Private.view values in
                    Attribute.Float3 (Packed.Float3.Private.of_owned_exn
                      ~x:(select_array mapping view.x) ~y:(select_array mapping view.y)
                      ~z:(select_array mapping view.z))
                | Attribute.Float4 values ->
                    let view = Packed.Float4.Private.view values in
                    Attribute.Float4 (Packed.Float4.of_owned
                      ~x:(select_array mapping view.x) ~y:(select_array mapping view.y)
                      ~z:(select_array mapping view.z) ~w:(select_array mapping view.w)
                      |> get_ok)
                | Attribute.Int_array values -> Attribute.Int_array
                    (Ragged_ops.remap_int ?cancel ~grain mapping values)
                | Attribute.Float_array values -> Attribute.Float_array
                    (Ragged_ops.remap_float ?cancel ~grain mapping values) in
              let storage =
                if String.equal (Attribute.name attribute) "N"
                   && (owner = Attribute.Point || owner = Attribute.Vertex)
                then
                  match Attribute.Private.storage attribute with
                  | Attribute.Float3 values -> reflect_normal_arrays owner mapping values
                  | storage -> remap_storage storage
                else remap_storage (Attribute.Private.storage attribute) in
              Attribute.create_owned ~name:(Attribute.name attribute) ~owner storage
        in
        let rec map_attributes result = function
          | [] -> Ok (List.rev result)
          | attribute :: rest -> Result.bind (map_attribute attribute)
              (fun mapped -> map_attributes (mapped :: result) rest) in
        Result.bind (map_attributes [] (Geometry.attributes geometry))
          (fun attributes ->
            let groups = List.map (fun group ->
              let mapping = match Group.owner group with
                | Group.Point -> point_map
                | Group.Vertex -> vertex_map
                | Group.Primitive -> primitive_map in
              let target = Group.init ~grain ~owner:(Group.owner group)
                  ~name:(Group.name group) (Array.length mapping)
                  (fun output -> Group.mem mapping.(output) group) in
              Group.Private.remap_order ~source:group
                ~source_of_target:mapping target)
                (Geometry.groups geometry) in
            let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz
            and topology = Topology.Private.create_validated_owned
                ~point_count:output_points ~vertex_points ~primitive_offsets
                ~primitive_kinds in
            let edge_groups = match Geometry.edge_groups geometry with
              | [] -> []
              | source_groups ->
                  let source_topology = Geometry.topology geometry in
                  let source_index = Topology_index.create ?cancel source_topology
                  and target_index = Topology_index.create ?cancel topology in
                  let remap offset group =
                    let point_map = Array.init source_points (fun point ->
                      point + offset) in
                    Edge_group.remap ?cancel ~source_index
                      ~target_topology:topology ~target_index ~point_map group
                    |> get_ok in
                  List.map (fun group ->
                    if keep_original then
                      Edge_group.union (remap 0 group)
                        (remap reflected_point_base group) |> get_ok
                    else remap 0 group) source_groups in
            Geometry.create ~positions ~topology ~attributes ~groups ~edge_groups ())

let normals ?cancel ?(grain = 16_384) ?selection ?owner ?weighting ?cusp_angle
    ?keep_original_zero ?reverse ?attribute geometry =
  Normal_ops.run ?cancel ~grain ?selection ?owner ?weighting ?cusp_angle
    ?keep_original_zero ?reverse ?attribute geometry

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

let select_parallel ?cancel ~grain mapping source =
  let count = Array.length mapping in
  if count = 0 then [||]
  else begin
    let output = Array.make count source.(mapping.(0)) in
    Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1) (fun index ->
      if index land 4095 = 0 then Cancel.check_opt cancel;
      output.(index) <- source.(mapping.(index)));
    output
  end

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
    let px = select_parallel ?cancel ~grain new_to_old source_positions.x
    and py = select_parallel ?cancel ~grain new_to_old source_positions.y
    and pz = select_parallel ?cancel ~grain new_to_old source_positions.z in
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
      else
        let storage = match Attribute.Private.storage attribute with
          | Attribute.Float values ->
              Attribute.Float (select_parallel ?cancel ~grain new_to_old values)
          | Attribute.Int values ->
              Attribute.Int (select_parallel ?cancel ~grain new_to_old values)
          | Attribute.Text values ->
              Attribute.Text (select_parallel ?cancel ~grain new_to_old values)
          | Attribute.Float2 values ->
              let values = Packed.Float2.Private.view values in
              Attribute.Float2 (Packed.Float2.of_owned
                ~x:(select_parallel ?cancel ~grain new_to_old values.x)
                ~y:(select_parallel ?cancel ~grain new_to_old values.y) |> get_ok)
          | Attribute.Float3 values ->
              let values = Packed.Float3.Private.view values in
              Attribute.Float3 (Packed.Float3.Private.of_owned_exn
                ~x:(select_parallel ?cancel ~grain new_to_old values.x)
                ~y:(select_parallel ?cancel ~grain new_to_old values.y)
                ~z:(select_parallel ?cancel ~grain new_to_old values.z))
          | Attribute.Float4 values ->
              let values = Packed.Float4.Private.view values in
              Attribute.Float4 (Packed.Float4.of_owned
                ~x:(select_parallel ?cancel ~grain new_to_old values.x)
                ~y:(select_parallel ?cancel ~grain new_to_old values.y)
                ~z:(select_parallel ?cancel ~grain new_to_old values.z)
                ~w:(select_parallel ?cancel ~grain new_to_old values.w) |> get_ok)
          | Attribute.Int_array values -> Attribute.Int_array
              (Ragged_ops.remap_int ?cancel ~grain new_to_old values)
          | Attribute.Float_array values -> Attribute.Float_array
              (Ragged_ops.remap_float ?cancel ~grain new_to_old values) in
        Attribute.create_owned ~name:(Attribute.name attribute)
          ~owner:Attribute.Point storage in
    let rec remap_attributes result = function
      | [] -> Ok (List.rev result)
      | attribute :: rest -> Result.bind (remap_point_attribute attribute)
          (fun attribute -> remap_attributes (attribute :: result) rest) in
    Result.bind (remap_attributes [] (Geometry.attributes geometry))
      (fun attributes ->
        let groups = List.map (fun group ->
          if Group.owner group <> Group.Point then group
          else
            let target = Group.init ~grain ~owner:Group.Point
                ~name:(Group.name group) !retained (fun point ->
                  if point land 4095 = 0 then Cancel.check_opt cancel;
                  Group.mem new_to_old.(point) group) in
            Group.Private.remap_order ~source:group
              ~source_of_target:new_to_old target)
            (Geometry.groups geometry) in
        let edge_groups = remap_edge_groups ?cancel
            ~source_topology:source_topology_value ~target_topology:topology
            ~point_map:old_to_new (Geometry.edge_groups geometry) in
        Geometry.create ~positions ~topology ~attributes ~groups ~edge_groups ())
  end

let point_float geometry name =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Ok None
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> Ok (Some values)
       | _ -> Error (Printf.sprintf "Pdk.Ops.copy_to_points: %s must be point float" name))

let point_float3 geometry name =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Ok None
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Ok (Some values)
       | _ -> Error (Printf.sprintf "Pdk.Ops.copy_to_points: %s must be point float3" name))

let point_float4 geometry name =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Ok None
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Ok (Some values)
       | _ -> Error (Printf.sprintf "Pdk.Ops.copy_to_points: %s must be point float4" name))

let point_affine_transform geometry name =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Ok None
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float_array values ->
           let view = Packed.Float_array.Private.view values in
           let rows = Array.length view.offsets - 1 in
           let width = if rows = 0 then 16
             else view.offsets.(1) - view.offsets.(0) in
           if width <> 9 && width <> 16 then Error (Printf.sprintf
             "Pdk.Ops.copy_to_points: %s rows must contain 9 or 16 floats" name)
           else begin
             let valid = ref true in
             for row = 0 to rows - 1 do
               let first = view.offsets.(row) and last = view.offsets.(row + 1) in
               if last - first <> width then valid := false;
               for value = first to last - 1 do
                 if not (finite view.values.(value)) then valid := false
               done;
               if width = 16 && (abs_float view.values.(first + 12) > 1e-12
                   || abs_float view.values.(first + 13) > 1e-12
                   || abs_float view.values.(first + 14) > 1e-12
                   || abs_float (view.values.(first + 15) -. 1.) > 1e-12)
               then valid := false
             done;
             if !valid then Ok (Some (view, width))
             else Error (Printf.sprintf
               "Pdk.Ops.copy_to_points: %s must contain finite, fixed-width affine matrices"
               name)
           end
       | _ -> Error (Printf.sprintf
           "Pdk.Ops.copy_to_points: %s must be a point float-array matrix" name))

let checked_product operation left right =
  if left <> 0 && right > max_int / left then
    Error (operation ^ ": output cardinality exceeds OCaml array limits")
  else Ok (left * right)

type copy_target_owner = Copy_target_points | Copy_target_vertices
  | Copy_target_primitives
type copy_target_operation = Copy_target_nothing | Copy_target_copy
  | Copy_target_add | Copy_target_subtract | Copy_target_multiply
type copy_target_attribute_rule = {
  copy_target_pattern : string;
  copy_target_owner : copy_target_owner;
  copy_target_operation : copy_target_operation;
}

let parallel_output_ranges ?cancel ~grain length body =
  if length > 0 then begin
    let chunk_count = 1 + ((length - 1) / grain) in
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(chunk_count - 1) (fun chunk ->
      Cancel.check_opt cancel;
      let first = chunk * grain in
      let last = first + min grain (length - first) in
      body ~first ~last)
  end

let copy_target_attribute ?cancel ~grain ~copies ~per_copy rule target_attribute
    geometry =
  try
  let owner = match rule.copy_target_owner with
    | Copy_target_points -> Attribute.Point
    | Copy_target_vertices -> Attribute.Vertex
    | Copy_target_primitives -> Attribute.Primitive in
  let name = Attribute.name target_attribute in
  let output_count = copies * per_copy in
  let existing = Geometry.find_attribute ~owner name geometry in
  let operation = rule.copy_target_operation in
  let[@inline always] float_missing target = match operation with
    | Copy_target_nothing -> assert false
    | Copy_target_subtract -> -.target
    | Copy_target_copy | Copy_target_add | Copy_target_multiply -> target in
  let[@inline always] float_existing source target = match operation with
    | Copy_target_nothing -> assert false
    | Copy_target_copy -> target
    | Copy_target_add -> source +. target
    | Copy_target_subtract -> source -. target
    | Copy_target_multiply -> source *. target in
  let[@inline always] int_missing target = match operation with
    | Copy_target_nothing -> assert false
    | Copy_target_subtract -> -target
    | Copy_target_copy | Copy_target_add | Copy_target_multiply -> target in
  let[@inline always] int_existing source target = match operation with
    | Copy_target_nothing -> assert false
    | Copy_target_copy -> target
    | Copy_target_add -> source + target
    | Copy_target_subtract -> source - target
    | Copy_target_multiply -> source * target in
  let incompatible expected = Error (Printf.sprintf
    "Pdk.Ops.copy_to_points: target attribute %S requires matching %s storage for arithmetic"
    name expected) in
  let fixed_float target destination =
    let output = Array.make output_count 0. in
    (match destination with
    | None -> parallel_output_ranges ?cancel ~grain output_count
        (fun ~first ~last -> for index = first to last - 1 do
          output.(index) <- float_missing target.(index / per_copy) done)
    | Some source -> parallel_output_ranges ?cancel ~grain output_count
        (fun ~first ~last -> for index = first to last - 1 do
          output.(index) <- float_existing source.(index)
              target.(index / per_copy) done));
    Attribute.Float output in
  let fixed_int target destination =
    let output = Array.make output_count 0 in
    (match destination with
    | None -> parallel_output_ranges ?cancel ~grain output_count
        (fun ~first ~last -> for index = first to last - 1 do
          output.(index) <- int_missing target.(index / per_copy) done)
    | Some source -> parallel_output_ranges ?cancel ~grain output_count
        (fun ~first ~last -> for index = first to last - 1 do
          output.(index) <- int_existing source.(index)
              target.(index / per_copy) done));
    Attribute.Int output in
  let destination_storage () = Option.map Attribute.Private.storage existing in
  let storage_result = match Attribute.Private.storage target_attribute with
    | Attribute.Float target ->
        let destination = match operation, destination_storage () with
          | Copy_target_copy, _ | _, None -> Ok None
          | _, Some (Attribute.Float values) -> Ok (Some values)
          | _ -> incompatible "float" in
        Result.map (fixed_float target) destination
    | Attribute.Int target ->
        let destination = match operation, destination_storage () with
          | Copy_target_copy, _ | _, None -> Ok None
          | _, Some (Attribute.Int values) -> Ok (Some values)
          | _ -> incompatible "int" in
        Result.map (fixed_int target) destination
    | Attribute.Float2 target ->
        let target = Packed.Float2.Private.view target in
        let destination = match operation, destination_storage () with
          | Copy_target_copy, _ | _, None -> Ok None
          | _, Some (Attribute.Float2 values) ->
              Ok (Some (Packed.Float2.Private.view values))
          | _ -> incompatible "float2" in
        Result.map (fun (destination : Packed.Float2.Private.view option) ->
          let x = Array.make output_count 0. and y = Array.make output_count 0. in
          parallel_output_ranges ?cancel ~grain output_count (fun ~first ~last ->
            for index = first to last - 1 do
              let target_index = index / per_copy in
              (match destination with
               | None ->
                   x.(index) <- float_missing target.x.(target_index);
                   y.(index) <- float_missing target.y.(target_index)
               | Some values ->
                   x.(index) <- float_existing values.x.(index)
                       target.x.(target_index);
                   y.(index) <- float_existing values.y.(index)
                       target.y.(target_index))
            done);
          Attribute.Float2 (Packed.Float2.of_owned ~x ~y |> get_ok)) destination
    | Attribute.Float3 target ->
        let target = Packed.Float3.Private.view target in
        let destination = match operation, destination_storage () with
          | Copy_target_copy, _ | _, None -> Ok None
          | _, Some (Attribute.Float3 values) ->
              Ok (Some (Packed.Float3.Private.view values))
          | _ -> incompatible "float3" in
        Result.map (fun (destination : Packed.Float3.Private.view option) ->
          let x = Array.make output_count 0. and y = Array.make output_count 0.
          and z = Array.make output_count 0. in
          parallel_output_ranges ?cancel ~grain output_count (fun ~first ~last ->
            for index = first to last - 1 do
              let target_index = index / per_copy in
              (match destination with
               | None ->
                   x.(index) <- float_missing target.x.(target_index);
                   y.(index) <- float_missing target.y.(target_index);
                   z.(index) <- float_missing target.z.(target_index)
               | Some values ->
                   x.(index) <- float_existing values.x.(index)
                       target.x.(target_index);
                   y.(index) <- float_existing values.y.(index)
                       target.y.(target_index);
                   z.(index) <- float_existing values.z.(index)
                       target.z.(target_index))
            done);
          Attribute.Float3 (Packed.Float3.Private.of_owned_exn ~x ~y ~z)) destination
    | Attribute.Float4 target ->
        let target = Packed.Float4.Private.view target in
        let destination = match operation, destination_storage () with
          | Copy_target_copy, _ | _, None -> Ok None
          | _, Some (Attribute.Float4 values) ->
              Ok (Some (Packed.Float4.Private.view values))
          | _ -> incompatible "float4" in
        Result.map (fun (destination : Packed.Float4.Private.view option) ->
          let x = Array.make output_count 0. and y = Array.make output_count 0.
          and z = Array.make output_count 0. and w = Array.make output_count 0. in
          parallel_output_ranges ?cancel ~grain output_count (fun ~first ~last ->
            for index = first to last - 1 do
              let target_index = index / per_copy in
              (match destination with
               | None ->
                   x.(index) <- float_missing target.x.(target_index);
                   y.(index) <- float_missing target.y.(target_index);
                   z.(index) <- float_missing target.z.(target_index);
                   w.(index) <- float_missing target.w.(target_index)
               | Some values ->
                   x.(index) <- float_existing values.x.(index)
                       target.x.(target_index);
                   y.(index) <- float_existing values.y.(index)
                       target.y.(target_index);
                   z.(index) <- float_existing values.z.(index)
                       target.z.(target_index);
                   w.(index) <- float_existing values.w.(index)
                       target.w.(target_index))
            done);
          Attribute.Float4 (Packed.Float4.of_owned ~x ~y ~z ~w |> get_ok)) destination
    | Attribute.Text target ->
        let output = Array.make output_count "" in
        parallel_output_ranges ?cancel ~grain output_count (fun ~first ~last ->
          for index = first to last - 1 do
            output.(index) <- target.(index / per_copy)
          done);
        Ok (Attribute.Text output)
    | Attribute.Int_array target ->
        let target = Packed.Int_array.Private.view target in
        let destination = match operation, destination_storage () with
          | Copy_target_copy, _ | _, None -> Ok None
          | _, Some (Attribute.Int_array values) ->
              Ok (Some (Packed.Int_array.Private.view values))
          | _ -> incompatible "int_array" in
        Result.bind destination
          (fun (destination : Packed.Int_array.Private.view option) ->
          let offsets = Array.make (output_count + 1) 0 in
          for index = 0 to output_count - 1 do
            let target_index = index / per_copy in
            let width = target.offsets.(target_index + 1)
                - target.offsets.(target_index) in
            let width = match destination with
              | None -> width
              | Some values ->
                  let actual = values.offsets.(index + 1) - values.offsets.(index) in
                  if actual <> width then raise (Invalid_argument
                    "copy target integer-array row widths differ");
                  width in
            if offsets.(index) > max_int - width then raise (Invalid_argument
              "copy target integer-array cardinality exceeds limits");
            offsets.(index + 1) <- offsets.(index) + width
          done;
          let values = Array.make offsets.(output_count) 0 in
          parallel_output_ranges ?cancel ~grain output_count (fun ~first ~last ->
            for index = first to last - 1 do
              let target_index = index / per_copy in
              let target_first = target.offsets.(target_index)
              and output_first = offsets.(index) in
              for component = 0 to offsets.(index + 1) - output_first - 1 do
                values.(output_first + component) <- (match destination with
                  | None -> int_missing target.values.(target_first + component)
                  | Some source -> int_existing
                      source.values.(source.offsets.(index) + component)
                      target.values.(target_first + component))
              done
            done);
          Ok (Attribute.Int_array (Packed.Int_array.Private.create_validated_owned
            ~offsets ~values)))
    | Attribute.Float_array target ->
        let target = Packed.Float_array.Private.view target in
        let destination = match operation, destination_storage () with
          | Copy_target_copy, _ | _, None -> Ok None
          | _, Some (Attribute.Float_array values) ->
              Ok (Some (Packed.Float_array.Private.view values))
          | _ -> incompatible "float_array" in
        Result.bind destination
          (fun (destination : Packed.Float_array.Private.view option) ->
          let offsets = Array.make (output_count + 1) 0 in
          for index = 0 to output_count - 1 do
            let target_index = index / per_copy in
            let width = target.offsets.(target_index + 1)
                - target.offsets.(target_index) in
            let width = match destination with
              | None -> width
              | Some values ->
                  let actual = values.offsets.(index + 1) - values.offsets.(index) in
                  if actual <> width then raise (Invalid_argument
                    "copy target float-array row widths differ");
                  width in
            if offsets.(index) > max_int - width then raise (Invalid_argument
              "copy target float-array cardinality exceeds limits");
            offsets.(index + 1) <- offsets.(index) + width
          done;
          let values = Array.make offsets.(output_count) 0. in
          parallel_output_ranges ?cancel ~grain output_count (fun ~first ~last ->
            for index = first to last - 1 do
              let target_index = index / per_copy in
              let target_first = target.offsets.(target_index)
              and output_first = offsets.(index) in
              for component = 0 to offsets.(index + 1) - output_first - 1 do
                values.(output_first + component) <- (match destination with
                  | None -> float_missing target.values.(target_first + component)
                  | Some source -> float_existing
                      source.values.(source.offsets.(index) + component)
                      target.values.(target_first + component))
              done
            done);
          Ok (Attribute.Float_array
            (Packed.Float_array.Private.create_validated_owned ~offsets ~values))) in
  Result.bind storage_result (fun storage ->
    Result.bind (Attribute.create_owned ~name ~owner storage) (fun attribute ->
      Geometry.with_attribute attribute geometry))
  with Invalid_argument message ->
    Error ("Pdk.Ops.copy_to_points: " ^ message)

let compile_copy_target_rules rules =
  let rec compile result = function
    | [] -> Ok (List.rev result)
    | rule :: rest ->
        Result.bind (Attribute_pattern.compile rule.copy_target_pattern)
          (fun pattern -> compile ((rule, pattern) :: result) rest) in
  compile [] rules

let winning_copy_target_rule rules name =
  List.fold_left (fun winner (rule, pattern) ->
    if Attribute_pattern.matches pattern name then Some rule else winner)
    None rules

let copy_target_group ?cancel ~grain ~copies ~per_copy rule target_group
    geometry =
  let owner = match rule.copy_target_owner with
    | Copy_target_points -> Group.Point
    | Copy_target_vertices -> Group.Vertex
    | Copy_target_primitives -> Group.Primitive in
  let name = Group.name target_group in
  let existing = Geometry.find_group ~owner name geometry in
  let length = copies * per_copy in
  let group = Group.init ~grain ~owner ~name length (fun index ->
    if index land 4095 = 0 then Cancel.check_opt cancel;
    let target_member = Group.mem (index / per_copy) target_group in
    match rule.copy_target_operation, existing with
    | Copy_target_nothing, _ -> assert false
    | Copy_target_copy, _ -> target_member
    | (Copy_target_add | Copy_target_multiply), None -> target_member
    | Copy_target_subtract, None -> false
    | Copy_target_add, Some source -> Group.mem index source || target_member
    | Copy_target_multiply, Some source -> Group.mem index source && target_member
    | Copy_target_subtract, Some source -> Group.mem index source && not target_member
  ) in
  Geometry.with_group group geometry

let apply_copy_target_rules ?cancel ~grain ~copies ~source_points
    ~source_vertices ~source_primitives rules targets geometry =
  let per_copy rule = match rule.copy_target_owner with
    | Copy_target_points -> source_points
    | Copy_target_vertices -> source_vertices
    | Copy_target_primitives -> source_primitives in
  let rec apply_attributes geometry = function
    | [] -> Ok geometry
    | attribute :: attributes ->
        let next = match Attribute.owner attribute with
          | Attribute.Point ->
              (match winning_copy_target_rule rules (Attribute.name attribute) with
               | None | Some { copy_target_operation = Copy_target_nothing; _ } ->
                   Ok geometry
               | Some rule -> copy_target_attribute ?cancel ~grain ~copies
                   ~per_copy:(per_copy rule) rule attribute geometry)
          | Attribute.Vertex | Attribute.Primitive | Attribute.Detail -> Ok geometry in
        Result.bind next (fun geometry -> apply_attributes geometry attributes) in
  let rec apply_groups geometry = function
    | [] -> Ok geometry
    | group :: groups ->
        let next = match Group.owner group with
          | Group.Point ->
              (match winning_copy_target_rule rules (Group.name group) with
               | None | Some { copy_target_operation = Copy_target_nothing; _ } ->
                   Ok geometry
               | Some rule -> copy_target_group ?cancel ~grain ~copies
                   ~per_copy:(per_copy rule) rule group geometry)
          | Group.Vertex | Group.Primitive -> Ok geometry in
        Result.bind next (fun geometry -> apply_groups geometry groups) in
  Result.bind (apply_attributes geometry (Geometry.attributes targets))
    (fun geometry -> apply_groups geometry (Geometry.groups targets))

let repeat_array ?cancel ?(grain = 16_384) copies source =
  let length = Array.length source in
  if copies = 0 || length = 0 then [||]
  else begin
    let total = copies * length in
    let output = Array.make total source.(0) in
    parallel_output_ranges ?cancel ~grain total (fun ~first ~last ->
      let output_at = ref first in
      while !output_at < last do
        let source_at = !output_at mod length in
        let count = min (length - source_at) (last - !output_at) in
        Array.blit source source_at output !output_at count;
        output_at := !output_at + count
      done);
    output
  end

let repeat_attribute ?cancel ?(grain = 16_384) copies attribute =
  if Attribute.owner attribute = Attribute.Detail then Ok attribute
  else
    let storage = match Attribute.Private.storage attribute with
      | Attribute.Float values ->
          Attribute.Float (repeat_array ?cancel ~grain copies values)
      | Attribute.Int values ->
          Attribute.Int (repeat_array ?cancel ~grain copies values)
      | Attribute.Text values ->
          Attribute.Text (repeat_array ?cancel ~grain copies values)
      | Attribute.Float2 values ->
          let view = Packed.Float2.Private.view values in
          Attribute.Float2 (Packed.Float2.of_owned
            ~x:(repeat_array ?cancel ~grain copies view.x)
            ~y:(repeat_array ?cancel ~grain copies view.y) |> get_ok)
      | Attribute.Float3 values ->
          let view = Packed.Float3.Private.view values in
          Attribute.Float3 (Packed.Float3.Private.of_owned_exn
            ~x:(repeat_array ?cancel ~grain copies view.x)
            ~y:(repeat_array ?cancel ~grain copies view.y)
            ~z:(repeat_array ?cancel ~grain copies view.z))
      | Attribute.Float4 values ->
          let view = Packed.Float4.Private.view values in
          Attribute.Float4 (Packed.Float4.of_owned
            ~x:(repeat_array ?cancel ~grain copies view.x)
            ~y:(repeat_array ?cancel ~grain copies view.y)
            ~z:(repeat_array ?cancel ~grain copies view.z)
            ~w:(repeat_array ?cancel ~grain copies view.w) |> get_ok)
      | Attribute.Int_array values ->
          let source_count = Packed.Int_array.length values in
          let mapping = Array.init (copies * source_count)
              (fun index -> index mod source_count) in
          Attribute.Int_array (Ragged_ops.remap_int ?cancel ~grain mapping values)
      | Attribute.Float_array values ->
          let source_count = Packed.Float_array.length values in
          let mapping = Array.init (copies * source_count)
              (fun index -> index mod source_count) in
          Attribute.Float_array (Ragged_ops.remap_float ?cancel ~grain mapping values) in
    Attribute.create_owned ~name:(Attribute.name attribute)
      ~owner:(Attribute.owner attribute) storage

let repeat_group ?cancel ?grain copies group =
  let source_count = Group.length group in
  let target = Group.init ?grain ~owner:(Group.owner group)
      ~name:(Group.name group) (copies * source_count)
      (fun index ->
        if index land 4095 = 0 then Cancel.check_opt cancel;
        Group.mem (index mod source_count) group) in
  match Group.Private.order_view group with
  | None -> target
  | Some source_order ->
      let order = Array.make (copies * Array.length source_order) 0
      and output = ref 0 in
      for copy = 0 to copies - 1 do
        if copy land 255 = 0 then Cancel.check_opt cancel;
        Array.iter (fun source_element ->
          order.(!output) <- (copy * source_count) + source_element;
          incr output
        ) source_order
      done;
      Group.Private.with_owned_order order target

let transform_single_instance ?cancel ~grain matrix geometry =
  let source = Packed.Float3.Private.view (Geometry.positions geometry) in
  let count = Array.length source.x in
  let x = Array.make count 0. and y = Array.make count 0.
  and z = Array.make count 0. in
  let (m00,m01,m02,m03), (m10,m11,m12,m13),
      (m20,m21,m22,m23), (m30,m31,m32,m33) = Mat4.to_rows matrix in
  parallel_output_ranges ?cancel ~grain count (fun ~first ~last ->
    for point = first to last - 1 do
      let px = source.x.(point) and py = source.y.(point)
      and pz = source.z.(point) in
      let ox = m00*.px +. m01*.py +. m02*.pz +. m03
      and oy = m10*.px +. m11*.py +. m12*.pz +. m13
      and oz = m20*.px +. m21*.py +. m22*.pz +. m23
      and ow = m30*.px +. m31*.py +. m32*.pz +. m33 in
      if abs_float ow <= 1e-12 then begin
        x.(point) <- ox; y.(point) <- oy; z.(point) <- oz
      end else begin
        x.(point) <- ox /. ow; y.(point) <- oy /. ow;
        z.(point) <- oz /. ow
      end
    done);
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let output = Geometry.with_positions positions geometry |> get_ok in
  match Mat4.inverse matrix with
  | None ->
      List.fold_left (fun output owner ->
        match Geometry.find_attribute ~owner "N" geometry with
        | Some attribute when Attribute.get (Attribute.normal ~owner) attribute
            <> None -> Geometry.without_attribute ~owner "N" output
        | None | Some _ -> output)
        output [Attribute.Point; Attribute.Vertex]
  | Some inverse ->
      let normal_matrix = Mat4.transpose inverse in
      let (m00,m01,m02,_), (m10,m11,m12,_),
          (m20,m21,m22,_), _ = Mat4.to_rows normal_matrix in
      List.fold_left (fun output owner ->
        match Geometry.find_attribute ~owner "N" geometry with
        | None -> output
        | Some attribute ->
            (match Attribute.get (Attribute.normal ~owner) attribute with
             | None -> output
             | Some source ->
                 let source = Packed.Float3.Private.view source in
                 let count = Array.length source.x in
                 let x = Array.make count 0. and y = Array.make count 0.
                 and z = Array.make count 0. in
                 parallel_output_ranges ?cancel ~grain count
                   (fun ~first ~last ->
                     for index = first to last - 1 do
                       let ox = m00*.source.x.(index) +. m01*.source.y.(index)
                         +. m02*.source.z.(index)
                       and oy = m10*.source.x.(index) +. m11*.source.y.(index)
                         +. m12*.source.z.(index)
                       and oz = m20*.source.x.(index) +. m21*.source.y.(index)
                         +. m22*.source.z.(index) in
                       let length = sqrt (ox*.ox +. oy*.oy +. oz*.oz) in
                       if length > 1e-20 then begin
                         x.(index) <- ox/.length; y.(index) <- oy/.length;
                         z.(index) <- oz/.length
                       end
                     done);
                 let value = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
                 let attribute = Attribute.create_key_owned
                     (Attribute.normal ~owner) value |> get_ok in
                 Geometry.with_attribute attribute output |> get_ok))
        output [Attribute.Point; Attribute.Vertex]

let materialize_instances ?cancel ?(grain = 16_384) ?(apply_transform = true)
    ~transforms geometry =
  if grain <= 0 then
    invalid_arg "Pdk.Ops.materialize_instances: grain must be positive";
  Cancel.check_opt cancel;
  let matrices = Array.copy transforms in
  let invalid_transform = ref (-1) in
  if apply_transform then Array.iteri (fun instance matrix ->
      for row = 0 to 3 do for column = 0 to 3 do
        if !invalid_transform < 0
            && not (finite (Mat4.get matrix ~row ~column)) then
          invalid_transform := instance
      done done) matrices;
  let total = Array.length matrices in
  if !invalid_transform >= 0 then
    Error (Printf.sprintf
      "Pdk.Ops.materialize_instances: transform %d must be finite"
      !invalid_transform)
  else if total = 1 && (not apply_transform
      || Mat4.nearly_equal matrices.(0) Mat4.identity ~eps:0.) then
    Ok geometry
  else if total = 1 then
    Ok (transform_single_instance ?cancel ~grain matrices.(0) geometry)
  else
    let source_points = Geometry.point_count geometry
    and source_vertices = Geometry.vertex_count geometry
    and source_primitives = Geometry.primitive_count geometry in
    if source_points = 0 && source_vertices = 0 && source_primitives = 0 then
      Ok geometry
    else
    let product label count =
      if count <> 0 && total > Sys.max_array_length / count then
        Error ("Pdk.Ops.materialize_instances: " ^ label
          ^ " output exceeds array limits")
      else Ok (total * count) in
    Result.bind (product "point" source_points) (fun output_points ->
    Result.bind (product "vertex" source_vertices) (fun output_vertices ->
    Result.bind (product "primitive" source_primitives) (fun output_primitives ->
    if output_primitives = Sys.max_array_length then
      Error "Pdk.Ops.materialize_instances: primitive-offset output exceeds array limits"
    else begin
      let source_positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      let x, y, z = if not apply_transform then
          repeat_array ?cancel ~grain total source_positions.x,
          repeat_array ?cancel ~grain total source_positions.y,
          repeat_array ?cancel ~grain total source_positions.z
        else
          let rows = Array.map Mat4.to_rows matrices in
          let x = Array.make output_points 0. and y = Array.make output_points 0.
          and z = Array.make output_points 0. in
          parallel_output_ranges ?cancel ~grain output_points
            (fun ~first ~last ->
            let output_at = ref first in
            while !output_at < last do
              let copy = !output_at / source_points in
              let source_at = !output_at - (copy * source_points) in
              let count = min (source_points - source_at) (last - !output_at) in
              let (m00,m01,m02,m03), (m10,m11,m12,m13),
                  (m20,m21,m22,m23), (m30,m31,m32,m33) = rows.(copy) in
              for offset = 0 to count - 1 do
                let point = source_at + offset in
                let px = source_positions.x.(point)
                and py = source_positions.y.(point)
                and pz = source_positions.z.(point) in
                let ox = m00*.px +. m01*.py +. m02*.pz +. m03
                and oy = m10*.px +. m11*.py +. m12*.pz +. m13
                and oz = m20*.px +. m21*.py +. m22*.pz +. m23
                and ow = m30*.px +. m31*.py +. m32*.pz +. m33 in
                let output = !output_at + offset in
                if abs_float ow <= 1e-12 then begin
                  x.(output) <- ox; y.(output) <- oy; z.(output) <- oz
                end else begin
                  x.(output) <- ox /. ow; y.(output) <- oy /. ow;
                  z.(output) <- oz /. ow
                end
              done;
              output_at := !output_at + count
            done);
          x, y, z in
      let source_topology = Topology.Private.view (Geometry.topology geometry) in
      let vertex_points = Array.make output_vertices 0
      and primitive_offsets = Array.make (output_primitives + 1) 0
      and primitive_kinds = Bytes.make output_primitives '\000' in
      parallel_output_ranges ?cancel ~grain output_vertices
        (fun ~first ~last ->
          let output_at = ref first in
          while !output_at < last do
            let copy = !output_at / source_vertices in
            let source_at = !output_at - (copy * source_vertices) in
            let count = min (source_vertices - source_at) (last - !output_at) in
            let point_offset = copy * source_points in
            for offset = 0 to count - 1 do
              vertex_points.(!output_at + offset) <-
                source_topology.vertex_points.(source_at + offset) + point_offset
            done;
            output_at := !output_at + count
          done);
      parallel_output_ranges ?cancel ~grain output_primitives
        (fun ~first ~last ->
          let output_at = ref first in
          while !output_at < last do
            let copy = !output_at / source_primitives in
            let source_at = !output_at - (copy * source_primitives) in
            let count = min (source_primitives - source_at) (last - !output_at) in
            let vertex_offset = copy * source_vertices in
            for offset = 0 to count - 1 do
              primitive_offsets.(!output_at + offset) <-
                source_topology.primitive_offsets.(source_at + offset)
                + vertex_offset
            done;
            Bytes.blit source_topology.primitive_kinds source_at primitive_kinds
              !output_at count;
            output_at := !output_at + count
          done);
      primitive_offsets.(output_primitives) <- output_vertices;
      let topology = Topology.Private.create_validated_owned ~point_count:output_points
          ~vertex_points ~primitive_offsets ~primitive_kinds in
      let typed_normal attribute =
        let owner = Attribute.owner attribute in
        if String.equal (Attribute.name attribute) "N"
            && (owner = Attribute.Point || owner = Attribute.Vertex)
        then Attribute.get (Attribute.normal ~owner) attribute
        else None in
      let has_normals = apply_transform
        && List.exists (fun attribute -> typed_normal attribute <> None)
          (Geometry.attributes geometry) in
      let normal_matrices = if not has_normals then None
        else
          let output = Array.make total Mat4.identity
          and valid = ref true and instance = ref 0 in
          while !valid && !instance < total do
            match Mat4.inverse matrices.(!instance) with
            | None -> valid := false
            | Some inverse ->
                output.(!instance) <- Mat4.transpose inverse;
                incr instance
          done;
          if !valid then Some output else None in
      let transform_normals owner source normal_matrices =
        let source = Packed.Float3.Private.view source in
        let source_count = Array.length source.x in
        let nx = Array.make (total * source_count) 0.
        and ny = Array.make (total * source_count) 0.
        and nz = Array.make (total * source_count) 0. in
        parallel_output_ranges ?cancel ~grain (total * source_count)
          (fun ~first ~last ->
          let output_at = ref first in
          while !output_at < last do
            let copy = !output_at / source_count in
            let source_at = !output_at - (copy * source_count) in
            let count = min (source_count - source_at) (last - !output_at) in
            let (m00,m01,m02,_), (m10,m11,m12,_),
                (m20,m21,m22,_), _ = Mat4.to_rows normal_matrices.(copy) in
            for offset = 0 to count - 1 do
              let index = source_at + offset in
              let ox = m00*.source.x.(index) +. m01*.source.y.(index)
                +. m02*.source.z.(index)
              and oy = m10*.source.x.(index) +. m11*.source.y.(index)
                +. m12*.source.z.(index)
              and oz = m20*.source.x.(index) +. m21*.source.y.(index)
                +. m22*.source.z.(index) in
              let length = sqrt (ox*.ox +. oy*.oy +. oz*.oz) in
              if length > 1e-20 then begin
                let output = !output_at + offset in
                nx.(output) <- ox/.length; ny.(output) <- oy/.length;
                nz.(output) <- oz/.length
              end
            done;
            output_at := !output_at + count
          done);
        let value = Packed.Float3.Private.of_owned_exn ~x:nx ~y:ny ~z:nz in
        Attribute.create_key_owned (Attribute.normal ~owner) value |> get_ok in
      let rec attributes output = function
        | [] -> Ok (List.rev output)
        | attribute :: rest when apply_transform ->
            (match typed_normal attribute, normal_matrices with
             | Some _, None -> attributes output rest
             | Some source, Some matrices ->
                 let attribute = transform_normals (Attribute.owner attribute)
                     source matrices in
                 attributes (attribute :: output) rest
             | None, _ ->
                 Result.bind (repeat_attribute ?cancel ~grain total attribute)
                   (fun attribute -> attributes (attribute :: output) rest))
        | attribute :: rest ->
            Result.bind (repeat_attribute ?cancel ~grain total attribute)
            (fun attribute -> attributes (attribute :: output) rest) in
      Result.bind (attributes [] (Geometry.attributes geometry)) (fun attributes ->
        let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
        let edge_groups = match Geometry.edge_groups geometry with
          | [] -> []
          | source_groups ->
              let source_index = Topology_index.create ?cancel
                  (Geometry.topology geometry)
              in
              List.map (fun group -> Edge_group.replicate_exact_copies ?cancel
                ~source_topology:(Geometry.topology geometry) ~source_index
                ~target_topology:topology ~copies:total group |> get_ok)
                source_groups in
        let groups = List.map (fun group -> repeat_group ?cancel ~grain total group)
            (Geometry.groups geometry) in
        Geometry.create ~positions ~topology ~attributes ~groups ~edge_groups ())
    end)))

let duplicate ?cancel ?(grain = 16_384) ?(copies = 1) ?(cumulative = true)
    ?(transform = Mat4.identity) ?primitives ?copy_group_prefix
    ?(preserve_groups = false) geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.duplicate: grain must be positive";
  let selection_error = match primitives with
    | Some group when Group.owner group <> Group.Primitive ->
        Some "Pdk.Ops.duplicate: source selection must own primitives"
    | Some group when Group.length group <> Geometry.primitive_count geometry ->
        Some "Pdk.Ops.duplicate: source selection length does not match primitive count"
    | None | Some _ -> None in
  match selection_error with
  | Some message -> Error message
  | None when copies < 0 -> Error "Pdk.Ops.duplicate: copy count must be non-negative"
  | None when copies = 0 -> Ok geometry
  | None when copies >= Sys.max_array_length ->
    Error "Pdk.Ops.duplicate: copy count is too large"
  | None -> begin
    let full_matrices () =
      let matrices = Array.make (copies + 1) Mat4.identity in
      for copy = 1 to copies do
        matrices.(copy) <- if cumulative
          then Mat4.mul matrices.(copy - 1) transform else transform
      done;
      matrices in
    match primitives, copy_group_prefix with
    | None, None ->
        materialize_instances ?cancel ~grain ~transforms:(full_matrices ())
          geometry
    | _ ->
    let primitives_per_copy = match primitives with
      | None -> Geometry.primitive_count geometry
      | Some group -> Group.cardinality group in
    let group_preflight = match copy_group_prefix with
      | None -> Ok ()
      | Some prefix ->
          if primitives_per_copy <> 0
              && copies > (Sys.max_array_length
                - Geometry.primitive_count geometry) / primitives_per_copy
          then Error "Pdk.Ops.duplicate: primitive output exceeds array limits"
          else Duplicate.validate_copy_groups ~prefix ~copies
              ~primitive_count:(Geometry.primitive_count geometry
                + (copies * primitives_per_copy)) in
    Result.bind group_preflight (fun () ->
    let output = match primitives with
      | Some primitives ->
          let added = Array.make copies transform in
          if cumulative then
            for copy = 1 to copies - 1 do
              added.(copy) <- Mat4.mul added.(copy - 1) transform
            done;
          Duplicate.selected ?cancel ~grain ~primitives ~transforms:added geometry
      | None ->
          materialize_instances ?cancel ~grain ~transforms:(full_matrices ())
            geometry in
    Result.bind output (fun output -> match copy_group_prefix with
      | None -> Ok output
      | Some prefix ->
          Duplicate.add_copy_groups ?cancel ~grain ~prefix
            ~preserve:preserve_groups ~copies ~primitives_per_copy output)
    )
  end

let copy_to_points_all ?cancel ?(grain = 16_384) ~target_attributes
    ~source ~targets () =
  if grain <= 0 then invalid_arg "Pdk.Ops.copy_to_points: grain must be positive";
  let copies = Geometry.point_count targets and source_points = Geometry.point_count source
  and source_vertices = Geometry.vertex_count source
  and source_primitives = Geometry.primitive_count source in
  Result.bind (checked_product "Pdk.Ops.copy_to_points" copies source_points)
    (fun output_points ->
  Result.bind (checked_product "Pdk.Ops.copy_to_points" copies source_vertices)
    (fun output_vertices ->
  Result.bind (checked_product "Pdk.Ops.copy_to_points" copies source_primitives)
    (fun output_primitives ->
  Result.bind (point_float targets "pscale") (fun pscale ->
  Result.bind (point_float3 targets "scale") (fun scale ->
  Result.bind (point_float4 targets "orient") (fun orient ->
  Result.bind (point_float3 targets "N") (fun target_normal ->
  Result.bind (point_float3 targets "up") (fun target_up ->
  Result.bind (point_float3 targets "v") (fun target_velocity ->
  Result.bind (point_float4 targets "rot") (fun target_rotation ->
  Result.bind (point_float3 targets "trans") (fun target_translation ->
  Result.bind (point_float3 targets "pivot") (fun target_pivot ->
  Result.bind (point_affine_transform targets "transform") (fun target_transform ->
    let target_positions = Packed.Float3.Private.view (Geometry.positions targets)
    and source_positions = Packed.Float3.Private.view (Geometry.positions source)
    and source_topology = Topology.Private.view (Geometry.topology source) in
    let sx = Array.make copies 1. and sy = Array.make copies 1.
    and sz = Array.make copies 1. in
    if Option.is_none target_transform then begin
      Option.iter (fun values ->
        for index = 0 to copies - 1 do
          sx.(index) <- values.(index); sy.(index) <- values.(index);
          sz.(index) <- values.(index)
        done) pscale;
      Option.iter (fun values ->
        let values = Packed.Float3.Private.view values in
        for index = 0 to copies - 1 do
          sx.(index) <- sx.(index) *. values.x.(index);
          sy.(index) <- sy.(index) *. values.y.(index);
          sz.(index) <- sz.(index) *. values.z.(index)
        done) scale
    end;
    if Array.exists (fun value -> not (finite value)) sx
       || Array.exists (fun value -> not (finite value)) sy
       || Array.exists (fun value -> not (finite value)) sz
    then Error "Pdk.Ops.copy_to_points: target scales must be finite"
    else
      let r00 = Array.make copies 1. and r01 = Array.make copies 0.
      and r02 = Array.make copies 0. and r10 = Array.make copies 0.
      and r11 = Array.make copies 1. and r12 = Array.make copies 0.
      and r20 = Array.make copies 0. and r21 = Array.make copies 0.
      and r22 = Array.make copies 1. in
      let orientation_is_finite = ref true in
      let set_quaternion index x y z w =
        let scale = max (abs_float x) (max (abs_float y)
            (max (abs_float z) (abs_float w))) in
        if not (finite scale) then orientation_is_finite := false
        else if scale > 0. then begin
          let x = x /. scale and y = y /. scale and z = z /. scale
          and w = w /. scale in
          let length = sqrt ((x *. x) +. (y *. y) +. (z *. z) +. (w *. w)) in
          let x = x /. length and y = y /. length and z = z /. length
          and w = w /. length in
          let xx = x *. x and yy = y *. y and zz = z *. z
          and xy = x *. y and xz = x *. z and yz = y *. z
          and wx = w *. x and wy = w *. y and wz = w *. z in
          r00.(index) <- 1. -. (2. *. (yy +. zz));
          r01.(index) <- 2. *. (xy -. wz);
          r02.(index) <- 2. *. (xz +. wy);
          r10.(index) <- 2. *. (xy +. wz);
          r11.(index) <- 1. -. (2. *. (xx +. zz));
          r12.(index) <- 2. *. (yz -. wx);
          r20.(index) <- 2. *. (xz -. wy);
          r21.(index) <- 2. *. (yz +. wx);
          r22.(index) <- 1. -. (2. *. (xx +. yy))
        end in
      let target_direction = match target_normal with
        | Some _ -> target_normal
        | None -> target_velocity in
      (match target_transform with
      | Some (transform, width) ->
          if copies > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(copies - 1) (fun index ->
            if index land 4095 = 0 then Cancel.check_opt cancel;
            let first = transform.offsets.(index) in
            r00.(index) <- transform.values.(first);
            r01.(index) <- transform.values.(first + 1);
            r02.(index) <- transform.values.(first + 2);
            let second = first + if width = 9 then 3 else 4 in
            r10.(index) <- transform.values.(second);
            r11.(index) <- transform.values.(second + 1);
            r12.(index) <- transform.values.(second + 2);
            let third = first + if width = 9 then 6 else 8 in
            r20.(index) <- transform.values.(third);
            r21.(index) <- transform.values.(third + 1);
            r22.(index) <- transform.values.(third + 2)
          )
      | None -> match orient with
      | Some values ->
        let values = Packed.Float4.Private.view values in
        for index = 0 to copies - 1 do
          set_quaternion index values.x.(index) values.y.(index)
            values.z.(index) values.w.(index)
        done
      | None -> Option.iter (fun normals ->
          let normals = Packed.Float3.Private.view normals
          and up = Option.map Packed.Float3.Private.view target_up in
          for index = 0 to copies - 1 do
            let nx = normals.x.(index) and ny = normals.y.(index)
            and nz = normals.z.(index) in
            let nscale = max (abs_float nx) (max (abs_float ny) (abs_float nz)) in
            if not (finite nscale) then orientation_is_finite := false
            else if nscale > 0. then begin
              let nx = nx /. nscale and ny = ny /. nscale and nz = nz /. nscale in
              let nlength = sqrt ((nx *. nx) +. (ny *. ny) +. (nz *. nz)) in
              let zx = nx /. nlength and zy = ny /. nlength
              and zz = nz /. nlength in
              let aligned = match up with
                | None -> false
                | Some up ->
                    let ux = up.x.(index) and uy = up.y.(index)
                    and uz = up.z.(index) in
                    let uscale = max (abs_float ux)
                        (max (abs_float uy) (abs_float uz)) in
                    if not (finite uscale) then begin
                      orientation_is_finite := false; true
                    end else if uscale = 0. then false
                    else begin
                      let ux = ux /. uscale and uy = uy /. uscale
                      and uz = uz /. uscale in
                      let xx = (uy *. zz) -. (uz *. zy)
                      and xy = (uz *. zx) -. (ux *. zz)
                      and xz = (ux *. zy) -. (uy *. zx) in
                      let xscale = max (abs_float xx)
                          (max (abs_float xy) (abs_float xz)) in
                      if xscale <= 1e-20 then false
                      else begin
                        let xx = xx /. xscale and xy = xy /. xscale
                        and xz = xz /. xscale in
                        let xlength = sqrt
                            ((xx *. xx) +. (xy *. xy) +. (xz *. xz)) in
                        let xx = xx /. xlength and xy = xy /. xlength
                        and xz = xz /. xlength in
                        let yx = (zy *. xz) -. (zz *. xy)
                        and yy = (zz *. xx) -. (zx *. xz)
                        and yz = (zx *. xy) -. (zy *. xx) in
                        r00.(index) <- xx; r10.(index) <- xy; r20.(index) <- xz;
                        r01.(index) <- yx; r11.(index) <- yy; r21.(index) <- yz;
                        r02.(index) <- zx; r12.(index) <- zy; r22.(index) <- zz;
                        true
                      end
                    end in
              if not aligned then
                if zz <= -1. +. 1e-12 then set_quaternion index 0. 1. 0. 0.
                else set_quaternion index (-.zy) zx 0. (1. +. zz)
            end
          done) target_direction);
      let post_quaternion index x y z w =
        let scale = max (abs_float x) (max (abs_float y)
            (max (abs_float z) (abs_float w))) in
        if not (finite scale) then orientation_is_finite := false
        else if scale > 0. then begin
          let x = x /. scale and y = y /. scale and z = z /. scale
          and w = w /. scale in
          let length = sqrt ((x *. x) +. (y *. y) +. (z *. z) +. (w *. w)) in
          let x = x /. length and y = y /. length and z = z /. length
          and w = w /. length in
          let xx = x *. x and yy = y *. y and zz = z *. z
          and xy = x *. y and xz = x *. z and yz = y *. z
          and wx = w *. x and wy = w *. y and wz = w *. z in
          let a00 = 1. -. (2. *. (yy +. zz))
          and a01 = 2. *. (xy -. wz) and a02 = 2. *. (xz +. wy)
          and a10 = 2. *. (xy +. wz) and a11 = 1. -. (2. *. (xx +. zz))
          and a12 = 2. *. (yz -. wx) and a20 = 2. *. (xz -. wy)
          and a21 = 2. *. (yz +. wx) and a22 = 1. -. (2. *. (xx +. yy)) in
          let b00 = r00.(index) and b01 = r01.(index) and b02 = r02.(index)
          and b10 = r10.(index) and b11 = r11.(index) and b12 = r12.(index)
          and b20 = r20.(index) and b21 = r21.(index) and b22 = r22.(index) in
          r00.(index) <- (a00 *. b00) +. (a01 *. b10) +. (a02 *. b20);
          r01.(index) <- (a00 *. b01) +. (a01 *. b11) +. (a02 *. b21);
          r02.(index) <- (a00 *. b02) +. (a01 *. b12) +. (a02 *. b22);
          r10.(index) <- (a10 *. b00) +. (a11 *. b10) +. (a12 *. b20);
          r11.(index) <- (a10 *. b01) +. (a11 *. b11) +. (a12 *. b21);
          r12.(index) <- (a10 *. b02) +. (a11 *. b12) +. (a12 *. b22);
          r20.(index) <- (a20 *. b00) +. (a21 *. b10) +. (a22 *. b20);
          r21.(index) <- (a20 *. b01) +. (a21 *. b11) +. (a22 *. b21);
          r22.(index) <- (a20 *. b02) +. (a21 *. b12) +. (a22 *. b22)
        end in
      if Option.is_none target_transform then
        Option.iter (fun rotations ->
          let rotations = Packed.Float4.Private.view rotations in
          for index = 0 to copies - 1 do
            post_quaternion index rotations.x.(index) rotations.y.(index)
              rotations.z.(index) rotations.w.(index)
          done) target_rotation;
      if not !orientation_is_finite then
        Error "Pdk.Ops.copy_to_points: target orientations must be finite"
      else
      let owns_translation = Option.is_some target_translation
          || Option.is_some target_pivot || Option.is_some target_transform in
      let tx = if owns_translation then Array.copy target_positions.x
        else target_positions.x
      and ty = if owns_translation then Array.copy target_positions.y
        else target_positions.y
      and tz = if owns_translation then Array.copy target_positions.z
        else target_positions.z in
      Option.iter (fun translation ->
        let translation = Packed.Float3.Private.view translation in
        for index = 0 to copies - 1 do
          tx.(index) <- tx.(index) +. translation.x.(index);
          ty.(index) <- ty.(index) +. translation.y.(index);
          tz.(index) <- tz.(index) +. translation.z.(index)
        done) target_translation;
      (match target_transform with
      | Some (transform, 16) ->
          if copies > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(copies - 1) (fun index ->
            if index land 4095 = 0 then Cancel.check_opt cancel;
            let first = transform.offsets.(index) in
            tx.(index) <- tx.(index) +. transform.values.(first + 3);
            ty.(index) <- ty.(index) +. transform.values.(first + 7);
            tz.(index) <- tz.(index) +. transform.values.(first + 11)
          )
      | Some (_, 9) | None -> ()
      | Some _ -> assert false);
      Option.iter (fun pivot ->
        let pivot = Packed.Float3.Private.view pivot in
        if copies > 0 then Parallel.for_ ~chunk_size:grain ~start:0
          ~finish:(copies - 1) (fun index ->
          if index land 4095 = 0 then Cancel.check_opt cancel;
          let x = pivot.x.(index) *. sx.(index)
          and y = pivot.y.(index) *. sy.(index)
          and z = pivot.z.(index) *. sz.(index) in
          tx.(index) <- tx.(index) -. ((r00.(index) *. x)
              +. (r01.(index) *. y) +. (r02.(index) *. z));
          ty.(index) <- ty.(index) -. ((r10.(index) *. x)
              +. (r11.(index) *. y) +. (r12.(index) *. z));
          tz.(index) <- tz.(index) -. ((r20.(index) *. x)
              +. (r21.(index) *. y) +. (r22.(index) *. z))
        )) target_pivot;
      if Array.exists (fun value -> not (finite value)) tx
          || Array.exists (fun value -> not (finite value)) ty
          || Array.exists (fun value -> not (finite value)) tz then
        Error "Pdk.Ops.copy_to_points: target translations must be finite"
      else
      let px = Array.make output_points 0. and py = Array.make output_points 0.
      and pz = Array.make output_points 0. in
      if copies > 0 then Parallel.for_ ~chunk_size:(max 1 (grain / max 1 source_points))
          ~start:0 ~finish:(copies - 1) (fun copy ->
            let first = copy * source_points in
            for point = 0 to source_points - 1 do
              if point land 4095 = 0 then Cancel.check_opt cancel;
              let x = source_positions.x.(point) *. sx.(copy)
              and y = source_positions.y.(point) *. sy.(copy)
              and z = source_positions.z.(point) *. sz.(copy) in
              let output = first + point in
              px.(output) <- (r00.(copy) *. x) +. (r01.(copy) *. y)
                +. (r02.(copy) *. z) +. tx.(copy);
              py.(output) <- (r10.(copy) *. x) +. (r11.(copy) *. y)
                +. (r12.(copy) *. z) +. ty.(copy);
              pz.(output) <- (r20.(copy) *. x) +. (r21.(copy) *. y)
                +. (r22.(copy) *. z) +. tz.(copy)
            done);
      let matrix_normals_valid = ref true in
      (match target_transform with
      | None -> ()
      | Some _ ->
          let has_normals = Geometry.find_attribute ~owner:Attribute.Point "N" source
                <> None
              || Geometry.find_attribute ~owner:Attribute.Vertex "N" source <> None in
          if has_normals then begin
            let singular = Bytes.make copies '\000' in
            if copies > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(copies - 1) (fun index ->
              if index land 4095 = 0 then Cancel.check_opt cancel;
              let a = r00.(index) and b = r01.(index) and c = r02.(index)
              and d = r10.(index) and e = r11.(index) and f = r12.(index)
              and g = r20.(index) and h = r21.(index) and i = r22.(index) in
              let matrix_scale = max (abs_float a) (max (abs_float b)
                  (max (abs_float c) (max (abs_float d) (max (abs_float e)
                    (max (abs_float f) (max (abs_float g)
                      (max (abs_float h) (abs_float i)))))))) in
              if matrix_scale = 0. then Bytes.set singular index '\001'
              else begin
                let a = a /. matrix_scale and b = b /. matrix_scale
                and c = c /. matrix_scale and d = d /. matrix_scale
                and e = e /. matrix_scale and f = f /. matrix_scale
                and g = g /. matrix_scale and h = h /. matrix_scale
                and i = i /. matrix_scale in
                let c00 = (e *. i) -. (f *. h)
                and c01 = (f *. g) -. (d *. i)
                and c02 = (d *. h) -. (e *. g)
                and c10 = (c *. h) -. (b *. i)
                and c11 = (a *. i) -. (c *. g)
                and c12 = (b *. g) -. (a *. h)
                and c20 = (b *. f) -. (c *. e)
                and c21 = (c *. d) -. (a *. f)
                and c22 = (a *. e) -. (b *. d) in
                let determinant = (a *. c00) +. (b *. c01) +. (c *. c02) in
                if abs_float determinant <= 1e-20 then
                  Bytes.set singular index '\001'
                else begin
                  let sign = if determinant < 0. then -1. else 1. in
                  r00.(index) <- c00 *. sign; r01.(index) <- c01 *. sign;
                  r02.(index) <- c02 *. sign; r10.(index) <- c10 *. sign;
                  r11.(index) <- c11 *. sign; r12.(index) <- c12 *. sign;
                  r20.(index) <- c20 *. sign; r21.(index) <- c21 *. sign;
                  r22.(index) <- c22 *. sign
                end
              end
            );
            if Bytes.contains singular '\001' then matrix_normals_valid := false
          end);
      let vertex_points = Array.make output_vertices 0
      and primitive_offsets = Array.make (output_primitives + 1) 0
      and primitive_kinds = Bytes.make output_primitives '\000' in
      for copy = 0 to copies - 1 do
        Cancel.check_opt cancel;
        let point_offset = copy * source_points and vertex_offset = copy * source_vertices
        and primitive_offset = copy * source_primitives in
        for vertex = 0 to source_vertices - 1 do
          vertex_points.(vertex_offset + vertex) <-
            source_topology.vertex_points.(vertex) + point_offset
        done;
        for primitive = 0 to source_primitives - 1 do
          primitive_offsets.(primitive_offset + primitive) <-
            source_topology.primitive_offsets.(primitive) + vertex_offset
        done;
        Bytes.blit source_topology.primitive_kinds 0 primitive_kinds
          primitive_offset source_primitives
      done;
      primitive_offsets.(output_primitives) <- output_vertices;
      let topology = Topology.Private.create_validated_owned
          ~point_count:output_points ~vertex_points ~primitive_offsets
          ~primitive_kinds in
      let rec build_attributes result = function
        | [] -> Ok (List.rev result)
        | attribute :: rest
          when Attribute.name attribute = "N"
            && (Attribute.owner attribute = Attribute.Point
                || Attribute.owner attribute = Attribute.Vertex) ->
            build_attributes result rest
        | attribute :: rest ->
            Result.bind (repeat_attribute ?cancel ~grain copies attribute)
            (fun attribute -> build_attributes (attribute :: result) rest) in
      Result.bind (build_attributes [] (Geometry.attributes source)) (fun attributes ->
        let output_positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
        let edge_groups = match Geometry.edge_groups source with
          | [] -> []
          | source_groups ->
              let source_index = Topology_index.create ?cancel
                  (Geometry.topology source)
              in
              List.map (fun group -> Edge_group.replicate_exact_copies ?cancel
                ~source_topology:(Geometry.topology source) ~source_index
                ~target_topology:topology ~copies group |> get_ok) source_groups in
        let base = Geometry.create ~positions:output_positions ~topology
            ~attributes ~edge_groups () in
        Result.bind base (fun geometry ->
          let geometry = ref geometry in
          List.iter (fun owner ->
            if not !matrix_normals_valid then ()
            else match Geometry.find_attribute ~owner "N" source with
            | None -> ()
            | Some attribute ->
                (match Attribute.get (Attribute.normal ~owner) attribute with
                 | None -> ()
                 | Some values ->
                     let values = Packed.Float3.Private.view values in
                     let source_count = Array.length values.x
                     and count = copies * Array.length values.x in
                     let nx = Array.make count 0. and ny = Array.make count 0.
                     and nz = Array.make count 0. in
                     if copies > 0 then Parallel.for_
                       ~chunk_size:(max 1 (grain / max 1 source_count))
                       ~start:0 ~finish:(copies - 1) (fun copy ->
                         let first = copy * source_count in
                         for index = 0 to source_count - 1 do
                           if index land 4095 = 0 then Cancel.check_opt cancel;
                           let ix = if abs_float sx.(copy) <= 1e-20 then 0.
                             else values.x.(index) /. sx.(copy)
                           and iy = if abs_float sy.(copy) <= 1e-20 then 0.
                             else values.y.(index) /. sy.(copy)
                           and iz = if abs_float sz.(copy) <= 1e-20 then 0.
                             else values.z.(index) /. sz.(copy) in
                           let x = (r00.(copy) *. ix) +. (r01.(copy) *. iy)
                             +. (r02.(copy) *. iz)
                           and y = (r10.(copy) *. ix) +. (r11.(copy) *. iy)
                             +. (r12.(copy) *. iz)
                           and z = (r20.(copy) *. ix) +. (r21.(copy) *. iy)
                             +. (r22.(copy) *. iz) in
                           let length = sqrt ((x*.x) +. (y*.y) +. (z*.z)) in
                           if length > 1e-20 then begin
                             nx.(first + index) <- x /. length;
                             ny.(first + index) <- y /. length;
                             nz.(first + index) <- z /. length
                           end
                         done);
                     let normal = Packed.Float3.Private.of_owned_exn ~x:nx ~y:ny ~z:nz in
                     let attribute = Attribute.create_key_owned
                         (Attribute.normal ~owner) normal |> get_ok in
                     geometry := Geometry.with_attribute attribute !geometry |> get_ok))
            [Attribute.Point; Attribute.Vertex];
          let output_groups = List.map (fun group ->
            repeat_group ?cancel ~grain copies group)
              (Geometry.groups source) in
          let result = List.fold_left (fun result group ->
            Result.bind result (Geometry.with_group group)) (Ok !geometry)
            output_groups in
          Result.bind result (apply_copy_target_rules ?cancel ~grain ~copies
            ~source_points ~source_vertices ~source_primitives target_attributes
            targets))))))))))))))))

type copy_piece_values = Copy_piece_int of int array
  | Copy_piece_text of string array

let copy_piece_values attribute = match Attribute.Private.storage attribute with
  | Attribute.Int values -> Ok (Copy_piece_int values)
  | Attribute.Text values -> Ok (Copy_piece_text values)
  | _ -> Error (Printf.sprintf
      "Pdk.Ops.copy_to_points: piece attribute %S must use int or text storage"
      (Attribute.name attribute))

let plan_copy_pieces ?cancel ~name source targets =
  let target_attribute = Geometry.find_attribute ~owner:Attribute.Point name
      targets in
  match target_attribute with
  | None -> Error (Printf.sprintf
      "Pdk.Ops.copy_to_points: target point piece attribute %S does not exist"
      name)
  | Some target_attribute ->
      Result.bind (copy_piece_values target_attribute) (fun target_values ->
      let source_primitive = Geometry.find_attribute
          ~owner:Attribute.Primitive name source
      and source_point = Geometry.find_attribute ~owner:Attribute.Point name source in
      let source_attribute = match source_primitive, source_point with
        | Some attribute, _ -> Some (`Primitive, attribute)
        | None, Some attribute -> Some (`Point, attribute)
        | None, None -> None in
      match source_attribute, target_values with
      | None, Copy_piece_text _ -> Error (Printf.sprintf
          "Pdk.Ops.copy_to_points: text target piece attribute %S requires a matching source point or primitive attribute"
          name)
      | None, Copy_piece_int target_values ->
          let piece_count = Geometry.primitive_count source in
          let primitive_pieces = Array.init piece_count Fun.id in
          let target_pieces = Array.mapi (fun target primitive ->
            if target land 4095 = 0 then Cancel.check_opt cancel;
            if primitive >= 0 && primitive < piece_count then primitive else -1)
              target_values in
          Ok (piece_count, None, primitive_pieces, target_pieces)
      | Some (owner, attribute), _ ->
          Result.bind (copy_piece_values attribute) (fun source_values ->
          let type_matches = match source_values, target_values with
            | Copy_piece_int _, Copy_piece_int _
            | Copy_piece_text _, Copy_piece_text _ -> true
            | _ -> false in
          if not type_matches then Error (Printf.sprintf
            "Pdk.Ops.copy_to_points: source and target piece attribute %S storage must match"
            name)
          else
            let next_piece = ref 0 in
            let point_pieces, primitive_pieces, target_pieces =
              match source_values, target_values with
              | Copy_piece_int source_values, Copy_piece_int target_values ->
                  let pieces = Hashtbl.create (max 16 (Array.length source_values)) in
                  let intern value = match Hashtbl.find_opt pieces value with
                    | Some piece -> piece
                    | None -> let piece = !next_piece in incr next_piece;
                        Hashtbl.add pieces value piece; piece in
                  let source_pieces = Array.map intern source_values in
                  let target_pieces = Array.mapi (fun target value ->
                    if target land 4095 = 0 then Cancel.check_opt cancel;
                    Option.value ~default:(-1) (Hashtbl.find_opt pieces value))
                      target_values in
                  (match owner with
                   | `Primitive -> None, source_pieces, target_pieces
                   | `Point ->
                       let topology = Topology.Private.view
                           (Geometry.topology source) in
                       let primitive_pieces = Array.init
                           (Geometry.primitive_count source) (fun primitive ->
                             let first = topology.primitive_offsets.(primitive)
                             and last = topology.primitive_offsets.(primitive + 1) in
                             let piece = source_pieces.(topology.vertex_points.(first)) in
                             let coherent = ref true in
                             for vertex = first + 1 to last - 1 do
                               if source_pieces.(topology.vertex_points.(vertex)) <> piece
                               then coherent := false
                             done;
                             if !coherent then piece else -1) in
                       Some source_pieces, primitive_pieces, target_pieces)
              | Copy_piece_text source_values, Copy_piece_text target_values ->
                  let pieces = Hashtbl.create (max 16 (Array.length source_values)) in
                  let intern value = match Hashtbl.find_opt pieces value with
                    | Some piece -> piece
                    | None -> let piece = !next_piece in incr next_piece;
                        Hashtbl.add pieces value piece; piece in
                  let source_pieces = Array.map intern source_values in
                  let target_pieces = Array.mapi (fun target value ->
                    if target land 4095 = 0 then Cancel.check_opt cancel;
                    Option.value ~default:(-1) (Hashtbl.find_opt pieces value))
                      target_values in
                  (match owner with
                   | `Primitive -> None, source_pieces, target_pieces
                   | `Point ->
                       let topology = Topology.Private.view
                           (Geometry.topology source) in
                       let primitive_pieces = Array.init
                           (Geometry.primitive_count source) (fun primitive ->
                             let first = topology.primitive_offsets.(primitive)
                             and last = topology.primitive_offsets.(primitive + 1) in
                             let piece = source_pieces.(topology.vertex_points.(first)) in
                             let coherent = ref true in
                             for vertex = first + 1 to last - 1 do
                               if source_pieces.(topology.vertex_points.(vertex)) <> piece
                               then coherent := false
                             done;
                             if !coherent then piece else -1) in
                       Some source_pieces, primitive_pieces, target_pieces)
              | _ -> assert false in
            Ok (!next_piece, point_pieces, primitive_pieces, target_pieces)))

let without_detail_attributes geometry =
  Geometry.attributes geometry |> List.fold_left (fun geometry attribute ->
    if Attribute.owner attribute = Attribute.Detail then
      Geometry.without_attribute ~owner:Attribute.Detail
        (Attribute.name attribute) geometry
    else geometry) geometry

let restore_detail_attributes source geometry =
  Geometry.attributes source |> List.fold_left (fun result attribute ->
    if Attribute.owner attribute <> Attribute.Detail then result
    else Result.bind result (Geometry.with_attribute attribute)) (Ok geometry)

let array_is_identity values =
  let identity = ref true in
  let index = ref 0 in
  while !identity && !index < Array.length values do
    if values.(!index) <> !index then identity := false;
    incr index
  done;
  !identity

let empty_copy_targets ?cancel ~grain targets =
  let empty = Group.init ~owner:Group.Point ~name:"copy_piece_empty"
      (Geometry.point_count targets) (fun _ -> false) in
  Deletion.delete ?cancel ~grain ~selected:false empty targets

let checked_piece_cardinality label target_counts source_pieces owner_count =
  let rec loop piece total =
    if piece = Array.length target_counts then Ok ()
    else Result.bind (checked_product "Pdk.Ops.copy_to_points"
        target_counts.(piece) (owner_count source_pieces.(piece))) (fun count ->
      if total > max_int - count then Error (Printf.sprintf
        "Pdk.Ops.copy_to_points: output %s cardinality exceeds OCaml array limits"
        label)
      else loop (piece + 1) (total + count)) in
  loop 0 0

let copy_to_points_pieces ?cancel ~grain ~target_attributes ~piece_attribute
    ~source ~targets () =
  Result.bind (plan_copy_pieces ?cancel ~name:piece_attribute source targets)
    (fun (piece_count, point_pieces, primitive_pieces, target_pieces) ->
  let source_pieces = Deletion.primitive_partitions ?cancel ~grain ~piece_count
      ?point_pieces ~primitive_pieces source
  and no_target_primitives = Array.make (Geometry.primitive_count targets) (-1) in
  let target_pieces_geometry = Deletion.primitive_partitions ?cancel ~grain
      ~piece_count ~point_pieces:target_pieces
      ~primitive_pieces:no_target_primitives targets in
  let target_counts = Array.map Geometry.point_count target_pieces_geometry in
  let active_count = Array.fold_left (fun count targets ->
      if targets = 0 then count else count + 1) 0 target_counts in
  let cardinalities =
    Result.bind (checked_piece_cardinality "point" target_counts source_pieces
      Geometry.point_count) (fun () ->
    Result.bind (checked_piece_cardinality "vertex" target_counts source_pieces
      Geometry.vertex_count) (fun () ->
    checked_piece_cardinality "primitive" target_counts source_pieces
      Geometry.primitive_count)) in
  Result.bind cardinalities (fun () ->
  if active_count = 0 then
    Result.bind (empty_copy_targets ?cancel ~grain targets) (fun targets ->
      copy_to_points_all ?cancel ~grain ~target_attributes ~source ~targets ())
  else begin
    let outputs = Array.make piece_count None in
    let rec cook piece =
      if piece = piece_count then Ok ()
      else if target_counts.(piece) = 0 then cook (piece + 1)
      else Result.bind (copy_to_points_all ?cancel ~grain ~target_attributes
          ~source:source_pieces.(piece) ~targets:target_pieces_geometry.(piece) ())
        (fun output -> outputs.(piece) <- Some output; cook (piece + 1)) in
    Result.bind (cook 0) (fun () ->
    let source_has_normal owner =
      Geometry.find_attribute ~owner "N" source <> None in
    let drop_point_normal = source_has_normal Attribute.Point
      && Array.exists (function None -> false | Some output ->
        Geometry.find_attribute ~owner:Attribute.Point "N" output = None)
        outputs
    and drop_vertex_normal = source_has_normal Attribute.Vertex
      && Array.exists (function None -> false | Some output ->
        Geometry.find_attribute ~owner:Attribute.Vertex "N" output = None)
        outputs in
    let normalized_outputs = Array.map (Option.map (fun output ->
      let output = if drop_point_normal then
          Geometry.without_attribute ~owner:Attribute.Point "N" output
        else output in
      if drop_vertex_normal then
        Geometry.without_attribute ~owner:Attribute.Vertex "N" output
      else output)) outputs in
    let point_bases = Array.make piece_count 0
    and primitive_bases = Array.make piece_count 0
    and point_total = ref 0 and primitive_total = ref 0
    and batches = ref [] in
    Array.iteri (fun piece output -> match output with
      | None -> ()
      | Some output ->
          point_bases.(piece) <- !point_total;
          primitive_bases.(piece) <- !primitive_total;
          point_total := !point_total + Geometry.point_count output;
          primitive_total := !primitive_total + Geometry.primitive_count output;
          batches := without_detail_attributes output :: !batches)
      normalized_outputs;
    Result.bind (merge ?cancel ~grain (List.rev !batches)) (fun merged ->
    Result.bind (restore_detail_attributes source merged) (fun merged ->
    let target_count = Array.length target_pieces in
    let target_ranks = Array.make target_count (-1)
    and piece_next = Array.make piece_count 0
    and point_offsets = Array.make (target_count + 1) 0
    and primitive_offsets = Array.make (target_count + 1) 0 in
    for target = 0 to target_count - 1 do
      let piece = target_pieces.(target) in
      if piece >= 0 then begin
        target_ranks.(target) <- piece_next.(piece);
        piece_next.(piece) <- piece_next.(piece) + 1;
        point_offsets.(target + 1) <- point_offsets.(target)
          + Geometry.point_count source_pieces.(piece);
        primitive_offsets.(target + 1) <- primitive_offsets.(target)
          + Geometry.primitive_count source_pieces.(piece)
      end else begin
        point_offsets.(target + 1) <- point_offsets.(target);
        primitive_offsets.(target + 1) <- primitive_offsets.(target)
      end
    done;
    let point_permutation = Array.make point_offsets.(target_count) 0
    and primitive_permutation = Array.make primitive_offsets.(target_count) 0 in
    if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(target_count - 1) (fun target ->
        if target land 4095 = 0 then Cancel.check_opt cancel;
        let piece = target_pieces.(target) in
        if piece >= 0 then begin
          let rank = target_ranks.(target)
          and points = Geometry.point_count source_pieces.(piece)
          and primitives = Geometry.primitive_count source_pieces.(piece) in
          let source_point = point_bases.(piece) + (rank * points)
          and source_primitive = primitive_bases.(piece) + (rank * primitives) in
          for local = 0 to points - 1 do
            point_permutation.(point_offsets.(target) + local) <-
              source_point + local
          done;
          for local = 0 to primitives - 1 do
            primitive_permutation.(primitive_offsets.(target) + local) <-
              source_primitive + local
          done
        end);
    let merged = if array_is_identity point_permutation then merged
      else Ordering.apply_points ?cancel ~grain point_permutation merged in
    let merged = if array_is_identity primitive_permutation then merged
      else Ordering.apply_primitives ?cancel ~grain primitive_permutation merged in
    Ok merged)))
  end))

let copy_to_points ?cancel ?(grain = 16_384) ?source_primitives ?target_points
    ?piece_attribute ?(target_attributes = []) ~source ~targets () =
  if grain <= 0 then invalid_arg "Pdk.Ops.copy_to_points: grain must be positive";
  Result.bind (compile_copy_target_rules target_attributes) (fun target_attributes ->
  let prepare_source = match source_primitives with
    | None -> Ok source
    | Some group when Group.owner group <> Group.Primitive ->
        Error "Pdk.Ops.copy_to_points: source selection must own primitives"
    | Some group -> Deletion.delete ?cancel ~grain ~selected:false
        ~compact_points:true group source in
  Result.bind prepare_source (fun source ->
    let prepare_targets = match target_points with
      | None -> Ok targets
      | Some group when Group.owner group <> Group.Point ->
          Error "Pdk.Ops.copy_to_points: target selection must own points"
      | Some group -> Deletion.delete ?cancel ~grain ~selected:false group targets in
    Result.bind prepare_targets (fun targets -> match piece_attribute with
      | None -> copy_to_points_all ?cancel ~grain ~target_attributes ~source
          ~targets ()
      | Some name when String.trim name = "" ->
          Error "Pdk.Ops.copy_to_points: piece attribute name must not be empty"
      | Some name -> copy_to_points_pieces ?cancel ~grain ~target_attributes
          ~piece_attribute:name ~source ~targets ())))

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

let dissolve ?cancel ?grain ?edges ?operation ?bridge_policy
    ?remove_inline_points ?collinearity_tolerance ?remove_unused_points
    ?create_boundary_curves ?recompute_normals geometry =
  Dissolve.run ?cancel ?grain ?edges ?operation ?bridge_policy
    ?remove_inline_points ?collinearity_tolerance ?remove_unused_points
    ?create_boundary_curves ?recompute_normals geometry

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

let point_generate ?cancel ?(grain = 16_384) ?points ?keep_input ?seed
    ?generated_group ?source_point_attribute ?source_index_attribute
    ?copy_point_attributes ?copy_detail_attributes ~mode geometry =
  Point_generate.run ?cancel ~grain ?points ?keep_input ?seed ?generated_group
    ?source_point_attribute ?source_index_attribute ?copy_point_attributes
    ?copy_detail_attributes ~mode geometry

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

let color_by_height ?cancel ?(grain = 16_384) ~low ~high geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.color_by_height: grain must be positive";
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let count = Array.length positions.y in
  let minimum = ref infinity and maximum = ref neg_infinity in
  for index = 0 to count - 1 do
    if index land 16383 = 0 then Cancel.check_opt cancel;
    let value = positions.y.(index) in
    if value < !minimum then minimum := value;
    if value > !maximum then maximum := value
  done;
  let lr, lg, lb, la = Color.to_floats low and hr, hg, hb, ha = Color.to_floats high in
  let r = Array.make count lr and g = Array.make count lg
  and b = Array.make count lb and a = Array.make count la in
  let extent = !maximum -. !minimum in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun index ->
        if index land 4095 = 0 then Cancel.check_opt cancel;
        let t = if extent <= 1e-15 then 0. else (positions.y.(index) -. !minimum) /. extent in
        r.(index) <- lr +. ((hr -. lr) *. t);
        g.(index) <- lg +. ((hg -. lg) *. t);
        b.(index) <- lb +. ((hb -. lb) *. t);
        a.(index) <- la +. ((ha -. la) *. t));
  let values = Packed.Float4.of_owned ~x:r ~y:g ~z:b ~w:a |> get_ok in
  let attribute = Attribute.create_key_owned
      (Attribute.color ~owner:Attribute.Point) values |> get_ok in
  Geometry.with_attribute attribute geometry

let[@inline] clean_length dx dy dz =
  let scale = Float.max (abs_float dx)
      (Float.max (abs_float dy) (abs_float dz)) in
  if scale = 0. then 0.
  else if not (finite scale) then infinity
  else
    let x = dx /. scale and y = dy /. scale and z = dz /. scale in
    scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z))

let[@inline] clean_point_distance positions a b =
  let scale = Float.max
      (Float.max (abs_float positions.Packed.Float3.Private.x.(a))
         (abs_float positions.x.(b)))
      (Float.max
         (Float.max (abs_float positions.y.(a)) (abs_float positions.y.(b)))
         (Float.max (abs_float positions.z.(a)) (abs_float positions.z.(b)))) in
  if scale = 0. then 0.
  else if not (finite scale) then infinity
  else clean_length
      ((positions.x.(b) /. scale) -. (positions.x.(a) /. scale))
      ((positions.y.(b) /. scale) -. (positions.y.(a) /. scale))
      ((positions.z.(b) /. scale) -. (positions.z.(a) /. scale)) *. scale

let[@inline] clean_triangle_is_degenerate ~epsilon positions a b c =
  let ax = positions.Packed.Float3.Private.x.(a)
  and ay = positions.y.(a) and az = positions.z.(a)
  and bx = positions.x.(b) and by = positions.y.(b) and bz = positions.z.(b)
  and cx = positions.x.(c) and cy = positions.y.(c) and cz = positions.z.(c) in
  if not (finite ax && finite ay && finite az && finite bx && finite by
      && finite bz && finite cx && finite cy && finite cz) then true
  else
    let ux = bx -. ax and uy = by -. ay and uz = bz -. az
    and vx = cx -. ax and vy = cy -. ay and vz = cz -. az in
    let nx = (uy *. vz) -. (uz *. vy)
    and ny = (uz *. vx) -. (ux *. vz)
    and nz = (ux *. vy) -. (uy *. vx) in
    if finite nx && finite ny && finite nz then
      0.5 *. clean_length nx ny nz <= epsilon *. epsilon
    else
      let scale = Float.max (Float.max (Float.max (abs_float ax) (abs_float ay))
          (Float.max (abs_float az) (abs_float bx)))
          (Float.max (Float.max (abs_float by) (abs_float bz))
             (Float.max (abs_float cx) (Float.max (abs_float cy) (abs_float cz)))) in
      if scale = 0. then true
      else
        let ax = ax /. scale and ay = ay /. scale and az = az /. scale in
        let ux = (bx /. scale) -. ax and uy = (by /. scale) -. ay
        and uz = (bz /. scale) -. az
        and vx = (cx /. scale) -. ax and vy = (cy /. scale) -. ay
        and vz = (cz /. scale) -. az in
        let nx = (uy *. vz) -. (uz *. vy)
        and ny = (uz *. vx) -. (ux *. vz)
        and nz = (ux *. vy) -. (uy *. vx)
        and ratio = epsilon /. scale in
        0.5 *. clean_length nx ny nz <= ratio *. ratio

let clean_delete_degenerate ?cancel ~grain ?primitives ~epsilon geometry =
  let primitive_count = Geometry.primitive_count geometry in
  if match primitives with
    | Some group -> Group.owner group <> Group.Primitive
        || Group.length group <> primitive_count
    | None -> false
  then Error "Facet selection must be a matching primitive group"
  else if primitive_count = 0 then Ok geometry
  else
    let positions = Packed.Float3.Private.view (Geometry.positions geometry)
    and topology_value = Geometry.topology geometry
    and flags = Bytes.make primitive_count '\000' in
    let topology = Topology.Private.view topology_value in
    if Topology.all_triangles topology_value then
      Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(primitive_count - 1)
        (fun primitive ->
          if primitive land 4_095 = 0 then Cancel.check_opt cancel;
          let first = topology.primitive_offsets.(primitive) in
          if (match primitives with None -> true
                | Some group -> Group.mem primitive group)
              && clean_triangle_is_degenerate ~epsilon positions
              topology.vertex_points.(first)
              topology.vertex_points.(first + 1)
              topology.vertex_points.(first + 2) then
            Bytes.unsafe_set flags primitive '\001')
    else begin
      let scratch_a = Array.make primitive_count 0.
      and scratch_b = Array.make primitive_count 0.
      and scratch_c = Array.make primitive_count 0.
      and scratch_d = Array.make primitive_count 0. in
      Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(primitive_count - 1)
      (fun primitive ->
        if primitive land 4_095 = 0 then Cancel.check_opt cancel;
        let first = topology.primitive_offsets.(primitive)
        and last = topology.primitive_offsets.(primitive + 1)
        and kind = Bytes.unsafe_get topology.primitive_kinds primitive in
        if match primitives with Some group -> not (Group.mem primitive group)
          | None -> false then ()
        else if kind = '\000' then begin
          let origin = topology.vertex_points.(first) in
          let ox = positions.x.(origin) and oy = positions.y.(origin)
          and oz = positions.z.(origin) in
          for vertex = first to last - 1 do
            let next = if vertex + 1 < last then vertex + 1 else first in
            let a = topology.vertex_points.(vertex)
            and b = topology.vertex_points.(next) in
            let ax = positions.x.(a) -. ox and ay = positions.y.(a) -. oy
            and az = positions.z.(a) -. oz
            and bx = positions.x.(b) -. ox and by = positions.y.(b) -. oy
            and bz = positions.z.(b) -. oz in
            if not (finite positions.x.(a) && finite positions.y.(a)
                && finite positions.z.(a)) then
              Bytes.unsafe_set flags primitive '\001'
            else if Bytes.unsafe_get flags primitive <> '\001' then begin
              let nx = scratch_b.(primitive) +. ((ay *. bz) -. (az *. by))
              and ny = scratch_c.(primitive) +. ((az *. bx) -. (ax *. bz))
              and nz = scratch_d.(primitive) +. ((ax *. by) -. (ay *. bx)) in
              scratch_b.(primitive) <- nx;
              scratch_c.(primitive) <- ny;
              scratch_d.(primitive) <- nz;
              if not (finite nx && finite ny && finite nz) then
                Bytes.unsafe_set flags primitive '\002'
            end
          done;
          if Bytes.unsafe_get flags primitive = '\000' then begin
            let area = 0.5 *. clean_length scratch_b.(primitive)
                scratch_c.(primitive) scratch_d.(primitive) in
            if area <= epsilon *. epsilon then
              Bytes.unsafe_set flags primitive '\001'
          end else if Bytes.unsafe_get flags primitive = '\002' then begin
            Bytes.unsafe_set flags primitive '\000';
            scratch_b.(primitive) <- 0.;
            scratch_c.(primitive) <- 0.;
            scratch_d.(primitive) <- 0.;
            for vertex = first to last - 1 do
              let point = topology.vertex_points.(vertex) in
              scratch_a.(primitive) <- Float.max scratch_a.(primitive)
                  (abs_float positions.x.(point));
              scratch_a.(primitive) <- Float.max scratch_a.(primitive)
                  (abs_float positions.y.(point));
              scratch_a.(primitive) <- Float.max scratch_a.(primitive)
                  (abs_float positions.z.(point))
            done;
            let scale = scratch_a.(primitive) in
            let ox = positions.x.(origin) /. scale
            and oy = positions.y.(origin) /. scale
            and oz = positions.z.(origin) /. scale in
            for vertex = first to last - 1 do
              let next = if vertex + 1 < last then vertex + 1 else first in
              let a = topology.vertex_points.(vertex)
              and b = topology.vertex_points.(next) in
              let ax = (positions.x.(a) /. scale) -. ox
              and ay = (positions.y.(a) /. scale) -. oy
              and az = (positions.z.(a) /. scale) -. oz
              and bx = (positions.x.(b) /. scale) -. ox
              and by = (positions.y.(b) /. scale) -. oy
              and bz = (positions.z.(b) /. scale) -. oz in
              scratch_b.(primitive) <- scratch_b.(primitive)
                +. ((ay *. bz) -. (az *. by));
              scratch_c.(primitive) <- scratch_c.(primitive)
                +. ((az *. bx) -. (ax *. bz));
              scratch_d.(primitive) <- scratch_d.(primitive)
                +. ((ax *. by) -. (ay *. bx))
            done;
            let area = 0.5 *. clean_length scratch_b.(primitive)
                scratch_c.(primitive) scratch_d.(primitive)
            and ratio = epsilon /. scale in
            if area <= ratio *. ratio then
              Bytes.unsafe_set flags primitive '\001'
          end
        end else begin
          let size = last - first in
          let edges = size - 1 + if kind = '\001' then 0 else 1 in
          for edge = 0 to edges - 1 do
            let a = topology.vertex_points.(first + (edge mod size))
            and b = topology.vertex_points.
                (first + ((edge + 1) mod size)) in
            scratch_a.(primitive) <- scratch_a.(primitive)
              +. clean_point_distance positions a b
          done;
          if not (finite scratch_a.(primitive))
              || scratch_a.(primitive) <= epsilon then
            Bytes.unsafe_set flags primitive '\001'
        end)
    end;
    let removed = ref false in
    Bytes.iter (fun flag -> if flag <> '\000' then removed := true) flags;
    if not !removed then Ok geometry
    else
      let selection = Group.init ~grain ~owner:Group.Primitive
          ~name:"__clean_degenerate" primitive_count
          (fun primitive -> Bytes.get flags primitive <> '\000') in
      Deletion.delete ?cancel ~grain selection geometry

let clean_delete_nan_points ?cancel ~grain geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let point_count = Geometry.point_count geometry in
  if point_count = 0 then Ok geometry
  else
    let flags = Bytes.make point_count '\000' in
    Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
      (fun point ->
        if point land 16_383 = 0 then Cancel.check_opt cancel;
        if positions.x.(point) <> positions.x.(point)
            || positions.y.(point) <> positions.y.(point)
            || positions.z.(point) <> positions.z.(point)
        then Bytes.set flags point '\001');
    let removed = ref false in
    Bytes.iter (fun flag -> if flag <> '\000' then removed := true) flags;
    if not !removed then Ok geometry
    else
      let selection = Group.init ~grain ~owner:Group.Point
          ~name:"__clean_nan_points" point_count
          (fun point -> Bytes.get flags point <> '\000') in
      Deletion.delete ?cancel ~grain selection geometry

let[@inline] clean_cycle_point topology first size start direction offset =
  let local = (start + (direction * offset)) mod size in
  topology.Topology.Private.vertex_points.
    (first + if local < 0 then local + size else local)

let clean_minimal_rotation_into topology first size direction primitive
    work_left work_right work_offset =
  work_left.(primitive) <- 0;
  work_right.(primitive) <- 1;
  work_offset.(primitive) <- 0;
  while work_left.(primitive) < size && work_right.(primitive) < size
      && work_offset.(primitive) < size do
    let offset = work_offset.(primitive) in
    let a = clean_cycle_point topology first size work_left.(primitive)
        direction offset
    and b = clean_cycle_point topology first size work_right.(primitive)
        direction offset in
    if a = b then work_offset.(primitive) <- offset + 1
    else begin
      if a > b then begin
        work_left.(primitive) <- work_left.(primitive) + offset + 1;
        if work_left.(primitive) = work_right.(primitive) then
          work_left.(primitive) <- work_left.(primitive) + 1
      end else begin
        work_right.(primitive) <- work_right.(primitive) + offset + 1;
        if work_right.(primitive) = work_left.(primitive) then
          work_right.(primitive) <- work_right.(primitive) + 1
      end;
      work_offset.(primitive) <- 0
    end
  done;
  min work_left.(primitive) work_right.(primitive) mod size

let clean_delete_overlaps_general ?cancel ~grain ~policy geometry =
  let topology = Topology.Private.view (Geometry.topology geometry) in
  let primitive_count = Geometry.primitive_count geometry in
  let sizes = Array.make primitive_count 0 and starts = Array.make primitive_count 0
  and directions = Array.make primitive_count 1
  and hashes = Array.make primitive_count 0
  and reverse_starts = Array.make primitive_count 0
  and work_left = Array.make primitive_count 0
  and work_right = Array.make primitive_count 0
  and work_offset = Array.make primitive_count 0
  and comparisons = Array.make primitive_count 0 in
  let polygon_count = ref 0 in
  for primitive = 0 to primitive_count - 1 do
    if Bytes.get topology.primitive_kinds primitive = '\000' then incr polygon_count
  done;
  if !polygon_count = 0 then Ok geometry
  else if !polygon_count > Sys.max_array_length / 4 then
    Error "Pdk.Ops.clean: overlap table exceeds array limits"
  else begin
    Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(primitive_count - 1)
      (fun primitive ->
        if primitive land 4_095 = 0 then Cancel.check_opt cancel;
        if Bytes.get topology.primitive_kinds primitive = '\000' then begin
          let first = topology.primitive_offsets.(primitive)
          and size = topology.primitive_offsets.(primitive + 1)
            - topology.primitive_offsets.(primitive) in
          starts.(primitive) <- clean_minimal_rotation_into topology first size 1
              primitive work_left work_right work_offset;
          reverse_starts.(primitive) <- clean_minimal_rotation_into topology first
              size (-1) primitive work_left work_right work_offset;
          work_offset.(primitive) <- 0;
          comparisons.(primitive) <- 0;
          while work_offset.(primitive) < size
              && comparisons.(primitive) = 0 do
            let offset = work_offset.(primitive) in
            comparisons.(primitive) <- Int.compare
                (clean_cycle_point topology first size starts.(primitive) 1 offset)
                (clean_cycle_point topology first size reverse_starts.(primitive)
                   (-1) offset);
            work_offset.(primitive) <- offset + 1
          done;
          if comparisons.(primitive) > 0 then begin
            starts.(primitive) <- reverse_starts.(primitive);
            directions.(primitive) <- -1
          end;
          hashes.(primitive) <- 17 lxor size;
          for offset = 0 to size - 1 do
            hashes.(primitive) <- ((hashes.(primitive) * 65_599) lxor
              clean_cycle_point topology first size starts.(primitive)
                directions.(primitive) offset) land max_int
          done;
          sizes.(primitive) <- size;
        end);
    let capacity = ref 8 in
    while !capacity < !polygon_count * 2 do capacity := !capacity lsl 1 done;
    let table = Array.make !capacity (-1) and mask = !capacity - 1
    and flags = Bytes.make primitive_count '\000' in
    let point primitive offset =
      let first = topology.primitive_offsets.(primitive)
      and size = sizes.(primitive) in
      let local = (starts.(primitive) + (directions.(primitive) * offset)) mod size in
      topology.vertex_points.(first + if local < 0 then local + size else local) in
    let equal_offset = ref 0 and equal_same = ref true in
    let equal left right =
      if sizes.(left) <> sizes.(right) then false
      else begin
        equal_offset := 0;
        equal_same := true;
        while !equal_same && !equal_offset < sizes.(left) do
          equal_same := point left !equal_offset = point right !equal_offset;
          incr equal_offset
        done;
        !equal_same
      end in
    let slot = ref 0 and found = ref (-1) and searching = ref true in
    for primitive = 0 to primitive_count - 1 do
      if primitive land 4_095 = 0 then Cancel.check_opt cancel;
      if sizes.(primitive) > 0 then begin
        slot := hashes.(primitive) land mask;
        found := -1;
        searching := true;
        while !searching do
          let candidate = table.(!slot) in
          if candidate < 0 then searching := false
          else if hashes.(candidate) = hashes.(primitive)
              && equal candidate primitive then begin
            found := candidate; searching := false
          end else slot := (!slot + 1) land mask
        done;
        if !found < 0 then table.(!slot) <- primitive
        else begin
          Bytes.set flags primitive '\001';
          if policy = Delete_overlap_pairs then Bytes.set flags !found '\001'
        end
      end
    done;
    let removed = ref false in
    Bytes.iter (fun flag -> if flag <> '\000' then removed := true) flags;
    if not !removed then Ok geometry
    else
      let selection = Group.init ~grain ~owner:Group.Primitive
          ~name:"__clean_overlaps" primitive_count
          (fun primitive -> Bytes.get flags primitive <> '\000') in
      Deletion.delete ?cancel ~grain selection geometry
  end

let clean_delete_triangle_overlaps ?cancel ~grain ~policy geometry =
  let topology = Topology.Private.view (Geometry.topology geometry) in
  let primitive_count = Geometry.primitive_count geometry in
  if primitive_count = 0 then Ok geometry
  else if primitive_count > Sys.max_array_length / 4 then
    Error "Pdk.Ops.clean: overlap table exceeds array limits"
  else begin
    let first_points = Array.make primitive_count 0
    and second_points = Array.make primitive_count 0
    and third_points = Array.make primitive_count 0
    and hashes = Array.make primitive_count 0 in
    Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(primitive_count - 1)
      (fun primitive ->
        if primitive land 4_095 = 0 then Cancel.check_opt cancel;
        let first = topology.primitive_offsets.(primitive) in
        let p0 = topology.vertex_points.(first)
        and p1 = topology.vertex_points.(first + 1)
        and p2 = topology.vertex_points.(first + 2) in
        let low, high = if p0 <= p1 then p0, p1 else p1, p0 in
        let a, b, c = if p2 <= low then p2, low, high
          else if p2 >= high then low, high, p2
          else low, p2, high in
        first_points.(primitive) <- a;
        second_points.(primitive) <- b;
        third_points.(primitive) <- c;
        hashes.(primitive) <- (((((17 lxor 3) * 65_599) lxor a) * 65_599
          lxor b) * 65_599 lxor c) land max_int);
    let capacity = ref 8 in
    while !capacity < primitive_count * 2 do capacity := !capacity lsl 1 done;
    let table = Array.make !capacity (-1) and mask = !capacity - 1
    and flags = Bytes.make primitive_count '\000' in
    let slot = ref 0 and found = ref (-1) and searching = ref true in
    for primitive = 0 to primitive_count - 1 do
      if primitive land 4_095 = 0 then Cancel.check_opt cancel;
      slot := hashes.(primitive) land mask;
      found := -1;
      searching := true;
      while !searching do
        let candidate = table.(!slot) in
        if candidate < 0 then searching := false
        else if hashes.(candidate) = hashes.(primitive)
            && first_points.(candidate) = first_points.(primitive)
            && second_points.(candidate) = second_points.(primitive)
            && third_points.(candidate) = third_points.(primitive) then begin
          found := candidate;
          searching := false
        end else slot := (!slot + 1) land mask
      done;
      if !found < 0 then table.(!slot) <- primitive
      else begin
        Bytes.unsafe_set flags primitive '\001';
        if policy = Delete_overlap_pairs then
          Bytes.unsafe_set flags !found '\001'
      end
    done;
    let removed = ref false in
    Bytes.iter (fun flag -> if flag <> '\000' then removed := true) flags;
    if not !removed then Ok geometry
    else
      let selection = Group.init ~grain ~owner:Group.Primitive
          ~name:"__clean_overlaps" primitive_count
          (fun primitive -> Bytes.get flags primitive <> '\000') in
      Deletion.delete ?cancel ~grain selection geometry
  end

let clean_delete_overlaps ?cancel ~grain ~policy geometry =
  if Topology.all_triangles (Geometry.topology geometry) then
    clean_delete_triangle_overlaps ?cancel ~grain ~policy geometry
  else clean_delete_overlaps_general ?cancel ~grain ~policy geometry

let clean ?cancel ?(grain = 16_384) ?(epsilon = 1e-12)
    ?(remove_degenerate = true) ?consolidate_distance ?overlaps
    ?(reverse_winding = false) ?(remove_nan_points = false)
    ?(remove_unused_points = false) ?(delete_unused_groups = false)
    ?point_attributes ?vertex_attributes ?primitive_attributes ?detail_attributes
    ?point_groups ?vertex_groups ?primitive_groups ?edge_groups geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.clean: grain must be positive";
  if not (finite epsilon) || epsilon < 0. then
    Error "Pdk.Ops.clean: epsilon must be finite and non-negative"
  else if (match consolidate_distance with
    | Some value -> not (finite value) || value < 0.
    | None -> false) then
    Error "Pdk.Ops.clean: consolidate distance must be finite and non-negative"
  else begin
    let validate_pattern = function
      | None -> Ok ()
      | Some pattern when String.trim pattern = "" -> Ok ()
      | Some pattern -> Result.map (fun _ -> ()) (Attribute_pattern.compile pattern) in
    let patterns = [point_attributes; vertex_attributes; primitive_attributes;
      detail_attributes; point_groups; vertex_groups; primitive_groups; edge_groups] in
    let validation = List.fold_left (fun result pattern ->
      Result.bind result (fun () -> validate_pattern pattern)) (Ok ()) patterns in
    Result.bind validation (fun () ->
      let result = if remove_nan_points then
          clean_delete_nan_points ?cancel ~grain geometry else Ok geometry in
      let result = Result.bind result (fun geometry -> match consolidate_distance with
        | None -> Ok geometry
        | Some tolerance -> fuse ?cancel ~grain ~tolerance geometry) in
      let result = Result.bind result (fun geometry ->
        if remove_degenerate then clean_delete_degenerate ?cancel ~grain ~epsilon geometry
        else Ok geometry) in
      let result = Result.bind result (fun geometry -> match overlaps with
        | None -> Ok geometry
        | Some policy -> clean_delete_overlaps ?cancel ~grain ~policy geometry) in
      let result = Result.bind result (fun geometry ->
        if reverse_winding then reverse ?cancel geometry else Ok geometry) in
      let result = Result.bind result (fun geometry ->
        if remove_unused_points then compact_points ?cancel ~grain geometry
        else Ok geometry) in
      let result = Result.bind result (fun geometry ->
        Attribute_lifecycle.delete ?cancel ?point_pattern:point_attributes
          ?vertex_pattern:vertex_attributes ?primitive_pattern:primitive_attributes
          ?detail_pattern:detail_attributes geometry) in
      Result.bind result (fun geometry ->
        let add owner pattern rules = match pattern with
          | None -> rules
          | Some pattern when String.trim pattern = "" -> rules
          | Some delete_pattern ->
              ({ delete_owner = Some owner; delete_pattern } : group_delete_rule)
              :: rules in
        let rules = [] |> add Group_points point_groups
            |> add Group_vertices vertex_groups
            |> add Group_primitives primitive_groups
            |> add Group_edges edge_groups |> List.rev in
        if rules = [] && not delete_unused_groups then Ok geometry
        else Group_ops.delete ~rules ~delete_unused:delete_unused_groups geometry))
  end

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
        clean_delete_degenerate ?cancel ~grain
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

let remap_attribute_all point_map vertex_map primitive_map attribute =
  if String.equal (Attribute.name attribute) "N"
     && (Attribute.owner attribute = Attribute.Point
         || Attribute.owner attribute = Attribute.Vertex)
  then Ok None
  else
    let mapping = match Attribute.owner attribute with
      | Attribute.Point -> Some point_map
      | Attribute.Vertex -> Some vertex_map
      | Attribute.Primitive -> Some primitive_map
      | Attribute.Detail -> None in
    match mapping with
    | None -> Ok (Some attribute)
    | Some mapping ->
        let storage = match Attribute.Private.storage attribute with
          | Attribute.Float values -> Attribute.Float (select_array mapping values)
          | Attribute.Int values -> Attribute.Int (select_array mapping values)
          | Attribute.Text values -> Attribute.Text (select_array mapping values)
          | Attribute.Float2 values ->
              let view = Packed.Float2.Private.view values in
              Attribute.Float2 (Packed.Float2.of_owned
                ~x:(select_array mapping view.x) ~y:(select_array mapping view.y)
                |> get_ok)
          | Attribute.Float3 values ->
              let view = Packed.Float3.Private.view values in
              Attribute.Float3 (Packed.Float3.Private.of_owned_exn
                ~x:(select_array mapping view.x) ~y:(select_array mapping view.y)
                ~z:(select_array mapping view.z))
          | Attribute.Float4 values ->
              let view = Packed.Float4.Private.view values in
              Attribute.Float4 (Packed.Float4.of_owned
                ~x:(select_array mapping view.x) ~y:(select_array mapping view.y)
                ~z:(select_array mapping view.z) ~w:(select_array mapping view.w)
                |> get_ok)
          | Attribute.Int_array values ->
              Attribute.Int_array (Ragged_ops.remap_int mapping values)
          | Attribute.Float_array values ->
              Attribute.Float_array (Ragged_ops.remap_float mapping values) in
        Result.map Option.some (Attribute.create_owned ~name:(Attribute.name attribute)
          ~owner:(Attribute.owner attribute) storage)

let remap_group_all point_map vertex_map primitive_map group =
  let mapping = match Group.owner group with
    | Group.Point -> point_map
    | Group.Vertex -> vertex_map
    | Group.Primitive -> primitive_map in
  let target = Group.init ~owner:(Group.owner group) ~name:(Group.name group)
      (Array.length mapping) (fun index -> Group.mem mapping.(index) group) in
  Group.Private.remap_order ~source:group ~source_of_target:mapping target

let poly_extrude_legacy ?cancel ?(grain = 1_024) ~distance geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.poly_extrude: grain must be positive";
  if not (finite distance) then
    Error "Pdk.Ops.poly_extrude: distance must be finite"
  else
    let topology = Geometry.topology geometry
    and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let source_vertices = Geometry.vertex_count geometry
    and source_primitives = Geometry.primitive_count geometry in
    let curve = ref None in
    for primitive = 0 to source_primitives - 1 do
      if Topology.primitive_kind topology primitive <> Topology.Polygon
         && !curve = None
      then curve := Some primitive
    done;
    match !curve with
    | Some primitive -> Error (Printf.sprintf
        "Pdk.Ops.poly_extrude: primitive %d is a curve" primitive)
    | None when source_vertices > max_int / 6
             || source_primitives > (max_int - source_vertices) / 2 ->
        Error "Pdk.Ops.poly_extrude: output cardinality exceeds OCaml array limits"
    | None ->
        let output_points = source_vertices * 2
        and output_vertices = source_vertices * 6
        and output_primitives = source_primitives * 2 + source_vertices in
        let px = Array.make output_points 0. and py = Array.make output_points 0.
        and pz = Array.make output_points 0.
        and point_map = Array.make output_points 0
        and vertex_points = Array.make output_vertices 0
        and vertex_map = Array.make output_vertices 0
        and primitive_offsets = Array.make (output_primitives + 1) 0
        and primitive_map = Array.make output_primitives 0
        and primitive_kinds = Bytes.make output_primitives '\000' in
        let failures = Array.make source_primitives None in
        if source_primitives > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(source_primitives - 1) (fun primitive ->
              if primitive land 255 = 0 then Cancel.check_opt cancel;
              let first, last = Topology.primitive_vertex_range topology primitive in
              let count = last - first and nx = ref 0. and ny = ref 0. and nz = ref 0. in
              for local = 0 to count - 1 do
                let next = (local + 1) mod count in
                let a = Topology.point_of_vertex topology (first + local)
                and b = Topology.point_of_vertex topology (first + next) in
                let ax = positions.x.(a) and ay = positions.y.(a) and az = positions.z.(a)
                and bx = positions.x.(b) and by = positions.y.(b) and bz = positions.z.(b) in
                nx := !nx +. ((ay -. by) *. (az +. bz));
                ny := !ny +. ((az -. bz) *. (ax +. bx));
                nz := !nz +. ((ax -. bx) *. (ay +. by))
              done;
              let length = sqrt ((!nx *. !nx) +. (!ny *. !ny) +. (!nz *. !nz)) in
              if length <= 1e-20 || not (finite length) then
                failures.(primitive) <- Some (Printf.sprintf
                  "Pdk.Ops.poly_extrude: primitive %d is degenerate" primitive)
              else begin
                let dx = distance *. !nx /. length and dy = distance *. !ny /. length
                and dz = distance *. !nz /. length and output_vertex = first * 6
                and output_primitive = (primitive * 2) + first in
                for local = 0 to count - 1 do
                  let vertex = first + local in
                  let point = Topology.point_of_vertex topology vertex
                  and bottom = vertex * 2 in
                  px.(bottom) <- positions.x.(point);
                  py.(bottom) <- positions.y.(point);
                  pz.(bottom) <- positions.z.(point);
                  px.(bottom + 1) <- positions.x.(point) +. dx;
                  py.(bottom + 1) <- positions.y.(point) +. dy;
                  pz.(bottom + 1) <- positions.z.(point) +. dz;
                  point_map.(bottom) <- point; point_map.(bottom + 1) <- point;
                  let reversed_vertex = first + count - local - 1 in
                  vertex_points.(output_vertex + local) <- reversed_vertex * 2;
                  vertex_map.(output_vertex + local) <- reversed_vertex;
                  vertex_points.(output_vertex + count + local) <- (vertex * 2) + 1;
                  vertex_map.(output_vertex + count + local) <- vertex
                done;
                primitive_offsets.(output_primitive) <- output_vertex;
                primitive_offsets.(output_primitive + 1) <- output_vertex + count;
                primitive_map.(output_primitive) <- primitive;
                primitive_map.(output_primitive + 1) <- primitive;
                for local = 0 to count - 1 do
                  let next = (local + 1) mod count and current_vertex = first + local in
                  let next_vertex = first + next
                  and output = output_vertex + (2 * count) + (local * 4)
                  and output_side = output_primitive + 2 + local in
                  vertex_points.(output) <- current_vertex * 2;
                  vertex_points.(output + 1) <- next_vertex * 2;
                  vertex_points.(output + 2) <- (next_vertex * 2) + 1;
                  vertex_points.(output + 3) <- (current_vertex * 2) + 1;
                  vertex_map.(output) <- current_vertex;
                  vertex_map.(output + 1) <- next_vertex;
                  vertex_map.(output + 2) <- next_vertex;
                  vertex_map.(output + 3) <- current_vertex;
                  primitive_offsets.(output_side) <- output;
                  primitive_map.(output_side) <- primitive
                done
              end);
        primitive_offsets.(output_primitives) <- output_vertices;
        match Array.find_opt Option.is_some failures |> Option.join with
        | Some message -> Error message
        | None ->
            let output_positions = Packed.Float3.Private.of_owned_exn
                ~x:px ~y:py ~z:pz in
            let output_topology = Topology.Private.create_validated_owned
                ~point_count:output_points ~vertex_points ~primitive_offsets
                ~primitive_kinds in
            let rec attributes result = function
              | [] -> Ok (List.rev result)
              | attribute :: rest ->
                  Result.bind (remap_attribute_all point_map vertex_map primitive_map
                    attribute) (function
                    | None -> attributes result rest
                    | Some attribute -> attributes (attribute :: result) rest) in
            Result.bind (attributes [] (Geometry.attributes geometry)) (fun attributes ->
              let groups = List.map
                  (remap_group_all point_map vertex_map primitive_map)
                  (Geometry.groups geometry) in
              let edge_groups = match Geometry.edge_groups geometry with
                | [] -> []
                | source_groups ->
                    let source_index = Topology_index.create ?cancel topology
                    and target_index = Topology_index.create ?cancel
                        output_topology in
                    List.map (fun source_group ->
                      let builder = Edge_group.Builder.create
                          ~topology:output_topology ~index:target_index
                          ~name:(Edge_group.name source_group) in
                      Edge_group.iter (fun edge ->
                        let incidence = Topology_index.edge_incidence_count
                            source_index edge in
                        for local = 0 to incidence - 1 do
                          let current = Topology_index.edge_vertex source_index
                              ~edge ~local in
                          let next = Topology_index.next_vertex source_index current in
                          let add a b = match Topology_index.find_edge target_index
                              ~a ~b with
                            | None -> ()
                            | Some target -> Edge_group.Builder.set builder target true in
                          if next >= 0 then begin
                            add (current * 2) (next * 2);
                            add (current * 2 + 1) (next * 2 + 1)
                          end
                        done) source_group;
                      Edge_group.Builder.freeze builder) source_groups in
              Geometry.create ~positions:output_positions ~topology:output_topology
                ~attributes ~groups ~edge_groups ())

let poly_extrude ?cancel ?(grain = 1_024) ?primitives ?split_edges
    ?(divide = Extrude_individual) ?(divisions = 1)
    ?(output_front = true) ?(output_back = true) ?(output_side = true)
    ?front_group ?back_group ?side_group ?front_boundary_group
    ?back_boundary_group ~distance geometry =
  if primitives = None && split_edges = None && divide = Extrude_individual
      && divisions = 1 && output_front && output_back && output_side
      && front_group = None && back_group = None && side_group = None
      && front_boundary_group = None && back_boundary_group = None then
    poly_extrude_legacy ?cancel ~grain ~distance geometry
  else
    Poly_extrude.run ?cancel ~grain ?primitives ?split_edges ~divide ~divisions
      ~output_front ~output_back ~output_side ?front_group ?back_group
      ?side_group ?front_boundary_group ?back_boundary_group ~distance geometry

let poly_fill ?cancel ?grain ?boundary ?mode ?reverse_patches ?unique_points
    ?update_point_normals ?patch_group geometry =
  Poly_fill.run ?cancel ?grain ?boundary ?mode ?reverse_patches ?unique_points
    ?update_point_normals ?patch_group geometry

let interpolated_array ~grain left right weights source =
  Parallel.init_array ~grain (Array.length weights) (fun index ->
    let t = weights.(index) in
    source.(left.(index)) +. ((source.(right.(index)) -. source.(left.(index))) *. t))

let nearest_array ~grain left right weights source =
  Parallel.init_array ~grain (Array.length weights) (fun index ->
    source.((if weights.(index) < 0.5 then left else right).(index)))

let interpolate_attribute ~grain point_left point_right vertex_left vertex_right
    weights attribute =
  let mapping = match Attribute.owner attribute with
    | Attribute.Point -> Some (point_left, point_right)
    | Attribute.Vertex -> Some (vertex_left, vertex_right)
    | Attribute.Primitive | Attribute.Detail -> None in
  match mapping with
  | None -> Ok attribute
  | Some (left, right) ->
      let storage = match Attribute.Private.storage attribute with
        | Attribute.Float values ->
            Attribute.Float (interpolated_array ~grain left right weights values)
        | Attribute.Int values ->
            Attribute.Int (nearest_array ~grain left right weights values)
        | Attribute.Text values ->
            Attribute.Text (nearest_array ~grain left right weights values)
        | Attribute.Float2 values ->
            let view = Packed.Float2.Private.view values in
            Attribute.Float2 (Packed.Float2.of_owned
              ~x:(interpolated_array ~grain left right weights view.x)
              ~y:(interpolated_array ~grain left right weights view.y) |> get_ok)
        | Attribute.Float3 values ->
            let view = Packed.Float3.Private.view values in
            let x = interpolated_array ~grain left right weights view.x
            and y = interpolated_array ~grain left right weights view.y
            and z = interpolated_array ~grain left right weights view.z in
            if String.equal (Attribute.name attribute) "N" then
              Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(Array.length x - 1)
                  (fun index ->
                let length = sqrt ((x.(index) *. x.(index))
                    +. (y.(index) *. y.(index)) +. (z.(index) *. z.(index))) in
                if length > 1e-20 then begin
                  x.(index) <- x.(index) /. length;
                  y.(index) <- y.(index) /. length;
                  z.(index) <- z.(index) /. length
                end);
            Attribute.Float3 (Packed.Float3.Private.of_owned_exn ~x ~y ~z)
        | Attribute.Float4 values ->
            let view = Packed.Float4.Private.view values in
            Attribute.Float4 (Packed.Float4.of_owned
              ~x:(interpolated_array ~grain left right weights view.x)
              ~y:(interpolated_array ~grain left right weights view.y)
              ~z:(interpolated_array ~grain left right weights view.z)
              ~w:(interpolated_array ~grain left right weights view.w) |> get_ok)
        | Attribute.Int_array values ->
            let mapping = Parallel.init_array ~grain (Array.length weights) (fun index ->
                if weights.(index) < 0.5 then left.(index) else right.(index)) in
            Attribute.Int_array (Ragged_ops.remap_int mapping values)
        | Attribute.Float_array values ->
            let mapping = Parallel.init_array ~grain (Array.length weights) (fun index ->
                if weights.(index) < 0.5 then left.(index) else right.(index)) in
            Attribute.Float_array (Ragged_ops.remap_float mapping values) in
      Attribute.create_owned ~name:(Attribute.name attribute)
        ~owner:(Attribute.owner attribute) storage

let resample_curves ?cancel ?(grain = 16_384) ?primitives ?segments
    ?maximum_segment_length ?segment_length_attribute ?segments_attribute
    ?(even_last_segment = true) ?curve_u_attribute ?curve_number_attribute
    ?distance_attribute ?tangent_attribute geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.resample_curves: grain must be positive";
  let invalid = ref None in
  (match segments with
   | Some value when value < 1 ->
       invalid := Some "segments must be positive"
   | _ -> ());
  (match maximum_segment_length with
   | Some value when not (finite value) || value <= 0. ->
       invalid := Some "maximum segment length must be finite and positive"
   | _ -> ());
  if segments = None && maximum_segment_length = None
      && segment_length_attribute = None && segments_attribute = None then
    invalid := Some ("segments, maximum_segment_length, or a primitive "
      ^ "override attribute is required");
  let generated_names = [curve_u_attribute; curve_number_attribute;
    distance_attribute; tangent_attribute] |> List.filter_map Fun.id in
  List.iter (fun name ->
    if String.trim name = "" then
      invalid := Some "generated attribute names must not be empty"
    else if String.equal name "P" then
      invalid := Some "generated attributes cannot replace canonical P")
    generated_names;
  let sorted_names = List.sort String.compare generated_names in
  let rec duplicate = function
    | left :: (right :: _ as rest) ->
        if String.equal left right then Some left else duplicate rest
    | _ -> None in
  Option.iter (fun name -> invalid := Some (Printf.sprintf
      "generated attribute name %S is used more than once" name))
    (duplicate sorted_names);
  let topology = Geometry.topology geometry
  and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let primitive_count = Geometry.primitive_count geometry in
  (match primitives with
   | Some group when Group.owner group <> Group.Primitive ->
       invalid := Some "selection group must own primitives"
   | Some group when Group.length group <> primitive_count ->
       invalid := Some "selection group length does not match primitive count"
   | _ -> ());
  let find_primitive_attribute label name storage = match name with
    | None -> None, None
    | Some name when String.trim name = "" ->
        None, Some (label ^ " attribute name must not be empty")
    | Some name ->
        (match Geometry.find_attribute ~owner:Attribute.Primitive name geometry with
         | None -> None, Some (Printf.sprintf
             "primitive %s attribute %S does not exist" label name)
         | Some attribute ->
             match storage (Attribute.Private.storage attribute) with
             | Some values -> Some values, None
             | None -> None, Some (Printf.sprintf
                 "primitive %s attribute %S has incompatible storage" label name)) in
  let segment_length_values, segment_length_error = find_primitive_attribute
      "segment length" segment_length_attribute
      (function Attribute.Float values -> Some values | _ -> None)
  and segments_values, segments_error = find_primitive_attribute
      "segments" segments_attribute
      (function Attribute.Int values -> Some values | _ -> None) in
  if !invalid = None then invalid := (match segment_length_error with
    | Some _ as error -> error | None -> segments_error);
  Option.iter (fun values ->
    let primitive = ref 0 in
    while !invalid = None && !primitive < Array.length values do
      if not (finite values.(!primitive)) then invalid := Some (Printf.sprintf
          "primitive segment length attribute contains a non-finite value at primitive %d"
          !primitive);
      incr primitive
    done) segment_length_values;
  let source_offsets = Array.make (primitive_count + 1) 0
  and primitive_kinds = Array.make primitive_count Topology.Open_polyline in
  for primitive = 0 to primitive_count - 1 do
    let first, last = Topology.primitive_vertex_range topology primitive in
    let source_count = last - first
    and kind = Topology.primitive_kind topology primitive in
    primitive_kinds.(primitive) <- kind;
    (match kind with
     | Topology.Polygon when !invalid = None ->
         invalid := Some (Printf.sprintf "primitive %d is a polygon" primitive)
     | _ -> ());
    let cumulative_count = source_count
        + if kind = Topology.Closed_polyline then 1 else 0 in
    if source_offsets.(primitive) > Sys.max_array_length - cumulative_count then
      invalid := Some "input curve cardinality exceeds OCaml array limits"
    else source_offsets.(primitive + 1) <-
        source_offsets.(primitive) + cumulative_count
  done;
  match !invalid with
  | Some message -> Error ("Pdk.Ops.resample_curves: " ^ message)
  | None ->
      let cumulative = Array.make source_offsets.(primitive_count) 0.
      and totals = Array.make primitive_count 0.
      and failures = Bytes.make primitive_count '\000' in
      let average_vertices = max 1
          (Geometry.vertex_count geometry / max 1 primitive_count) in
      if primitive_count > 0 then Parallel.for_
          ~chunk_size:(max 1 (grain / average_vertices)) ~start:0
          ~finish:(primitive_count - 1) (fun primitive ->
        if primitive land 255 = 0 then Cancel.check_opt cancel;
        let first, last = Topology.primitive_vertex_range topology primitive in
        let source_count = last - first
        and closed = primitive_kinds.(primitive) = Topology.Closed_polyline
        and base = source_offsets.(primitive) in
        let edge_count = source_count - 1 + if closed then 1 else 0 in
        for edge = 0 to edge_count - 1 do
          let left_vertex = first + (edge mod source_count)
          and right_vertex = first + ((edge + 1) mod source_count) in
          let left_point = Topology.point_of_vertex topology left_vertex
          and right_point = Topology.point_of_vertex topology right_vertex in
          let dx = positions.x.(right_point) -. positions.x.(left_point)
          and dy = positions.y.(right_point) -. positions.y.(left_point)
          and dz = positions.z.(right_point) -. positions.z.(left_point) in
          let direct_length = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
          let edge_length = if finite direct_length then direct_length
            else
              let ax = abs_float dx and ay = abs_float dy and az = abs_float dz in
              let scale = if ax >= ay then if ax >= az then ax else az
                else if ay >= az then ay else az in
              let sx = if scale = 0. then 0. else dx /. scale
              and sy = if scale = 0. then 0. else dy /. scale
              and sz = if scale = 0. then 0. else dz /. scale in
              scale *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
          let next = cumulative.(base + edge) +. edge_length in
          if not (finite edge_length && finite next) then
            Bytes.set failures primitive '\001'
          else cumulative.(base + edge + 1) <- next
        done;
        let total = cumulative.(base + edge_count) in
        totals.(primitive) <- total;
        if total <= 1e-20 || not (finite total) then
          Bytes.set failures primitive '\002');
      let failed = ref 0 in
      while !failed < primitive_count && Bytes.get failures !failed = '\000' do
        incr failed
      done;
      if !failed < primitive_count then
        Error (Printf.sprintf
          "Pdk.Ops.resample_curves: primitive %d has zero or non-finite length"
          !failed)
      else begin
        let output_edges = Array.make primitive_count 0
        and uniform_spacing = Bytes.make primitive_count '\000'
        and preserve_original = Bytes.make primitive_count '\000'
        and effective_maximum = Array.make primitive_count 0.
        and primitive_offsets = Array.make (primitive_count + 1) 0 in
        let cardinality_error = ref None in
        for primitive = 0 to primitive_count - 1 do
          let closed = primitive_kinds.(primitive) = Topology.Closed_polyline in
          let minimum = if closed then 3 else 1 in
          let selected = match primitives with
            | None -> true | Some group -> Group.mem primitive group in
          let primitive_segments = if not selected then None else
              match segments_values with
              | Some values -> if values.(primitive) <= 0 then None
                  else Some values.(primitive)
              | None -> segments in
          let primitive_maximum = if not selected then None else
              match segment_length_values with
              | Some values -> if values.(primitive) <= 0. then None
                  else Some values.(primitive)
              | None -> maximum_segment_length in
          let preserve = not selected
              || (primitive_segments = None && primitive_maximum = None) in
          if preserve then Bytes.set preserve_original primitive '\001';
          Option.iter (fun value -> effective_maximum.(primitive) <- value)
            primitive_maximum;
          (match primitive_segments with
           | Some count when closed && count < 3 ->
               cardinality_error := Some (Printf.sprintf
                 "closed primitive %d requires at least three segments" primitive)
           | _ -> ());
          let length_edges = match primitive_maximum with
            | None -> None
            | Some maximum ->
                let ratio = totals.(primitive) /. maximum in
                if not (finite ratio)
                    || ratio >= float_of_int Sys.max_array_length then begin
                  cardinality_error := Some (Printf.sprintf
                    "primitive %d length-driven cardinality exceeds OCaml array limits"
                    primitive);
                  Some Sys.max_array_length
                end else Some (max minimum (int_of_float (ceil ratio))) in
          let source_first, source_last =
            Topology.primitive_vertex_range topology primitive in
          let source_edges = source_last - source_first - 1
              + if closed then 1 else 0 in
          let edges = if preserve then source_edges else
              match primitive_segments, length_edges with
            | Some count, Some by_length -> max minimum (min count by_length)
            | Some count, None -> max minimum count
            | None, Some count -> count
            | None, None -> assert false in
          output_edges.(primitive) <- edges;
          let capped_by_segments = match primitive_segments, length_edges with
            | Some count, Some by_length -> count < by_length
            | _ -> false in
          if preserve then Bytes.set uniform_spacing primitive '\002'
          else if primitive_maximum = None || even_last_segment
              || capped_by_segments || edges = minimum then
            Bytes.set uniform_spacing primitive '\001';
          let samples = edges + if closed then 0 else 1 in
          if samples < edges
              || primitive_offsets.(primitive) > Sys.max_array_length - samples then
            cardinality_error := Some "output cardinality exceeds OCaml array limits"
          else primitive_offsets.(primitive + 1) <-
              primitive_offsets.(primitive) + samples
        done;
        match !cardinality_error with
        | Some message -> Error ("Pdk.Ops.resample_curves: " ^ message)
        | None ->
          let output_count = primitive_offsets.(primitive_count) in
          let px = Array.make output_count 0. and py = Array.make output_count 0.
          and pz = Array.make output_count 0.
          and point_left = Array.make output_count 0
          and point_right = Array.make output_count 0
          and vertex_left = Array.make output_count 0
          and vertex_right = Array.make output_count 0
          and weights = Array.make output_count 0.
          and curve_u = Option.map (fun _ -> Array.make output_count 0.)
              curve_u_attribute
          and curve_number = Option.map (fun _ -> Array.make output_count 0)
              curve_number_attribute in
          let chunk_count = if output_count = 0 then 0
            else (output_count + grain - 1) / grain in
          let output_failures = Bytes.make chunk_count '\000' in
          let find_primitive index =
            let low = ref 0 and high = ref primitive_count in
            while !low + 1 < !high do
              let middle = (!low + !high) / 2 in
              if primitive_offsets.(middle) <= index then low := middle
              else high := middle
            done;
            !low in
          if chunk_count > 0 then Parallel.for_ ~chunk_size:1 ~start:0
              ~finish:(chunk_count - 1) (fun chunk ->
            Cancel.check_opt cancel;
            let index = ref (chunk * grain) in
            let finish = min output_count (!index + grain) in
            let primitive = ref (find_primitive !index) in
            while !index < finish do
              let output_first = primitive_offsets.(!primitive)
              and output_last = min finish primitive_offsets.(!primitive + 1) in
              let source_first, source_last =
                Topology.primitive_vertex_range topology !primitive in
              let source_count = source_last - source_first
              and source_base = source_offsets.(!primitive)
              and closed = primitive_kinds.(!primitive) = Topology.Closed_polyline
              and edges = output_edges.(!primitive)
              and total = totals.(!primitive) in
              let source_edge_count = source_count - 1 + if closed then 1 else 0
              and spacing = Bytes.get uniform_spacing !primitive
              and maximum = effective_maximum.(!primitive) in
              let preserve = spacing = '\002' and uniform = spacing <> '\000' in
              let local = !index - output_first in
              let first_distance =
                if preserve then cumulative.(source_base + local)
                else if not closed && local = edges then total
                else if uniform then
                  total *. float_of_int local /. float_of_int edges
                else float_of_int local *. maximum in
              let low = ref 1 and high = ref source_edge_count in
              while !low < !high do
                let middle = (!low + !high) / 2 in
                if cumulative.(source_base + middle) < first_distance then
                  low := middle + 1 else high := middle
              done;
              let edge = ref (!low - 1) in
              while !index < output_last do
                let local = !index - output_first in
                let distance =
                  if preserve then cumulative.(source_base + local)
                  else if not closed && local = edges then total
                  else if uniform then
                    total *. float_of_int local /. float_of_int edges
                  else float_of_int local *. maximum in
                while !edge < source_edge_count - 1
                    && cumulative.(source_base + !edge + 1) < distance do
                  incr edge
                done;
                let edge_start = cumulative.(source_base + !edge)
                and edge_finish = cumulative.(source_base + !edge + 1) in
                let edge_length = edge_finish -. edge_start in
                let sampled_t = if edge_length <= 1e-20 then 0.
                  else (distance -. edge_start) /. edge_length in
                let sampled_left = source_first + (!edge mod source_count)
                and sampled_right = source_first
                    + ((!edge + 1) mod source_count) in
                let left_vertex = if preserve then source_first + local
                  else sampled_left
                and right_vertex = if preserve then source_first + local
                  else sampled_right
                and t = if preserve then 0. else sampled_t in
                let left_point = Topology.point_of_vertex topology left_vertex
                and right_point = Topology.point_of_vertex topology right_vertex in
                point_left.(!index) <- left_point;
                point_right.(!index) <- right_point;
                vertex_left.(!index) <- left_vertex;
                vertex_right.(!index) <- right_vertex;
                weights.(!index) <- t;
                let x = positions.x.(left_point)
                    +. ((positions.x.(right_point) -. positions.x.(left_point)) *. t)
                and y = positions.y.(left_point)
                    +. ((positions.y.(right_point) -. positions.y.(left_point)) *. t)
                and z = positions.z.(left_point)
                    +. ((positions.z.(right_point) -. positions.z.(left_point)) *. t) in
                if finite x && finite y && finite z then begin
                  px.(!index) <- x; py.(!index) <- y; pz.(!index) <- z
                end else Bytes.set output_failures chunk '\001';
                (match curve_u with
                 | None -> ()
                 | Some values -> values.(!index) <-
                     if preserve then float_of_int local
                         /. float_of_int source_edge_count
                     else (float_of_int !edge +. t)
                         /. float_of_int source_edge_count);
                (match curve_number with
                 | None -> ()
                 | Some values -> values.(!index) <- !primitive);
                incr index
              done;
              incr primitive
            done);
          let failed_chunk = ref 0 in
          while !failed_chunk < chunk_count
              && Bytes.get output_failures !failed_chunk = '\000' do
            incr failed_chunk
          done;
          if !failed_chunk < chunk_count then Error
              "Pdk.Ops.resample_curves: generated a non-finite sample"
          else begin
            let distance_values = Option.map (fun _ -> Array.make output_count 0.)
                distance_attribute
            and tangent_x = Option.map (fun _ -> Array.make output_count 0.)
                tangent_attribute
            and tangent_y = Option.map (fun _ -> Array.make output_count 0.)
                tangent_attribute
            and tangent_z = Option.map (fun _ -> Array.make output_count 0.)
                tangent_attribute
            and diagnostic_failures = Bytes.make chunk_count '\000' in
            if chunk_count > 0
                && (distance_attribute <> None || tangent_attribute <> None) then
              Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(chunk_count - 1)
                (fun chunk ->
              Cancel.check_opt cancel;
              let first_index = chunk * grain in
              let last_index = min output_count (first_index + grain) in
              let primitive = ref (find_primitive first_index) in
              for index = first_index to last_index - 1 do
                while index >= primitive_offsets.(!primitive + 1) do
                  incr primitive
                done;
                let first = primitive_offsets.(!primitive)
                and last = primitive_offsets.(!primitive + 1) in
                let local = index - first and count = last - first
                and closed = primitive_kinds.(!primitive)
                    = Topology.Closed_polyline in
                let previous = if local = 0 then
                    if closed then last - 1 else index
                  else index - 1
                and next = if local = count - 1 then
                    if closed then first else index
                  else index + 1 in
                (match distance_values with
                 | None -> ()
                 | Some values ->
                  let left = if previous = index then 0. else
                      let dx = px.(index) -. px.(previous)
                      and dy = py.(index) -. py.(previous)
                      and dz = pz.(index) -. pz.(previous) in
                      let direct = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
                      if finite direct then direct else
                        let ax = abs_float dx and ay = abs_float dy
                        and az = abs_float dz in
                        let scale = if ax >= ay then if ax >= az then ax else az
                          else if ay >= az then ay else az in
                        let sx = if scale = 0. then 0. else dx /. scale
                        and sy = if scale = 0. then 0. else dy /. scale
                        and sz = if scale = 0. then 0. else dz /. scale in
                        scale *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz))
                  and right = if next = index then 0. else
                      let dx = px.(next) -. px.(index)
                      and dy = py.(next) -. py.(index)
                      and dz = pz.(next) -. pz.(index) in
                      let direct = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
                      if finite direct then direct else
                        let ax = abs_float dx and ay = abs_float dy
                        and az = abs_float dz in
                        let scale = if ax >= ay then if ax >= az then ax else az
                          else if ay >= az then ay else az in
                        let sx = if scale = 0. then 0. else dx /. scale
                        and sy = if scale = 0. then 0. else dy /. scale
                        and sz = if scale = 0. then 0. else dz /. scale in
                        scale *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                  let value = 0.5 *. (left +. right) in
                  if finite value then values.(index) <- value
                  else Bytes.set diagnostic_failures chunk '\001');
                match tangent_x, tangent_y, tangent_z with
                | Some tx, Some ty, Some tz ->
                    let dx = px.(next) -. px.(previous)
                    and dy = py.(next) -. py.(previous)
                    and dz = pz.(next) -. pz.(previous) in
                    let ax = abs_float dx and ay = abs_float dy
                    and az = abs_float dz in
                    let scale = if ax >= ay then if ax >= az then ax else az
                      else if ay >= az then ay else az in
                    let sx = if scale = 0. then 0. else dx /. scale
                    and sy = if scale = 0. then 0. else dy /. scale
                    and sz = if scale = 0. then 0. else dz /. scale in
                    let length = sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                    if scale = 0. || not (finite length) then
                      Bytes.set diagnostic_failures chunk '\002'
                    else begin
                      tx.(index) <- sx /. length;
                      ty.(index) <- sy /. length;
                      tz.(index) <- sz /. length
                    end
                | _ -> ()
              done);
            let failed_diagnostic = ref 0 in
            while !failed_diagnostic < chunk_count
                && Bytes.get diagnostic_failures !failed_diagnostic = '\000' do
              incr failed_diagnostic
            done;
            if !failed_diagnostic < chunk_count then Error
                "Pdk.Ops.resample_curves: generated a non-finite or undefined diagnostic"
            else
            let vertex_points = Parallel.init_array ~grain output_count Fun.id in
            Result.bind (Topology.create_owned ~point_count:output_count
                ~vertex_points ~primitive_offsets ~primitive_kinds) (fun topology ->
              let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
              let rec attributes result = function
                | [] -> Ok (List.rev result)
                | attribute :: rest -> Result.bind
                    (interpolate_attribute ~grain point_left point_right vertex_left
                      vertex_right weights attribute)
                    (fun attribute -> attributes (attribute :: result) rest) in
              Result.bind (attributes [] (Geometry.attributes geometry)) (fun attributes ->
                let generated = ref [] in
                let add name storage = match name with
                  | None -> ()
                  | Some name -> generated := (Attribute.create_owned
                      ~owner:Attribute.Point ~name storage |> get_ok) :: !generated in
                Option.iter (fun values -> add curve_u_attribute
                    (Attribute.Float values)) curve_u;
                Option.iter (fun values -> add curve_number_attribute
                    (Attribute.Int values)) curve_number;
                Option.iter (fun values -> add distance_attribute
                    (Attribute.Float values)) distance_values;
                (match tangent_x, tangent_y, tangent_z with
                 | Some x, Some y, Some z -> add tangent_attribute
                     (Attribute.Float3
                       (Packed.Float3.Private.of_owned_exn ~x ~y ~z))
                 | _ -> ());
                let generated = List.rev !generated in
                let attributes = List.filter (fun attribute ->
                    Attribute.owner attribute <> Attribute.Point
                    || not (List.exists (fun generated_attribute ->
                        String.equal (Attribute.name attribute)
                          (Attribute.name generated_attribute)) generated))
                    attributes @ generated in
                let groups = List.map (fun group ->
                  match Group.owner group with
                  | Group.Primitive -> group
                  | Group.Point ->
                      let source index =
                        (if weights.(index) < 0.5 then point_left else point_right).(index) in
                      let target = Group.init ~grain ~owner:Group.Point
                          ~name:(Group.name group) output_count
                          (fun index -> Group.mem (source index) group) in
                      if not (Group.is_ordered group) then target
                      else
                        let source_of_target = Parallel.init_array ~grain
                            output_count source in
                        Group.Private.remap_order ~source:group ~source_of_target target
                  | Group.Vertex ->
                      let source index =
                        (if weights.(index) < 0.5 then vertex_left else vertex_right).(index) in
                      let target = Group.init ~grain ~owner:Group.Vertex
                          ~name:(Group.name group) output_count
                          (fun index -> Group.mem (source index) group) in
                      if not (Group.is_ordered group) then target
                      else
                        let source_of_target = Parallel.init_array ~grain
                            output_count source in
                        Group.Private.remap_order ~source:group ~source_of_target target)
                    (Geometry.groups geometry) in
                let edge_groups = match Geometry.edge_groups geometry with
                  | [] -> []
                  | source_groups ->
                      let source_index = Topology_index.create ?cancel
                          (Geometry.topology geometry)
                      and target_index = Topology_index.create ?cancel topology in
                      let target_view = Topology_index.Private.view target_index in
                      List.map (fun source_group ->
                        let builder = Edge_group.Builder.create ~topology
                            ~index:target_index ~name:(Edge_group.name source_group) in
                        for primitive = 0 to primitive_count - 1 do
                          let source_first, source_last =
                            Topology.primitive_vertex_range
                              (Geometry.topology geometry) primitive in
                          let source_count = source_last - source_first in
                          let closed = Topology.primitive_kind
                              (Geometry.topology geometry) primitive
                              = Topology.Closed_polyline in
                          let source_edges = source_count - 1
                              + if closed then 1 else 0 in
                          let output_first, output_last =
                            Topology.primitive_vertex_range topology primitive in
                          let output_edges = output_last - output_first - 1
                              + if closed then 1 else 0 in
                          let selected_local local =
                            let corner = source_first + (local mod source_count) in
                            let edge = Topology_index.edge_of_vertex source_index corner in
                            edge >= 0 && Edge_group.mem edge source_group in
                          for local = 0 to output_edges - 1 do
                            let output_corner = output_first + local
                            and next_corner = output_first
                                + ((local + 1) mod (output_last - output_first)) in
                            let start_point = Topology.point_of_vertex topology
                                output_corner
                            and end_point = Topology.point_of_vertex topology next_corner in
                            let start_local = vertex_left.(start_point) - source_first
                                + if weights.(start_point) >= 1. -. 1e-12 then 1 else 0
                            and end_local = vertex_left.(end_point) - source_first in
                            let all = ref true in
                            let check first last =
                              for edge = first to last do
                                if edge >= 0 && edge < source_edges
                                   && not (selected_local edge) then all := false
                              done in
                            if closed && local = output_edges - 1 then begin
                              check start_local (source_edges - 1);
                              if weights.(end_point) > 1e-12 then check 0 end_local
                            end else begin
                              let last = if weights.(end_point) <= 1e-12
                                then end_local - 1 else end_local in
                              check start_local last
                            end;
                            if !all then begin
                              let target_edge = target_view.edge_of_vertex.(output_corner) in
                              if target_edge >= 0 then
                                Edge_group.Builder.set builder target_edge true
                            end
                          done
                        done;
                        Edge_group.Builder.freeze builder) source_groups in
                Geometry.create ~positions ~topology ~attributes ~groups
                  ~edge_groups ()))
          end
      end

let revolve ?cancel ?(grain = 16_384) ?primitives
    ?(revolve_type = Revolve_closed) ?(connectivity = Grid_quads)
    ?(start_angle = 0.) ?(end_angle = 2. *. Float.pi)
    ?(reverse_cross_sections = false) ?(caps = false) ?cap_group
    ?(uv_attribute = Some "uv") ~divisions ~(origin : Vec3.t)
    ~(axis : Vec3.t) geometry =
  let operation = "Pdk.Ops.revolve" in
  Cancel.check_opt cancel;
  let topology = Geometry.topology geometry in
  let source = Topology.Private.view topology
  and source_positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let source_vertices = Geometry.vertex_count geometry
  and source_primitives = Geometry.primitive_count geometry in
  let selected primitive = match primitives with
    | None -> true
    | Some group -> Group.mem primitive group in
  let polygon_surface = match connectivity with
    | Grid_quads | Grid_triangles | Grid_alternating_triangles
    | Grid_reverse_triangles -> true
    | Grid_points | Grid_rows | Grid_columns | Grid_rows_and_columns -> false in
  let selection_error = match primitives with
    | Some group when Group.owner group <> Group.Primitive ->
        Some "primitive selection has the wrong owner"
    | Some group when Group.length group <> source_primitives ->
        Some "primitive selection length does not match topology"
    | None | Some _ -> None in
  let uv_error = match uv_attribute with
    | Some name when String.trim name = "" || String.equal name "P"
        || String.equal name "N" ->
        Some "UV attribute name must be non-empty and cannot be P or N"
    | None | Some _ -> None in
  let cap_error = match cap_group with
    | Some name when String.trim name = "" -> Some "cap group name must not be empty"
    | Some _ when not caps -> Some "cap_group requires caps=true"
    | None | Some _ -> None in
  if grain <= 0 then Error (operation ^ ": grain must be positive")
  else if divisions < (match revolve_type with Revolve_closed -> 3
      | Revolve_open_arc -> 1) then
    Error (operation ^ ": divisions are too small for the revolve type")
  else if divisions > Sys.max_array_length -
      (match revolve_type with Revolve_closed -> 0 | Revolve_open_arc -> 1) then
    Error (operation ^ ": angular cardinality exceeds OCaml array limits")
  else if not (finite origin.x && finite origin.y && finite origin.z
      && finite axis.x && finite axis.y && finite axis.z
      && finite start_angle && finite end_angle) then
    Error (operation ^ ": origin, axis, and angles must be finite")
  else if revolve_type = Revolve_open_arc
      && (not (finite (end_angle -. start_angle))
          || end_angle = start_angle) then
    Error (operation ^ ": open arc angles must have a finite non-zero span")
  else if caps && (revolve_type <> Revolve_closed || not polygon_surface) then
    Error (operation ^
      ": caps require a closed polygon-surface revolution")
  else match selection_error, uv_error, cap_error with
  | Some message, _, _ | _, Some message, _ | _, _, Some message ->
      Error (operation ^ ": " ^ message)
  | None, None, None ->
      let axis_scale = max (abs_float axis.x)
          (max (abs_float axis.y) (abs_float axis.z)) in
      if axis_scale = 0. || not (finite axis_scale) then
        Error (operation ^ ": axis must be non-zero")
      else
        let sx = axis.x /. axis_scale and sy = axis.y /. axis_scale
        and sz = axis.z /. axis_scale in
        let axis_length = sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
        if axis_length = 0. || not (finite axis_length) then
          Error (operation ^ ": axis normalization failed")
        else
          let ax = sx /. axis_length and ay = sy /. axis_length
          and az = sz /. axis_length in
          let angular_samples = match revolve_type with
            | Revolve_closed -> divisions
            | Revolve_open_arc -> divisions + 1 in
          let angle_span = match revolve_type with
            | Revolve_closed -> 2. *. Float.pi
            | Revolve_open_arc -> end_angle -. start_angle in
          let angle_cos = Array.make angular_samples 0.
          and angle_sin = Array.make angular_samples 0. in
          for sample = 0 to angular_samples - 1 do
            let angle = start_angle +.
                (angle_span *. float_of_int sample /. float_of_int divisions) in
            angle_cos.(sample) <- cos angle;
            angle_sin.(sample) <- sin angle
          done;
          let selected_vertices = Bytes.make source_vertices '\000'
          and on_axis = Bytes.make source_vertices '\000'
          and profile_u = Array.make source_vertices 0.
          and ring_offsets = Array.make (source_vertices + 1) 0
          and input_errors = Array.make source_primitives 0 in
          let robust_distance a b =
            let dx = source_positions.x.(b) -. source_positions.x.(a)
            and dy = source_positions.y.(b) -. source_positions.y.(a)
            and dz = source_positions.z.(b) -. source_positions.z.(a) in
            let scale = max (abs_float dx) (max (abs_float dy) (abs_float dz)) in
            if scale = 0. then 0.
            else if not (finite scale) then infinity
            else
              let x = dx /. scale and y = dy /. scale and z = dz /. scale in
              scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
          if source_primitives > 0 then Parallel.for_
              ~chunk_size:(max 1 (grain / 16)) ~start:0
              ~finish:(source_primitives - 1) (fun primitive ->
            if selected primitive then begin
              Cancel.check_opt cancel;
              if Topology.primitive_kind topology primitive = Topology.Polygon then
                input_errors.(primitive) <- 1
              else
                let first = source.primitive_offsets.(primitive)
                and last = source.primitive_offsets.(primitive + 1) in
                if last - first < 2 then input_errors.(primitive) <- 2
                else begin
                  let cumulative = ref 0. in
                  for local = 0 to last - first - 1 do
                    let vertex = first + local
                    and point = source.vertex_points.(first + local) in
                    Bytes.set selected_vertices vertex '\001';
                    let x = source_positions.x.(point)
                    and y = source_positions.y.(point)
                    and z = source_positions.z.(point) in
                    if not (finite x && finite y && finite z) then
                      input_errors.(primitive) <- 3
                    else begin
                      let rx = x -. origin.x and ry = y -. origin.y
                      and rz = z -. origin.z in
                      if not (finite rx && finite ry && finite rz) then
                        input_errors.(primitive) <- 3
                      else begin
                        let along = (rx *. ax) +. (ry *. ay) +. (rz *. az) in
                        let qx = rx -. (along *. ax)
                        and qy = ry -. (along *. ay)
                        and qz = rz -. (along *. az) in
                        let radial_scale = max (abs_float qx)
                            (max (abs_float qy) (abs_float qz)) in
                        if radial_scale = 0. then Bytes.set on_axis vertex '\001'
                        else if not (finite radial_scale) then
                          input_errors.(primitive) <- 3
                      end
                    end;
                    if local > 0 then begin
                      let previous = source.vertex_points.(vertex - 1) in
                      let length = robust_distance previous point in
                      if length = 0. || not (finite length) then
                        input_errors.(primitive) <- 4
                      else cumulative := !cumulative +. length
                    end;
                    profile_u.(vertex) <- !cumulative
                  done;
                  let closed = Topology.primitive_kind topology primitive
                      = Topology.Closed_polyline in
                  let total = if closed then begin
                      let a = source.vertex_points.(last - 1)
                      and b = source.vertex_points.(first) in
                      let length = robust_distance a b in
                      if length = 0. || not (finite length) then begin
                        input_errors.(primitive) <- 4; !cumulative
                      end else !cumulative +. length
                    end else !cumulative in
                  if total = 0. || not (finite total) then
                    input_errors.(primitive) <- 5
                  else for vertex = first to last - 1 do
                    profile_u.(vertex) <- profile_u.(vertex) /. total
                  done
                end
            end);
          let failed = ref 0 in
          while !failed < source_primitives && input_errors.(!failed) = 0 do
            incr failed
          done;
          if !failed < source_primitives then
            Error (Printf.sprintf "%s: primitive %d %s" operation !failed
              (match input_errors.(!failed) with
               | 1 -> "is a polygon, not a polygon curve"
               | 2 -> "has fewer than two vertices"
               | 3 -> "contains a non-finite or unrepresentable position"
               | 4 -> "contains a zero-length or non-finite edge"
               | _ -> "has zero or non-finite length"))
          else begin
            let point_limit = Sys.max_array_length
            and primitive_limit = min (Sys.max_array_length - 1)
                Sys.max_string_length in
            let cardinality_error = ref None in
            for vertex = 0 to source_vertices - 1 do
              let count = if Bytes.get selected_vertices vertex = '\000' then 0
                else if Bytes.get on_axis vertex <> '\000' then 1
                else angular_samples in
              if ring_offsets.(vertex) > point_limit - count then
                cardinality_error := Some "point cardinality exceeds OCaml array limits"
              else ring_offsets.(vertex + 1) <- ring_offsets.(vertex) + count
            done;
            let output_points = ring_offsets.(source_vertices) in
            let source_output_counts = Array.make source_primitives 0
            and primitive_bases = Array.make (source_primitives + 1) 0 in
            let checked_add primitive value =
              if source_output_counts.(primitive) > primitive_limit - value
              then cardinality_error := Some
                  "primitive cardinality exceeds OCaml array limits"
              else source_output_counts.(primitive) <-
                  source_output_counts.(primitive) + value in
            let checked_cells primitive cells multiplier =
              if cells <> 0 && multiplier > primitive_limit / cells then
                cardinality_error := Some
                  "primitive cardinality exceeds OCaml array limits"
              else checked_add primitive (cells * multiplier) in
            for primitive = 0 to source_primitives - 1 do
              if selected primitive then begin
                let first = source.primitive_offsets.(primitive)
                and last = source.primitive_offsets.(primitive + 1) in
                let size = last - first in
                (match connectivity with
                 | Grid_rows | Grid_rows_and_columns ->
                     let rows = ref 0 in
                     for vertex = first to last - 1 do
                       if Bytes.get on_axis vertex = '\000' then incr rows
                     done;
                     checked_add primitive !rows
                 | Grid_points | Grid_columns | Grid_quads | Grid_triangles
                 | Grid_alternating_triangles | Grid_reverse_triangles -> ());
                (match connectivity with
                 | Grid_columns | Grid_rows_and_columns ->
                     checked_add primitive angular_samples
                 | Grid_points | Grid_rows | Grid_quads | Grid_triangles
                 | Grid_alternating_triangles | Grid_reverse_triangles -> ());
                if polygon_surface then begin
                  let edges = size - 1 +
                      if Topology.primitive_kind topology primitive
                         = Topology.Closed_polyline then 1 else 0 in
                  for local = 0 to edges - 1 do
                    let current = first + local
                    and next = first + ((local + 1) mod size) in
                    let current_axis = Bytes.get on_axis current <> '\000'
                    and next_axis = Bytes.get on_axis next <> '\000' in
                    if not (current_axis && next_axis) then
                      checked_cells primitive divisions
                        (if current_axis || next_axis || connectivity = Grid_quads
                         then 1 else 2)
                  done;
                  if caps && Topology.primitive_kind topology primitive
                      = Topology.Open_polyline then begin
                    if Bytes.get on_axis first = '\000' then checked_add primitive 1;
                    if Bytes.get on_axis (last - 1) = '\000' then
                      checked_add primitive 1
                  end
                end
              end
            done;
            for primitive = 0 to source_primitives - 1 do
              if primitive_bases.(primitive) > primitive_limit
                  - source_output_counts.(primitive) then
                cardinality_error := Some
                    "primitive cardinality exceeds OCaml array limits"
              else primitive_bases.(primitive + 1) <- primitive_bases.(primitive)
                  + source_output_counts.(primitive)
            done;
            match !cardinality_error with
            | Some message -> Error (operation ^ ": " ^ message)
            | None ->
                let output_primitives = primitive_bases.(source_primitives) in
                let primitive_sizes = Array.make output_primitives 0
                and primitive_map = Array.make output_primitives 0
                and primitive_kinds = Bytes.make output_primitives '\000'
                and cap_flags = Bytes.make output_primitives '\000'
                and surface_edge_bases = Array.make source_vertices (-1)
                and surface_edge_next = Array.make source_vertices (-1)
                and surface_edge_local = Array.make source_vertices 0 in
                let source_vertex primitive logical =
                  let first = source.primitive_offsets.(primitive)
                  and last = source.primitive_offsets.(primitive + 1) in
                  if reverse_cross_sections then last - 1 - logical
                  else first + logical in
                if source_primitives > 0 then Parallel.for_
                    ~chunk_size:(max 1 (grain / 32)) ~start:0
                    ~finish:(source_primitives - 1) (fun primitive ->
                  if selected primitive then begin
                    Cancel.check_opt cancel;
                    let first = source.primitive_offsets.(primitive)
                    and last = source.primitive_offsets.(primitive + 1) in
                    let size = last - first
                    and output = ref primitive_bases.(primitive) in
                    let emit size kind cap =
                      let at = !output in
                      primitive_sizes.(at) <- size;
                      primitive_map.(at) <- primitive;
                      Bytes.set primitive_kinds at kind;
                      if cap then Bytes.set cap_flags at '\001';
                      incr output in
                    (match connectivity with
                     | Grid_rows | Grid_rows_and_columns ->
                         for logical = 0 to size - 1 do
                           let vertex = source_vertex primitive logical in
                           if Bytes.get on_axis vertex = '\000' then emit
                               angular_samples
                               (if revolve_type = Revolve_closed
                                then '\002' else '\001') false
                         done
                     | Grid_points | Grid_columns | Grid_quads | Grid_triangles
                     | Grid_alternating_triangles | Grid_reverse_triangles -> ());
                    (match connectivity with
                     | Grid_columns | Grid_rows_and_columns ->
                         for _sample = 0 to angular_samples - 1 do
                           emit size
                             (if Topology.primitive_kind topology primitive
                                 = Topology.Closed_polyline then '\002' else '\001')
                             false
                         done
                     | Grid_points | Grid_rows | Grid_quads | Grid_triangles
                     | Grid_alternating_triangles | Grid_reverse_triangles -> ());
                    if polygon_surface then begin
                      let edges = size - 1 +
                          if Topology.primitive_kind topology primitive
                              = Topology.Closed_polyline then 1 else 0 in
                      for local = 0 to edges - 1 do
                        let current = source_vertex primitive local
                        and next = source_vertex primitive ((local + 1) mod size) in
                        let current_axis = Bytes.get on_axis current <> '\000'
                        and next_axis = Bytes.get on_axis next <> '\000' in
                        if not (current_axis && next_axis) then begin
                          surface_edge_bases.(current) <- !output;
                          surface_edge_next.(current) <- next;
                          surface_edge_local.(current) <- local;
                          for _side = 0 to divisions - 1 do
                            if current_axis || next_axis
                                || connectivity = Grid_quads then emit
                                (if current_axis || next_axis then 3 else 4)
                                '\000' false
                            else begin emit 3 '\000' false; emit 3 '\000' false end
                          done
                        end
                      done;
                      if caps && Topology.primitive_kind topology primitive
                          = Topology.Open_polyline then begin
                        let start = source_vertex primitive 0
                        and finish = source_vertex primitive (size - 1) in
                        if Bytes.get on_axis start = '\000' then
                          emit divisions '\000' true;
                        if Bytes.get on_axis finish = '\000' then
                          emit divisions '\000' true
                      end
                    end;
                    assert (!output = primitive_bases.(primitive + 1))
                  end);
                let primitive_offsets = Array.make (output_primitives + 1) 0 in
                for primitive = 0 to output_primitives - 1 do
                  let size = primitive_sizes.(primitive) in
                  if primitive_offsets.(primitive) > point_limit - size then
                    cardinality_error := Some
                      "vertex cardinality exceeds OCaml array limits"
                  else primitive_offsets.(primitive + 1) <-
                      primitive_offsets.(primitive) + size
                done;
                (match !cardinality_error with
                 | Some message -> Error (operation ^ ": " ^ message)
                 | None ->
                  let output_vertices = primitive_offsets.(output_primitives) in
                  let px = Array.make output_points 0.
                  and py = Array.make output_points 0.
                  and pz = Array.make output_points 0.
                  and point_map = Array.make output_points 0
                  and vertex_points = Array.make output_vertices 0
                  and vertex_map = Array.make output_vertices 0
                  and invalid_positions = Bytes.make source_vertices '\000' in
                  let point_uv_x, point_uv_y = match uv_attribute, connectivity with
                    | Some _, Grid_points -> Some (Array.make output_points 0.),
                        Some (Array.make output_points 0.)
                    | _ -> None, None in
                  let vertex_uv_x, vertex_uv_y = match uv_attribute, connectivity with
                    | Some _, (Grid_rows | Grid_columns | Grid_rows_and_columns
                        | Grid_quads | Grid_triangles
                        | Grid_alternating_triangles | Grid_reverse_triangles) ->
                        Some (Array.make output_vertices 0.),
                        Some (Array.make output_vertices 0.)
                    | _ -> None, None in
                  if source_vertices > 0 then Parallel.for_ ~chunk_size:grain
                      ~start:0 ~finish:(source_vertices - 1) (fun vertex ->
                    let first = ring_offsets.(vertex)
                    and last = ring_offsets.(vertex + 1) in
                    if first < last then begin
                      if vertex land 4095 = 0 then Cancel.check_opt cancel;
                      let source_point = source.vertex_points.(vertex) in
                      let x = source_positions.x.(source_point)
                      and y = source_positions.y.(source_point)
                      and z = source_positions.z.(source_point) in
                      let rx = x -. origin.x and ry = y -. origin.y
                      and rz = z -. origin.z in
                      let along = (rx *. ax) +. (ry *. ay) +. (rz *. az) in
                      let qx = rx -. (along *. ax)
                      and qy = ry -. (along *. ay)
                      and qz = rz -. (along *. az) in
                      let base_x = origin.x +. (along *. ax)
                      and base_y = origin.y +. (along *. ay)
                      and base_z = origin.z +. (along *. az) in
                      let cross_x = (ay *. qz) -. (az *. qy)
                      and cross_y = (az *. qx) -. (ax *. qz)
                      and cross_z = (ax *. qy) -. (ay *. qx) in
                      for local = 0 to last - first - 1 do
                        let output = first + local
                        and cosine = if last - first = 1 then 1.
                          else angle_cos.(local)
                        and sine = if last - first = 1 then 0.
                          else angle_sin.(local) in
                        let ox = base_x +. (qx *. cosine) +. (cross_x *. sine)
                        and oy = base_y +. (qy *. cosine) +. (cross_y *. sine)
                        and oz = base_z +. (qz *. cosine) +. (cross_z *. sine) in
                        if finite ox && finite oy && finite oz then begin
                          px.(output) <- ox; py.(output) <- oy; pz.(output) <- oz
                        end else Bytes.set invalid_positions vertex '\001';
                        point_map.(output) <- source_point;
                        (match point_uv_x, point_uv_y with
                         | Some ux, Some uy ->
                             ux.(output) <- if reverse_cross_sections
                               then 1. -. profile_u.(vertex)
                               else profile_u.(vertex);
                             uy.(output) <- if last - first = 1 then 0.
                               else float_of_int local /. float_of_int divisions
                         | None, None -> () | _ -> assert false)
                      done
                    end);
                  let invalid = ref 0 in
                  while !invalid < source_vertices
                      && Bytes.get invalid_positions !invalid = '\000' do
                    incr invalid
                  done;
                  if !invalid < source_vertices then Error (Printf.sprintf
                      "%s: generated ring for source vertex %d is not finite"
                      operation !invalid)
                  else begin
                    let ring_point vertex sample =
                      let count = ring_offsets.(vertex + 1) - ring_offsets.(vertex) in
                      if count = 1 then ring_offsets.(vertex)
                      else ring_offsets.(vertex) + sample in
                    let uv_u vertex = if reverse_cross_sections
                      then 1. -. profile_u.(vertex) else profile_u.(vertex) in
                    let set_corner corner point vertex u v =
                      vertex_points.(corner) <- point;
                      vertex_map.(corner) <- vertex;
                      match vertex_uv_x, vertex_uv_y with
                      | Some ux, Some uy -> ux.(corner) <- u; uy.(corner) <- v
                      | None, None -> () | _ -> assert false in
                    if polygon_surface && source_vertices > 0 then
                      Parallel.for_ ~chunk_size:(max 1 (grain / divisions))
                        ~start:0 ~finish:(source_vertices - 1) (fun current ->
                      let base = surface_edge_bases.(current) in
                      if base >= 0 then begin
                        if current land 4095 = 0 then Cancel.check_opt cancel;
                        let next = surface_edge_next.(current)
                        and local = surface_edge_local.(current)
                        and current_axis = Bytes.get on_axis current <> '\000'
                        and next_axis = Bytes.get on_axis
                            surface_edge_next.(current) <> '\000'
                        and output = ref base in
                        let finish () = incr output in
                        for side = 0 to divisions - 1 do
                          let next_side = if revolve_type = Revolve_closed
                            then (side + 1) mod angular_samples else side + 1 in
                          let p0 = ring_point current side
                          and p1 = ring_point current next_side
                          and p2 = ring_point next next_side
                          and p3 = ring_point next side
                          and u0 = uv_u current and u1 = uv_u next
                          and v0 = float_of_int side /. float_of_int divisions
                          and v1 = float_of_int (side + 1)
                              /. float_of_int divisions in
                          if current_axis then begin
                            let at = primitive_offsets.(!output) in
                            set_corner at p0 current u0 v0;
                            set_corner (at + 1) p2 next u1 v1;
                            set_corner (at + 2) p3 next u1 v0;
                            finish ()
                          end else if next_axis then begin
                            let at = primitive_offsets.(!output) in
                            set_corner at p0 current u0 v0;
                            set_corner (at + 1) p1 current u0 v1;
                            set_corner (at + 2) p2 next u1 v1;
                            finish ()
                          end else if connectivity = Grid_quads then begin
                            let at = primitive_offsets.(!output) in
                            set_corner at p0 current u0 v0;
                            set_corner (at + 1) p1 current u0 v1;
                            set_corner (at + 2) p2 next u1 v1;
                            set_corner (at + 3) p3 next u1 v0;
                            finish ()
                          end else begin
                            let reverse = connectivity = Grid_reverse_triangles
                              || connectivity = Grid_alternating_triangles
                                && ((local + side) land 1 = 1) in
                            let at = primitive_offsets.(!output) in
                            if reverse then begin
                              set_corner at p0 current u0 v0;
                              set_corner (at + 1) p1 current u0 v1;
                              set_corner (at + 2) p3 next u1 v0;
                              finish ();
                              let at = primitive_offsets.(!output) in
                              set_corner at p1 current u0 v1;
                              set_corner (at + 1) p2 next u1 v1;
                              set_corner (at + 2) p3 next u1 v0;
                              finish ()
                            end else begin
                              set_corner at p0 current u0 v0;
                              set_corner (at + 1) p1 current u0 v1;
                              set_corner (at + 2) p2 next u1 v1;
                              finish ();
                              let at = primitive_offsets.(!output) in
                              set_corner at p0 current u0 v0;
                              set_corner (at + 1) p2 next u1 v1;
                              set_corner (at + 2) p3 next u1 v0;
                              finish ()
                            end
                          end
                        done
                      end);
                    if source_primitives > 0 && output_primitives > 0 then
                      Parallel.for_ ~chunk_size:(max 1 (grain / 64)) ~start:0
                        ~finish:(source_primitives - 1) (fun primitive ->
                      if selected primitive then begin
                        Cancel.check_opt cancel;
                        let first = source.primitive_offsets.(primitive)
                        and last = source.primitive_offsets.(primitive + 1) in
                        let size = last - first
                        and output = ref primitive_bases.(primitive) in
                        let finish () = incr output in
                        (match connectivity with
                         | Grid_rows | Grid_rows_and_columns ->
                             for logical = 0 to size - 1 do
                               let vertex = source_vertex primitive logical in
                               if Bytes.get on_axis vertex = '\000' then begin
                                 let at = primitive_offsets.(!output)
                                 and u = uv_u vertex in
                                 for sample = 0 to angular_samples - 1 do
                                   set_corner (at + sample) (ring_point vertex sample)
                                     vertex u
                                     (float_of_int sample /. float_of_int divisions)
                                 done;
                                 finish ()
                               end
                             done
                         | Grid_points | Grid_columns | Grid_quads | Grid_triangles
                         | Grid_alternating_triangles | Grid_reverse_triangles -> ());
                        (match connectivity with
                         | Grid_columns | Grid_rows_and_columns ->
                             for sample = 0 to angular_samples - 1 do
                               let at = primitive_offsets.(!output)
                               and v = float_of_int sample /. float_of_int divisions in
                               for logical = 0 to size - 1 do
                                 let vertex = source_vertex primitive logical in
                                 set_corner (at + logical) (ring_point vertex sample)
                                   vertex (uv_u vertex) v
                               done;
                               finish ()
                             done
                         | Grid_points | Grid_rows | Grid_quads | Grid_triangles
                         | Grid_alternating_triangles | Grid_reverse_triangles -> ());
                        if polygon_surface then begin
                          let edges = size - 1 +
                              if Topology.primitive_kind topology primitive
                                  = Topology.Closed_polyline then 1 else 0 in
                          for local = 0 to edges - 1 do
                            let current = source_vertex primitive local in
                            let base = surface_edge_bases.(current) in
                            if base >= 0 then begin
                              let next = surface_edge_next.(current) in
                              let multiplier = if Bytes.get on_axis current <> '\000'
                                  || Bytes.get on_axis next <> '\000'
                                  || connectivity = Grid_quads then 1 else 2 in
                              output := !output + (divisions * multiplier)
                            end
                          done;
                          if caps && Topology.primitive_kind topology primitive
                              = Topology.Open_polyline then begin
                            let start = source_vertex primitive 0
                            and finish_vertex = source_vertex primitive (size - 1) in
                            if Bytes.get on_axis start = '\000' then begin
                              let at = primitive_offsets.(!output) in
                              for local = 0 to divisions - 1 do
                                let sample = local in
                                set_corner (at + local) (ring_point start sample)
                                  start (0.5 +. (0.5 *. angle_cos.(sample)))
                                  (0.5 +. (0.5 *. angle_sin.(sample)))
                              done;
                              finish ()
                            end;
                            if Bytes.get on_axis finish_vertex = '\000' then begin
                              let at = primitive_offsets.(!output) in
                              for local = 0 to divisions - 1 do
                                let sample = divisions - 1 - local in
                                set_corner (at + local)
                                  (ring_point finish_vertex sample) finish_vertex
                                  (0.5 +. (0.5 *. angle_cos.(sample)))
                                  (0.5 +. (0.5 *. angle_sin.(sample)))
                              done;
                              finish ()
                            end
                          end
                        end;
                        assert (!output = primitive_bases.(primitive + 1))
                      end);
                    let output_positions = Packed.Float3.Private.of_owned_exn
                        ~x:px ~y:py ~z:pz
                    and output_topology = Topology.Private.create_validated_owned
                        ~point_count:output_points ~vertex_points
                        ~primitive_offsets ~primitive_kinds in
                    let uv_owner = if connectivity = Grid_points
                      then Attribute.Point else Attribute.Vertex in
                    let rec remap_attributes result = function
                      | [] -> Ok (List.rev result)
                      | attribute :: rest ->
                          let generated_conflict = match uv_attribute with
                            | Some name -> Attribute.owner attribute = uv_owner
                                && String.equal (Attribute.name attribute) name
                            | None -> false in
                          if generated_conflict then remap_attributes result rest
                          else Result.bind
                              (remap_attribute_all point_map vertex_map
                                primitive_map attribute)
                              (function
                                | None -> remap_attributes result rest
                                | Some value -> remap_attributes
                                    (value :: result) rest) in
                    Result.bind
                      (remap_attributes [] (Geometry.attributes geometry))
                      (fun attributes ->
                      let attributes = match uv_attribute, point_uv_x, point_uv_y,
                          vertex_uv_x, vertex_uv_y with
                        | None, _, _, _, _ -> attributes
                        | Some name, Some x, Some y, None, None ->
                            (Attribute.create_owned ~name ~owner:Attribute.Point
                              (Attribute.Float2
                                (Packed.Float2.of_owned ~x ~y |> get_ok))
                              |> get_ok) :: attributes
                        | Some name, None, None, Some x, Some y ->
                            (Attribute.create_owned ~name ~owner:Attribute.Vertex
                              (Attribute.Float2
                                (Packed.Float2.of_owned ~x ~y |> get_ok))
                              |> get_ok) :: attributes
                        | _ -> assert false in
                      let groups = List.map
                          (remap_group_all point_map vertex_map primitive_map)
                          (Geometry.groups geometry) in
                      let edge_groups = match Geometry.edge_groups geometry with
                        | [] -> []
                        | source_groups ->
                            let source_index = Topology_index.create ?cancel topology
                            and target_index = Topology_index.create ?cancel
                                output_topology in
                            let target_view = Topology_index.Private.view
                                target_index in
                            List.map (fun source_group ->
                              Edge_group.init ~grain ~topology:output_topology
                                ~index:target_index
                                ~name:(Edge_group.name source_group)
                                (fun target_edge ->
                                  let target_a = target_view.edge_a.(target_edge)
                                  and target_b = target_view.edge_b.(target_edge) in
                                  let source_a = point_map.(target_a)
                                  and source_b = point_map.(target_b) in
                                  source_a <> source_b
                                  && match Topology_index.find_edge source_index
                                      ~a:source_a ~b:source_b with
                                     | Some source_edge ->
                                         Edge_group.mem source_edge source_group
                                     | None -> false)) source_groups in
                      Result.bind (Geometry.create ~positions:output_positions
                          ~topology:output_topology ~attributes ~groups
                          ~edge_groups ()) (fun output_geometry ->
                        match cap_group with
                        | None -> Ok output_geometry
                        | Some name -> Geometry.with_group
                            (Group.init ~grain ~owner:Group.Primitive ~name
                              output_primitives (fun primitive ->
                                Bytes.get cap_flags primitive <> '\000'))
                            output_geometry))
                  end)
          end

let sweep_circle ?cancel ?(grain = 16_384) ?(sides = 12) ?scale_attribute
    ?(seam_offset = 0) ?seam_attribute ?v_attribute ?up_attribute
    ?(caps = false) ?cap_group ~radius geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.sweep_circle: grain must be positive";
  if sides < 3 then Error "Pdk.Ops.sweep_circle: sides must be at least three"
  else if not (finite radius) || radius <= 0. then
    Error "Pdk.Ops.sweep_circle: radius must be finite and positive"
  else
    let topology = Geometry.topology geometry
    and source_positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let source_vertices = Geometry.vertex_count geometry
    and source_primitives = Geometry.primitive_count geometry in
    let find_point_attribute label name storage = match name with
      | None -> None, None
      | Some name when String.trim name = "" ->
          None, Some (label ^ " attribute name must not be empty")
      | Some name ->
          (match Geometry.find_attribute ~owner:Attribute.Point name geometry with
           | None -> None, Some (Printf.sprintf
               "point %s attribute %S does not exist" label name)
           | Some attribute ->
               match storage (Attribute.Private.storage attribute) with
               | Some values -> Some values, None
               | None -> None, Some (Printf.sprintf
                   "point %s attribute %S has incompatible storage" label name)) in
    let scale_values, scale_error = find_point_attribute "scale" scale_attribute
        (function Attribute.Float values -> Some values | _ -> None)
    and seam_values, seam_error = find_point_attribute "seam" seam_attribute
        (function Attribute.Int values -> Some values | _ -> None)
    and v_values, v_error = find_point_attribute "V texture" v_attribute
        (function Attribute.Float values -> Some values | _ -> None)
    and up_values, up_error = find_point_attribute "joint up" up_attribute
        (function Attribute.Float3 values ->
          Some (Packed.Float3.Private.view values) | _ -> None) in
    let invalid = ref (List.find_opt Option.is_some
        [scale_error; seam_error; v_error; up_error] |> Option.join)
    and edge_count = ref 0
    and open_count = ref 0 in
    Option.iter (fun name -> if String.trim name = "" then
      invalid := Some "cap group name must not be empty") cap_group;
    if cap_group <> None && not caps then
      invalid := Some "cap_group requires caps=true";
    Option.iter (fun values ->
      let point = ref 0 in
      while !invalid = None && !point < Array.length values do
        let value = values.(!point) in
        if not (finite value) || value < 0. then invalid := Some (Printf.sprintf
            "point scale attribute %S contains a non-finite or negative value at point %d"
            (Option.get scale_attribute) !point);
        incr point
      done) scale_values;
    Option.iter (fun values ->
      let point = ref 0 in
      while !invalid = None && !point < Array.length values do
        if not (finite values.(!point)) then invalid := Some (Printf.sprintf
            "point V texture attribute %S contains a non-finite value at point %d"
            (Option.get v_attribute) !point);
        incr point
      done) v_values;
    Option.iter (fun (values : Packed.Float3.Private.view) ->
      let point = ref 0 in
      while !invalid = None && !point < Array.length values.x do
        if not (finite values.x.(!point) && finite values.y.(!point)
            && finite values.z.(!point)) then invalid := Some (Printf.sprintf
            "point joint up attribute %S contains a non-finite value at point %d"
            (Option.get up_attribute) !point);
        incr point
      done) up_values;
    let source_primitive_offsets = Array.make (source_primitives + 1) 0
    and open_ranks = Array.make source_primitives (-1) in
    for primitive = 0 to source_primitives - 1 do
      let size = Topology.primitive_size topology primitive in
      match Topology.primitive_kind topology primitive with
      | Topology.Polygon -> if !invalid = None then invalid := Some
          (Printf.sprintf "primitive %d is a polygon" primitive)
      | Topology.Open_polyline ->
          open_ranks.(primitive) <- !open_count;
          incr open_count;
          edge_count := !edge_count + size - 1;
          source_primitive_offsets.(primitive + 1) <- !edge_count
      | Topology.Closed_polyline ->
          edge_count := !edge_count + size;
          source_primitive_offsets.(primitive + 1) <- !edge_count
    done;
    if source_vertices > max_int / sides || !edge_count > max_int / sides
        || (caps && !open_count > max_int / 2) then
      invalid := Some "output cardinality exceeds OCaml array limits";
    if !invalid = None then
      for primitive = 1 to source_primitives do
        source_primitive_offsets.(primitive) <-
          source_primitive_offsets.(primitive) * sides
      done;
    match !invalid with
    | Some message -> Error ("Pdk.Ops.sweep_circle: " ^ message)
    | None ->
        let output_points = source_vertices * sides
        and side_primitives = !edge_count * sides in
        let cap_primitives = if caps then !open_count * 2 else 0 in
        let output_primitives = side_primitives + cap_primitives in
        if output_primitives < side_primitives
            || side_primitives > max_int / 4
            || (cap_primitives > 0
                && cap_primitives > (max_int - (side_primitives * 4)) / sides) then
          Error "Pdk.Ops.sweep_circle: output vertex count exceeds OCaml array limits"
        else
          let side_vertices = side_primitives * 4 in
          let output_vertices = side_vertices + (cap_primitives * sides) in
          let px = Array.make output_points 0. and py = Array.make output_points 0.
          and pz = Array.make output_points 0. and nx = Array.make output_points 0.
          and ny = Array.make output_points 0. and nz = Array.make output_points 0.
          and uvx = Array.make output_vertices 0. and uvy = Array.make output_vertices 0.
          and point_map = Array.make output_points 0
          and frame_nx = Array.make source_vertices 0.
          and frame_ny = Array.make source_vertices 0.
          and frame_nz = Array.make source_vertices 0.
          and tangent_x = Array.make source_vertices 0.
          and tangent_y = Array.make source_vertices 0.
          and tangent_z = Array.make source_vertices 0.
          and cumulative = Array.make source_vertices 0.
          and curve_total = Array.make source_primitives 0.
          and vertex_points = Array.make output_vertices 0
          and vertex_map = Array.make output_vertices 0
          and primitive_offsets = Array.init (output_primitives + 1)
              (fun primitive ->
                if primitive <= side_primitives then primitive * 4
                else side_vertices + ((primitive - side_primitives) * sides))
          and primitive_map = Array.make output_primitives 0
          and primitive_kinds = Bytes.make output_primitives '\000'
          and vertex_nx = if caps then Array.make output_vertices 0. else [||]
          and vertex_ny = if caps then Array.make output_vertices 0. else [||]
          and vertex_nz = if caps then Array.make output_vertices 0. else [||] in
          let edge_primitive = Array.make !edge_count 0 in
          if source_primitives > 0 then Parallel.for_ ~chunk_size:1 ~start:0
              ~finish:(source_primitives - 1) (fun primitive ->
            let first_edge = source_primitive_offsets.(primitive) / sides
            and last_edge = source_primitive_offsets.(primitive + 1) / sides in
            for edge = first_edge to last_edge - 1 do
              edge_primitive.(edge) <- primitive
            done);
          let side_cos = Array.init sides (fun side ->
              cos (2. *. Float.pi *. float_of_int side /. float_of_int sides))
          and side_sin = Array.init sides (fun side ->
              sin (2. *. Float.pi *. float_of_int side /. float_of_int sides))
          and failures = Bytes.make source_primitives '\000'
          and invalid_frames = Bytes.make source_vertices '\000' in
          let base_seam = let value = seam_offset mod sides in
            if value < 0 then value + sides else value in
          let initialize_frame vertex tx ty tz =
            let ax, ay, az =
              let x = abs_float tx and y = abs_float ty and z = abs_float tz in
              if x <= y && x <= z then 1., 0., 0.
              else if y <= z then 0., 1., 0. else 0., 0., 1. in
            let x = (ay *. tz) -. (az *. ty)
            and y = (az *. tx) -. (ax *. tz)
            and z = (ax *. ty) -. (ay *. tx) in
            let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
            frame_nx.(vertex) <- x /. length;
            frame_ny.(vertex) <- y /. length;
            frame_nz.(vertex) <- z /. length in
          let average_vertices = max 1
              (source_vertices / max 1 source_primitives) in
          if source_primitives > 0 then Parallel.for_
              ~chunk_size:(max 1 (grain / average_vertices)) ~start:0
              ~finish:(source_primitives - 1) (fun primitive ->
            Cancel.check_opt cancel;
            let first, last = Topology.primitive_vertex_range topology primitive in
            let count = last - first
            and closed = Topology.primitive_kind topology primitive
                = Topology.Closed_polyline in
            for local = 0 to count - 1 do
              if local land 4095 = 0 then Cancel.check_opt cancel;
              let previous = if local = 0 then (if closed then count - 1 else 0)
                else local - 1
              and next = if local = count - 1 then (if closed then 0 else count - 1)
                else local + 1 in
              let previous_point = Topology.point_of_vertex topology (first + previous)
              and next_point = Topology.point_of_vertex topology (first + next) in
              let tx = source_positions.x.(next_point) -. source_positions.x.(previous_point)
              and ty = source_positions.y.(next_point) -. source_positions.y.(previous_point)
              and tz = source_positions.z.(next_point) -. source_positions.z.(previous_point) in
              let ax = abs_float tx and ay = abs_float ty and az = abs_float tz in
              let scale = if ax >= ay then if ax >= az then ax else az
                else if ay >= az then ay else az in
              let sx = if scale = 0. then 0. else tx /. scale
              and sy = if scale = 0. then 0. else ty /. scale
              and sz = if scale = 0. then 0. else tz /. scale in
              let length = sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
              if scale = 0. || not (finite scale && finite length) then begin
                if Bytes.get failures primitive = '\000' then
                  Bytes.set failures primitive '\001'
              end
              else begin
                tangent_x.(first + local) <- sx /. length;
                tangent_y.(first + local) <- sy /. length;
                tangent_z.(first + local) <- sz /. length
              end;
              if local > 0 then begin
                let a = Topology.point_of_vertex topology (first + local - 1)
                and b = Topology.point_of_vertex topology (first + local) in
                let dx = source_positions.x.(b) -. source_positions.x.(a)
                and dy = source_positions.y.(b) -. source_positions.y.(a)
                and dz = source_positions.z.(b) -. source_positions.z.(a) in
                let ax = abs_float dx and ay = abs_float dy
                and az = abs_float dz in
                let scale = if ax >= ay then if ax >= az then ax else az
                  else if ay >= az then ay else az in
                let sx = if scale = 0. then 0. else dx /. scale
                and sy = if scale = 0. then 0. else dy /. scale
                and sz = if scale = 0. then 0. else dz /. scale in
                let segment_length = scale
                    *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                if segment_length <= 1e-20 || not (finite segment_length) then
                  Bytes.set failures primitive '\003'
                else cumulative.(first + local) <-
                    cumulative.(first + local - 1) +. segment_length
              end
            done;
            let total = if closed then begin
                let a = Topology.point_of_vertex topology (last - 1)
                and b = Topology.point_of_vertex topology first in
                let dx = source_positions.x.(b) -. source_positions.x.(a)
                and dy = source_positions.y.(b) -. source_positions.y.(a)
                and dz = source_positions.z.(b) -. source_positions.z.(a) in
                let ax = abs_float dx and ay = abs_float dy
                and az = abs_float dz in
                let scale = if ax >= ay then if ax >= az then ax else az
                  else if ay >= az then ay else az in
                let sx = if scale = 0. then 0. else dx /. scale
                and sy = if scale = 0. then 0. else dy /. scale
                and sz = if scale = 0. then 0. else dz /. scale in
                let segment_length = scale
                    *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                if segment_length <= 1e-20 || not (finite segment_length) then begin
                  Bytes.set failures primitive '\003'; 0.
                end else cumulative.(last - 1) +. segment_length
              end else cumulative.(last - 1) in
            curve_total.(primitive) <- total;
            if total <= 1e-20 || not (finite total) then begin
              if Bytes.get failures primitive = '\000' then
                Bytes.set failures primitive '\002'
            end;
            if Bytes.get failures primitive = '\000' then begin
              (match up_values with
               | Some _ -> ()
               | None ->
                initialize_frame first tangent_x.(first) tangent_y.(first)
                  tangent_z.(first);
                for local = 1 to count - 1 do
                let previous = first + local - 1 and vertex = first + local in
                let ax = (tangent_y.(previous) *. tangent_z.(vertex))
                    -. (tangent_z.(previous) *. tangent_y.(vertex))
                and ay = (tangent_z.(previous) *. tangent_x.(vertex))
                    -. (tangent_x.(previous) *. tangent_z.(vertex))
                and az = (tangent_x.(previous) *. tangent_y.(vertex))
                    -. (tangent_y.(previous) *. tangent_x.(vertex)) in
                let sine = sqrt ((ax *. ax) +. (ay *. ay) +. (az *. az))
                and cosine = (tangent_x.(previous) *. tangent_x.(vertex))
                    +. (tangent_y.(previous) *. tangent_y.(vertex))
                    +. (tangent_z.(previous) *. tangent_z.(vertex)) in
                if sine <= 1e-12 then
                  if cosine >= 0. then begin
                    frame_nx.(vertex) <- frame_nx.(previous);
                    frame_ny.(vertex) <- frame_ny.(previous);
                    frame_nz.(vertex) <- frame_nz.(previous)
                  end else initialize_frame vertex tangent_x.(vertex)
                      tangent_y.(vertex) tangent_z.(vertex)
                else begin
                  let kx = ax /. sine and ky = ay /. sine and kz = az /. sine
                  and vx = frame_nx.(previous) and vy = frame_ny.(previous)
                  and vz = frame_nz.(previous) in
                  let cross_x = (ky *. vz) -. (kz *. vy)
                  and cross_y = (kz *. vx) -. (kx *. vz)
                  and cross_z = (kx *. vy) -. (ky *. vx)
                  and dot = (kx *. vx) +. (ky *. vy) +. (kz *. vz) in
                  frame_nx.(vertex) <- (vx *. cosine) +. (cross_x *. sine)
                    +. (kx *. dot *. (1. -. cosine));
                  frame_ny.(vertex) <- (vy *. cosine) +. (cross_y *. sine)
                    +. (ky *. dot *. (1. -. cosine));
                  frame_nz.(vertex) <- (vz *. cosine) +. (cross_z *. sine)
                    +. (kz *. dot *. (1. -. cosine))
                end
                done;
                if closed then begin
                  let previous = last - 1 and vertex = first in
                  let ax = (tangent_y.(previous) *. tangent_z.(vertex))
                      -. (tangent_z.(previous) *. tangent_y.(vertex))
                  and ay = (tangent_z.(previous) *. tangent_x.(vertex))
                      -. (tangent_x.(previous) *. tangent_z.(vertex))
                  and az = (tangent_x.(previous) *. tangent_y.(vertex))
                      -. (tangent_y.(previous) *. tangent_x.(vertex)) in
                  let sine = sqrt ((ax *. ax) +. (ay *. ay) +. (az *. az))
                  and cosine = (tangent_x.(previous) *. tangent_x.(vertex))
                      +. (tangent_y.(previous) *. tangent_y.(vertex))
                      +. (tangent_z.(previous) *. tangent_z.(vertex)) in
                  let cnx, cny, cnz = if sine <= 1e-12 then
                      frame_nx.(previous), frame_ny.(previous),
                      frame_nz.(previous)
                    else
                      let kx = ax /. sine and ky = ay /. sine and kz = az /. sine
                      and vx = frame_nx.(previous) and vy = frame_ny.(previous)
                      and vz = frame_nz.(previous) in
                      let cross_x = (ky *. vz) -. (kz *. vy)
                      and cross_y = (kz *. vx) -. (kx *. vz)
                      and cross_z = (kx *. vy) -. (ky *. vx)
                      and dot = (kx *. vx) +. (ky *. vy) +. (kz *. vz) in
                      (vx *. cosine) +. (cross_x *. sine)
                        +. (kx *. dot *. (1. -. cosine)),
                      (vy *. cosine) +. (cross_y *. sine)
                        +. (ky *. dot *. (1. -. cosine)),
                      (vz *. cosine) +. (cross_z *. sine)
                        +. (kz *. dot *. (1. -. cosine)) in
                  let target_x = frame_nx.(first)
                  and target_y = frame_ny.(first)
                  and target_z = frame_nz.(first) in
                  let cross_x = (cny *. target_z) -. (cnz *. target_y)
                  and cross_y = (cnz *. target_x) -. (cnx *. target_z)
                  and cross_z = (cnx *. target_y) -. (cny *. target_x) in
                  let correction = atan2
                      ((tangent_x.(first) *. cross_x)
                        +. (tangent_y.(first) *. cross_y)
                        +. (tangent_z.(first) *. cross_z))
                      ((cnx *. target_x) +. (cny *. target_y)
                        +. (cnz *. target_z)) in
                  let span = cumulative.(last - 1) in
                  if abs_float correction > 1e-15 && span > 0. then
                    for local = 1 to count - 1 do
                      let vertex = first + local in
                      let angle = correction *. cumulative.(vertex) /. span in
                      let cosine = cos angle and sine = sin angle
                      and tx = tangent_x.(vertex) and ty = tangent_y.(vertex)
                      and tz = tangent_z.(vertex)
                      and vx = frame_nx.(vertex) and vy = frame_ny.(vertex)
                      and vz = frame_nz.(vertex) in
                      let cross_x = (ty *. vz) -. (tz *. vy)
                      and cross_y = (tz *. vx) -. (tx *. vz)
                      and cross_z = (tx *. vy) -. (ty *. vx) in
                      frame_nx.(vertex) <- (vx *. cosine) +. (cross_x *. sine);
                      frame_ny.(vertex) <- (vy *. cosine) +. (cross_y *. sine);
                      frame_nz.(vertex) <- (vz *. cosine) +. (cross_z *. sine)
                    done
                end)
            end);
          Option.iter (fun (up : Packed.Float3.Private.view) ->
            if source_vertices > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                ~finish:(source_vertices - 1) (fun vertex ->
              if vertex land 4095 = 0 then Cancel.check_opt cancel;
                let source_point = Topology.point_of_vertex topology vertex in
                let tx = tangent_x.(vertex) and ty = tangent_y.(vertex)
                and tz = tangent_z.(vertex) in
                let ax = abs_float up.x.(source_point)
                and ay = abs_float up.y.(source_point)
                and az = abs_float up.z.(source_point) in
                let scale = if ax >= ay then if ax >= az then ax else az
                  else if ay >= az then ay else az in
                let ux = if scale = 0. then 0. else up.x.(source_point) /. scale
                and uy = if scale = 0. then 0. else up.y.(source_point) /. scale
                and uz = if scale = 0. then 0. else up.z.(source_point) /. scale in
                let projection = (ux *. tx) +. (uy *. ty) +. (uz *. tz) in
                let x = ux -. (projection *. tx)
                and y = uy -. (projection *. ty)
                and z = uz -. (projection *. tz) in
                let ax = abs_float x and ay = abs_float y
                and az = abs_float z in
                let residual_scale = if ax >= ay then
                    if ax >= az then ax else az
                  else if ay >= az then ay else az in
                let sx = if residual_scale = 0. then 0.
                    else x /. residual_scale
                and sy = if residual_scale = 0. then 0.
                    else y /. residual_scale
                and sz = if residual_scale = 0. then 0.
                    else z /. residual_scale in
                let length = sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                if scale = 0. || residual_scale <= 1e-12
                    || not (finite length) then
                  Bytes.set invalid_frames vertex '\001'
                else begin
                  frame_nx.(vertex) <- sx /. length;
                  frame_ny.(vertex) <- sy /. length;
                  frame_nz.(vertex) <- sz /. length
                end)) up_values;
          let invalid_positions = Bytes.make source_vertices '\000' in
          if source_vertices > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(source_vertices - 1) (fun vertex ->
            if vertex land 4095 = 0 then Cancel.check_opt cancel;
            let source_point = Topology.point_of_vertex topology vertex in
            let ring_radius = radius *. match scale_values with
              | None -> 1. | Some values -> values.(source_point) in
            let attribute_seam = match seam_values with
              | None -> 0
              | Some values -> let value = values.(source_point) mod sides in
                  if value < 0 then value + sides else value in
            let ring_seam = let value = base_seam + attribute_seam in
              if value >= sides then value - sides else value in
            let bx = (tangent_y.(vertex) *. frame_nz.(vertex))
                -. (tangent_z.(vertex) *. frame_ny.(vertex))
            and by = (tangent_z.(vertex) *. frame_nx.(vertex))
                -. (tangent_x.(vertex) *. frame_nz.(vertex))
            and bz = (tangent_x.(vertex) *. frame_ny.(vertex))
                -. (tangent_y.(vertex) *. frame_nx.(vertex)) in
            let frame_b_length = sqrt ((bx *. bx) +. (by *. by) +. (bz *. bz)) in
            let invalid_frame_b = frame_b_length = 0.
                || not (finite frame_b_length) in
            if invalid_frame_b then Bytes.set invalid_frames vertex '\002';
            let bx = if invalid_frame_b then 0. else bx /. frame_b_length
            and by = if invalid_frame_b then 0. else by /. frame_b_length
            and bz = if invalid_frame_b then 0. else bz /. frame_b_length in
            for side = 0 to sides - 1 do
              let profile_side = let value = side + ring_seam in
                if value >= sides then value - sides else value in
              let cosine = side_cos.(profile_side)
              and sine = side_sin.(profile_side)
              and output = (vertex * sides) + side in
              let rx = (frame_nx.(vertex) *. cosine)
                  +. (bx *. sine)
              and ry = (frame_ny.(vertex) *. cosine)
                  +. (by *. sine)
              and rz = (frame_nz.(vertex) *. cosine)
                  +. (bz *. sine) in
              let x = source_positions.x.(source_point) +. (ring_radius *. rx)
              and y = source_positions.y.(source_point) +. (ring_radius *. ry)
              and z = source_positions.z.(source_point) +. (ring_radius *. rz) in
              if finite x && finite y && finite z then begin
                px.(output) <- x; py.(output) <- y; pz.(output) <- z
              end else Bytes.set invalid_positions vertex '\001';
              nx.(output) <- rx; ny.(output) <- ry; nz.(output) <- rz;
              point_map.(output) <- source_point
            done);
          if !edge_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(!edge_count - 1) (fun edge ->
            if edge land 4095 = 0 then Cancel.check_opt cancel;
            let primitive = edge_primitive.(edge) in
            let first, last = Topology.primitive_vertex_range topology primitive in
            let count = last - first
            and closed = Topology.primitive_kind topology primitive
                = Topology.Closed_polyline
            and edge_base = source_primitive_offsets.(primitive) / sides in
            let local = edge - edge_base in
            let current = first + local
            and next = first + ((local + 1) mod count)
            and total = curve_total.(primitive) in
            for side = 0 to sides - 1 do
              let next_side = (side + 1) mod sides
              and output_primitive = (edge * sides) + side in
              let at = output_primitive * 4 in
              vertex_points.(at) <- (current * sides) + side;
              vertex_points.(at + 1) <- (current * sides) + next_side;
              vertex_points.(at + 2) <- (next * sides) + next_side;
              vertex_points.(at + 3) <- (next * sides) + side;
              if caps then begin
                vertex_nx.(at) <- nx.((current * sides) + side);
                vertex_ny.(at) <- ny.((current * sides) + side);
                vertex_nz.(at) <- nz.((current * sides) + side);
                vertex_nx.(at + 1) <- nx.((current * sides) + next_side);
                vertex_ny.(at + 1) <- ny.((current * sides) + next_side);
                vertex_nz.(at + 1) <- nz.((current * sides) + next_side);
                vertex_nx.(at + 2) <- nx.((next * sides) + next_side);
                vertex_ny.(at + 2) <- ny.((next * sides) + next_side);
                vertex_nz.(at + 2) <- nz.((next * sides) + next_side);
                vertex_nx.(at + 3) <- nx.((next * sides) + side);
                vertex_ny.(at + 3) <- ny.((next * sides) + side);
                vertex_nz.(at + 3) <- nz.((next * sides) + side)
              end;
              vertex_map.(at) <- current; vertex_map.(at + 1) <- current;
              vertex_map.(at + 2) <- next; vertex_map.(at + 3) <- next;
              let u0 = float_of_int side /. float_of_int sides
              and u1 = float_of_int (side + 1) /. float_of_int sides
              and v0 = match v_values with
                | Some values -> values.(Topology.point_of_vertex topology current)
                | None -> cumulative.(current) /. total
              and v1 = match v_values with
                | Some values -> values.(Topology.point_of_vertex topology next)
                | None -> if closed && local = count - 1 then 1.
                    else cumulative.(next) /. total in
              uvx.(at) <- u0; uvy.(at) <- v0;
              uvx.(at + 1) <- u1; uvy.(at + 1) <- v0;
              uvx.(at + 2) <- u1; uvy.(at + 2) <- v1;
              uvx.(at + 3) <- u0; uvy.(at + 3) <- v1;
              primitive_map.(output_primitive) <- primitive
            done);
          if caps && source_primitives > 0 then Parallel.for_
              ~chunk_size:(max 1 (grain / average_vertices)) ~start:0
              ~finish:(source_primitives - 1) (fun primitive ->
            let rank = open_ranks.(primitive) in
            if rank >= 0 && Bytes.get failures primitive = '\000' then begin
              Cancel.check_opt cancel;
              let first, last = Topology.primitive_vertex_range topology primitive in
              let start_primitive = side_primitives + (rank * 2)
              and start_vertex = side_vertices + (rank * 2 * sides) in
              let seam_at vertex =
                let source_point = Topology.point_of_vertex topology vertex in
                let attribute_seam = match seam_values with
                  | None -> 0
                  | Some values -> let value = values.(source_point) mod sides in
                      if value < 0 then value + sides else value in
                let value = base_seam + attribute_seam in
                if value >= sides then value - sides else value in
              let start_seam = seam_at first and end_seam = seam_at (last - 1) in
              primitive_map.(start_primitive) <- primitive;
              primitive_map.(start_primitive + 1) <- primitive;
              for local = 0 to sides - 1 do
                let start_side = sides - 1 - local
                and end_side = local
                and start_at = start_vertex + local
                and end_at = start_vertex + sides + local in
                vertex_points.(start_at) <- (first * sides) + start_side;
                vertex_points.(end_at) <- ((last - 1) * sides) + end_side;
                vertex_map.(start_at) <- first;
                vertex_map.(end_at) <- last - 1;
                let start_profile = let value = start_side + start_seam in
                  if value >= sides then value - sides else value
                and end_profile = let value = end_side + end_seam in
                  if value >= sides then value - sides else value in
                uvx.(start_at) <- 0.5 +. (0.5 *. side_cos.(start_profile));
                uvy.(start_at) <- 0.5 +. (0.5 *. side_sin.(start_profile));
                uvx.(end_at) <- 0.5 +. (0.5 *. side_cos.(end_profile));
                uvy.(end_at) <- 0.5 +. (0.5 *. side_sin.(end_profile));
                vertex_nx.(start_at) <- -.tangent_x.(first);
                vertex_ny.(start_at) <- -.tangent_y.(first);
                vertex_nz.(start_at) <- -.tangent_z.(first);
                vertex_nx.(end_at) <- tangent_x.(last - 1);
                vertex_ny.(end_at) <- tangent_y.(last - 1);
                vertex_nz.(end_at) <- tangent_z.(last - 1)
              done
            end);
          let failed_primitive = ref 0 in
          while !failed_primitive < source_primitives
              && Bytes.get failures !failed_primitive = '\000' do
            incr failed_primitive
          done;
          let invalid_frame = ref 0 in
          while !invalid_frame < source_vertices
              && Bytes.get invalid_frames !invalid_frame = '\000' do
            incr invalid_frame
          done;
          let invalid_position = ref 0 in
          while !invalid_position < source_vertices
              && Bytes.get invalid_positions !invalid_position = '\000' do
            incr invalid_position
          done;
          if !failed_primitive < source_primitives then
            Error (Printf.sprintf "Pdk.Ops.sweep_circle: primitive %d has %s"
              !failed_primitive
              (match Bytes.get failures !failed_primitive with
               | '\001' -> "an undefined tangent"
               | '\003' -> "a zero-length or non-finite edge"
               | _ -> "zero length"))
          else if !invalid_frame < source_vertices then
            Error (Printf.sprintf
              "Pdk.Ops.sweep_circle: point %d has %s"
              (Topology.point_of_vertex topology !invalid_frame)
              (match Bytes.get invalid_frames !invalid_frame with
               | '\001' -> "a joint up vector parallel to its tangent"
               | _ -> "an undefined local frame"))
          else if !invalid_position < source_vertices then
            Error (Printf.sprintf
              "Pdk.Ops.sweep_circle: generated ring %d is not finite"
              !invalid_position)
          else
              let output_positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz
              and output_topology = Topology.Private.create_validated_owned
                  ~point_count:output_points ~vertex_points ~primitive_offsets
                  ~primitive_kinds in
              let rec attributes result = function
                | [] -> Ok (List.rev result)
                | attribute :: rest -> Result.bind
                    (remap_attribute_all point_map vertex_map primitive_map attribute)
                    (function None -> attributes result rest
                      | Some attribute -> attributes (attribute :: result) rest) in
              Result.bind (attributes [] (Geometry.attributes geometry)) (fun attributes ->
                let normal = Attribute.create_key_owned
                    (Attribute.normal ~owner:Attribute.Point)
                    (Packed.Float3.Private.of_owned_exn ~x:nx ~y:ny ~z:nz) |> get_ok
                and uv = Attribute.create_key_owned
                    (Attribute.tex_coord ~owner:Attribute.Vertex)
                    (Packed.Float2.of_owned ~x:uvx ~y:uvy |> get_ok) |> get_ok in
                let vertex_normal = if caps then Some
                    (Attribute.create_key_owned
                      (Attribute.normal ~owner:Attribute.Vertex)
                      (Packed.Float3.Private.of_owned_exn ~x:vertex_nx
                        ~y:vertex_ny ~z:vertex_nz) |> get_ok)
                  else None in
                let groups = List.map
                    (remap_group_all point_map vertex_map primitive_map)
                    (Geometry.groups geometry) in
                let edge_groups = match Geometry.edge_groups geometry with
                  | [] -> []
                  | source_groups ->
                      let source_index = Topology_index.create ?cancel topology
                      and target_index = Topology_index.create ?cancel
                          output_topology in
                      List.map (fun source_group ->
                        let builder = Edge_group.Builder.create
                            ~topology:output_topology ~index:target_index
                            ~name:(Edge_group.name source_group) in
                        Edge_group.iter (fun edge ->
                          let incidence = Topology_index.edge_incidence_count
                              source_index edge in
                          for local = 0 to incidence - 1 do
                            let current = Topology_index.edge_vertex source_index
                                ~edge ~local in
                            let next = Topology_index.next_vertex source_index current in
                            if next >= 0 then
                              for side = 0 to sides - 1 do
                                match Topology_index.find_edge target_index
                                    ~a:(current * sides + side)
                                    ~b:(next * sides + side) with
                                | None -> ()
                                | Some target ->
                                    Edge_group.Builder.set builder target true
                              done
                          done) source_group;
                        Edge_group.Builder.freeze builder) source_groups in
                Result.bind (Geometry.create ~positions:output_positions
                    ~topology:output_topology ~attributes ~groups ~edge_groups ())
                  (fun geometry ->
                  Result.bind (Geometry.with_attribute normal geometry)
                    (fun geometry ->
                  Result.bind (Geometry.with_attribute uv geometry)
                    (fun geometry ->
                  Result.bind (match vertex_normal with
                    | None -> Ok geometry
                    | Some normal -> Geometry.with_attribute normal geometry)
                    (fun geometry -> match cap_group with
                      | None -> Ok geometry
                      | Some name -> Geometry.with_group
                          (Group.init ~grain ~owner:Group.Primitive ~name
                            output_primitives
                            (fun primitive -> primitive >= side_primitives))
                          geometry)))))

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

let polyline_raw = polyline
let polyline ?closed values =
  detailed "polyline" "invalid_parameter" (polyline_raw ?closed values)

let line_raw = line
let line ?cancel ?grain ?kind ?points ~origin ~direction ~length () =
  protected "line" "invalid_parameter" (fun () ->
    line_raw ?cancel ?grain ?kind ?points ~origin ~direction ~length ())

let circle_raw = circle
let circle ?cancel ?grain ?arc ?orientation ?reverse ?center ?radius_x ?radius_y
    ?rotation ?uniform_scale ?segments ~radius () =
  protected "circle" "invalid_parameter" (fun () ->
    circle_raw ?cancel ?grain ?arc ?orientation ?reverse ?center ?radius_x
      ?radius_y ?rotation ?uniform_scale ?segments ~radius ())

let grid_raw = grid
let grid ?cancel ?grain ?counts ?connectivity ?orientation ?center ?width
    ?height ?rotation ?uv_attribute ~columns ~rows ~size () =
  protected "grid" "invalid_parameter" (fun () ->
    grid_raw ?cancel ?grain ?counts ?connectivity ?orientation ?center ?width
      ?height ?rotation ?uv_attribute ~columns ~rows ~size ())

let box_raw = box
let box ?cancel ?grain ?connectivity ?consolidate_points ?normals ?center
    ?rotation ?rotation_order ?uniform_scale ?x_divisions ?y_divisions
    ?z_divisions ?uv_attribute ?face_groups ~size () =
  protected "box" "invalid_parameter" (fun () ->
    box_raw ?cancel ?grain ?connectivity ?consolidate_points ?normals ?center
      ?rotation ?rotation_order ?uniform_scale ?x_divisions ?y_divisions
      ?z_divisions ?uv_attribute ?face_groups ~size ())

let uv_sphere_raw = uv_sphere
let uv_sphere ?cancel ?grain ?connectivity ?unique_points_per_pole
    ?triangular_poles ?normals ?orientation ?center ?rotation ?rotation_order
    ?uniform_scale ?radius_x ?radius_y ?radius_z ?uv_attribute ?segments ?rings
    ~radius () =
  protected "uv_sphere" "invalid_parameter" (fun () ->
    uv_sphere_raw ?cancel ?grain ?connectivity ?unique_points_per_pole
      ?triangular_poles ?normals ?orientation ?center ?rotation ?rotation_order
      ?uniform_scale ?radius_x ?radius_y ?radius_z ?uv_attribute ?segments
      ?rings ~radius ())

let torus_raw = torus
let torus ?cancel ?grain ?connectivity ?normals ?orientation ?center ?rotation
    ?rotation_order ?uniform_scale ?u_start ?u_end ?v_start ?v_end ?u_wrap
    ?v_wrap ?u_end_caps ?v_end_cap ?uv_attribute ?rows ?columns ~major_radius
    ~minor_radius () =
  protected "torus" "invalid_parameter" (fun () ->
    torus_raw ?cancel ?grain ?connectivity ?normals ?orientation ?center
      ?rotation ?rotation_order ?uniform_scale ?u_start ?u_end ?v_start ?v_end
      ?u_wrap ?v_wrap ?u_end_caps ?v_end_cap ?uv_attribute ?rows ?columns
      ~major_radius ~minor_radius ())

let tube_raw = tube
let tube ?cancel ?grain ?connectivity ?end_caps ?consolidate_cap_points
    ?normals ?orientation ?center ?rotation ?rotation_order ?radius_scale
    ?uv_attribute ?cap_group ?rows ?columns ~top_radius ~bottom_radius ~height
    () =
  protected "tube" "invalid_parameter" (fun () ->
    tube_raw ?cancel ?grain ?connectivity ?end_caps ?consolidate_cap_points
      ?normals ?orientation ?center ?rotation ?rotation_order ?radius_scale
      ?uv_attribute ?cap_group ?rows ?columns ~top_radius ~bottom_radius
      ~height ())

let platonic_raw = platonic
let platonic ?cancel ?kind ?normals ?orientation ?center ?rotation
    ?rotation_order ?face_groups ~radius () =
  protected "platonic" "invalid_parameter" (fun () ->
    platonic_raw ?cancel ?kind ?normals ?orientation ?center ?rotation
      ?rotation_order ?face_groups ~radius ())

let spiral_raw = spiral
let spiral ?cancel ?grain ?extent ?radius ?height_ramp ?radius_scale
    ?radius_ramp ?direction ?start_angle ?divisions ?uniform_angle
    ?spiral_count ?orientation ?center ?rotation ?rotation_order ?uniform_scale
    ?angle_attribute ?x_axis_attribute ?y_axis_attribute ?tangent_attribute
    ?orient_attribute ?distance_attribute () =
  protected "spiral" "invalid_parameter" (fun () ->
    spiral_raw ?cancel ?grain ?extent ?radius ?height_ramp ?radius_scale
      ?radius_ramp ?direction ?start_angle ?divisions ?uniform_angle
      ?spiral_count ?orientation ?center ?rotation ?rotation_order ?uniform_scale
      ?angle_attribute ?x_axis_attribute ?y_axis_attribute ?tangent_attribute
      ?orient_attribute ?distance_attribute ())

let merge_raw = merge
let merge ?cancel ?grain geometries = protected "merge" "schema_mismatch"
    (fun () -> merge_raw ?cancel ?grain geometries)

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

let edge_collapse_raw = edge_collapse
let edge_collapse ?cancel ?grain ?edges ?connectivity_attribute ?position
    ?remove_degenerate_primitives ?recompute_point_normals geometry =
  protected "edge_collapse" "invalid_topology" (fun () ->
    edge_collapse_raw ?cancel ?grain ?edges ?connectivity_attribute ?position
      ?remove_degenerate_primitives ?recompute_point_normals geometry)

let dissolve_raw = dissolve
let dissolve ?cancel ?grain ?edges ?operation ?bridge_policy
    ?remove_inline_points ?collinearity_tolerance ?remove_unused_points
    ?create_boundary_curves ?recompute_normals geometry =
  protected "dissolve" "invalid_topology" (fun () ->
    dissolve_raw ?cancel ?grain ?edges ?operation ?bridge_policy
      ?remove_inline_points ?collinearity_tolerance ?remove_unused_points
      ?create_boundary_curves ?recompute_normals geometry)

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

let triangulate_raw = triangulate
let triangulate ?cancel ?grain ?primitives geometry =
  protected "triangulate" "invalid_topology"
    (fun () -> triangulate_raw ?cancel ?grain ?primitives geometry)

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
    ?preserve_point_payload ?keep_primitives ?(remove_unused_points = false)
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
      ?preserve_point_payload ?keep_primitives ?split_point_group ?triangle_group
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
      triangulate = (fun geometry -> triangulate_raw ?cancel ~grain geometry);
      collapse = (fun edges geometry ->
        edge_collapse_raw ?cancel ~grain ~edges ~position:Average_position
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
  protected "blend_shapes" "invalid_blend_shapes" (fun () ->
    Blend_shapes.run ?cancel ?grain ?points ?mode ?masking ?mask_attribute
      ?point_id_attribute ?attributes ~shapes geometry)

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
  protected "attribute_composite" "invalid_attribute_composite" (fun () ->
    Attribute_composite.run ?cancel ?grain ?operation ?weight
      ?detail_attributes ?primitive_attributes ?point_attributes
      ?vertex_attributes ?allow_position ?alpha_attribute ~inputs geometry)

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
  protected "attribute_mirror" "invalid_attribute_mirror" (fun () ->
    Attribute_mirror.run ?cancel ?grain ?group ?group_use ?attributes ?transform
      ?string_replace ?output_mapping ?source_group ?destination_group ~owner
      ~method_ geometry)

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

let reverse_raw = reverse
let reverse ?cancel ?grain ?primitives ?operation geometry =
  protected "reverse" "invalid_topology"
    (fun () -> reverse_raw ?cancel ?grain ?primitives ?operation geometry)

let mirror_raw = mirror
let mirror ?cancel ?grain ?keep_original ~origin ~normal geometry =
  protected "mirror" "invalid_parameter" (fun () ->
    mirror_raw ?cancel ?grain ?keep_original ~origin ~normal geometry)

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
  protected "attribute_fade" "invalid_attribute_fade" (fun () ->
    Attribute_fade.fade ?cancel ?grain ?points ?start_source ?hold_source
      ?fade_attribute ?start_attribute ?start_retime ?hold_scale_attribute
      ~frame ?frame_offset ?fade_in ?fade_hold ?fade_out ?fade_in_ramp
      ?fade_out_ramp ?visualize geometry)

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

let normals_raw = normals
let normals ?cancel ?grain ?selection ?owner ?weighting ?cusp_angle
    ?keep_original_zero ?reverse ?attribute geometry =
  protected "normals" "invalid_topology"
    (fun () -> normals_raw ?cancel ?grain ?selection ?owner ?weighting
      ?cusp_angle ?keep_original_zero ?reverse ?attribute geometry)

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

let delete_primitives ?cancel ?grain ?selected ?(compact_points = false)
    group geometry =
  if Group.owner group <> Group.Primitive then
    detailed "delete_primitives" "invalid_selection"
      (Error "selection must own primitives")
  else protected "delete_primitives" "invalid_selection" (fun () ->
    Deletion.delete ?cancel ?grain ?selected ~compact_points group geometry)

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

let sort ?cancel ?grain ?selection ?descending ?output_indices ?combine_indices
    ~owner ~key geometry =
  protected "sort" "invalid_sort" (fun () ->
    Ordering.sort ?cancel ?grain ?selection ?descending ?output_indices
      ?combine_indices ~owner ~key geometry)

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

let copy_to_points_raw = copy_to_points
let copy_to_points ?cancel ?grain ?source_primitives ?target_points
    ?piece_attribute ?target_attributes ~source ~targets () =
  let selection_error = match source_primitives, target_points with
    | Some group, _ when Group.owner group <> Group.Primitive ->
        Some "source selection must own primitives"
    | Some group, _ when Group.length group <> Geometry.primitive_count source ->
        Some "source selection length does not match source primitive count"
    | _, Some group when Group.owner group <> Group.Point ->
        Some "target selection must own points"
    | _, Some group when Group.length group <> Geometry.point_count targets ->
        Some "target selection length does not match target point count"
    | _ -> None in
  match selection_error with
  | Some message -> detailed "copy_to_points" "invalid_selection" (Error message)
  | None -> protected "copy_to_points" "invalid_attribute"
      (fun () -> copy_to_points_raw ?cancel ?grain ?source_primitives
        ?target_points ?piece_attribute ?target_attributes ~source ~targets ())

let materialize_instances_raw = materialize_instances
let materialize_instances ?cancel ?grain ?apply_transform ~transforms geometry =
  protected "materialize_instances" "invalid_parameter" (fun () ->
    materialize_instances_raw ?cancel ?grain ?apply_transform ~transforms geometry)

let duplicate_raw = duplicate
let duplicate ?cancel ?grain ?copies ?cumulative ?transform ?primitives
    ?copy_group_prefix ?preserve_groups geometry =
  protected "duplicate" "invalid_parameter" (fun () ->
    duplicate_raw ?cancel ?grain ?copies ?cumulative ?transform ?primitives
      ?copy_group_prefix ?preserve_groups geometry)

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

let point_generate_raw = point_generate
let point_generate ?cancel ?grain ?points ?keep_input ?seed ?generated_group
    ?source_point_attribute ?source_index_attribute ?copy_point_attributes
    ?copy_detail_attributes ~mode geometry =
  protected "point_generate" "invalid_geometry" (fun () ->
    point_generate_raw ?cancel ?grain ?points ?keep_input ?seed
      ?generated_group ?source_point_attribute ?source_index_attribute
      ?copy_point_attributes ?copy_detail_attributes ~mode geometry)

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

let color_by_height_raw = color_by_height
let color_by_height ?cancel ?grain ~low ~high geometry =
  protected "color_by_height" "invalid_geometry"
    (fun () -> color_by_height_raw ?cancel ?grain ~low ~high geometry)

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

let poly_extrude_raw = poly_extrude
let poly_extrude ?cancel ?grain ?primitives ?split_edges ?divide ?divisions
    ?output_front ?output_back ?output_side ?front_group ?back_group ?side_group
    ?front_boundary_group ?back_boundary_group ~distance geometry =
  protected "poly_extrude" "invalid_geometry"
    (fun () -> poly_extrude_raw ?cancel ?grain ?primitives ?split_edges ?divide
      ?divisions ?output_front ?output_back ?output_side ?front_group ?back_group
      ?side_group ?front_boundary_group ?back_boundary_group ~distance geometry)

let poly_fill_raw = poly_fill
let poly_fill ?cancel ?grain ?boundary ?mode ?reverse_patches ?unique_points
    ?update_point_normals ?patch_group geometry =
  protected "poly_fill" "invalid_geometry"
    (fun () -> poly_fill_raw ?cancel ?grain ?boundary ?mode ?reverse_patches
      ?unique_points ?update_point_normals ?patch_group geometry)

let resample_curves_raw = resample_curves
let resample_curves ?cancel ?grain ?primitives ?segments ?maximum_segment_length
    ?segment_length_attribute ?segments_attribute ?even_last_segment
    ?curve_u_attribute ?curve_number_attribute ?distance_attribute
    ?tangent_attribute geometry =
  protected "resample_curves" "invalid_geometry"
    (fun () -> resample_curves_raw ?cancel ?grain ?primitives ?segments
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

let revolve_raw = revolve
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

let sweep_circle_raw = sweep_circle
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
  protected "groups_from_name" "invalid_group" (fun () ->
    Group_ops.groups_from_name ?cancel ?grain ?prefix ?conflict ?invalid_names
      ?max_groups ?max_payload_bytes ~owner ~attribute geometry)

let name_from_groups ?cancel ?grain ?attribute ?pattern ?default ?overlap
    ?delete_groups ~owner geometry =
  protected "name_from_groups" "invalid_group" (fun () ->
    Group_ops.name_from_groups ?cancel ?grain ?attribute ?pattern ?default
      ?overlap ?delete_groups ~owner geometry)

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
  protected "group_promote" "invalid_group" (fun () ->
    Group_ops.promote ?cancel ?grain ?name ?keep_original ?output_attribute
      ?mode ~source ~destination ~group geometry)

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
  protected "group_promotions" "invalid_group" (fun () ->
    Group_ops.promotions ?cancel ?grain ?max_outputs ?max_payload_bytes
      rules geometry)

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
  protected "group_expand" "invalid_group" (fun () ->
    Group_ops.expand ?cancel ?grain ?name ?steps ?flood ?step_attribute
      ?primitive_connectivity ?normal_spread ?normal_attribute
      ?connectivity_attributes ?connectivity_tolerance ?collision
      ~owner ~group geometry)

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
