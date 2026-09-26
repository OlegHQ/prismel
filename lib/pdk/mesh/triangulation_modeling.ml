open Prismel_math

type deform_selection = Deform.selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t

let protected operation code work = Error.guard ~operation ~code work

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
      Result.bind (if remove_unused_points then Compact_points.run ?cancel
          ?grain output else Ok output) (fun output ->
        if recompute_point_normals
            && Option.is_some (Geometry.find_attribute
              ~owner:Attribute.Point "N" geometry) then
          Normal_ops.run ?cancel ?grain ~owner:Attribute.Point ~attribute:"N" output
        else Ok output)))

let remesh ?cancel ?(grain = 16_384) ?iterations ?smoothing ?project
    ?use_input_points_only ?hard_points ?hard_edges ?target_size_attribute
    ?preserve_uv_seams ?uv_attribute ?output_hard_edges ?output_mesh_size
    ?output_quality ?recompute_point_normals ~target_length geometry =
  protected "remesh" "invalid_remesh" (fun () ->
    let kernels : Remesh.kernels = {
      triangulate = (fun geometry -> Triangulate.run ?cancel ~grain geometry);
      collapse = (fun edges geometry ->
        Edge_collapse.raw ?cancel ~grain ~edges ~position:Fuse_reduce.Average_position
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

