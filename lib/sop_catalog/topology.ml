open Rays_math
open Procedural
open Shared


module Crease = struct
  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Add", Rdk.Crease.Crease_add;
      "Set", Rdk.Crease.Crease_set;
      "Delete", Rdk.Crease.Crease_delete;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    operation : Rdk.Crease.operation [@sop.default Rdk.Crease.Crease_add]
      [@sop.label "Operation"] [@sop.kind operation_parameter];
    weight : float [@sop.default 1.] [@sop.label "Weight"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
    add_vertex_color : bool [@sop.default false]
      [@sop.label "Visualize with vertex color"];
  } [@@sop.node_key "crease"] [@@sop.node_label "Crease"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.crease ~label ?group:(optional_text parameters.group)
      ~operation:parameters.operation ~weight:parameters.weight
      ~add_vertex_color:parameters.add_vertex_color input)

  let factory = parameters_factory build
end

module Subdivide = struct
  type crack_mode =
    | Do_not_close
    | Pull_no_division
    | Pull_divide
    | Pull_triangulate
    | Stitch_no_division
    | Stitch_divide
    | Stitch_triangulate

  let scheme_parameter = Parameter.choice ~equal:( = ) [
      "Catmull-Clark", Rdk.Subdivide.Catmull_clark;
      "Loop", Rdk.Subdivide.Loop;
      "Bilinear", Rdk.Subdivide.Bilinear;
    ]

  let cracks_parameter = Parameter.choice ~equal:( = ) [
      "Do not close", Do_not_close;
      "Pull, no edge division", Pull_no_division;
      "Pull, divide edges", Pull_divide;
      "Pull, triangulate", Pull_triangulate;
      "Stitch, no edge division", Stitch_no_division;
      "Stitch, divide edges", Stitch_divide;
      "Stitch, triangulate", Stitch_triangulate;
    ]

  let boundary_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Subdivide.Subdivide_boundary_none;
      "Edge only", Rdk.Subdivide.Subdivide_boundary_edge_only;
      "Edge and corner", Rdk.Subdivide.Subdivide_boundary_edge_and_corner;
    ]

  let fvar_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Subdivide.Subdivide_fvar_none;
      "Corners only", Rdk.Subdivide.Subdivide_fvar_corners_only;
      "Corners plus 1", Rdk.Subdivide.Subdivide_fvar_corners_plus1;
      "Corners plus 2", Rdk.Subdivide.Subdivide_fvar_corners_plus2;
      "Boundaries", Rdk.Subdivide.Subdivide_fvar_boundaries;
      "All", Rdk.Subdivide.Subdivide_fvar_all;
    ]

  let triangle_parameter = Parameter.choice ~equal:( = ) [
      "Catmull-Clark", Rdk.Subdivide.Subdivide_triangles_catmull_clark;
      "Smooth", Rdk.Subdivide.Subdivide_triangles_smooth;
    ]

  let creasing_parameter = Parameter.choice ~equal:( = ) [
      "Uniform", Rdk.Subdivide.Subdivide_creasing_uniform;
      "Chaikin", Rdk.Subdivide.Subdivide_creasing_chaikin;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    scheme : Rdk.Subdivide.scheme
      [@sop.default Rdk.Subdivide.Catmull_clark]
      [@sop.label "Scheme"] [@sop.kind scheme_parameter];
    iterations : int [@sop.default 1] [@sop.label "Depth"]
      [@sop.min 1] [@sop.max 6] [@sop.hard_min 1];
    cracks : crack_mode [@sop.default Do_not_close]
      [@sop.label "Close cracks"] [@sop.kind cracks_parameter];
    crack_bias : float [@sop.default 0.5] [@sop.label "Pull bias"]
      [@sop.folder "Cracks"] [@sop.min 0.] [@sop.max 1.];
    consistent_topology : bool [@sop.default false]
      [@sop.label "Consistent topology"] [@sop.folder "Cracks"];
    crease_group : string [@sop.default ""] [@sop.label "Crease group"]
      [@sop.folder "Creases"];
    crease_weight : float [@sop.default 1.] [@sop.label "Crease weight"]
      [@sop.folder "Creases"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    generate_resulting_creases : bool [@sop.default false]
      [@sop.label "Generate resulting creases"] [@sop.folder "Creases"];
    resulting_crease_group : string [@sop.default ""]
      [@sop.label "Resulting crease group"] [@sop.folder "Creases"];
    hole_group : string [@sop.default "subdivision_hole"]
      [@sop.label "Hole group"] [@sop.folder "Holes"];
    remove_holes : bool [@sop.default false] [@sop.label "Remove holes"]
      [@sop.folder "Holes"];
    boundary_interpolation : Rdk.Subdivide.boundary_interpolation
      [@sop.default Rdk.Subdivide.Subdivide_boundary_edge_and_corner]
      [@sop.label "Point boundaries"] [@sop.folder "Interpolation"]
      [@sop.kind boundary_parameter];
    face_varying_interpolation :
      Rdk.Subdivide.face_varying_interpolation
      [@sop.default Rdk.Subdivide.Subdivide_fvar_boundaries]
      [@sop.label "Vertex boundaries"] [@sop.folder "Interpolation"]
      [@sop.kind fvar_parameter];
    triangle_policy : Rdk.Subdivide.triangle_policy
      [@sop.default Rdk.Subdivide.Subdivide_triangles_catmull_clark]
      [@sop.label "Triangles"] [@sop.folder "Interpolation"]
      [@sop.kind triangle_parameter];
    creasing_method : Rdk.Subdivide.creasing_method
      [@sop.default Rdk.Subdivide.Subdivide_creasing_uniform]
      [@sop.label "Creasing method"] [@sop.folder "Creases"]
      [@sop.kind creasing_parameter];
    treat_curves_as_independent : bool [@sop.default false]
      [@sop.label "Treat curves independently"];
    recompute_point_normals : bool [@sop.default false]
      [@sop.label "Recompute point normals"];
  } [@@sop.node_key "subdivide"] [@@sop.node_label "Subdivide"]
    [@@sop.node_category "Topology"] [@@sop.node_inputs 2] [@@sop.node_slots "input, creases"]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let cracks parameters = match parameters.cracks with
    | Do_not_close -> Rdk.Subdivide.Subdivide_do_not_close
    | Pull_no_division -> Rdk.Subdivide.Subdivide_pull_no_edge_division
    | Pull_divide -> Rdk.Subdivide.Subdivide_pull_divide_edges parameters.crack_bias
    | Pull_triangulate ->
        Rdk.Subdivide.Subdivide_pull_triangulate parameters.crack_bias
    | Stitch_no_division -> Rdk.Subdivide.Subdivide_stitch_no_edge_division
    | Stitch_divide -> Rdk.Subdivide.Subdivide_stitch_divide_edges
    | Stitch_triangulate -> Rdk.Subdivide.Subdivide_stitch_triangulate

  let build = parameters_build (fun ~label parameters input creases ->
    Sop.subdivide ~label ?group:(optional_text parameters.group)
      ~scheme:parameters.scheme ~iterations:parameters.iterations
      ~cracks:(cracks parameters)
      ~consistent_topology:parameters.consistent_topology ?creases
      ?crease_group:(optional_text parameters.crease_group)
      ~crease_weight:parameters.crease_weight
      ~generate_resulting_creases:parameters.generate_resulting_creases
      ?resulting_crease_group:(optional_text
        parameters.resulting_crease_group)
      ?hole_group:(optional_text parameters.hole_group)
      ~remove_holes:parameters.remove_holes
      ~boundary_interpolation:parameters.boundary_interpolation
      ~face_varying_interpolation:parameters.face_varying_interpolation
      ~triangle_policy:parameters.triangle_policy
      ~creasing_method:parameters.creasing_method
      ~treat_curves_as_independent:parameters.treat_curves_as_independent
      ~recompute_point_normals:parameters.recompute_point_normals input)

  let factory = parameters_factory build
end

module Edge_divide = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    divisions : int [@sop.default 2] [@sop.label "Divisions"]
      [@sop.min 1] [@sop.max 64] [@sop.hard_min 1];
    share_points : bool [@sop.default true] [@sop.label "Share points"];
  } [@@sop.node_key "edge_divide"] [@@sop.node_label "Edge Divide"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.edge_divide ~label ?group:(optional_text parameters.group)
      ~divisions:parameters.divisions ~share_points:parameters.share_points
      input)

  let factory = parameters_factory build
end

module Edge_collapse = struct
  let position_parameter = Parameter.choice ~equal:( = ) [
      "First", Rdk.Fuse_reduce.First_position;
      "Least point", Rdk.Fuse_reduce.Least_point_position;
      "Greatest point", Rdk.Fuse_reduce.Greatest_point_position;
      "Average", Rdk.Fuse_reduce.Average_position;
      "Minimum", Rdk.Fuse_reduce.Minimum_position;
      "Maximum", Rdk.Fuse_reduce.Maximum_position;
      "Mode", Rdk.Fuse_reduce.Mode_position;
      "Median", Rdk.Fuse_reduce.Median_position;
      "Sum", Rdk.Fuse_reduce.Sum_position;
      "Sum squares", Rdk.Fuse_reduce.Sum_squares_position;
      "Root mean square", Rdk.Fuse_reduce.Root_mean_square_position;
      "Weighted average", Rdk.Fuse_reduce.Weighted_average_position;
      "Weighted sum", Rdk.Fuse_reduce.Weighted_sum_position;
      "Minimum weight", Rdk.Fuse_reduce.Minimum_weight_position;
      "Maximum weight", Rdk.Fuse_reduce.Maximum_weight_position;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    connectivity_attribute : string [@sop.default ""]
      [@sop.label "Connectivity attribute"];
    position : Rdk.Fuse_reduce.position
      [@sop.default Rdk.Fuse_reduce.Average_position]
      [@sop.label "Position"] [@sop.kind position_parameter];
    remove_degenerate_primitives : bool [@sop.default true]
      [@sop.label "Remove degenerate primitives"] [@sop.folder "Cleanup"];
    recompute_point_normals : bool [@sop.default true]
      [@sop.label "Recompute point normals"] [@sop.folder "Cleanup"];
  } [@@sop.node_key "edge_collapse"] [@@sop.node_label "Edge Collapse"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.edge_collapse ~label ?group:(optional_text parameters.group)
      ?connectivity_attribute:(optional_text
        parameters.connectivity_attribute)
      ~position:parameters.position
      ~remove_degenerate_primitives:parameters.remove_degenerate_primitives
      ~recompute_point_normals:parameters.recompute_point_normals input)

  let factory = parameters_factory build
end

module Dissolve = struct
  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Selected", Rdk.Dissolve.Dissolve_selected;
      "Non-selected", Rdk.Dissolve.Dissolve_non_selected;
    ]

  let bridge_parameter = Parameter.choice ~equal:( = ) [
      "Create bridged polygons", Rdk.Dissolve.Create_bridged_polygons;
      "Create disjoint polygons", Rdk.Dissolve.Create_disjoint_polygons;
      "Delete bridge polygons", Rdk.Dissolve.Delete_bridge_polygons;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    operation : Rdk.Dissolve.operation
      [@sop.default Rdk.Dissolve.Dissolve_selected]
      [@sop.label "Operation"] [@sop.kind operation_parameter];
    bridge_policy : Rdk.Dissolve.bridge_policy
      [@sop.default Rdk.Dissolve.Create_bridged_polygons]
      [@sop.label "Bridge loops"] [@sop.kind bridge_parameter];
    remove_inline_points : bool [@sop.default true]
      [@sop.label "Remove inline points"] [@sop.folder "Cleanup"];
    collinearity_tolerance : float [@sop.default 1e-6]
      [@sop.label "Collinearity tolerance"] [@sop.folder "Cleanup"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.];
    remove_unused_points : bool [@sop.default true]
      [@sop.label "Remove unused points"] [@sop.folder "Cleanup"];
    create_boundary_curves : bool [@sop.default false]
      [@sop.label "Create boundary curves"];
    recompute_normals : bool [@sop.default true]
      [@sop.label "Recompute normals"] [@sop.folder "Cleanup"];
  } [@@sop.node_key "dissolve"] [@@sop.node_label "Dissolve"]
    [@@sop.node_category "Topology"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.dissolve ~label ?group:(optional_text parameters.group)
      ~operation:parameters.operation ~bridge_policy:parameters.bridge_policy
      ~remove_inline_points:parameters.remove_inline_points
      ~collinearity_tolerance:parameters.collinearity_tolerance
      ~remove_unused_points:parameters.remove_unused_points
      ~create_boundary_curves:parameters.create_boundary_curves
      ~recompute_normals:parameters.recompute_normals input)

  let factory = parameters_factory build
end

module Poly_bevel = struct
  type shape = Chamfer | Round

  let shape_parameter = Parameter.choice ~equal:( = ) [
      "Chamfer", Chamfer; "Round", Round;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    shape : shape [@sop.default Chamfer] [@sop.label "Shape"]
      [@sop.kind shape_parameter];
    convexity : float [@sop.default 0.5] [@sop.label "Convexity"]
      [@sop.folder "Round"] [@sop.min 0.] [@sop.max 1.];
    distance : float [@sop.default 0.1] [@sop.label "Distance"]
      [@sop.min 0.] [@sop.max 2.] [@sop.hard_min 0.];
    divisions : int [@sop.default 1] [@sop.label "Divisions"]
      [@sop.min 1] [@sop.max 32] [@sop.hard_min 1];
    point_scale_attribute : string [@sop.default ""]
      [@sop.label "Point scale attribute"] [@sop.folder "Attributes"];
    ignore_flat_angle : float [@sop.default 0.]
      [@sop.label "Ignore flat angle (0: bevel every edge)"] [@sop.folder "Robustness"]
      [@sop.min 0.] [@sop.max 3.14159] [@sop.hard_min 0.];
    clamp_overlap : bool [@sop.default true]
      [@sop.label "Clamp overlap"] [@sop.folder "Robustness"];
    edge_group : string [@sop.default ""] [@sop.label "Edge group"]
      [@sop.folder "Output groups"];
    corner_group : string [@sop.default ""] [@sop.label "Corner group"]
      [@sop.folder "Output groups"];
    offset_group : string [@sop.default ""] [@sop.label "Offset group"]
      [@sop.folder "Output groups"];
    recompute_point_normals : bool [@sop.default true]
      [@sop.label "Recompute point normals"];
  } [@@sop.node_key "poly_bevel"] [@@sop.node_label "Poly Bevel"]
    [@@sop.node_category "Topology/Polygon"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let shape = match parameters.shape with
      | Chamfer -> Rdk.Poly_bevel.Bevel_chamfer
      | Round -> Rdk.Poly_bevel.Bevel_round { convexity = parameters.convexity } in
    Sop.poly_bevel ~label ?group:(optional_text parameters.group) ~shape
      ~divisions:parameters.divisions
      ?point_scale_attribute:(optional_text parameters.point_scale_attribute)
      ?ignore_flat_angle:(if parameters.ignore_flat_angle > 0.
                          then Some parameters.ignore_flat_angle else None)
      ~clamp_overlap:parameters.clamp_overlap
      ?edge_group:(optional_text parameters.edge_group)
      ?corner_group:(optional_text parameters.corner_group)
      ?offset_group:(optional_text parameters.offset_group)
      ~recompute_point_normals:parameters.recompute_point_normals
      ~distance:parameters.distance input)

  let factory = parameters_factory build

  let create ?label:node_label ?(shape = parameters_default.shape)
      ?(divisions = parameters_default.divisions) ~distance input =
    build ~label:(label "poly-bevel" node_label) ~inputs:[input]
      { parameters_default with shape; divisions; distance }
end

module Triangulate = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
  } [@@sop.node_key "triangulate"] [@@sop.node_label "Triangulate"]
    [@@sop.node_category "Topology"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.triangulate ~label ?group:(optional_text parameters.group) input)

  let factory = parameters_factory build

end

module Reverse = struct
  type operation = Reverse | Shift
  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Reverse vertices", Reverse; "Shift vertices", Shift;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    operation : operation [@sop.default Reverse] [@sop.label "Operation"]
      [@sop.kind operation_parameter];
    shift : int [@sop.default 1] [@sop.label "Shift"]
      [@sop.min (-32)] [@sop.max 32];
  } [@@sop.node_key "reverse"] [@@sop.node_label "Reverse"]
    [@@sop.node_category "Topology"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let operation = match parameters.operation with
      | Reverse -> Rdk.Reverse_faces.Reverse_vertices
      | Shift -> Rdk.Reverse_faces.Shift_vertices parameters.shift in
    Sop.reverse ~label ?group:(optional_text parameters.group) ~operation input)

  let factory = parameters_factory build
end

module Clean = struct
  let overlaps_parameter = Parameter.choice ~equal:( = ) [
      "Keep first", Rdk.Clean.Keep_first_overlap;
      "Delete pairs", Rdk.Clean.Delete_overlap_pairs;
    ]

  type parameters = {
    epsilon : float [@sop.default 1e-9] [@sop.label "Epsilon"]
      [@sop.folder "Robustness"] [@sop.min 0.] [@sop.max 0.001]
      [@sop.hard_min 0.];
    remove_degenerate : bool [@sop.default true]
      [@sop.label "Remove degenerate primitives"];
    consolidate_distance : float [@sop.default 0.]
      [@sop.label "Consolidate distance"] [@sop.min 0.] [@sop.max 0.1]
      [@sop.hard_min 0.];
    overlaps : Rdk.Clean.overlap_policy
      [@sop.default Rdk.Clean.Keep_first_overlap]
      [@sop.label "Overlaps"] [@sop.kind overlaps_parameter];
    reverse_winding : bool [@sop.default false]
      [@sop.label "Reverse winding"];
    remove_nan_points : bool [@sop.default true]
      [@sop.label "Remove non-finite points"];
    remove_unused_points : bool [@sop.default true]
      [@sop.label "Remove unused points"];
    delete_unused_groups : bool [@sop.default true]
      [@sop.label "Delete unused groups"];
    point_attributes : string [@sop.default ""]
      [@sop.label "Point attributes"] [@sop.folder "Delete attributes"];
    vertex_attributes : string [@sop.default ""]
      [@sop.label "Vertex attributes"] [@sop.folder "Delete attributes"];
    primitive_attributes : string [@sop.default ""]
      [@sop.label "Primitive attributes"] [@sop.folder "Delete attributes"];
    detail_attributes : string [@sop.default ""]
      [@sop.label "Detail attributes"] [@sop.folder "Delete attributes"];
    point_groups : string [@sop.default ""] [@sop.label "Point groups"]
      [@sop.folder "Delete groups"];
    vertex_groups : string [@sop.default ""] [@sop.label "Vertex groups"]
      [@sop.folder "Delete groups"];
    primitive_groups : string [@sop.default ""] [@sop.label "Primitive groups"]
      [@sop.folder "Delete groups"];
    edge_groups : string [@sop.default ""] [@sop.label "Edge groups"]
      [@sop.folder "Delete groups"];
  } [@@sop.node_key "clean"] [@@sop.node_label "Clean"]
    [@@sop.node_category "Topology/Cleanup"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.clean ~label ~epsilon:parameters.epsilon
      ~remove_degenerate:parameters.remove_degenerate
      ~consolidate_distance:parameters.consolidate_distance
      ~overlaps:parameters.overlaps ~reverse_winding:parameters.reverse_winding
      ~remove_nan_points:parameters.remove_nan_points
      ~remove_unused_points:parameters.remove_unused_points
      ~delete_unused_groups:parameters.delete_unused_groups
      ?point_attributes:(optional_text parameters.point_attributes)
      ?vertex_attributes:(optional_text parameters.vertex_attributes)
      ?primitive_attributes:(optional_text parameters.primitive_attributes)
      ?detail_attributes:(optional_text parameters.detail_attributes)
      ?point_groups:(optional_text parameters.point_groups)
      ?vertex_groups:(optional_text parameters.vertex_groups)
      ?primitive_groups:(optional_text parameters.primitive_groups)
      ?edge_groups:(optional_text parameters.edge_groups) input)

  let factory = parameters_factory build
end

module Facet = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    pre_compute_normals : bool [@sop.default false]
      [@sop.label "Pre-compute normals"] [@sop.folder "Normals"];
    make_normals_unit_length : bool [@sop.default false]
      [@sop.label "Make normals unit length"] [@sop.folder "Normals"];
    unique_points : bool [@sop.default false] [@sop.label "Unique points"];
    consolidate_distance : float [@sop.default 0.]
      [@sop.label "Consolidate distance"] [@sop.folder "Consolidate"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.];
    consolidate_normals_distance : float [@sop.default 0.]
      [@sop.label "Normal distance"] [@sop.folder "Consolidate"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.];
    remove_inline_points : bool [@sop.default false]
      [@sop.label "Remove inline points"];
    inline_distance : float [@sop.default 1e-6]
      [@sop.label "Inline distance"] [@sop.min 0.] [@sop.max 0.1]
      [@sop.hard_min 0.];
    orient_polygons : bool [@sop.default false]
      [@sop.label "Orient polygons"];
    cusp_angle : float [@sop.default 3.141592653589793]
      [@sop.label "Cusp angle"] [@sop.folder "Normals"]
      [@sop.min 0.] [@sop.max 3.141592653589793]
      [@sop.hard_min 0.] [@sop.hard_max 3.141592653589793];
    remove_degenerate : bool [@sop.default false]
      [@sop.label "Remove degenerate primitives"];
    make_planar : bool [@sop.default false] [@sop.label "Make planar"];
    post_compute_normals : bool [@sop.default false]
      [@sop.label "Post-compute normals"] [@sop.folder "Normals"];
    reverse_normals : bool [@sop.default false]
      [@sop.label "Reverse normals"] [@sop.folder "Normals"];
  } [@@sop.node_key "facet"] [@@sop.node_label "Facet"]
    [@@sop.node_category "Topology/Cleanup"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.facet ~label ?group:(optional_text parameters.group)
      ~pre_compute_normals:parameters.pre_compute_normals
      ~make_normals_unit_length:parameters.make_normals_unit_length
      ~unique_points:parameters.unique_points
      ~consolidate_distance:parameters.consolidate_distance
      ~consolidate_normals_distance:parameters.consolidate_normals_distance
      ~remove_inline_points:parameters.remove_inline_points
      ~inline_distance:parameters.inline_distance
      ~orient_polygons:parameters.orient_polygons
      ~cusp_angle:parameters.cusp_angle
      ~remove_degenerate:parameters.remove_degenerate
      ~make_planar:parameters.make_planar
      ~post_compute_normals:parameters.post_compute_normals
      ~reverse_normals:parameters.reverse_normals input)

  let factory = parameters_factory build
end

module Edge_flip = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    cycles : int [@sop.default 1] [@sop.label "Cycles"]
      [@sop.min 0] [@sop.max 16] [@sop.hard_min 0];
    cycle_vertex_attributes : bool [@sop.default true]
      [@sop.label "Cycle vertex attributes"];
    recompute_point_normals : bool [@sop.default false]
      [@sop.label "Recompute point normals"];
  } [@@sop.node_key "edge_flip"] [@@sop.node_label "Edge Flip"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.edge_flip ~label ?group:(optional_text parameters.group)
      ~cycles:parameters.cycles
      ~cycle_vertex_attributes:parameters.cycle_vertex_attributes
      ~recompute_point_normals:parameters.recompute_point_normals input)

  let factory = parameters_factory build
end

module Edge_cusp = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    update_point_normals : bool [@sop.default true]
      [@sop.label "Update point normals"];
  } [@@sop.node_key "edge_cusp"] [@@sop.node_label "Edge Cusp"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.edge_cusp ~label ?group:(optional_text parameters.group)
      ~update_point_normals:parameters.update_point_normals input)

  let factory = parameters_factory build
end

module Edge_straighten = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    output_group : string [@sop.default ""] [@sop.label "Output group"];
  } [@@sop.node_key "edge_straighten"] [@@sop.node_label "Edge Straighten"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.edge_straighten ~label ?group:(optional_text parameters.group)
      ?output_group:(optional_text parameters.output_group) input)

  let factory = parameters_factory build
end

module Circle_from_edges = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    use_radius : bool [@sop.default false] [@sop.label "Override radius"];
    radius : float [@sop.default 1.] [@sop.label "Radius"]
      [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.];
    scale_x : float [@sop.default 1.] [@sop.label "Scale X"]
      [@sop.folder "Scale"] [@sop.min (-4.)] [@sop.max 4.]; [@sop.vec3 "scale"]
    scale_y : float [@sop.default 1.] [@sop.label "Scale Y"]
      [@sop.folder "Scale"] [@sop.min (-4.)] [@sop.max 4.]; [@sop.vec3 "scale"]
    scale_z : float [@sop.default 1.] [@sop.label "Scale Z"]
      [@sop.folder "Scale"] [@sop.min (-4.)] [@sop.max 4.]; [@sop.vec3 "scale"]
    output_group : string [@sop.default ""] [@sop.label "Output group"];
  } [@@sop.node_key "circle_from_edges"]
    [@@sop.node_label "Circle from Edges"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let radius = if parameters.use_radius then Some parameters.radius
      else None in
    Sop.circle_from_edges ~label ?group:(optional_text parameters.group)
      ?radius ~scale:(Vec3.create parameters.scale_x parameters.scale_y
        parameters.scale_z)
      ?output_group:(optional_text parameters.output_group) input)

  let factory = parameters_factory build
end

module Edge_equalize = struct
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Average", Rdk.Edge_ops.Equalize_average;
      "Longest", Rdk.Edge_ops.Equalize_longest;
      "Shortest", Rdk.Edge_ops.Equalize_shortest;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    method_ : Rdk.Edge_ops.equalize_method
      [@sop.default Rdk.Edge_ops.Equalize_average]
      [@sop.label "Method"] [@sop.kind method_parameter];
    iterations : int [@sop.default 64] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 256] [@sop.hard_min 1];
    tolerance : float [@sop.default 0.000001] [@sop.label "Tolerance"]
      [@sop.min 0.000000001] [@sop.max 0.01] [@sop.hard_min 0.];
    output_group : string [@sop.default ""] [@sop.label "Output group"];
  } [@@sop.node_key "edge_equalize"] [@@sop.node_label "Edge Equalize"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.edge_equalize ~label ?group:(optional_text parameters.group)
      ~method_:parameters.method_ ~iterations:parameters.iterations
      ~tolerance:parameters.tolerance
      ?output_group:(optional_text parameters.output_group) input)

  let factory = parameters_factory build
end

module Remesh = struct
  type parameters = {
    target_length : float [@sop.default 0.1] [@sop.label "Target length"]
      [@sop.min 0.0001] [@sop.max 10.] [@sop.hard_min 0.];
    iterations : int [@sop.default 3] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 32] [@sop.hard_min 0];
    smoothing : float [@sop.default 0.5] [@sop.label "Smoothing"]
      [@sop.min 0.] [@sop.max 1.];
    project : bool [@sop.default true] [@sop.label "Project to surface"];
    use_input_points_only : bool [@sop.default false]
      [@sop.label "Use input points only"];
    hard_point_group : string [@sop.default ""] [@sop.label "Hard points"]
      [@sop.folder "Constraints"];
    hard_edge_group : string [@sop.default ""] [@sop.label "Hard edges"]
      [@sop.folder "Constraints"];
    target_size_attribute : string [@sop.default ""]
      [@sop.label "Target size attribute"] [@sop.folder "Adaptivity"];
    preserve_uv_seams : bool [@sop.default true]
      [@sop.label "Preserve UV seams"] [@sop.folder "UV"];
    uv_attribute : string [@sop.default "uv"] [@sop.label "UV attribute"]
      [@sop.folder "UV"];
    output_hard_edges : string [@sop.default ""]
      [@sop.label "Output hard edges"] [@sop.folder "Output"];
    output_mesh_size : string [@sop.default ""]
      [@sop.label "Output mesh size"] [@sop.folder "Output"];
    output_quality : string [@sop.default ""]
      [@sop.label "Output quality"] [@sop.folder "Output"];
    recompute_point_normals : bool [@sop.default true]
      [@sop.label "Recompute point normals"] [@sop.folder "Output"];
  } [@@sop.node_key "remesh"] [@@sop.node_label "Remesh"]
    [@@sop.node_category "Topology/Remesh"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.remesh ~label ~iterations:parameters.iterations
      ~smoothing:parameters.smoothing ~project:parameters.project
      ~use_input_points_only:parameters.use_input_points_only
      ?hard_point_group:(optional_text parameters.hard_point_group)
      ?hard_edge_group:(optional_text parameters.hard_edge_group)
      ?target_size_attribute:(optional_text parameters.target_size_attribute)
      ~preserve_uv_seams:parameters.preserve_uv_seams
      ~uv_attribute:parameters.uv_attribute
      ?output_hard_edges:(optional_text parameters.output_hard_edges)
      ?output_mesh_size:(optional_text parameters.output_mesh_size)
      ?output_quality:(optional_text parameters.output_quality)
      ~recompute_point_normals:parameters.recompute_point_normals
      ~target_length:parameters.target_length input)

  let factory = parameters_factory build
end

module Poly_extrude = struct
  let divide_parameter = Parameter.choice ~equal:( = ) [
      "Individual elements", Rdk.Poly_extrude.Extrude_individual;
      "Connected components", Rdk.Poly_extrude.Extrude_connected_components;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    split_edges : string [@sop.default ""] [@sop.label "Split edge group"];
    distance : float [@sop.default 0.1] [@sop.label "Distance"]
      [@sop.min (-10.)] [@sop.max 10.];
    divide : Rdk.Poly_extrude.divide
      [@sop.default Rdk.Poly_extrude.Extrude_individual]
      [@sop.label "Divide into"] [@sop.kind divide_parameter];
    divisions : int [@sop.default 1] [@sop.label "Divisions"]
      [@sop.min 1] [@sop.max 64] [@sop.hard_min 1];
    output_front : bool [@sop.default true] [@sop.label "Output front"]
      [@sop.folder "Output"];
    output_back : bool [@sop.default true] [@sop.label "Output back"]
      [@sop.folder "Output"];
    output_side : bool [@sop.default true] [@sop.label "Output side"]
      [@sop.folder "Output"];
    front_group : string [@sop.default ""] [@sop.label "Front group"]
      [@sop.folder "Groups"];
    back_group : string [@sop.default ""] [@sop.label "Back group"]
      [@sop.folder "Groups"];
    side_group : string [@sop.default ""] [@sop.label "Side group"]
      [@sop.folder "Groups"];
    front_boundary_group : string [@sop.default ""]
      [@sop.label "Front boundary group"] [@sop.folder "Groups"];
    back_boundary_group : string [@sop.default ""]
      [@sop.label "Back boundary group"] [@sop.folder "Groups"];
  } [@@sop.node_key "poly_extrude"] [@@sop.node_label "Poly Extrude"]
    [@@sop.node_category "Topology/Polygon"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.poly_extrude ~label ?group:(optional_text parameters.group)
      ?split_edges:(optional_text parameters.split_edges)
      ~divide:parameters.divide ~divisions:parameters.divisions
      ~output_front:parameters.output_front
      ~output_back:parameters.output_back ~output_side:parameters.output_side
      ?front_group:(optional_text parameters.front_group)
      ?back_group:(optional_text parameters.back_group)
      ?side_group:(optional_text parameters.side_group)
      ?front_boundary_group:(optional_text parameters.front_boundary_group)
      ?back_boundary_group:(optional_text parameters.back_boundary_group)
      ~distance:parameters.distance input)

  let factory = parameters_factory build
end

module Poly_fill = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Single polygon", Rdk.Poly_fill.Fill_single_polygon;
      "Triangles", Rdk.Poly_fill.Fill_triangles;
      "Triangle fan", Rdk.Poly_fill.Fill_triangle_fan;
    ]

  type parameters = {
    boundary_group : string [@sop.default ""] [@sop.label "Boundary group"];
    mode : Rdk.Poly_fill.mode [@sop.default Rdk.Poly_fill.Fill_triangles]
      [@sop.label "Fill mode"] [@sop.kind mode_parameter];
    reverse_patches : bool [@sop.default false]
      [@sop.label "Reverse patches"];
    unique_points : bool [@sop.default false] [@sop.label "Unique points"];
    update_point_normals : bool [@sop.default false]
      [@sop.label "Update point normals"];
    patch_group : string [@sop.default ""] [@sop.label "Patch group"];
  } [@@sop.node_key "poly_fill"] [@@sop.node_label "Poly Fill"]
    [@@sop.node_category "Topology/Polygon"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.poly_fill ~label
      ?boundary_group:(optional_text parameters.boundary_group)
      ~mode:parameters.mode ~reverse_patches:parameters.reverse_patches
      ~unique_points:parameters.unique_points
      ~update_point_normals:parameters.update_point_normals
      ?patch_group:(optional_text parameters.patch_group) input)

  let factory = parameters_factory build
end

module Convert_line = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    connect_path : bool [@sop.default false] [@sop.label "Connect path"];
    maximum_distance : float [@sop.default 0.001]
      [@sop.label "Maximum distance"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    connect_only_to_other_end_points : bool [@sop.default false]
      [@sop.label "Only other endpoints"];
    make_isolated_loops_closed : bool [@sop.default false]
      [@sop.label "Close isolated loops"];
    remove_unused_points : bool [@sop.default false]
      [@sop.label "Remove unused points"];
    length_attribute : string [@sop.default ""]
      [@sop.label "Length attribute"];
  } [@@sop.node_key "convert_line"] [@@sop.node_label "Convert Line"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.convert_line ~label ?group:(optional_text parameters.group)
      ~connect_path:parameters.connect_path
      ~maximum_distance:parameters.maximum_distance
      ~connect_only_to_other_end_points:
        parameters.connect_only_to_other_end_points
      ~make_isolated_loops_closed:parameters.make_isolated_loops_closed
      ~remove_unused_points:parameters.remove_unused_points
      ?length_attribute:(optional_text parameters.length_attribute) input)

  let factory = parameters_factory build
end

module Resample = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    use_segments : bool [@sop.default true] [@sop.label "Use segments"];
    segments : int [@sop.default 10] [@sop.label "Segments"]
      [@sop.min 1] [@sop.max 1024] [@sop.hard_min 1];
    use_maximum_segment_length : bool [@sop.default false]
      [@sop.label "Use maximum segment length"];
    maximum_segment_length : float [@sop.default 0.1]
      [@sop.label "Maximum segment length"] [@sop.min 0.0001]
      [@sop.max 10.] [@sop.hard_min 0.];
    segment_length_attribute : string [@sop.default ""]
      [@sop.label "Segment length attribute"] [@sop.folder "Overrides"];
    segments_attribute : string [@sop.default ""]
      [@sop.label "Segments attribute"] [@sop.folder "Overrides"];
    even_last_segment : bool [@sop.default true]
      [@sop.label "Even last segment"];
    curve_u_attribute : string [@sop.default ""] [@sop.label "Curve U"]
      [@sop.folder "Output attributes"];
    curve_number_attribute : string [@sop.default ""]
      [@sop.label "Curve number"] [@sop.folder "Output attributes"];
    distance_attribute : string [@sop.default ""] [@sop.label "Distance"]
      [@sop.folder "Output attributes"];
    tangent_attribute : string [@sop.default ""] [@sop.label "Tangent"]
      [@sop.folder "Output attributes"];
  } [@@sop.node_key "resample"] [@@sop.node_label "Resample"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let segments = if parameters.use_segments
      then Some parameters.segments else None
    and maximum_segment_length = if parameters.use_maximum_segment_length
      then Some parameters.maximum_segment_length else None in
    Sop.resample ~label ?group:(optional_text parameters.group) ?segments
      ?maximum_segment_length
      ?segment_length_attribute:
        (optional_text parameters.segment_length_attribute)
      ?segments_attribute:(optional_text parameters.segments_attribute)
      ~even_last_segment:parameters.even_last_segment
      ?curve_u_attribute:(optional_text parameters.curve_u_attribute)
      ?curve_number_attribute:
        (optional_text parameters.curve_number_attribute)
      ?distance_attribute:(optional_text parameters.distance_attribute)
      ?tangent_attribute:(optional_text parameters.tangent_attribute) input)

  let factory = parameters_factory build
end

module Carve = struct
  let attribute_mode_parameter = Parameter.choice ~equal:( = ) [
      "Replace", Rdk.Curve_ops.Replace;
      "Scale", Rdk.Curve_ops.Scale;
    ]
  let keep_parameter = Parameter.choice ~equal:( = ) [
      "Inside", Rdk.Curve_ops.Inside;
      "Outside", Rdk.Curve_ops.Outside;
      "Inside and outside", Rdk.Curve_ops.Inside_and_outside;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    relative_arc_length : bool [@sop.default true]
      [@sop.label "Relative arc length"];
    first : float [@sop.default 0.] [@sop.label "First U"]
      [@sop.min 0.] [@sop.max 1.];
    last : float [@sop.default 1.] [@sop.label "Second U"]
      [@sop.min 0.] [@sop.max 1.];
    first_attribute : string [@sop.default ""]
      [@sop.label "First attribute"] [@sop.folder "Attributes"];
    last_attribute : string [@sop.default ""]
      [@sop.label "Second attribute"] [@sop.folder "Attributes"];
    attribute_mode : Rdk.Curve_ops.parameter_attribute_mode
      [@sop.default Rdk.Curve_ops.Replace]
      [@sop.label "Attribute mode"] [@sop.folder "Attributes"]
      [@sop.kind attribute_mode_parameter];
    only_at_breakpoints : bool [@sop.default false]
      [@sop.label "Only at breakpoints"];
    cut_at_all_internal_breakpoints : bool [@sop.default false]
      [@sop.label "Cut at internal breakpoints"];
    keep : Rdk.Curve_ops.cut_mode [@sop.default Rdk.Curve_ops.Inside]
      [@sop.label "Keep"] [@sop.kind keep_parameter];
    extract_points : bool [@sop.default false] [@sop.label "Extract points"];
    divisions : int [@sop.default 1] [@sop.label "Divisions"]
      [@sop.min 1] [@sop.max 256] [@sop.hard_min 1];
    keep_original : bool [@sop.default false] [@sop.label "Keep original"];
  } [@@sop.node_key "carve"] [@@sop.node_label "Carve"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.carve ~label ?group:(optional_text parameters.group)
      ~relative_arc_length:parameters.relative_arc_length
      ~first:parameters.first ~last:parameters.last
      ?first_attribute:(optional_text parameters.first_attribute)
      ?last_attribute:(optional_text parameters.last_attribute)
      ~attribute_mode:parameters.attribute_mode
      ~only_at_breakpoints:parameters.only_at_breakpoints
      ~cut_at_all_internal_breakpoints:
        parameters.cut_at_all_internal_breakpoints ~keep:parameters.keep
      ~extract_points:parameters.extract_points
      ~divisions:parameters.divisions ~keep_original:parameters.keep_original
      input)

  let factory = parameters_factory build
end

module Ends = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Open", Rdk.Curve_topology.Ends_open;
      "Close straight", Rdk.Curve_topology.Ends_close_straight;
      "Unroll shared point", Rdk.Curve_topology.Ends_unroll_shared;
      "Unroll new point", Rdk.Curve_topology.Ends_unroll_new;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    mode : Rdk.Curve_topology.ends_mode [@sop.default Rdk.Curve_topology.Ends_open]
      [@sop.label "U end"] [@sop.kind mode_parameter];
  } [@@sop.node_key "ends"] [@@sop.node_label "Ends"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.ends ~label ?group:(optional_text parameters.group)
      parameters.mode input)

  let factory = parameters_factory build
end

module Join_curves = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    orient_closest : bool [@sop.default true]
      [@sop.label "Orient closest ends"];
    connect_closest_ends : bool [@sop.default false]
      [@sop.label "Connect closest ends"];
    only_connected : bool [@sop.default false]
      [@sop.label "Only connected"];
    use_group_size : bool [@sop.default false] [@sop.label "Use group size"];
    group_size : int [@sop.default 2] [@sop.label "Group size"]
      [@sop.min 1] [@sop.max 1024] [@sop.hard_min 1];
    keep_originals : bool [@sop.default false]
      [@sop.label "Keep originals"];
    tolerance : float [@sop.default 0.] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    wrap : bool [@sop.default false] [@sop.label "Wrap"];
  } [@@sop.node_key "join_curves"] [@@sop.node_label "Join Curves"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let group_size = if parameters.use_group_size
      then Some parameters.group_size else None in
    Sop.join_curves ~label ?group:(optional_text parameters.group)
      ~orient_closest:parameters.orient_closest
      ~connect_closest_ends:parameters.connect_closest_ends
      ~only_connected:parameters.only_connected ?group_size
      ~keep_originals:parameters.keep_originals
      ~tolerance:parameters.tolerance ~wrap:parameters.wrap input)

  let factory = parameters_factory build
end

module Poly_path = struct
  type parameters = {
    connect_end_points : bool [@sop.default false]
      [@sop.label "Connect endpoints"];
    maximum_distance : float [@sop.default 0.001]
      [@sop.label "Maximum distance"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    connect_only_to_other_end_points : bool [@sop.default false]
      [@sop.label "Only other endpoints"];
    make_isolated_loops_closed : bool [@sop.default false]
      [@sop.label "Close isolated loops"];
  } [@@sop.node_key "poly_path"] [@@sop.node_label "PolyPath"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.poly_path ~label ~connect_end_points:parameters.connect_end_points
      ~maximum_distance:parameters.maximum_distance
      ~connect_only_to_other_end_points:
        parameters.connect_only_to_other_end_points
      ~make_isolated_loops_closed:parameters.make_isolated_loops_closed input)

  let factory = parameters_factory build
end

module Boolean_fracture = struct
  let detriangulation_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Rdk.Boolean.Triangles;
      "Unchanged polygons", Rdk.Boolean.Unchanged_polygons;
      "All polygons", Rdk.Boolean.All_polygons;
    ]

  type parameters = {
    resolve_cutter_self_intersections : bool [@sop.default false]
      [@sop.label "Resolve cutter self-intersections"];
    detriangulation : Rdk.Boolean.detriangulation
      [@sop.default Rdk.Boolean.Triangles]
      [@sop.label "Polygons"] [@sop.kind detriangulation_parameter];
    require_closed : bool [@sop.default true] [@sop.label "Require closed"];
    piece_attribute : string [@sop.default "piece"]
      [@sop.label "Piece attribute"];
    point_tolerance : float [@sop.default 0.] [@sop.label "Point tolerance"]
      [@sop.folder "Robustness"] [@sop.min 0.] [@sop.max 0.001]
      [@sop.hard_min 0.];
    tiny_seam_threshold : float [@sop.default 0.]
      [@sop.label "Tiny seam threshold"] [@sop.folder "Robustness"]
      [@sop.min 0.] [@sop.max 0.001] [@sop.hard_min 0.];
    cleanup_max_batches : int [@sop.default 8]
      [@sop.label "Cleanup batches"] [@sop.folder "Robustness"]
      [@sop.min 1] [@sop.max 32] [@sop.hard_min 1];
    strict_cleanup : bool [@sop.default true] [@sop.label "Strict cleanup"]
      [@sop.folder "Robustness"];
  } [@@sop.node_key "boolean_fracture"] [@@sop.node_label "Boolean Fracture"]
    [@@sop.node_operation "boolean"]
    [@@sop.node_category "Boolean"] [@@sop.node_inputs 2] [@@sop.node_slots "source, cutters"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters source cutters ->
    Sop.boolean_fracture ~label
      ~resolve_cutter_self_intersections:
        parameters.resolve_cutter_self_intersections
      ~point_tolerance:parameters.point_tolerance
      ~tiny_seam_threshold:parameters.tiny_seam_threshold
      ~cleanup_max_batches:parameters.cleanup_max_batches
      ~strict_cleanup:parameters.strict_cleanup
      ~detriangulation:parameters.detriangulation
      ~require_closed:parameters.require_closed
      ~piece_attribute:parameters.piece_attribute ~cutters source)

  let factory = parameters_factory build

  let create ?label:node_label
      ?(resolve_cutter_self_intersections =
          parameters_default.resolve_cutter_self_intersections)
      ?(detriangulation = parameters_default.detriangulation)
      ?(require_closed = parameters_default.require_closed)
      ?(piece_attribute = parameters_default.piece_attribute) ~cutters source =
    build ~label:(label "boolean-fracture" node_label)
      ~inputs:[source; cutters]
      { parameters_default with resolve_cutter_self_intersections;
        detriangulation; require_closed; piece_attribute }
end

module Boolean = struct
  type closed_policy = Closed_default | Closed_required | Closed_not_required

  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Union", Rdk.Boolean.Union;
      "Intersection", Rdk.Boolean.Intersection;
      "Subtract B from A", Rdk.Boolean.Difference;
      "Subtract A from B", Rdk.Boolean.Reverse_difference;
      "Exclusive or", Rdk.Boolean.Xor;
      "Shatter", Rdk.Boolean.Shatter;
    ]
  let treatment_parameter = Parameter.choice ~equal:( = ) [
      "Solid", Rdk.Boolean.Solid; "Surface", Rdk.Boolean.Surface;
    ]
  let conflict_parameter = Parameter.choice ~equal:( = ) [
      "Reject conflict", Rdk.Boolean.Reject;
      "Promote to vertex", Rdk.Boolean.Promote_to_vertex;
    ]
  let seam_points_parameter = Parameter.choice ~equal:( = ) [
      "Shared", Rdk.Boolean.Shared_seam_points;
      "Split", Rdk.Boolean.Split_seam_points;
    ]
  let detriangulation_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Rdk.Boolean.Triangles;
      "Unchanged polygons", Rdk.Boolean.Unchanged_polygons;
      "All polygons", Rdk.Boolean.All_polygons;
    ]
  let closed_parameter = Parameter.choice ~equal:( = ) [
      "Operation default", Closed_default;
      "Require closed", Closed_required;
      "Allow open", Closed_not_required;
    ]

  type parameters = {
    operation : Rdk.Boolean.operation [@sop.default Rdk.Boolean.Union]
      [@sop.label "Operation"] [@sop.kind operation_parameter];
    left_treatment : Rdk.Boolean.treatment [@sop.default Rdk.Boolean.Solid]
      [@sop.label "A treatment"] [@sop.folder "Operands"]
      [@sop.kind treatment_parameter];
    right_treatment : Rdk.Boolean.treatment [@sop.default Rdk.Boolean.Solid]
      [@sop.label "B treatment"] [@sop.folder "Operands"]
      [@sop.kind treatment_parameter];
    resolve_left_self_intersections : bool [@sop.default false]
      [@sop.label "Resolve A self-intersections"] [@sop.folder "Operands"];
    resolve_right_self_intersections : bool [@sop.default false]
      [@sop.label "Resolve B self-intersections"] [@sop.folder "Operands"];
    point_conflict : Rdk.Boolean.point_conflict
      [@sop.default Rdk.Boolean.Promote_to_vertex]
      [@sop.label "Point attribute conflicts"] [@sop.folder "Attributes"]
      [@sop.kind conflict_parameter];
    point_tolerance : float [@sop.default 0.] [@sop.label "Point tolerance"]
      [@sop.folder "Robustness"] [@sop.min 0.] [@sop.max 0.001]
      [@sop.hard_min 0.];
    tiny_seam_threshold : float [@sop.default 0.]
      [@sop.label "Tiny seam threshold"] [@sop.folder "Robustness"]
      [@sop.min 0.] [@sop.max 0.001] [@sop.hard_min 0.];
    cleanup_max_batches : int [@sop.default 8]
      [@sop.label "Cleanup batches"] [@sop.folder "Robustness"]
      [@sop.min 1] [@sop.max 32] [@sop.hard_min 1];
    strict_cleanup : bool [@sop.default true] [@sop.label "Strict cleanup"]
      [@sop.folder "Robustness"];
    seam_points : Rdk.Boolean.seam_points
      [@sop.default Rdk.Boolean.Shared_seam_points]
      [@sop.label "Seam points"] [@sop.folder "Output"]
      [@sop.kind seam_points_parameter];
    detriangulation : Rdk.Boolean.detriangulation
      [@sop.default Rdk.Boolean.Triangles]
      [@sop.label "Polygons"] [@sop.folder "Output"]
      [@sop.kind detriangulation_parameter];
    assume_flat : bool [@sop.default false] [@sop.label "Assume flat"]
      [@sop.folder "Output"];
    require_closed : closed_policy [@sop.default Closed_default]
      [@sop.label "Closed output"] [@sop.folder "Output"]
      [@sop.kind closed_parameter];
    piece_attribute : string [@sop.default ""] [@sop.label "Piece attribute"]
      [@sop.folder "Output"];
    left_piece_group : string [@sop.default "boolean_left"]
      [@sop.label "A-only group"] [@sop.folder "Shatter groups"];
    overlap_piece_group : string [@sop.default "boolean_overlap"]
      [@sop.label "Overlap group"] [@sop.folder "Shatter groups"];
    right_piece_group : string [@sop.default "boolean_right"]
      [@sop.label "B-only group"] [@sop.folder "Shatter groups"];
  } [@@sop.node_key "boolean"] [@@sop.node_label "Boolean"]
    [@@sop.node_category "Boolean"] [@@sop.node_inputs 2] [@@sop.node_slots "left, right"]
    [@@deriving sop_params, sop_node]

  let require_closed = function
    | Closed_default -> None | Closed_required -> Some true
    | Closed_not_required -> Some false

  let build = parameters_build (fun ~label parameters left right ->
    Sop.boolean ~label ~operation:parameters.operation
      ~left_treatment:parameters.left_treatment
      ~right_treatment:parameters.right_treatment
      ~resolve_left_self_intersections:
        parameters.resolve_left_self_intersections
      ~resolve_right_self_intersections:
        parameters.resolve_right_self_intersections
      ~point_conflict:parameters.point_conflict
      ~point_tolerance:parameters.point_tolerance
      ~tiny_seam_threshold:parameters.tiny_seam_threshold
      ~cleanup_max_batches:parameters.cleanup_max_batches
      ~strict_cleanup:parameters.strict_cleanup
      ~seam_points:parameters.seam_points
      ~detriangulation:parameters.detriangulation
      ~assume_flat:parameters.assume_flat
      ?require_closed:(require_closed parameters.require_closed)
      ?piece_attribute:(optional_text parameters.piece_attribute)
      ~left_piece_group:(optional_text parameters.left_piece_group)
      ~overlap_piece_group:(optional_text parameters.overlap_piece_group)
      ~right_piece_group:(optional_text parameters.right_piece_group)
      ~right left)

  let factory = parameters_factory build

  let create ?label:node_label ?(operation = parameters_default.operation)
      ?(resolve_right_self_intersections =
          parameters_default.resolve_right_self_intersections)
      ?(detriangulation = parameters_default.detriangulation) ~right left =
    build ~label:(label "boolean" node_label) ~inputs:[left; right]
      { parameters_default with operation; resolve_right_self_intersections;
        detriangulation }
end

module Boolean_seam = struct
  let output_parameter = Parameter.choice ~equal:( = ) [
      "Seam curves", Rdk.Boolean.Seam_curves;
      "Coincident patches", Rdk.Boolean.Coincident_patches;
    ]
  let treatment_parameter = Parameter.choice ~equal:( = ) [
      "Solid", Rdk.Boolean.Solid; "Surface", Rdk.Boolean.Surface;
    ]

  type parameters = {
    output : Rdk.Boolean.seam_output [@sop.default Rdk.Boolean.Seam_curves]
      [@sop.label "Output"] [@sop.kind output_parameter];
    left_treatment : Rdk.Boolean.treatment [@sop.default Rdk.Boolean.Solid]
      [@sop.label "A treatment"] [@sop.folder "Operands"]
      [@sop.kind treatment_parameter];
    right_treatment : Rdk.Boolean.treatment [@sop.default Rdk.Boolean.Solid]
      [@sop.label "B treatment"] [@sop.folder "Operands"]
      [@sop.kind treatment_parameter];
    resolve_left_self_intersections : bool [@sop.default false]
      [@sop.label "Resolve A self-intersections"] [@sop.folder "Operands"];
    resolve_right_self_intersections : bool [@sop.default false]
      [@sop.label "Resolve B self-intersections"] [@sop.folder "Operands"];
    left_self_group : string [@sop.default "boolean_left_self_seam"]
      [@sop.label "A self group"] [@sop.folder "Groups"];
    between_group : string [@sop.default "boolean_seam"]
      [@sop.label "Between group"] [@sop.folder "Groups"];
    right_self_group : string [@sop.default "boolean_right_self_seam"]
      [@sop.label "B self group"] [@sop.folder "Groups"];
    coincident_group : string [@sop.default "boolean_coincident"]
      [@sop.label "Coincident group"] [@sop.folder "Groups"];
  } [@@sop.node_key "boolean_seam"] [@@sop.node_label "Boolean Seam"]
    [@@sop.node_category "Boolean/Analysis"] [@@sop.node_inputs 2] [@@sop.node_slots "left, right"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters left right ->
    Sop.boolean_seam ~label ~output:parameters.output
      ~left_treatment:parameters.left_treatment
      ~right_treatment:parameters.right_treatment
      ~resolve_left_self_intersections:
        parameters.resolve_left_self_intersections
      ~resolve_right_self_intersections:
        parameters.resolve_right_self_intersections
      ~left_self_group:(optional_text parameters.left_self_group)
      ~between_group:(optional_text parameters.between_group)
      ~right_self_group:(optional_text parameters.right_self_group)
      ~coincident_group:(optional_text parameters.coincident_group)
      ~right left)

  let factory = parameters_factory build
end

module Boolean_detect = struct
  type parameters = {
    source_group : string [@sop.default ""] [@sop.label "Source group"]
      [@sop.folder "Inputs"];
    collision_group : string [@sop.default ""] [@sop.label "Collision group"]
      [@sop.folder "Inputs"];
    tolerance : float [@sop.default 0.] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.001] [@sop.hard_min 0.];
    include_coplanar : bool [@sop.default true]
      [@sop.label "Include coplanar overlap"];
    intersecting_group : string [@sop.default "boolean_intersections"]
      [@sop.label "Intersecting group"] [@sop.folder "A/B outputs"];
    intersections_attribute : string [@sop.default ""]
      [@sop.label "Intersections attribute"] [@sop.folder "A/B outputs"];
    count_attribute : string [@sop.default ""]
      [@sop.label "Count attribute"] [@sop.folder "A/B outputs"];
    self_intersecting_group : string
      [@sop.default "boolean_self_intersections"]
      [@sop.label "Self-intersecting group"] [@sop.folder "Self outputs"];
    self_intersections_attribute : string [@sop.default ""]
      [@sop.label "Self intersections attribute"] [@sop.folder "Self outputs"];
    self_count_attribute : string [@sop.default ""]
      [@sop.label "Self count attribute"] [@sop.folder "Self outputs"];
  } [@@sop.node_key "boolean_detect"] [@@sop.node_label "Boolean Detect"]
    [@@sop.node_category "Boolean/Analysis"] [@@sop.node_inputs 2] [@@sop.node_slots "input, collision"]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input collision ->
    let collision_group = match collision with
      | None -> None | Some _ -> optional_text parameters.collision_group in
    let intersecting_group = match collision with
      | None -> None | Some _ -> optional_text parameters.intersecting_group
    and intersections_attribute = match collision with
      | None -> None
      | Some _ -> optional_text parameters.intersections_attribute
    and count_attribute = match collision with
      | None -> None | Some _ -> optional_text parameters.count_attribute in
    Sop.boolean_detect ~label
      ?source_group:(optional_text parameters.source_group) ?collision_group
      ~tolerance:parameters.tolerance
      ~include_coplanar:parameters.include_coplanar
      ~intersecting_group ?intersections_attribute ?count_attribute
      ~self_intersecting_group:
        (optional_text parameters.self_intersecting_group)
      ?self_intersections_attribute:
        (optional_text parameters.self_intersections_attribute)
      ?self_count_attribute:(optional_text parameters.self_count_attribute)
      ?collision input)

  let factory = parameters_factory build
end

module Intersection_analysis = struct
  type parameters = {
    source_group : string [@sop.default ""] [@sop.label "Source group"]
      [@sop.folder "Inputs"];
    collision_group : string [@sop.default ""] [@sop.label "Collision group"]
      [@sop.folder "Inputs"];
    tolerance : float [@sop.default 0.] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.001] [@sop.hard_min 0.];
    include_coplanar : bool [@sop.default true]
      [@sop.label "Include coplanar overlap"];
    input_attribute : string [@sop.default "sourceinput"]
      [@sop.label "Input attribute"] [@sop.folder "Output attributes"];
    primitive_attribute : string [@sop.default "sourceprim"]
      [@sop.label "Primitive attribute"] [@sop.folder "Output attributes"];
    primitive_uvw_attribute : string [@sop.default "sourceprimuv"]
      [@sop.label "Primitive UVW attribute"] [@sop.folder "Output attributes"];
    point_attribute : string [@sop.default "sourcepoint"]
      [@sop.label "Point attribute"] [@sop.folder "Output attributes"];
  } [@@sop.node_key "intersection_analysis"]
    [@@sop.node_label "Intersection Analysis"]
    [@@sop.node_category "Boolean/Analysis"] [@@sop.node_inputs 2] [@@sop.node_slots "input, collision"]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input collision ->
    let collision_group = match collision with
      | None -> None | Some _ -> optional_text parameters.collision_group in
    Sop.intersection_analysis ~label
      ?source_group:(optional_text parameters.source_group) ?collision_group
      ~tolerance:parameters.tolerance
      ~include_coplanar:parameters.include_coplanar
      ~input_attribute:(optional_text parameters.input_attribute)
      ~primitive_attribute:(optional_text parameters.primitive_attribute)
      ~primitive_uvw_attribute:
        (optional_text parameters.primitive_uvw_attribute)
      ~point_attribute:(optional_text parameters.point_attribute)
      ?collision input)

  let factory = parameters_factory build
end

module Poly_reduce = struct
  type target_mode = Ratio | Primitive_count
  let target_parameter = Parameter.choice ~equal:( = ) [
      "Percentage", Ratio; "Primitive count", Primitive_count;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    hard_point_group : string [@sop.default ""]
      [@sop.label "Hard point group"] [@sop.folder "Constraints"];
    hard_edge_group : string [@sop.default ""]
      [@sop.label "Hard edge group"] [@sop.folder "Constraints"];
    target_mode : target_mode [@sop.default Ratio]
      [@sop.label "Target"] [@sop.kind target_parameter];
    ratio : float [@sop.default 0.5] [@sop.label "Percentage"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    primitive_count : int [@sop.default 100] [@sop.label "Primitive count"]
      [@sop.min 0] [@sop.max 1000000] [@sop.hard_min 0];
    preserve_boundary : bool [@sop.default true]
      [@sop.label "Preserve boundary"];
    only_original_positions : bool [@sop.default false]
      [@sop.label "Only original positions"];
    equalize_lengths : float [@sop.default 0.0000000001]
      [@sop.label "Equalize edge lengths"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.];
    limit_normal_deviation : bool [@sop.default false]
      [@sop.label "Limit normal deviation"];
    max_normal_deviation : float [@sop.default 0.5]
      [@sop.label "Maximum normal deviation"] [@sop.min 0.]
      [@sop.max 3.141592653589793] [@sop.hard_min 0.];
    output_group : string [@sop.default ""] [@sop.label "Output group"];
    recompute_point_normals : bool [@sop.default true]
      [@sop.label "Recompute point normals"];
  } [@@sop.node_key "poly_reduce"] [@@sop.node_label "PolyReduce"]
    [@@sop.node_category "Topology/Remesh"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let target = match parameters.target_mode with
      | Ratio -> Rdk.Poly_reduce.Reduce_ratio parameters.ratio
      | Primitive_count ->
          Rdk.Poly_reduce.Reduce_primitive_count parameters.primitive_count in
    let max_normal_deviation = if parameters.limit_normal_deviation
      then Some parameters.max_normal_deviation else None in
    Sop.poly_reduce ~label ?group:(optional_text parameters.group)
      ?hard_point_group:(optional_text parameters.hard_point_group)
      ?hard_edge_group:(optional_text parameters.hard_edge_group) ~target
      ~preserve_boundary:parameters.preserve_boundary
      ~only_original_positions:parameters.only_original_positions
      ~equalize_lengths:parameters.equalize_lengths ?max_normal_deviation
      ?output_group:(optional_text parameters.output_group)
      ~recompute_point_normals:parameters.recompute_point_normals input)

  let factory = parameters_factory build
end

module Convex_hull = struct
  type parameters = {
    group_owner : element_owner [@sop.default Element_point]
      [@sop.label "Group type"] [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    preserve_point_payload : bool [@sop.default true]
      [@sop.label "Preserve point payload"];
    source_point_attribute : string [@sop.default "sourcepoint"]
      [@sop.label "Source point attribute"] [@sop.folder "Output"];
    hull_group : string [@sop.default "hull"] [@sop.label "Hull group"]
      [@sop.folder "Output"];
  } [@@sop.node_key "convex_hull"] [@@sop.node_label "Convex Hull"]
    [@@sop.node_category "Topology"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.convex_hull ~label
      ?selection:(optional_element_group parameters.group_owner
        parameters.group)
      ~preserve_point_payload:parameters.preserve_point_payload
      ?source_point_attribute:
        (optional_text parameters.source_point_attribute)
      ?hull_group:(optional_text parameters.hull_group) input)
  let factory = parameters_factory build
end

module Fuse = struct
  type targeting_mode = Near_points | Specified_points
  let targeting_parameter = Parameter.choice ~equal:( = ) [
      "Near points", Near_points; "Specified points", Specified_points;
    ]
  let using_parameter = Parameter.choice ~equal:( = ) [
      "Least target point", Rdk.Fuse_grid.Least_target_point;
      "Closest target point", Rdk.Fuse_grid.Closest_target_point;
    ]
  let position_parameter = Parameter.choice ~equal:( = ) [
      "First", Rdk.Fuse_reduce.First_position;
      "Least point", Rdk.Fuse_reduce.Least_point_position;
      "Greatest point", Rdk.Fuse_reduce.Greatest_point_position;
      "Average", Rdk.Fuse_reduce.Average_position;
      "Minimum", Rdk.Fuse_reduce.Minimum_position;
      "Maximum", Rdk.Fuse_reduce.Maximum_position;
      "Mode", Rdk.Fuse_reduce.Mode_position;
      "Median", Rdk.Fuse_reduce.Median_position;
      "Sum", Rdk.Fuse_reduce.Sum_position;
      "Sum squares", Rdk.Fuse_reduce.Sum_squares_position;
      "Root mean square", Rdk.Fuse_reduce.Root_mean_square_position;
      "Weighted average", Rdk.Fuse_reduce.Weighted_average_position;
      "Weighted sum", Rdk.Fuse_reduce.Weighted_sum_position;
      "Minimum weight", Rdk.Fuse_reduce.Minimum_weight_position;
      "Maximum weight", Rdk.Fuse_reduce.Maximum_weight_position;
    ]
  let attributes_parameter = Parameter.choice ~equal:( = ) [
      "Keep first", Rdk.Fuse_reduce.Keep_first;
      "Average numeric", Rdk.Fuse_reduce.Average_numeric;
    ]
  let metric_parameter = Parameter.choice ~equal:( = ) [
      "Euclidean", Rdk.Fuse_grid.Euclidean;
      "Componentwise", Rdk.Fuse_grid.Componentwise;
    ]
  let condition_parameter = Parameter.choice ~equal:( = ) [
      "Equal", Rdk.Fuse_grid.Equal_attribute_values;
      "Unequal", Rdk.Fuse_grid.Unequal_attribute_values;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    target_group : string [@sop.default ""] [@sop.label "Target group"];
    targeting : targeting_mode [@sop.default Near_points]
      [@sop.label "Targeting"] [@sop.kind targeting_parameter];
    target_attribute : string [@sop.default "targetpoint"]
      [@sop.label "Target point attribute"];
    using : Rdk.Fuse_grid.fuse_using [@sop.default Rdk.Fuse_grid.Least_target_point]
      [@sop.label "Use target"] [@sop.kind using_parameter];
    tolerance : float [@sop.default 0.001] [@sop.label "Snap distance"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
    position : Rdk.Fuse_reduce.position [@sop.default Rdk.Fuse_reduce.Average_position]
      [@sop.label "Position"] [@sop.folder "Fuse"]
      [@sop.kind position_parameter];
    weight_attribute : string [@sop.default ""]
      [@sop.label "Weight attribute"] [@sop.folder "Fuse"];
    attributes : Rdk.Fuse_reduce.attributes [@sop.default Rdk.Fuse_reduce.Keep_first]
      [@sop.label "Attributes"] [@sop.folder "Fuse"]
      [@sop.kind attributes_parameter];
    metric : Rdk.Fuse_grid.fuse_metric [@sop.default Rdk.Fuse_grid.Euclidean]
      [@sop.label "Metric"] [@sop.folder "Matching"]
      [@sop.kind metric_parameter];
    inclusive : bool [@sop.default true] [@sop.label "Inclusive distance"]
      [@sop.folder "Matching"];
    match_attributes : bool [@sop.default false]
      [@sop.label "Match attributes"] [@sop.folder "Matching"];
    radius_attribute : string [@sop.default ""]
      [@sop.label "Radius attribute"] [@sop.folder "Matching"];
    match_attribute : string [@sop.default ""]
      [@sop.label "Match attribute"] [@sop.folder "Matching"];
    match_condition : Rdk.Fuse_grid.fuse_match_condition
      [@sop.default Rdk.Fuse_grid.Equal_attribute_values]
      [@sop.label "Match condition"] [@sop.folder "Matching"]
      [@sop.kind condition_parameter];
    match_tolerance : float [@sop.default 0.] [@sop.label "Match tolerance"]
      [@sop.folder "Matching"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.];
    modify_target : bool [@sop.default false] [@sop.label "Modify target"];
    fuse_points : bool [@sop.default true] [@sop.label "Fuse points"];
    keep_fused_points : bool [@sop.default false]
      [@sop.label "Keep fused points"];
    snapped_group : string [@sop.default ""] [@sop.label "Snapped group"]
      [@sop.folder "Output"];
    snapped_destination_attribute : string [@sop.default ""]
      [@sop.label "Destination attribute"] [@sop.folder "Output"];
    remove_degenerate_primitives : bool [@sop.default true]
      [@sop.label "Remove degenerate primitives"] [@sop.folder "Cleanup"];
    remove_unused_points_from_degenerate_primitives : bool [@sop.default true]
      [@sop.label "Remove newly unused points"] [@sop.folder "Cleanup"];
    remove_all_unused_points : bool [@sop.default false]
      [@sop.label "Remove all unused points"] [@sop.folder "Cleanup"];
  } [@@sop.node_key "fuse"] [@@sop.node_label "Fuse"]
    [@@sop.node_category "Topology/Cleanup"] [@@sop.node_inputs 2] [@@sop.node_slots "input, target"]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let targeting parameters = match parameters.targeting with
    | Near_points -> Rdk.Fuse_grid.Near_points
    | Specified_points -> Rdk.Fuse_grid.Specified_points parameters.target_attribute

  let build = parameters_build (fun ~label parameters input target ->
    Sop.fuse ~label ?group:(optional_text parameters.group)
      ?target_group:(optional_text parameters.target_group)
      ~targeting:(targeting parameters) ~using:parameters.using
      ~tolerance:parameters.tolerance ~position:parameters.position
      ?weight_attribute:(optional_text parameters.weight_attribute)
      ~attributes:parameters.attributes ~metric:parameters.metric
      ~inclusive:parameters.inclusive
      ~match_attributes:parameters.match_attributes
      ?radius_attribute:(optional_text parameters.radius_attribute)
      ?match_attribute:(optional_text parameters.match_attribute)
      ~match_condition:parameters.match_condition
      ~match_tolerance:parameters.match_tolerance
      ~modify_target:parameters.modify_target
      ~fuse_points:parameters.fuse_points
      ~keep_fused_points:parameters.keep_fused_points
      ?snapped_group:(optional_text parameters.snapped_group)
      ?snapped_destination_attribute:
        (optional_text parameters.snapped_destination_attribute)
      ~remove_degenerate_primitives:parameters.remove_degenerate_primitives
      ~remove_unused_points_from_degenerate_primitives:
        parameters.remove_unused_points_from_degenerate_primitives
      ~remove_all_unused_points:parameters.remove_all_unused_points
      ?target input)

  let factory = parameters_factory build
end

module Point_split = struct
  type parameters = {
    group_owner : element_owner [@sop.default Element_point]
      [@sop.label "Group type"] [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    attributes : string [@sop.default "*"] [@sop.label "Attributes"];
    tolerance : float [@sop.default 0.] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    promote_attributes : bool [@sop.default false]
      [@sop.label "Promote attributes"];
  } [@@sop.node_key "point_split"] [@@sop.node_label "Point Split"]
    [@@sop.node_category "Topology/Point"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.point_split ~label
      ?selection:(optional_element_group parameters.group_owner
        parameters.group) ~attributes:parameters.attributes
      ~tolerance:parameters.tolerance
      ~promote_attributes:parameters.promote_attributes input)
  let factory = parameters_factory build
end

module Poly_bridge = struct
  let pairing_parameter = Parameter.choice ~equal:( = ) [
      "By order", Rdk.Poly_bridge.Bridge_by_order;
      "By centroid", Rdk.Poly_bridge.Bridge_by_centroid;
    ]
  let minimize_parameter = Parameter.choice ~equal:( = ) [
      "Two point distance", Rdk.Poly_loft.Two_point_distance;
      "Three point distance", Rdk.Poly_loft.Three_point_distance;
    ]

  type parameters = {
    source_group : string [@sop.default "source"]
      [@sop.label "Source edge group"];
    destination_group : string [@sop.default "destination"]
      [@sop.label "Destination edge group"];
    pairing : Rdk.Poly_bridge.pairing
      [@sop.default Rdk.Poly_bridge.Bridge_by_order]
      [@sop.label "Pairing"] [@sop.kind pairing_parameter];
    connect_closest_ends : bool [@sop.default true]
      [@sop.label "Connect closest ends"];
    minimize : Rdk.Poly_loft.minimize
      [@sop.default Rdk.Poly_loft.Two_point_distance]
      [@sop.label "Minimize"] [@sop.kind minimize_parameter];
    reverse_source : bool [@sop.default false] [@sop.label "Reverse source"];
    reverse_destination : bool [@sop.default false]
      [@sop.label "Reverse destination"];
    pairing_shift : int [@sop.default 0] [@sop.label "Pairing shift"]
      [@sop.min (-128)] [@sop.max 128];
    divisions : int [@sop.default 1] [@sop.label "Divisions"]
      [@sop.min 1] [@sop.max 256] [@sop.hard_min 1];
    keep_input : bool [@sop.default true] [@sop.label "Keep input"];
    output_group : string [@sop.default "bridge"] [@sop.label "Output group"];
    collinearity_tolerance : float [@sop.default 0.]
      [@sop.label "Collinearity tolerance"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.];
    recompute_normals : bool [@sop.default false]
      [@sop.label "Recompute normals"];
  } [@@sop.node_key "poly_bridge"] [@@sop.node_label "PolyBridge"]
    [@@sop.node_category "Topology/Polygon"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.poly_bridge ~label ~source_group:parameters.source_group
      ~destination_group:parameters.destination_group
      ~pairing:parameters.pairing
      ~connect_closest_ends:parameters.connect_closest_ends
      ~minimize:parameters.minimize
      ~reverse_source:parameters.reverse_source
      ~reverse_destination:parameters.reverse_destination
      ~pairing_shift:parameters.pairing_shift
      ~divisions:parameters.divisions ~keep_input:parameters.keep_input
      ?output_group:(optional_text parameters.output_group)
      ~collinearity_tolerance:parameters.collinearity_tolerance
      ~recompute_normals:parameters.recompute_normals input)
  let factory = parameters_factory build
end

module Edge_relax = struct
  let target_parameter = Parameter.choice ~equal:( = ) [
      "Individual lengths", Rdk.Edge_relax.Individual_lengths;
      "Scale-independent distribution", Rdk.Edge_relax.Scale_independent_distribution;
    ]

  type parameters = {
    group_owner : element_owner [@sop.default Element_edge]
      [@sop.label "Group type"] [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    pin_group : string [@sop.default ""] [@sop.label "Pin point group"];
    iterations : int [@sop.default 32] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 1024] [@sop.hard_min 1];
    step_size : float [@sop.default 0.5] [@sop.label "Step size"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    target_mode : Rdk.Edge_relax.target_mode
      [@sop.default Rdk.Edge_relax.Individual_lengths]
      [@sop.label "Target mode"] [@sop.kind target_parameter];
    only_shorten : bool [@sop.default false] [@sop.label "Only shorten"];
    tolerance : float [@sop.default 0.000001] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.];
  } [@@sop.node_key "edge_relax"] [@@sop.node_label "Edge Relax"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 2] [@@sop.node_slots "source, reference"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters source reference ->
    Sop.edge_relax ~label
      ?group:(optional_element_group parameters.group_owner parameters.group)
      ?pin_group:(optional_text parameters.pin_group)
      ~iterations:parameters.iterations ~step_size:parameters.step_size
      ~target_mode:parameters.target_mode
      ~only_shorten:parameters.only_shorten
      ~tolerance:parameters.tolerance ~reference source)
  let factory = parameters_factory build
end

module Poly_loft = struct
  let minimize_parameter = Parameter.choice ~equal:( = ) [
      "Two point distance", Rdk.Poly_loft.Two_point_distance;
      "Three point distance", Rdk.Poly_loft.Three_point_distance;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    connect_closest_ends : bool [@sop.default true]
      [@sop.label "Connect closest ends"];
    minimize : Rdk.Poly_loft.minimize
      [@sop.default Rdk.Poly_loft.Two_point_distance]
      [@sop.label "Minimize"] [@sop.kind minimize_parameter];
    u_wrap : bool [@sop.default false] [@sop.label "Wrap U"];
    v_wrap : bool [@sop.default false] [@sop.label "Wrap V"];
    keep_primitives : bool [@sop.default false]
      [@sop.label "Keep source primitives"];
    output_group : string [@sop.default "loft"] [@sop.label "Output group"];
    collinearity_tolerance : float [@sop.default 0.]
      [@sop.label "Collinearity tolerance"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.];
    recompute_normals : bool [@sop.default true]
      [@sop.label "Recompute normals"];
  } [@@sop.node_key "poly_loft"] [@@sop.node_label "PolyLoft"]
    [@@sop.node_category "Topology/Polygon"] [@@sop.node_inputs 2] [@@sop.node_slots "input, rest"]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input rest ->
    Sop.poly_loft ~label ?group:(optional_text parameters.group) ?rest
      ~connect_closest_ends:parameters.connect_closest_ends
      ~minimize:parameters.minimize ~u_wrap:parameters.u_wrap
      ~v_wrap:parameters.v_wrap ~keep_primitives:parameters.keep_primitives
      ?output_group:(optional_text parameters.output_group)
      ~collinearity_tolerance:parameters.collinearity_tolerance
      ~recompute_normals:parameters.recompute_normals input)

  let factory = parameters_factory build
end

module Revolve = struct
  let type_parameter = Parameter.choice ~equal:( = ) [
      "Closed", Rdk.Sweep_modeling.Revolve_closed;
      "Open arc", Rdk.Sweep_modeling.Revolve_open_arc;
    ]
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Points", Rdk.Plane_generators.Grid_points;
      "Rows", Rdk.Plane_generators.Grid_rows;
      "Columns", Rdk.Plane_generators.Grid_columns;
      "Rows and columns", Rdk.Plane_generators.Grid_rows_and_columns;
      "Quads", Rdk.Plane_generators.Grid_quads;
      "Triangles", Rdk.Plane_generators.Grid_triangles;
      "Alternating triangles", Rdk.Plane_generators.Grid_alternating_triangles;
      "Reverse triangles", Rdk.Plane_generators.Grid_reverse_triangles;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    revolve_type : Rdk.Sweep_modeling.revolve_type [@sop.default Rdk.Sweep_modeling.Revolve_closed]
      [@sop.label "Revolve type"] [@sop.kind type_parameter];
    connectivity : Rdk.Plane_generators.grid_connectivity [@sop.default Rdk.Plane_generators.Grid_quads]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    start_angle : float [@sop.default 0.] [@sop.label "Start angle"]
      [@sop.min (-6.283185307179586)] [@sop.max 6.283185307179586];
    end_angle : float [@sop.default 6.283185307179586]
      [@sop.label "End angle"] [@sop.min (-6.283185307179586)]
      [@sop.max 6.283185307179586];
    reverse_cross_sections : bool [@sop.default false]
      [@sop.label "Reverse cross sections"];
    caps : bool [@sop.default false] [@sop.label "End caps"];
    cap_group : string [@sop.default "caps"] [@sop.label "Cap group"];
    uv_attribute : string [@sop.default "uv"] [@sop.label "UV attribute"];
    divisions : int [@sop.default 32] [@sop.label "Divisions"]
      [@sop.min 2] [@sop.max 512] [@sop.hard_min 1];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Axis/Origin"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "origin"]
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Axis/Origin"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "origin"]
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Axis/Origin"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "origin"]
    axis_x : float [@sop.default 0.] [@sop.label "Axis X"]
      [@sop.folder "Axis/Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Axis/Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Axis/Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
  } [@@sop.node_key "revolve"] [@@sop.node_label "Revolve"]
    [@@sop.node_category "Topology/Surface"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.revolve ~label ?group:(optional_text parameters.group)
      ~revolve_type:parameters.revolve_type
      ~connectivity:parameters.connectivity
      ~start_angle:parameters.start_angle ~end_angle:parameters.end_angle
      ~reverse_cross_sections:parameters.reverse_cross_sections
      ~caps:parameters.caps
      ?cap_group:(if parameters.caps then optional_text parameters.cap_group else None)
      ~uv_attribute:(optional_text parameters.uv_attribute)
      ~divisions:parameters.divisions
      ~origin:(Vec3.create parameters.origin_x parameters.origin_y
        parameters.origin_z)
      ~axis:(Vec3.create parameters.axis_x parameters.axis_y
        parameters.axis_z) input)
  let factory = parameters_factory build
end

module Sweep = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Points", Rdk.Plane_generators.Grid_points; "Rows", Rdk.Plane_generators.Grid_rows;
      "Columns", Rdk.Plane_generators.Grid_columns;
      "Rows and columns", Rdk.Plane_generators.Grid_rows_and_columns;
      "Quads", Rdk.Plane_generators.Grid_quads; "Triangles", Rdk.Plane_generators.Grid_triangles;
      "Alternating triangles", Rdk.Plane_generators.Grid_alternating_triangles;
      "Reverse triangles", Rdk.Plane_generators.Grid_reverse_triangles;
    ]
  let tangent_parameter = Parameter.choice ~equal:( = ) [
      "Average edges", Rdk.Sweep_modeling.Sweep_average_edges;
      "Central difference", Rdk.Sweep_modeling.Sweep_central_difference;
      "Previous edge", Rdk.Sweep_modeling.Sweep_previous_edge;
      "Next edge", Rdk.Sweep_modeling.Sweep_next_edge;
      "Z axis", Rdk.Sweep_modeling.Sweep_z_axis;
    ]

  type parameters = {
    backbone_group : string [@sop.default ""]
      [@sop.label "Backbone primitive group"];
    cross_section_group : string [@sop.default ""]
      [@sop.label "Cross-section primitive group"];
    connectivity : Rdk.Plane_generators.grid_connectivity [@sop.default Rdk.Plane_generators.Grid_quads]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    tangent : Rdk.Sweep_modeling.sweep_tangent
      [@sop.default Rdk.Sweep_modeling.Sweep_average_edges]
      [@sop.label "Tangent"] [@sop.kind tangent_parameter];
    continuous_closed : bool [@sop.default true]
      [@sop.label "Continuous closed backbone"];
    transform_attributes : bool [@sop.default true]
      [@sop.label "Transform attributes"];
    reverse_cross_sections : bool [@sop.default false]
      [@sop.label "Reverse cross sections"];
    scale : float [@sop.default 1.] [@sop.label "Scale"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.];
    roll : float [@sop.default 0.] [@sop.label "Roll"]
      [@sop.folder "Transform"] [@sop.min (-6.283185307179586)]
      [@sop.max 6.283185307179586];
    twist : float [@sop.default 0.] [@sop.label "Twist"]
      [@sop.folder "Transform"] [@sop.min (-12.566370614359172)]
      [@sop.max 12.566370614359172];
    caps : bool [@sop.default false] [@sop.label "End caps"];
    cap_group : string [@sop.default "caps"] [@sop.label "Cap group"];
    uv_attribute : string [@sop.default "uv"] [@sop.label "UV attribute"];
    cross_section_prefix : string [@sop.default "cross_section_"]
      [@sop.label "Cross-section attribute prefix"];
  } [@@sop.node_key "sweep"] [@@sop.node_label "Sweep"]
    [@@sop.node_category "Topology/Surface"] [@@sop.node_inputs 2] [@@sop.node_slots "backbone, cross_section"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters backbone cross_section ->
    Sop.sweep ~label
      ?backbone_group:(optional_text parameters.backbone_group)
      ?cross_section_group:(optional_text parameters.cross_section_group)
      ~connectivity:parameters.connectivity ~tangent:parameters.tangent
      ~continuous_closed:parameters.continuous_closed
      ~transform_attributes:parameters.transform_attributes
      ~reverse_cross_sections:parameters.reverse_cross_sections
      ~scale:parameters.scale ~roll:parameters.roll ~twist:parameters.twist
      ~caps:parameters.caps
      ?cap_group:(if parameters.caps then optional_text parameters.cap_group else None)
      ~uv_attribute:(optional_text parameters.uv_attribute)
      ~cross_section_prefix:parameters.cross_section_prefix
      ~backbone ~cross_section ())
  let factory = parameters_factory build
end

module Polywire = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    radius : float [@sop.default 0.1] [@sop.label "Radius"]
      [@sop.min 0.0001] [@sop.max 10.] [@sop.hard_min 0.];
    use_sides : bool [@sop.default true] [@sop.label "Set divisions"];
    sides : int [@sop.default 8] [@sop.label "Divisions"]
      [@sop.min 3] [@sop.max 256] [@sop.hard_min 3];
    divisions_attribute : string [@sop.default ""]
      [@sop.label "Divisions attribute"] [@sop.folder "Overrides"];
    segments : int [@sop.default 1] [@sop.label "Segments"]
      [@sop.min 1] [@sop.max 256] [@sop.hard_min 1];
    segments_attribute : string [@sop.default ""]
      [@sop.label "Segments attribute"] [@sop.folder "Overrides"];
    use_segment_scales : bool [@sop.default false]
      [@sop.label "Scale segment endpoints"];
    first_segment_scale : float [@sop.default 0.]
      [@sop.label "First segment scale"] [@sop.folder "Segments"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    last_segment_scale : float [@sop.default 1.]
      [@sop.label "Last segment scale"] [@sop.folder "Segments"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    segment_scales_attribute : string [@sop.default ""]
      [@sop.label "Segment scales attribute"] [@sop.folder "Overrides"];
    prevent_joint_buckling : bool [@sop.default false]
      [@sop.label "Prevent joint buckling"] [@sop.folder "Joints"];
    maximum_joint_scale : float [@sop.default 10.]
      [@sop.label "Maximum joint scale"] [@sop.folder "Joints"]
      [@sop.min 1.] [@sop.max 100.] [@sop.hard_min 1.];
    maximum_joint_scale_attribute : string [@sop.default ""]
      [@sop.label "Maximum scale attribute"] [@sop.folder "Overrides"];
    smooth_point : bool [@sop.default true] [@sop.label "Smooth points"]
      [@sop.folder "Joints"];
    smooth_attribute : string [@sop.default ""]
      [@sop.label "Smooth attribute"] [@sop.folder "Overrides"];
    use_max_valence : bool [@sop.default false]
      [@sop.label "Limit smooth valence"] [@sop.folder "Joints"];
    max_valence : int [@sop.default 4] [@sop.label "Maximum valence"]
      [@sop.folder "Joints"] [@sop.min 1] [@sop.max 128]
      [@sop.hard_min 1];
    scale_attribute : string [@sop.default ""] [@sop.label "Scale attribute"]
      [@sop.folder "Overrides"];
    seam_offset : int [@sop.default 0] [@sop.label "Seam offset"]
      [@sop.folder "Seams"] [@sop.min (-256)] [@sop.max 256];
    seam_attribute : string [@sop.default ""] [@sop.label "Seam attribute"]
      [@sop.folder "Overrides"];
    segment_seam_attribute : string [@sop.default ""]
      [@sop.label "Segment seam attribute"] [@sop.folder "Overrides"];
    v_attribute : string [@sop.default ""] [@sop.label "V attribute"]
      [@sop.folder "Overrides"];
    up_attribute : string [@sop.default ""] [@sop.label "Up attribute"]
      [@sop.folder "Overrides"];
    generate_uv : bool [@sop.default true] [@sop.label "Generate UV"]
      [@sop.folder "UV"];
    u_min : float [@sop.default 0.] [@sop.label "U minimum"]
      [@sop.folder "UV/U range"] [@sop.min (-10.)] [@sop.max 10.];
    u_max : float [@sop.default 1.] [@sop.label "U maximum"]
      [@sop.folder "UV/U range"] [@sop.min (-10.)] [@sop.max 10.];
    v_min : float [@sop.default 0.] [@sop.label "V minimum"]
      [@sop.folder "UV/V range"] [@sop.min (-10.)] [@sop.max 10.];
    v_max : float [@sop.default 1.] [@sop.label "V maximum"]
      [@sop.folder "UV/V range"] [@sop.min (-10.)] [@sop.max 10.];
    uv_range_attribute : string [@sop.default ""]
      [@sop.label "UV range attribute"] [@sop.folder "Overrides"];
    caps : bool [@sop.default false] [@sop.label "End caps"];
    cap_group : string [@sop.default "caps"] [@sop.label "Cap group"];
  } [@@sop.node_key "polywire"] [@@sop.node_label "PolyWire"]
    [@@sop.node_category "Topology/Surface"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let sides = if parameters.use_sides then Some parameters.sides else None
    and segment_scales = if parameters.use_segment_scales then Some
        (parameters.first_segment_scale, parameters.last_segment_scale)
      else None
    and max_valence = if parameters.use_max_valence
      then Some parameters.max_valence else None in
    Sop.polywire ~label ?group:(optional_text parameters.group) ?sides
      ?divisions_attribute:(optional_text parameters.divisions_attribute)
      ~segments:parameters.segments
      ?segments_attribute:(optional_text parameters.segments_attribute)
      ?segment_scales
      ?segment_scales_attribute:
        (optional_text parameters.segment_scales_attribute)
      ~prevent_joint_buckling:parameters.prevent_joint_buckling
      ~maximum_joint_scale:parameters.maximum_joint_scale
      ?maximum_joint_scale_attribute:
        (optional_text parameters.maximum_joint_scale_attribute)
      ~smooth_point:parameters.smooth_point
      ?smooth_attribute:(optional_text parameters.smooth_attribute)
      ?max_valence ?scale_attribute:(optional_text parameters.scale_attribute)
      ~seam_offset:parameters.seam_offset
      ?seam_attribute:(optional_text parameters.seam_attribute)
      ?segment_seam_attribute:
        (optional_text parameters.segment_seam_attribute)
      ?v_attribute:(optional_text parameters.v_attribute)
      ?up_attribute:(optional_text parameters.up_attribute)
      ~generate_uv:parameters.generate_uv
      ~u_range:(parameters.u_min, parameters.u_max)
      ~v_range:(parameters.v_min, parameters.v_max)
      ?uv_range_attribute:(optional_text parameters.uv_range_attribute)
      ~caps:parameters.caps
      ?cap_group:(if parameters.caps then optional_text parameters.cap_group else None)
      ~radius:parameters.radius input)
  let factory = parameters_factory build
end

module Poly_cut = struct
  type detection = All | Crossing | Change
  let element_parameter = Parameter.choice ~equal:( = ) [
      "Points", Rdk.Poly_cut.Poly_cut_points; "Edges", Rdk.Poly_cut.Poly_cut_edges;
    ]
  let strategy_parameter = Parameter.choice ~equal:( = ) [
      "Remove", Rdk.Poly_cut.Poly_cut_remove; "Cut", Rdk.Poly_cut.Poly_cut_cut;
    ]
  let detection_parameter = Parameter.choice ~equal:( = ) [
      "All selected", All; "Attribute crossing", Crossing;
      "Attribute change", Change;
    ]
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    cut_group : string [@sop.default ""] [@sop.label "Cut group"];
    element : Rdk.Poly_cut.element [@sop.default Rdk.Poly_cut.Poly_cut_points]
      [@sop.label "Cut elements"] [@sop.kind element_parameter];
    strategy : Rdk.Poly_cut.strategy
      [@sop.default Rdk.Poly_cut.Poly_cut_remove]
      [@sop.label "Strategy"] [@sop.kind strategy_parameter];
    detection : detection [@sop.default All] [@sop.label "Detection"]
      [@sop.folder "Detection"] [@sop.kind detection_parameter];
    attribute : string [@sop.default "cut"] [@sop.label "Attribute"]
      [@sop.folder "Detection"];
    value : float [@sop.default 0.5] [@sop.label "Crossing value"]
      [@sop.folder "Detection"] [@sop.min (-10.)] [@sop.max 10.];
    threshold : float [@sop.default 0.] [@sop.label "Change threshold"]
      [@sop.folder "Detection"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    keep_closed : bool [@sop.default true] [@sop.label "Keep closed"];
  } [@@sop.node_key "poly_cut"] [@@sop.node_label "Poly Cut"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let detection parameters = match parameters.detection with
    | All -> Rdk.Poly_cut.Poly_cut_all
    | Crossing -> Rdk.Poly_cut.Poly_cut_crossing {
        attribute = parameters.attribute; value = parameters.value }
    | Change -> Rdk.Poly_cut.Poly_cut_change {
        attribute = parameters.attribute; threshold = parameters.threshold }
  let build = parameters_build (fun ~label parameters input ->
    Sop.poly_cut ~label ?group:(optional_text parameters.group)
        ?cut_group:(optional_text parameters.cut_group)
        ~element:parameters.element ~strategy:parameters.strategy
        ~detection:(detection parameters) ~keep_closed:parameters.keep_closed
        input)
  let factory = parameters_factory build
end

module Rewire_vertices = struct
  type parameters = {
    selection_owner : element_owner [@sop.default Element_vertex]
      [@sop.label "Selection owner"] [@sop.kind element_owner_parameter];
    selection : string [@sop.default ""] [@sop.label "Selection group"];
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Vertex]
      [@sop.label "Target attribute owner"]
      [@sop.kind element_attribute_owner_parameter];
    target_attribute : string [@sop.default "target"]
      [@sop.label "Target attribute"];
    recursive : bool [@sop.default false] [@sop.label "Resolve recursively"];
    delete_target_attribute : bool [@sop.default true]
      [@sop.label "Delete target attribute"];
    keep_unused_points : bool [@sop.default false]
      [@sop.label "Keep unused points"];
    original_point_attribute : string [@sop.default ""]
      [@sop.label "Original point attribute"] [@sop.folder "Output"];
  } [@@sop.node_key "rewire_vertices"] [@@sop.node_label "Rewire Vertices"]
    [@@sop.node_category "Topology/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.rewire_vertices ~label
        ?selection:(optional_element_group parameters.selection_owner
          parameters.selection)
        ~recursive:parameters.recursive
        ~delete_target_attribute:parameters.delete_target_attribute
        ~keep_unused_points:parameters.keep_unused_points
        ?original_point_attribute:
          (optional_text parameters.original_point_attribute)
        ~owner:parameters.owner ~target_attribute:parameters.target_attribute
        input)
  let factory = parameters_factory build
end

module Blast_by_attribute = struct
  type mode = Below | Range | Width
  type output = Delete | Group
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Points", Rdk.Blast_by_attribute.Blast_points;
      "Primitives", Rdk.Blast_by_attribute.Blast_primitives;
    ]
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Below threshold", Below; "Range", Range; "Center and width", Width;
    ]
  let output_parameter = Parameter.choice ~equal:( = ) [
      "Delete elements", Delete; "Create group", Group;
    ]
  type parameters = {
    owner : Rdk.Blast_by_attribute.owner [@sop.default Rdk.Blast_by_attribute.Blast_points]
      [@sop.label "Owner"] [@sop.kind owner_parameter];
    attribute : string [@sop.default "mask"] [@sop.label "Attribute"];
    mode : mode [@sop.default Below] [@sop.label "Comparison"]
      [@sop.kind mode_parameter];
    threshold : float [@sop.default 0.5] [@sop.label "Threshold"]
      [@sop.folder "Comparison/Below"] [@sop.min (-10.)] [@sop.max 10.];
    minimum : float [@sop.default 0.] [@sop.label "Minimum"]
      [@sop.folder "Comparison/Range"] [@sop.min (-10.)] [@sop.max 10.];
    maximum : float [@sop.default 1.] [@sop.label "Maximum"]
      [@sop.folder "Comparison/Range"] [@sop.min (-10.)] [@sop.max 10.];
    center : float [@sop.default 0.5] [@sop.label "Center"]
      [@sop.folder "Comparison/Width"] [@sop.min (-10.)] [@sop.max 10.];
    width : float [@sop.default 0.5] [@sop.label "Width"]
      [@sop.folder "Comparison/Width"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    group : string [@sop.default ""] [@sop.label "Base group"];
    invert : bool [@sop.default false] [@sop.label "Invert selection"];
    output : output [@sop.default Delete] [@sop.label "Output"]
      [@sop.kind output_parameter];
    output_group : string [@sop.default "selected"]
      [@sop.label "Output group"] [@sop.folder "Output"];
    remove_unused_points : bool [@sop.default false]
      [@sop.label "Remove unused points"] [@sop.folder "Output"];
  } [@@sop.node_key "blast_by_attribute"]
    [@@sop.node_label "Blast by Attribute"]
    [@@sop.node_category "Topology/Delete"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let blast_mode parameters = match parameters.mode with
    | Below -> Rdk.Blast_by_attribute.Blast_below parameters.threshold
    | Range -> Rdk.Blast_by_attribute.Blast_range {
        minimum = parameters.minimum; maximum = parameters.maximum }
    | Width -> Rdk.Blast_by_attribute.Blast_width {
        center = parameters.center; width = parameters.width }
  let build = parameters_build (fun ~label parameters input ->
    let output = match parameters.output with
      | Delete -> Rdk.Blast_by_attribute.Blast_delete
      | Group -> Rdk.Blast_by_attribute.Blast_group parameters.output_group in
    Sop.blast_by_attribute ~label
      ?group:(optional_text parameters.group) ~invert:parameters.invert
      ~remove_unused_points:parameters.remove_unused_points
      ~owner:parameters.owner ~attribute:parameters.attribute
      ~mode:(blast_mode parameters) ~output input)
  let factory = parameters_factory build
end

module Blast = struct
  type parameters = {
    owner : Rdk.Group.owner [@sop.default Rdk.Group.Primitive]
      [@sop.label "Group type"] [@sop.kind ordinary_group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Group"];
    selected : bool [@sop.default true] [@sop.label "Delete selected"];
    compact_points : bool [@sop.default false]
      [@sop.label "Remove unused points"];
    policy : Rdk.Deletion.topology_policy
      [@sop.default Rdk.Deletion.Destroy_touched_primitives]
      [@sop.label "Point deletion policy"]
      [@sop.kind delete_topology_policy_parameter];
  } [@@sop.node_key "blast"] [@@sop.node_label "Blast"]
    [@@sop.node_category "Topology/Delete"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.blast ~label ~selected:parameters.selected
        ~compact_points:parameters.compact_points ~policy:parameters.policy
        ~owner:parameters.owner ~group:parameters.group input)
  let factory = parameters_factory build

  let create ?label:node_label ?(selected = parameters_default.selected)
      ?(compact_points = parameters_default.compact_points) ~owner ~group
      input =
    build ~label:(label "blast" node_label) ~inputs:[input]
      { parameters_default with selected; compact_points; owner; group }
end

module Compact_points = struct
  let factory = Edit_graph.factory ~key:"compact_points"
      ~label:"Compact Points" ~category:["Topology"; "Cleanup"] ~arity:1
      (function
        | [input] -> Sop.compact_points ~label:"compact-points" input
        | _ -> invalid_arg "Compact Points SOP expects one input")
end

module Triangulate_2d = struct
  type projection = Best_fit | XY | YZ | ZX | Plane | Point_attribute
  let projection_parameter = Parameter.choice ~equal:( = ) [
      "Best fit", Best_fit; "XY", XY; "YZ", YZ; "ZX", ZX;
      "Custom plane", Plane; "Point attribute", Point_attribute;
    ]
  type parameters = {
    point_group : string [@sop.default ""] [@sop.label "Point group"]
      [@sop.folder "Input"];
    constraint_edge_group : string [@sop.default ""]
      [@sop.label "Constraint edge group"] [@sop.folder "Input"];
    constraint_primitive_group : string [@sop.default ""]
      [@sop.label "Constraint primitive group"] [@sop.folder "Input"];
    projection : projection [@sop.default Best_fit] [@sop.label "Projection"]
      [@sop.folder "Projection"] [@sop.kind projection_parameter];
    plane_origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Projection/Plane"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "plane_origin"]
    plane_origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Projection/Plane"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "plane_origin"]
    plane_origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Projection/Plane"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "plane_origin"]
    plane_normal_x : float [@sop.default 0.] [@sop.label "Normal X"]
      [@sop.folder "Projection/Plane"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "plane_normal"]
    plane_normal_y : float [@sop.default 0.] [@sop.label "Normal Y"]
      [@sop.folder "Projection/Plane"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "plane_normal"]
    plane_normal_z : float [@sop.default 1.] [@sop.label "Normal Z"]
      [@sop.folder "Projection/Plane"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "plane_normal"]
    point_attribute : string [@sop.default "uv"] [@sop.label "Point attribute"]
      [@sop.folder "Projection"];
    seed : int [@sop.default 0] [@sop.label "Seed"]
      [@sop.folder "Triangulation"] [@sop.min 0] [@sop.max 9999];
    split_crossing_constraints : bool [@sop.default false]
      [@sop.label "Split crossing constraints"] [@sop.folder "Constraints"];
    flood_from_hull_boundary : bool [@sop.default false]
      [@sop.label "Flood from hull boundary"] [@sop.folder "Constraints"];
    remove_outside_constraint_polygons : bool [@sop.default false]
      [@sop.label "Remove outside constraints"] [@sop.folder "Constraints"];
    silhouette_constraints : bool [@sop.default false]
      [@sop.label "Silhouette constraints"] [@sop.folder "Constraints"];
    remove_outside_silhouette : bool [@sop.default false]
      [@sop.label "Remove outside silhouette"] [@sop.folder "Constraints"];
    ignore_non_constraint_points : bool [@sop.default false]
      [@sop.label "Ignore non-constraint points"] [@sop.folder "Constraints"];
    remove_duplicate_points : bool [@sop.default false]
      [@sop.label "Remove duplicate points"] [@sop.folder "Cleanup"];
    refine : bool [@sop.default false] [@sop.label "Refine"]
      [@sop.folder "Refinement"];
    allow_constraint_splitting : bool [@sop.default true]
      [@sop.label "Allow constraint splitting"] [@sop.folder "Refinement"];
    minimum_angle : float [@sop.default 0.3490658503988659]
      [@sop.label "Minimum angle"] [@sop.folder "Refinement"] [@sop.min 0.]
      [@sop.max 1.0471975511965976] [@sop.hard_min 0.];
    use_maximum_area : bool [@sop.default false] [@sop.label "Maximum area"]
      [@sop.folder "Refinement"];
    maximum_area : float [@sop.default 1.] [@sop.label "Area"]
      [@sop.folder "Refinement"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    use_target_edge_length : bool [@sop.default false]
      [@sop.label "Target edge length"] [@sop.folder "Refinement"];
    target_edge_length : float [@sop.default 1.] [@sop.label "Edge length"]
      [@sop.folder "Refinement"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    minimum_edge_length : float [@sop.default 0.]
      [@sop.label "Minimum edge length"] [@sop.folder "Refinement"]
      [@sop.min 0.] [@sop.max 100.] [@sop.hard_min 0.];
    maximum_new_points : int [@sop.default 100000]
      [@sop.label "Maximum new points"] [@sop.folder "Refinement/Limits"]
      [@sop.min 0] [@sop.max 1000000] [@sop.hard_min 0];
    regularization_steps : int [@sop.default 0]
      [@sop.label "Regularization steps"] [@sop.folder "Refinement"]
      [@sop.min 0] [@sop.max 100] [@sop.hard_min 0];
    allow_movement_of_interior_input_points : bool [@sop.default false]
      [@sop.label "Move interior input points"] [@sop.folder "Refinement"];
    preserve_point_payload : bool [@sop.default true]
      [@sop.label "Preserve point payload"] [@sop.folder "Payload"];
    restore_original_point_positions : bool [@sop.default true]
      [@sop.label "Restore original positions"] [@sop.folder "Payload"];
    keep_primitives : bool [@sop.default false] [@sop.label "Keep primitives"]
      [@sop.folder "Output"];
    remove_unused_points : bool [@sop.default false]
      [@sop.label "Remove unused points"] [@sop.folder "Cleanup"];
    recompute_point_normals : bool [@sop.default false]
      [@sop.label "Recompute point normals"] [@sop.folder "Output"];
    split_point_group : string [@sop.default ""]
      [@sop.label "Split point group"] [@sop.folder "Output"];
    refinement_point_group : string [@sop.default ""]
      [@sop.label "Refinement point group"] [@sop.folder "Output"];
    triangle_group : string [@sop.default ""] [@sop.label "Triangle group"]
      [@sop.folder "Output"];
    constraint_group : string [@sop.default ""]
      [@sop.label "Constraint group"] [@sop.folder "Output"];
  } [@@sop.node_key "triangulate_2d"] [@@sop.node_label "Triangulate 2D"]
    [@@sop.node_category "Topology/Triangulate"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let projection parameters = match parameters.projection with
    | Best_fit -> Rdk.Triangulate2d.Best_fit
    | XY -> Rdk.Triangulate2d.Plane_xy
    | YZ -> Rdk.Triangulate2d.Plane_yz
    | ZX -> Rdk.Triangulate2d.Plane_zx
    | Plane -> Rdk.Triangulate2d.Plane {
        origin = Vec3.create parameters.plane_origin_x parameters.plane_origin_y
          parameters.plane_origin_z;
        normal = Vec3.create parameters.plane_normal_x parameters.plane_normal_y
          parameters.plane_normal_z }
    | Point_attribute ->
        Rdk.Triangulate2d.Point_attribute parameters.point_attribute
  let build = parameters_build (fun ~label parameters input ->
    Sop.triangulate_2d ~label
        ?point_group:(optional_text parameters.point_group)
        ?constraint_edge_group:(optional_text parameters.constraint_edge_group)
        ?constraint_primitive_group:
          (optional_text parameters.constraint_primitive_group)
        ~projection:(projection parameters) ~seed:(Int64.of_int parameters.seed)
        ~split_crossing_constraints:parameters.split_crossing_constraints
        ~flood_from_hull_boundary:parameters.flood_from_hull_boundary
        ~remove_outside_constraint_polygons:
          parameters.remove_outside_constraint_polygons
        ~silhouette_constraints:parameters.silhouette_constraints
        ~remove_outside_silhouette:parameters.remove_outside_silhouette
        ~ignore_non_constraint_points:parameters.ignore_non_constraint_points
        ~remove_duplicate_points:parameters.remove_duplicate_points
        ~refine:parameters.refine
        ~allow_constraint_splitting:parameters.allow_constraint_splitting
        ~minimum_angle:parameters.minimum_angle
        ?maximum_area:(if parameters.use_maximum_area
          then Some parameters.maximum_area else None)
        ?target_edge_length:(if parameters.use_target_edge_length
          then Some parameters.target_edge_length else None)
        ~minimum_edge_length:parameters.minimum_edge_length
        ~maximum_new_points:parameters.maximum_new_points
        ~regularization_steps:parameters.regularization_steps
        ~allow_movement_of_interior_input_points:
          parameters.allow_movement_of_interior_input_points
        ~preserve_point_payload:parameters.preserve_point_payload
        ~restore_original_point_positions:
          parameters.restore_original_point_positions
        ~keep_primitives:parameters.keep_primitives
        ~remove_unused_points:parameters.remove_unused_points
        ~recompute_point_normals:parameters.recompute_point_normals
        ?split_point_group:(optional_text parameters.split_point_group)
        ?refinement_point_group:
          (optional_text parameters.refinement_point_group)
        ?triangle_group:(optional_text parameters.triangle_group)
        ?constraint_group:(optional_text parameters.constraint_group) input)
  let factory = parameters_factory build
end
