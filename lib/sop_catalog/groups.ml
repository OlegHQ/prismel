open Rays_math
open Procedural
open Shared

module Group_bounds = struct
  type shape = Box | Sphere
  let shape_parameter = Parameter.choice ~equal:( = ) [
      "Box", Box; "Sphere", Sphere;
    ]
  let containment_parameter = Parameter.choice ~equal:( = ) [
      "Fully contained", Rdk.Group_ops.Fully_contained;
      "Partially contained", Rdk.Group_ops.Partially_contained;
    ]
  type parameters = {
    owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "bounds"] [@sop.label "Group name"];
    shape : shape [@sop.default Box] [@sop.label "Bounding shape"]
      [@sop.kind shape_parameter];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Bounds/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Bounds/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Bounds/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    size_x : float [@sop.default 1.] [@sop.label "Size X"]
      [@sop.folder "Bounds/Size"] [@sop.min 0.] [@sop.max 20.]
      [@sop.hard_min 0.]; [@sop.vec3 "size"]
    size_y : float [@sop.default 1.] [@sop.label "Size Y"]
      [@sop.folder "Bounds/Size"] [@sop.min 0.] [@sop.max 20.]
      [@sop.hard_min 0.]; [@sop.vec3 "size"]
    size_z : float [@sop.default 1.] [@sop.label "Size Z"]
      [@sop.folder "Bounds/Size"] [@sop.min 0.] [@sop.max 20.]
      [@sop.hard_min 0.]; [@sop.vec3 "size"]
    radius : float [@sop.default 0.5] [@sop.label "Radius"]
      [@sop.folder "Bounds"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"];
    containment : Rdk.Group_ops.containment
      [@sop.default Rdk.Group_ops.Fully_contained] [@sop.label "Containment"]
      [@sop.folder "Combine"] [@sop.kind containment_parameter];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_bounds"] [@@sop.node_label "Group by Bounds"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let bounds parameters =
    let center = Vec3.create parameters.center_x parameters.center_y
        parameters.center_z in
    match parameters.shape with
    | Sphere -> Rdk.Group_ops.Bounds_sphere { center; radius = parameters.radius }
    | Box -> let half = Vec3.create (parameters.size_x *. 0.5)
          (parameters.size_y *. 0.5) (parameters.size_z *. 0.5) in
        Rdk.Group_ops.Bounds_box { minimum = Vec3.sub center half;
          maximum = Vec3.add center half }
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_bounds ~label ?base:(optional_text parameters.base)
        ~containment:parameters.containment ~merge:parameters.merge
        (bounds parameters) ~owner:parameters.owner ~name:parameters.name input)
  let factory = parameters_factory build
end

module Group_normal = struct
  type parameters = {
    owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_primitives]
      [@sop.label "Group type"] [@sop.kind group_normal_owner_parameter];
    name : string [@sop.default "normal"] [@sop.label "Group name"];
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
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
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
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

module Group_promotions = struct
  let bool_token value = if value then "true" else "false"
  let bool_of_token = function
    | "true" | "1" | "yes" -> Ok true
    | "false" | "0" | "no" -> Ok false
    | token -> Error (Printf.sprintf "expected boolean, got %S" token)
  let encode_attributes attributes = encode_table (List.map
      (fun (attribute : Rdk.Group_ops.boundary_attribute) ->
        [attribute_owner_token attribute.boundary_attribute_owner;
         attribute.boundary_attribute_pattern]) attributes)
  let decode_attributes text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun attributes ->
        match row with
        | [owner; pattern] -> Result.map (fun boundary_attribute_owner ->
            { Rdk.Group_ops.boundary_attribute_owner;
              boundary_attribute_pattern = pattern } :: attributes)
            (attribute_owner_of_token
              (String.lowercase_ascii (String.trim owner)))
        | row -> Error (Printf.sprintf
            "boundary attribute needs owner and pattern, got %d columns"
            (List.length row)))) (Ok []) rows |> Result.map List.rev)
  let encode_operation = function
    | Rdk.Group_ops.Promote_elements mode ->
        let token = match mode with
          | Rdk.Group_ops.Include_any -> "any"
          | Rdk.Group_ops.Include_all -> "all"
          | Rdk.Group_ops.Include_shared_edge -> "shared_edge" in
        [token; "0"; "false"; "false"; "false"; ""]
    | Rdk.Group_ops.Promote_boundary options -> [
        "boundary"; Printf.sprintf "%.17g" options.promote_boundary_tolerance;
        bool_token options.promote_include_unshared_edges;
        bool_token options.promote_include_all_unshared_curve_edges;
        bool_token options.promote_include_all_primitives_sharing_boundary_points;
        encode_attributes options.promote_boundary_attributes;
      ]
  let decode_operation = function
    | [kind; tolerance; unshared; all_curve; all_primitives; attributes] ->
        (match String.lowercase_ascii (String.trim kind) with
         | "any" -> Ok (Rdk.Group_ops.Promote_elements Rdk.Group_ops.Include_any)
         | "all" -> Ok (Rdk.Group_ops.Promote_elements Rdk.Group_ops.Include_all)
         | "shared_edge" | "shared edge" ->
             Ok (Rdk.Group_ops.Promote_elements Rdk.Group_ops.Include_shared_edge)
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
                                Rdk.Group_ops.Promote_boundary {
                                  Rdk.Group_ops.promote_boundary_attributes;
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
  let encode_rule (rule : Rdk.Group_ops.promotion_rule) = [
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
                    Rdk.Group_ops.promotion_source; promotion_destination;
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
      Rdk.Group_ops.promotion_source = Rdk.Group_ops.Group_points;
      promotion_destination = Rdk.Group_ops.Group_primitives;
      promotion_pattern = "*"; promotion_new_name = None;
      promotion_keep_original = false;
      promotion_output_as_attribute = false;
      promotion_operation = Rdk.Group_ops.Promote_elements Rdk.Group_ops.Include_any;
    }]
  type parameters = {
    rules : Rdk.Group_ops.promotion_rule list [@sop.default default_rules]
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
  type owner = Any | Owner of Rdk.Group_ops.owner
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Any", Any; "Points", Owner Rdk.Group_ops.Group_points;
      "Vertices", Owner Rdk.Group_ops.Group_vertices;
      "Primitives", Owner Rdk.Group_ops.Group_primitives;
      "Edges", Owner Rdk.Group_ops.Group_edges;
    ]
  type parameters = {
    owner : owner [@sop.default Any] [@sop.label "Group type"]
      [@sop.kind owner_parameter];
    pattern : string [@sop.default "*"] [@sop.label "Group pattern"];
    new_name : string [@sop.default ""] [@sop.label "New name pattern"];
    conflict : Rdk.Group_ops.rename_conflict
      [@sop.default Rdk.Group_ops.Rename_overwrite] [@sop.label "Conflict"]
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

module Group_combine = struct
  let bool_token value = if value then "true" else "false"
  let bool_of_token = function
    | "true" | "1" | "yes" -> Ok true
    | "false" | "0" | "no" -> Ok false
    | token -> Error (Printf.sprintf "expected boolean, got %S" token)
  let encode_step (step : Rdk.Group_ops.combine_step) = [
      group_boolean_token step.operation; step.operand.pattern;
      bool_token step.operand.inverted;
    ]
  let decode_step = function
    | [operation; pattern; inverted] ->
        Result.bind (group_boolean_of_token
          (String.lowercase_ascii (String.trim operation)))
          (fun operation -> Result.map (fun inverted -> {
            Rdk.Group_ops.operation; operand = { pattern; inverted } })
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
    owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "combined"] [@sop.label "Output group"];
    base_pattern : string [@sop.default "*"] [@sop.label "Base pattern"];
    base_inverted : bool [@sop.default false] [@sop.label "Invert base"];
    steps : Rdk.Group_ops.combine_step list [@sop.default []]
      [@sop.label "Steps (operation, pattern, invert)"]
      [@sop.kind steps_parameter];
  } [@@sop.node_key "group_combine"] [@@sop.node_label "Group Combine"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_combine ~label ~owner:parameters.owner
        ~name:parameters.name ~base:{ Rdk.Group_ops.pattern = parameters.base_pattern;
          inverted = parameters.base_inverted }
        ~steps:parameters.steps input)
  let factory = parameters_factory build
end

module Group_expand = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Share points", Rdk.Group_ops.Primitive_share_points;
      "Share edges", Rdk.Group_ops.Primitive_share_edges;
    ]
  type parameters = {
    owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Source group"];
    name : string [@sop.default ""] [@sop.label "Output group"];
    steps : int [@sop.default 1] [@sop.label "Steps"]
      [@sop.min (-100)] [@sop.max 100];
    flood : bool [@sop.default false] [@sop.label "Flood fill"];
    step_attribute : string [@sop.default ""]
      [@sop.label "Step attribute"] [@sop.folder "Output"];
    primitive_connectivity : Rdk.Group_ops.primitive_connectivity
      [@sop.default Rdk.Group_ops.Primitive_share_points]
      [@sop.label "Primitive connectivity"]
      [@sop.folder "Connectivity"] [@sop.kind connectivity_parameter];
    normal_spread : float [@sop.default 3.141592653589793]
      [@sop.label "Normal spread"] [@sop.folder "Connectivity/Normals"]
      [@sop.min 0.] [@sop.max 3.141592653589793]
      [@sop.hard_min 0.] [@sop.hard_max 3.141592653589793];
    use_normal_attribute : bool [@sop.default false]
      [@sop.label "Use normal attribute"] [@sop.folder "Connectivity/Normals"];
    normal_owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Primitive]
      [@sop.label "Normal owner"] [@sop.folder "Connectivity/Normals"]
      [@sop.kind element_attribute_owner_parameter];
    normal_name : string [@sop.default "N"] [@sop.label "Normal attribute"]
      [@sop.folder "Connectivity/Normals"];
    connectivity_attributes : Rdk.Group_ops.boundary_attribute list
      [@sop.default []] [@sop.label "Boundary attributes (owner, pattern)"]
      [@sop.folder "Connectivity"] [@sop.kind boundary_attributes_parameter];
    connectivity_tolerance : float [@sop.default 0.00001]
      [@sop.label "Attribute tolerance"] [@sop.folder "Connectivity"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    use_collision : bool [@sop.default false]
      [@sop.label "Use collision group"] [@sop.folder "Collision"];
    collision_owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_edges]
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
        Rdk.Group_ops.expand_normal_owner = parameters.normal_owner;
        expand_normal_name = parameters.normal_name } else None
    and collision = if parameters.use_collision then Some {
        Rdk.Group_ops.expand_collision_owner = parameters.collision_owner;
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
    owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "range"] [@sop.label "Output group"];
    base : string [@sop.default ""] [@sop.label "Base group"];
    invert : bool [@sop.default false] [@sop.label "Invert range"];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Merge"]
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
    collision_owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_edges]
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
    | Start_end -> Rdk.Group_ops.Range_start_end {
        start = parameters.start; end_ = parameters.end_ }
    | From_ends -> Rdk.Group_ops.Range_from_ends {
        start = parameters.start; end_offset = parameters.end_offset }
    | Start_length -> Rdk.Group_ops.Range_start_length {
        start = parameters.start; length = parameters.length }
    | Partition -> Rdk.Group_ops.Range_partition {
        partition = parameters.partition; partitions = parameters.partitions }
  let filter parameters = if parameters.use_filter then Some {
      Rdk.Group_ops.select = parameters.filter_select; of_ = parameters.filter_of;
      offset = parameters.filter_offset } else None
  let connectivity parameters =
    let region = if parameters.use_region then Some parameters.region else None in
    match parameters.connectivity_mode with
    | No_connectivity -> None
    | Disconnected -> Some (Rdk.Group_ops.Range_disconnected { region })
    | Connected ->
        let collision = if parameters.use_collision then Some {
            Rdk.Group_ops.collision_owner = parameters.collision_owner;
            collision_pattern = parameters.collision_pattern;
            keep_boundary = parameters.keep_boundary } else None in
        Some (Rdk.Group_ops.Range_connected {
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
    | Rdk.Group_ops.Range_start_end { start; end_ } ->
        ["start_end"; string_of_int start; string_of_int end_]
    | Rdk.Group_ops.Range_from_ends { start; end_offset } ->
        ["from_ends"; string_of_int start; string_of_int end_offset]
    | Rdk.Group_ops.Range_start_length { start; length } ->
        ["start_length"; string_of_int start; string_of_int length]
    | Rdk.Group_ops.Range_partition { partition; partitions } ->
        ["partition"; string_of_int partition; string_of_int partitions]
  let decode_specification = function
    | [kind; a; b] ->
        let ( let* ) = Result.bind in
        let* a = int_of_token a in
        let* b = int_of_token b in
        (match String.lowercase_ascii (String.trim kind) with
         | "start_end" -> Ok (Rdk.Group_ops.Range_start_end { start = a; end_ = b })
         | "from_ends" -> Ok (Rdk.Group_ops.Range_from_ends {
             start = a; end_offset = b })
         | "start_length" -> Ok (Rdk.Group_ops.Range_start_length {
             start = a; length = b })
         | "partition" -> Ok (Rdk.Group_ops.Range_partition {
             partition = a; partitions = b })
         | token -> Error (Printf.sprintf "unknown range kind %S" token))
    | columns -> Error (Printf.sprintf
        "range specification needs 3 columns, got %d" (List.length columns))
  let encode_filter = function
    | None -> ["none"; "0"; "1"; "0"]
    | Some filter -> ["filter"; string_of_int filter.Rdk.Group_ops.select;
        string_of_int filter.of_; string_of_int filter.offset]
  let decode_filter = function
    | [kind; select; of_; offset] ->
        if String.lowercase_ascii (String.trim kind) = "none" then Ok None
        else
          let ( let* ) = Result.bind in
          let* select = int_of_token select in
          let* of_ = int_of_token of_ in
          let* offset = int_of_token offset in
          Ok (Some { Rdk.Group_ops.select; of_; offset })
    | columns -> Error (Printf.sprintf
        "range filter needs 4 columns, got %d" (List.length columns))
  let encode_connectivity = function
    | None -> ["none"; ""; ""; "0"; "false"; "edge"; "";
        "false"; "false"]
    | Some (Rdk.Group_ops.Range_disconnected { region }) -> [
        "disconnected"; Option.fold ~none:"" ~some:string_of_int region;
        ""; "0"; "false"; "edge"; ""; "false"; "false"]
    | Some (Rdk.Group_ops.Range_connected connectivity) ->
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
         | "disconnected" -> Ok (Some (Rdk.Group_ops.Range_disconnected { region }))
         | "connected" ->
             let* connectivity_tolerance = float_of_token tolerance in
             let* collision_enabled = bool_of_token collision_enabled in
             let* collision = if not collision_enabled then Ok None else
               let* collision_owner = group_owner_of_token
                   (String.lowercase_ascii (String.trim collision_owner)) in
               let* keep_boundary = bool_of_token keep_boundary in
               Ok (Some { Rdk.Group_ops.collision_owner; collision_pattern;
                 keep_boundary }) in
             let* remove_other_regions = bool_of_token remove_other_regions in
             Ok (Some (Rdk.Group_ops.Range_connected {
               connectivity_attributes = optional_text attributes;
               connectivity_tolerance; collision; region;
               remove_other_regions }))
         | token -> Error (Printf.sprintf
             "unknown range connectivity %S" token))
    | columns -> Error (Printf.sprintf
        "range connectivity needs 9 columns, got %d" (List.length columns))
  let encode_rule (rule : Rdk.Group_ops.range_rule) =
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
        Ok { Rdk.Group_ops.range_owner; range_name = name;
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
  let default_rules = [Rdk.Group_ops.range_rule
      ~owner:Rdk.Group_ops.Group_points ~name:"range"
      (Rdk.Group_ops.Range_start_end { start = 0; end_ = -1 })]
  type parameters = {
    rules : Rdk.Group_ops.range_rule list [@sop.default default_rules]
      [@sop.label "Range rules"] [@sop.kind rules_parameter];
  } [@@sop.node_key "group_ranges"] [@@sop.node_label "Group Ranges"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.group_ranges ~label parameters.rules input)
  let factory = parameters_factory build
end

module Ordered_group = struct
  let decode text =
    String.split_on_char ' ' (String.map (function
      | ',' | '\t' | '\n' -> ' ' | character -> character) text)
    |> List.filter (fun token -> token <> "")
    |> List.fold_left (fun result token -> Result.bind result (fun elements ->
        Result.bind (int_of_token token) (fun element ->
          if element < 0 then Error (Printf.sprintf
            "expected a non-negative element index, got %d" element)
          else Ok (element :: elements)))) (Ok [])
    |> Result.map List.rev
  let elements_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun elements ->
        String.concat " " (List.map string_of_int elements)) ~decode
  type parameters = {
    owner : Rdk.Group.owner [@sop.default Rdk.Group.Point]
      [@sop.label "Group type"] [@sop.kind ordinary_group_owner_parameter];
    name : string [@sop.default "ordered"] [@sop.label "Output group"];
    elements : int list [@sop.default [0]] [@sop.label "Elements in order"]
      [@sop.kind elements_parameter];
  } [@@sop.node_key "ordered_group"] [@@sop.node_label "Group Ordered"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.ordered_group ~label ~owner:parameters.owner ~name:parameters.name
      (Array.of_list parameters.elements) input)
  let factory = parameters_factory build
end
