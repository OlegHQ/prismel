(* Topology nodes, declared once: the record is the editor schema, the
   factory and the typed [Sop] constructor. *)

open Sop_support

(* ocamldep must see the PPX's [Procedural.X] resolve inside this library. *)
module Procedural = Sop_support.Procedural

module Edge_divide = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"] [@sop.nonblank "empty edge group name"];
    divisions : int [@sop.default 2] [@sop.label "Divisions"]
      [@sop.min 1] [@sop.max 64] [@sop.hard_min 1] [@sop.validate "divisions must be positive"];
    share_points : bool [@sop.default true] [@sop.label "Share points"];
  } [@@sop.node_key "edge_divide"] [@@sop.node_label "Edge Divide"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@sop.fn "edge_divide"] [@@sop.args "?group ?divisions ?share_points in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let group = optional_text parameters.group in
    let divisions = parameters.divisions in
    let share_points = parameters.share_points in
    Node.Private.make ?label ~operation:"edge_divide" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        let edges = match group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_edge_group name inputs.(0) with
               | Some group -> Ok (Some group)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf
                      "edge_divide could not find native edge group %S" name))) in
        match edges with
        | Error error -> Error error
        | Ok edges ->
            match Rdk.Subdivide.edge_divide ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?edges ~divisions ~share_points
                inputs.(0) with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
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
    group : string [@sop.default ""] [@sop.label "Edge group"] [@sop.nonblank "empty edge group name"];
    connectivity_attribute : string [@sop.default ""]
      [@sop.label "Connectivity attribute"] [@sop.nonblank "empty connectivity attribute name"];
    position : Rdk.Fuse_reduce.position
      [@sop.default Rdk.Fuse_reduce.Average_position]
      [@sop.label "Position"] [@sop.kind position_parameter];
    remove_degenerate_primitives : bool [@sop.default true]
      [@sop.label "Remove degenerate primitives"] [@sop.folder "Cleanup"];
    recompute_point_normals : bool [@sop.default true]
      [@sop.label "Recompute point normals"] [@sop.folder "Cleanup"];
  } [@@sop.node_key "edge_collapse"] [@@sop.node_label "Edge Collapse"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@sop.fn "edge_collapse"] [@@sop.args "?group ?connectivity_attribute ?position ?remove_degenerate_primitives ?recompute_point_normals in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let group = optional_text parameters.group in
    let connectivity_attribute = optional_text
          parameters.connectivity_attribute in
    let position = parameters.position in
    let remove_degenerate_primitives = parameters.remove_degenerate_primitives in
    let recompute_point_normals = parameters.recompute_point_normals in
    Node.Private.make ?label ~operation:"edge_collapse" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        let geometry = inputs.(0) in
        let edges = match group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_edge_group name geometry with
               | Some edges -> Ok (Some edges)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf
                      "edge_collapse could not find native edge group %S" name))) in
        match edges with
        | Error error -> Error error
        | Ok edges ->
            match Rdk.Edge_collapse.run ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?edges ?connectivity_attribute
                ~position
                ~remove_degenerate_primitives ~recompute_point_normals geometry with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
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
      [@sop.label "Remove inline points"] [@sop.folder "Cleanup"] [@sop.arg_default (false)];
    collinearity_tolerance : float [@sop.default 1e-6]
      [@sop.label "Collinearity tolerance"] [@sop.folder "Cleanup"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.] [@sop.arg_default (0.)];
    remove_unused_points : bool [@sop.default true]
      [@sop.label "Remove unused points"] [@sop.folder "Cleanup"];
    create_boundary_curves : bool [@sop.default false]
      [@sop.label "Create boundary curves"];
    recompute_normals : bool [@sop.default true]
      [@sop.label "Recompute normals"] [@sop.folder "Cleanup"];
  } [@@sop.node_key "dissolve"] [@@sop.node_label "Dissolve"]
    [@@sop.node_category "Topology"] [@@sop.node_inputs 1]
    [@@sop.fn "dissolve"] [@@sop.args "?group ?operation ?bridge_policy ?remove_inline_points ?collinearity_tolerance ?remove_unused_points ?create_boundary_curves ?recompute_normals in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let group = optional_text parameters.group in
    let operation = parameters.operation in
    let bridge_policy = parameters.bridge_policy in
    let remove_inline_points = parameters.remove_inline_points in
    let collinearity_tolerance = parameters.collinearity_tolerance in
    let remove_unused_points = parameters.remove_unused_points in
    let create_boundary_curves = parameters.create_boundary_curves in
    let recompute_normals = parameters.recompute_normals in
    Node.Private.make ?label ~operation:"dissolve" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0)
      ~dependencies:Context.Dependencies.static ~inputs:[|input|]
      (fun ~node_id:_ context inputs ->
        let edges = match group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_edge_group name inputs.(0) with
               | Some value -> Ok (Some value)
               | None -> Error (Diagnostic.error ~code:"missing_edge_group"
                   (Printf.sprintf "dissolve could not find edge group %S" name))) in
        match edges with
        | Error error -> Error error
        | Ok edges ->
            match Rdk.Dissolve.run ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?edges ~operation ~bridge_policy
                ~remove_inline_points ~collinearity_tolerance
                ~remove_unused_points ~create_boundary_curves ~recompute_normals
                inputs.(0) with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Triangulate = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"] [@sop.nonblank "empty primitive group name"];
  } [@@sop.node_key "triangulate"] [@@sop.node_label "Triangulate"]
    [@@sop.node_category "Topology"] [@@sop.node_inputs 1]
    [@@sop.fn "triangulate"] [@@sop.args "?group in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let group = optional_text parameters.group in
    Node.Private.make ?label ~operation:"triangulate" ~version:2
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        let geometry = inputs.(0) in
        let primitives = match group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive name geometry with
               | Some group -> Ok (Some group)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf
                      "triangulate could not find primitive group %S" name))) in
        match primitives with
        | Error error -> Error error
        | Ok primitives ->
            match Rdk.Triangulate.run ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?primitives geometry with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build

end


module Edge_flip = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"] [@sop.nonblank "empty edge group name"];
    cycles : int [@sop.default 1] [@sop.label "Cycles"]
      [@sop.min 0] [@sop.max 16] [@sop.hard_min 0] [@sop.validate "cycles must be non-negative"];
    cycle_vertex_attributes : bool [@sop.default true]
      [@sop.label "Cycle vertex attributes"];
    recompute_point_normals : bool [@sop.default false]
      [@sop.label "Recompute point normals"];
  } [@@sop.node_key "edge_flip"] [@@sop.node_label "Edge Flip"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@sop.fn "edge_flip"] [@@sop.args "?group ?cycles ?cycle_vertex_attributes ?recompute_point_normals in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let group = optional_text parameters.group in
    let cycles = parameters.cycles in
    let cycle_vertex_attributes = parameters.cycle_vertex_attributes in
    let recompute_point_normals = parameters.recompute_point_normals in
    Node.Private.make ?label ~operation:"edge_flip" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        let geometry = inputs.(0) in
        let edges = match group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_edge_group name geometry with
               | Some edges -> Ok (Some edges)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf
                      "edge_flip could not find native edge group %S" name))) in
        match edges with
        | Error error -> Error error
        | Ok edges ->
            match Rdk.Edge_flip.run ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?edges ~cycles
                ~cycle_vertex_attributes ~recompute_point_normals geometry with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Edge_cusp = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"] [@sop.nonblank "empty edge group name"];
    update_point_normals : bool [@sop.default true]
      [@sop.label "Update point normals"];
  } [@@sop.node_key "edge_cusp"] [@@sop.node_label "Edge Cusp"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@sop.fn "edge_cusp"] [@@sop.args "?group ?update_point_normals in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let group = optional_text parameters.group in
    let update_point_normals = parameters.update_point_normals in
    Node.Private.make ?label ~operation:"edge_cusp" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        let geometry = inputs.(0) in
        let edges = match group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_edge_group name geometry with
               | Some edges -> Ok (Some edges)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf
                      "edge_cusp could not find native edge group %S" name))) in
        match edges with
        | Error error -> Error error
        | Ok edges ->
            match Rdk.Facet.edge_cusp ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?edges ~update_point_normals
                geometry with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Edge_straighten = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"] [@sop.nonblank "empty edge group name"];
    output_group : string [@sop.default ""] [@sop.label "Output group"] [@sop.nonblank "empty output edge group name"];
  } [@@sop.node_key "edge_straighten"] [@@sop.node_label "Edge Straighten"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@sop.fn "edge_straighten"] [@@sop.args "?group ?output_group in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let group = optional_text parameters.group in
    let output_group = optional_text parameters.output_group in
    Node.Private.make ?label ~operation:"edge_straighten" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        let geometry = inputs.(0) in
        let edges = match group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_edge_group name geometry with
               | Some edges -> Ok (Some edges)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf
                      "edge_straighten could not find native edge group %S" name))) in
        match edges with
        | Error error -> Error error
        | Ok edges ->
            match Rdk.Edge_ops.straighten ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?edges ?output_group geometry with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Poly_extrude = struct
  let divide_parameter = Parameter.choice ~equal:( = ) [
      "Individual elements", Rdk.Poly_extrude.Extrude_individual;
      "Connected components", Rdk.Poly_extrude.Extrude_connected_components;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"] [@sop.nonblank "empty selection group name"];
    split_edges : string [@sop.default ""] [@sop.label "Split edge group"] [@sop.nonblank "empty split edge group name"];
    distance : float [@sop.default 0.1] [@sop.label "Distance"]
      [@sop.min (-10.)] [@sop.max 10.];
    divide : Rdk.Poly_extrude.divide
      [@sop.default Rdk.Poly_extrude.Extrude_individual]
      [@sop.label "Divide into"] [@sop.kind divide_parameter];
    divisions : int [@sop.default 1] [@sop.label "Divisions"]
      [@sop.min 1] [@sop.max 64] [@sop.hard_min 1] [@sop.validate "divisions must be positive"];
    output_front : bool [@sop.default true] [@sop.label "Output front"]
      [@sop.folder "Output"];
    output_back : bool [@sop.default true] [@sop.label "Output back"]
      [@sop.folder "Output"];
    output_side : bool [@sop.default true] [@sop.label "Output side"]
      [@sop.folder "Output"];
    front_group : string [@sop.default ""] [@sop.label "Front group"]
      [@sop.folder "Groups"] [@sop.nonblank "empty front group name"];
    back_group : string [@sop.default ""] [@sop.label "Back group"]
      [@sop.folder "Groups"] [@sop.nonblank "empty back group name"];
    side_group : string [@sop.default ""] [@sop.label "Side group"]
      [@sop.folder "Groups"] [@sop.nonblank "empty side group name"];
    front_boundary_group : string [@sop.default ""]
      [@sop.label "Front boundary group"] [@sop.folder "Groups"] [@sop.nonblank "empty front boundary group name"];
    back_boundary_group : string [@sop.default ""]
      [@sop.label "Back boundary group"] [@sop.folder "Groups"] [@sop.nonblank "empty back boundary group name"];
  } [@@sop.node_key "poly_extrude"] [@@sop.node_label "Poly Extrude"]
    [@@sop.node_category "Topology/Polygon"] [@@sop.node_inputs 1]
    [@@sop.fn "poly_extrude"] [@@sop.args "?group ?split_edges ?divide ?divisions ?output_front ?output_back ?output_side ?front_group ?back_group ?side_group ?front_boundary_group ?back_boundary_group ~distance in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let group = optional_text parameters.group in
    let split_edges = optional_text parameters.split_edges in
    let divide = parameters.divide in
    let divisions = parameters.divisions in
    let output_front = parameters.output_front in
    let output_back = parameters.output_back in
    let output_side = parameters.output_side in
    let front_group = optional_text parameters.front_group in
    let back_group = optional_text parameters.back_group in
    let side_group = optional_text parameters.side_group in
    let front_boundary_group = optional_text parameters.front_boundary_group in
    let back_boundary_group = optional_text parameters.back_boundary_group in
    let distance = parameters.distance in
    Node.Private.make ?label ~operation:"poly_extrude" ~version:2
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0)
      ~dependencies:Context.Dependencies.static ~inputs:[|input|]
      (fun ~node_id:_ context inputs ->
        let geometry = inputs.(0) in
        let primitives = match group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive name geometry with
               | Some group -> Ok (Some group)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf
                     "poly_extrude could not find primitive group %S" name))) in
        let split = match split_edges with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_edge_group name geometry with
               | Some group -> Ok (Some group)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf
                     "poly_extrude could not find edge split group %S" name))) in
        match primitives, split with
        | Error error, _ | _, Error error -> Error error
        | Ok primitives, Ok split_edges ->
            match Rdk.Poly_extrude.run ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?primitives ?split_edges ~divide
                ~divisions ~output_front ~output_back ~output_side ?front_group
                ?back_group ?side_group ?front_boundary_group
                ?back_boundary_group ~distance geometry with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Poly_fill = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Single polygon", Rdk.Poly_fill.Fill_single_polygon;
      "Triangles", Rdk.Poly_fill.Fill_triangles;
      "Triangle fan", Rdk.Poly_fill.Fill_triangle_fan;
    ]

  type parameters = {
    boundary_group : string [@sop.default ""] [@sop.label "Boundary group"] [@sop.nonblank "empty boundary group name"];
    mode : Rdk.Poly_fill.mode [@sop.default Rdk.Poly_fill.Fill_triangles]
      [@sop.label "Fill mode"] [@sop.kind mode_parameter];
    reverse_patches : bool [@sop.default false]
      [@sop.label "Reverse patches"];
    unique_points : bool [@sop.default false] [@sop.label "Unique points"];
    update_point_normals : bool [@sop.default false]
      [@sop.label "Update point normals"];
    patch_group : string [@sop.default ""] [@sop.label "Patch group"] [@sop.nonblank "empty patch group name"];
  } [@@sop.node_key "poly_fill"] [@@sop.node_label "Poly Fill"]
    [@@sop.node_category "Topology/Polygon"] [@@sop.node_inputs 1]
    [@@sop.fn "poly_fill"] [@@sop.args "?boundary_group ?mode ?reverse_patches ?unique_points ?update_point_normals ?patch_group in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let boundary_group = optional_text parameters.boundary_group in
    let mode = parameters.mode in
    let reverse_patches = parameters.reverse_patches in
    let unique_points = parameters.unique_points in
    let update_point_normals = parameters.update_point_normals in
    let patch_group = optional_text parameters.patch_group in
    Node.Private.make ?label ~operation:"poly_fill" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0)
      ~dependencies:Context.Dependencies.static ~inputs:[|input|]
      (fun ~node_id:_ context inputs ->
        let geometry = inputs.(0) in
        let boundary = match boundary_group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_edge_group name geometry with
               | Some group -> Ok (Some group)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf
                     "poly_fill could not find boundary edge group %S" name))) in
        match boundary with
        | Error error -> Error error
        | Ok boundary ->
            match Rdk.Poly_fill.run ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?boundary ~mode ~reverse_patches
                ~unique_points ~update_point_normals ?patch_group geometry with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Convert_line = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"] [@sop.nonblank "empty edge group name"];
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
      [@sop.label "Length attribute"] [@sop.nonblank "empty length attribute name"];
  } [@@sop.node_key "convert_line"] [@@sop.node_label "Convert Line"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@sop.fn "convert_line"] [@@sop.args "?group ?connect_path ?maximum_distance ?connect_only_to_other_end_points ?make_isolated_loops_closed ?remove_unused_points ?length_attribute in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let group = optional_text parameters.group in
    let connect_path = parameters.connect_path in
    let maximum_distance = parameters.maximum_distance in
    let connect_only_to_other_end_points = parameters.connect_only_to_other_end_points in
    let make_isolated_loops_closed = parameters.make_isolated_loops_closed in
    let remove_unused_points = parameters.remove_unused_points in
    let length_attribute = optional_text parameters.length_attribute in
    Node.Private.make ?label ~operation:"convert_line" ~version:2
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        let edges = match group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_edge_group name inputs.(0) with
               | Some group -> Ok (Some group)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   ~hints:["Create the native edge group before Convert Line"]
                   (Printf.sprintf "convert_line could not find edge group %S"
                     name))) in
        match edges with
        | Error _ as error -> error
        | Ok edges ->
            match Rdk.Curve_topology.convert_line ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?edges ~connect_path
                ~maximum_distance ~connect_only_to_other_end_points
                ~make_isolated_loops_closed ~remove_unused_points
                ?length_attribute inputs.(0) with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Blast = struct
  type parameters = {
    owner : Rdk.Group.owner [@sop.default Rdk.Group.Primitive]
      [@sop.label "Group type"] [@sop.kind ordinary_group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Group"] [@sop.nonblank "empty group name"];
    selected : bool [@sop.default true] [@sop.label "Delete selected"];
    compact_points : bool [@sop.default false]
      [@sop.label "Remove unused points"];
    policy : Rdk.Deletion.topology_policy
      [@sop.default Rdk.Deletion.Destroy_touched_primitives]
      [@sop.label "Point deletion policy"]
      [@sop.kind delete_topology_policy_parameter];
  } [@@sop.node_key "blast"] [@@sop.node_label "Blast"]
    [@@sop.node_category "Topology/Delete"] [@@sop.node_inputs 1]
    [@@sop.fn "blast"] [@@sop.args "?selected ?compact_points ?policy ~owner ~group in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let selected = parameters.selected in
    let compact_points = parameters.compact_points in
    let policy = parameters.policy in
    let owner = parameters.owner in
    let group = parameters.group in
    Node.Private.make ?label ~operation:"blast" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Geometry.find_group ~owner group inputs.(0) with
        | None -> Error (Diagnostic.error ~code:"missing_group"
            ~hints:["Create the typed group before Blast or correct its owner/name"]
            (Printf.sprintf "blast could not find %s group %S"
              (group_owner_key owner) group))
        | Some selection ->
            match Rdk.Deletion.delete ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ~selected ~compact_points ~policy
                selection inputs.(0) with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )
  let factory = parameters_factory build

  let create ?label:node_label ?(selected = parameters_default.selected)
      ?(compact_points = parameters_default.compact_points) ~owner ~group
      input =
    build ~label:(label "blast" node_label) ~inputs:[input]
      { parameters_default with selected; compact_points; owner; group }
  let fn = parameters_fn build
end

