(* Group nodes, declared once: the record is the editor schema, the factory
   and the typed [Sop] constructor. *)

open Rays_math
open Sop_support

(* ocamldep must see the PPX's [Procedural.X] resolve inside this library. *)
module Procedural = Sop_support.Procedural

module Group_non_planar = struct
  type parameters = {
    name : string [@sop.default "nonplanar"] [@sop.label "Group name"] [@sop.nonblank "empty group name"];
    tolerance : float [@sop.default 1e-6] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.] [@sop.validate "tolerance must be finite and non-negative"];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"] [@sop.nonblank "empty base group name"];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_non_planar"] [@@sop.node_label "Group Non-Planar"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@sop.fn "group_non_planar"] [@@sop.args "?base ?merge ~tolerance ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let base = optional_text parameters.base in
    let merge = parameters.merge in
    let tolerance = parameters.tolerance in
    let name = parameters.name in
    Node.Private.make ~label ~operation:"group_non_planar" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_non_planar ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ?base ~merge ~tolerance ~name inputs.(0)
        with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_backface = struct
  type parameters = {
    name : string [@sop.default "backface"] [@sop.label "Group name"] [@sop.nonblank "empty group name"];
    viewpoint_x : float [@sop.default 0.] [@sop.label "Viewpoint X"]
      [@sop.folder "Viewpoint"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "viewpoint"] [@sop.validate "viewpoint must be finite"]
    viewpoint_y : float [@sop.default 0.] [@sop.label "Viewpoint Y"]
      [@sop.folder "Viewpoint"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "viewpoint"] [@sop.validate "viewpoint must be finite"]
    viewpoint_z : float [@sop.default 10.] [@sop.label "Viewpoint Z"]
      [@sop.folder "Viewpoint"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "viewpoint"] [@sop.validate "viewpoint must be finite"]
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"] [@sop.nonblank "empty base group name"];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_backface"] [@@sop.node_label "Group Backfaces"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@sop.fn "group_backface"] [@@sop.args "?base ?merge ~viewpoint ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let base = optional_text parameters.base in
    let merge = parameters.merge in
    let viewpoint = Vec3.create parameters.viewpoint_x parameters.viewpoint_y
            parameters.viewpoint_z in
    let name = parameters.name in
    let viewpoint = vec3_copy viewpoint in
    Node.Private.make ~label ~operation:"group_backface" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_backface ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ?base ~merge ~viewpoint ~name inputs.(0)
        with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_unshared = struct
  type parameters = {
    owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_edges]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "unshared"] [@sop.label "Group name"] [@sop.nonblank "empty output group name"];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_unshared"] [@@sop.node_label "Group Unshared"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@sop.fn "group_unshared"] [@@sop.args "?merge ~owner ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let merge = parameters.merge in
    let owner = parameters.owner in
    let name = parameters.name in
    Node.Private.make ~label ~operation:"group_unshared" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_unshared ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ~merge ~owner ~name inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_edges = struct
  let incidence_parameter = Parameter.choice ~equal:( = ) [
      "Any", Rdk.Group_mesh.Any_edge; "Boundary", Rdk.Group_mesh.Boundary_edge;
      "Manifold", Rdk.Group_mesh.Manifold_edge;
      "Non-manifold", Rdk.Group_mesh.Non_manifold_edge;
    ]
  let angle_basis_parameter = Parameter.choice ~equal:( = ) [
      "Primitive dihedral", Rdk.Group_mesh.Primitive_dihedral;
      "Incident edges", Rdk.Group_mesh.Incident_edges;
    ]
  type parameters = {
    name : string [@sop.default "edges"] [@sop.label "Group name"] [@sop.nonblank "empty group name"];
    group : string [@sop.default ""] [@sop.label "Primitive group"] [@sop.nonblank "empty primitive group name"];
    incidence : Rdk.Group_mesh.incidence [@sop.default Rdk.Group_mesh.Any_edge]
      [@sop.label "Incidence"] [@sop.kind incidence_parameter];
    use_min_length : bool [@sop.default false] [@sop.label "Minimum length"]
      [@sop.folder "Length"];
    min_length : float [@sop.default 0.] [@sop.label "Minimum"]
      [@sop.folder "Length"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.] [@sop.present "use_min_length"];
    use_max_length : bool [@sop.default false] [@sop.label "Maximum length"]
      [@sop.folder "Length"];
    max_length : float [@sop.default 1.] [@sop.label "Maximum"]
      [@sop.folder "Length"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.] [@sop.present "use_max_length"];
    angle_basis : Rdk.Group_mesh.angle_basis
      [@sop.default Rdk.Group_mesh.Primitive_dihedral]
      [@sop.label "Angle basis"] [@sop.folder "Angle"]
      [@sop.kind angle_basis_parameter];
    use_min_angle : bool [@sop.default false] [@sop.label "Minimum angle"]
      [@sop.folder "Angle"];
    min_angle : float [@sop.default 0.] [@sop.label "Minimum"]
      [@sop.folder "Angle"] [@sop.min 0.] [@sop.max 3.141592653589793] [@sop.present "use_min_angle"];
    use_max_angle : bool [@sop.default false] [@sop.label "Maximum angle"]
      [@sop.folder "Angle"];
    max_angle : float [@sop.default 3.141592653589793]
      [@sop.label "Maximum"] [@sop.folder "Angle"] [@sop.min 0.]
      [@sop.max 3.141592653589793] [@sop.present "use_max_angle"];
  } [@@sop.node_key "group_edges"] [@@sop.node_label "Group Edges"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@sop.fn "group_edges"] [@@sop.args "?name ?group ?incidence ?min_length ?max_length ?angle_basis ?min_angle ?max_angle in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let name = parameters.name in
    let group = optional_text parameters.group in
    let incidence = parameters.incidence in
    let min_length = if parameters.use_min_length then Some parameters.min_length
            else None in
    let max_length = if parameters.use_max_length then Some parameters.max_length
            else None in
    let angle_basis = parameters.angle_basis in
    let min_angle = if parameters.use_min_angle then Some parameters.min_angle
            else None in
    let max_angle = if parameters.use_max_angle then Some parameters.max_angle
            else None in
    Node.Private.make ?label ~operation:"group_edges" ~version:2
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        let primitives = match group with
          | None -> Ok None
          | Some group_name ->
              (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive
                  group_name inputs.(0) with
               | Some value -> Ok (Some value)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   ~hints:["Create the primitive group before Edge Group"]
                   (Printf.sprintf "group_edges could not find primitive group %S"
                     group_name))) in
        match primitives with
        | Error _ as error -> error
        | Ok primitives ->
            match Rdk.Group_mesh.group_edges ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ~name ?primitives ~incidence
                ?min_length ?max_length ~angle_basis ?min_angle ?max_angle
                inputs.(0) with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_random = struct
  type parameters = {
    owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "random"] [@sop.label "Group name"] [@sop.nonblank "empty group name"];
    probability : float [@sop.default 0.5] [@sop.label "Probability"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.] [@sop.validate "probability must be in [0,1]"];
    context_seed : bool [@sop.default false] [@sop.label "Use context seed"]
      [@sop.folder "Random"];
    seed : int [@sop.default 0] [@sop.label "Seed"]
      [@sop.folder "Random"] [@sop.min 0] [@sop.max 9999] [@sop.absent "context_seed"];
    seed_attribute : string [@sop.default ""] [@sop.label "Seed attribute"]
      [@sop.folder "Random"] [@sop.nonblank "empty seed attribute name"];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"] [@sop.nonblank "empty base group name"];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_random"] [@@sop.node_label "Group Random"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@sop.fn "group_random"] [@@sop.args "?seed ?seed_attribute ?base ?merge ~probability ~owner ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let seed = if parameters.context_seed then None else Some parameters.seed in
    let seed_attribute = optional_text parameters.seed_attribute in
    let base = optional_text parameters.base in
    let merge = parameters.merge in
    let probability = parameters.probability in
    let owner = parameters.owner in
    let name = parameters.name in
    let dependencies = match seed with
      | Some _ -> Context.Dependencies.static
      | None -> Context.Dependencies.one Context.Dependencies.Seed in
    let stable_identity = Option.map (fun label ->
      stable_string_hash ("group_random:" ^ label)) label in
    Node.Private.make ?label ~operation:"group_random" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs:[|input|]
      (fun ~node_id context inputs ->
        let identity = Option.value ~default:(Int64.of_int node_id)
            stable_identity in
        let seed = Rand.seed (Option.value ~default:(mixed_seed context identity)
            seed) in
        match Rdk.Group_ops.group_random ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ~seed ?seed_attribute ?base ~merge
            ~probability ~owner ~name inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build

  let create ?label:node_label ?(seed = parameters_default.seed) ~probability
      ~owner ~name input =
    build ~label:(label "group-random" node_label) ~inputs:[input]
      { parameters_default with seed; probability; owner; name }
  let fn = parameters_fn build
end

module Group_edge_depth = struct
  type parameters = {
    point_group : string [@sop.default "seed"] [@sop.label "Seed point group"] [@sop.nonblank "empty seed point group name"];
    name : string [@sop.default "depth"] [@sop.label "Output group"] [@sop.nonblank "empty output group name"];
    depth : int [@sop.default 1] [@sop.label "Depth"] [@sop.min 0]
      [@sop.max 100] [@sop.hard_min 0];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_edge_depth"] [@@sop.node_label "Group Edge Depth"]
    [@@sop.node_category "Group/Expand"] [@@sop.node_inputs 1]
    [@@sop.fn "group_edge_depth"] [@@sop.args "?merge ~depth ~point_group ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let merge = parameters.merge in
    let depth = parameters.depth in
    let point_group = parameters.point_group in
    let name = parameters.name in
    Node.Private.make ?label ~operation:"group_edge_depth" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_edge_depth ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ~merge ~depth ~point_group ~name
            inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_boundary_components = struct
  let conflict_parameter = Parameter.choice ~equal:( = ) [
      "Replace", Rdk.Group_ops.Name_replace; "Union", Rdk.Group_ops.Name_union;
    ]
  type parameters = {
    prefix : string [@sop.default "boundary"] [@sop.label "Group prefix"] [@sop.nonblank "empty output prefix"];
    conflict : Rdk.Group_ops.name_conflict
      [@sop.default Rdk.Group_ops.Name_replace] [@sop.label "Conflict"]
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
    [@@sop.fn "group_boundary_components"] [@@sop.args "?prefix ?conflict ?max_groups ?max_payload_bytes in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let prefix = parameters.prefix in
    let conflict = parameters.conflict in
    let max_groups = parameters.max_groups in
    let max_payload_bytes = parameters.max_payload_bytes in
    Node.Private.make ?label ~operation:"group_boundary_components" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_boundary_components
            ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
            ~prefix ~conflict ~max_groups ~max_payload_bytes inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_from_attribute_boundary = struct
  type parameters = {
    owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_edges]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "attribute_boundary"]
      [@sop.label "Group name"] [@sop.nonblank "empty group name"];
    attributes : Rdk.Group_ops.boundary_attribute list [@sop.default []]
      [@sop.label "Attributes (owner, pattern)"]
      [@sop.kind boundary_attributes_parameter];
    tolerance : float [@sop.default 0.00001] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.arg_default (1e-6)];
    include_unshared_edges : bool [@sop.default false]
      [@sop.label "Include unshared edges"];
    include_all_unshared_curve_edges : bool [@sop.default false]
      [@sop.label "Include all unshared curve edges"];
    include_all_primitives_sharing_boundary_points : bool [@sop.default false]
      [@sop.label "Include primitives sharing boundary points"];
  } [@@sop.node_key "group_from_attribute_boundary"]
    [@@sop.node_label "Group from Attribute Boundary"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@sop.fn "group_from_attribute_boundary"] [@@sop.args "?attributes ?tolerance ?include_unshared_edges ?include_all_unshared_curve_edges ?include_all_primitives_sharing_boundary_points ~owner ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let attributes = parameters.attributes in
    let tolerance = parameters.tolerance in
    let include_unshared_edges = parameters.include_unshared_edges in
    let include_all_unshared_curve_edges = parameters.include_all_unshared_curve_edges in
    let include_all_primitives_sharing_boundary_points = parameters.include_all_primitives_sharing_boundary_points in
    let owner = parameters.owner in
    let name = parameters.name in
    let attributes = List.map (fun (rule : Rdk.Group_ops.boundary_attribute) ->
      { Rdk.Group_ops.boundary_attribute_owner = rule.boundary_attribute_owner;
        boundary_attribute_pattern = rule.boundary_attribute_pattern }) attributes in
    Node.Private.make ?label ~operation:"group_from_attribute_boundary" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_from_attribute_boundary
            ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
            ~attributes ~tolerance ~include_unshared_edges
            ~include_all_unshared_curve_edges
            ~include_all_primitives_sharing_boundary_points ~owner ~name inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Groups_from_name = struct
  let conflict_parameter = Parameter.choice ~equal:( = ) [
      "Replace", Rdk.Group_ops.Name_replace; "Union", Rdk.Group_ops.Name_union;
    ]
  let invalid_parameter = Parameter.choice ~equal:( = ) [
      "Ignore invalid", Rdk.Group_ops.Ignore_invalid;
      "Force valid", Rdk.Group_ops.Force_valid;
    ]
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Primitive]
      [@sop.label "Attribute owner"]
      [@sop.kind element_attribute_owner_parameter];
    attribute : string [@sop.default "name"] [@sop.label "Name attribute"] [@sop.nonblank "empty attribute name"];
    prefix : string [@sop.default ""] [@sop.label "Group prefix"];
    conflict : Rdk.Group_ops.name_conflict
      [@sop.default Rdk.Group_ops.Name_replace] [@sop.label "Conflict"]
      [@sop.kind conflict_parameter];
    invalid_names : Rdk.Group_ops.invalid_name_policy
      [@sop.default Rdk.Group_ops.Ignore_invalid] [@sop.label "Invalid names"]
      [@sop.kind invalid_parameter];
    max_groups : int [@sop.default 4096] [@sop.label "Maximum groups"]
      [@sop.folder "Limits"] [@sop.min 1] [@sop.max 16384]
      [@sop.hard_min 1];
    max_payload_bytes : int [@sop.default 268435456]
      [@sop.label "Maximum payload bytes"] [@sop.folder "Limits"]
      [@sop.min 1048576] [@sop.max 1073741824] [@sop.hard_min 1];
  } [@@sop.node_key "groups_from_name"] [@@sop.node_label "Groups from Name"]
    [@@sop.node_category "Group/Convert"] [@@sop.node_inputs 1]
    [@@sop.fn "groups_from_name"] [@@sop.args "?prefix ?conflict ?invalid_names ?max_groups ?max_payload_bytes ~owner ~attribute in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let prefix = parameters.prefix in
    let conflict = parameters.conflict in
    let invalid_names = parameters.invalid_names in
    let max_groups = parameters.max_groups in
    let max_payload_bytes = parameters.max_payload_bytes in
    let owner = parameters.owner in
    let attribute = parameters.attribute in
    Node.Private.make ?label ~operation:"groups_from_name" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.groups_from_name ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ~prefix ~conflict ~invalid_names
            ~max_groups ~max_payload_bytes ~owner ~attribute inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Name_from_groups = struct
  let overlap_parameter = Parameter.choice ~equal:( = ) [
      "First group", Rdk.Group_ops.First_group; "Last group", Rdk.Group_ops.Last_group;
      "Error on overlap", Rdk.Group_ops.Error_on_overlap;
    ]
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Primitive]
      [@sop.label "Group type"] [@sop.kind element_attribute_owner_parameter];
    attribute : string [@sop.default "name"] [@sop.label "Name attribute"] [@sop.nonblank "empty attribute name"];
    pattern : string [@sop.default "*"] [@sop.label "Group pattern"];
    default : string [@sop.default ""] [@sop.label "Default value"];
    overlap : Rdk.Group_ops.name_overlap [@sop.default Rdk.Group_ops.First_group]
      [@sop.label "Overlapping groups"] [@sop.kind overlap_parameter] [@sop.arg_default (Rdk.Group_ops.Last_group)];
    delete_groups : bool [@sop.default false]
      [@sop.label "Delete source groups"];
  } [@@sop.node_key "name_from_groups"] [@@sop.node_label "Name from Groups"]
    [@@sop.node_category "Group/Convert"] [@@sop.node_inputs 1]
    [@@sop.fn "name_from_groups"] [@@sop.args "?attribute ?pattern ?default ?overlap ?delete_groups ~owner in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let attribute = parameters.attribute in
    let pattern = parameters.pattern in
    let default = parameters.default in
    let overlap = parameters.overlap in
    let delete_groups = parameters.delete_groups in
    let owner = parameters.owner in
    Node.Private.make ?label ~operation:"name_from_groups" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.name_from_groups ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ~attribute ~pattern ~default ~overlap
            ~delete_groups ~owner inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_promote_boundary = struct
  type parameters = {
    source : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_primitives]
      [@sop.label "Source owner"] [@sop.kind group_owner_parameter];
    destination : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_edges]
      [@sop.label "Destination owner"] [@sop.kind group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Source group"] [@sop.nonblank "empty group name"];
    name : string [@sop.default ""] [@sop.label "New group name"] [@sop.nonblank "empty output name"];
    keep_original : bool [@sop.default false]
      [@sop.label "Keep original group"];
    output_attribute : string [@sop.default ""]
      [@sop.label "Output mask attribute"] [@sop.folder "Output"] [@sop.nonblank "empty output attribute name"];
    attributes : Rdk.Group_ops.boundary_attribute list [@sop.default []]
      [@sop.label "Boundary attributes (owner, pattern)"]
      [@sop.kind boundary_attributes_parameter];
    tolerance : float [@sop.default 0.00001] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.arg_default (1e-6)];
    include_unshared_edges : bool [@sop.default false]
      [@sop.label "Include unshared edges"];
    include_all_unshared_curve_edges : bool [@sop.default false]
      [@sop.label "Include all unshared curve edges"];
    include_all_primitives_sharing_boundary_points : bool [@sop.default false]
      [@sop.label "Include primitives sharing boundary points"];
  } [@@sop.node_key "group_promote_boundary"]
    [@@sop.node_label "Group Promote Boundary"]
    [@@sop.node_category "Group/Convert"] [@@sop.node_inputs 1]
    [@@sop.fn "group_promote_boundary"] [@@sop.args "?name ?keep_original ?output_attribute ?attributes ?tolerance ?include_unshared_edges ?include_all_unshared_curve_edges ?include_all_primitives_sharing_boundary_points ~source ~destination ~group in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let name = optional_text parameters.name in
    let keep_original = parameters.keep_original in
    let output_attribute = optional_text parameters.output_attribute in
    let attributes = parameters.attributes in
    let tolerance = parameters.tolerance in
    let include_unshared_edges = parameters.include_unshared_edges in
    let include_all_unshared_curve_edges = parameters.include_all_unshared_curve_edges in
    let include_all_primitives_sharing_boundary_points = parameters.include_all_primitives_sharing_boundary_points in
    let source = parameters.source in
    let destination = parameters.destination in
    let group = parameters.group in
    let attributes = List.map (fun (rule : Rdk.Group_ops.boundary_attribute) ->
      { Rdk.Group_ops.boundary_attribute_owner = rule.boundary_attribute_owner;
        boundary_attribute_pattern = rule.boundary_attribute_pattern }) attributes in
    Node.Private.make ?label ~operation:"group_promote_boundary" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_promote_boundary
            ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
            ?name ~keep_original ?output_attribute ~attributes ~tolerance
            ~include_unshared_edges ~include_all_unshared_curve_edges
            ~include_all_primitives_sharing_boundary_points
            ~source ~destination ~group inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_delete = struct
  let encode_rule (rule : Rdk.Group_ops.delete_rule) = [
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
          Rdk.Group_ops.delete_owner; delete_pattern = pattern }) owner
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
    rules : Rdk.Group_ops.delete_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern)"] [@sop.kind rules_parameter];
    delete_unused : bool [@sop.default false]
      [@sop.label "Delete unused groups"];
  } [@@sop.node_key "group_delete"] [@@sop.node_label "Group Delete"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@sop.fn "group_delete"] [@@sop.args "?delete_unused ~rules in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let delete_unused = parameters.delete_unused in
    let rules = parameters.rules in
    let rules = List.map (fun (rule : Rdk.Group_ops.delete_rule) ->
      { Rdk.Group_ops.delete_owner = rule.delete_owner;
        delete_pattern = rule.delete_pattern }) rules in
    Node.Private.make ?label ~operation:"group_delete" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
        match Rdk.Group_ops.delete ~rules ~delete_unused inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_rename = struct
  let conflict_token = function
    | Rdk.Group_ops.Rename_skip -> "skip"
    | Rdk.Group_ops.Rename_error -> "error"
    | Rdk.Group_ops.Rename_overwrite -> "overwrite"
    | Rdk.Group_ops.Rename_union -> "union"
  let conflict_of_token = function
    | "skip" -> Ok Rdk.Group_ops.Rename_skip
    | "error" -> Ok Rdk.Group_ops.Rename_error
    | "overwrite" -> Ok Rdk.Group_ops.Rename_overwrite
    | "union" -> Ok Rdk.Group_ops.Rename_union
    | token -> Error (Printf.sprintf "unknown group rename conflict %S" token)
  let encode_rule (rule : Rdk.Group_ops.rename_rule) = [
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
            Rdk.Group_ops.rename_owner; rename_pattern = pattern;
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
    rules : Rdk.Group_ops.rename_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, replacement, conflict)"]
      [@sop.kind rules_parameter];
  } [@@sop.node_key "group_rename"] [@@sop.node_label "Group Rename"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@sop.fn "group_rename"] [@@sop.args "~rules in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let rules = parameters.rules in
    let rules = List.map (fun (rule : Rdk.Group_ops.rename_rule) ->
      { Rdk.Group_ops.rename_owner = rule.rename_owner;
        rename_pattern = rule.rename_pattern;
        rename_replacement = rule.rename_replacement;
        rename_conflict = rule.rename_conflict }) rules in
    Node.Private.make ?label ~operation:"group_rename" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
        match Rdk.Group_ops.rename ~rules inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_copy = struct
  let encode_rule (rule : Rdk.Group_ops.copy_rule) = [
      group_owner_token rule.copy_owner; rule.copy_pattern; rule.copy_prefix;
      Option.value ~default:"" rule.match_attribute;
    ]
  let decode_rule = function
    | [owner; pattern; prefix; match_attribute] ->
        Result.map (fun copy_owner -> { Rdk.Group_ops.copy_owner;
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
    rules : Rdk.Group_ops.copy_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, prefix, match attribute)"]
      [@sop.kind rules_parameter] [@sop.present "use_rules"];
    conflict : Rdk.Group_ops.copy_conflict
      [@sop.default Rdk.Group_ops.Copy_overwrite] [@sop.label "Conflict"]
      [@sop.kind group_copy_conflict_parameter] [@sop.arg_default (Rdk.Group_ops.Copy_skip)];
    copy_empty : bool [@sop.default false] [@sop.label "Copy empty groups"];
  } [@@sop.node_key "group_copy"] [@@sop.node_label "Group Copy"]
    [@@sop.node_category "Group/Transfer"] [@@sop.node_inputs 2] [@@sop.node_slots "source, target"]
    [@@sop.fn "group_copy"] [@@sop.args "?rules ?conflict ?copy_empty ~source ~target ()"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters source target ->
    let label = Some label in
    let rules = if parameters.use_rules then Some parameters.rules else None in
    let conflict = parameters.conflict in
    let copy_empty = parameters.copy_empty in
    let rules = Option.map (List.map (fun (rule : Rdk.Group_ops.copy_rule) ->
      { Rdk.Group_ops.copy_owner = rule.copy_owner;
        copy_pattern = rule.copy_pattern;
        copy_prefix = rule.copy_prefix;
        match_attribute = rule.match_attribute })) rules in
    Node.Private.make ?label ~operation:"group_copy" ~version:1
      ~parameters:""
      ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
      ~inputs:[|source; target|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.copy ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ?rules ~conflict ~copy_empty
            ~source:inputs.(0) ~target:inputs.(1) () with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_transfer = struct
  let encode_rule (rule : Rdk.Group_ops.transfer_rule) = [
      group_owner_token rule.transfer_owner; rule.transfer_pattern;
      rule.transfer_prefix;
    ]
  let decode_rule = function
    | [owner; pattern; prefix] ->
        Result.map (fun transfer_owner -> { Rdk.Group_ops.transfer_owner;
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
    rules : Rdk.Group_ops.transfer_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, prefix)"]
      [@sop.kind rules_parameter] [@sop.present "use_rules"];
    conflict : Rdk.Group_ops.copy_conflict
      [@sop.default Rdk.Group_ops.Copy_overwrite] [@sop.label "Conflict"]
      [@sop.kind group_copy_conflict_parameter] [@sop.arg_default (Rdk.Group_ops.Copy_skip)];
    create_empty : bool [@sop.default false]
      [@sop.label "Create empty groups"];
    distance : float [@sop.default 0.001] [@sop.label "Maximum distance"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
  } [@@sop.node_key "group_transfer"] [@@sop.node_label "Group Transfer"]
    [@@sop.node_category "Group/Transfer"] [@@sop.node_inputs 2] [@@sop.node_slots "source, target"]
    [@@sop.fn "group_transfer"] [@@sop.args "?rules ?conflict ?create_empty ?distance ~source ~target ()"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters source target ->
    let label = Some label in
    let rules = if parameters.use_rules then Some parameters.rules else None in
    let conflict = parameters.conflict in
    let create_empty = parameters.create_empty in
    let distance = parameters.distance in
    let rules = Option.map (List.map (fun (rule : Rdk.Group_ops.transfer_rule) ->
      { Rdk.Group_ops.transfer_owner = rule.transfer_owner;
        transfer_pattern = rule.transfer_pattern;
        transfer_prefix = rule.transfer_prefix })) rules in
    Node.Private.make ?label ~operation:"group_transfer" ~version:1
      ~parameters:""
      ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
      ~inputs:[|source; target|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.transfer ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ?rules ~conflict ~create_empty ~distance
            ~source:inputs.(0) ~target:inputs.(1) () with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_find_path = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Through each", Rdk.Group_mesh.Through_each;
      "Start/end pairs", Rdk.Group_mesh.Start_end_pairs;
    ]
  let ending_parameter = Parameter.choice ~equal:( = ) [
      "Stop at end", Rdk.Group_mesh.Stop_at_end; "Close path", Rdk.Group_mesh.Close_path;
    ]
  type parameters = {
    owner : Rdk.Group.owner [@sop.default Rdk.Group.Point]
      [@sop.label "Group type"] [@sop.kind ordinary_group_owner_parameter];
    base_group : string [@sop.default "ordered"] [@sop.label "Base group"];
    name : string [@sop.default "path"] [@sop.label "Output group"];
    mode : Rdk.Group_mesh.path_mode [@sop.default Rdk.Group_mesh.Through_each]
      [@sop.label "Path mode"] [@sop.kind mode_parameter];
    ending : Rdk.Group_mesh.path_ending [@sop.default Rdk.Group_mesh.Stop_at_end]
      [@sop.label "Ending"] [@sop.kind ending_parameter];
    avoid_self_intersection : bool [@sop.default true]
      [@sop.label "Avoid self-intersection"];
    collision_group : string [@sop.default ""]
      [@sop.label "Collision group"] [@sop.folder "Collision"];
    contain : bool [@sop.default false] [@sop.label "Contain path"]
      [@sop.folder "Collision"];
  } [@@sop.node_key "group_find_path"] [@@sop.node_label "Group Find Path"]
    [@@sop.node_category "Group/Path"] [@@sop.node_inputs 1]
    [@@sop.fn "group_find_path"] [@@sop.args "?mode ?ending ?avoid_self_intersection ?owner ?collision_group ?contain ~base_group ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let mode = parameters.mode in
    let ending = parameters.ending in
    let avoid_self_intersection = parameters.avoid_self_intersection in
    let owner = parameters.owner in
    let collision_group = optional_text parameters.collision_group in
    let contain = parameters.contain in
    let base_group = parameters.base_group in
    let name = parameters.name in
    Node.Private.make ?label ~operation:"group_find_path" ~version:2
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        let geometry = inputs.(0) in
        match Rdk.Geometry.find_group ~owner base_group geometry with
        | None -> Error (Diagnostic.error ~code:"missing_group"
            (Printf.sprintf "group_find_path could not find %s group %S"
              (group_owner_key owner) base_group))
        | Some base ->
            let collision = match collision_group with
              | None -> Ok None
              | Some group ->
                  (match Rdk.Geometry.find_group ~owner group geometry with
                   | Some group -> Ok (Some group)
                   | None -> Error (Diagnostic.error ~code:"missing_group"
                       (Printf.sprintf
                         "group_find_path could not find collision %s group %S"
                         (group_owner_key owner) group))) in
            Result.bind collision (fun collision ->
              match Rdk.Group_mesh.group_find_path
                  ~cancel:(Context.cancel_token context)
                  ~grain:(Context.grain context) ~mode ~ending
                  ~avoid_self_intersection ?collision ~contain ~base ~name geometry with
              | Ok geometry -> cooked geometry
              | Error error -> structured_rdk_error error)))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Delete_edge_group = struct
  type parameters = {
    name : string [@sop.default "edges"] [@sop.label "Edge group"] [@sop.nonblank "empty name"];
  } [@@sop.node_key "delete_edge_group"]
    [@@sop.node_label "Delete Edge Group"]
    [@@sop.node_category "Group/Manage"] [@@sop.node_inputs 1]
    [@@sop.fn "delete_edge_group"] [@@sop.args "~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let name = parameters.name in
    Node.Private.make ?label ~operation:"delete_edge_group" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
        cooked (Rdk.Geometry.without_edge_group name inputs.(0))))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Rename_edge_group = struct
  type parameters = {
    from : string [@sop.default "edges"] [@sop.label "From"] [@sop.nonblank "empty name"];
    into : string [@sop.default "renamed"] [@sop.label "To"] [@sop.nonblank "empty name"];
  } [@@sop.node_key "rename_edge_group"]
    [@@sop.node_label "Rename Edge Group"]
    [@@sop.node_category "Group/Manage"] [@@sop.node_inputs 1]
    [@@sop.fn "rename_edge_group"] [@@sop.args "~from ~into in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let from = parameters.from in
    let into = parameters.into in
    Node.Private.make ?label ~operation:"rename_edge_group" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
        match Rdk.Geometry.rename_edge_group ~from ~into inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error message -> rdk_error "rename_edge_group" message))
  let factory = parameters_factory build
  let fn = parameters_fn build
end
