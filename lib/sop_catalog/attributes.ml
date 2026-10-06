open Rays
open Procedural
open Shared

module Material = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    material : string [@sop.default ""] [@sop.label "Material"];
    color_r : float [@sop.default 1.] [@sop.label "Red"] [@sop.vec3 "color"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    color_g : float [@sop.default 1.] [@sop.label "Green"] [@sop.vec3 "color"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    color_b : float [@sop.default 1.] [@sop.label "Blue"] [@sop.vec3 "color"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    roughness : float [@sop.default 0.4] [@sop.label "Roughness"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    emission_r : float [@sop.default 0.] [@sop.label "Emission red"] [@sop.vec3 "emission"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    emission_g : float [@sop.default 0.] [@sop.label "Emission green"] [@sop.vec3 "emission"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
    emission_b : float [@sop.default 0.] [@sop.label "Emission blue"] [@sop.vec3 "emission"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
  } [@@sop.node_key "material"] [@@sop.node_label "Material"]
    [@@sop.node_category "Attribute/Material"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label p input ->
    Sop.material ~label ?group:(optional_text p.group) ~name:p.material
      ~color:(Vec3.create p.color_r p.color_g p.color_b) ~roughness:p.roughness
      ~emission:(Vec3.create p.emission_r p.emission_g p.emission_b) input)
  let factory = parameters_factory build
end


module Attribute_noise_quaternion = struct
  let encode_location = function
    | Rdk.Attribute_ops.Noise_position -> "position"
    | Noise_element_number -> "element-number"
    | Noise_attribute name -> "attribute:" ^ name

  let decode_location = function
    | "position" -> Ok Rdk.Attribute_ops.Noise_position
    | "element-number" -> Ok Noise_element_number
    | value when String.starts_with ~prefix:"attribute:" value ->
        Ok (Noise_attribute (String.sub value 10 (String.length value - 10)))
    | _ -> Error "location must be position, element-number, or attribute:name"

  let location_parameter = Parameter.encoded ~equal:( = )
      ~encode:encode_location ~decode:decode_location

  let encode_numeric value = String.concat "," (match value with
    | Rdk.Attribute_ops.Scalar x -> ["scalar"; string_of_float x]
    | Vec2 value -> ["vec2"; string_of_float value.Vec2.x;
        string_of_float value.y]
    | Vec3 value -> ["vec3"; string_of_float value.Vec3.x;
        string_of_float value.y; string_of_float value.z]
    | Vec4 (x, y, z, w) -> ["vec4"; string_of_float x;
        string_of_float y; string_of_float z; string_of_float w])

  let decode_numeric value = match String.split_on_char ',' value with
    | ["scalar"; x] -> Option.map (fun x -> Rdk.Attribute_ops.Scalar x)
        (float_of_string_opt x)
    | ["vec2"; x; y] ->
        (match float_of_string_opt x, float_of_string_opt y with
         | Some x, Some y -> Some (Vec2 (Vec2.create x y)) | _ -> None)
    | ["vec3"; x; y; z] ->
        (match float_of_string_opt x, float_of_string_opt y,
            float_of_string_opt z with
         | Some x, Some y, Some z -> Some (Vec3 (Vec3.create x y z))
         | _ -> None)
    | ["vec4"; x; y; z; w] ->
        (match float_of_string_opt x, float_of_string_opt y,
            float_of_string_opt z, float_of_string_opt w with
         | Some x, Some y, Some z, Some w -> Some (Vec4 (x, y, z, w))
         | _ -> None)
    | _ -> None

  let encode_range = function
    | Rdk.Attribute_ops.Noise_positive -> "positive"
    | Noise_zero_centered -> "zero-centered"
    | Noise_min_max (minimum, maximum) ->
        String.concat ";" ["min-max"; encode_numeric minimum;
          encode_numeric maximum]

  let decode_range value = match String.split_on_char ';' value with
    | ["positive"] -> Ok Rdk.Attribute_ops.Noise_positive
    | ["zero-centered"] -> Ok Noise_zero_centered
    | ["min-max"; minimum; maximum] ->
        (match decode_numeric minimum, decode_numeric maximum with
         | Some minimum, Some maximum -> Ok (Noise_min_max (minimum, maximum))
         | _ -> Error "invalid noise range bounds")
    | _ -> Error "range must be positive, zero-centered, or min-max bounds"

  let range_parameter = Parameter.encoded ~equal:( = )
      ~encode:encode_range ~decode:decode_range

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Group"];
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "orient"] [@sop.label "Attribute"];
    location : Rdk.Attribute_ops.noise_location
      [@sop.default Rdk.Attribute_ops.Noise_element_number]
      [@sop.label "Location"] [@sop.kind location_parameter];
    range : Rdk.Attribute_ops.noise_range
      [@sop.default Rdk.Attribute_ops.Noise_zero_centered]
      [@sop.label "Range"] [@sop.kind range_parameter];
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.min 0]
      [@sop.max 9999];
    frequency_x : float [@sop.default 1.] [@sop.label "Frequency X"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.]; [@sop.vec3 "frequency"]
    frequency_y : float [@sop.default 1.] [@sop.label "Frequency Y"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.]; [@sop.vec3 "frequency"]
    frequency_z : float [@sop.default 1.] [@sop.label "Frequency Z"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.]; [@sop.vec3 "frequency"]
    octaves : int [@sop.default 1] [@sop.label "Octaves"]
      [@sop.min 1] [@sop.max 8] [@sop.hard_min 1];
  } [@@sop.node_key "attribute_noise_quaternion"]
    [@@sop.node_operation "attribute_noise"]
    [@@sop.node_label "Attribute Noise (Quaternion)"]
    [@@sop.node_category "Attribute/Noise"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.attribute_noise ~label ?group:(optional_text parameters.group)
      ~seed:parameters.seed ~location:parameters.location
      ~range:parameters.range
      ~frequency:(Vec3.create parameters.frequency_x parameters.frequency_y
        parameters.frequency_z) ~octaves:parameters.octaves
      ~owner:parameters.owner ~name:parameters.name
      Rdk.Attribute_ops.Noise_quaternion input)

  let factory = parameters_factory build

  let create ?label:node_label ?group
      ?(location = parameters_default.location)
      ?(range = parameters_default.range) ~owner ~name ~seed ~frequency
      ~octaves input =
    build ~label:(label "attribute-noise-quaternion" node_label)
      ~inputs:[input] {
        group = Option.value ~default:parameters_default.group group;
        owner; name; location; range;
        seed; frequency_x = frequency.Vec3.x; frequency_y = frequency.y;
        frequency_z = frequency.z; octaves }
end

module Measure_curvature = struct
  let boundary_parameter = Parameter.choice ~equal:( = ) [
      "Zero", Rdk.Curvature.Curvature_boundary_zero;
      "One-sided", Rdk.Curvature.Curvature_boundary_one_sided;
    ]

  type parameters = {
    point_group : string [@sop.default ""] [@sop.label "Point group"];
    boundary : Rdk.Curvature.boundary
      [@sop.default Rdk.Curvature.Curvature_boundary_zero]
      [@sop.label "Boundary"] [@sop.kind boundary_parameter];
    smoothing_iterations : int [@sop.default 0]
      [@sop.label "Smoothing iterations"] [@sop.min 0] [@sop.max 64]
      [@sop.hard_min 0];
    smoothing_strength : float [@sop.default 0.5]
      [@sop.label "Smoothing strength"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.] [@sop.hard_max 1.];
    mean : string [@sop.default "curvature"] [@sop.label "Mean"]
      [@sop.folder "Outputs"];
    gaussian : string [@sop.default ""] [@sop.label "Gaussian"]
      [@sop.folder "Outputs"];
    minimum : string [@sop.default ""] [@sop.label "Minimum"]
      [@sop.folder "Outputs"];
    maximum : string [@sop.default ""] [@sop.label "Maximum"]
      [@sop.folder "Outputs"];
    curvedness : string [@sop.default ""] [@sop.label "Curvedness"]
      [@sop.folder "Outputs"];
    shape_index : string [@sop.default ""] [@sop.label "Shape index"]
      [@sop.folder "Outputs"];
  } [@@sop.node_key "measure_curvature"]
    [@@sop.node_label "Measure Curvature"]
    [@@sop.node_category "Measure"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let outputs : Rdk.Curvature.outputs = {
      mean = optional_text parameters.mean;
      gaussian = optional_text parameters.gaussian;
      minimum = optional_text parameters.minimum;
      maximum = optional_text parameters.maximum;
      curvedness = optional_text parameters.curvedness;
      shape_index = optional_text parameters.shape_index } in
    Sop.measure_curvature ~label
      ?point_group:(optional_text parameters.point_group)
      ~boundary:parameters.boundary
      ~smoothing_iterations:parameters.smoothing_iterations
      ~smoothing_strength:parameters.smoothing_strength ~outputs input)

  let factory = parameters_factory build
end

module Attribute_laplacian = struct
  let weighting_parameter = Parameter.choice ~equal:( = ) [
      "Cotangent", Rdk.Laplacian.Laplacian_cotan;
      "Positive cotangent", Rdk.Laplacian.Laplacian_positive_cotan;
      "Uniform", Rdk.Laplacian.Laplacian_uniform;
    ]

  type parameters = {
    point_group : string [@sop.default ""] [@sop.label "Point group"];
    weighting : Rdk.Laplacian.weighting
      [@sop.default Rdk.Laplacian.Laplacian_cotan]
      [@sop.label "Weighting"] [@sop.kind weighting_parameter];
    normalize : bool [@sop.default true] [@sop.label "Normalize"];
    source : string [@sop.default "P"] [@sop.label "Source attribute"];
    output : string [@sop.default "laplacian"] [@sop.label "Output attribute"];
  } [@@sop.node_key "attribute_laplacian"]
    [@@sop.node_label "Attribute Laplacian"]
    [@@sop.node_category "Attribute/Filter"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.attribute_laplacian ~label
      ?point_group:(optional_text parameters.point_group)
      ~weighting:parameters.weighting ~normalize:parameters.normalize
      ~source:parameters.source ?output:(optional_text parameters.output)
      input)

  let factory = parameters_factory build
end

module Polyframe = struct
  type style = Style_first_edge | Style_two_edges | Style_centroid
    | Style_texture_uv | Style_texture_uv_gradient | Style_attribute_gradient
  let style_parameter = Parameter.choice ~equal:( = ) [
      "First edge", Style_first_edge; "Two edges", Style_two_edges;
      "Primitive centroid", Style_centroid; "Texture UV", Style_texture_uv;
      "Texture UV gradient", Style_texture_uv_gradient;
      "Attribute gradient", Style_attribute_gradient;
    ]

  type parameters = {
    group_owner : element_owner [@sop.default Element_primitive]
      [@sop.label "Group type"] [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    style : style [@sop.default Style_first_edge]
      [@sop.label "Style"] [@sop.kind style_parameter];
    style_attribute : string [@sop.default "uv"]
      [@sop.label "Style attribute"];
    orthogonal : bool [@sop.default false] [@sop.label "Make orthogonal"];
    left_handed : bool [@sop.default false] [@sop.label "Left handed"];
    normal_attribute : string [@sop.default "N"] [@sop.label "Normal"]
      [@sop.folder "Output attributes"];
    tangent_attribute : string [@sop.default "tangentu"] [@sop.label "Tangent"]
      [@sop.folder "Output attributes"];
    bitangent_attribute : string [@sop.default "tangentv"]
      [@sop.label "Bitangent"] [@sop.folder "Output attributes"];
  } [@@sop.node_key "polyframe"] [@@sop.node_label "PolyFrame"]
    [@@sop.node_category "Attribute"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let style parameters = match parameters.style with
    | Style_first_edge -> Rdk.Polyframe.First_edge
    | Style_two_edges -> Rdk.Polyframe.Two_edges
    | Style_centroid -> Rdk.Polyframe.Primitive_centroid
    | Style_texture_uv -> Rdk.Polyframe.Texture_uv parameters.style_attribute
    | Style_texture_uv_gradient ->
        Rdk.Polyframe.Texture_uv_gradient parameters.style_attribute
    | Style_attribute_gradient ->
        Rdk.Polyframe.Attribute_gradient parameters.style_attribute

  let build = parameters_build (fun ~label parameters input ->
    Sop.polyframe ~label
      ?selection:(optional_element_group parameters.group_owner
        parameters.group)
      ~orthogonal:parameters.orthogonal ~left_handed:parameters.left_handed
      ~normal_attribute:parameters.normal_attribute
      ~tangent_attribute:(optional_text parameters.tangent_attribute)
      ~bitangent_attribute:(optional_text parameters.bitangent_attribute)
      (style parameters) input)

  let factory = parameters_factory build
end

module Distance_along_geometry = struct
  type parameters = {
    start_owner : element_owner [@sop.default Element_point]
      [@sop.label "Start group type"] [@sop.kind element_owner_parameter];
    start_group : string [@sop.default "start"] [@sop.label "Start group"];
    affected_owner : element_owner [@sop.default Element_point]
      [@sop.label "Affected group type"] [@sop.folder "Affected"]
      [@sop.kind element_owner_parameter];
    affected_group : string [@sop.default ""] [@sop.label "Affected group"]
      [@sop.folder "Affected"];
    falloff : Rdk.Transform_ops.soft_transform_falloff
      [@sop.default Rdk.Transform_ops.Soft_linear]
      [@sop.label "Falloff"] [@sop.kind soft_falloff_parameter];
    radius_mode : distance_radius_mode [@sop.default Radius_maximum]
      [@sop.label "Radius"] [@sop.kind distance_radius_parameter];
    radius : float [@sop.default 1.] [@sop.label "Fixed radius"]
      [@sop.min 0.0001] [@sop.max 1000.] [@sop.hard_min 0.];
    distance_attribute : string [@sop.default "distance"]
      [@sop.label "Distance attribute"] [@sop.folder "Output"];
    mask_attribute : string [@sop.default ""] [@sop.label "Mask attribute"]
      [@sop.folder "Output"];
  } [@@sop.node_key "distance_along_geometry"]
    [@@sop.node_label "Distance Along Geometry"]
    [@@sop.node_category "Attribute/Distance"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let start = match optional_element_group parameters.start_owner
        parameters.start_group with
      | Some start -> start
      | None -> Sop.Point_group "start" in
    Sop.distance_along_geometry ~label
      ?affected:(optional_element_group parameters.affected_owner
        parameters.affected_group) ~falloff:parameters.falloff
      ~radius:(distance_radius parameters.radius_mode parameters.radius)
      ~distance_attribute:(optional_text parameters.distance_attribute)
      ?mask_attribute:(optional_text parameters.mask_attribute) ~start input)
  let factory = parameters_factory build
end

module Distance_from_geometry = struct
  let reference_parameter = Parameter.choice ~equal:( = ) [
      "Points", Rdk.Transform_ops.Distance_reference_points;
      "Primitives", Rdk.Transform_ops.Distance_reference_primitives;
    ]

  type parameters = {
    affected_owner : element_owner [@sop.default Element_point]
      [@sop.label "Affected group type"] [@sop.folder "Source"]
      [@sop.kind element_owner_parameter];
    affected_group : string [@sop.default ""] [@sop.label "Affected group"]
      [@sop.folder "Source"];
    reference_owner : element_owner [@sop.default Element_primitive]
      [@sop.label "Reference group type"] [@sop.folder "Reference"]
      [@sop.kind element_owner_parameter];
    reference_group : string [@sop.default ""] [@sop.label "Reference group"]
      [@sop.folder "Reference"];
    reference_kind : Rdk.Transform_ops.distance_from_geometry_reference
      [@sop.default Rdk.Transform_ops.Distance_reference_primitives]
      [@sop.label "Reference type"] [@sop.folder "Reference"]
      [@sop.kind reference_parameter];
    falloff : Rdk.Transform_ops.soft_transform_falloff
      [@sop.default Rdk.Transform_ops.Soft_linear]
      [@sop.label "Falloff"] [@sop.kind soft_falloff_parameter];
    radius_mode : distance_radius_mode [@sop.default Radius_maximum]
      [@sop.label "Radius"] [@sop.kind distance_radius_parameter];
    radius : float [@sop.default 1.] [@sop.label "Fixed radius"]
      [@sop.min 0.0001] [@sop.max 1000.] [@sop.hard_min 0.];
    distance_attribute : string [@sop.default "distance"]
      [@sop.label "Distance attribute"] [@sop.folder "Output"];
    mask_attribute : string [@sop.default ""] [@sop.label "Mask attribute"]
      [@sop.folder "Output"];
  } [@@sop.node_key "distance_from_geometry"]
    [@@sop.node_label "Distance from Geometry"]
    [@@sop.node_category "Attribute/Distance"] [@@sop.node_inputs 2] [@@sop.node_slots "source, reference"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters source reference ->
    Sop.distance_from_geometry ~label
      ?affected:(optional_element_group parameters.affected_owner
        parameters.affected_group)
      ?reference_selection:
        (optional_element_group parameters.reference_owner
          parameters.reference_group)
      ~reference_kind:parameters.reference_kind ~falloff:parameters.falloff
      ~radius:(distance_radius parameters.radius_mode parameters.radius)
      ~distance_attribute:(optional_text parameters.distance_attribute)
      ?mask_attribute:(optional_text parameters.mask_attribute)
      ~reference source)
  let factory = parameters_factory build
end

module Distance_from_target = struct
  let projection_parameter = Parameter.choice ~equal:( = ) [
      "Spherical", Rdk.Transform_ops.Distance_target_spherical;
      "Cylindrical", Rdk.Transform_ops.Distance_target_cylindrical;
      "Planar", Rdk.Transform_ops.Distance_target_planar;
    ]
  let metric_parameter = Parameter.choice ~equal:( = ) [
      "Absolute", Rdk.Transform_ops.Distance_target_absolute;
      "Signed", Rdk.Transform_ops.Distance_target_signed;
    ]

  type parameters = {
    affected_owner : element_owner [@sop.default Element_point]
      [@sop.label "Affected group type"] [@sop.kind element_owner_parameter];
    affected_group : string [@sop.default ""] [@sop.label "Affected group"];
    projection : Rdk.Transform_ops.distance_from_target_projection
      [@sop.default Rdk.Transform_ops.Distance_target_spherical]
      [@sop.label "Projection"] [@sop.kind projection_parameter];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Target/Origin"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "origin"]
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Target/Origin"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "origin"]
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Target/Origin"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "origin"]
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Target/Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Target/Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Target/Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    metric : Rdk.Transform_ops.distance_from_target_metric
      [@sop.default Rdk.Transform_ops.Distance_target_absolute]
      [@sop.label "Metric"] [@sop.kind metric_parameter];
    falloff : Rdk.Transform_ops.soft_transform_falloff
      [@sop.default Rdk.Transform_ops.Soft_linear]
      [@sop.label "Falloff"] [@sop.kind soft_falloff_parameter];
    radius_mode : distance_radius_mode [@sop.default Radius_maximum]
      [@sop.label "Radius"] [@sop.kind distance_radius_parameter];
    radius : float [@sop.default 1.] [@sop.label "Fixed radius"]
      [@sop.min 0.0001] [@sop.max 1000.] [@sop.hard_min 0.];
    distance_attribute : string [@sop.default "distance"]
      [@sop.label "Distance attribute"] [@sop.folder "Output"];
    mask_attribute : string [@sop.default ""] [@sop.label "Mask attribute"]
      [@sop.folder "Output"];
  } [@@sop.node_key "distance_from_target"]
    [@@sop.node_label "Distance from Target"]
    [@@sop.node_category "Attribute/Distance"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.distance_from_target ~label
      ?affected:(optional_element_group parameters.affected_owner
        parameters.affected_group) ~projection:parameters.projection
      ~origin:(Vec3.create parameters.origin_x parameters.origin_y
        parameters.origin_z)
      ~direction:(Vec3.create parameters.direction_x parameters.direction_y
        parameters.direction_z) ~metric:parameters.metric
      ~falloff:parameters.falloff
      ~radius:(distance_radius parameters.radius_mode parameters.radius)
      ~distance_attribute:(optional_text parameters.distance_attribute)
      ?mask_attribute:(optional_text parameters.mask_attribute) input)
  let factory = parameters_factory build
end

module Graph_color = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Primitives by point", Rdk.Graph_color.Graph_primitives_by_point;
      "Points by primitive", Rdk.Graph_color.Graph_points_by_primitive;
      "Primitives by edge", Rdk.Graph_color.Graph_primitives_by_edge;
    ]

  type parameters = {
    group_owner : element_owner [@sop.default Element_primitive]
      [@sop.label "Group type"] [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    connectivity : Rdk.Graph_color.connectivity
      [@sop.default Rdk.Graph_color.Graph_primitives_by_point]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    color_attribute : string [@sop.default "color"]
      [@sop.label "Color attribute"];
    sort_output : bool [@sop.default false] [@sop.label "Sort output"];
    output_worksets : bool [@sop.default false]
      [@sop.label "Output worksets"];
    workset_begin_attribute : string [@sop.default "workset_begin"]
      [@sop.label "Begin attribute"] [@sop.folder "Worksets"];
    workset_length_attribute : string [@sop.default "workset_length"]
      [@sop.label "Length attribute"] [@sop.folder "Worksets"];
  } [@@sop.node_key "graph_color"] [@@sop.node_label "Graph Color"]
    [@@sop.node_category "Attribute"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let worksets = if parameters.output_worksets then Some {
        Rdk.Graph_color.begin_attribute = parameters.workset_begin_attribute;
        length_attribute = parameters.workset_length_attribute }
      else None in
    Sop.graph_color ~label
      ?selection:(optional_element_group parameters.group_owner
        parameters.group) ~connectivity:parameters.connectivity
      ~color_attribute:parameters.color_attribute
      ~sort_output:parameters.sort_output ?worksets input)
  let factory = parameters_factory build
end

module Uv_project = struct
  type projection = Planar | Cylindrical | Spherical
  let projection_parameter = Parameter.choice ~equal:( = ) [
      "Planar", Planar; "Cylindrical", Cylindrical; "Spherical", Spherical;
    ]
  type parameters = {
    projection : projection [@sop.default Planar] [@sop.label "Projection"]
      [@sop.kind projection_parameter];
    name : string [@sop.default "uv"] [@sop.label "UV attribute"];
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Projection/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Projection/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Projection/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    axis_x : float [@sop.default 0.] [@sop.label "Axis X"]
      [@sop.folder "Projection/Axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Projection/Axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Projection/Axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    seam_x : float [@sop.default 1.] [@sop.label "Seam X"]
      [@sop.folder "Projection/Seam"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "seam"]
    seam_y : float [@sop.default 0.] [@sop.label "Seam Y"]
      [@sop.folder "Projection/Seam"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "seam"]
    seam_z : float [@sop.default 0.] [@sop.label "Seam Z"]
      [@sop.folder "Projection/Seam"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "seam"]
    planar_u_x : float [@sop.default 1.] [@sop.label "U axis X"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "planar_u"]
    planar_u_y : float [@sop.default 0.] [@sop.label "U axis Y"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "planar_u"]
    planar_u_z : float [@sop.default 0.] [@sop.label "U axis Z"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "planar_u"]
    planar_v_x : float [@sop.default 0.] [@sop.label "V axis X"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "planar_v"]
    planar_v_y : float [@sop.default 0.] [@sop.label "V axis Y"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "planar_v"]
    planar_v_z : float [@sop.default 1.] [@sop.label "V axis Z"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "planar_v"]
    height : float [@sop.default 1.] [@sop.label "Cylinder height"]
      [@sop.folder "Projection/Cylindrical"] [@sop.min 0.01]
      [@sop.max 10.] [@sop.hard_min 0.];
    u_min : float [@sop.default 0.] [@sop.label "U minimum"]
      [@sop.folder "Range/U"] [@sop.min (-10.)] [@sop.max 10.];
    u_max : float [@sop.default 1.] [@sop.label "U maximum"]
      [@sop.folder "Range/U"] [@sop.min (-10.)] [@sop.max 10.];
    v_min : float [@sop.default 0.] [@sop.label "V minimum"]
      [@sop.folder "Range/V"] [@sop.min (-10.)] [@sop.max 10.];
    v_max : float [@sop.default 1.] [@sop.label "V maximum"]
      [@sop.folder "Range/V"] [@sop.min (-10.)] [@sop.max 10.];
    fix_seams : bool [@sop.default true] [@sop.label "Fix seams"];
    fix_poles : bool [@sop.default true] [@sop.label "Fix poles"];
  } [@@sop.node_key "uv_project"] [@@sop.node_label "UV Project"]
    [@@sop.node_category "UV/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let projection parameters =
    let origin = Vec3.create parameters.origin_x parameters.origin_y
        parameters.origin_z in
    match parameters.projection with
    | Planar -> Rdk.Uv_ops.Planar { origin;
        u_axis = Vec3.create parameters.planar_u_x parameters.planar_u_y
          parameters.planar_u_z;
        v_axis = Vec3.create parameters.planar_v_x parameters.planar_v_y
          parameters.planar_v_z }
    | Cylindrical -> Rdk.Uv_ops.Cylindrical { origin;
        axis = Vec3.create parameters.axis_x parameters.axis_y parameters.axis_z;
        seam = Vec3.create parameters.seam_x parameters.seam_y parameters.seam_z;
        height = parameters.height }
    | Spherical -> Rdk.Uv_ops.Spherical { origin;
        axis = Vec3.create parameters.axis_x parameters.axis_y parameters.axis_z;
        seam = Vec3.create parameters.seam_x parameters.seam_y parameters.seam_z }
  let build = parameters_build (fun ~label parameters input ->
    Sop.uv_project ~label ~name:parameters.name
        ?group:(optional_text parameters.group)
        ~u_range:(parameters.u_min, parameters.u_max)
        ~v_range:(parameters.v_min, parameters.v_max)
        ~fix_seams:parameters.fix_seams ~fix_poles:parameters.fix_poles
        (projection parameters) input)
  let factory = parameters_factory build
end

module Uv_transform = struct
  type parameters = {
    name : string [@sop.default "uv"] [@sop.label "UV attribute"];
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Vertex]
      [@sop.label "Owner"] [@sop.kind uv_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    translate_u : float [@sop.default 0.] [@sop.label "Translate U"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.primary]
    translate_v : float [@sop.default 0.] [@sop.label "Translate V"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.primary]
    scale_u : float [@sop.default 1.] [@sop.label "Scale U"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.primary]
    scale_v : float [@sop.default 1.] [@sop.label "Scale V"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.primary]
    angle : float [@sop.default 0.] [@sop.label "Angle"]
      [@sop.folder "Transform"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.primary]
    pivot_u : float [@sop.default 0.5] [@sop.label "Pivot U"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.];
    pivot_v : float [@sop.default 0.5] [@sop.label "Pivot V"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.];
  } [@@sop.node_key "uv_transform"] [@@sop.node_label "UV Transform"]
    [@@sop.node_category "UV/Modify"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.uv_transform ~label ~name:parameters.name
        ~owner:parameters.owner ?group:(optional_text parameters.group)
        ~translate:(Vec2.create parameters.translate_u parameters.translate_v)
        ~scale:(Vec2.create parameters.scale_u parameters.scale_v)
        ~angle:parameters.angle
        ~pivot:(Vec2.create parameters.pivot_u parameters.pivot_v) input)
  let factory = parameters_factory build
end

module Uv_auto_seam = struct
  type parameters = {
    name : string [@sop.default "uv_seams"] [@sop.label "Seam group"];
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    angle : float [@sop.default 1.0471975511965976]
      [@sop.label "Angle threshold"] [@sop.min 0.]
      [@sop.max 3.141592653589793] [@sop.hard_min 0.]
      [@sop.hard_max 3.141592653589793];
    include_boundaries : bool [@sop.default true]
      [@sop.label "Include boundaries"];
    include_non_manifold : bool [@sop.default true]
      [@sop.label "Include non-manifold"];
    partition_attribute : string [@sop.default ""]
      [@sop.label "Partition attribute"] [@sop.folder "Cuts"];
    existing_uv : string [@sop.default ""] [@sop.label "Existing UV"]
      [@sop.folder "Cuts"];
    uv_tolerance : float [@sop.default 1e-9] [@sop.label "UV tolerance"]
      [@sop.folder "Cuts"] [@sop.min 0.] [@sop.max 0.01]
      [@sop.hard_min 0.];
    island_attribute : string [@sop.default ""]
      [@sop.label "Island attribute"] [@sop.folder "Output"];
  } [@@sop.node_key "uv_auto_seam"] [@@sop.node_label "UV Auto Seam"]
    [@@sop.node_category "UV/Seams"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.uv_auto_seam ~label ~name:parameters.name
        ?group:(optional_text parameters.group) ~angle:parameters.angle
        ~include_boundaries:parameters.include_boundaries
        ~include_non_manifold:parameters.include_non_manifold
        ?partition_attribute:(optional_text parameters.partition_attribute)
        ?existing_uv:(optional_text parameters.existing_uv)
        ~uv_tolerance:parameters.uv_tolerance
        ?island_attribute:(optional_text parameters.island_attribute) input)
  let factory = parameters_factory build
end

module Uv_unitize = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Per face", Rdk.Uv_ops.Per_face; "Islands", Rdk.Uv_ops.Islands;
    ]
  type parameters = {
    mode : Rdk.Uv_ops.unitize_mode [@sop.default Rdk.Uv_ops.Per_face]
      [@sop.label "Mode"] [@sop.kind mode_parameter];
    name : string [@sop.default "uv"] [@sop.label "UV attribute"];
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    seams : string [@sop.default ""] [@sop.label "Seam group"];
    tolerance : float [@sop.default 1e-9] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.01] [@sop.hard_min 0.];
    uniform : bool [@sop.default true] [@sop.label "Uniform scale"];
  } [@@sop.node_key "uv_unitize"] [@@sop.node_label "UV Unitize"]
    [@@sop.node_category "UV/Layout"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.uv_unitize ~label ~name:parameters.name
        ?group:(optional_text parameters.group)
        ?seams:(optional_text parameters.seams)
        ~tolerance:parameters.tolerance ~uniform:parameters.uniform
        parameters.mode input)
  let factory = parameters_factory build
end

module Uv_flatten = struct
  type parameters = {
    name : string [@sop.default "uv"] [@sop.label "UV attribute"];
    seams : string [@sop.default ""] [@sop.label "Seam group"];
    iterations : int [@sop.default 500] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 2000] [@sop.hard_min 1];
    tolerance : float [@sop.default 1e-7] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.01] [@sop.hard_min 0.];
  } [@@sop.node_key "uv_flatten"] [@@sop.node_label "UV Flatten"]
    [@@sop.node_category "UV/Layout"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.uv_flatten ~label ~name:parameters.name
        ?seams:(optional_text parameters.seams)
        ~iterations:parameters.iterations ~tolerance:parameters.tolerance input)
  let factory = parameters_factory build
end

module Uv_relax = struct
  type parameters = {
    name : string [@sop.default "uv"] [@sop.label "UV attribute"];
    seams : string [@sop.default ""] [@sop.label "Seam group"];
    uv_tolerance : float [@sop.default 1e-9] [@sop.label "UV tolerance"]
      [@sop.min 0.] [@sop.max 0.01] [@sop.hard_min 0.];
    iterations : int [@sop.default 500] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 2000] [@sop.hard_min 1];
    tolerance : float [@sop.default 1e-7] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.01] [@sop.hard_min 0.];
  } [@@sop.node_key "uv_relax"] [@@sop.node_label "UV Relax"]
    [@@sop.node_category "UV/Layout"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.uv_relax ~label ~name:parameters.name
        ?seams:(optional_text parameters.seams)
        ~uv_tolerance:parameters.uv_tolerance
        ~iterations:parameters.iterations ~tolerance:parameters.tolerance input)
  let factory = parameters_factory build
end

module Color_by_height = struct
  type parameters = {
    low_red : int [@sop.default 32] [@sop.label "Red"]
      [@sop.folder "Low color"] [@sop.min 0] [@sop.max 255]
      [@sop.hard_min 0] [@sop.hard_max 255];
    low_green : int [@sop.default 64] [@sop.label "Green"]
      [@sop.folder "Low color"] [@sop.min 0] [@sop.max 255]
      [@sop.hard_min 0] [@sop.hard_max 255];
    low_blue : int [@sop.default 192] [@sop.label "Blue"]
      [@sop.folder "Low color"] [@sop.min 0] [@sop.max 255]
      [@sop.hard_min 0] [@sop.hard_max 255];
    high_red : int [@sop.default 255] [@sop.label "Red"]
      [@sop.folder "High color"] [@sop.min 0] [@sop.max 255]
      [@sop.hard_min 0] [@sop.hard_max 255];
    high_green : int [@sop.default 160] [@sop.label "Green"]
      [@sop.folder "High color"] [@sop.min 0] [@sop.max 255]
      [@sop.hard_min 0] [@sop.hard_max 255];
    high_blue : int [@sop.default 32] [@sop.label "Blue"]
      [@sop.folder "High color"] [@sop.min 0] [@sop.max 255]
      [@sop.hard_min 0] [@sop.hard_max 255];
  } [@@sop.node_key "color_by_height"] [@@sop.node_label "Color by Height"]
    [@@sop.node_category "Attribute/Color"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.color_by_height ~label
        ~low:(Color.rgb parameters.low_red parameters.low_green
          parameters.low_blue)
        ~high:(Color.rgb parameters.high_red parameters.high_green
          parameters.high_blue) input)
  let factory = parameters_factory build
end

module Attribute_noise = struct
  type location = Position | Element_number | Attribute
  type range = Positive | Zero_centered | Min_max
  let kind_parameter = Parameter.choice ~equal:( = ) [
      "Float", Rdk.Attribute_ops.Noise_float;
      "Vector", Rdk.Attribute_ops.Noise_vector;
      "Quaternion", Rdk.Attribute_ops.Noise_quaternion;
    ]
  let location_parameter = Parameter.choice ~equal:( = ) [
      "Position", Position; "Element number", Element_number;
      "Attribute", Attribute;
    ]
  let range_parameter = Parameter.choice ~equal:( = ) [
      "Positive", Positive; "Zero centered", Zero_centered;
      "Minimum / maximum", Min_max;
    ]
  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Set initial", Rdk.Attribute_ops.Noise_set_initial;
      "Set", Rdk.Attribute_ops.Noise_set;
      "Add", Rdk.Attribute_ops.Noise_add;
      "Subtract", Rdk.Attribute_ops.Noise_subtract;
      "Multiply", Rdk.Attribute_ops.Noise_multiply;
      "Minimum", Rdk.Attribute_ops.Noise_minimum;
      "Maximum", Rdk.Attribute_ops.Noise_maximum;
    ]
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "noise"] [@sop.label "Attribute"];
    group : string [@sop.default ""] [@sop.label "Group"];
    kind : Rdk.Attribute_ops.noise_kind
      [@sop.default Rdk.Attribute_ops.Noise_float] [@sop.label "Type"]
      [@sop.kind kind_parameter];
    context_seed : bool [@sop.default false] [@sop.label "Use context seed"]
      [@sop.folder "Noise"];
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.folder "Noise"]
      [@sop.min 0] [@sop.max 9999];
    location : location [@sop.default Position] [@sop.label "Location"]
      [@sop.folder "Sampling"] [@sop.kind location_parameter];
    location_attribute : string [@sop.default "P"]
      [@sop.label "Location attribute"] [@sop.folder "Sampling"];
    range : range [@sop.default Positive] [@sop.label "Range"]
      [@sop.folder "Output"] [@sop.kind range_parameter];
    min_x : float [@sop.default 0.] [@sop.label "Minimum X"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "min"]
    min_y : float [@sop.default 0.] [@sop.label "Minimum Y"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "min"]
    min_z : float [@sop.default 0.] [@sop.label "Minimum Z"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "min"]
    min_w : float [@sop.default 0.] [@sop.label "Minimum W"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    max_x : float [@sop.default 1.] [@sop.label "Maximum X"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "max"]
    max_y : float [@sop.default 1.] [@sop.label "Maximum Y"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "max"]
    max_z : float [@sop.default 1.] [@sop.label "Maximum Z"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "max"]
    max_w : float [@sop.default 1.] [@sop.label "Maximum W"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    operation : Rdk.Attribute_ops.noise_operation
      [@sop.default Rdk.Attribute_ops.Noise_set] [@sop.label "Operation"]
      [@sop.folder "Output"] [@sop.kind operation_parameter];
    blend : float [@sop.default 1.] [@sop.label "Blend"]
      [@sop.folder "Output"] [@sop.min 0.] [@sop.max 1.];
    frequency_x : float [@sop.default 1.] [@sop.label "Frequency X"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.]; [@sop.vec3 "frequency"]
    frequency_y : float [@sop.default 1.] [@sop.label "Frequency Y"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.]; [@sop.vec3 "frequency"]
    frequency_z : float [@sop.default 1.] [@sop.label "Frequency Z"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.]; [@sop.vec3 "frequency"]
    offset_x : float [@sop.default 0.] [@sop.label "Offset X"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "offset"]
    offset_y : float [@sop.default 0.] [@sop.label "Offset Y"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "offset"]
    offset_z : float [@sop.default 0.] [@sop.label "Offset Z"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "offset"]
    octaves : int [@sop.default 1] [@sop.label "Octaves"]
      [@sop.folder "Noise/Fractal"] [@sop.min 1] [@sop.max 12]
      [@sop.hard_min 1];
    lacunarity : float [@sop.default 2.] [@sop.label "Lacunarity"]
      [@sop.folder "Noise/Fractal"] [@sop.min 0.] [@sop.max 8.];
    roughness : float [@sop.default 0.5] [@sop.label "Roughness"]
      [@sop.folder "Noise/Fractal"] [@sop.min 0.] [@sop.max 1.];
  } [@@sop.node_key "attribute_noise"] [@@sop.node_label "Attribute Noise"]
    [@@sop.node_category "Attribute/Noise"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let numeric_kind = function
    | Rdk.Attribute_ops.Noise_float -> Numeric_scalar
    | Rdk.Attribute_ops.Noise_vector -> Numeric_vec3
    | Rdk.Attribute_ops.Noise_quaternion -> Numeric_vec4
  let build = parameters_build (fun ~label parameters input ->
    let location = match parameters.location with
      | Position -> Rdk.Attribute_ops.Noise_position
      | Element_number -> Rdk.Attribute_ops.Noise_element_number
      | Attribute -> Rdk.Attribute_ops.Noise_attribute
          parameters.location_attribute in
    let range = match parameters.range with
      | Positive -> Rdk.Attribute_ops.Noise_positive
      | Zero_centered -> Rdk.Attribute_ops.Noise_zero_centered
      | Min_max -> let kind = numeric_kind parameters.kind in
          Rdk.Attribute_ops.Noise_min_max
            (numeric_value kind parameters.min_x parameters.min_y
               parameters.min_z parameters.min_w,
             numeric_value kind parameters.max_x parameters.max_y
               parameters.max_z parameters.max_w) in
    Sop.attribute_noise ~label ?group:(optional_text parameters.group)
      ?seed:(if parameters.context_seed then None else Some parameters.seed)
      ~location ~range ~operation:parameters.operation ~blend:parameters.blend
      ~frequency:(Vec3.create parameters.frequency_x parameters.frequency_y
        parameters.frequency_z)
      ~offset:(Vec3.create parameters.offset_x parameters.offset_y
        parameters.offset_z)
      ~octaves:parameters.octaves ~lacunarity:parameters.lacunarity
      ~roughness:parameters.roughness ~owner:parameters.owner
      ~name:parameters.name parameters.kind input)
  let factory = parameters_factory build
end

module Attribute_remap = struct
  type input_range = Automatic | Explicit
  let input_parameter = Parameter.choice ~equal:( = ) [
      "Automatic", Automatic; "Explicit", Explicit;
    ]
  let policy_parameter = Parameter.choice ~equal:( = ) [
      "Clamp", Rdk.Attribute_ops.Remap_clamp;
      "Cycle", Rdk.Attribute_ops.Remap_cycle;
      "Extrapolate", Rdk.Attribute_ops.Remap_extrapolate;
    ]
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "value"] [@sop.label "Source attribute"];
    into : string [@sop.default ""] [@sop.label "Destination attribute"];
    group : string [@sop.default ""] [@sop.label "Group"];
    kind : numeric_kind [@sop.default Numeric_scalar] [@sop.label "Value type"]
      [@sop.kind numeric_kind_parameter];
    input_range : input_range [@sop.default Automatic]
      [@sop.label "Input range"] [@sop.kind input_parameter];
    input_min_x : float [@sop.default 0.] [@sop.label "Minimum X"]
      [@sop.folder "Input/Minimum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "input_min"]
    input_min_y : float [@sop.default 0.] [@sop.label "Minimum Y"]
      [@sop.folder "Input/Minimum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "input_min"]
    input_min_z : float [@sop.default 0.] [@sop.label "Minimum Z"]
      [@sop.folder "Input/Minimum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "input_min"]
    input_min_w : float [@sop.default 0.] [@sop.label "Minimum W"]
      [@sop.folder "Input/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    input_max_x : float [@sop.default 1.] [@sop.label "Maximum X"]
      [@sop.folder "Input/Maximum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "input_max"]
    input_max_y : float [@sop.default 1.] [@sop.label "Maximum Y"]
      [@sop.folder "Input/Maximum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "input_max"]
    input_max_z : float [@sop.default 1.] [@sop.label "Maximum Z"]
      [@sop.folder "Input/Maximum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "input_max"]
    input_max_w : float [@sop.default 1.] [@sop.label "Maximum W"]
      [@sop.folder "Input/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    output_min_x : float [@sop.default 0.] [@sop.label "Minimum X"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "output_min"]
    output_min_y : float [@sop.default 0.] [@sop.label "Minimum Y"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "output_min"]
    output_min_z : float [@sop.default 0.] [@sop.label "Minimum Z"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "output_min"]
    output_min_w : float [@sop.default 0.] [@sop.label "Minimum W"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    output_max_x : float [@sop.default 1.] [@sop.label "Maximum X"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "output_max"]
    output_max_y : float [@sop.default 1.] [@sop.label "Maximum Y"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "output_max"]
    output_max_z : float [@sop.default 1.] [@sop.label "Maximum Z"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "output_max"]
    output_max_w : float [@sop.default 1.] [@sop.label "Maximum W"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    policy : Rdk.Attribute_ops.remap_policy
      [@sop.default Rdk.Attribute_ops.Remap_clamp] [@sop.label "Outside range"]
      [@sop.kind policy_parameter];
  } [@@sop.node_key "attribute_remap"] [@@sop.node_label "Attribute Remap"]
    [@@sop.node_category "Attribute/Modify"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input_node ->
    let value x y z w = numeric_value parameters.kind x y z w in
    let input = match parameters.input_range with
      | Automatic -> Rdk.Attribute_ops.Remap_auto
      | Explicit -> Rdk.Attribute_ops.Remap_explicit {
          min = value parameters.input_min_x parameters.input_min_y
            parameters.input_min_z parameters.input_min_w;
          max = value parameters.input_max_x parameters.input_max_y
            parameters.input_max_z parameters.input_max_w } in
    Sop.attribute_remap ~label ?group:(optional_text parameters.group)
      ?into:(optional_text parameters.into) ~policy:parameters.policy
      ~owner:parameters.owner ~name:parameters.name ~input
      ~output_min:(value parameters.output_min_x parameters.output_min_y
        parameters.output_min_z parameters.output_min_w)
      ~output_max:(value parameters.output_max_x parameters.output_max_y
        parameters.output_max_z parameters.output_max_w) input_node)
  let factory = parameters_factory build
end

module Attribute_randomize = struct
  type distribution = Constant | Two_values | Uniform | Uniform_discrete
    | Normal | Exponential | Log_normal | Cauchy | Direction | Inside_sphere
    | Inside_sphere_cone
  let distribution_parameter = Parameter.choice ~equal:( = ) [
      "Constant", Constant; "Two values", Two_values; "Uniform", Uniform;
      "Uniform discrete", Uniform_discrete; "Normal", Normal;
      "Exponential", Exponential; "Log normal", Log_normal;
      "Cauchy", Cauchy; "Direction", Direction;
      "Inside sphere", Inside_sphere;
      "Inside sphere cone", Inside_sphere_cone;
    ]
  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Set", Rdk.Attribute_ops.Random_set;
      "Add", Rdk.Attribute_ops.Random_add;
      "Minimum", Rdk.Attribute_ops.Random_minimum;
      "Maximum", Rdk.Attribute_ops.Random_maximum;
      "Multiply", Rdk.Attribute_ops.Random_multiply;
    ]
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "random"] [@sop.label "Attribute"];
    group : string [@sop.default ""] [@sop.label "Group"];
    kind : numeric_kind [@sop.default Numeric_scalar] [@sop.label "Value type"]
      [@sop.kind numeric_kind_parameter];
    distribution : distribution [@sop.default Uniform]
      [@sop.label "Distribution"] [@sop.kind distribution_parameter];
    context_seed : bool [@sop.default false] [@sop.label "Use context seed"]
      [@sop.folder "Random"];
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.folder "Random"]
      [@sop.min 0] [@sop.max 9999];
    seed_attribute : string [@sop.default ""] [@sop.label "Seed attribute"]
      [@sop.folder "Random"];
    fraction_attribute : string [@sop.default ""]
      [@sop.label "Fraction attribute"] [@sop.folder "Random"];
    a_x : float [@sop.default 0.] [@sop.label "A / minimum X"]
      [@sop.folder "Distribution/A"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "a"]
    a_y : float [@sop.default 0.] [@sop.label "A / minimum Y"]
      [@sop.folder "Distribution/A"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "a"]
    a_z : float [@sop.default 0.] [@sop.label "A / minimum Z"]
      [@sop.folder "Distribution/A"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "a"]
    a_w : float [@sop.default 0.] [@sop.label "A / minimum W"]
      [@sop.folder "Distribution/A"] [@sop.min (-10.)] [@sop.max 10.];
    b_x : float [@sop.default 1.] [@sop.label "B / maximum X"]
      [@sop.folder "Distribution/B"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "b"]
    b_y : float [@sop.default 1.] [@sop.label "B / maximum Y"]
      [@sop.folder "Distribution/B"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "b"]
    b_z : float [@sop.default 1.] [@sop.label "B / maximum Z"]
      [@sop.folder "Distribution/B"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "b"]
    b_w : float [@sop.default 1.] [@sop.label "B / maximum W"]
      [@sop.folder "Distribution/B"] [@sop.min (-10.)] [@sop.max 10.];
    step_x : float [@sop.default 1.] [@sop.label "Step X"]
      [@sop.folder "Distribution/Step"] [@sop.min 0.] [@sop.max 10.]; [@sop.vec3 "step"]
    step_y : float [@sop.default 1.] [@sop.label "Step Y"]
      [@sop.folder "Distribution/Step"] [@sop.min 0.] [@sop.max 10.]; [@sop.vec3 "step"]
    step_z : float [@sop.default 1.] [@sop.label "Step Z"]
      [@sop.folder "Distribution/Step"] [@sop.min 0.] [@sop.max 10.]; [@sop.vec3 "step"]
    step_w : float [@sop.default 1.] [@sop.label "Step W"]
      [@sop.folder "Distribution/Step"] [@sop.min 0.] [@sop.max 10.];
    probability_b : float [@sop.default 0.5] [@sop.label "Probability B"]
      [@sop.folder "Distribution"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.] [@sop.hard_max 1.];
    cone_angle : float [@sop.default 0.7853981633974483]
      [@sop.label "Cone angle"] [@sop.folder "Distribution"] [@sop.min 0.]
      [@sop.max 3.141592653589793];
    dimensions : int [@sop.default 3] [@sop.label "Dimensions"]
      [@sop.folder "Distribution"] [@sop.min 1] [@sop.max 4]
      [@sop.hard_min 1] [@sop.hard_max 4];
    use_minimum : bool [@sop.default false] [@sop.label "Clamp minimum"]
      [@sop.folder "Clamp"];
    minimum : float [@sop.default 0.] [@sop.label "Minimum"]
      [@sop.folder "Clamp"] [@sop.min (-10.)] [@sop.max 10.];
    use_maximum : bool [@sop.default false] [@sop.label "Clamp maximum"]
      [@sop.folder "Clamp"];
    maximum : float [@sop.default 1.] [@sop.label "Maximum"]
      [@sop.folder "Clamp"] [@sop.min (-10.)] [@sop.max 10.];
    direction_bias : float [@sop.default 0.] [@sop.label "Direction bias"]
      [@sop.folder "Output"] [@sop.min (-1.)] [@sop.max 1.];
    operation : Rdk.Attribute_ops.random_operation
      [@sop.default Rdk.Attribute_ops.Random_set] [@sop.label "Operation"]
      [@sop.folder "Output"] [@sop.kind operation_parameter];
    scale : float [@sop.default 1.] [@sop.label "Global scale"]
      [@sop.folder "Output"] [@sop.min (-10.)] [@sop.max 10.];
  } [@@sop.node_key "attribute_randomize"]
    [@@sop.node_label "Attribute Randomize"]
    [@@sop.node_category "Attribute/Random"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let distribution parameters =
    let a = numeric_value parameters.kind parameters.a_x parameters.a_y
        parameters.a_z parameters.a_w
    and b = numeric_value parameters.kind parameters.b_x parameters.b_y
        parameters.b_z parameters.b_w
    and step = numeric_value parameters.kind parameters.step_x parameters.step_y
        parameters.step_z parameters.step_w in
    match parameters.distribution with
    | Constant -> Rdk.Attribute_ops.Random_constant a
    | Two_values -> Rdk.Attribute_ops.Random_two_values {
        a; b; probability_b = parameters.probability_b }
    | Uniform -> Rdk.Attribute_ops.Random_uniform { min = a; max = b }
    | Uniform_discrete -> Rdk.Attribute_ops.Random_uniform_discrete {
        min = a; max = b; step }
    | Normal -> Rdk.Attribute_ops.Random_normal { middle = a; scale = b }
    | Exponential -> Rdk.Attribute_ops.Random_exponential { median = a }
    | Log_normal -> Rdk.Attribute_ops.Random_log_normal {
        median = a; stddev = b }
    | Cauchy -> Rdk.Attribute_ops.Random_cauchy { median = a; scale = b }
    | Direction -> Rdk.Attribute_ops.Random_direction {
        direction = a; cone_angle = parameters.cone_angle }
    | Inside_sphere -> Rdk.Attribute_ops.Random_inside_sphere {
        dimensions = parameters.dimensions }
    | Inside_sphere_cone -> Rdk.Attribute_ops.Random_inside_sphere_cone {
        direction = a; cone_angle = parameters.cone_angle }
  let build = parameters_build (fun ~label parameters input ->
    let fraction = optional_text parameters.fraction_attribute in
    Sop.attribute_randomize ~label ?group:(optional_text parameters.group)
      ?seed:(if Option.is_some fraction || parameters.context_seed then None
        else Some parameters.seed)
      ?seed_attribute:(if Option.is_some fraction then None
        else optional_text parameters.seed_attribute)
      ?fraction_attribute:fraction
      ?minimum:(if parameters.use_minimum then
        Some (numeric_value parameters.kind parameters.minimum
          parameters.minimum parameters.minimum parameters.minimum)
        else None)
      ?maximum:(if parameters.use_maximum then
        Some (numeric_value parameters.kind parameters.maximum
          parameters.maximum parameters.maximum parameters.maximum)
        else None)
      ~direction_bias:parameters.direction_bias
      ~operation:parameters.operation ~scale:parameters.scale
      ~owner:parameters.owner ~name:parameters.name
      (distribution parameters) input)
  let factory = parameters_factory build

  (* A uniform scalar in [minimum, maximum]. *)
  let create ?label:node_label ?(owner = parameters_default.owner)
      ?(seed = parameters_default.seed) ~name ~minimum ~maximum input =
    build ~label:(label "attribute-randomize" node_label) ~inputs:[input]
      { parameters_default with owner; seed; name; a_x = minimum; b_x = maximum }
end

module Attribute_mirror = struct
  type method_ = Plane | Mapping
  type transform = Copy | Uv | Vector | Point
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Point", Rdk.Attribute_mirror.Mirror_point_attributes;
      "Vertex", Rdk.Attribute_mirror.Mirror_vertex_attributes;
      "Primitive", Rdk.Attribute_mirror.Mirror_primitive_attributes;
    ]
  let group_use_parameter = Parameter.choice ~equal:( = ) [
      "Group is source", Rdk.Attribute_mirror.Mirror_group_as_source;
      "Group is destination", Rdk.Attribute_mirror.Mirror_group_as_destination;
    ]
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Plane", Plane; "Mapping attribute", Mapping;
    ]
  let transform_parameter = Parameter.choice ~equal:( = ) [
      "Copy", Copy; "UV", Uv; "Vector", Vector; "Point", Point;
    ]
  type parameters = {
    owner : Rdk.Attribute_mirror.owner
      [@sop.default Rdk.Attribute_mirror.Mirror_point_attributes]
      [@sop.label "Attribute owner"] [@sop.kind owner_parameter];
    attributes : string [@sop.default "Cd"] [@sop.label "Attributes"];
    group : string [@sop.default ""] [@sop.label "Selection group"];
    group_use : Rdk.Attribute_mirror.group_use
      [@sop.default Rdk.Attribute_mirror.Mirror_group_as_source]
      [@sop.label "Group use"] [@sop.kind group_use_parameter];
    method_ : method_ [@sop.default Plane] [@sop.label "Mirror method"]
      [@sop.kind method_parameter];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    normal_x : float [@sop.default 1.] [@sop.label "Normal X"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "normal"]
    normal_y : float [@sop.default 0.] [@sop.label "Normal Y"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "normal"]
    normal_z : float [@sop.default 0.] [@sop.label "Normal Z"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "normal"]
    distance : float [@sop.default 1000000.] [@sop.label "Maximum distance"]
      [@sop.folder "Plane"] [@sop.min 0.] [@sop.max 1000000.]
      [@sop.hard_min 0.];
    tolerance : float [@sop.default 0.00001] [@sop.label "Tolerance"]
      [@sop.folder "Plane"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.];
    mapping_attribute : string [@sop.default "mirror"]
      [@sop.label "Mapping attribute"] [@sop.folder "Mapping"];
    mapping_destination_group : string [@sop.default "mirror_destination"]
      [@sop.label "Mapping destination group"] [@sop.folder "Mapping"];
    transform : transform [@sop.default Copy] [@sop.label "Value transform"]
      [@sop.kind transform_parameter];
    uv_origin_u : float [@sop.default 0.] [@sop.label "UV origin U"]
      [@sop.folder "Value transform/UV"] [@sop.min (-10.)] [@sop.max 10.];
    uv_origin_v : float [@sop.default 0.] [@sop.label "UV origin V"]
      [@sop.folder "Value transform/UV"] [@sop.min (-10.)] [@sop.max 10.];
    uv_direction_u : float [@sop.default 1.] [@sop.label "UV direction U"]
      [@sop.folder "Value transform/UV"] [@sop.min (-10.)] [@sop.max 10.];
    uv_direction_v : float [@sop.default 0.] [@sop.label "UV direction V"]
      [@sop.folder "Value transform/UV"] [@sop.min (-10.)] [@sop.max 10.];
    replace_strings : bool [@sop.default false]
      [@sop.label "Replace strings"] [@sop.folder "Strings"];
    string_search : string [@sop.default "L"] [@sop.label "Search"]
      [@sop.folder "Strings"];
    string_replacement : string [@sop.default "R"] [@sop.label "Replacement"]
      [@sop.folder "Strings"];
    output_mapping : string [@sop.default ""]
      [@sop.label "Output mapping"] [@sop.folder "Output"];
    source_group : string [@sop.default ""] [@sop.label "Source group"]
      [@sop.folder "Output"];
    destination_group : string [@sop.default ""]
      [@sop.label "Destination group"] [@sop.folder "Output"];
  } [@@sop.node_key "attribute_mirror"] [@@sop.node_label "Attribute Mirror"]
    [@@sop.node_category "Attribute/Transform"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let method_ parameters = match parameters.method_ with
    | Plane -> Sop.Attribute_mirror_plane {
        origin = Vec3.create parameters.origin_x parameters.origin_y
          parameters.origin_z;
        normal = Vec3.create parameters.normal_x parameters.normal_y
          parameters.normal_z;
        distance = parameters.distance; tolerance = parameters.tolerance }
    | Mapping -> Sop.Attribute_mirror_mapping {
        mapping_attribute = parameters.mapping_attribute;
        destination_group = parameters.mapping_destination_group }
  let transform parameters = match parameters.transform with
    | Copy -> Rdk.Attribute_mirror.Mirror_copy
    | Uv -> Rdk.Attribute_mirror.Mirror_uv { origin_u = parameters.uv_origin_u;
        origin_v = parameters.uv_origin_v;
        direction_u = parameters.uv_direction_u;
        direction_v = parameters.uv_direction_v }
    | Vector -> Rdk.Attribute_mirror.Mirror_vector
    | Point -> Rdk.Attribute_mirror.Mirror_point
  let build = parameters_build (fun ~label parameters input ->
    Sop.attribute_mirror ~label
        ?group:(optional_text parameters.group) ~group_use:parameters.group_use
        ~attributes:parameters.attributes ~transform:(transform parameters)
        ?string_replace:(if parameters.replace_strings then
          Some (parameters.string_search, parameters.string_replacement)
          else None)
        ?output_mapping:(optional_text parameters.output_mapping)
        ?source_group:(optional_text parameters.source_group)
        ?destination_group:(optional_text parameters.destination_group)
        ~owner:parameters.owner ~method_:(method_ parameters) input)
  let factory = parameters_factory build
end

module Edge_transport = struct
  type parameters = {
    attribute : string [@sop.default "value"] [@sop.label "Attribute"];
    point_group : string [@sop.default ""] [@sop.label "Point group"];
    roots : transport_roots [@sop.default Transport_first]
      [@sop.label "Roots"] [@sop.kind transport_roots_parameter];
    root_group : string [@sop.default ""] [@sop.label "Root group"];
    direction : Rdk.Edge_transport.direction
      [@sop.default Rdk.Edge_transport.Transport_forward] [@sop.label "Direction"]
      [@sop.kind edge_transport_direction_parameter];
    operation : Rdk.Edge_transport.operation
      [@sop.default Rdk.Edge_transport.Transport] [@sop.label "Operation"]
      [@sop.kind edge_transport_operation_parameter];
    root_value : Rdk.Edge_transport.root_value
      [@sop.default Rdk.Edge_transport.Transport_root_zero] [@sop.label "Root value"]
      [@sop.kind edge_transport_root_value_parameter];
    integrate_constant : bool [@sop.default false]
      [@sop.label "Integrate constant"];
    scale_by_edge_length : bool [@sop.default false]
      [@sop.label "Scale by edge length"];
    split : Rdk.Edge_transport.split [@sop.default Rdk.Edge_transport.Transport_copy]
      [@sop.label "Branch split"] [@sop.kind edge_transport_split_parameter];
    merge : Rdk.Edge_transport.merge
      [@sop.default Rdk.Edge_transport.Transport_merge_add]
      [@sop.label "Branch merge"] [@sop.kind edge_transport_merge_parameter];
    normalization : Rdk.Edge_transport.normalization
      [@sop.default Rdk.Edge_transport.Transport_no_normalization]
      [@sop.label "Normalization"]
      [@sop.kind edge_transport_normalization_parameter];
  } [@@sop.node_key "edge_transport"] [@@sop.node_label "Edge Transport"]
    [@@sop.node_category "Attribute/Transport"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let root_group, roots = transport_roots parameters.roots
        parameters.root_group in
    Sop.edge_transport ~label
      ?point_group:(optional_text parameters.point_group) ?root_group
      ~roots ~direction:parameters.direction ~operation:parameters.operation
      ~root_value:parameters.root_value
      ~integrate_constant:parameters.integrate_constant
      ~scale_by_edge_length:parameters.scale_by_edge_length
      ~split:parameters.split ~merge:parameters.merge
      ~normalization:parameters.normalization
      ~attribute:parameters.attribute input)
  let factory = parameters_factory build
end

module Edge_transport_curves = struct
  type parameters = {
    attribute : string [@sop.default "value"] [@sop.label "Attribute"];
    primitive_group : string [@sop.default ""]
      [@sop.label "Primitive group"];
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Attribute owner"] [@sop.kind uv_owner_parameter];
    direction : Rdk.Edge_transport.direction
      [@sop.default Rdk.Edge_transport.Transport_forward] [@sop.label "Direction"]
      [@sop.kind edge_transport_direction_parameter];
    operation : Rdk.Edge_transport.operation
      [@sop.default Rdk.Edge_transport.Transport] [@sop.label "Operation"]
      [@sop.kind edge_transport_operation_parameter];
    root_value : Rdk.Edge_transport.root_value
      [@sop.default Rdk.Edge_transport.Transport_root_zero] [@sop.label "Root value"]
      [@sop.kind edge_transport_root_value_parameter];
    integrate_constant : bool [@sop.default false]
      [@sop.label "Integrate constant"];
    scale_by_edge_length : bool [@sop.default false]
      [@sop.label "Scale by edge length"];
    normalization : Rdk.Edge_transport.normalization
      [@sop.default Rdk.Edge_transport.Transport_no_normalization]
      [@sop.label "Normalization"]
      [@sop.kind edge_transport_normalization_parameter];
  } [@@sop.node_key "edge_transport_curves"]
    [@@sop.node_label "Edge Transport Curves"]
    [@@sop.node_category "Attribute/Transport"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.edge_transport_curves ~label
        ?primitive_group:(optional_text parameters.primitive_group)
        ~owner:parameters.owner ~direction:parameters.direction
        ~operation:parameters.operation ~root_value:parameters.root_value
        ~integrate_constant:parameters.integrate_constant
        ~scale_by_edge_length:parameters.scale_by_edge_length
        ~normalization:parameters.normalization
        ~attribute:parameters.attribute input)
  let factory = parameters_factory build
end

module Edge_transport_parent = struct
  type parameters = {
    attribute : string [@sop.default "value"] [@sop.label "Attribute"];
    point_group : string [@sop.default ""] [@sop.label "Point group"];
    parent_attribute : string [@sop.default "parent"]
      [@sop.label "Parent attribute"];
    direction : Rdk.Edge_transport.direction
      [@sop.default Rdk.Edge_transport.Transport_forward] [@sop.label "Direction"]
      [@sop.kind edge_transport_direction_parameter];
    operation : Rdk.Edge_transport.operation
      [@sop.default Rdk.Edge_transport.Transport] [@sop.label "Operation"]
      [@sop.kind edge_transport_operation_parameter];
    root_value : Rdk.Edge_transport.root_value
      [@sop.default Rdk.Edge_transport.Transport_root_zero] [@sop.label "Root value"]
      [@sop.kind edge_transport_root_value_parameter];
    integrate_constant : bool [@sop.default false]
      [@sop.label "Integrate constant"];
    scale_by_edge_length : bool [@sop.default false]
      [@sop.label "Scale by edge length"];
    split : Rdk.Edge_transport.split [@sop.default Rdk.Edge_transport.Transport_copy]
      [@sop.label "Branch split"] [@sop.kind edge_transport_split_parameter];
    merge : Rdk.Edge_transport.merge
      [@sop.default Rdk.Edge_transport.Transport_merge_add]
      [@sop.label "Branch merge"] [@sop.kind edge_transport_merge_parameter];
    normalization : Rdk.Edge_transport.normalization
      [@sop.default Rdk.Edge_transport.Transport_no_normalization]
      [@sop.label "Normalization"]
      [@sop.kind edge_transport_normalization_parameter];
  } [@@sop.node_key "edge_transport_parent"]
    [@@sop.node_label "Edge Transport Parent"]
    [@@sop.node_category "Attribute/Transport"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.edge_transport_parent ~label
        ?point_group:(optional_text parameters.point_group)
        ~parent_attribute:parameters.parent_attribute
        ~direction:parameters.direction ~operation:parameters.operation
        ~root_value:parameters.root_value
        ~integrate_constant:parameters.integrate_constant
        ~scale_by_edge_length:parameters.scale_by_edge_length
        ~split:parameters.split ~merge:parameters.merge
        ~normalization:parameters.normalization
        ~attribute:parameters.attribute input)
  let factory = parameters_factory build
end

module Delete_attributes = struct
  type parameters = {
    delete_non_selected : bool [@sop.default false]
      [@sop.label "Delete non-selected"];
    point_pattern : string [@sop.default ""] [@sop.label "Point attributes"]
      [@sop.folder "Patterns"];
    vertex_pattern : string [@sop.default ""] [@sop.label "Vertex attributes"]
      [@sop.folder "Patterns"];
    primitive_pattern : string [@sop.default ""]
      [@sop.label "Primitive attributes"] [@sop.folder "Patterns"];
    detail_pattern : string [@sop.default ""] [@sop.label "Detail attributes"]
      [@sop.folder "Patterns"];
  } [@@sop.node_key "delete_attributes"]
    [@@sop.node_operation "attribute_delete_pattern"]
    [@@sop.node_label "Delete Attributes"]
    [@@sop.node_category "Attribute/Manage"] [@@sop.node_inputs 2] [@@sop.node_slots "input, reference"]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input reference ->
    Sop.delete_attributes ~label ?reference
      ~delete_non_selected:parameters.delete_non_selected
      ?point_pattern:(optional_text parameters.point_pattern)
      ?vertex_pattern:(optional_text parameters.vertex_pattern)
      ?primitive_pattern:(optional_text parameters.primitive_pattern)
      ?detail_pattern:(optional_text parameters.detail_pattern) input)
  let factory = parameters_factory build
end

module Rename_attributes = struct
  let conflict_token = function
    | Rdk.Attribute_ops.Attribute_rename_skip -> "skip"
    | Rdk.Attribute_ops.Attribute_rename_error -> "error"
    | Rdk.Attribute_ops.Attribute_rename_overwrite -> "overwrite"
  let conflict_of_token = function
    | "skip" -> Ok Rdk.Attribute_ops.Attribute_rename_skip
    | "error" -> Ok Rdk.Attribute_ops.Attribute_rename_error
    | "overwrite" -> Ok Rdk.Attribute_ops.Attribute_rename_overwrite
    | token -> Error (Printf.sprintf
        "unknown attribute rename conflict %S" token)
  let encode_rule (rule : Rdk.Attribute_ops.rename_rule) = [
      (match rule.rename_attribute_owner with None -> "any"
       | Some owner -> attribute_owner_token owner);
      rule.rename_attribute_pattern; rule.rename_attribute_replacement;
      conflict_token rule.rename_attribute_conflict;
    ]
  let decode_rule = function
    | [owner; pattern; replacement; conflict] ->
        let owner = String.lowercase_ascii (String.trim owner)
        and conflict = String.lowercase_ascii (String.trim conflict) in
        let owner = if owner = "any" || owner = "*" then Ok None
          else Result.map Option.some (attribute_owner_of_token owner) in
        Result.bind owner (fun rename_attribute_owner ->
          Result.map (fun rename_attribute_conflict -> {
            Rdk.Attribute_ops.rename_attribute_owner;
            rename_attribute_pattern = pattern;
            rename_attribute_replacement = replacement;
            rename_attribute_conflict }) (conflict_of_token conflict))
    | row -> Error (Printf.sprintf
        "Attribute Rename rule needs owner, pattern, replacement, and conflict; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  type parameters = {
    rules : Rdk.Attribute_ops.rename_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, replacement, conflict)"]
      [@sop.kind rules_parameter];
  } [@@sop.node_key "rename_attributes"]
    [@@sop.node_operation "attribute_rename_pattern"]
    [@@sop.node_label "Rename Attributes"]
    [@@sop.node_category "Attribute/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.rename_attributes ~label ~rules:parameters.rules input)
  let factory = parameters_factory build
end

module Swap_attributes = struct
  let method_token = function
    | Rdk.Attribute_ops.Attribute_swap -> "swap"
    | Rdk.Attribute_ops.Attribute_move -> "move"
    | Rdk.Attribute_ops.Attribute_copy -> "copy"
  let method_of_token = function
    | "swap" -> Ok Rdk.Attribute_ops.Attribute_swap
    | "move" -> Ok Rdk.Attribute_ops.Attribute_move
    | "copy" -> Ok Rdk.Attribute_ops.Attribute_copy
    | token -> Error (Printf.sprintf "unknown attribute swap method %S" token)
  let encode_rule (rule : Rdk.Attribute_ops.swap_rule) = [
      attribute_owner_token rule.swap_attribute_owner;
      rule.swap_attribute_source; rule.swap_attribute_destination;
      method_token rule.swap_attribute_method;
    ]
  let decode_rule = function
    | [owner; source; destination; method_] ->
        Result.bind (attribute_owner_of_token
          (String.lowercase_ascii (String.trim owner)))
          (fun swap_attribute_owner ->
            Result.map (fun swap_attribute_method -> {
              Rdk.Attribute_ops.swap_attribute_owner;
              swap_attribute_source = source;
              swap_attribute_destination = destination;
              swap_attribute_method })
              (method_of_token
                (String.lowercase_ascii (String.trim method_))))
    | row -> Error (Printf.sprintf
        "Attribute Swap rule needs owner, source, destination, and method; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  type parameters = {
    rules : Rdk.Attribute_ops.swap_rule list [@sop.default []]
      [@sop.label "Rules (owner, source, destination, method)"]
      [@sop.kind rules_parameter];
  } [@@sop.node_key "swap_attributes"]
    [@@sop.node_operation "attribute_swap"]
    [@@sop.node_label "Swap Attributes"]
    [@@sop.node_category "Attribute/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.swap_attributes ~label ~rules:parameters.rules input)
  let factory = parameters_factory build
end

module Blend_shapes = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Normalized", Rdk.Blend_shapes.Blend_normalized;
      "Differencing", Rdk.Blend_shapes.Blend_differencing;
    ]
  let masking_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Blend_shapes.Blend_no_mask;
      "Set from attribute", Rdk.Blend_shapes.Blend_set_from_attribute;
      "Scale from attribute", Rdk.Blend_shapes.Blend_scale_from_attribute;
    ]
  let mask_source_parameter = Parameter.choice ~equal:( = ) [
      "First input", Rdk.Blend_shapes.Blend_mask_first_input;
      "Shape", Rdk.Blend_shapes.Blend_mask_shape;
    ]
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    mode : Rdk.Blend_shapes.mode [@sop.default Rdk.Blend_shapes.Blend_normalized]
      [@sop.label "Mode"] [@sop.kind mode_parameter];
    attributes : string [@sop.default "*"] [@sop.label "Attributes"];
    weight1 : float [@sop.default 1.] [@sop.label "Weight 1"]
      [@sop.folder "Weights"] [@sop.min (-1.)] [@sop.max 2.];
    weight2 : float [@sop.default 0.] [@sop.label "Weight 2"]
      [@sop.folder "Weights"] [@sop.min (-1.)] [@sop.max 2.];
    weight3 : float [@sop.default 0.] [@sop.label "Weight 3"]
      [@sop.folder "Weights"] [@sop.min (-1.)] [@sop.max 2.];
    weight4 : float [@sop.default 0.] [@sop.label "Weight 4"]
      [@sop.folder "Weights"] [@sop.min (-1.)] [@sop.max 2.];
    masking : Rdk.Blend_shapes.masking
      [@sop.default Rdk.Blend_shapes.Blend_no_mask] [@sop.label "Masking"]
      [@sop.folder "Mask"] [@sop.kind masking_parameter];
    mask_attribute : string [@sop.default "mask"] [@sop.label "Mask attribute"]
      [@sop.folder "Mask"];
    mask_source : Rdk.Blend_shapes.mask_source
      [@sop.default Rdk.Blend_shapes.Blend_mask_first_input]
      [@sop.label "Mask source"] [@sop.folder "Mask"]
      [@sop.kind mask_source_parameter];
    point_id_attribute : string [@sop.default ""]
      [@sop.label "Point ID attribute"] [@sop.folder "Matching"];
  } [@@sop.node_key "blend_shapes"] [@@sop.node_label "Blend Shapes"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 5]
    [@@sop.node_slots "input, shape1, shape2, shape3, shape4"]
    [@@sop.node_optional "1,2,3,4"] [@@deriving sop_params, sop_node]
  (* Unwired shape slots drop out (none wired passes the input through); the
     mask applies to every wired shape. *)
  let build = parameters_build (fun ~label parameters input shape1 shape2 shape3 shape4 ->
    let masked = parameters.masking <> Rdk.Blend_shapes.Blend_no_mask in
    let mask_attribute =
      if masked then optional_text parameters.mask_attribute else None in
    let shapes = List.filter_map (fun (weight, shape) ->
        Option.map (Sop.blend_shape ?mask_attribute
          ~mask_source:parameters.mask_source ~weight) shape) [
        parameters.weight1, shape1; parameters.weight2, shape2;
        parameters.weight3, shape3; parameters.weight4, shape4] in
    if shapes = [] then
      operator ~label ~operation:"blend_shapes" [|input|]
        (fun ~node_id:_ _context inputs -> cooked inputs.(0))
    else
    Sop.blend_shapes ~label ?point_group:(optional_text parameters.group)
      ~mode:parameters.mode ~masking:parameters.masking ?mask_attribute
      ?point_id_attribute:(optional_text parameters.point_id_attribute)
      ~attributes:parameters.attributes ~shapes input)
  let factory = parameters_factory build
end

module Attribute_composite = struct
  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Mean", Rdk.Attribute_composite.Composite_mean;
      "Maximum", Rdk.Attribute_composite.Composite_maximum;
      "Minimum", Rdk.Attribute_composite.Composite_minimum;
      "Over", Rdk.Attribute_composite.Composite_over;
      "Under", Rdk.Attribute_composite.Composite_under;
    ]
  type parameters = {
    operation : Rdk.Attribute_composite.operation
      [@sop.default Rdk.Attribute_composite.Composite_mean]
      [@sop.label "Operation"] [@sop.kind operation_parameter];
    weight : float [@sop.default 1.] [@sop.label "Weight"]
      [@sop.min 0.] [@sop.max 1.];
    point_attributes : string [@sop.default "*"]
      [@sop.label "Point attributes"];
    allow_position : bool [@sop.default false] [@sop.label "Allow P"];
    alpha_attribute : string [@sop.default ""] [@sop.label "Alpha attribute"];
    vertex_attributes : string [@sop.default "*"]
      [@sop.label "Vertex attributes"] [@sop.folder "Attributes"];
    primitive_attributes : string [@sop.default "*"]
      [@sop.label "Primitive attributes"] [@sop.folder "Attributes"];
    detail_attributes : string [@sop.default "*"]
      [@sop.label "Detail attributes"] [@sop.folder "Attributes"];
    weight1 : float [@sop.default 1.] [@sop.label "Weight 1"]
      [@sop.folder "Layers"] [@sop.min 0.] [@sop.max 1.];
    weight2 : float [@sop.default 1.] [@sop.label "Weight 2"]
      [@sop.folder "Layers"] [@sop.min 0.] [@sop.max 1.];
    weight3 : float [@sop.default 1.] [@sop.label "Weight 3"]
      [@sop.folder "Layers"] [@sop.min 0.] [@sop.max 1.];
    weight4 : float [@sop.default 1.] [@sop.label "Weight 4"]
      [@sop.folder "Layers"] [@sop.min 0.] [@sop.max 1.];
  } [@@sop.node_key "attribute_composite"]
    [@@sop.node_label "Attribute Composite"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 5]
    [@@sop.node_slots "input, layer1, layer2, layer3, layer4"]
    [@@sop.node_optional "1,2,3,4"] [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input layer1 layer2 layer3 layer4 ->
    let inputs = List.filter_map (fun (weight, layer) ->
        Option.map (Sop.attribute_composite_input ~weight) layer) [
        parameters.weight1, layer1; parameters.weight2, layer2;
        parameters.weight3, layer3; parameters.weight4, layer4] in
    Sop.attribute_composite ~label ~operation:parameters.operation
      ~weight:parameters.weight
      ~detail_attributes:parameters.detail_attributes
      ~primitive_attributes:parameters.primitive_attributes
      ~point_attributes:parameters.point_attributes
      ~vertex_attributes:parameters.vertex_attributes
      ~allow_position:parameters.allow_position
      ?alpha_attribute:(optional_text parameters.alpha_attribute) ~inputs input)
  let factory = parameters_factory build
end

module Attribute_fade = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    fade_attribute : string [@sop.default "fade"] [@sop.label "Fade attribute"];
    start_attribute : string [@sop.default ""] [@sop.label "Start attribute"]
      [@sop.folder "Sources"];
    start_retime_offset : float [@sop.default 0.] [@sop.label "Start offset"]
      [@sop.folder "Sources/Start retime"] [@sop.min (-100.)]
      [@sop.max 100.];
    start_retime_scale : float [@sop.default 1.] [@sop.label "Start scale"]
      [@sop.folder "Sources/Start retime"] [@sop.min (-10.)]
      [@sop.max 10.];
    hold_scale_attribute : string [@sop.default ""]
      [@sop.label "Hold scale attribute"] [@sop.folder "Sources"];
    frame_offset : float [@sop.default 0.] [@sop.label "Frame offset"]
      [@sop.folder "Timing"] [@sop.min (-100.)] [@sop.max 100.];
    fade_in : float [@sop.default 2.] [@sop.label "Fade in"]
      [@sop.folder "Timing"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    fade_hold : float [@sop.default 0.] [@sop.label "Hold"]
      [@sop.folder "Timing"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    fade_out : float [@sop.default 2.] [@sop.label "Fade out"]
      [@sop.folder "Timing"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    visualize : bool [@sop.default false] [@sop.label "Visualize fade"]
      [@sop.folder "Output"];
  } [@@sop.node_key "attribute_fade"] [@@sop.node_label "Attribute Fade"]
    [@@sop.node_category "Attribute/Motion"] [@@sop.node_inputs 3] [@@sop.node_slots "input, start_source, hold_source"]
    [@@sop.node_optional "1,2"] [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input start_source hold_source ->
    Sop.attribute_fade ~label ?group:(optional_text parameters.group)
      ?start_source ?hold_source ~fade_attribute:parameters.fade_attribute
      ?start_attribute:(optional_text parameters.start_attribute)
      ~start_retime:(parameters.start_retime_offset,
        parameters.start_retime_scale)
      ?hold_scale_attribute:
        (optional_text parameters.hold_scale_attribute)
      ~frame_offset:parameters.frame_offset ~fade_in:parameters.fade_in
      ~fade_hold:parameters.fade_hold ~fade_out:parameters.fade_out
      ~visualize:parameters.visualize input)

  let factory = parameters_factory build
end

module Point_velocity = struct
  type initialization = Compute | Keep | Set | From_attribute
  let approximation_parameter = Parameter.choice ~equal:( = ) [
      "Backward difference", Rdk.Motion.Backward_difference;
      "Central difference", Rdk.Motion.Central_difference;
      "Forward difference", Rdk.Motion.Forward_difference;
    ]
  let initialization_parameter = Parameter.choice ~equal:( = ) [
      "Compute from deformation", Compute; "Keep incoming", Keep;
      "Set value", Set; "From attribute", From_attribute;
    ]
  let unmatched_parameter = Parameter.choice ~equal:( = ) [
      "Error", Rdk.Motion.Velocity_unmatched_error;
      "Zero", Rdk.Motion.Velocity_unmatched_zero;
    ]
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    approximation : Rdk.Motion.velocity_approximation
      [@sop.default Rdk.Motion.Backward_difference]
      [@sop.label "Approximation"] [@sop.kind approximation_parameter];
    dt : float [@sop.default 0.016666666666666666] [@sop.label "Time step"]
      [@sop.min 0.000001] [@sop.max 10.] [@sop.hard_min 0.];
    initialization : initialization [@sop.default Compute]
      [@sop.label "Initialization"] [@sop.kind initialization_parameter];
    set_x : float [@sop.default 0.] [@sop.label "Velocity X"]
      [@sop.folder "Initialization/Value"] [@sop.min (-100.)]
      [@sop.max 100.]; [@sop.vec3 "set"]
    set_y : float [@sop.default 0.] [@sop.label "Velocity Y"]
      [@sop.folder "Initialization/Value"] [@sop.min (-100.)]
      [@sop.max 100.]; [@sop.vec3 "set"]
    set_z : float [@sop.default 0.] [@sop.label "Velocity Z"]
      [@sop.folder "Initialization/Value"] [@sop.min (-100.)]
      [@sop.max 100.]; [@sop.vec3 "set"]
    source_attribute : string [@sop.default "v"]
      [@sop.label "Source attribute"] [@sop.folder "Initialization/Attribute"];
    source_scale : float [@sop.default 1.] [@sop.label "Source scale"]
      [@sop.folder "Initialization/Attribute"] [@sop.min (-10.)]
      [@sop.max 10.];
    match_attribute : string [@sop.default ""] [@sop.label "Match attribute"]
      [@sop.folder "Matching"];
    unmatched : Rdk.Motion.velocity_unmatched
      [@sop.default Rdk.Motion.Velocity_unmatched_error]
      [@sop.label "Unmatched"] [@sop.folder "Matching"]
      [@sop.kind unmatched_parameter];
    velocity_attribute : string [@sop.default "v"]
      [@sop.label "Velocity attribute"] [@sop.folder "Output"];
    add_x : float [@sop.default 0.] [@sop.label "Add X"]
      [@sop.folder "Output/Add velocity"] [@sop.min (-100.)]
      [@sop.max 100.]; [@sop.vec3 "add"]
    add_y : float [@sop.default 0.] [@sop.label "Add Y"]
      [@sop.folder "Output/Add velocity"] [@sop.min (-100.)]
      [@sop.max 100.]; [@sop.vec3 "add"]
    add_z : float [@sop.default 0.] [@sop.label "Add Z"]
      [@sop.folder "Output/Add velocity"] [@sop.min (-100.)]
      [@sop.max 100.]; [@sop.vec3 "add"]
    compute_acceleration : bool [@sop.default false]
      [@sop.label "Compute acceleration"] [@sop.folder "Output"];
    acceleration_attribute : string [@sop.default "accel"]
      [@sop.label "Acceleration attribute"] [@sop.folder "Output"];
  } [@@sop.node_key "point_velocity"] [@@sop.node_label "Point Velocity"]
    [@@sop.node_category "Attribute/Motion"] [@@sop.node_inputs 3] [@@sop.node_slots "input, previous, next"]
    [@@sop.node_optional "1,2"] [@@deriving sop_params, sop_node]
  let initialization parameters = match parameters.initialization with
    | Compute -> Rdk.Motion.Compute_from_deformation
    | Keep -> Rdk.Motion.Keep_incoming
    | Set -> Rdk.Motion.Set_value
        (Vec3.create parameters.set_x parameters.set_y parameters.set_z)
    | From_attribute -> Rdk.Motion.From_attribute {
        name = parameters.source_attribute; scale = parameters.source_scale }
  let build = parameters_build (fun ~label parameters input previous next ->
    let inputs = Array.of_list (input :: List.filter_map Fun.id [previous; next]) in
    let cook_mode = if Array.length inputs = 1 then Node.Duplicate_input 0
      else Node.Generic in
    operator ~label ~operation:"point_velocity" ~cook_mode inputs
      (fun ~node_id:_ context inputs ->
        let slot = ref 1 in
        let take present = if not present then None
          else (let value = Some inputs.(!slot) in incr slot; value) in
        let previous = take (previous <> None) in
        let next = take (next <> None) in
        let points = match optional_text parameters.group with
          | None -> Ok None
          | Some name ->
              (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point name inputs.(0) with
               | Some group -> Ok (Some group)
               | None -> Error (Diagnostic.error ~code:"missing_group"
                   (Printf.sprintf "point_velocity could not find point group %S" name))) in
        Result.bind points (fun points ->
          rdk_cooked (Rdk.Motion.point_velocity
            ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
            ?points ?previous ?next ~approximation:parameters.approximation
            ~dt:parameters.dt ~initialization:(initialization parameters)
            ?match_attribute:(optional_text parameters.match_attribute)
            ~unmatched:parameters.unmatched
            ~velocity_attribute:parameters.velocity_attribute
            ~add_velocity:(Vec3.create parameters.add_x parameters.add_y
              parameters.add_z)
            ~compute_acceleration:parameters.compute_acceleration
            ~acceleration_attribute:parameters.acceleration_attribute inputs.(0)))))

  let factory = parameters_factory build
end

module Attribute_copy = struct
  type match_ = Cyclic | By_values | To_element
  let match_parameter = Parameter.choice ~equal:( = ) [
      "Cyclic", Cyclic; "By attribute values", By_values;
      "To source element", To_element;
    ]
  let encode_rule (rule : Rdk.Attribute_ops.copy_rule) = [
      attribute_owner_token rule.copy_owner; rule.copy_pattern;
      Option.value ~default:"" rule.copy_into;
    ]
  let decode_rule = function
    | [owner; pattern; into] ->
        Result.map (fun copy_owner -> { Rdk.Attribute_ops.copy_owner;
          copy_pattern = pattern; copy_into = optional_text into })
          (attribute_owner_of_token
            (String.lowercase_ascii (String.trim owner)))
    | row -> Error (Printf.sprintf
        "Attribute Copy rule needs owner, pattern, and destination; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  let default_rules = [{ Rdk.Attribute_ops.copy_owner = Rdk.Attribute.Point;
      copy_pattern = "*"; copy_into = None }]
  type parameters = {
    group_owner : Rdk.Group.owner [@sop.default Rdk.Group.Point]
      [@sop.label "Selection owner"] [@sop.kind ordinary_group_owner_parameter];
    match_ : match_ [@sop.default Cyclic] [@sop.label "Element matching"]
      [@sop.kind match_parameter];
    source_match_attribute : string [@sop.default "id"]
      [@sop.label "Source match attribute"] [@sop.folder "Matching"];
    target_match_attribute : string [@sop.default "id"]
      [@sop.label "Target match attribute"] [@sop.folder "Matching"];
    target_element_attribute : string [@sop.default "source"]
      [@sop.label "Source element attribute"] [@sop.folder "Matching"];
    allow_position : bool [@sop.default false] [@sop.label "Allow P"];
    source_group : string [@sop.default ""] [@sop.label "Source group"]
      [@sop.folder "Groups/Source"];
    source_group_pattern : string [@sop.default ""]
      [@sop.label "Source group pattern"] [@sop.folder "Groups/Source"];
    target_group : string [@sop.default ""] [@sop.label "Target group"]
      [@sop.folder "Groups/Target"];
    target_group_pattern : string [@sop.default ""]
      [@sop.label "Target group pattern"] [@sop.folder "Groups/Target"];
    rules : Rdk.Attribute_ops.copy_rule list [@sop.default default_rules]
      [@sop.label "Rules (owner, pattern, destination)"]
      [@sop.folder "Attributes"] [@sop.kind rules_parameter];
  } [@@sop.node_key "attribute_copy"] [@@sop.node_label "Attribute Copy"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2] [@@sop.node_slots "source, target"]
    [@@deriving sop_params, sop_node]
  let match_ parameters = match parameters.match_ with
    | Cyclic -> Rdk.Attribute_ops.Cyclic
    | By_values -> Rdk.Attribute_ops.By_values {
        source_attribute = parameters.source_match_attribute;
        target_attribute = parameters.target_match_attribute }
    | To_element -> Rdk.Attribute_ops.To_element {
        target_attribute = parameters.target_element_attribute }
  let build = parameters_build (fun ~label parameters source target ->
    let source_group, source_group_pattern = exact_or_pattern
        parameters.source_group parameters.source_group_pattern
    and target_group, target_group_pattern = exact_or_pattern
        parameters.target_group parameters.target_group_pattern in
    Sop.attribute_copy ~label ~match_:(match_ parameters)
      ~allow_position:parameters.allow_position ?source_group
      ?source_group_pattern ?target_group ?target_group_pattern
      ~group_owner:parameters.group_owner ~rules:parameters.rules
      ~source ~target ())
  let factory = parameters_factory build
end

module Attribute_interpolate = struct
  type driver = Primitive_uvw | Point_weights | Vertex_weights
    | Primitive_weights
  let driver_parameter = Parameter.choice ~equal:( = ) [
      "Primitive UVW", Primitive_uvw; "Point weights", Point_weights;
      "Vertex weights", Vertex_weights;
      "Primitive weights", Primitive_weights;
    ]
  let encode_attribute (attribute : Rdk.Attribute_ops.interpolate_attribute) = [
      attribute_owner_token attribute.interpolate_owner;
      attribute.interpolate_source; attribute.interpolate_target;
    ]
  let decode_attribute = function
    | [owner; source; target] -> Result.map (fun interpolate_owner -> {
        Rdk.Attribute_ops.interpolate_owner; interpolate_source = source;
        interpolate_target = target })
        (attribute_owner_of_token
          (String.lowercase_ascii (String.trim owner)))
    | row -> Error (Printf.sprintf
        "Attribute Interpolate rule needs owner, source, and target; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun attributes ->
        Result.map (fun attribute -> attribute :: attributes)
          (decode_attribute row))) (Ok []) rows |> Result.map List.rev)
  let attributes_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun attributes -> encode_table
        (List.map encode_attribute attributes)) ~decode
  let default_attributes = [{
      Rdk.Attribute_ops.interpolate_owner = Rdk.Attribute.Point;
      interpolate_source = "Cd"; interpolate_target = "Cd" }]
  type parameters = {
    target_owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Target owner"] [@sop.kind attribute_owner_parameter];
    attributes : Rdk.Attribute_ops.interpolate_attribute list
      [@sop.default default_attributes]
      [@sop.label "Attributes (owner, source, target)"]
      [@sop.kind attributes_parameter];
    group : string [@sop.default ""] [@sop.label "Target group"];
    group_pattern : string [@sop.default ""]
      [@sop.label "Target group pattern"];
    driver : driver [@sop.default Primitive_uvw] [@sop.label "Driver"]
      [@sop.kind driver_parameter];
    primitive_attribute : string [@sop.default "sourceprim"]
      [@sop.label "Primitive attribute"] [@sop.folder "Driver"];
    uvw_attribute : string [@sop.default "sourceuvw"]
      [@sop.label "UVW attribute"] [@sop.folder "Driver"];
    numbers_attribute : string [@sop.default "sourcenums"]
      [@sop.label "Numbers attribute"] [@sop.folder "Driver"];
    weights_attribute : string [@sop.default "sourceweights"]
      [@sop.label "Weights attribute"] [@sop.folder "Driver"];
    compute_weights : bool [@sop.default false]
      [@sop.label "Compute weight arrays"] [@sop.folder "Output weights"];
    computed_owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Computed owner"] [@sop.folder "Output weights"]
      [@sop.kind uv_owner_parameter];
    computed_numbers_attribute : string [@sop.default "computednums"]
      [@sop.label "Computed numbers"] [@sop.folder "Output weights"];
    computed_weights_attribute : string [@sop.default "computedweights"]
      [@sop.label "Computed weights"] [@sop.folder "Output weights"];
    point_pattern : string [@sop.default ""] [@sop.label "Point pattern"]
      [@sop.folder "Patterns"];
    vertex_pattern : string [@sop.default ""] [@sop.label "Vertex pattern"]
      [@sop.folder "Patterns"];
    primitive_pattern : string [@sop.default ""]
      [@sop.label "Primitive pattern"] [@sop.folder "Patterns"];
    detail_pattern : string [@sop.default ""] [@sop.label "Detail pattern"]
      [@sop.folder "Patterns"];
    match_groups : bool [@sop.default false] [@sop.label "Match groups"]
      [@sop.folder "Patterns"];
    pre_scale : float [@sop.default 1.] [@sop.label "Pre-scale"]
      [@sop.folder "Weights"] [@sop.min (-10.)] [@sop.max 10.];
    normalize_weights : bool [@sop.default true]
      [@sop.label "Normalize weights"] [@sop.folder "Weights"];
    threshold : float [@sop.default 0.] [@sop.label "Threshold"]
      [@sop.folder "Weights"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.];
    blend : float [@sop.default 1.] [@sop.label "Blend"]
      [@sop.folder "Weights"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.] [@sop.hard_max 1.];
    unmatched : Rdk.Attribute_ops.unmatched
      [@sop.default Rdk.Attribute_ops.Keep_target] [@sop.label "Unmatched"]
      [@sop.kind transfer_unmatched_parameter];
  } [@@sop.node_key "attribute_interpolate"]
    [@@sop.node_label "Attribute Interpolate"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2] [@@sop.node_slots "source, target"]
    [@@deriving sop_params, sop_node]
  let driver parameters = match parameters.driver with
    | Primitive_uvw -> Rdk.Attribute_ops.Primitive_uvw {
        primitive_attribute = parameters.primitive_attribute;
        uvw_attribute = parameters.uvw_attribute }
    | Point_weights -> Rdk.Attribute_ops.Point_weights {
        numbers_attribute = parameters.numbers_attribute;
        weights_attribute = parameters.weights_attribute }
    | Vertex_weights -> Rdk.Attribute_ops.Vertex_weights {
        numbers_attribute = parameters.numbers_attribute;
        weights_attribute = parameters.weights_attribute }
    | Primitive_weights -> Rdk.Attribute_ops.Primitive_weights {
        numbers_attribute = parameters.numbers_attribute;
        weights_attribute = parameters.weights_attribute }
  let build = parameters_build (fun ~label parameters source target ->
    let group, group_pattern = exact_or_pattern parameters.group
        parameters.group_pattern
    and compute_weights = if parameters.compute_weights then Some {
        Rdk.Attribute_ops.computed_owner = parameters.computed_owner;
        computed_numbers_attribute = parameters.computed_numbers_attribute;
        computed_weights_attribute = parameters.computed_weights_attribute }
      else None in
    Sop.attribute_interpolate ~label ?group ?group_pattern
      ~driver:(driver parameters) ?compute_weights
      ?point_pattern:(optional_text parameters.point_pattern)
      ?vertex_pattern:(optional_text parameters.vertex_pattern)
      ?primitive_pattern:(optional_text parameters.primitive_pattern)
      ?detail_pattern:(optional_text parameters.detail_pattern)
      ~match_groups:parameters.match_groups
      ~pre_scale:parameters.pre_scale
      ~normalize_weights:parameters.normalize_weights
      ~threshold:parameters.threshold ~blend:parameters.blend
      ~unmatched:parameters.unmatched ~target_owner:parameters.target_owner
      ~attributes:parameters.attributes ~source ~target ())
  let factory = parameters_factory build
end

module Attribute_transfer = struct
  let vertex_selection_parameter = Parameter.choice ~equal:( = ) [
      "All triangle vertices", Rdk.Attribute_ops.All_triangle_vertices;
      "Any triangle vertex", Rdk.Attribute_ops.Any_triangle_vertex;
    ]
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    pattern : string [@sop.default "*"] [@sop.label "Attributes"];
    mode : transfer_mode [@sop.default Transfer_nearest]
      [@sop.label "Transfer mode"] [@sop.kind transfer_mode_parameter];
    neighbors : int [@sop.default 4] [@sop.label "Neighbors"]
      [@sop.folder "Sampling"] [@sop.min 1] [@sop.max 128]
      [@sop.hard_min 1];
    power : float [@sop.default 2.] [@sop.label "Inverse power"]
      [@sop.folder "Sampling"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    kernel_radius : float [@sop.default 1.] [@sop.label "Kernel radius"]
      [@sop.folder "Sampling"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    max_distance : float [@sop.default 1.] [@sop.label "Maximum distance"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    blend_width : float [@sop.default 0.] [@sop.label "Blend width"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    falloff : transfer_falloff [@sop.default Transfer_linear]
      [@sop.label "Falloff"] [@sop.folder "Distance"]
      [@sop.kind transfer_falloff_parameter];
    uniform_bias : float [@sop.default 0.5] [@sop.label "Uniform bias"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.] [@sop.hard_max 1.];
    unmatched : Rdk.Attribute_ops.unmatched
      [@sop.default Rdk.Attribute_ops.Keep_target] [@sop.label "Unmatched"]
      [@sop.kind transfer_unmatched_parameter];
    source_group : string [@sop.default ""] [@sop.label "Source group"]
      [@sop.folder "Groups/Source"];
    source_group_pattern : string [@sop.default ""]
      [@sop.label "Source group pattern"] [@sop.folder "Groups/Source"];
    source_vertex_group : string [@sop.default ""]
      [@sop.label "Source vertex group"] [@sop.folder "Groups/Source"];
    source_vertex_group_pattern : string [@sop.default ""]
      [@sop.label "Source vertex pattern"] [@sop.folder "Groups/Source"];
    source_vertex_selection : Rdk.Attribute_ops.surface_vertex_selection
      [@sop.default Rdk.Attribute_ops.All_triangle_vertices]
      [@sop.label "Vertex selection"] [@sop.folder "Groups/Source"]
      [@sop.kind vertex_selection_parameter];
    target_group : string [@sop.default ""] [@sop.label "Target group"]
      [@sop.folder "Groups/Target"];
    target_group_pattern : string [@sop.default ""]
      [@sop.label "Target group pattern"] [@sop.folder "Groups/Target"];
  } [@@sop.node_key "attribute_transfer"]
    [@@sop.node_label "Attribute Transfer"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2] [@@sop.node_slots "source, target"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters source target ->
    let source_group, source_group_pattern = exact_or_pattern
        parameters.source_group parameters.source_group_pattern
    and source_vertex_group, source_vertex_group_pattern = exact_or_pattern
        parameters.source_vertex_group
        parameters.source_vertex_group_pattern
    and target_group, target_group_pattern = exact_or_pattern
        parameters.target_group parameters.target_group_pattern in
    Sop.attribute_transfer ~label ~owner:parameters.owner
      ~pattern:parameters.pattern
      ~mode:(transfer_mode parameters.mode parameters.neighbors
        parameters.power parameters.kernel_radius)
      ~max_distance:parameters.max_distance
      ~blend_width:parameters.blend_width
      ~falloff:(transfer_falloff parameters.falloff parameters.uniform_bias)
      ~unmatched:parameters.unmatched ?source_group ?source_group_pattern
      ?source_vertex_group ?source_vertex_group_pattern
      ~source_vertex_selection:parameters.source_vertex_selection
      ?target_group ?target_group_pattern ~source ~target ())
  let factory = parameters_factory build
end

module Attribute_transfer_surface = struct
  let vertex_selection_parameter = Parameter.choice ~equal:( = ) [
      "All triangle vertices", Rdk.Attribute_ops.All_triangle_vertices;
      "Any triangle vertex", Rdk.Attribute_ops.Any_triangle_vertex;
    ]
  let encode_attribute (attribute : Rdk.Attribute_ops.surface_attribute) = [
      attribute_owner_token attribute.source_owner; attribute.source_name;
      attribute.target_name;
    ]
  let decode_attribute = function
    | [owner; source_name; target_name] ->
        Result.map (fun source_owner -> {
          Rdk.Attribute_ops.source_owner; source_name; target_name })
          (attribute_owner_of_token
            (String.lowercase_ascii (String.trim owner)))
    | row -> Error (Printf.sprintf
        "Surface Transfer attribute needs owner, source, and target; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun attributes ->
        Result.map (fun attribute -> attribute :: attributes)
          (decode_attribute row))) (Ok []) rows |> Result.map List.rev)
  let attributes_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun attributes -> encode_table
        (List.map encode_attribute attributes)) ~decode
  let default_attributes = [Rdk.Attribute_ops.surface_attribute
      ~owner:Rdk.Attribute.Point "Cd"]
  type parameters = {
    target_owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Target owner"]
      [@sop.kind element_attribute_owner_parameter];
    attributes : Rdk.Attribute_ops.surface_attribute list
      [@sop.default default_attributes]
      [@sop.label "Attributes (owner, source, target)"]
      [@sop.kind attributes_parameter];
    max_distance : float [@sop.default 1.] [@sop.label "Maximum distance"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    blend_width : float [@sop.default 0.] [@sop.label "Blend width"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    falloff : transfer_falloff [@sop.default Transfer_linear]
      [@sop.label "Falloff"] [@sop.folder "Distance"]
      [@sop.kind transfer_falloff_parameter];
    uniform_bias : float [@sop.default 0.5] [@sop.label "Uniform bias"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.] [@sop.hard_max 1.];
    unmatched : Rdk.Attribute_ops.unmatched
      [@sop.default Rdk.Attribute_ops.Keep_target] [@sop.label "Unmatched"]
      [@sop.kind transfer_unmatched_parameter];
    distance_attribute : string [@sop.default ""]
      [@sop.label "Distance attribute"] [@sop.folder "Output"];
    source_group : string [@sop.default ""] [@sop.label "Source group"]
      [@sop.folder "Groups/Source"];
    source_group_pattern : string [@sop.default ""]
      [@sop.label "Source group pattern"] [@sop.folder "Groups/Source"];
    source_vertex_group : string [@sop.default ""]
      [@sop.label "Source vertex group"] [@sop.folder "Groups/Source"];
    source_vertex_group_pattern : string [@sop.default ""]
      [@sop.label "Source vertex group pattern"]
      [@sop.folder "Groups/Source"];
    source_vertex_selection : Rdk.Attribute_ops.surface_vertex_selection
      [@sop.default Rdk.Attribute_ops.All_triangle_vertices]
      [@sop.label "Vertex selection"] [@sop.folder "Groups/Source"]
      [@sop.kind vertex_selection_parameter];
    target_group : string [@sop.default ""] [@sop.label "Target group"]
      [@sop.folder "Groups/Target"];
    target_group_pattern : string [@sop.default ""]
      [@sop.label "Target group pattern"] [@sop.folder "Groups/Target"];
  } [@@sop.node_key "attribute_transfer_surface"]
    [@@sop.node_label "Attribute Transfer Surface"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2] [@@sop.node_slots "source, target"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters source target ->
    let source_group, source_group_pattern = exact_or_pattern
        parameters.source_group parameters.source_group_pattern
    and source_vertex_group, source_vertex_group_pattern = exact_or_pattern
        parameters.source_vertex_group
        parameters.source_vertex_group_pattern
    and target_group, target_group_pattern = exact_or_pattern
        parameters.target_group parameters.target_group_pattern in
    Sop.attribute_transfer_surface ~label
      ~max_distance:parameters.max_distance
      ~blend_width:parameters.blend_width
      ~falloff:(transfer_falloff parameters.falloff parameters.uniform_bias)
      ~unmatched:parameters.unmatched ~target_owner:parameters.target_owner
      ?distance_attribute:(optional_text parameters.distance_attribute)
      ?source_group ?source_group_pattern ?source_vertex_group
      ?source_vertex_group_pattern
      ~source_vertex_selection:parameters.source_vertex_selection
      ?target_group ?target_group_pattern ~attributes:parameters.attributes
      ~source ~target ())
  let factory = parameters_factory build
end

module Attribute_transfer_all = struct
  type parameters = {
    point_pattern : string [@sop.default "*"] [@sop.label "Point attributes"];
    vertex_pattern : string [@sop.default ""] [@sop.label "Vertex attributes"];
    primitive_pattern : string [@sop.default ""]
      [@sop.label "Primitive attributes"];
    detail_pattern : string [@sop.default ""] [@sop.label "Detail attributes"];
    mode : transfer_mode [@sop.default Transfer_nearest]
      [@sop.label "Transfer mode"] [@sop.kind transfer_mode_parameter];
    neighbors : int [@sop.default 4] [@sop.label "Neighbors"]
      [@sop.folder "Sampling"] [@sop.min 1] [@sop.max 128]
      [@sop.hard_min 1];
    power : float [@sop.default 2.] [@sop.label "Inverse power"]
      [@sop.folder "Sampling"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    kernel_radius : float [@sop.default 1.] [@sop.label "Kernel radius"]
      [@sop.folder "Sampling"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    max_distance : float [@sop.default 1.] [@sop.label "Maximum distance"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    blend_width : float [@sop.default 0.] [@sop.label "Blend width"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    falloff : transfer_falloff [@sop.default Transfer_linear]
      [@sop.label "Falloff"] [@sop.folder "Distance"]
      [@sop.kind transfer_falloff_parameter];
    uniform_bias : float [@sop.default 0.5] [@sop.label "Uniform bias"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.] [@sop.hard_max 1.];
    unmatched : Rdk.Attribute_ops.unmatched
      [@sop.default Rdk.Attribute_ops.Keep_target] [@sop.label "Unmatched"]
      [@sop.kind transfer_unmatched_parameter];
  } [@@sop.node_key "attribute_transfer_all"]
    [@@sop.node_label "Attribute Transfer All"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2] [@@sop.node_slots "source, target"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters source target ->
    Sop.attribute_transfer_all ~label
        ?point_pattern:(optional_text parameters.point_pattern)
        ?vertex_pattern:(optional_text parameters.vertex_pattern)
        ?primitive_pattern:(optional_text parameters.primitive_pattern)
        ?detail_pattern:(optional_text parameters.detail_pattern)
        ~mode:(transfer_mode parameters.mode parameters.neighbors
          parameters.power parameters.kernel_radius)
        ~max_distance:parameters.max_distance
        ~blend_width:parameters.blend_width
        ~falloff:(transfer_falloff parameters.falloff parameters.uniform_bias)
        ~unmatched:parameters.unmatched ~source ~target ())
  let factory = parameters_factory build
end

module Promote_attributes = struct
  type parameters = {
    source : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Source owner"] [@sop.kind attribute_owner_parameter];
    destination : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Primitive]
      [@sop.label "Destination owner"] [@sop.kind attribute_owner_parameter];
    pattern : string [@sop.default "*"] [@sop.label "Attribute pattern"];
    method_ : Rdk.Attribute_ops.method_ [@sop.default Rdk.Attribute_ops.Average]
      [@sop.label "Promotion method"]
      [@sop.kind attribute_promotion_method_parameter];
    delete_source : bool [@sop.default false] [@sop.label "Delete source"];
    piece_attribute : string [@sop.default ""]
      [@sop.label "Piece attribute"] [@sop.folder "Partition"];
    into_pattern : string [@sop.default ""]
      [@sop.label "Rename pattern"] [@sop.folder "Output"];
    index_pattern : string [@sop.default ""]
      [@sop.label "Index pattern"] [@sop.folder "Output"];
  } [@@sop.node_key "promote_attributes"]
    [@@sop.node_label "Promote Attributes"]
    [@@sop.node_category "Attribute/Promote"] [@@sop.node_inputs 1]
    [@@sop.node_operation "attribute_promote_pattern"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.promote_attributes ~label ~method_:parameters.method_
        ~delete_source:parameters.delete_source
        ?piece_attribute:(optional_text parameters.piece_attribute)
        ?into_pattern:(optional_text parameters.into_pattern)
        ?index_pattern:(optional_text parameters.index_pattern)
        ~source:parameters.source ~destination:parameters.destination
        ~pattern:parameters.pattern input)
  let factory = parameters_factory build
end

module Measure = struct
  let kind_parameter = Parameter.choice ~equal:( = ) [
      "Perimeter", Rdk.Analysis.Perimeter;
      "Area", Rdk.Analysis.Area;
      "Signed volume", Rdk.Analysis.Signed_volume;
    ]
  let accumulation_parameter = Parameter.choice ~equal:( = ) [
      "Per element", Rdk.Analysis.Per_element;
      "Throughout", Rdk.Analysis.Throughout;
    ]
  type parameters = {
    kind : Rdk.Analysis.measure [@sop.default Rdk.Analysis.Area]
      [@sop.label "Measure"] [@sop.kind kind_parameter];
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    accumulation : Rdk.Analysis.accumulation
      [@sop.default Rdk.Analysis.Per_element]
      [@sop.label "Accumulation"] [@sop.kind accumulation_parameter];
    attribute : string [@sop.default ""] [@sop.label "Attribute"]
      [@sop.folder "Output"];
    total_attribute : string [@sop.default ""]
      [@sop.label "Total attribute"] [@sop.folder "Output"];
  } [@@sop.node_key "measure"] [@@sop.node_label "Measure"]
    [@@sop.node_category "Attribute/Analysis"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.measure ~label ?group:(optional_text parameters.group)
      ~accumulation:parameters.accumulation
      ?name:(optional_text parameters.attribute)
      ?total_name:(optional_text parameters.total_attribute)
      parameters.kind input)
  let factory = parameters_factory build
end

module Connectivity = struct
  type output = Integer | Text
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Points", Rdk.Analysis.Connectivity_points;
      "Primitives", Rdk.Analysis.Connectivity_primitives;
    ]
  let output_parameter = Parameter.choice ~equal:( = ) [
      "Integer", Integer; "Text", Text;
    ]
  type parameters = {
    owner : Rdk.Analysis.connectivity_owner
      [@sop.default Rdk.Analysis.Connectivity_primitives]
      [@sop.label "Connectivity type"] [@sop.kind owner_parameter];
    primitive_group : string [@sop.default ""] [@sop.label "Primitive group"]
      [@sop.folder "Selection"];
    point_group : string [@sop.default ""] [@sop.label "Point group"]
      [@sop.folder "Selection"];
    seam_group : string [@sop.default ""] [@sop.label "Seam edge group"]
      [@sop.folder "Seams"];
    uv_attribute : string [@sop.default ""] [@sop.label "UV attribute"]
      [@sop.folder "Seams"];
    name : string [@sop.default "class"] [@sop.label "Attribute"]
      [@sop.folder "Output"];
    output : output [@sop.default Integer] [@sop.label "Storage"]
      [@sop.folder "Output"] [@sop.kind output_parameter];
    text_prefix : string [@sop.default "piece"] [@sop.label "Text prefix"]
      [@sop.folder "Output"];
  } [@@sop.node_key "connectivity"] [@@sop.node_label "Connectivity"]
    [@@sop.node_category "Attribute/Analysis"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let attribute = match parameters.output with
      | Integer -> Rdk.Analysis.Connectivity_integer
      | Text -> Rdk.Analysis.Connectivity_text parameters.text_prefix in
    Sop.connectivity ~label
      ?primitive_group:(optional_text parameters.primitive_group)
      ?point_group:(optional_text parameters.point_group)
      ?seam_group:(optional_text parameters.seam_group)
      ?uv_attribute:(optional_text parameters.uv_attribute)
      ~owner:parameters.owner ?name:(optional_text parameters.name)
      ~attribute input)
  let factory = parameters_factory build
end

module Set_float = struct
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "value"] [@sop.label "Attribute"];
    value : float [@sop.default 0.] [@sop.label "Value"]
      [@sop.min (-10.)] [@sop.max 10.];
  } [@@sop.node_key "set_float"] [@@sop.node_label "Set Float"]
    [@@sop.node_category "Attribute/Set"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.set_float ~label ~owner:parameters.owner
        ~name:parameters.name parameters.value input)
  let factory = parameters_factory build
end

module Set_int = struct
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "value"] [@sop.label "Attribute"];
    value : int [@sop.default 0] [@sop.label "Value"]
      [@sop.min (-100)] [@sop.max 100];
  } [@@sop.node_key "set_int"] [@@sop.node_label "Set Integer"]
    [@@sop.node_category "Attribute/Set"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.set_int ~label ~owner:parameters.owner
        ~name:parameters.name parameters.value input)
  let factory = parameters_factory build
end

module Set_vector = struct
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "v"] [@sop.label "Attribute"];
    x : float [@sop.default 0.] [@sop.label "X"] [@sop.folder "Value"]
      [@sop.min (-10.)] [@sop.max 10.];
    y : float [@sop.default 0.] [@sop.label "Y"] [@sop.folder "Value"]
      [@sop.min (-10.)] [@sop.max 10.];
    z : float [@sop.default 0.] [@sop.label "Z"] [@sop.folder "Value"]
      [@sop.min (-10.)] [@sop.max 10.];
  } [@@sop.node_key "set_vector"] [@@sop.node_label "Set Vector"]
    [@@sop.node_category "Attribute/Set"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.set_vector ~label ~owner:parameters.owner
        ~name:parameters.name (Vec3.create parameters.x parameters.y parameters.z)
        input)
  let factory = parameters_factory build
end

module Set_orient = struct
  type parameters = {
    x : float [@sop.default 0.] [@sop.label "X"] [@sop.min (-1.)]
      [@sop.max 1.];
    y : float [@sop.default 0.] [@sop.label "Y"] [@sop.min (-1.)]
      [@sop.max 1.];
    z : float [@sop.default 0.] [@sop.label "Z"] [@sop.min (-1.)]
      [@sop.max 1.];
    w : float [@sop.default 1.] [@sop.label "W"] [@sop.min (-1.)]
      [@sop.max 1.];
  } [@@sop.node_key "set_orient"] [@@sop.node_label "Set Orient"]
    [@@sop.node_category "Attribute/Set"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.set_orient ~label
        (Quat.create ~x:parameters.x ~y:parameters.y ~z:parameters.z
          ~w:parameters.w) input)
  let factory = parameters_factory build
end

module Set_transform = struct
  type parameters = {
    m00 : float [@sop.default 1.] [@sop.label "M00"]
      [@sop.folder "Matrix/Row 0"] [@sop.min (-10.)] [@sop.max 10.];
    m01 : float [@sop.default 0.] [@sop.label "M01"]
      [@sop.folder "Matrix/Row 0"] [@sop.min (-10.)] [@sop.max 10.];
    m02 : float [@sop.default 0.] [@sop.label "M02"]
      [@sop.folder "Matrix/Row 0"] [@sop.min (-10.)] [@sop.max 10.];
    m03 : float [@sop.default 0.] [@sop.label "M03"]
      [@sop.folder "Matrix/Row 0"] [@sop.min (-10.)] [@sop.max 10.];
    m10 : float [@sop.default 0.] [@sop.label "M10"]
      [@sop.folder "Matrix/Row 1"] [@sop.min (-10.)] [@sop.max 10.];
    m11 : float [@sop.default 1.] [@sop.label "M11"]
      [@sop.folder "Matrix/Row 1"] [@sop.min (-10.)] [@sop.max 10.];
    m12 : float [@sop.default 0.] [@sop.label "M12"]
      [@sop.folder "Matrix/Row 1"] [@sop.min (-10.)] [@sop.max 10.];
    m13 : float [@sop.default 0.] [@sop.label "M13"]
      [@sop.folder "Matrix/Row 1"] [@sop.min (-10.)] [@sop.max 10.];
    m20 : float [@sop.default 0.] [@sop.label "M20"]
      [@sop.folder "Matrix/Row 2"] [@sop.min (-10.)] [@sop.max 10.];
    m21 : float [@sop.default 0.] [@sop.label "M21"]
      [@sop.folder "Matrix/Row 2"] [@sop.min (-10.)] [@sop.max 10.];
    m22 : float [@sop.default 1.] [@sop.label "M22"]
      [@sop.folder "Matrix/Row 2"] [@sop.min (-10.)] [@sop.max 10.];
    m23 : float [@sop.default 0.] [@sop.label "M23"]
      [@sop.folder "Matrix/Row 2"] [@sop.min (-10.)] [@sop.max 10.];
    m30 : float [@sop.default 0.] [@sop.label "M30"]
      [@sop.folder "Matrix/Row 3"] [@sop.min (-10.)] [@sop.max 10.];
    m31 : float [@sop.default 0.] [@sop.label "M31"]
      [@sop.folder "Matrix/Row 3"] [@sop.min (-10.)] [@sop.max 10.];
    m32 : float [@sop.default 0.] [@sop.label "M32"]
      [@sop.folder "Matrix/Row 3"] [@sop.min (-10.)] [@sop.max 10.];
    m33 : float [@sop.default 1.] [@sop.label "M33"]
      [@sop.folder "Matrix/Row 3"] [@sop.min (-10.)] [@sop.max 10.];
  } [@@sop.node_key "set_transform"] [@@sop.node_label "Set Transform"]
    [@@sop.node_category "Attribute/Set"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let matrix parameters = Mat4.of_rows
      (parameters.m00, parameters.m01, parameters.m02, parameters.m03)
      (parameters.m10, parameters.m11, parameters.m12, parameters.m13)
      (parameters.m20, parameters.m21, parameters.m22, parameters.m23)
      (parameters.m30, parameters.m31, parameters.m32, parameters.m33)
  let build = parameters_build (fun ~label parameters input ->
    Sop.set_transform ~label (matrix parameters) input)
  let factory = parameters_factory build
end

module Set_color = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Group"];
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    color_r : float [@sop.default 1.] [@sop.label "Red"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.]
      [@sop.vec3 "color"];
    color_g : float [@sop.default 1.] [@sop.label "Green"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.]
      [@sop.vec3 "color"];
    color_b : float [@sop.default 1.] [@sop.label "Blue"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.]
      [@sop.vec3 "color"];
    alpha : float [@sop.default 1.] [@sop.label "Alpha"] [@sop.min 0.]
      [@sop.max 1.] [@sop.hard_min 0.] [@sop.hard_max 1.];
  } [@@sop.node_key "set_color"] [@@sop.node_label "Set Color"]
    [@@sop.node_category "Attribute/Set"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    Sop.set_color_float ~label ?group:(optional_text parameters.group)
      ~owner:parameters.owner
      ~color:(Vec3.create parameters.color_r parameters.color_g parameters.color_b)
      ~alpha:parameters.alpha input)
  let factory = parameters_factory build
end

module Rest_position = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Store", Rdk.Motion.Store_rest; "Extract", Rdk.Motion.Extract_rest;
      "Swap", Rdk.Motion.Swap_rest;
    ]
  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Motion.No_rest_normals;
      "If present", Rdk.Motion.Rest_normals_if_present;
      "Always", Rdk.Motion.Rest_normals_always;
    ]
  type parameters = {
    mode : Rdk.Motion.rest_mode [@sop.default Rdk.Motion.Store_rest]
      [@sop.label "Mode"] [@sop.kind mode_parameter];
    rest_attribute : string [@sop.default "rest"] [@sop.label "Rest position"]
      [@sop.folder "Attributes"];
    normals : Rdk.Motion.rest_normals [@sop.default Rdk.Motion.No_rest_normals]
      [@sop.label "Rest normals"] [@sop.kind normals_parameter];
    normal_attribute : string [@sop.default "N"] [@sop.label "Normal"]
      [@sop.folder "Attributes"];
    rest_normal_attribute : string [@sop.default "restN"]
      [@sop.label "Rest normal"] [@sop.folder "Attributes"];
  } [@@sop.node_key "rest_position"] [@@sop.node_label "Rest Position"]
    [@@sop.node_category "Attribute/Motion"] [@@sop.node_inputs 2] [@@sop.node_slots "input, reference"]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input reference ->
    let inputs, cook_mode = match reference with
      | None -> [|input|], Node.Duplicate_input 0
      | Some reference -> [|input; reference|], Node.Generic in
    operator ~label ~operation:"rest_position" ~cook_mode inputs
      (fun ~node_id:_ context inputs ->
        let reference = if Array.length inputs = 2 then Some inputs.(1) else None in
        rdk_cooked (Rdk.Motion.rest_position ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?reference
          ~rest_attribute:parameters.rest_attribute ~normals:parameters.normals
          ~normal_attribute:parameters.normal_attribute
          ~rest_normal_attribute:parameters.rest_normal_attribute
          parameters.mode inputs.(0))))

  let factory = parameters_factory build
end

module Enumerate = struct
  type storage = Integer | Text
  let storage_parameter = Parameter.choice ~equal:( = ) [
      "Integer", Integer; "Text", Text;
    ]
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Elements within pieces", Rdk.Attribute_ops.Enumerate_piece_elements;
      "Pieces", Rdk.Attribute_ops.Enumerate_pieces;
    ]
  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind element_attribute_owner_parameter];
    name : string [@sop.default "id"] [@sop.label "Attribute"];
    group : string [@sop.default ""] [@sop.label "Group"];
    start : int [@sop.default 0] [@sop.label "Start"]
      [@sop.folder "Sequence"] [@sop.min (-100)] [@sop.max 100];
    step : int [@sop.default 1] [@sop.label "Step"]
      [@sop.folder "Sequence"] [@sop.min (-20)] [@sop.max 20];
    storage : storage [@sop.default Integer] [@sop.label "Storage"]
      [@sop.folder "Output"] [@sop.kind storage_parameter];
    prefix : string [@sop.default "piece"] [@sop.label "Text prefix"]
      [@sop.folder "Output"];
    piece_attribute : string [@sop.default ""] [@sop.label "Piece attribute"]
      [@sop.folder "Pieces"];
    mode : Rdk.Attribute_ops.enumeration_mode
      [@sop.default Rdk.Attribute_ops.Enumerate_piece_elements]
      [@sop.label "Piece mode"] [@sop.folder "Pieces"]
      [@sop.kind mode_parameter];
  } [@@sop.node_key "enumerate"] [@@sop.node_label "Enumerate"]
    [@@sop.node_category "Attribute/Generate"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let storage = match parameters.storage with
      | Integer -> Rdk.Attribute_ops.Integer
      | Text -> Rdk.Attribute_ops.Text { prefix = parameters.prefix } in
    Sop.enumerate ~label ?group:(optional_text parameters.group)
      ~start:parameters.start ~step:parameters.step ~storage
      ?piece_attribute:(optional_text parameters.piece_attribute)
      ~mode:parameters.mode ~owner:parameters.owner ~name:parameters.name
      input)
  let factory = parameters_factory build
end

module Attribute_blur = struct
  type mode = Laplacian | Custom
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Uniform", Rdk.Attribute_ops.Uniform;
      "Edge length", Rdk.Attribute_ops.Edge_length;
    ]
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Laplacian", Laplacian; "Custom steps", Custom;
    ]
  type parameters = {
    attributes : string [@sop.default "P"] [@sop.label "Attributes"];
    group : string [@sop.default ""] [@sop.label "Point group"];
    iterations : int [@sop.default 1] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 100] [@sop.hard_min 0];
    method_ : Rdk.Attribute_ops.blur_method
      [@sop.default Rdk.Attribute_ops.Uniform]
      [@sop.label "Method"] [@sop.kind method_parameter];
    mode : mode [@sop.default Laplacian] [@sop.label "Mode"]
      [@sop.folder "Step"] [@sop.kind mode_parameter];
    laplacian_step : float [@sop.default 0.5] [@sop.label "Step"]
      [@sop.folder "Step"] [@sop.min (-1.)] [@sop.max 1.];
    odd_step : float [@sop.default 0.5] [@sop.label "Odd step"]
      [@sop.folder "Step/Custom"] [@sop.min (-1.)] [@sop.max 1.];
    even_step : float [@sop.default (-0.51)] [@sop.label "Even step"]
      [@sop.folder "Step/Custom"] [@sop.min (-1.)] [@sop.max 1.];
    weight_attribute : string [@sop.default ""] [@sop.label "Weight attribute"]
      [@sop.folder "Mask"];
    alpha_attribute : string [@sop.default ""] [@sop.label "Alpha attribute"]
      [@sop.folder "Mask"];
    pin_borders : bool [@sop.default false] [@sop.label "Pin borders"];
    original_blend : float [@sop.default 0.] [@sop.label "Original blend"]
      [@sop.folder "Blend"] [@sop.min 0.] [@sop.max 1.];
    blurred_blend : float [@sop.default 1.] [@sop.label "Blurred blend"]
      [@sop.folder "Blend"] [@sop.min 0.] [@sop.max 1.];
  } [@@sop.node_key "attribute_blur"] [@@sop.node_label "Attribute Blur"]
    [@@sop.node_category "Attribute/Filter"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let mode = match parameters.mode with
      | Laplacian -> Rdk.Attribute_ops.Laplacian parameters.laplacian_step
      | Custom -> Rdk.Attribute_ops.Custom_steps {
          odd = parameters.odd_step; even = parameters.even_step } in
    Sop.attribute_blur ~label ?group:(optional_text parameters.group)
      ~iterations:parameters.iterations ~method_:parameters.method_ ~mode
      ?weight_attribute:(optional_text parameters.weight_attribute)
      ?alpha_attribute:(optional_text parameters.alpha_attribute)
      ~pin_borders:parameters.pin_borders
      ~original_blend:parameters.original_blend
      ~blurred_blend:parameters.blurred_blend
      ~attributes:parameters.attributes input)
  let factory = parameters_factory build
end

(* A render camera: parameters only, cooking to empty geometry.
   ponytail: no frustum gizmo in the viewport; add a wireframe overlay if asked. *)
module Normal = struct
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Point", Rdk.Attribute.Point;
      "Vertex", Rdk.Attribute.Vertex;
    ]

  let weighting_parameter = Parameter.choice ~equal:( = ) [
      "Vertex angle", Rdk.Normal_ops.Vertex_angle;
      "Each vertex", Rdk.Normal_ops.Each_vertex;
      "Face area", Rdk.Normal_ops.Face_area;
    ]

  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Vertex]
      [@sop.label "Add normals to"] [@sop.kind owner_parameter];
    weighting : Rdk.Normal_ops.weighting
      [@sop.default Rdk.Normal_ops.Vertex_angle]
      [@sop.label "Weighting"] [@sop.kind weighting_parameter];
    cusp_angle : float [@sop.default 3.141592653589793]
      [@sop.label "Cusp angle"] [@sop.min 0.] [@sop.max 3.141592653589793]
      [@sop.hard_min 0.] [@sop.hard_max 3.141592653589793];
    keep_original_zero : bool [@sop.default false]
      [@sop.label "Keep original zero normals"];
    reverse : bool [@sop.default false] [@sop.label "Reverse normals"];
    attribute : string [@sop.default "N"] [@sop.label "Attribute"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "normals"] [@@sop.node_label "Normal"]
    [@@sop.node_category "Attribute"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.normals ~label ~owner:parameters.owner
      ~weighting:parameters.weighting ~cusp_angle:parameters.cusp_angle
      ~keep_original_zero:parameters.keep_original_zero
      ~reverse:parameters.reverse ~attribute:parameters.attribute input)

  let factory = parameters_factory build

  let create ?label:node_label ?(owner = Rdk.Attribute.Vertex)
      ?(weighting = Rdk.Normal_ops.Vertex_angle) ?(cusp_angle = Float.pi)
      ?(keep_original_zero = false) ?(reverse = false) ?(attribute = "N")
      input =
    build ~label:(label "normal" node_label) ~inputs:[input] {
      owner; weighting; cusp_angle; keep_original_zero; reverse; attribute }
end
