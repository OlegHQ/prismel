open Prismel
open Procedural
open Shared


module Group_edges = struct
  let incidence_parameter = Parameter.choice ~equal:( = ) [
      "Any", Pdk.Group_mesh.Any_edge; "Boundary", Pdk.Group_mesh.Boundary_edge;
      "Manifold", Pdk.Group_mesh.Manifold_edge;
      "Non-manifold", Pdk.Group_mesh.Non_manifold_edge;
    ]
  let angle_basis_parameter = Parameter.choice ~equal:( = ) [
      "Primitive dihedral", Pdk.Group_mesh.Primitive_dihedral;
      "Incident edges", Pdk.Group_mesh.Incident_edges;
    ]
  type parameters = {
    name : string [@sop.default "edges"] [@sop.label "Group name"];
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    incidence : Pdk.Group_mesh.incidence [@sop.default Pdk.Group_mesh.Any_edge]
      [@sop.label "Incidence"] [@sop.kind incidence_parameter];
    use_min_length : bool [@sop.default false] [@sop.label "Minimum length"]
      [@sop.folder "Length"];
    min_length : float [@sop.default 0.] [@sop.label "Minimum"]
      [@sop.folder "Length"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    use_max_length : bool [@sop.default false] [@sop.label "Maximum length"]
      [@sop.folder "Length"];
    max_length : float [@sop.default 1.] [@sop.label "Maximum"]
      [@sop.folder "Length"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    angle_basis : Pdk.Group_mesh.angle_basis
      [@sop.default Pdk.Group_mesh.Primitive_dihedral]
      [@sop.label "Angle basis"] [@sop.folder "Angle"]
      [@sop.kind angle_basis_parameter];
    use_min_angle : bool [@sop.default false] [@sop.label "Minimum angle"]
      [@sop.folder "Angle"];
    min_angle : float [@sop.default 0.] [@sop.label "Minimum"]
      [@sop.folder "Angle"] [@sop.min 0.] [@sop.max 3.141592653589793];
    use_max_angle : bool [@sop.default false] [@sop.label "Maximum angle"]
      [@sop.folder "Angle"];
    max_angle : float [@sop.default 3.141592653589793]
      [@sop.label "Maximum"] [@sop.folder "Angle"] [@sop.min 0.]
      [@sop.max 3.141592653589793];
  } [@@sop.node_key "group_edges"] [@@sop.node_label "Group Edges"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_edges ~label ~name:parameters.name
        ?group:(optional_text parameters.group) ~incidence:parameters.incidence
        ?min_length:(if parameters.use_min_length then Some parameters.min_length
          else None)
        ?max_length:(if parameters.use_max_length then Some parameters.max_length
          else None)
        ~angle_basis:parameters.angle_basis
        ?min_angle:(if parameters.use_min_angle then Some parameters.min_angle
          else None)
        ?max_angle:(if parameters.use_max_angle then Some parameters.max_angle
          else None) input)
  let factory = parameters_factory build
end

module Group_random = struct
  type parameters = {
    owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "random"] [@sop.label "Group name"];
    probability : float [@sop.default 0.5] [@sop.label "Probability"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    context_seed : bool [@sop.default false] [@sop.label "Use context seed"]
      [@sop.folder "Random"];
    seed : int [@sop.default 0] [@sop.label "Seed"]
      [@sop.folder "Random"] [@sop.min 0] [@sop.max 9999];
    seed_attribute : string [@sop.default ""] [@sop.label "Seed attribute"]
      [@sop.folder "Random"];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"];
    merge : Pdk.Group_ops.boolean_operation
      [@sop.default Pdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_random"] [@@sop.node_label "Group Random"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_random ~label
        ?seed:(if parameters.context_seed then None else Some parameters.seed)
        ?seed_attribute:(optional_text parameters.seed_attribute)
        ?base:(optional_text parameters.base) ~merge:parameters.merge
        ~probability:parameters.probability ~owner:parameters.owner
        ~name:parameters.name input)
  let factory = parameters_factory build

  let create ?label:node_label ?(seed = parameters_default.seed) ~probability
      ~owner ~name input =
    build ~label:(label "group-random" node_label) ~inputs:[input]
      { parameters_default with seed; probability; owner; name }
end

module Group_bounds = struct
  type shape = Box | Sphere
  let shape_parameter = Parameter.choice ~equal:( = ) [
      "Box", Box; "Sphere", Sphere;
    ]
  let containment_parameter = Parameter.choice ~equal:( = ) [
      "Fully contained", Pdk.Group_ops.Fully_contained;
      "Partially contained", Pdk.Group_ops.Partially_contained;
    ]
  type parameters = {
    owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "bounds"] [@sop.label "Group name"];
    shape : shape [@sop.default Box] [@sop.label "Bounding shape"]
      [@sop.kind shape_parameter];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Bounds/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Bounds/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Bounds/Center"] [@sop.min (-10.)] [@sop.max 10.];
    size_x : float [@sop.default 1.] [@sop.label "Size X"]
      [@sop.folder "Bounds/Size"] [@sop.min 0.] [@sop.max 20.]
      [@sop.hard_min 0.];
    size_y : float [@sop.default 1.] [@sop.label "Size Y"]
      [@sop.folder "Bounds/Size"] [@sop.min 0.] [@sop.max 20.]
      [@sop.hard_min 0.];
    size_z : float [@sop.default 1.] [@sop.label "Size Z"]
      [@sop.folder "Bounds/Size"] [@sop.min 0.] [@sop.max 20.]
      [@sop.hard_min 0.];
    radius : float [@sop.default 0.5] [@sop.label "Radius"]
      [@sop.folder "Bounds"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"];
    containment : Pdk.Group_ops.containment
      [@sop.default Pdk.Group_ops.Fully_contained] [@sop.label "Containment"]
      [@sop.folder "Combine"] [@sop.kind containment_parameter];
    merge : Pdk.Group_ops.boolean_operation
      [@sop.default Pdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_bounds"] [@@sop.node_label "Group by Bounds"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let bounds parameters =
    let center = Vec3.create parameters.center_x parameters.center_y
        parameters.center_z in
    match parameters.shape with
    | Sphere -> Pdk.Group_ops.Bounds_sphere { center; radius = parameters.radius }
    | Box -> let half = Vec3.create (parameters.size_x *. 0.5)
          (parameters.size_y *. 0.5) (parameters.size_z *. 0.5) in
        Pdk.Group_ops.Bounds_box { minimum = Vec3.sub center half;
          maximum = Vec3.add center half }
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_bounds ~label ?base:(optional_text parameters.base)
        ~containment:parameters.containment ~merge:parameters.merge
        (bounds parameters) ~owner:parameters.owner ~name:parameters.name input)
  let factory = parameters_factory build
end

module Group_normal = struct
  type parameters = {
    owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_primitives]
      [@sop.label "Group type"] [@sop.kind group_normal_owner_parameter];
    name : string [@sop.default "normal"] [@sop.label "Group name"];
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.];
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.];
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.];
    spread_angle : float [@sop.default 0.7853981633974483]
      [@sop.label "Spread angle"] [@sop.min 0.]
      [@sop.max 3.141592653589793] [@sop.hard_min 0.]
      [@sop.hard_max 3.141592653589793];
    normal_attribute : string [@sop.default ""] [@sop.label "Normal attribute"]
      [@sop.folder "Normals"];
    use_existing_normal : bool [@sop.default true]
      [@sop.label "Use existing normal"] [@sop.folder "Normals"];
    include_opposite : bool [@sop.default false]
      [@sop.label "Include opposite"] [@sop.folder "Normals"];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"];
    merge : Pdk.Group_ops.boolean_operation
      [@sop.default Pdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_normal"] [@@sop.node_label "Group by Normal"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_normal ~label
        ?normal_attribute:(optional_text parameters.normal_attribute)
        ~use_existing_normal:parameters.use_existing_normal
        ?base:(optional_text parameters.base)
        ~include_opposite:parameters.include_opposite ~merge:parameters.merge
        ~direction:(Vec3.create parameters.direction_x parameters.direction_y
          parameters.direction_z) ~spread_angle:parameters.spread_angle
        ~owner:parameters.owner ~name:parameters.name input)
  let factory = parameters_factory build
end

module Group_non_planar = struct
  type parameters = {
    name : string [@sop.default "nonplanar"] [@sop.label "Group name"];
    tolerance : float [@sop.default 1e-6] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"];
    merge : Pdk.Group_ops.boolean_operation
      [@sop.default Pdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_non_planar"] [@@sop.node_label "Group Non-Planar"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_non_planar ~label
        ?base:(optional_text parameters.base) ~merge:parameters.merge
        ~tolerance:parameters.tolerance ~name:parameters.name input)
  let factory = parameters_factory build
end

module Group_backface = struct
  type parameters = {
    name : string [@sop.default "backface"] [@sop.label "Group name"];
    viewpoint_x : float [@sop.default 0.] [@sop.label "Viewpoint X"]
      [@sop.folder "Viewpoint"] [@sop.min (-100.)] [@sop.max 100.];
    viewpoint_y : float [@sop.default 0.] [@sop.label "Viewpoint Y"]
      [@sop.folder "Viewpoint"] [@sop.min (-100.)] [@sop.max 100.];
    viewpoint_z : float [@sop.default 10.] [@sop.label "Viewpoint Z"]
      [@sop.folder "Viewpoint"] [@sop.min (-100.)] [@sop.max 100.];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"];
    merge : Pdk.Group_ops.boolean_operation
      [@sop.default Pdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_backface"] [@@sop.node_label "Group Backfaces"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_backface ~label ?base:(optional_text parameters.base)
        ~merge:parameters.merge
        ~viewpoint:(Vec3.create parameters.viewpoint_x parameters.viewpoint_y
          parameters.viewpoint_z) ~name:parameters.name input)
  let factory = parameters_factory build
end

module Group_edge_depth = struct
  type parameters = {
    point_group : string [@sop.default "seed"] [@sop.label "Seed point group"];
    name : string [@sop.default "depth"] [@sop.label "Output group"];
    depth : int [@sop.default 1] [@sop.label "Depth"] [@sop.min 0]
      [@sop.max 100] [@sop.hard_min 0];
    merge : Pdk.Group_ops.boolean_operation
      [@sop.default Pdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_edge_depth"] [@@sop.node_label "Group Edge Depth"]
    [@@sop.node_category "Group/Expand"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_edge_depth ~label ~merge:parameters.merge
        ~depth:parameters.depth ~point_group:parameters.point_group
        ~name:parameters.name input)
  let factory = parameters_factory build
end

module Group_unshared = struct
  type parameters = {
    owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_edges]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "unshared"] [@sop.label "Group name"];
    merge : Pdk.Group_ops.boolean_operation
      [@sop.default Pdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_unshared"] [@@sop.node_label "Group Unshared"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_unshared ~label ~merge:parameters.merge
        ~owner:parameters.owner ~name:parameters.name input)
  let factory = parameters_factory build
end

module Group_boundary_components = struct
  let conflict_parameter = Parameter.choice ~equal:( = ) [
      "Replace", Pdk.Group_ops.Name_replace; "Union", Pdk.Group_ops.Name_union;
    ]
  type parameters = {
    prefix : string [@sop.default "boundary"] [@sop.label "Group prefix"];
    conflict : Pdk.Group_ops.name_conflict
      [@sop.default Pdk.Group_ops.Name_replace] [@sop.label "Conflict"]
      [@sop.kind conflict_parameter];
    max_groups : int [@sop.default 4096] [@sop.label "Maximum groups"]
      [@sop.folder "Limits"] [@sop.min 1] [@sop.max 16384]
      [@sop.hard_min 1];
    max_payload_bytes : int [@sop.default 268435456]
      [@sop.label "Maximum payload bytes"] [@sop.folder "Limits"]
      [@sop.min 1048576] [@sop.max 1073741824] [@sop.hard_min 1];
  } [@@sop.node_key "group_boundary_components"]
    [@@sop.node_label "Group Boundary Components"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_boundary_components ~label ~prefix:parameters.prefix
        ~conflict:parameters.conflict ~max_groups:parameters.max_groups
        ~max_payload_bytes:parameters.max_payload_bytes input)
  let factory = parameters_factory build
end

module Group_from_attribute_boundary = struct
  type parameters = {
    owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_edges]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "attribute_boundary"]
      [@sop.label "Group name"];
    attributes : Pdk.Group_ops.boundary_attribute list [@sop.default []]
      [@sop.label "Attributes (owner, pattern)"]
      [@sop.kind boundary_attributes_parameter];
    tolerance : float [@sop.default 0.00001] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    include_unshared_edges : bool [@sop.default false]
      [@sop.label "Include unshared edges"];
    include_all_unshared_curve_edges : bool [@sop.default false]
      [@sop.label "Include all unshared curve edges"];
    include_all_primitives_sharing_boundary_points : bool [@sop.default false]
      [@sop.label "Include primitives sharing boundary points"];
  } [@@sop.node_key "group_from_attribute_boundary"]
    [@@sop.node_label "Group from Attribute Boundary"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_from_attribute_boundary ~label
        ~attributes:parameters.attributes ~tolerance:parameters.tolerance
        ~include_unshared_edges:parameters.include_unshared_edges
        ~include_all_unshared_curve_edges:
          parameters.include_all_unshared_curve_edges
        ~include_all_primitives_sharing_boundary_points:
          parameters.include_all_primitives_sharing_boundary_points
        ~owner:parameters.owner ~name:parameters.name input)
  let factory = parameters_factory build
end

module Groups_from_name = struct
  let conflict_parameter = Parameter.choice ~equal:( = ) [
      "Replace", Pdk.Group_ops.Name_replace; "Union", Pdk.Group_ops.Name_union;
    ]
  let invalid_parameter = Parameter.choice ~equal:( = ) [
      "Ignore invalid", Pdk.Group_ops.Ignore_invalid;
      "Force valid", Pdk.Group_ops.Force_valid;
    ]
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Primitive]
      [@sop.label "Attribute owner"]
      [@sop.kind element_attribute_owner_parameter];
    attribute : string [@sop.default "name"] [@sop.label "Name attribute"];
    prefix : string [@sop.default ""] [@sop.label "Group prefix"];
    conflict : Pdk.Group_ops.name_conflict
      [@sop.default Pdk.Group_ops.Name_replace] [@sop.label "Conflict"]
      [@sop.kind conflict_parameter];
    invalid_names : Pdk.Group_ops.invalid_name_policy
      [@sop.default Pdk.Group_ops.Ignore_invalid] [@sop.label "Invalid names"]
      [@sop.kind invalid_parameter];
    max_groups : int [@sop.default 4096] [@sop.label "Maximum groups"]
      [@sop.folder "Limits"] [@sop.min 1] [@sop.max 16384]
      [@sop.hard_min 1];
    max_payload_bytes : int [@sop.default 268435456]
      [@sop.label "Maximum payload bytes"] [@sop.folder "Limits"]
      [@sop.min 1048576] [@sop.max 1073741824] [@sop.hard_min 1];
  } [@@sop.node_key "groups_from_name"] [@@sop.node_label "Groups from Name"]
    [@@sop.node_category "Group/Convert"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.groups_from_name ~label ~prefix:parameters.prefix
        ~conflict:parameters.conflict ~invalid_names:parameters.invalid_names
        ~max_groups:parameters.max_groups
        ~max_payload_bytes:parameters.max_payload_bytes
        ~owner:parameters.owner ~attribute:parameters.attribute input)
  let factory = parameters_factory build
end

module Name_from_groups = struct
  let overlap_parameter = Parameter.choice ~equal:( = ) [
      "First group", Pdk.Group_ops.First_group; "Last group", Pdk.Group_ops.Last_group;
      "Error on overlap", Pdk.Group_ops.Error_on_overlap;
    ]
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Primitive]
      [@sop.label "Group type"] [@sop.kind element_attribute_owner_parameter];
    attribute : string [@sop.default "name"] [@sop.label "Name attribute"];
    pattern : string [@sop.default "*"] [@sop.label "Group pattern"];
    default : string [@sop.default ""] [@sop.label "Default value"];
    overlap : Pdk.Group_ops.name_overlap [@sop.default Pdk.Group_ops.First_group]
      [@sop.label "Overlapping groups"] [@sop.kind overlap_parameter];
    delete_groups : bool [@sop.default false]
      [@sop.label "Delete source groups"];
  } [@@sop.node_key "name_from_groups"] [@@sop.node_label "Name from Groups"]
    [@@sop.node_category "Group/Convert"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.name_from_groups ~label ~attribute:parameters.attribute
        ~pattern:parameters.pattern ~default:parameters.default
        ~overlap:parameters.overlap ~delete_groups:parameters.delete_groups
        ~owner:parameters.owner input)
  let factory = parameters_factory build
end

module Group_promote_boundary = struct
  type parameters = {
    source : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_primitives]
      [@sop.label "Source owner"] [@sop.kind group_owner_parameter];
    destination : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_edges]
      [@sop.label "Destination owner"] [@sop.kind group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Source group"];
    name : string [@sop.default ""] [@sop.label "New group name"];
    keep_original : bool [@sop.default false]
      [@sop.label "Keep original group"];
    output_attribute : string [@sop.default ""]
      [@sop.label "Output mask attribute"] [@sop.folder "Output"];
    attributes : Pdk.Group_ops.boundary_attribute list [@sop.default []]
      [@sop.label "Boundary attributes (owner, pattern)"]
      [@sop.kind boundary_attributes_parameter];
    tolerance : float [@sop.default 0.00001] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    include_unshared_edges : bool [@sop.default false]
      [@sop.label "Include unshared edges"];
    include_all_unshared_curve_edges : bool [@sop.default false]
      [@sop.label "Include all unshared curve edges"];
    include_all_primitives_sharing_boundary_points : bool [@sop.default false]
      [@sop.label "Include primitives sharing boundary points"];
  } [@@sop.node_key "group_promote_boundary"]
    [@@sop.node_label "Group Promote Boundary"]
    [@@sop.node_category "Group/Convert"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_promote_boundary ~label
        ?name:(optional_text parameters.name)
        ~keep_original:parameters.keep_original
        ?output_attribute:(optional_text parameters.output_attribute)
        ~attributes:parameters.attributes ~tolerance:parameters.tolerance
        ~include_unshared_edges:parameters.include_unshared_edges
        ~include_all_unshared_curve_edges:
          parameters.include_all_unshared_curve_edges
        ~include_all_primitives_sharing_boundary_points:
          parameters.include_all_primitives_sharing_boundary_points
        ~source:parameters.source ~destination:parameters.destination
        ~group:parameters.group input)
  let factory = parameters_factory build
end

module Group_promotions = struct
  let bool_token value = if value then "true" else "false"
  let bool_of_token = function
    | "true" | "1" | "yes" -> Ok true
    | "false" | "0" | "no" -> Ok false
    | token -> Error (Printf.sprintf "expected boolean, got %S" token)
  let encode_attributes attributes = encode_table (List.map
      (fun (attribute : Pdk.Group_ops.boundary_attribute) ->
        [attribute_owner_token attribute.boundary_attribute_owner;
         attribute.boundary_attribute_pattern]) attributes)
  let decode_attributes text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun attributes ->
        match row with
        | [owner; pattern] -> Result.map (fun boundary_attribute_owner ->
            { Pdk.Group_ops.boundary_attribute_owner;
              boundary_attribute_pattern = pattern } :: attributes)
            (attribute_owner_of_token
              (String.lowercase_ascii (String.trim owner)))
        | row -> Error (Printf.sprintf
            "boundary attribute needs owner and pattern, got %d columns"
            (List.length row)))) (Ok []) rows |> Result.map List.rev)
  let encode_operation = function
    | Pdk.Group_ops.Promote_elements mode ->
        let token = match mode with
          | Pdk.Group_ops.Include_any -> "any"
          | Pdk.Group_ops.Include_all -> "all"
          | Pdk.Group_ops.Include_shared_edge -> "shared_edge" in
        [token; "0"; "false"; "false"; "false"; ""]
    | Pdk.Group_ops.Promote_boundary options -> [
        "boundary"; Printf.sprintf "%.17g" options.promote_boundary_tolerance;
        bool_token options.promote_include_unshared_edges;
        bool_token options.promote_include_all_unshared_curve_edges;
        bool_token options.promote_include_all_primitives_sharing_boundary_points;
        encode_attributes options.promote_boundary_attributes;
      ]
  let decode_operation = function
    | [kind; tolerance; unshared; all_curve; all_primitives; attributes] ->
        (match String.lowercase_ascii (String.trim kind) with
         | "any" -> Ok (Pdk.Group_ops.Promote_elements Pdk.Group_ops.Include_any)
         | "all" -> Ok (Pdk.Group_ops.Promote_elements Pdk.Group_ops.Include_all)
         | "shared_edge" | "shared edge" ->
             Ok (Pdk.Group_ops.Promote_elements Pdk.Group_ops.Include_shared_edge)
         | "boundary" ->
             (match float_of_string_opt (String.trim tolerance) with
              | None -> Error (Printf.sprintf "invalid boundary tolerance %S"
                  tolerance)
              | Some promote_boundary_tolerance ->
                  Result.bind (bool_of_token
                    (String.lowercase_ascii (String.trim unshared)))
                    (fun promote_include_unshared_edges ->
                      Result.bind (bool_of_token
                        (String.lowercase_ascii (String.trim all_curve)))
                        (fun promote_include_all_unshared_curve_edges ->
                          Result.bind (bool_of_token
                            (String.lowercase_ascii
                              (String.trim all_primitives)))
                            (fun promote_include_all_primitives_sharing_boundary_points ->
                              Result.map (fun promote_boundary_attributes ->
                                Pdk.Group_ops.Promote_boundary {
                                  Pdk.Group_ops.promote_boundary_attributes;
                                  promote_boundary_tolerance;
                                  promote_include_unshared_edges;
                                  promote_include_all_unshared_curve_edges;
                                  promote_include_all_primitives_sharing_boundary_points })
                                (decode_attributes attributes)))))
         | token -> Error (Printf.sprintf
             "unknown group promotion operation %S" token))
    | columns -> Error (Printf.sprintf
        "group promotion operation needs 6 columns, got %d"
        (List.length columns))
  let encode_rule (rule : Pdk.Group_ops.promotion_rule) = [
      group_owner_token rule.promotion_source;
      group_owner_token rule.promotion_destination;
      rule.promotion_pattern;
      Option.value ~default:"" rule.promotion_new_name;
      bool_token rule.promotion_keep_original;
      bool_token rule.promotion_output_as_attribute;
    ] @ encode_operation rule.promotion_operation
  let decode_rule = function
    | source :: destination :: pattern :: new_name :: keep_original ::
        output_as_attribute :: operation ->
        Result.bind (group_owner_of_token
          (String.lowercase_ascii (String.trim source)))
          (fun promotion_source -> Result.bind (group_owner_of_token
            (String.lowercase_ascii (String.trim destination)))
            (fun promotion_destination -> Result.bind (bool_of_token
              (String.lowercase_ascii (String.trim keep_original)))
              (fun promotion_keep_original -> Result.bind (bool_of_token
                (String.lowercase_ascii (String.trim output_as_attribute)))
                (fun promotion_output_as_attribute ->
                  Result.map (fun promotion_operation -> {
                    Pdk.Group_ops.promotion_source; promotion_destination;
                    promotion_pattern = pattern;
                    promotion_new_name = optional_text new_name;
                    promotion_keep_original; promotion_output_as_attribute;
                    promotion_operation }) (decode_operation operation)))))
    | row -> Error (Printf.sprintf
        "Group Promotions rule needs 12 columns, got %d"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  let default_rules = [{
      Pdk.Group_ops.promotion_source = Pdk.Group_ops.Group_points;
      promotion_destination = Pdk.Group_ops.Group_primitives;
      promotion_pattern = "*"; promotion_new_name = None;
      promotion_keep_original = false;
      promotion_output_as_attribute = false;
      promotion_operation = Pdk.Group_ops.Promote_elements Pdk.Group_ops.Include_any;
    }]
  type parameters = {
    rules : Pdk.Group_ops.promotion_rule list [@sop.default default_rules]
      [@sop.label "Rules (source, destination, pattern, new name, keep, attribute, operation...)"]
      [@sop.kind rules_parameter];
    max_outputs : int [@sop.default 4096] [@sop.label "Maximum outputs"]
      [@sop.folder "Limits"] [@sop.min 1] [@sop.max 16384]
      [@sop.hard_min 1];
    max_payload_bytes : int [@sop.default 268435456]
      [@sop.label "Maximum payload bytes"] [@sop.folder "Limits"]
      [@sop.min 1048576] [@sop.max 1073741824] [@sop.hard_min 1];
  } [@@sop.node_key "group_promotions"]
    [@@sop.node_label "Group Promotions"]
    [@@sop.node_category "Group/Convert"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_promotions ~label
        ~max_outputs:parameters.max_outputs
        ~max_payload_bytes:parameters.max_payload_bytes parameters.rules input)
  let factory = parameters_factory build
end

module Group_invert = struct
  type owner = Any | Owner of Pdk.Group_ops.owner
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Any", Any; "Points", Owner Pdk.Group_ops.Group_points;
      "Vertices", Owner Pdk.Group_ops.Group_vertices;
      "Primitives", Owner Pdk.Group_ops.Group_primitives;
      "Edges", Owner Pdk.Group_ops.Group_edges;
    ]
  type parameters = {
    owner : owner [@sop.default Any] [@sop.label "Group type"]
      [@sop.kind owner_parameter];
    pattern : string [@sop.default "*"] [@sop.label "Group pattern"];
    new_name : string [@sop.default ""] [@sop.label "New name pattern"];
    conflict : Pdk.Group_ops.rename_conflict
      [@sop.default Pdk.Group_ops.Rename_overwrite] [@sop.label "Conflict"]
      [@sop.kind group_rename_conflict_parameter];
  } [@@sop.node_key "group_invert"] [@@sop.node_label "Group Invert"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let owner = match parameters.owner with Any -> None | Owner owner -> Some owner in
    Sop.group_invert ~label ~conflict:parameters.conflict ?owner
      ~pattern:parameters.pattern ?new_name:(optional_text parameters.new_name)
      input)
  let factory = parameters_factory build
end

module Group_delete = struct
  let encode_rule (rule : Pdk.Group_ops.delete_rule) = [
      (match rule.delete_owner with None -> "any"
       | Some owner -> group_owner_token owner);
      rule.delete_pattern;
    ]
  let decode_rule = function
    | [owner; pattern] ->
        let owner = String.lowercase_ascii (String.trim owner) in
        let owner = if owner = "any" || owner = "*" then Ok None
          else Result.map Option.some (group_owner_of_token owner) in
        Result.map (fun delete_owner -> {
          Pdk.Group_ops.delete_owner; delete_pattern = pattern }) owner
    | row -> Error (Printf.sprintf
        "Group Delete rule needs owner and pattern, got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  type parameters = {
    rules : Pdk.Group_ops.delete_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern)"] [@sop.kind rules_parameter];
    delete_unused : bool [@sop.default false]
      [@sop.label "Delete unused groups"];
  } [@@sop.node_key "group_delete"] [@@sop.node_label "Group Delete"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_delete ~label
        ~delete_unused:parameters.delete_unused ~rules:parameters.rules input)
  let factory = parameters_factory build
end

module Group_rename = struct
  let conflict_token = function
    | Pdk.Group_ops.Rename_skip -> "skip"
    | Pdk.Group_ops.Rename_error -> "error"
    | Pdk.Group_ops.Rename_overwrite -> "overwrite"
    | Pdk.Group_ops.Rename_union -> "union"
  let conflict_of_token = function
    | "skip" -> Ok Pdk.Group_ops.Rename_skip
    | "error" -> Ok Pdk.Group_ops.Rename_error
    | "overwrite" -> Ok Pdk.Group_ops.Rename_overwrite
    | "union" -> Ok Pdk.Group_ops.Rename_union
    | token -> Error (Printf.sprintf "unknown group rename conflict %S" token)
  let encode_rule (rule : Pdk.Group_ops.rename_rule) = [
      (match rule.rename_owner with None -> "any"
       | Some owner -> group_owner_token owner);
      rule.rename_pattern; rule.rename_replacement;
      conflict_token rule.rename_conflict;
    ]
  let decode_rule = function
    | [owner; pattern; replacement; conflict] ->
        let owner = String.lowercase_ascii (String.trim owner)
        and conflict = String.lowercase_ascii (String.trim conflict) in
        let owner = if owner = "any" || owner = "*" then Ok None
          else Result.map Option.some (group_owner_of_token owner) in
        Result.bind owner (fun rename_owner ->
          Result.map (fun rename_conflict -> {
            Pdk.Group_ops.rename_owner; rename_pattern = pattern;
            rename_replacement = replacement; rename_conflict })
            (conflict_of_token conflict))
    | row -> Error (Printf.sprintf
        "Group Rename rule needs owner, pattern, replacement, and conflict; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  type parameters = {
    rules : Pdk.Group_ops.rename_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, replacement, conflict)"]
      [@sop.kind rules_parameter];
  } [@@sop.node_key "group_rename"] [@@sop.node_label "Group Rename"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_rename ~label ~rules:parameters.rules input)
  let factory = parameters_factory build
end

module Group_copy = struct
  let encode_rule (rule : Pdk.Group_ops.copy_rule) = [
      group_owner_token rule.copy_owner; rule.copy_pattern; rule.copy_prefix;
      Option.value ~default:"" rule.match_attribute;
    ]
  let decode_rule = function
    | [owner; pattern; prefix; match_attribute] ->
        Result.map (fun copy_owner -> { Pdk.Group_ops.copy_owner;
          copy_pattern = pattern; copy_prefix = prefix;
          match_attribute = optional_text match_attribute })
          (group_owner_of_token
            (String.lowercase_ascii (String.trim owner)))
    | row -> Error (Printf.sprintf
        "Group Copy rule needs owner, pattern, prefix, and match attribute; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  type parameters = {
    use_rules : bool [@sop.default false] [@sop.label "Use rules"];
    rules : Pdk.Group_ops.copy_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, prefix, match attribute)"]
      [@sop.kind rules_parameter];
    conflict : Pdk.Group_ops.copy_conflict
      [@sop.default Pdk.Group_ops.Copy_overwrite] [@sop.label "Conflict"]
      [@sop.kind group_copy_conflict_parameter];
    copy_empty : bool [@sop.default false] [@sop.label "Copy empty groups"];
  } [@@sop.node_key "group_copy"] [@@sop.node_label "Group Copy"]
    [@@sop.node_category "Group/Transfer"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters source target ->
    Sop.group_copy ~label
        ?rules:(if parameters.use_rules then Some parameters.rules else None)
        ~conflict:parameters.conflict ~copy_empty:parameters.copy_empty
        ~source ~target ())
  let factory = parameters_factory build
end

module Group_transfer = struct
  let encode_rule (rule : Pdk.Group_ops.transfer_rule) = [
      group_owner_token rule.transfer_owner; rule.transfer_pattern;
      rule.transfer_prefix;
    ]
  let decode_rule = function
    | [owner; pattern; prefix] ->
        Result.map (fun transfer_owner -> { Pdk.Group_ops.transfer_owner;
          transfer_pattern = pattern; transfer_prefix = prefix })
          (group_owner_of_token
            (String.lowercase_ascii (String.trim owner)))
    | row -> Error (Printf.sprintf
        "Group Transfer rule needs owner, pattern, and prefix; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  type parameters = {
    use_rules : bool [@sop.default false] [@sop.label "Use rules"];
    rules : Pdk.Group_ops.transfer_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, prefix)"]
      [@sop.kind rules_parameter];
    conflict : Pdk.Group_ops.copy_conflict
      [@sop.default Pdk.Group_ops.Copy_overwrite] [@sop.label "Conflict"]
      [@sop.kind group_copy_conflict_parameter];
    create_empty : bool [@sop.default false]
      [@sop.label "Create empty groups"];
    distance : float [@sop.default 0.001] [@sop.label "Maximum distance"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
  } [@@sop.node_key "group_transfer"] [@@sop.node_label "Group Transfer"]
    [@@sop.node_category "Group/Transfer"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters source target ->
    Sop.group_transfer ~label
        ?rules:(if parameters.use_rules then Some parameters.rules else None)
        ~conflict:parameters.conflict ~create_empty:parameters.create_empty
        ~distance:parameters.distance ~source ~target ())
  let factory = parameters_factory build
end

module Group_combine = struct
  let bool_token value = if value then "true" else "false"
  let bool_of_token = function
    | "true" | "1" | "yes" -> Ok true
    | "false" | "0" | "no" -> Ok false
    | token -> Error (Printf.sprintf "expected boolean, got %S" token)
  let encode_step (step : Pdk.Group_ops.combine_step) = [
      group_boolean_token step.operation; step.operand.pattern;
      bool_token step.operand.inverted;
    ]
  let decode_step = function
    | [operation; pattern; inverted] ->
        Result.bind (group_boolean_of_token
          (String.lowercase_ascii (String.trim operation)))
          (fun operation -> Result.map (fun inverted -> {
            Pdk.Group_ops.operation; operand = { pattern; inverted } })
            (bool_of_token
              (String.lowercase_ascii (String.trim inverted))))
    | row -> Error (Printf.sprintf
        "Group Combine step needs operation, pattern, and invert; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun steps ->
        Result.map (fun step -> step :: steps) (decode_step row))) (Ok []) rows
      |> Result.map List.rev)
  let steps_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun steps -> encode_table (List.map encode_step steps)) ~decode
  type parameters = {
    owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "combined"] [@sop.label "Output group"];
    base_pattern : string [@sop.default "*"] [@sop.label "Base pattern"];
    base_inverted : bool [@sop.default false] [@sop.label "Invert base"];
    steps : Pdk.Group_ops.combine_step list [@sop.default []]
      [@sop.label "Steps (operation, pattern, invert)"]
      [@sop.kind steps_parameter];
  } [@@sop.node_key "group_combine"] [@@sop.node_label "Group Combine"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_combine ~label ~owner:parameters.owner
        ~name:parameters.name ~base:{ Pdk.Group_ops.pattern = parameters.base_pattern;
          inverted = parameters.base_inverted }
        ~steps:parameters.steps input)
  let factory = parameters_factory build
end

module Group_expand = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Share points", Pdk.Group_ops.Primitive_share_points;
      "Share edges", Pdk.Group_ops.Primitive_share_edges;
    ]
  type parameters = {
    owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Source group"];
    name : string [@sop.default ""] [@sop.label "Output group"];
    steps : int [@sop.default 1] [@sop.label "Steps"]
      [@sop.min (-100)] [@sop.max 100];
    flood : bool [@sop.default false] [@sop.label "Flood fill"];
    step_attribute : string [@sop.default ""]
      [@sop.label "Step attribute"] [@sop.folder "Output"];
    primitive_connectivity : Pdk.Group_ops.primitive_connectivity
      [@sop.default Pdk.Group_ops.Primitive_share_points]
      [@sop.label "Primitive connectivity"]
      [@sop.folder "Connectivity"] [@sop.kind connectivity_parameter];
    normal_spread : float [@sop.default 3.141592653589793]
      [@sop.label "Normal spread"] [@sop.folder "Connectivity/Normals"]
      [@sop.min 0.] [@sop.max 3.141592653589793]
      [@sop.hard_min 0.] [@sop.hard_max 3.141592653589793];
    use_normal_attribute : bool [@sop.default false]
      [@sop.label "Use normal attribute"] [@sop.folder "Connectivity/Normals"];
    normal_owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Primitive]
      [@sop.label "Normal owner"] [@sop.folder "Connectivity/Normals"]
      [@sop.kind element_attribute_owner_parameter];
    normal_name : string [@sop.default "N"] [@sop.label "Normal attribute"]
      [@sop.folder "Connectivity/Normals"];
    connectivity_attributes : Pdk.Group_ops.boundary_attribute list
      [@sop.default []] [@sop.label "Boundary attributes (owner, pattern)"]
      [@sop.folder "Connectivity"] [@sop.kind boundary_attributes_parameter];
    connectivity_tolerance : float [@sop.default 0.00001]
      [@sop.label "Attribute tolerance"] [@sop.folder "Connectivity"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    use_collision : bool [@sop.default false]
      [@sop.label "Use collision group"] [@sop.folder "Collision"];
    collision_owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_edges]
      [@sop.label "Collision owner"] [@sop.folder "Collision"]
      [@sop.kind group_owner_parameter];
    collision_group : string [@sop.default "collision"]
      [@sop.label "Collision group"] [@sop.folder "Collision"];
    collision_contain : bool [@sop.default false]
      [@sop.label "Contain region"] [@sop.folder "Collision"];
    collision_allow_boundary : bool [@sop.default false]
      [@sop.label "Allow boundary"] [@sop.folder "Collision"];
  } [@@sop.node_key "group_expand"] [@@sop.node_label "Group Expand"]
    [@@sop.node_category "Group/Expand"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let normal_attribute = if parameters.use_normal_attribute then Some {
        Pdk.Group_ops.expand_normal_owner = parameters.normal_owner;
        expand_normal_name = parameters.normal_name } else None
    and collision = if parameters.use_collision then Some {
        Pdk.Group_ops.expand_collision_owner = parameters.collision_owner;
        expand_collision_group = parameters.collision_group;
        expand_collision_contain = parameters.collision_contain;
        expand_collision_allow_boundary =
          parameters.collision_allow_boundary } else None in
    Sop.group_expand ~label ?name:(optional_text parameters.name)
      ~steps:parameters.steps ~flood:parameters.flood
      ?step_attribute:(optional_text parameters.step_attribute)
      ~primitive_connectivity:parameters.primitive_connectivity
      ~normal_spread:parameters.normal_spread ?normal_attribute
      ~connectivity_attributes:parameters.connectivity_attributes
      ~connectivity_tolerance:parameters.connectivity_tolerance ?collision
      ~owner:parameters.owner ~group:parameters.group input)
  let factory = parameters_factory build
end

module Group_range = struct
  type range_mode = Start_end | From_ends | Start_length | Partition
  type connectivity_mode = No_connectivity | Disconnected | Connected
  let range_parameter = Parameter.choice ~equal:( = ) [
      "Start and end", Start_end; "From ends", From_ends;
      "Start and length", Start_length; "Partition", Partition;
    ]
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "None", No_connectivity; "Disconnected regions", Disconnected;
      "Connected with seams", Connected;
    ]
  type parameters = {
    owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "range"] [@sop.label "Output group"];
    base : string [@sop.default ""] [@sop.label "Base group"];
    invert : bool [@sop.default false] [@sop.label "Invert range"];
    merge : Pdk.Group_ops.boolean_operation
      [@sop.default Pdk.Group_ops.Group_replace] [@sop.label "Merge"]
      [@sop.kind group_merge_parameter];
    range_mode : range_mode [@sop.default Start_end] [@sop.label "Range"]
      [@sop.kind range_parameter];
    start : int [@sop.default 0] [@sop.label "Start"]
      [@sop.folder "Range"] [@sop.min (-100000)] [@sop.max 100000];
    end_ : int [@sop.default (-1)] [@sop.label "End"]
      [@sop.folder "Range"] [@sop.min (-100000)] [@sop.max 100000];
    end_offset : int [@sop.default 0] [@sop.label "End offset"]
      [@sop.folder "Range"] [@sop.min (-100000)] [@sop.max 100000];
    length : int [@sop.default 1] [@sop.label "Length"]
      [@sop.folder "Range"] [@sop.min 0] [@sop.max 100000]
      [@sop.hard_min 0];
    partition : int [@sop.default 0] [@sop.label "Partition"]
      [@sop.folder "Range"] [@sop.min 0] [@sop.max 10000]
      [@sop.hard_min 0];
    partitions : int [@sop.default 2] [@sop.label "Partitions"]
      [@sop.folder "Range"] [@sop.min 1] [@sop.max 10000]
      [@sop.hard_min 1];
    use_filter : bool [@sop.default false] [@sop.label "Use filter"]
      [@sop.folder "Filter"];
    filter_select : int [@sop.default 1] [@sop.label "Select"]
      [@sop.folder "Filter"] [@sop.min 0] [@sop.max 10000]
      [@sop.hard_min 0];
    filter_of : int [@sop.default 1] [@sop.label "Of"]
      [@sop.folder "Filter"] [@sop.min 1] [@sop.max 10000]
      [@sop.hard_min 1];
    filter_offset : int [@sop.default 0] [@sop.label "Offset"]
      [@sop.folder "Filter"] [@sop.min (-10000)] [@sop.max 10000];
    connectivity_mode : connectivity_mode [@sop.default No_connectivity]
      [@sop.label "Connectivity"] [@sop.folder "Connectivity"]
      [@sop.kind connectivity_parameter];
    use_region : bool [@sop.default false] [@sop.label "Restrict region"]
      [@sop.folder "Connectivity"];
    region : int [@sop.default 0] [@sop.label "Region"]
      [@sop.folder "Connectivity"] [@sop.min 0] [@sop.max 100000]
      [@sop.hard_min 0];
    connectivity_attributes : string [@sop.default ""]
      [@sop.label "Connectivity attributes"] [@sop.folder "Connectivity"];
    connectivity_tolerance : float [@sop.default 0.00001]
      [@sop.label "Attribute tolerance"] [@sop.folder "Connectivity"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    use_collision : bool [@sop.default false]
      [@sop.label "Use collision group"] [@sop.folder "Connectivity/Collision"];
    collision_owner : Pdk.Group_ops.owner [@sop.default Pdk.Group_ops.Group_edges]
      [@sop.label "Collision owner"] [@sop.folder "Connectivity/Collision"]
      [@sop.kind group_owner_parameter];
    collision_pattern : string [@sop.default "collision"]
      [@sop.label "Collision pattern"] [@sop.folder "Connectivity/Collision"];
    keep_boundary : bool [@sop.default false] [@sop.label "Keep boundary"]
      [@sop.folder "Connectivity/Collision"];
    remove_other_regions : bool [@sop.default false]
      [@sop.label "Remove other regions"] [@sop.folder "Connectivity"];
  } [@@sop.node_key "group_range"] [@@sop.node_label "Group Range"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let range parameters = match parameters.range_mode with
    | Start_end -> Pdk.Group_ops.Range_start_end {
        start = parameters.start; end_ = parameters.end_ }
    | From_ends -> Pdk.Group_ops.Range_from_ends {
        start = parameters.start; end_offset = parameters.end_offset }
    | Start_length -> Pdk.Group_ops.Range_start_length {
        start = parameters.start; length = parameters.length }
    | Partition -> Pdk.Group_ops.Range_partition {
        partition = parameters.partition; partitions = parameters.partitions }
  let filter parameters = if parameters.use_filter then Some {
      Pdk.Group_ops.select = parameters.filter_select; of_ = parameters.filter_of;
      offset = parameters.filter_offset } else None
  let connectivity parameters =
    let region = if parameters.use_region then Some parameters.region else None in
    match parameters.connectivity_mode with
    | No_connectivity -> None
    | Disconnected -> Some (Pdk.Group_ops.Range_disconnected { region })
    | Connected ->
        let collision = if parameters.use_collision then Some {
            Pdk.Group_ops.collision_owner = parameters.collision_owner;
            collision_pattern = parameters.collision_pattern;
            keep_boundary = parameters.keep_boundary } else None in
        Some (Pdk.Group_ops.Range_connected {
          connectivity_attributes =
            optional_text parameters.connectivity_attributes;
          connectivity_tolerance = parameters.connectivity_tolerance;
          collision; region;
          remove_other_regions = parameters.remove_other_regions })
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_range ~label ?base:(optional_text parameters.base)
        ~invert:parameters.invert ?filter:(filter parameters)
        ?connectivity:(connectivity parameters) ~merge:parameters.merge
        ~owner:parameters.owner ~name:parameters.name (range parameters) input)
  let factory = parameters_factory build
end

module Group_ranges = struct
  let encode_specification = function
    | Pdk.Group_ops.Range_start_end { start; end_ } ->
        ["start_end"; string_of_int start; string_of_int end_]
    | Pdk.Group_ops.Range_from_ends { start; end_offset } ->
        ["from_ends"; string_of_int start; string_of_int end_offset]
    | Pdk.Group_ops.Range_start_length { start; length } ->
        ["start_length"; string_of_int start; string_of_int length]
    | Pdk.Group_ops.Range_partition { partition; partitions } ->
        ["partition"; string_of_int partition; string_of_int partitions]
  let decode_specification = function
    | [kind; a; b] ->
        let ( let* ) = Result.bind in
        let* a = int_of_token a in
        let* b = int_of_token b in
        (match String.lowercase_ascii (String.trim kind) with
         | "start_end" -> Ok (Pdk.Group_ops.Range_start_end { start = a; end_ = b })
         | "from_ends" -> Ok (Pdk.Group_ops.Range_from_ends {
             start = a; end_offset = b })
         | "start_length" -> Ok (Pdk.Group_ops.Range_start_length {
             start = a; length = b })
         | "partition" -> Ok (Pdk.Group_ops.Range_partition {
             partition = a; partitions = b })
         | token -> Error (Printf.sprintf "unknown range kind %S" token))
    | columns -> Error (Printf.sprintf
        "range specification needs 3 columns, got %d" (List.length columns))
  let encode_filter = function
    | None -> ["none"; "0"; "1"; "0"]
    | Some filter -> ["filter"; string_of_int filter.Pdk.Group_ops.select;
        string_of_int filter.of_; string_of_int filter.offset]
  let decode_filter = function
    | [kind; select; of_; offset] ->
        if String.lowercase_ascii (String.trim kind) = "none" then Ok None
        else
          let ( let* ) = Result.bind in
          let* select = int_of_token select in
          let* of_ = int_of_token of_ in
          let* offset = int_of_token offset in
          Ok (Some { Pdk.Group_ops.select; of_; offset })
    | columns -> Error (Printf.sprintf
        "range filter needs 4 columns, got %d" (List.length columns))
  let encode_connectivity = function
    | None -> ["none"; ""; ""; "0"; "false"; "edge"; "";
        "false"; "false"]
    | Some (Pdk.Group_ops.Range_disconnected { region }) -> [
        "disconnected"; Option.fold ~none:"" ~some:string_of_int region;
        ""; "0"; "false"; "edge"; ""; "false"; "false"]
    | Some (Pdk.Group_ops.Range_connected connectivity) ->
        let collision_enabled, collision_owner, collision_pattern, keep_boundary =
          match connectivity.collision with
          | None -> "false", "edge", "", "false"
          | Some collision -> "true",
              group_owner_token collision.collision_owner,
              collision.collision_pattern, bool_token collision.keep_boundary in
        ["connected";
         Option.fold ~none:"" ~some:string_of_int connectivity.region;
         Option.value ~default:"" connectivity.connectivity_attributes;
         Printf.sprintf "%.17g" connectivity.connectivity_tolerance;
         collision_enabled; collision_owner; collision_pattern; keep_boundary;
         bool_token connectivity.remove_other_regions]
  let decode_connectivity = function
    | [kind; region; attributes; tolerance; collision_enabled;
        collision_owner; collision_pattern; keep_boundary;
        remove_other_regions] ->
        let ( let* ) = Result.bind in
        let region = if String.trim region = "" then Ok None
          else Result.map Option.some (int_of_token region) in
        let* region = region in
        (match String.lowercase_ascii (String.trim kind) with
         | "none" -> Ok None
         | "disconnected" -> Ok (Some (Pdk.Group_ops.Range_disconnected { region }))
         | "connected" ->
             let* connectivity_tolerance = float_of_token tolerance in
             let* collision_enabled = bool_of_token collision_enabled in
             let* collision = if not collision_enabled then Ok None else
               let* collision_owner = group_owner_of_token
                   (String.lowercase_ascii (String.trim collision_owner)) in
               let* keep_boundary = bool_of_token keep_boundary in
               Ok (Some { Pdk.Group_ops.collision_owner; collision_pattern;
                 keep_boundary }) in
             let* remove_other_regions = bool_of_token remove_other_regions in
             Ok (Some (Pdk.Group_ops.Range_connected {
               connectivity_attributes = optional_text attributes;
               connectivity_tolerance; collision; region;
               remove_other_regions }))
         | token -> Error (Printf.sprintf
             "unknown range connectivity %S" token))
    | columns -> Error (Printf.sprintf
        "range connectivity needs 9 columns, got %d" (List.length columns))
  let encode_rule (rule : Pdk.Group_ops.range_rule) =
    [group_owner_token rule.range_owner; rule.range_name;
     Option.value ~default:"" rule.range_base; bool_token rule.range_invert;
     group_boolean_token rule.range_merge]
    @ encode_specification rule.range_specification
    @ encode_filter rule.range_filter
    @ encode_connectivity rule.range_connectivity
  let decode_rule = function
    | [owner; name; base; invert; merge; s0; s1; s2; f0; f1; f2; f3;
        c0; c1; c2; c3; c4; c5; c6; c7; c8] ->
        let ( let* ) = Result.bind in
        let* range_owner = group_owner_of_token
            (String.lowercase_ascii (String.trim owner)) in
        let* range_invert = bool_of_token invert in
        let* range_merge = group_boolean_of_token
            (String.lowercase_ascii (String.trim merge)) in
        let* range_specification = decode_specification [s0; s1; s2] in
        let* range_filter = decode_filter [f0; f1; f2; f3] in
        let* range_connectivity = decode_connectivity
            [c0; c1; c2; c3; c4; c5; c6; c7; c8] in
        Ok { Pdk.Group_ops.range_owner; range_name = name;
          range_base = optional_text base; range_invert; range_filter;
          range_connectivity; range_merge; range_specification }
    | row -> Error (Printf.sprintf
        "Group Ranges rule needs 21 columns, got %d" (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  let default_rules = [Pdk.Group_ops.range_rule
      ~owner:Pdk.Group_ops.Group_points ~name:"range"
      (Pdk.Group_ops.Range_start_end { start = 0; end_ = -1 })]
  type parameters = {
    rules : Pdk.Group_ops.range_rule list [@sop.default default_rules]
      [@sop.label "Range rules"] [@sop.kind rules_parameter];
  } [@@sop.node_key "group_ranges"] [@@sop.node_label "Group Ranges"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_ranges ~label parameters.rules input)
  let factory = parameters_factory build
end

module Group_find_path = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Through each", Pdk.Group_mesh.Through_each;
      "Start/end pairs", Pdk.Group_mesh.Start_end_pairs;
    ]
  let ending_parameter = Parameter.choice ~equal:( = ) [
      "Stop at end", Pdk.Group_mesh.Stop_at_end; "Close path", Pdk.Group_mesh.Close_path;
    ]
  type parameters = {
    owner : Pdk.Group.owner [@sop.default Pdk.Group.Point]
      [@sop.label "Group type"] [@sop.kind ordinary_group_owner_parameter];
    base_group : string [@sop.default "ordered"] [@sop.label "Base group"];
    name : string [@sop.default "path"] [@sop.label "Output group"];
    mode : Pdk.Group_mesh.path_mode [@sop.default Pdk.Group_mesh.Through_each]
      [@sop.label "Path mode"] [@sop.kind mode_parameter];
    ending : Pdk.Group_mesh.path_ending [@sop.default Pdk.Group_mesh.Stop_at_end]
      [@sop.label "Ending"] [@sop.kind ending_parameter];
    avoid_self_intersection : bool [@sop.default true]
      [@sop.label "Avoid self-intersection"];
    collision_group : string [@sop.default ""]
      [@sop.label "Collision group"] [@sop.folder "Collision"];
    contain : bool [@sop.default false] [@sop.label "Contain path"]
      [@sop.folder "Collision"];
  } [@@sop.node_key "group_find_path"] [@@sop.node_label "Group Find Path"]
    [@@sop.node_category "Group/Path"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_find_path ~label ~mode:parameters.mode
        ~ending:parameters.ending
        ~avoid_self_intersection:parameters.avoid_self_intersection
        ~owner:parameters.owner
        ?collision_group:(optional_text parameters.collision_group)
        ~contain:parameters.contain ~base_group:parameters.base_group
        ~name:parameters.name input)
  let factory = parameters_factory build
end

module Delete_edge_group = struct
  type parameters = {
    name : string [@sop.default "edges"] [@sop.label "Edge group"];
  } [@@sop.node_key "delete_edge_group"]
    [@@sop.node_label "Delete Edge Group"]
    [@@sop.node_category "Group/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.delete_edge_group ~label ~name:parameters.name input)
  let factory = parameters_factory build
end

module Rename_edge_group = struct
  type parameters = {
    from : string [@sop.default "edges"] [@sop.label "From"];
    into : string [@sop.default "renamed"] [@sop.label "To"];
  } [@@sop.node_key "rename_edge_group"]
    [@@sop.node_label "Rename Edge Group"]
    [@@sop.node_category "Group/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.rename_edge_group ~label ~from:parameters.from
        ~into:parameters.into input)
  let factory = parameters_factory build
end
