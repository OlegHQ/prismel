open Prismel
open Procedural

let label fallback = function Some label -> label | None -> fallback

let optional_text value =
  let value = String.trim value in
  if value = "" then None else Some value

let encode_table rows =
  let encode_cell value =
    let buffer = Buffer.create (String.length value) in
    String.iter (function
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\t' -> Buffer.add_string buffer "\\t"
      | '\n' -> Buffer.add_string buffer "\\n"
      | character -> Buffer.add_char buffer character) value;
    Buffer.contents buffer in
  rows |> List.map (fun row -> String.concat "\t" (List.map encode_cell row))
       |> String.concat "\n"

let decode_table text =
  if text = "" then Ok [] else
  let rows = ref [] and row = ref [] and cell = Buffer.create 32 in
  let finish_cell () =
    row := Buffer.contents cell :: !row;
    Buffer.clear cell in
  let finish_row () = finish_cell (); rows := List.rev !row :: !rows; row := [] in
  let escaped = ref false and error = ref None in
  String.iter (fun character -> if Option.is_none !error then
    if !escaped then begin
      escaped := false;
      match character with
      | '\\' -> Buffer.add_char cell '\\'
      | 't' -> Buffer.add_char cell '\t'
      | 'n' -> Buffer.add_char cell '\n'
      | character -> error := Some (Printf.sprintf
          "unsupported table escape \\%c" character)
    end else match character with
      | '\\' -> escaped := true
      | '\t' -> finish_cell ()
      | '\n' -> finish_row ()
      | character -> Buffer.add_char cell character) text;
  match !error with
  | Some error -> Error error
  | None when !escaped -> Error "trailing table escape"
  | None -> finish_row (); Ok (List.rev !rows)

let bool_token value = if value then "true" else "false"
let bool_of_token value = match String.lowercase_ascii (String.trim value) with
  | "true" | "1" | "yes" -> Ok true
  | "false" | "0" | "no" -> Ok false
  | token -> Error (Printf.sprintf "expected boolean, got %S" token)
let int_of_token value = match int_of_string_opt (String.trim value) with
  | Some value -> Ok value
  | None -> Error (Printf.sprintf "expected integer, got %S" value)
let float_of_token value = match float_of_string_opt (String.trim value) with
  | Some value when Float.is_finite value -> Ok value
  | Some _ | None -> Error (Printf.sprintf "expected finite float, got %S" value)

type element_owner = Element_point | Element_vertex
  | Element_primitive | Element_edge

let element_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Element_point; "Vertex", Element_vertex;
    "Primitive", Element_primitive; "Edge", Element_edge;
  ]

let optional_element_group owner name = match optional_text name with
  | None -> None
  | Some name -> Some (match owner with
      | Element_point -> Sop.Point_group name
      | Element_vertex -> Sop.Vertex_group name
      | Element_primitive -> Sop.Primitive_group name
      | Element_edge -> Sop.Edge_group name)

let attribute_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Pdk.Attribute.Point; "Vertex", Pdk.Attribute.Vertex;
    "Primitive", Pdk.Attribute.Primitive; "Detail", Pdk.Attribute.Detail;
  ]

let attribute_owner_token = function
  | Pdk.Attribute.Point -> "point"
  | Pdk.Attribute.Vertex -> "vertex"
  | Pdk.Attribute.Primitive -> "primitive"
  | Pdk.Attribute.Detail -> "detail"

let attribute_owner_of_token = function
  | "point" | "points" -> Ok Pdk.Attribute.Point
  | "vertex" | "vertices" -> Ok Pdk.Attribute.Vertex
  | "primitive" | "primitives" -> Ok Pdk.Attribute.Primitive
  | "detail" -> Ok Pdk.Attribute.Detail
  | token -> Error (Printf.sprintf "unknown attribute owner %S" token)

let encode_boundary_attributes attributes = encode_table (List.map
    (fun (attribute : Pdk.Ops.group_boundary_attribute) ->
      [attribute_owner_token attribute.boundary_attribute_owner;
       attribute.boundary_attribute_pattern]) attributes)

let decode_boundary_attributes text = Result.bind (decode_table text) (fun rows ->
    List.fold_left (fun result row -> Result.bind result (fun attributes ->
      match row with
      | [owner; pattern] -> Result.map (fun boundary_attribute_owner ->
          { Pdk.Ops.boundary_attribute_owner;
            boundary_attribute_pattern = pattern } :: attributes)
          (attribute_owner_of_token
            (String.lowercase_ascii (String.trim owner)))
      | row -> Error (Printf.sprintf
          "boundary attribute needs owner and pattern, got %d columns"
          (List.length row)))) (Ok []) rows |> Result.map List.rev)

let boundary_attributes_parameter = Parameter.encoded ~equal:( = )
    ~encode:encode_boundary_attributes ~decode:decode_boundary_attributes

let element_attribute_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Pdk.Attribute.Point; "Vertex", Pdk.Attribute.Vertex;
    "Primitive", Pdk.Attribute.Primitive;
  ]

let uv_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Pdk.Attribute.Point; "Vertex", Pdk.Attribute.Vertex;
  ]

let group_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Pdk.Ops.Group_points; "Vertices", Pdk.Ops.Group_vertices;
    "Primitives", Pdk.Ops.Group_primitives; "Edges", Pdk.Ops.Group_edges;
  ]

let group_owner_token = function
  | Pdk.Ops.Group_points -> "point"
  | Pdk.Ops.Group_vertices -> "vertex"
  | Pdk.Ops.Group_primitives -> "primitive"
  | Pdk.Ops.Group_edges -> "edge"

let group_owner_of_token = function
  | "point" | "points" -> Ok Pdk.Ops.Group_points
  | "vertex" | "vertices" -> Ok Pdk.Ops.Group_vertices
  | "primitive" | "primitives" -> Ok Pdk.Ops.Group_primitives
  | "edge" | "edges" -> Ok Pdk.Ops.Group_edges
  | token -> Error (Printf.sprintf "unknown group owner %S" token)

let ordinary_group_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Pdk.Group.Point; "Vertices", Pdk.Group.Vertex;
    "Primitives", Pdk.Group.Primitive;
  ]

let group_normal_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Pdk.Ops.Group_points; "Primitives", Pdk.Ops.Group_primitives;
    "Edges", Pdk.Ops.Group_edges;
  ]

let group_merge_parameter = Parameter.choice ~equal:( = ) [
    "Replace", Pdk.Ops.Group_replace; "Union", Pdk.Ops.Group_union;
    "Intersection", Pdk.Ops.Group_intersection;
    "Subtract", Pdk.Ops.Group_subtract; "Exclusive or", Pdk.Ops.Group_xor;
  ]

let group_boolean_token = function
  | Pdk.Ops.Group_replace -> "replace"
  | Pdk.Ops.Group_union -> "union"
  | Pdk.Ops.Group_intersection -> "intersection"
  | Pdk.Ops.Group_subtract -> "subtract"
  | Pdk.Ops.Group_xor -> "xor"

let group_boolean_of_token = function
  | "replace" -> Ok Pdk.Ops.Group_replace
  | "union" -> Ok Pdk.Ops.Group_union
  | "intersection" -> Ok Pdk.Ops.Group_intersection
  | "subtract" -> Ok Pdk.Ops.Group_subtract
  | "xor" -> Ok Pdk.Ops.Group_xor
  | token -> Error (Printf.sprintf "unknown group operation %S" token)

let attribute_promotion_method_parameter = Parameter.choice ~equal:( = ) [
    "First", Pdk.Attribute_ops.First;
    "Last", Pdk.Attribute_ops.Last;
    "Average", Pdk.Attribute_ops.Average;
    "Minimum", Pdk.Attribute_ops.Minimum;
    "Maximum", Pdk.Attribute_ops.Maximum;
    "Mode", Pdk.Attribute_ops.Mode;
    "Median", Pdk.Attribute_ops.Median;
    "Sum", Pdk.Attribute_ops.Sum;
    "Sum of squares", Pdk.Attribute_ops.Sum_squares;
    "Root mean square", Pdk.Attribute_ops.Root_mean_square;
    "Array of all", Pdk.Attribute_ops.Array_all;
    "Unique values", Pdk.Attribute_ops.Unique_values;
  ]

let group_promote_mode_parameter = Parameter.choice ~equal:( = ) [
    "Include any", Pdk.Ops.Include_any;
    "Include all", Pdk.Ops.Include_all;
    "Include shared edge", Pdk.Ops.Include_shared_edge;
  ]

let group_rename_conflict_parameter = Parameter.choice ~equal:( = ) [
    "Skip", Pdk.Ops.Rename_skip; "Error", Pdk.Ops.Rename_error;
    "Overwrite", Pdk.Ops.Rename_overwrite; "Union", Pdk.Ops.Rename_union;
  ]

let delete_topology_policy_parameter = Parameter.choice ~equal:( = ) [
    "Destroy touched primitives", Pdk.Ops.Destroy_touched_primitives;
    "Heal primitives", Pdk.Ops.Heal_primitives;
  ]

let group_copy_conflict_parameter = Parameter.choice ~equal:( = ) [
    "Skip", Pdk.Ops.Copy_skip; "Overwrite", Pdk.Ops.Copy_overwrite;
    "Add suffix", Pdk.Ops.Copy_add_suffix;
  ]

let edge_transport_direction_parameter = Parameter.choice ~equal:( = ) [
    "Forward", Pdk.Ops.Transport_forward;
    "Backward", Pdk.Ops.Transport_backward;
  ]

let edge_transport_operation_parameter = Parameter.choice ~equal:( = ) [
    "Transport", Pdk.Ops.Transport;
    "From root", Pdk.Ops.Transport_from_root;
    "Total", Pdk.Ops.Transport_total;
    "Maximum", Pdk.Ops.Transport_maximum;
    "Minimum", Pdk.Ops.Transport_minimum;
  ]

let edge_transport_root_value_parameter = Parameter.choice ~equal:( = ) [
    "Zero", Pdk.Ops.Transport_root_zero;
    "Hold", Pdk.Ops.Transport_root_hold;
  ]

let edge_transport_normalization_parameter = Parameter.choice ~equal:( = ) [
    "None", Pdk.Ops.Transport_no_normalization;
    "Per component", Pdk.Ops.Transport_normalize_components;
    "Global", Pdk.Ops.Transport_normalize_global;
  ]

let edge_transport_split_parameter = Parameter.choice ~equal:( = ) [
    "Copy", Pdk.Ops.Transport_copy; "Split", Pdk.Ops.Transport_split;
  ]

let edge_transport_merge_parameter = Parameter.choice ~equal:( = ) [
    "Add", Pdk.Ops.Transport_merge_add;
    "Maximum", Pdk.Ops.Transport_merge_maximum;
    "Minimum", Pdk.Ops.Transport_merge_minimum;
  ]

type numeric_kind = Numeric_scalar | Numeric_vec2 | Numeric_vec3 | Numeric_vec4
let numeric_kind_parameter = Parameter.choice ~equal:( = ) [
    "Scalar", Numeric_scalar; "Vector 2", Numeric_vec2;
    "Vector 3", Numeric_vec3; "Vector 4", Numeric_vec4;
  ]
let numeric_value kind x y z w = match kind with
  | Numeric_scalar -> Pdk.Attribute_ops.Scalar x
  | Numeric_vec2 -> Pdk.Attribute_ops.Vec2 (Vec2.create x y)
  | Numeric_vec3 -> Pdk.Attribute_ops.Vec3 (Vec3.create x y z)
  | Numeric_vec4 -> Pdk.Attribute_ops.Vec4 (x, y, z, w)

let soft_falloff_parameter = Parameter.choice ~equal:( = ) [
    "Linear", Pdk.Ops.Soft_linear; "Quadratic", Pdk.Ops.Soft_quadratic;
    "Cubic", Pdk.Ops.Soft_cubic;
  ]

type distance_radius_mode = Radius_fixed | Radius_maximum
let distance_radius_parameter = Parameter.choice ~equal:( = ) [
    "Fixed", Radius_fixed; "Maximum distance", Radius_maximum;
  ]
let distance_radius mode value = match mode with
  | Radius_fixed -> Pdk.Ops.Distance_fixed value
  | Radius_maximum -> Pdk.Ops.Distance_maximum

module Box = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Pdk.Ops.Box_triangles;
      "Quads", Pdk.Ops.Box_quads;
      "Surface points", Pdk.Ops.Box_surface_points;
      "Lattice points", Pdk.Ops.Box_lattice_points;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Pdk.Ops.Box_no_normals;
      "Point", Pdk.Ops.Box_point_normals;
      "Vertex", Pdk.Ops.Box_vertex_normals;
    ]

  let rotation_order_parameter = Parameter.choice ~equal:( = ) [
      "XYZ", Pdk.Ops.Box_xyz; "XZY", Pdk.Ops.Box_xzy;
      "YXZ", Pdk.Ops.Box_yxz; "YZX", Pdk.Ops.Box_yzx;
      "ZXY", Pdk.Ops.Box_zxy; "ZYX", Pdk.Ops.Box_zyx;
    ]

  type parameters = {
    connectivity : Pdk.Ops.box_connectivity
      [@sop.default Pdk.Ops.Box_quads]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    normals : Pdk.Ops.box_normals [@sop.default Pdk.Ops.Box_vertex_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    size_x : float [@sop.default 1.] [@sop.label "Size X"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.];
    size_y : float [@sop.default 1.] [@sop.label "Size Y"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.];
    size_z : float [@sop.default 1.] [@sop.label "Size Z"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.];
    x_divisions : int [@sop.default 1] [@sop.label "X divisions"]
      [@sop.folder "Divisions"] [@sop.min 1] [@sop.max 24] [@sop.hard_min 1];
    y_divisions : int [@sop.default 1] [@sop.label "Y divisions"]
      [@sop.folder "Divisions"] [@sop.min 1] [@sop.max 24] [@sop.hard_min 1];
    z_divisions : int [@sop.default 1] [@sop.label "Z divisions"]
      [@sop.folder "Divisions"] [@sop.min 1] [@sop.max 24] [@sop.hard_min 1];
    consolidate_points : bool [@sop.default false]
      [@sop.label "Consolidate points"] [@sop.folder "Topology"];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_order : Pdk.Ops.box_rotation_order
      [@sop.default Pdk.Ops.Box_xyz]
      [@sop.label "Rotation order"] [@sop.folder "Transform/Rotate"]
      [@sop.kind rotation_order_parameter];
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Transform"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    uv_attribute : string [@sop.default ""] [@sop.label "UV attribute"]
      [@sop.folder "Attributes"];
    face_groups : string [@sop.default ""] [@sop.label "Face group prefix"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "box"] [@@sop.node_label "Box"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs:_ parameters =
    Sop.box ~label ~size:(Vec3.create parameters.size_x parameters.size_y
      parameters.size_z) ~connectivity:parameters.connectivity
      ~consolidate_points:parameters.consolidate_points
      ~normals:parameters.normals
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z)
      ~rotation:(Vec3.create parameters.rotation_x parameters.rotation_y
        parameters.rotation_z) ~rotation_order:parameters.rotation_order
      ~uniform_scale:parameters.uniform_scale
      ~x_divisions:parameters.x_divisions ~y_divisions:parameters.y_divisions
      ~z_divisions:parameters.z_divisions
      ?uv_attribute:(optional_text parameters.uv_attribute)
      ?face_groups:(optional_text parameters.face_groups) ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build

  let create ?label:node_label ?(size = Vec3.create 1. 1. 1.)
      ?(connectivity = Pdk.Ops.Box_triangles) ?(consolidate_points = false)
      ?normals ?(center = Vec3.zero) ?(rotation = Vec3.zero)
      ?(rotation_order = Pdk.Ops.Box_xyz) ?(uniform_scale = 1.)
      ?(x_divisions = 1) ?(y_divisions = 1) ?(z_divisions = 1)
      ?(uv_attribute = "") ?(face_groups = "") () =
    let normals = match normals, connectivity with
      | Some normals, _ -> normals
      | None, (Pdk.Ops.Box_triangles | Box_quads) -> Pdk.Ops.Box_point_normals
      | None, (Box_surface_points | Box_lattice_points) -> Box_no_normals in
    build ~label:(label "box" node_label) ~inputs:[] {
      connectivity; normals;
      size_x = size.x; size_y = size.y; size_z = size.z;
      x_divisions; y_divisions; z_divisions; consolidate_points;
      center_x = center.x; center_y = center.y; center_z = center.z;
      rotation_x = rotation.x; rotation_y = rotation.y;
      rotation_z = rotation.z; rotation_order; uniform_scale;
      uv_attribute; face_groups }
end [@@sop.register]

module Platonic = struct
  type orientation_mode = Axis_x | Axis_y | Axis_z | Axis_custom

  let kind_parameter = Parameter.choice ~equal:( = ) [
      "Tetrahedron", Pdk.Ops.Platonic_tetrahedron;
      "Cube", Pdk.Ops.Platonic_cube;
      "Octahedron", Pdk.Ops.Platonic_octahedron;
      "Icosahedron", Pdk.Ops.Platonic_icosahedron;
      "Dodecahedron", Pdk.Ops.Platonic_dodecahedron;
      "Soccer ball", Pdk.Ops.Platonic_soccer_ball;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Pdk.Ops.Platonic_no_normals;
      "Point", Pdk.Ops.Platonic_point_normals;
      "Vertex", Pdk.Ops.Platonic_vertex_normals;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Axis_x; "Y axis", Axis_y; "Z axis", Axis_z;
      "Custom axis", Axis_custom;
    ]

  let rotation_order_parameter = Parameter.choice ~equal:( = ) [
      "XYZ", Pdk.Ops.Platonic_xyz; "XZY", Pdk.Ops.Platonic_xzy;
      "YXZ", Pdk.Ops.Platonic_yxz; "YZX", Pdk.Ops.Platonic_yzx;
      "ZXY", Pdk.Ops.Platonic_zxy; "ZYX", Pdk.Ops.Platonic_zyx;
    ]

  type parameters = {
    kind : Pdk.Ops.platonic_kind
      [@sop.default Pdk.Ops.Platonic_dodecahedron]
      [@sop.label "Type"] [@sop.kind kind_parameter];
    normals : Pdk.Ops.platonic_normals
      [@sop.default Pdk.Ops.Platonic_vertex_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    radius : float [@sop.default 1.] [@sop.label "Radius"]
      [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.];
    orientation : orientation_mode [@sop.default Axis_y]
      [@sop.label "Orientation"] [@sop.folder "Transform"]
      [@sop.kind orientation_parameter];
    axis_x : float [@sop.default 0.] [@sop.label "Axis X"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.];
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.];
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_order : Pdk.Ops.platonic_rotation_order
      [@sop.default Pdk.Ops.Platonic_xyz]
      [@sop.label "Rotation order"] [@sop.folder "Transform/Rotate"]
      [@sop.kind rotation_order_parameter];
    face_groups : string [@sop.default ""] [@sop.label "Face group prefix"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "platonic"] [@@sop.node_label "Platonic Solid"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let pdk_orientation parameters = match parameters.orientation with
    | Axis_x -> Pdk.Ops.Platonic_x
    | Axis_y -> Pdk.Ops.Platonic_y
    | Axis_z -> Pdk.Ops.Platonic_z
    | Axis_custom -> Pdk.Ops.Platonic_axis (Vec3.create parameters.axis_x
        parameters.axis_y parameters.axis_z)

  let rec build ~label ~inputs:_ parameters =
    Sop.platonic ~label ~kind:parameters.kind ~normals:parameters.normals
      ~orientation:(pdk_orientation parameters)
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z)
      ~rotation:(Vec3.create parameters.rotation_x parameters.rotation_y
        parameters.rotation_z) ~rotation_order:parameters.rotation_order
      ?face_groups:(optional_text parameters.face_groups)
      ~radius:parameters.radius ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build

  let create ?label:node_label ?(kind = Pdk.Ops.Platonic_tetrahedron)
      ?(normals = Pdk.Ops.Platonic_no_normals)
      ?(orientation = Pdk.Ops.Platonic_y) ?(center = Vec3.zero)
      ?(rotation = Vec3.zero) ?(rotation_order = Pdk.Ops.Platonic_xyz)
      ?(face_groups = "") ~radius () =
    let orientation, axis = match orientation with
      | Pdk.Ops.Platonic_x -> Axis_x, Vec3.create 1. 0. 0.
      | Pdk.Ops.Platonic_y -> Axis_y, Vec3.create 0. 1. 0.
      | Pdk.Ops.Platonic_z -> Axis_z, Vec3.create 0. 0. 1.
      | Pdk.Ops.Platonic_axis axis -> Axis_custom, axis in
    build ~label:(label "platonic" node_label) ~inputs:[] {
      kind; normals; radius; orientation;
      axis_x = axis.x; axis_y = axis.y; axis_z = axis.z;
      center_x = center.x; center_y = center.y; center_z = center.z;
      rotation_x = rotation.x; rotation_y = rotation.y;
      rotation_z = rotation.z; rotation_order; face_groups }
end [@@sop.register]

module Spiral = struct
  type extent_mode = Turns_height | Height_pitch
  type radius_mode = Archimedean_change | Archimedean_end
    | Logarithmic_change | Logarithmic_end
  type divisions_mode = Per_curve | Per_turn
  type orientation_mode = Axis_x | Axis_y | Axis_z | Axis_custom

  let extent_parameter = Parameter.choice ~equal:( = ) [
      "Turns and height", Turns_height; "Height and pitch", Height_pitch;
    ]
  let radius_parameter = Parameter.choice ~equal:( = ) [
      "Archimedean change", Archimedean_change;
      "Archimedean end", Archimedean_end;
      "Logarithmic change", Logarithmic_change;
      "Logarithmic end", Logarithmic_end;
    ]
  let direction_parameter = Parameter.choice ~equal:( = ) [
      "Counterclockwise", Pdk.Ops.Spiral_counterclockwise;
      "Clockwise", Pdk.Ops.Spiral_clockwise;
    ]
  let divisions_parameter = Parameter.choice ~equal:( = ) [
      "Per curve", Per_curve; "Per turn", Per_turn;
    ]
  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Axis_x; "Y axis", Axis_y; "Z axis", Axis_z;
      "Custom axis", Axis_custom;
    ]
  let rotation_order_parameter = Parameter.choice ~equal:( = ) [
      "XYZ", Pdk.Ops.Spiral_xyz; "XZY", Pdk.Ops.Spiral_xzy;
      "YXZ", Pdk.Ops.Spiral_yxz; "YZX", Pdk.Ops.Spiral_yzx;
      "ZXY", Pdk.Ops.Spiral_zxy; "ZYX", Pdk.Ops.Spiral_zyx;
    ]

  type parameters = {
    extent_mode : extent_mode [@sop.default Turns_height]
      [@sop.label "Extent"] [@sop.kind extent_parameter];
    turns : float [@sop.default 3.] [@sop.label "Turns"]
      [@sop.folder "Extent"] [@sop.min 0.01] [@sop.max 20.]
      [@sop.hard_min 0.];
    height : float [@sop.default 2.] [@sop.label "Height"]
      [@sop.folder "Extent"] [@sop.min (-20.)] [@sop.max 20.];
    pitch : float [@sop.default 0.6666666666666666] [@sop.label "Pitch"]
      [@sop.folder "Extent"] [@sop.min (-10.)] [@sop.max 10.];
    radius_mode : radius_mode [@sop.default Archimedean_change]
      [@sop.label "Radius model"] [@sop.kind radius_parameter];
    start_radius : float [@sop.default 1.] [@sop.label "Start radius"]
      [@sop.folder "Radius"] [@sop.min 0.001] [@sop.max 10.]
      [@sop.hard_min 0.];
    radius_change : float [@sop.default 0.] [@sop.label "Increase per turn"]
      [@sop.folder "Radius"] [@sop.min (-5.)] [@sop.max 5.];
    end_radius : float [@sop.default 1.] [@sop.label "End radius"]
      [@sop.folder "Radius"] [@sop.min 0.001] [@sop.max 10.]
      [@sop.hard_min 0.];
    logarithmic_scale : float [@sop.default 1.]
      [@sop.label "Scale per turn"] [@sop.folder "Radius"]
      [@sop.min 0.01] [@sop.max 4.] [@sop.hard_min 0.];
    radius_scale : float [@sop.default 1.] [@sop.label "Radius scale"]
      [@sop.folder "Radius"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    direction : Pdk.Ops.spiral_direction
      [@sop.default Pdk.Ops.Spiral_counterclockwise]
      [@sop.label "Direction"] [@sop.kind direction_parameter];
    start_angle : float [@sop.default 0.] [@sop.label "Start angle"]
      [@sop.min (-6.283185307179586)] [@sop.max 6.283185307179586];
    divisions_mode : divisions_mode [@sop.default Per_turn]
      [@sop.label "Divisions"] [@sop.kind divisions_parameter];
    divisions : int [@sop.default 32] [@sop.label "Division count"]
      [@sop.min 2] [@sop.max 512] [@sop.hard_min 1];
    uniform_angle : bool [@sop.default true] [@sop.label "Uniform angle"];
    spiral_count : int [@sop.default 1] [@sop.label "Spiral count"]
      [@sop.min 1] [@sop.max 64] [@sop.hard_min 1];
    orientation : orientation_mode [@sop.default Axis_y]
      [@sop.label "Orientation"] [@sop.folder "Transform"]
      [@sop.kind orientation_parameter];
    axis_x : float [@sop.default 0.] [@sop.label "Axis X"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.];
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.];
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_order : Pdk.Ops.spiral_rotation_order
      [@sop.default Pdk.Ops.Spiral_xyz]
      [@sop.label "Rotation order"] [@sop.folder "Transform/Rotate"]
      [@sop.kind rotation_order_parameter];
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Transform"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    angle_attribute : string [@sop.default ""] [@sop.label "Angle"]
      [@sop.folder "Attributes"];
    x_axis_attribute : string [@sop.default ""] [@sop.label "X axis"]
      [@sop.folder "Attributes"];
    y_axis_attribute : string [@sop.default ""] [@sop.label "Y axis"]
      [@sop.folder "Attributes"];
    tangent_attribute : string [@sop.default ""] [@sop.label "Tangent"]
      [@sop.folder "Attributes"];
    orient_attribute : string [@sop.default ""] [@sop.label "Orient"]
      [@sop.folder "Attributes"];
    distance_attribute : string [@sop.default ""] [@sop.label "Distance"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "spiral"] [@@sop.node_label "Spiral"]
    [@@sop.node_category "Create/Curve"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let extent parameters = match parameters.extent_mode with
    | Turns_height -> Pdk.Ops.Spiral_turns {
        turns = parameters.turns; height = parameters.height }
    | Height_pitch -> Pdk.Ops.Spiral_height_pitch {
        height = parameters.height; pitch = parameters.pitch }

  let radius parameters = match parameters.radius_mode with
    | Archimedean_change -> Pdk.Ops.Spiral_archimedean_change {
        start_radius = parameters.start_radius;
        increase_per_turn = parameters.radius_change }
    | Archimedean_end -> Pdk.Ops.Spiral_archimedean_end {
        start_radius = parameters.start_radius; end_radius = parameters.end_radius }
    | Logarithmic_change -> Pdk.Ops.Spiral_logarithmic_change {
        start_radius = parameters.start_radius;
        scale_per_turn = parameters.logarithmic_scale }
    | Logarithmic_end -> Pdk.Ops.Spiral_logarithmic_end {
        start_radius = parameters.start_radius; end_radius = parameters.end_radius }

  let divisions parameters = match parameters.divisions_mode with
    | Per_curve -> Pdk.Ops.Spiral_divisions_per_curve parameters.divisions
    | Per_turn -> Pdk.Ops.Spiral_divisions_per_turn parameters.divisions

  let orientation parameters = match parameters.orientation with
    | Axis_x -> Pdk.Ops.Spiral_x
    | Axis_y -> Pdk.Ops.Spiral_y
    | Axis_z -> Pdk.Ops.Spiral_z
    | Axis_custom -> Pdk.Ops.Spiral_axis (Vec3.create parameters.axis_x
        parameters.axis_y parameters.axis_z)

  let rec build ~label ~inputs:_ parameters =
    Sop.spiral ~label ~extent:(extent parameters) ~radius:(radius parameters)
      ~radius_scale:parameters.radius_scale ~direction:parameters.direction
      ~start_angle:parameters.start_angle ~divisions:(divisions parameters)
      ~uniform_angle:parameters.uniform_angle
      ~spiral_count:parameters.spiral_count
      ~orientation:(orientation parameters)
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z)
      ~rotation:(Vec3.create parameters.rotation_x parameters.rotation_y
        parameters.rotation_z) ~rotation_order:parameters.rotation_order
      ~uniform_scale:parameters.uniform_scale
      ?angle_attribute:(optional_text parameters.angle_attribute)
      ?x_axis_attribute:(optional_text parameters.x_axis_attribute)
      ?y_axis_attribute:(optional_text parameters.y_axis_attribute)
      ?tangent_attribute:(optional_text parameters.tangent_attribute)
      ?orient_attribute:(optional_text parameters.orient_attribute)
      ?distance_attribute:(optional_text parameters.distance_attribute) ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build
  let create ?label:node_label () =
    build ~label:(label "spiral" node_label) ~inputs:[] parameters_default
end [@@sop.register]

module Switch = struct
  type parameters = { input : int }

  let option_label index node =
    Printf.sprintf "%d · %s" index (Node.label node)

  let schema inputs default =
    let options = List.mapi (fun index node -> option_label index node, index)
        inputs in
    Parameter.schema ~name:"switch" ~default
      [Parameter.field ~name:"input" ~label:"Source"
         ~description:"Input branch displayed and cooked by this Switch SOP"
         ~kind:(Parameter.choice ~equal:Int.equal options)
         ~default:default.input ~get:(fun value -> value.input)
         ~set:(fun input _ -> { input }) ()]

  let rec build ~label ~inputs parameters =
    let schema = schema inputs parameters in
    Sop.switch ~label ~index:parameters.input inputs
    |> Node.parameterize ~schema ~values:parameters ~rebuild:build

  let create ?label:node_label ?(index = 0) inputs =
    build ~label:(label "switch" node_label) ~inputs { input = index }

  let factory = Edit_graph.factory ~key:"switch" ~label:"Switch"
      ~category:["Utility"] ~arity:2 (fun inputs -> create inputs)
end [@@sop.register]

module Line = struct
  let kind_parameter = Parameter.choice ~equal:( = ) [
      "Polygon curve", Pdk.Ops.Line_curve;
      "Points", Pdk.Ops.Line_points;
    ]

  type parameters = {
    kind : Pdk.Ops.line_kind [@sop.default Pdk.Ops.Line_curve]
      [@sop.label "Primitive type"] [@sop.kind kind_parameter];
    points : int [@sop.default 2] [@sop.label "Points"]
      [@sop.min 2] [@sop.max 128] [@sop.hard_min 1];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Origin"] [@sop.min (-10.)] [@sop.max 10.];
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.];
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.];
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.];
    length : float [@sop.default 1.] [@sop.label "Length"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
  } [@@sop.node_key "line"] [@@sop.node_label "Line"]
    [@@sop.node_category "Create/Curve"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs:_ parameters =
    Sop.line ~label ~kind:parameters.kind ~points:parameters.points
      ~origin:(Vec3.create parameters.origin_x parameters.origin_y
        parameters.origin_z)
      ~direction:(Vec3.create parameters.direction_x parameters.direction_y
        parameters.direction_z) ~length:parameters.length ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build

  let create ?label:node_label ?(kind = Pdk.Ops.Line_curve) ?(points = 2)
      ?(origin = Vec3.zero) ?(direction = Vec3.create 0. 1. 0.)
      ?(length = 1.) () =
    build ~label:(label "line" node_label) ~inputs:[] {
      kind; points; origin_x = origin.x; origin_y = origin.y;
      origin_z = origin.z; direction_x = direction.x;
      direction_y = direction.y; direction_z = direction.z; length }
end [@@sop.register]

module Circle = struct
  type arc_mode = Closed | Open | Chord | Sliced

  let arc_parameter = Parameter.choice ~equal:( = ) [
      "Closed", Closed; "Open arc", Open; "Chord closed", Chord;
      "Sliced", Sliced;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "XZ", Pdk.Ops.Circle_xz; "XY", Pdk.Ops.Circle_xy;
      "YZ", Pdk.Ops.Circle_yz;
    ]

  type parameters = {
    arc : arc_mode [@sop.default Closed] [@sop.label "Arc"]
      [@sop.kind arc_parameter];
    start_angle : float [@sop.default 0.] [@sop.label "Start angle"]
      [@sop.folder "Arc"] [@sop.min (-6.283185)] [@sop.max 6.283185];
    end_angle : float [@sop.default 6.283185307179586]
      [@sop.label "End angle"] [@sop.folder "Arc"]
      [@sop.min (-6.283185)] [@sop.max 6.283185];
    orientation : Pdk.Ops.circle_orientation
      [@sop.default Pdk.Ops.Circle_xz] [@sop.label "Orientation"]
      [@sop.kind orientation_parameter];
    reverse : bool [@sop.default false] [@sop.label "Reverse"];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.];
    radius_x : float [@sop.default 1.] [@sop.label "Radius X"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    radius_y : float [@sop.default 1.] [@sop.label "Radius Y"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    rotation : float [@sop.default 0.] [@sop.label "Rotation"]
      [@sop.folder "Transform"] [@sop.min (-3.14159)] [@sop.max 3.14159];
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    segments : int [@sop.default 48] [@sop.label "Segments"]
      [@sop.min 3] [@sop.max 256] [@sop.hard_min 3];
  } [@@sop.node_key "circle"] [@@sop.node_label "Circle"]
    [@@sop.node_category "Create/Curve"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let arc parameters = match parameters.arc with
    | Closed -> Pdk.Ops.Circle_closed
    | Open -> Pdk.Ops.Circle_open_arc {
        start_angle = parameters.start_angle; end_angle = parameters.end_angle }
    | Chord -> Pdk.Ops.Circle_closed_arc {
        start_angle = parameters.start_angle; end_angle = parameters.end_angle }
    | Sliced -> Pdk.Ops.Circle_sliced_arc {
        start_angle = parameters.start_angle; end_angle = parameters.end_angle }

  let rec build ~label ~inputs:_ parameters =
    Sop.circle ~label ~arc:(arc parameters) ~orientation:parameters.orientation
      ~reverse:parameters.reverse
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z) ~radius_x:parameters.radius_x
      ~radius_y:parameters.radius_y ~rotation:parameters.rotation
      ~uniform_scale:parameters.uniform_scale ~segments:parameters.segments
      ~radius:1. ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build

  let create ?label:node_label () =
    build ~label:(label "circle" node_label) ~inputs:[] parameters_default
end [@@sop.register]

module Grid = struct
  let counts_parameter = Parameter.choice ~equal:( = ) [
      "Divisions", Pdk.Ops.Grid_divisions;
      "Point counts", Pdk.Ops.Grid_point_counts;
    ]

  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Points", Pdk.Ops.Grid_points;
      "Rows", Pdk.Ops.Grid_rows;
      "Columns", Pdk.Ops.Grid_columns;
      "Rows and columns", Pdk.Ops.Grid_rows_and_columns;
      "Quads", Pdk.Ops.Grid_quads;
      "Triangles", Pdk.Ops.Grid_triangles;
      "Alternating triangles", Pdk.Ops.Grid_alternating_triangles;
      "Reverse triangles", Pdk.Ops.Grid_reverse_triangles;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "XY", Pdk.Ops.Grid_xy;
      "XZ", Pdk.Ops.Grid_xz;
      "YZ", Pdk.Ops.Grid_yz;
    ]

  type parameters = {
    counts : Pdk.Ops.grid_counts [@sop.default Pdk.Ops.Grid_divisions]
      [@sop.label "Counts"] [@sop.kind counts_parameter];
    connectivity : Pdk.Ops.grid_connectivity
      [@sop.default Pdk.Ops.Grid_triangles]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    orientation : Pdk.Ops.grid_orientation [@sop.default Pdk.Ops.Grid_xz]
      [@sop.label "Orientation"] [@sop.kind orientation_parameter];
    columns : int [@sop.default 10] [@sop.label "Columns"]
      [@sop.folder "Resolution"] [@sop.min 1] [@sop.max 64]
      [@sop.hard_min 1];
    rows : int [@sop.default 10] [@sop.label "Rows"]
      [@sop.folder "Resolution"] [@sop.min 1] [@sop.max 64]
      [@sop.hard_min 1];
    size : float [@sop.default 1.] [@sop.label "Size"]
      [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.];
    width : float [@sop.default 1.] [@sop.label "Width"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    height : float [@sop.default 1.] [@sop.label "Height"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    rotation : float [@sop.default 0.] [@sop.label "Rotation"]
      [@sop.folder "Transform"] [@sop.min (-3.14159)] [@sop.max 3.14159];
    uv_attribute : string [@sop.default ""] [@sop.label "UV attribute"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "grid"] [@@sop.node_label "Grid"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs:_ parameters =
    Sop.grid ~label ~counts:parameters.counts
      ~connectivity:parameters.connectivity ~orientation:parameters.orientation
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z) ~width:parameters.width ~height:parameters.height
      ~rotation:parameters.rotation
      ?uv_attribute:(optional_text parameters.uv_attribute)
      ~columns:parameters.columns ~rows:parameters.rows ~size:parameters.size ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build

  let create ?label:node_label ?(counts = Pdk.Ops.Grid_divisions)
      ?(connectivity = Pdk.Ops.Grid_triangles)
      ?(orientation = Pdk.Ops.Grid_xz) ?(center = Vec3.zero) ?width ?height
      ?(rotation = 0.) ?(uv_attribute = "") ~columns ~rows ~size () =
    build ~label:(label "grid" node_label) ~inputs:[] {
      counts; connectivity; orientation; columns; rows; size;
      width = Option.value ~default:size width;
      height = Option.value ~default:size height;
      center_x = center.x; center_y = center.y; center_z = center.z;
      rotation; uv_attribute }
end [@@sop.register]

module Uv_sphere = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Pdk.Ops.Sphere_triangles;
      "Alternating triangles", Pdk.Ops.Sphere_alternating_triangles;
      "Quads", Pdk.Ops.Sphere_quads;
      "Rows", Pdk.Ops.Sphere_rows;
      "Columns", Pdk.Ops.Sphere_columns;
      "Rows and columns", Pdk.Ops.Sphere_rows_and_columns;
      "Points", Pdk.Ops.Sphere_points;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Pdk.Ops.Sphere_no_normals;
      "Point", Pdk.Ops.Sphere_point_normals;
      "Vertex", Pdk.Ops.Sphere_vertex_normals;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Pdk.Ops.Sphere_x;
      "Y axis", Pdk.Ops.Sphere_y;
      "Z axis", Pdk.Ops.Sphere_z;
    ]

  type parameters = {
    connectivity : Pdk.Ops.sphere_connectivity
      [@sop.default Pdk.Ops.Sphere_triangles]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    normals : Pdk.Ops.sphere_normals
      [@sop.default Pdk.Ops.Sphere_point_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    orientation : Pdk.Ops.sphere_orientation
      [@sop.default Pdk.Ops.Sphere_y]
      [@sop.label "Pole axis"] [@sop.kind orientation_parameter];
    unique_points_per_pole : bool [@sop.default false]
      [@sop.label "Unique pole points"] [@sop.folder "Topology"];
    triangular_poles : bool [@sop.default true]
      [@sop.label "Triangular poles"] [@sop.folder "Topology"];
    radius_x : float [@sop.default 1.] [@sop.label "Radius X"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    radius_y : float [@sop.default 1.] [@sop.label "Radius Y"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    radius_z : float [@sop.default 1.] [@sop.label "Radius Z"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    segments : int [@sop.default 48] [@sop.label "Segments"]
      [@sop.folder "Resolution"] [@sop.min 3] [@sop.max 256]
      [@sop.hard_min 3];
    rings : int [@sop.default 24] [@sop.label "Rings"]
      [@sop.folder "Resolution"] [@sop.min 2] [@sop.max 128]
      [@sop.hard_min 2];
    uv_attribute : string [@sop.default "uv"] [@sop.label "UV attribute"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "uv_sphere"] [@@sop.node_label "UV Sphere"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs:_ parameters =
    Sop.uv_sphere ~label ~connectivity:parameters.connectivity
      ~unique_points_per_pole:parameters.unique_points_per_pole
      ~triangular_poles:parameters.triangular_poles ~normals:parameters.normals
      ~orientation:parameters.orientation
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z)
      ~rotation:(Vec3.create parameters.rotation_x parameters.rotation_y
        parameters.rotation_z) ~uniform_scale:parameters.uniform_scale
      ~radius_x:parameters.radius_x ~radius_y:parameters.radius_y
      ~radius_z:parameters.radius_z
      ?uv_attribute:(optional_text parameters.uv_attribute)
      ~segments:parameters.segments ~rings:parameters.rings ~radius:1. ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build

  let create ?label:node_label () =
    build ~label:(label "uv-sphere" node_label) ~inputs:[] parameters_default
end [@@sop.register]

module Torus = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Pdk.Ops.Torus_triangles;
      "Alternating triangles", Pdk.Ops.Torus_alternating_triangles;
      "Quads", Pdk.Ops.Torus_quads;
      "Rows", Pdk.Ops.Torus_rows;
      "Columns", Pdk.Ops.Torus_columns;
      "Rows and columns", Pdk.Ops.Torus_rows_and_columns;
      "Points", Pdk.Ops.Torus_points;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Pdk.Ops.Torus_no_normals;
      "Point", Pdk.Ops.Torus_point_normals;
      "Vertex", Pdk.Ops.Torus_vertex_normals;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Pdk.Ops.Torus_x;
      "Y axis", Pdk.Ops.Torus_y;
      "Z axis", Pdk.Ops.Torus_z;
    ]

  type parameters = {
    connectivity : Pdk.Ops.torus_connectivity
      [@sop.default Pdk.Ops.Torus_triangles]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    normals : Pdk.Ops.torus_normals
      [@sop.default Pdk.Ops.Torus_point_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    orientation : Pdk.Ops.torus_orientation
      [@sop.default Pdk.Ops.Torus_y]
      [@sop.label "Hole axis"] [@sop.kind orientation_parameter];
    major_radius : float [@sop.default 1.] [@sop.label "Major radius"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    minor_radius : float [@sop.default 0.25] [@sop.label "Minor radius"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 5.]
      [@sop.hard_min 0.];
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    u_start : float [@sop.default 0.] [@sop.label "U start"]
      [@sop.folder "Arc/U"] [@sop.min (-6.283185)] [@sop.max 6.283185];
    u_end : float [@sop.default 6.283185307179586] [@sop.label "U end"]
      [@sop.folder "Arc/U"] [@sop.min (-6.283185)] [@sop.max 6.283185];
    v_start : float [@sop.default 0.] [@sop.label "V start"]
      [@sop.folder "Arc/V"] [@sop.min (-6.283185)] [@sop.max 6.283185];
    v_end : float [@sop.default 6.283185307179586] [@sop.label "V end"]
      [@sop.folder "Arc/V"] [@sop.min (-6.283185)] [@sop.max 6.283185];
    u_wrap : bool [@sop.default true] [@sop.label "Wrap U"]
      [@sop.folder "Arc/U"];
    v_wrap : bool [@sop.default true] [@sop.label "Wrap V"]
      [@sop.folder "Arc/V"];
    u_end_caps : bool [@sop.default false] [@sop.label "U end caps"]
      [@sop.folder "Caps"];
    v_end_cap : bool [@sop.default false] [@sop.label "V end cap"]
      [@sop.folder "Caps"];
    rows : int [@sop.default 48] [@sop.label "Rows"]
      [@sop.folder "Resolution"] [@sop.min 3] [@sop.max 256]
      [@sop.hard_min 2];
    columns : int [@sop.default 24] [@sop.label "Columns"]
      [@sop.folder "Resolution"] [@sop.min 3] [@sop.max 256]
      [@sop.hard_min 2];
    uv_attribute : string [@sop.default "uv"] [@sop.label "UV attribute"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "torus"] [@@sop.node_label "Torus"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs:_ parameters =
    Sop.torus ~label ~connectivity:parameters.connectivity
      ~normals:parameters.normals ~orientation:parameters.orientation
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z)
      ~rotation:(Vec3.create parameters.rotation_x parameters.rotation_y
        parameters.rotation_z) ~uniform_scale:parameters.uniform_scale
      ~u_start:parameters.u_start ~u_end:parameters.u_end
      ~v_start:parameters.v_start ~v_end:parameters.v_end
      ~u_wrap:parameters.u_wrap ~v_wrap:parameters.v_wrap
      ~u_end_caps:parameters.u_end_caps ~v_end_cap:parameters.v_end_cap
      ?uv_attribute:(optional_text parameters.uv_attribute)
      ~rows:parameters.rows ~columns:parameters.columns
      ~major_radius:parameters.major_radius ~minor_radius:parameters.minor_radius
      ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build

  let create ?label:node_label () =
    build ~label:(label "torus" node_label) ~inputs:[] parameters_default
end [@@sop.register]

module Tube = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Pdk.Ops.Tube_triangles;
      "Alternating triangles", Pdk.Ops.Tube_alternating_triangles;
      "Quads", Pdk.Ops.Tube_quads;
      "Rows", Pdk.Ops.Tube_rows;
      "Columns", Pdk.Ops.Tube_columns;
      "Rows and columns", Pdk.Ops.Tube_rows_and_columns;
      "Points", Pdk.Ops.Tube_points;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Pdk.Ops.Tube_no_normals;
      "Point", Pdk.Ops.Tube_point_normals;
      "Vertex", Pdk.Ops.Tube_vertex_normals;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Pdk.Ops.Tube_x;
      "Y axis", Pdk.Ops.Tube_y;
      "Z axis", Pdk.Ops.Tube_z;
    ]

  type parameters = {
    connectivity : Pdk.Ops.tube_connectivity
      [@sop.default Pdk.Ops.Tube_triangles]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    normals : Pdk.Ops.tube_normals
      [@sop.default Pdk.Ops.Tube_point_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    orientation : Pdk.Ops.tube_orientation
      [@sop.default Pdk.Ops.Tube_y]
      [@sop.label "Primary axis"] [@sop.kind orientation_parameter];
    top_radius : float [@sop.default 1.] [@sop.label "Top radius"]
      [@sop.folder "Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    bottom_radius : float [@sop.default 1.] [@sop.label "Bottom radius"]
      [@sop.folder "Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    height : float [@sop.default 2.] [@sop.label "Height"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    radius_scale : float [@sop.default 1.] [@sop.label "Radius scale"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    end_caps : bool [@sop.default true] [@sop.label "End caps"]
      [@sop.folder "Caps"];
    consolidate_cap_points : bool [@sop.default false]
      [@sop.label "Consolidate cap points"] [@sop.folder "Caps"];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.];
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159];
    rows : int [@sop.default 1] [@sop.label "Rows"]
      [@sop.folder "Resolution"] [@sop.min 1] [@sop.max 128]
      [@sop.hard_min 1];
    columns : int [@sop.default 32] [@sop.label "Columns"]
      [@sop.folder "Resolution"] [@sop.min 3] [@sop.max 256]
      [@sop.hard_min 3];
    uv_attribute : string [@sop.default "uv"] [@sop.label "UV attribute"]
      [@sop.folder "Attributes"];
    cap_group : string [@sop.default "caps"] [@sop.label "Cap group"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "tube"] [@@sop.node_label "Tube"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs:_ parameters =
    Sop.tube ~label ~connectivity:parameters.connectivity
      ~end_caps:parameters.end_caps
      ~consolidate_cap_points:parameters.consolidate_cap_points
      ~normals:parameters.normals ~orientation:parameters.orientation
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z)
      ~rotation:(Vec3.create parameters.rotation_x parameters.rotation_y
        parameters.rotation_z) ~radius_scale:parameters.radius_scale
      ?uv_attribute:(optional_text parameters.uv_attribute)
      ?cap_group:(optional_text parameters.cap_group)
      ~rows:parameters.rows ~columns:parameters.columns
      ~top_radius:parameters.top_radius ~bottom_radius:parameters.bottom_radius
      ~height:parameters.height ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build

  let create ?label:node_label () =
    build ~label:(label "tube" node_label) ~inputs:[] parameters_default
end [@@sop.register]

module Transform = struct
  type parameters = {
    translate_x : float [@sop.default 0.] [@sop.label "Translate X"]
      [@sop.folder "Translate"] [@sop.min (-10.)] [@sop.max 10.];
    translate_y : float [@sop.default 0.] [@sop.label "Translate Y"]
      [@sop.folder "Translate"] [@sop.min (-10.)] [@sop.max 10.];
    translate_z : float [@sop.default 0.] [@sop.label "Translate Z"]
      [@sop.folder "Translate"] [@sop.min (-10.)] [@sop.max 10.];
    rotate_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Rotate"] [@sop.min (-3.14159)] [@sop.max 3.14159];
    rotate_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Rotate"] [@sop.min (-3.14159)] [@sop.max 3.14159];
    rotate_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Rotate"] [@sop.min (-3.14159)] [@sop.max 3.14159];
    scale_x : float [@sop.default 1.] [@sop.label "Scale X"]
      [@sop.folder "Scale"] [@sop.min 0.01] [@sop.max 10.];
    scale_y : float [@sop.default 1.] [@sop.label "Scale Y"]
      [@sop.folder "Scale"] [@sop.min 0.01] [@sop.max 10.];
    scale_z : float [@sop.default 1.] [@sop.label "Scale Z"]
      [@sop.folder "Scale"] [@sop.min 0.01] [@sop.max 10.];
    preserve_normal_length : bool [@sop.default false]
      [@sop.label "Preserve normal length"] [@sop.folder "Normals"];
    recompute_normals : bool [@sop.default false]
      [@sop.label "Recompute normals"] [@sop.folder "Normals"];
  } [@@sop.node_key "transform"] [@@sop.node_label "Transform"]
    [@@sop.node_category "Modify"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.transform_trs ~label
          ~translate:(Vec3.create parameters.translate_x parameters.translate_y
            parameters.translate_z)
          ~rotate:(Vec3.create parameters.rotate_x parameters.rotate_y
            parameters.rotate_z)
          ~scale:(Vec3.create parameters.scale_x parameters.scale_y
            parameters.scale_z)
          ~preserve_normal_length:parameters.preserve_normal_length
          ~recompute_normals:parameters.recompute_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Transform expects one input"

  let factory = parameters_factory build

  let create ?label:node_label ?(translate = Vec3.zero) ?(rotate = Vec3.zero)
      ?(scale = Vec3.create 1. 1. 1.) ?(preserve_normal_length = false)
      ?(recompute_normals = false) input =
    build ~label:(label "transform" node_label) ~inputs:[input] {
      translate_x = translate.x; translate_y = translate.y;
      translate_z = translate.z; rotate_x = rotate.x; rotate_y = rotate.y;
      rotate_z = rotate.z; scale_x = scale.x; scale_y = scale.y;
      scale_z = scale.z; preserve_normal_length; recompute_normals }
end [@@sop.register]

module Match_size = struct
  let fit_parameter = Parameter.choice ~equal:( = ) [
      "Translate only", Pdk.Ops.Translate_only;
      "Stretch", Pdk.Ops.Stretch;
      "Contain", Pdk.Ops.Contain;
      "Cover", Pdk.Ops.Cover;
      "Match X", Pdk.Ops.Match_x;
      "Match Y", Pdk.Ops.Match_y;
      "Match Z", Pdk.Ops.Match_z;
      "Match perimeter", Pdk.Ops.Match_perimeter;
      "Match area", Pdk.Ops.Match_area;
      "Match volume", Pdk.Ops.Match_volume;
    ]

  type parameters = {
    fit : Pdk.Ops.match_size_fit [@sop.default Pdk.Ops.Contain]
      [@sop.label "Fit"] [@sop.kind fit_parameter];
    translate_x : bool [@sop.default true] [@sop.label "Translate X"]
      [@sop.folder "Axes/Translate"];
    translate_y : bool [@sop.default true] [@sop.label "Translate Y"]
      [@sop.folder "Axes/Translate"];
    translate_z : bool [@sop.default true] [@sop.label "Translate Z"]
      [@sop.folder "Axes/Translate"];
    scale_x : bool [@sop.default true] [@sop.label "Scale X"]
      [@sop.folder "Axes/Scale"];
    scale_y : bool [@sop.default true] [@sop.label "Scale Y"]
      [@sop.folder "Axes/Scale"];
    scale_z : bool [@sop.default true] [@sop.label "Scale Z"]
      [@sop.folder "Axes/Scale"];
    justify_x : float [@sop.default 0.] [@sop.label "Justify X"]
      [@sop.folder "Justify/Source"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.];
    justify_y : float [@sop.default 0.] [@sop.label "Justify Y"]
      [@sop.folder "Justify/Source"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.];
    justify_z : float [@sop.default 0.] [@sop.label "Justify Z"]
      [@sop.folder "Justify/Source"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.];
    target_justify_x : float [@sop.default 0.] [@sop.label "Justify X"]
      [@sop.folder "Justify/Target"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.];
    target_justify_y : float [@sop.default 0.] [@sop.label "Justify Y"]
      [@sop.folder "Justify/Target"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.];
    target_justify_z : float [@sop.default 0.] [@sop.label "Justify Z"]
      [@sop.folder "Justify/Target"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.];
    offset_x : float [@sop.default 0.] [@sop.label "Offset X"]
      [@sop.folder "Transform/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    offset_y : float [@sop.default 0.] [@sop.label "Offset Y"]
      [@sop.folder "Transform/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    offset_z : float [@sop.default 0.] [@sop.label "Offset Z"]
      [@sop.folder "Transform/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    scale : float [@sop.default 1.] [@sop.label "Scale"]
      [@sop.folder "Transform"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    target_center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Numeric target/Center"] [@sop.min (-10.)]
      [@sop.max 10.];
    target_center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Numeric target/Center"] [@sop.min (-10.)]
      [@sop.max 10.];
    target_center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Numeric target/Center"] [@sop.min (-10.)]
      [@sop.max 10.];
    target_size_x : float [@sop.default 1.] [@sop.label "Size X"]
      [@sop.folder "Numeric target/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    target_size_y : float [@sop.default 1.] [@sop.label "Size Y"]
      [@sop.folder "Numeric target/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    target_size_z : float [@sop.default 1.] [@sop.label "Size Z"]
      [@sop.folder "Numeric target/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
  } [@@sop.node_key "match_size"] [@@sop.node_label "Match Size"]
    [@@sop.node_category "Modify"] [@@sop.node_inputs 2]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; target] ->
        let target_center, target_size = match target with
          | Some _ -> None, None
          | None ->
              Some (Vec3.create parameters.target_center_x
                parameters.target_center_y parameters.target_center_z),
              Some (Vec3.create parameters.target_size_x
                parameters.target_size_y parameters.target_size_z) in
        Sop.match_size ~label ~fit:parameters.fit
          ~translate_axes:(parameters.translate_x, parameters.translate_y,
            parameters.translate_z)
          ~scale_axes:(parameters.scale_x, parameters.scale_y,
            parameters.scale_z)
          ~justify:(Vec3.create parameters.justify_x parameters.justify_y
            parameters.justify_z)
          ~target_justify:(Vec3.create parameters.target_justify_x
            parameters.target_justify_y parameters.target_justify_z)
          ~offset:(Vec3.create parameters.offset_x parameters.offset_y
            parameters.offset_z) ~scale:parameters.scale
          ?target_center ?target_size
          ?target input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild
    | _ -> invalid_arg "Sop_catalog.Match_size requires its source input"

  and rebuild ~label ~inputs parameters = match inputs with
    | [input] -> build_slots ~label ~inputs:[Some input; None] parameters
    | [input; target] ->
        build_slots ~label ~inputs:[Some input; Some target] parameters
    | _ -> invalid_arg "Sop_catalog.Match_size has invalid physical inputs"

  let factory = parameters_factory build_slots

  let create ?label:node_label ?target input =
    build_slots ~label:(label "match-size" node_label)
      ~inputs:[Some input; target]
      parameters_default
end [@@sop.register]

module Mirror = struct
  type parameters = {
    keep_original : bool [@sop.default true] [@sop.label "Keep original"];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    normal_x : float [@sop.default 1.] [@sop.label "Normal X"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.];
    normal_y : float [@sop.default 0.] [@sop.label "Normal Y"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.];
    normal_z : float [@sop.default 0.] [@sop.label "Normal Z"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.];
  } [@@sop.node_key "mirror"] [@@sop.node_label "Mirror"]
    [@@sop.node_category "Modify"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.mirror ~label ~keep_original:parameters.keep_original
          ~origin:(Vec3.create parameters.origin_x parameters.origin_y
            parameters.origin_z)
          ~normal:(Vec3.create parameters.normal_x parameters.normal_y
            parameters.normal_z) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Mirror expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "mirror" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Clip = struct
  let keep_parameter = Parameter.choice ~equal:( = ) [
      "Above", Pdk.Ops.Above;
      "Below", Pdk.Ops.Below;
      "All", Pdk.Ops.All;
    ]

  type parameters = {
    keep : Pdk.Ops.clip_keep [@sop.default Pdk.Ops.Above]
      [@sop.label "Keep"] [@sop.kind keep_parameter];
    snapping_tolerance : float [@sop.default 1e-9]
      [@sop.label "Snapping tolerance"] [@sop.folder "Robustness"]
      [@sop.min 0.] [@sop.max 0.001] [@sop.hard_min 0.];
    fill : bool [@sop.default false] [@sop.label "Fill cut"]
      [@sop.folder "Topology"];
    split_connectivity : bool [@sop.default false]
      [@sop.label "Split connectivity"] [@sop.folder "Topology"];
    distance : float [@sop.default 0.] [@sop.label "Distance"]
      [@sop.folder "Plane"] [@sop.min (-10.)] [@sop.max 10.];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    normal_x : float [@sop.default 0.] [@sop.label "Normal X"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.];
    normal_y : float [@sop.default 1.] [@sop.label "Normal Y"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.];
    normal_z : float [@sop.default 0.] [@sop.label "Normal Z"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.];
    clip_attribute : string [@sop.default "P"]
      [@sop.label "Clip attribute"] [@sop.folder "Attributes"];
    clipped_edge_group : string [@sop.default ""]
      [@sop.label "Clipped edges"] [@sop.folder "Output groups"];
    cap_group : string [@sop.default ""] [@sop.label "Caps"]
      [@sop.folder "Output groups"];
    clipped_group : string [@sop.default ""] [@sop.label "Clipped"]
      [@sop.folder "Output groups"];
    above_group : string [@sop.default ""] [@sop.label "Above"]
      [@sop.folder "Output groups"];
    below_group : string [@sop.default ""] [@sop.label "Below"]
      [@sop.folder "Output groups"];
    replace_existing_groups : bool [@sop.default false]
      [@sop.label "Replace existing groups"] [@sop.folder "Output groups"];
  } [@@sop.node_key "clip"] [@@sop.node_label "Clip"]
    [@@sop.node_category "Modify"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.clip ~label ~keep:parameters.keep
          ~snapping_tolerance:parameters.snapping_tolerance
          ~fill:parameters.fill ~split_connectivity:parameters.split_connectivity
          ?clip_attribute:(optional_text parameters.clip_attribute)
          ~distance:parameters.distance
          ~replace_existing_groups:parameters.replace_existing_groups
          ?clipped_edge_group:(optional_text parameters.clipped_edge_group)
          ?cap_group:(optional_text parameters.cap_group)
          ?clipped_group:(optional_text parameters.clipped_group)
          ?above_group:(optional_text parameters.above_group)
          ?below_group:(optional_text parameters.below_group)
          ~origin:(Vec3.create parameters.origin_x parameters.origin_y
            parameters.origin_z)
          ~normal:(Vec3.create parameters.normal_x parameters.normal_y
            parameters.normal_z) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Clip expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "clip" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

module Crease = struct
  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Add", Pdk.Ops.Crease_add;
      "Set", Pdk.Ops.Crease_set;
      "Delete", Pdk.Ops.Crease_delete;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    operation : Pdk.Ops.crease_operation [@sop.default Pdk.Ops.Crease_add]
      [@sop.label "Operation"] [@sop.kind operation_parameter];
    weight : float [@sop.default 1.] [@sop.label "Weight"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
    add_vertex_color : bool [@sop.default false]
      [@sop.label "Visualize with vertex color"];
  } [@@sop.node_key "crease"] [@@sop.node_label "Crease"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.crease ~label ?group:(optional_text parameters.group)
          ~operation:parameters.operation ~weight:parameters.weight
          ~add_vertex_color:parameters.add_vertex_color input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Crease expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "crease" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

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
      "Catmull-Clark", Pdk.Ops.Catmull_clark;
      "Loop", Pdk.Ops.Loop;
      "Bilinear", Pdk.Ops.Bilinear;
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
      "None", Pdk.Ops.Subdivide_boundary_none;
      "Edge only", Pdk.Ops.Subdivide_boundary_edge_only;
      "Edge and corner", Pdk.Ops.Subdivide_boundary_edge_and_corner;
    ]

  let fvar_parameter = Parameter.choice ~equal:( = ) [
      "None", Pdk.Ops.Subdivide_fvar_none;
      "Corners only", Pdk.Ops.Subdivide_fvar_corners_only;
      "Corners plus 1", Pdk.Ops.Subdivide_fvar_corners_plus1;
      "Corners plus 2", Pdk.Ops.Subdivide_fvar_corners_plus2;
      "Boundaries", Pdk.Ops.Subdivide_fvar_boundaries;
      "All", Pdk.Ops.Subdivide_fvar_all;
    ]

  let triangle_parameter = Parameter.choice ~equal:( = ) [
      "Catmull-Clark", Pdk.Ops.Subdivide_triangles_catmull_clark;
      "Smooth", Pdk.Ops.Subdivide_triangles_smooth;
    ]

  let creasing_parameter = Parameter.choice ~equal:( = ) [
      "Uniform", Pdk.Ops.Subdivide_creasing_uniform;
      "Chaikin", Pdk.Ops.Subdivide_creasing_chaikin;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    scheme : Pdk.Ops.subdivision_scheme
      [@sop.default Pdk.Ops.Catmull_clark]
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
    boundary_interpolation : Pdk.Ops.subdivision_boundary_interpolation
      [@sop.default Pdk.Ops.Subdivide_boundary_edge_and_corner]
      [@sop.label "Point boundaries"] [@sop.folder "Interpolation"]
      [@sop.kind boundary_parameter];
    face_varying_interpolation :
      Pdk.Ops.subdivision_face_varying_interpolation
      [@sop.default Pdk.Ops.Subdivide_fvar_boundaries]
      [@sop.label "Vertex boundaries"] [@sop.folder "Interpolation"]
      [@sop.kind fvar_parameter];
    triangle_policy : Pdk.Ops.subdivision_triangle_policy
      [@sop.default Pdk.Ops.Subdivide_triangles_catmull_clark]
      [@sop.label "Triangles"] [@sop.folder "Interpolation"]
      [@sop.kind triangle_parameter];
    creasing_method : Pdk.Ops.subdivision_creasing_method
      [@sop.default Pdk.Ops.Subdivide_creasing_uniform]
      [@sop.label "Creasing method"] [@sop.folder "Creases"]
      [@sop.kind creasing_parameter];
    treat_curves_as_independent : bool [@sop.default false]
      [@sop.label "Treat curves independently"];
    recompute_point_normals : bool [@sop.default false]
      [@sop.label "Recompute point normals"];
  } [@@sop.node_key "subdivide"] [@@sop.node_label "Subdivide"]
    [@@sop.node_category "Topology"] [@@sop.node_inputs 2]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let cracks parameters = match parameters.cracks with
    | Do_not_close -> Pdk.Ops.Subdivide_do_not_close
    | Pull_no_division -> Pdk.Ops.Subdivide_pull_no_edge_division
    | Pull_divide -> Pdk.Ops.Subdivide_pull_divide_edges parameters.crack_bias
    | Pull_triangulate ->
        Pdk.Ops.Subdivide_pull_triangulate parameters.crack_bias
    | Stitch_no_division -> Pdk.Ops.Subdivide_stitch_no_edge_division
    | Stitch_divide -> Pdk.Ops.Subdivide_stitch_divide_edges
    | Stitch_triangulate -> Pdk.Ops.Subdivide_stitch_triangulate

  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; creases] ->
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
          ~recompute_point_normals:parameters.recompute_point_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild
    | _ -> invalid_arg "Sop_catalog.Subdivide requires its geometry input"

  and rebuild ~label ~inputs parameters = match inputs with
    | [input] -> build_slots ~label ~inputs:[Some input; None] parameters
    | [input; creases] ->
        build_slots ~label ~inputs:[Some input; Some creases] parameters
    | _ -> invalid_arg "Sop_catalog.Subdivide has invalid physical inputs"

  let factory = parameters_factory build_slots
  let create ?label:node_label ?creases input =
    build_slots ~label:(label "subdivide" node_label)
      ~inputs:[Some input; creases] parameters_default
end [@@sop.register]

module Edge_divide = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    divisions : int [@sop.default 2] [@sop.label "Divisions"]
      [@sop.min 1] [@sop.max 64] [@sop.hard_min 1];
    share_points : bool [@sop.default true] [@sop.label "Share points"];
  } [@@sop.node_key "edge_divide"] [@@sop.node_label "Edge Divide"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.edge_divide ~label ?group:(optional_text parameters.group)
          ~divisions:parameters.divisions ~share_points:parameters.share_points
          input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Edge_divide expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "edge-divide" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Edge_collapse = struct
  let position_parameter = Parameter.choice ~equal:( = ) [
      "First", Pdk.Ops.First_position;
      "Least point", Pdk.Ops.Least_point_position;
      "Greatest point", Pdk.Ops.Greatest_point_position;
      "Average", Pdk.Ops.Average_position;
      "Minimum", Pdk.Ops.Minimum_position;
      "Maximum", Pdk.Ops.Maximum_position;
      "Mode", Pdk.Ops.Mode_position;
      "Median", Pdk.Ops.Median_position;
      "Sum", Pdk.Ops.Sum_position;
      "Sum squares", Pdk.Ops.Sum_squares_position;
      "Root mean square", Pdk.Ops.Root_mean_square_position;
      "Weighted average", Pdk.Ops.Weighted_average_position;
      "Weighted sum", Pdk.Ops.Weighted_sum_position;
      "Minimum weight", Pdk.Ops.Minimum_weight_position;
      "Maximum weight", Pdk.Ops.Maximum_weight_position;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    connectivity_attribute : string [@sop.default ""]
      [@sop.label "Connectivity attribute"];
    position : Pdk.Ops.fuse_position
      [@sop.default Pdk.Ops.Average_position]
      [@sop.label "Position"] [@sop.kind position_parameter];
    remove_degenerate_primitives : bool [@sop.default true]
      [@sop.label "Remove degenerate primitives"] [@sop.folder "Cleanup"];
    recompute_point_normals : bool [@sop.default true]
      [@sop.label "Recompute point normals"] [@sop.folder "Cleanup"];
  } [@@sop.node_key "edge_collapse"] [@@sop.node_label "Edge Collapse"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.edge_collapse ~label ?group:(optional_text parameters.group)
          ?connectivity_attribute:(optional_text
            parameters.connectivity_attribute)
          ~position:parameters.position
          ~remove_degenerate_primitives:parameters.remove_degenerate_primitives
          ~recompute_point_normals:parameters.recompute_point_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Edge_collapse expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "edge-collapse" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Dissolve = struct
  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Selected", Pdk.Ops.Dissolve_selected;
      "Non-selected", Pdk.Ops.Dissolve_non_selected;
    ]

  let bridge_parameter = Parameter.choice ~equal:( = ) [
      "Create bridged polygons", Pdk.Ops.Create_bridged_polygons;
      "Create disjoint polygons", Pdk.Ops.Create_disjoint_polygons;
      "Delete bridge polygons", Pdk.Ops.Delete_bridge_polygons;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    operation : Pdk.Ops.dissolve_operation
      [@sop.default Pdk.Ops.Dissolve_selected]
      [@sop.label "Operation"] [@sop.kind operation_parameter];
    bridge_policy : Pdk.Ops.dissolve_bridge_policy
      [@sop.default Pdk.Ops.Create_bridged_polygons]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.dissolve ~label ?group:(optional_text parameters.group)
          ~operation:parameters.operation ~bridge_policy:parameters.bridge_policy
          ~remove_inline_points:parameters.remove_inline_points
          ~collinearity_tolerance:parameters.collinearity_tolerance
          ~remove_unused_points:parameters.remove_unused_points
          ~create_boundary_curves:parameters.create_boundary_curves
          ~recompute_normals:parameters.recompute_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Dissolve expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "dissolve" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
      [@sop.label "Ignore flat angle"] [@sop.folder "Robustness"]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let shape = match parameters.shape with
          | Chamfer -> Pdk.Ops.Bevel_chamfer
          | Round -> Pdk.Ops.Bevel_round { convexity = parameters.convexity } in
        Sop.poly_bevel ~label ?group:(optional_text parameters.group) ~shape
          ~divisions:parameters.divisions
          ?point_scale_attribute:(optional_text parameters.point_scale_attribute)
          ~ignore_flat_angle:parameters.ignore_flat_angle
          ~clamp_overlap:parameters.clamp_overlap
          ?edge_group:(optional_text parameters.edge_group)
          ?corner_group:(optional_text parameters.corner_group)
          ?offset_group:(optional_text parameters.offset_group)
          ~recompute_point_normals:parameters.recompute_point_normals
          ~distance:parameters.distance input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Poly_bevel expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "poly-bevel" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Triangulate = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
  } [@@sop.node_key "triangulate"] [@@sop.node_label "Triangulate"]
    [@@sop.node_category "Topology"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.triangulate ~label ?group:(optional_text parameters.group) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Triangulate expects one input"

  let factory = parameters_factory build

  let create ?label:node_label ?(group = "") input =
    build ~label:(label "triangulate" node_label) ~inputs:[input] { group }
end [@@sop.register]

module Copy_to_points = struct
  type parameters = {
    source_group : string [@sop.default ""] [@sop.label "Source group"]
      [@sop.folder "Selection"];
    target_group : string [@sop.default ""] [@sop.label "Target group"]
      [@sop.folder "Selection"];
    piece_attribute : string [@sop.default ""] [@sop.label "Piece attribute"]
      [@sop.folder "Matching"];
  } [@@sop.node_key "copy_to_points"] [@@sop.node_label "Copy to Points"]
    [@@sop.node_category "Copy"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [source; targets] ->
        Sop.copy_to_points ~label
          ?source_group:(optional_text parameters.source_group)
          ?target_group:(optional_text parameters.target_group)
          ?piece_attribute:(optional_text parameters.piece_attribute)
          ~source ~targets ()
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg
        "Sop_catalog.Copy_to_points expects source and target inputs"

  let factory = parameters_factory build

  let create ?label:node_label ?(source_group = "") ?(target_group = "")
      ?(piece_attribute = "") ~source ~targets () =
    build ~label:(label "copy-to-points" node_label) ~inputs:[source; targets] {
      source_group; target_group; piece_attribute }
end [@@sop.register]

module Mountain = struct
  type parameters = {
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.min 0]
      [@sop.max 9999];
    height : float [@sop.default 1.] [@sop.label "Height"]
      [@sop.min 0.] [@sop.max 2.] [@sop.hard_min 0.];
    frequency_x : float [@sop.default 1.] [@sop.label "Frequency X"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.];
    frequency_y : float [@sop.default 1.] [@sop.label "Frequency Y"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.];
    frequency_z : float [@sop.default 1.] [@sop.label "Frequency Z"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.];
    octaves : int [@sop.default 4] [@sop.label "Octaves"]
      [@sop.folder "Fractal"] [@sop.min 1] [@sop.max 8]
      [@sop.hard_min 1];
    lacunarity : float [@sop.default 2.] [@sop.label "Lacunarity"]
      [@sop.folder "Fractal"] [@sop.min 1.] [@sop.max 4.]
      [@sop.hard_min 0.];
    roughness : float [@sop.default 0.5] [@sop.label "Roughness"]
      [@sop.folder "Fractal"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.];
  } [@@sop.node_key "mountain"] [@@sop.node_label "Mountain"]
    [@@sop.node_category "Deform"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~group ~direction_attribute ~mask_attribute ~height_attribute
      ~recompute_normals ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.mountain ~label ?group ~seed:parameters.seed ?direction_attribute
          ?mask_attribute ~height:parameters.height
          ~frequency:(Vec3.create parameters.frequency_x parameters.frequency_y
            parameters.frequency_z) ~octaves:parameters.octaves
          ~lacunarity:parameters.lacunarity ~roughness:parameters.roughness
          ?height_attribute ~recompute_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:(build ~group ~direction_attribute ~mask_attribute
               ~height_attribute ~recompute_normals)
    | _ -> invalid_arg "Sop_catalog.Mountain expects one input"

  let factory = parameters_factory
      (build ~group:None ~direction_attribute:None ~mask_attribute:None
         ~height_attribute:None ~recompute_normals:true)

  let create ?label:node_label ?group ?direction_attribute ?mask_attribute
      ?height_attribute ?(recompute_normals = false) ~seed ~height ~frequency
      ~octaves ~lacunarity ~roughness input =
    build ~group ~direction_attribute ~mask_attribute ~height_attribute
      ~recompute_normals ~label:(label "mountain" node_label) ~inputs:[input] {
        seed; height; frequency_x = frequency.Vec3.x;
        frequency_y = frequency.y; frequency_z = frequency.z;
        octaves; lacunarity; roughness }
end [@@sop.register]

module Peak = struct
  type parameters = {
    direction_attribute : string [@sop.default "N"]
      [@sop.label "Direction attribute"] [@sop.folder "Direction"];
    normalize_direction : bool [@sop.default true]
      [@sop.label "Normalize direction"] [@sop.folder "Direction"];
    mask_attribute : string [@sop.default ""] [@sop.label "Mask attribute"];
    distance : float [@sop.default 0.1] [@sop.label "Distance"]
      [@sop.min (-10.)] [@sop.max 10.];
    recompute_normals : bool [@sop.default false]
      [@sop.label "Recompute normals"];
  } [@@sop.node_key "peak"] [@@sop.node_label "Peak"]
    [@@sop.node_category "Deform"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.peak ~label
          ?direction_attribute:(optional_text parameters.direction_attribute)
          ~normalize_direction:parameters.normalize_direction
          ?mask_attribute:(optional_text parameters.mask_attribute)
          ~distance:parameters.distance
          ~recompute_normals:parameters.recompute_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Peak expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "peak" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

module Bend = struct
  type parameters = {
    mask_attribute : string [@sop.default ""] [@sop.label "Mask attribute"];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Capture/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Capture/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Capture/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Capture/Direction"] [@sop.min (-1.)] [@sop.max 1.];
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Capture/Direction"] [@sop.min (-1.)] [@sop.max 1.];
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Capture/Direction"] [@sop.min (-1.)] [@sop.max 1.];
    up_x : float [@sop.default 0.] [@sop.label "Up X"]
      [@sop.folder "Capture/Up"] [@sop.min (-1.)] [@sop.max 1.];
    up_y : float [@sop.default 0.] [@sop.label "Up Y"]
      [@sop.folder "Capture/Up"] [@sop.min (-1.)] [@sop.max 1.];
    up_z : float [@sop.default 1.] [@sop.label "Up Z"]
      [@sop.folder "Capture/Up"] [@sop.min (-1.)] [@sop.max 1.];
    length : float [@sop.default 1.] [@sop.label "Length"]
      [@sop.folder "Capture"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    bend_angle : float [@sop.default 0.] [@sop.label "Bend angle"]
      [@sop.folder "Deformation"] [@sop.min (-6.283185)] [@sop.max 6.283185];
    twist_angle : float [@sop.default 0.] [@sop.label "Twist angle"]
      [@sop.folder "Deformation"] [@sop.min (-6.283185)] [@sop.max 6.283185];
    limit : bool [@sop.default true] [@sop.label "Limit deformation"];
    both_directions : bool [@sop.default false]
      [@sop.label "Capture both directions"];
    continuous_twist : bool [@sop.default false]
      [@sop.label "Continuous twist"];
    capture_attribute : string [@sop.default ""]
      [@sop.label "Capture attribute"] [@sop.folder "Attributes"];
    recompute_normals : bool [@sop.default false]
      [@sop.label "Recompute normals"];
  } [@@sop.node_key "bend"] [@@sop.node_label "Bend"]
    [@@sop.node_category "Deform"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.bend ~label ?mask_attribute:(optional_text parameters.mask_attribute)
          ~origin:(Vec3.create parameters.origin_x parameters.origin_y
            parameters.origin_z)
          ~direction:(Vec3.create parameters.direction_x parameters.direction_y
            parameters.direction_z)
          ~up:(Vec3.create parameters.up_x parameters.up_y parameters.up_z)
          ~length:parameters.length ~bend_angle:parameters.bend_angle
          ~twist_angle:parameters.twist_angle ~limit:parameters.limit
          ~both_directions:parameters.both_directions
          ~continuous_twist:parameters.continuous_twist
          ?capture_attribute:(optional_text parameters.capture_attribute)
          ~recompute_normals:parameters.recompute_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Bend expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "bend" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

module Smooth = struct
  type mode = Laplacian | Custom

  let boundary_parameter = Parameter.choice ~equal:( = ) [
      "Free", Pdk.Ops.Smooth_free;
      "Pin unshared", Pdk.Ops.Smooth_unshared;
      "Pin group boundary", Pdk.Ops.Smooth_group_boundary;
    ]

  let method_parameter = Parameter.choice ~equal:( = ) [
      "Uniform", Pdk.Attribute_ops.Uniform;
      "Edge length", Pdk.Attribute_ops.Edge_length;
    ]

  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Laplacian", Laplacian; "Custom steps", Custom;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    constrained_points : string [@sop.default ""]
      [@sop.label "Constrained points"];
    boundary : Pdk.Ops.smooth_boundary [@sop.default Pdk.Ops.Smooth_free]
      [@sop.label "Boundary"] [@sop.kind boundary_parameter];
    iterations : int [@sop.default 10] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 200] [@sop.hard_min 1];
    method_ : Pdk.Attribute_ops.blur_method
      [@sop.default Pdk.Attribute_ops.Uniform]
      [@sop.label "Method"] [@sop.kind method_parameter];
    mode : mode [@sop.default Laplacian] [@sop.label "Mode"]
      [@sop.kind mode_parameter];
    step : float [@sop.default 0.5] [@sop.label "Step"]
      [@sop.folder "Smoothing"] [@sop.min 0.] [@sop.max 1.];
    odd_step : float [@sop.default 0.5] [@sop.label "Odd step"]
      [@sop.folder "Custom steps"] [@sop.min (-1.)] [@sop.max 1.];
    even_step : float [@sop.default (-0.53)] [@sop.label "Even step"]
      [@sop.folder "Custom steps"] [@sop.min (-1.)] [@sop.max 1.];
    weight_attribute : string [@sop.default ""]
      [@sop.label "Weight attribute"] [@sop.folder "Attributes"];
    alpha_attribute : string [@sop.default ""]
      [@sop.label "Alpha attribute"] [@sop.folder "Attributes"];
    attributes : string [@sop.default "P"] [@sop.label "Attributes"]
      [@sop.folder "Attributes"];
    original_blend : float [@sop.default 0.] [@sop.label "Original blend"]
      [@sop.folder "Blend"] [@sop.min 0.] [@sop.max 1.];
    smoothed_blend : float [@sop.default 1.] [@sop.label "Smoothed blend"]
      [@sop.folder "Blend"] [@sop.min 0.] [@sop.max 1.];
    recompute_normals : bool [@sop.default false]
      [@sop.label "Recompute normals"];
  } [@@sop.node_key "smooth"] [@@sop.node_label "Smooth"]
    [@@sop.node_category "Deform"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let mode = match parameters.mode with
          | Laplacian -> Pdk.Attribute_ops.Laplacian parameters.step
          | Custom -> Pdk.Attribute_ops.Custom_steps {
              odd = parameters.odd_step; even = parameters.even_step } in
        Sop.smooth ~label ?group:(optional_text parameters.group)
          ?constrained_points:(optional_text parameters.constrained_points)
          ~boundary:parameters.boundary ~iterations:parameters.iterations
          ~method_:parameters.method_ ~mode
          ?weight_attribute:(optional_text parameters.weight_attribute)
          ?alpha_attribute:(optional_text parameters.alpha_attribute)
          ~recompute_normals:parameters.recompute_normals
          ~original_blend:parameters.original_blend
          ~smoothed_blend:parameters.smoothed_blend
          ~attributes:parameters.attributes input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Smooth expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "smooth" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let operation = match parameters.operation with
          | Reverse -> Pdk.Ops.Reverse_vertices
          | Shift -> Pdk.Ops.Shift_vertices parameters.shift in
        Sop.reverse ~label ?group:(optional_text parameters.group) ~operation input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Reverse expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "reverse" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Clean = struct
  let overlaps_parameter = Parameter.choice ~equal:( = ) [
      "Keep first", Pdk.Ops.Keep_first_overlap;
      "Delete pairs", Pdk.Ops.Delete_overlap_pairs;
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
    overlaps : Pdk.Ops.clean_overlap_policy
      [@sop.default Pdk.Ops.Keep_first_overlap]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          ?edge_groups:(optional_text parameters.edge_groups) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Clean expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "clean" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          ~reverse_normals:parameters.reverse_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Facet expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "facet" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

module Separate_pieces = struct
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Point", Pdk.Attribute.Point;
      "Primitive", Pdk.Attribute.Primitive;
    ]

  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Separate", Pdk.Ops.Separate_pieces_separate;
      "Move back", Pdk.Ops.Separate_pieces_move_back;
    ]

  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Primitive]
      [@sop.label "Piece owner"] [@sop.kind owner_parameter];
    piece_attribute : string [@sop.default "piece"]
      [@sop.label "Piece attribute"];
    translation_attribute : string [@sop.default "piece_translation"]
      [@sop.label "Translation attribute"];
    axis_x : float [@sop.default 1.] [@sop.label "Axis X"]
      [@sop.folder "Axis"] [@sop.min (-1.)] [@sop.max 1.];
    axis_y : float [@sop.default 0.] [@sop.label "Axis Y"]
      [@sop.folder "Axis"] [@sop.min (-1.)] [@sop.max 1.];
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Axis"] [@sop.min (-1.)] [@sop.max 1.];
    gap : float [@sop.default 0.001] [@sop.label "Gap"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    mode : Pdk.Ops.separate_pieces_mode
      [@sop.default Pdk.Ops.Separate_pieces_separate]
      [@sop.label "Mode"] [@sop.kind mode_parameter];
  } [@@sop.node_key "separate_pieces"] [@@sop.node_label "Separate Pieces"]
    [@@sop.node_category "Modify/Pieces"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.separate_pieces ~label ~owner:parameters.owner
          ~translation_attribute:parameters.translation_attribute
          ~axis:(Vec3.create parameters.axis_x parameters.axis_y
            parameters.axis_z) ~gap:parameters.gap ~mode:parameters.mode
          ~piece_attribute:parameters.piece_attribute input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Separate_pieces expects one input"

  let factory = parameters_factory build

  let create ?label:node_label ?(owner = Pdk.Attribute.Primitive)
      ?(translation_attribute = "piece_translation")
      ?(axis = Vec3.unit_x) ?(gap = 0.001)
      ?(mode = Pdk.Ops.Separate_pieces_separate) ~piece_attribute input =
    build ~label:(label "separate-pieces" node_label) ~inputs:[input] {
      owner; piece_attribute; translation_attribute;
      axis_x = axis.x; axis_y = axis.y; axis_z = axis.z; gap; mode }
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.edge_flip ~label ?group:(optional_text parameters.group)
          ~cycles:parameters.cycles
          ~cycle_vertex_attributes:parameters.cycle_vertex_attributes
          ~recompute_point_normals:parameters.recompute_point_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Edge_flip expects one input"

  let factory = parameters_factory build
  let create ?label:node_label ?(group = "") ?(cycles = 1)
      ?(cycle_vertex_attributes = true) ?(recompute_point_normals = false)
      input =
    build ~label:(label "edge-flip" node_label) ~inputs:[input]
      { group; cycles; cycle_vertex_attributes; recompute_point_normals }
end [@@sop.register]

module Edge_cusp = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    update_point_normals : bool [@sop.default true]
      [@sop.label "Update point normals"];
  } [@@sop.node_key "edge_cusp"] [@@sop.node_label "Edge Cusp"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.edge_cusp ~label ?group:(optional_text parameters.group)
          ~update_point_normals:parameters.update_point_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Edge_cusp expects one input"

  let factory = parameters_factory build
  let create ?label:node_label ?(group = "") ?(update_point_normals = true)
      input =
    build ~label:(label "edge-cusp" node_label) ~inputs:[input]
      { group; update_point_normals }
end [@@sop.register]

module Edge_straighten = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    output_group : string [@sop.default ""] [@sop.label "Output group"];
  } [@@sop.node_key "edge_straighten"] [@@sop.node_label "Edge Straighten"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.edge_straighten ~label ?group:(optional_text parameters.group)
          ?output_group:(optional_text parameters.output_group) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Edge_straighten expects one input"

  let factory = parameters_factory build
  let create ?label:node_label ?(group = "") ?(output_group = "") input =
    build ~label:(label "edge-straighten" node_label) ~inputs:[input]
      { group; output_group }
end [@@sop.register]

module Circle_from_edges = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    use_radius : bool [@sop.default false] [@sop.label "Override radius"];
    radius : float [@sop.default 1.] [@sop.label "Radius"]
      [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.];
    scale_x : float [@sop.default 1.] [@sop.label "Scale X"]
      [@sop.folder "Scale"] [@sop.min (-4.)] [@sop.max 4.];
    scale_y : float [@sop.default 1.] [@sop.label "Scale Y"]
      [@sop.folder "Scale"] [@sop.min (-4.)] [@sop.max 4.];
    scale_z : float [@sop.default 1.] [@sop.label "Scale Z"]
      [@sop.folder "Scale"] [@sop.min (-4.)] [@sop.max 4.];
    output_group : string [@sop.default ""] [@sop.label "Output group"];
  } [@@sop.node_key "circle_from_edges"]
    [@@sop.node_label "Circle from Edges"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let radius = if parameters.use_radius then Some parameters.radius
          else None in
        Sop.circle_from_edges ~label ?group:(optional_text parameters.group)
          ?radius ~scale:(Vec3.create parameters.scale_x parameters.scale_y
            parameters.scale_z)
          ?output_group:(optional_text parameters.output_group) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Circle_from_edges expects one input"

  let factory = parameters_factory build
  let create ?label:node_label ?(group = "") ?radius
      ?(scale = Vec3.create 1. 1. 1.) ?(output_group = "") input =
    build ~label:(label "circle-from-edges" node_label) ~inputs:[input] {
      group; use_radius = Option.is_some radius;
      radius = Option.value ~default:1. radius;
      scale_x = scale.x; scale_y = scale.y; scale_z = scale.z; output_group }
end [@@sop.register]

module Edge_equalize = struct
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Average", Pdk.Ops.Equalize_average;
      "Longest", Pdk.Ops.Equalize_longest;
      "Shortest", Pdk.Ops.Equalize_shortest;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Edge group"];
    method_ : Pdk.Ops.edge_equalize_method
      [@sop.default Pdk.Ops.Equalize_average]
      [@sop.label "Method"] [@sop.kind method_parameter];
    iterations : int [@sop.default 64] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 256] [@sop.hard_min 1];
    tolerance : float [@sop.default 0.000001] [@sop.label "Tolerance"]
      [@sop.min 0.000000001] [@sop.max 0.01] [@sop.hard_min 0.];
    output_group : string [@sop.default ""] [@sop.label "Output group"];
  } [@@sop.node_key "edge_equalize"] [@@sop.node_label "Edge Equalize"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.edge_equalize ~label ?group:(optional_text parameters.group)
          ~method_:parameters.method_ ~iterations:parameters.iterations
          ~tolerance:parameters.tolerance
          ?output_group:(optional_text parameters.output_group) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Edge_equalize expects one input"

  let factory = parameters_factory build
  let create ?label:node_label ?(group = "")
      ?(method_ = Pdk.Ops.Equalize_average) ?(iterations = 64)
      ?(tolerance = 0.000001) ?(output_group = "") input =
    build ~label:(label "edge-equalize" node_label) ~inputs:[input]
      { group; method_; iterations; tolerance; output_group }
end [@@sop.register]

module Snap_to_grid = struct
  let rounding_parameter = Parameter.choice ~equal:( = ) [
      "Nearest", Pdk.Ops.Grid_nearest;
      "Down", Pdk.Ops.Grid_down;
      "Up", Pdk.Ops.Grid_up;
    ]

  let position_parameter = Parameter.choice ~equal:( = ) [
      "First", Pdk.Ops.First_position;
      "Least point", Pdk.Ops.Least_point_position;
      "Greatest point", Pdk.Ops.Greatest_point_position;
      "Average", Pdk.Ops.Average_position;
      "Minimum", Pdk.Ops.Minimum_position;
      "Maximum", Pdk.Ops.Maximum_position;
      "Mode", Pdk.Ops.Mode_position;
      "Median", Pdk.Ops.Median_position;
      "Sum", Pdk.Ops.Sum_position;
      "Sum squares", Pdk.Ops.Sum_squares_position;
      "Root mean square", Pdk.Ops.Root_mean_square_position;
      "Weighted average", Pdk.Ops.Weighted_average_position;
      "Weighted sum", Pdk.Ops.Weighted_sum_position;
      "Minimum weight", Pdk.Ops.Minimum_weight_position;
      "Maximum weight", Pdk.Ops.Maximum_weight_position;
    ]

  let attributes_parameter = Parameter.choice ~equal:( = ) [
      "Keep first", Pdk.Ops.Keep_first;
      "Average numeric", Pdk.Ops.Average_numeric;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    spacing_x : float [@sop.default 1.] [@sop.label "Spacing X"]
      [@sop.folder "Grid/Spacing"] [@sop.min 0.001] [@sop.max 10.]
      [@sop.hard_min 0.];
    spacing_y : float [@sop.default 1.] [@sop.label "Spacing Y"]
      [@sop.folder "Grid/Spacing"] [@sop.min 0.001] [@sop.max 10.]
      [@sop.hard_min 0.];
    spacing_z : float [@sop.default 1.] [@sop.label "Spacing Z"]
      [@sop.folder "Grid/Spacing"] [@sop.min 0.001] [@sop.max 10.]
      [@sop.hard_min 0.];
    offset_x : float [@sop.default 0.] [@sop.label "Offset X"]
      [@sop.folder "Grid/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    offset_y : float [@sop.default 0.] [@sop.label "Offset Y"]
      [@sop.folder "Grid/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    offset_z : float [@sop.default 0.] [@sop.label "Offset Z"]
      [@sop.folder "Grid/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    rounding : Pdk.Ops.grid_rounding [@sop.default Pdk.Ops.Grid_nearest]
      [@sop.label "Rounding"] [@sop.kind rounding_parameter];
    limit_distance : bool [@sop.default false]
      [@sop.label "Limit snapping distance"];
    max_distance : float [@sop.default 1.] [@sop.label "Maximum distance"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
    fuse_points : bool [@sop.default false] [@sop.label "Fuse points"]
      [@sop.folder "Fuse"];
    position : Pdk.Ops.fuse_position
      [@sop.default Pdk.Ops.Average_position]
      [@sop.label "Position"] [@sop.folder "Fuse"]
      [@sop.kind position_parameter];
    weight_attribute : string [@sop.default ""]
      [@sop.label "Weight attribute"] [@sop.folder "Fuse"];
    attributes : Pdk.Ops.fuse_attributes
      [@sop.default Pdk.Ops.Keep_first]
      [@sop.label "Attributes"] [@sop.folder "Fuse"]
      [@sop.kind attributes_parameter];
    snapped_group : string [@sop.default ""] [@sop.label "Snapped group"]
      [@sop.folder "Output"];
  } [@@sop.node_key "snap_to_grid"] [@@sop.node_label "Snap to Grid"]
    [@@sop.node_category "Point"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let max_distance = if parameters.limit_distance
          then Some parameters.max_distance else None in
        Sop.snap_to_grid ~label ?group:(optional_text parameters.group)
          ~spacing:(Vec3.create parameters.spacing_x parameters.spacing_y
            parameters.spacing_z)
          ~offset:(Vec3.create parameters.offset_x parameters.offset_y
            parameters.offset_z) ~rounding:parameters.rounding ?max_distance
          ~fuse_points:parameters.fuse_points ~position:parameters.position
          ?weight_attribute:(optional_text parameters.weight_attribute)
          ~attributes:parameters.attributes
          ?snapped_group:(optional_text parameters.snapped_group) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Snap_to_grid expects one input"

  let factory = parameters_factory build
  let create ?label:node_label ?(group = "")
      ?(spacing = Vec3.create 1. 1. 1.) ?(offset = Vec3.zero)
      ?(rounding = Pdk.Ops.Grid_nearest) ?max_distance ?(fuse_points = false)
      ?(position = Pdk.Ops.Average_position) ?(weight_attribute = "")
      ?(attributes = Pdk.Ops.Keep_first) ?(snapped_group = "") input =
    build ~label:(label "snap-to-grid" node_label) ~inputs:[input] {
      group; spacing_x = spacing.x; spacing_y = spacing.y;
      spacing_z = spacing.z; offset_x = offset.x; offset_y = offset.y;
      offset_z = offset.z; rounding; limit_distance = Option.is_some max_distance;
      max_distance = Option.value ~default:1. max_distance; fuse_points;
      position; weight_attribute; attributes; snapped_group }
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          ~target_length:parameters.target_length input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Remesh expects one input"

  let factory = parameters_factory build
  let create ?label:node_label ?(target_length = 0.1) input =
    build ~label:(label "remesh" node_label) ~inputs:[input]
      { parameters_default with target_length }
end [@@sop.register]

module Poly_extrude = struct
  let divide_parameter = Parameter.choice ~equal:( = ) [
      "Individual elements", Pdk.Ops.Extrude_individual;
      "Connected components", Pdk.Ops.Extrude_connected_components;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    split_edges : string [@sop.default ""] [@sop.label "Split edge group"];
    distance : float [@sop.default 0.1] [@sop.label "Distance"]
      [@sop.min (-10.)] [@sop.max 10.];
    divide : Pdk.Ops.poly_extrude_divide
      [@sop.default Pdk.Ops.Extrude_individual]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          ~distance:parameters.distance input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Poly_extrude expects one input"

  let factory = parameters_factory build
  let create ?label:node_label ?(distance = 0.1) input =
    build ~label:(label "poly-extrude" node_label) ~inputs:[input]
      { parameters_default with distance }
end [@@sop.register]

module Poly_fill = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Single polygon", Pdk.Ops.Fill_single_polygon;
      "Triangles", Pdk.Ops.Fill_triangles;
      "Triangle fan", Pdk.Ops.Fill_triangle_fan;
    ]

  type parameters = {
    boundary_group : string [@sop.default ""] [@sop.label "Boundary group"];
    mode : Pdk.Ops.poly_fill_mode [@sop.default Pdk.Ops.Fill_triangles]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.poly_fill ~label
          ?boundary_group:(optional_text parameters.boundary_group)
          ~mode:parameters.mode ~reverse_patches:parameters.reverse_patches
          ~unique_points:parameters.unique_points
          ~update_point_normals:parameters.update_point_normals
          ?patch_group:(optional_text parameters.patch_group) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Poly_fill expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "poly-fill" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.convert_line ~label ?group:(optional_text parameters.group)
          ~connect_path:parameters.connect_path
          ~maximum_distance:parameters.maximum_distance
          ~connect_only_to_other_end_points:
            parameters.connect_only_to_other_end_points
          ~make_isolated_loops_closed:parameters.make_isolated_loops_closed
          ~remove_unused_points:parameters.remove_unused_points
          ?length_attribute:(optional_text parameters.length_attribute) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Convert_line expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "convert-line" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          ?tangent_attribute:(optional_text parameters.tangent_attribute) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Resample expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "resample" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Carve = struct
  let attribute_mode_parameter = Parameter.choice ~equal:( = ) [
      "Replace", Pdk.Ops.Attribute_replace;
      "Scale", Pdk.Ops.Attribute_scale;
    ]
  let keep_parameter = Parameter.choice ~equal:( = ) [
      "Inside", Pdk.Ops.Keep_inside;
      "Outside", Pdk.Ops.Keep_outside;
      "Inside and outside", Pdk.Ops.Keep_inside_and_outside;
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
    attribute_mode : Pdk.Ops.carve_attribute_mode
      [@sop.default Pdk.Ops.Attribute_replace]
      [@sop.label "Attribute mode"] [@sop.folder "Attributes"]
      [@sop.kind attribute_mode_parameter];
    only_at_breakpoints : bool [@sop.default false]
      [@sop.label "Only at breakpoints"];
    cut_at_all_internal_breakpoints : bool [@sop.default false]
      [@sop.label "Cut at internal breakpoints"];
    keep : Pdk.Ops.carve_keep [@sop.default Pdk.Ops.Keep_inside]
      [@sop.label "Keep"] [@sop.kind keep_parameter];
    extract_points : bool [@sop.default false] [@sop.label "Extract points"];
    divisions : int [@sop.default 1] [@sop.label "Divisions"]
      [@sop.min 1] [@sop.max 256] [@sop.hard_min 1];
    keep_original : bool [@sop.default false] [@sop.label "Keep original"];
  } [@@sop.node_key "carve"] [@@sop.node_label "Carve"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Carve expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "carve" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

module Ends = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Open", Pdk.Ops.Ends_open;
      "Close straight", Pdk.Ops.Ends_close_straight;
      "Unroll shared point", Pdk.Ops.Ends_unroll_shared;
      "Unroll new point", Pdk.Ops.Ends_unroll_new;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    mode : Pdk.Ops.ends_mode [@sop.default Pdk.Ops.Ends_open]
      [@sop.label "U end"] [@sop.kind mode_parameter];
  } [@@sop.node_key "ends"] [@@sop.node_label "Ends"]
    [@@sop.node_category "Topology/Curve"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.ends ~label ?group:(optional_text parameters.group)
          parameters.mode input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Ends expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "ends" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let group_size = if parameters.use_group_size
          then Some parameters.group_size else None in
        Sop.join_curves ~label ?group:(optional_text parameters.group)
          ~orient_closest:parameters.orient_closest
          ~connect_closest_ends:parameters.connect_closest_ends
          ~only_connected:parameters.only_connected ?group_size
          ~keep_originals:parameters.keep_originals
          ~tolerance:parameters.tolerance ~wrap:parameters.wrap input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Join_curves expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "join-curves" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.poly_path ~label ~connect_end_points:parameters.connect_end_points
          ~maximum_distance:parameters.maximum_distance
          ~connect_only_to_other_end_points:
            parameters.connect_only_to_other_end_points
          ~make_isolated_loops_closed:parameters.make_isolated_loops_closed input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Poly_path expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "poly-path" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Point_generate = struct
  type parameters = {
    points : int [@sop.default 50] [@sop.label "Points"]
      [@sop.min 1] [@sop.max 50] [@sop.hard_min 1] [@sop.hard_max 50];
  } [@@sop.node_key "points"] [@@sop.node_label "Point Generate"]
    [@@sop.node_operation "point_generate"]
    [@@sop.node_category "Create/Point"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs:_ parameters =
    Sop.point_generate_origin ~label ~points:parameters.points ()
    |> Node.parameterize ~schema:parameters_schema ~values:parameters
         ~rebuild:build

  let factory = parameters_factory build

  let origin ?label:node_label ~points () =
    build ~label:(label "point-generate" node_label) ~inputs:[] { points }
end [@@sop.register]

module Attribute_noise_quaternion = struct
  type parameters = {
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.min 0]
      [@sop.max 9999];
    frequency_x : float [@sop.default 1.] [@sop.label "Frequency X"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.];
    frequency_y : float [@sop.default 1.] [@sop.label "Frequency Y"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.];
    frequency_z : float [@sop.default 1.] [@sop.label "Frequency Z"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.];
    octaves : int [@sop.default 1] [@sop.label "Octaves"]
      [@sop.min 1] [@sop.max 8] [@sop.hard_min 1];
  } [@@sop.node_key "attribute_noise_quaternion"]
    [@@sop.node_operation "attribute_noise"]
    [@@sop.node_label "Attribute Noise (Quaternion)"]
    [@@sop.node_category "Attribute/Noise"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~group ~location ~range ~owner ~name ~label ~inputs parameters =
    match inputs with
    | [input] ->
        Sop.attribute_noise ~label ?group ~seed:parameters.seed ~location ~range
          ~frequency:(Vec3.create parameters.frequency_x parameters.frequency_y
            parameters.frequency_z) ~octaves:parameters.octaves ~owner ~name
          Pdk.Attribute_ops.Noise_quaternion input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:(build ~group ~location ~range ~owner ~name)
    | _ -> invalid_arg "Sop_catalog.Attribute_noise_quaternion expects one input"

  let factory = parameters_factory
      (build ~group:None ~location:Pdk.Attribute_ops.Noise_element_number
         ~range:Pdk.Attribute_ops.Noise_zero_centered
         ~owner:Pdk.Attribute.Point ~name:"orient")

  let create ?label:node_label ?group
      ?(location = Pdk.Attribute_ops.Noise_position)
      ?(range = Pdk.Attribute_ops.Noise_positive) ~owner ~name ~seed ~frequency
      ~octaves input =
    build ~group ~location ~range ~owner ~name
      ~label:(label "attribute-noise-quaternion" node_label) ~inputs:[input] {
        seed; frequency_x = frequency.Vec3.x; frequency_y = frequency.y;
        frequency_z = frequency.z; octaves }
end [@@sop.register]

module Point_jitter = struct
  type parameters = {
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.min 0]
      [@sop.max 9999];
    scale : float [@sop.default 1.] [@sop.label "Scale"]
      [@sop.min 0.] [@sop.max 2.] [@sop.hard_min 0.];
    axis_x : float [@sop.default 1.] [@sop.label "Axis X"]
      [@sop.folder "Axis scales"] [@sop.min 0.] [@sop.max 2.]
      [@sop.hard_min 0.];
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Axis scales"] [@sop.min 0.] [@sop.max 2.]
      [@sop.hard_min 0.];
    axis_z : float [@sop.default 1.] [@sop.label "Axis Z"]
      [@sop.folder "Axis scales"] [@sop.min 0.] [@sop.max 2.]
      [@sop.hard_min 0.];
  } [@@sop.node_key "point_jitter"] [@@sop.node_label "Point Jitter"]
    [@@sop.node_category "Point"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~group ~mask_attribute ~id_attribute ~label ~inputs parameters =
    match inputs with
    | [input] ->
        Sop.point_jitter ~label ?group ?mask_attribute ?id_attribute
          ~seed:parameters.seed ~scale:parameters.scale
          ~axis_scales:(Vec3.create parameters.axis_x parameters.axis_y
            parameters.axis_z) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:(build ~group ~mask_attribute ~id_attribute)
    | _ -> invalid_arg "Sop_catalog.Point_jitter expects one input"

  let factory = parameters_factory
      (build ~group:None ~mask_attribute:None ~id_attribute:None)

  let create ?label:node_label ?group ?mask_attribute ?id_attribute ~seed ~scale
      ?(axis_scales = Vec3.create 1. 1. 1.) input =
    build ~group ~mask_attribute ~id_attribute
      ~label:(label "point-jitter" node_label) ~inputs:[input] {
        seed; scale; axis_x = axis_scales.Vec3.x; axis_y = axis_scales.y;
        axis_z = axis_scales.z }
end [@@sop.register]

module Boolean_fracture = struct
  type parameters = {
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
    [@@sop.node_category "Boolean"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]

  let rec build ~resolve_cutter_self_intersections ~detriangulation
      ~require_closed ~piece_attribute ~label ~inputs parameters =
    match inputs with
    | [source; cutters] ->
        Sop.boolean_fracture ~label ~resolve_cutter_self_intersections
          ~point_tolerance:parameters.point_tolerance
          ~tiny_seam_threshold:parameters.tiny_seam_threshold
          ~cleanup_max_batches:parameters.cleanup_max_batches
          ~strict_cleanup:parameters.strict_cleanup ~detriangulation
          ~require_closed ~piece_attribute ~cutters source
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:(build ~resolve_cutter_self_intersections ~detriangulation
               ~require_closed ~piece_attribute)
    | _ -> invalid_arg "Sop_catalog.Boolean_fracture expects source and cutters"

  let factory = parameters_factory
      (build ~resolve_cutter_self_intersections:false
         ~detriangulation:Pdk.Boolean.Triangles ~require_closed:true
         ~piece_attribute:"piece")

  let create ?label:node_label ?(resolve_cutter_self_intersections = false)
      ?(detriangulation = Pdk.Boolean.Triangles) ?(require_closed = true)
      ?(piece_attribute = "piece") ~cutters source =
    build ~resolve_cutter_self_intersections ~detriangulation ~require_closed
      ~piece_attribute ~label:(label "boolean-fracture" node_label)
      ~inputs:[source; cutters] parameters_default
end [@@sop.register]

module Boolean = struct
  type closed_policy = Closed_default | Closed_required | Closed_not_required

  let operation_parameter = Parameter.choice ~equal:( = ) [
      "Union", Pdk.Boolean.Union;
      "Intersection", Pdk.Boolean.Intersection;
      "Subtract B from A", Pdk.Boolean.Difference;
      "Subtract A from B", Pdk.Boolean.Reverse_difference;
      "Exclusive or", Pdk.Boolean.Xor;
      "Shatter", Pdk.Boolean.Shatter;
    ]
  let treatment_parameter = Parameter.choice ~equal:( = ) [
      "Solid", Pdk.Boolean.Solid; "Surface", Pdk.Boolean.Surface;
    ]
  let conflict_parameter = Parameter.choice ~equal:( = ) [
      "Reject conflict", Pdk.Boolean.Reject;
      "Promote to vertex", Pdk.Boolean.Promote_to_vertex;
    ]
  let seam_points_parameter = Parameter.choice ~equal:( = ) [
      "Shared", Pdk.Boolean.Shared_seam_points;
      "Split", Pdk.Boolean.Split_seam_points;
    ]
  let detriangulation_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Pdk.Boolean.Triangles;
      "Unchanged polygons", Pdk.Boolean.Unchanged_polygons;
      "All polygons", Pdk.Boolean.All_polygons;
    ]
  let closed_parameter = Parameter.choice ~equal:( = ) [
      "Operation default", Closed_default;
      "Require closed", Closed_required;
      "Allow open", Closed_not_required;
    ]

  type parameters = {
    operation : Pdk.Boolean.operation [@sop.default Pdk.Boolean.Union]
      [@sop.label "Operation"] [@sop.kind operation_parameter];
    left_treatment : Pdk.Boolean.treatment [@sop.default Pdk.Boolean.Solid]
      [@sop.label "A treatment"] [@sop.folder "Operands"]
      [@sop.kind treatment_parameter];
    right_treatment : Pdk.Boolean.treatment [@sop.default Pdk.Boolean.Solid]
      [@sop.label "B treatment"] [@sop.folder "Operands"]
      [@sop.kind treatment_parameter];
    resolve_left_self_intersections : bool [@sop.default false]
      [@sop.label "Resolve A self-intersections"] [@sop.folder "Operands"];
    resolve_right_self_intersections : bool [@sop.default false]
      [@sop.label "Resolve B self-intersections"] [@sop.folder "Operands"];
    point_conflict : Pdk.Boolean.point_conflict
      [@sop.default Pdk.Boolean.Promote_to_vertex]
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
    seam_points : Pdk.Boolean.seam_points
      [@sop.default Pdk.Boolean.Shared_seam_points]
      [@sop.label "Seam points"] [@sop.folder "Output"]
      [@sop.kind seam_points_parameter];
    detriangulation : Pdk.Boolean.detriangulation
      [@sop.default Pdk.Boolean.Triangles]
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
    [@@sop.node_category "Boolean"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]

  let require_closed = function
    | Closed_default -> None | Closed_required -> Some true
    | Closed_not_required -> Some false

  let rec build ~label ~inputs parameters = match inputs with
    | [left; right] ->
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
          ~right left
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Boolean expects A and B inputs"

  let factory = parameters_factory build
  let create ?label:node_label ~right left =
    build ~label:(label "boolean" node_label) ~inputs:[left; right]
      parameters_default
end [@@sop.register]

module Boolean_seam = struct
  let output_parameter = Parameter.choice ~equal:( = ) [
      "Seam curves", Pdk.Boolean.Seam_curves;
      "Coincident patches", Pdk.Boolean.Coincident_patches;
    ]
  let treatment_parameter = Parameter.choice ~equal:( = ) [
      "Solid", Pdk.Boolean.Solid; "Surface", Pdk.Boolean.Surface;
    ]

  type parameters = {
    output : Pdk.Boolean.seam_output [@sop.default Pdk.Boolean.Seam_curves]
      [@sop.label "Output"] [@sop.kind output_parameter];
    left_treatment : Pdk.Boolean.treatment [@sop.default Pdk.Boolean.Solid]
      [@sop.label "A treatment"] [@sop.folder "Operands"]
      [@sop.kind treatment_parameter];
    right_treatment : Pdk.Boolean.treatment [@sop.default Pdk.Boolean.Solid]
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
    [@@sop.node_category "Boolean/Analysis"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [left; right] ->
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
          ~right left
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Boolean_seam expects A and B inputs"

  let factory = parameters_factory build
  let create ?label:node_label ~right left =
    build ~label:(label "boolean-seam" node_label) ~inputs:[left; right]
      parameters_default
end [@@sop.register]

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
    [@@sop.node_category "Boolean/Analysis"] [@@sop.node_inputs 2]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; collision] ->
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
          ?collision input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild
    | _ -> invalid_arg "Sop_catalog.Boolean_detect requires its source input"

  and rebuild ~label ~inputs parameters = match inputs with
    | [input] -> build_slots ~label ~inputs:[Some input; None] parameters
    | [input; collision] ->
        build_slots ~label ~inputs:[Some input; Some collision] parameters
    | _ -> invalid_arg "Sop_catalog.Boolean_detect has invalid physical inputs"

  let factory = parameters_factory build_slots
  let create ?label:node_label ?collision input =
    build_slots ~label:(label "boolean-detect" node_label)
      ~inputs:[Some input; collision] parameters_default
end [@@sop.register]

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
    [@@sop.node_category "Boolean/Analysis"] [@@sop.node_inputs 2]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; collision] ->
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
          ?collision input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild
    | _ -> invalid_arg
        "Sop_catalog.Intersection_analysis requires its source input"

  and rebuild ~label ~inputs parameters = match inputs with
    | [input] -> build_slots ~label ~inputs:[Some input; None] parameters
    | [input; collision] ->
        build_slots ~label ~inputs:[Some input; Some collision] parameters
    | _ -> invalid_arg
        "Sop_catalog.Intersection_analysis has invalid physical inputs"

  let factory = parameters_factory build_slots
  let create ?label:node_label ?collision input =
    build_slots ~label:(label "intersection-analysis" node_label)
      ~inputs:[Some input; collision] parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let target = match parameters.target_mode with
          | Ratio -> Pdk.Ops.Reduce_ratio parameters.ratio
          | Primitive_count ->
              Pdk.Ops.Reduce_primitive_count parameters.primitive_count in
        let max_normal_deviation = if parameters.limit_normal_deviation
          then Some parameters.max_normal_deviation else None in
        Sop.poly_reduce ~label ?group:(optional_text parameters.group)
          ?hard_point_group:(optional_text parameters.hard_point_group)
          ?hard_edge_group:(optional_text parameters.hard_edge_group) ~target
          ~preserve_boundary:parameters.preserve_boundary
          ~only_original_positions:parameters.only_original_positions
          ~equalize_lengths:parameters.equalize_lengths ?max_normal_deviation
          ?output_group:(optional_text parameters.output_group)
          ~recompute_point_normals:parameters.recompute_point_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Poly_reduce expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "poly-reduce" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Measure_curvature = struct
  let boundary_parameter = Parameter.choice ~equal:( = ) [
      "Zero", Pdk.Ops.Curvature_boundary_zero;
      "One-sided", Pdk.Ops.Curvature_boundary_one_sided;
    ]

  type parameters = {
    point_group : string [@sop.default ""] [@sop.label "Point group"];
    boundary : Pdk.Ops.curvature_boundary
      [@sop.default Pdk.Ops.Curvature_boundary_zero]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let outputs : Pdk.Ops.curvature_outputs = {
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
          ~smoothing_strength:parameters.smoothing_strength ~outputs input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Measure_curvature expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "measure-curvature" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Attribute_laplacian = struct
  let weighting_parameter = Parameter.choice ~equal:( = ) [
      "Cotangent", Pdk.Ops.Laplacian_cotan;
      "Positive cotangent", Pdk.Ops.Laplacian_positive_cotan;
      "Uniform", Pdk.Ops.Laplacian_uniform;
    ]

  type parameters = {
    point_group : string [@sop.default ""] [@sop.label "Point group"];
    weighting : Pdk.Ops.laplacian_weighting
      [@sop.default Pdk.Ops.Laplacian_cotan]
      [@sop.label "Weighting"] [@sop.kind weighting_parameter];
    normalize : bool [@sop.default true] [@sop.label "Normalize"];
    source : string [@sop.default "P"] [@sop.label "Source attribute"];
    output : string [@sop.default "laplacian"] [@sop.label "Output attribute"];
  } [@@sop.node_key "attribute_laplacian"]
    [@@sop.node_label "Attribute Laplacian"]
    [@@sop.node_category "Attribute/Filter"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.attribute_laplacian ~label
          ?point_group:(optional_text parameters.point_group)
          ~weighting:parameters.weighting ~normalize:parameters.normalize
          ~source:parameters.source ?output:(optional_text parameters.output)
          input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_laplacian expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "attribute-laplacian" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
    | Style_first_edge -> Pdk.Ops.First_edge
    | Style_two_edges -> Pdk.Ops.Two_edges
    | Style_centroid -> Pdk.Ops.Primitive_centroid
    | Style_texture_uv -> Pdk.Ops.Texture_uv parameters.style_attribute
    | Style_texture_uv_gradient ->
        Pdk.Ops.Texture_uv_gradient parameters.style_attribute
    | Style_attribute_gradient ->
        Pdk.Ops.Attribute_gradient parameters.style_attribute

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.polyframe ~label
          ?selection:(optional_element_group parameters.group_owner
            parameters.group)
          ~orthogonal:parameters.orthogonal ~left_handed:parameters.left_handed
          ~normal_attribute:parameters.normal_attribute
          ~tangent_attribute:(optional_text parameters.tangent_attribute)
          ~bitangent_attribute:(optional_text parameters.bitangent_attribute)
          (style parameters) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Polyframe expects one input"

  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "polyframe" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Duplicate = struct
  type parameters = {
    copies : int [@sop.default 1] [@sop.label "Copies"]
      [@sop.min 1] [@sop.max 1024] [@sop.hard_min 0];
    cumulative : bool [@sop.default true] [@sop.label "Cumulative transform"];
    m00 : float [@sop.default 1.] [@sop.label "M00"]
      [@sop.folder "Transform/Row 0"] [@sop.min (-10.)] [@sop.max 10.];
    m01 : float [@sop.default 0.] [@sop.label "M01"]
      [@sop.folder "Transform/Row 0"] [@sop.min (-10.)] [@sop.max 10.];
    m02 : float [@sop.default 0.] [@sop.label "M02"]
      [@sop.folder "Transform/Row 0"] [@sop.min (-10.)] [@sop.max 10.];
    m03 : float [@sop.default 0.] [@sop.label "M03"]
      [@sop.folder "Transform/Row 0"] [@sop.min (-10.)] [@sop.max 10.];
    m10 : float [@sop.default 0.] [@sop.label "M10"]
      [@sop.folder "Transform/Row 1"] [@sop.min (-10.)] [@sop.max 10.];
    m11 : float [@sop.default 1.] [@sop.label "M11"]
      [@sop.folder "Transform/Row 1"] [@sop.min (-10.)] [@sop.max 10.];
    m12 : float [@sop.default 0.] [@sop.label "M12"]
      [@sop.folder "Transform/Row 1"] [@sop.min (-10.)] [@sop.max 10.];
    m13 : float [@sop.default 0.] [@sop.label "M13"]
      [@sop.folder "Transform/Row 1"] [@sop.min (-10.)] [@sop.max 10.];
    m20 : float [@sop.default 0.] [@sop.label "M20"]
      [@sop.folder "Transform/Row 2"] [@sop.min (-10.)] [@sop.max 10.];
    m21 : float [@sop.default 0.] [@sop.label "M21"]
      [@sop.folder "Transform/Row 2"] [@sop.min (-10.)] [@sop.max 10.];
    m22 : float [@sop.default 1.] [@sop.label "M22"]
      [@sop.folder "Transform/Row 2"] [@sop.min (-10.)] [@sop.max 10.];
    m23 : float [@sop.default 0.] [@sop.label "M23"]
      [@sop.folder "Transform/Row 2"] [@sop.min (-10.)] [@sop.max 10.];
    m30 : float [@sop.default 0.] [@sop.label "M30"]
      [@sop.folder "Transform/Row 3"] [@sop.min (-10.)] [@sop.max 10.];
    m31 : float [@sop.default 0.] [@sop.label "M31"]
      [@sop.folder "Transform/Row 3"] [@sop.min (-10.)] [@sop.max 10.];
    m32 : float [@sop.default 0.] [@sop.label "M32"]
      [@sop.folder "Transform/Row 3"] [@sop.min (-10.)] [@sop.max 10.];
    m33 : float [@sop.default 1.] [@sop.label "M33"]
      [@sop.folder "Transform/Row 3"] [@sop.min (-10.)] [@sop.max 10.];
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    copy_group_prefix : string [@sop.default ""]
      [@sop.label "Copy group prefix"] [@sop.folder "Output"];
    preserve_groups : bool [@sop.default false]
      [@sop.label "Preserve groups"] [@sop.folder "Output"];
  } [@@sop.node_key "duplicate"] [@@sop.node_label "Duplicate"]
    [@@sop.node_category "Copy"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let matrix parameters = Mat4.of_rows
      (parameters.m00, parameters.m01, parameters.m02, parameters.m03)
      (parameters.m10, parameters.m11, parameters.m12, parameters.m13)
      (parameters.m20, parameters.m21, parameters.m22, parameters.m23)
      (parameters.m30, parameters.m31, parameters.m32, parameters.m33)

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.duplicate ~label ~copies:parameters.copies
          ~cumulative:parameters.cumulative ~transform:(matrix parameters)
          ?group:(optional_text parameters.group)
          ?copy_group_prefix:(optional_text parameters.copy_group_prefix)
          ~preserve_groups:parameters.preserve_groups input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Duplicate expects one input"

  let factory = parameters_factory build

  let create ?label:node_label ?(copies = 1) ?(cumulative = true)
      ?(transform = Mat4.identity) ?(group = "") ?(copy_group_prefix = "")
      ?(preserve_groups = false) input =
    let (m00,m01,m02,m03), (m10,m11,m12,m13),
        (m20,m21,m22,m23), (m30,m31,m32,m33) = Mat4.to_rows transform in
    build ~label:(label "duplicate" node_label) ~inputs:[input] {
      copies; cumulative; m00; m01; m02; m03; m10; m11; m12; m13;
      m20; m21; m22; m23; m30; m31; m32; m33; group;
      copy_group_prefix; preserve_groups }
end [@@sop.register]

module Match_axis = struct
  type parameters = {
    from_x : float [@sop.default 0.] [@sop.label "From X"]
      [@sop.folder "From"] [@sop.min (-1.)] [@sop.max 1.];
    from_y : float [@sop.default 1.] [@sop.label "From Y"]
      [@sop.folder "From"] [@sop.min (-1.)] [@sop.max 1.];
    from_z : float [@sop.default 0.] [@sop.label "From Z"]
      [@sop.folder "From"] [@sop.min (-1.)] [@sop.max 1.];
    into_x : float [@sop.default 0.] [@sop.label "Into X"]
      [@sop.folder "Into"] [@sop.min (-1.)] [@sop.max 1.];
    into_y : float [@sop.default 1.] [@sop.label "Into Y"]
      [@sop.folder "Into"] [@sop.min (-1.)] [@sop.max 1.];
    into_z : float [@sop.default 0.] [@sop.label "Into Z"]
      [@sop.folder "Into"] [@sop.min (-1.)] [@sop.max 1.];
  } [@@sop.node_key "match_axis"] [@@sop.node_label "Match Axis"]
    [@@sop.node_category "Modify/Align"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.match_axis ~label
          ~from:(Vec3.create parameters.from_x parameters.from_y
            parameters.from_z)
          ~into:(Vec3.create parameters.into_x parameters.into_y
            parameters.into_z) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Match_axis expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "match-axis" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.convex_hull ~label
          ?selection:(optional_element_group parameters.group_owner
            parameters.group)
          ~preserve_point_payload:parameters.preserve_point_payload
          ?source_point_attribute:
            (optional_text parameters.source_point_attribute)
          ?hull_group:(optional_text parameters.hull_group) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Convex_hull expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "convex-hull" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Extract_centroid = struct
  type run_mode = Detail | Primitives | Point_pieces | Primitive_pieces
  let run_parameter = Parameter.choice ~equal:( = ) [
      "Detail", Detail; "Primitives", Primitives;
      "Point pieces", Point_pieces; "Primitive pieces", Primitive_pieces;
    ]
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Point mass", Pdk.Ops.Centroid_point_mass;
      "Bounding box", Pdk.Ops.Centroid_bounding_box;
      "Convex hull", Pdk.Ops.Centroid_convex_hull;
    ]

  type parameters = {
    run_over : run_mode [@sop.default Detail]
      [@sop.label "Run over"] [@sop.kind run_parameter];
    piece_attribute : string [@sop.default "piece"]
      [@sop.label "Piece attribute"];
    method_ : Pdk.Ops.centroid_method
      [@sop.default Pdk.Ops.Centroid_point_mass]
      [@sop.label "Method"] [@sop.kind method_parameter];
    source_primitive_attribute : string [@sop.default ""]
      [@sop.label "Source primitive attribute"] [@sop.folder "Output"];
    piece_output_attribute : string [@sop.default ""]
      [@sop.label "Piece output attribute"] [@sop.folder "Output"];
  } [@@sop.node_key "extract_centroid"]
    [@@sop.node_label "Extract Centroid"]
    [@@sop.node_category "Create/Point"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let run_over parameters = match parameters.run_over with
    | Detail -> Pdk.Ops.Centroid_detail
    | Primitives -> Pdk.Ops.Centroid_primitives
    | Point_pieces -> Pdk.Ops.Centroid_pieces {
        owner = Pdk.Ops.Centroid_piece_points;
        attribute = parameters.piece_attribute }
    | Primitive_pieces -> Pdk.Ops.Centroid_pieces {
        owner = Pdk.Ops.Centroid_piece_primitives;
        attribute = parameters.piece_attribute }

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.extract_centroid ~label ~run_over:(run_over parameters)
          ~method_:parameters.method_
          ?source_primitive_attribute:
            (optional_text parameters.source_primitive_attribute)
          ?piece_output_attribute:
            (optional_text parameters.piece_output_attribute) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Extract_centroid expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "extract-centroid" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Bound = struct
  type shape = Box | Sphere
  let shape_parameter = Parameter.choice ~equal:( = ) [
      "Box", Box; "Sphere", Sphere;
    ]

  type parameters = {
    group_owner : element_owner [@sop.default Element_point]
      [@sop.label "Group type"] [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    shape : shape [@sop.default Box] [@sop.label "Shape"]
      [@sop.kind shape_parameter];
    divisions_x : int [@sop.default 1] [@sop.label "X divisions"]
      [@sop.folder "Box"] [@sop.min 1] [@sop.max 64] [@sop.hard_min 1];
    divisions_y : int [@sop.default 1] [@sop.label "Y divisions"]
      [@sop.folder "Box"] [@sop.min 1] [@sop.max 64] [@sop.hard_min 1];
    divisions_z : int [@sop.default 1] [@sop.label "Z divisions"]
      [@sop.folder "Box"] [@sop.min 1] [@sop.max 64] [@sop.hard_min 1];
    segments : int [@sop.default 32] [@sop.label "Segments"]
      [@sop.folder "Sphere"] [@sop.min 3] [@sop.max 256]
      [@sop.hard_min 3];
    rings : int [@sop.default 16] [@sop.label "Rings"]
      [@sop.folder "Sphere"] [@sop.min 2] [@sop.max 256]
      [@sop.hard_min 2];
    minimum_radius : float [@sop.default 0.] [@sop.label "Minimum radius"]
      [@sop.folder "Sphere"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    lower_x : float [@sop.default 0.] [@sop.label "Lower X"]
      [@sop.folder "Padding/Lower"] [@sop.min (-10.)] [@sop.max 10.];
    lower_y : float [@sop.default 0.] [@sop.label "Lower Y"]
      [@sop.folder "Padding/Lower"] [@sop.min (-10.)] [@sop.max 10.];
    lower_z : float [@sop.default 0.] [@sop.label "Lower Z"]
      [@sop.folder "Padding/Lower"] [@sop.min (-10.)] [@sop.max 10.];
    upper_x : float [@sop.default 0.] [@sop.label "Upper X"]
      [@sop.folder "Padding/Upper"] [@sop.min (-10.)] [@sop.max 10.];
    upper_y : float [@sop.default 0.] [@sop.label "Upper Y"]
      [@sop.folder "Padding/Upper"] [@sop.min (-10.)] [@sop.max 10.];
    upper_z : float [@sop.default 0.] [@sop.label "Upper Z"]
      [@sop.folder "Padding/Upper"] [@sop.min (-10.)] [@sop.max 10.];
    bounds_group : string [@sop.default ""] [@sop.label "Bounds group"]
      [@sop.folder "Output"];
    center_attribute : string [@sop.default ""] [@sop.label "Center attribute"]
      [@sop.folder "Output"];
    radii_attribute : string [@sop.default ""] [@sop.label "Radii attribute"]
      [@sop.folder "Output"];
  } [@@sop.node_key "bound"] [@@sop.node_label "Bound"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let shape parameters = match parameters.shape with
    | Box -> Pdk.Ops.Bound_box { divisions =
        parameters.divisions_x, parameters.divisions_y, parameters.divisions_z }
    | Sphere -> Pdk.Ops.Bound_sphere { segments = parameters.segments;
        rings = parameters.rings; minimum_radius = parameters.minimum_radius }

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.bound ~label
          ?selection:(optional_element_group parameters.group_owner
            parameters.group) ~shape:(shape parameters)
          ~lower_padding:(Vec3.create parameters.lower_x parameters.lower_y
            parameters.lower_z)
          ~upper_padding:(Vec3.create parameters.upper_x parameters.upper_y
            parameters.upper_z)
          ?bounds_group:(optional_text parameters.bounds_group)
          ?center_attribute:(optional_text parameters.center_attribute)
          ?radii_attribute:(optional_text parameters.radii_attribute) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Bound expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "bound" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

module Fuse = struct
  type targeting_mode = Near_points | Specified_points
  let targeting_parameter = Parameter.choice ~equal:( = ) [
      "Near points", Near_points; "Specified points", Specified_points;
    ]
  let using_parameter = Parameter.choice ~equal:( = ) [
      "Least target point", Pdk.Ops.Least_target_point;
      "Closest target point", Pdk.Ops.Closest_target_point;
    ]
  let position_parameter = Parameter.choice ~equal:( = ) [
      "First", Pdk.Ops.First_position;
      "Least point", Pdk.Ops.Least_point_position;
      "Greatest point", Pdk.Ops.Greatest_point_position;
      "Average", Pdk.Ops.Average_position;
      "Minimum", Pdk.Ops.Minimum_position;
      "Maximum", Pdk.Ops.Maximum_position;
      "Mode", Pdk.Ops.Mode_position;
      "Median", Pdk.Ops.Median_position;
      "Sum", Pdk.Ops.Sum_position;
      "Sum squares", Pdk.Ops.Sum_squares_position;
      "Root mean square", Pdk.Ops.Root_mean_square_position;
      "Weighted average", Pdk.Ops.Weighted_average_position;
      "Weighted sum", Pdk.Ops.Weighted_sum_position;
      "Minimum weight", Pdk.Ops.Minimum_weight_position;
      "Maximum weight", Pdk.Ops.Maximum_weight_position;
    ]
  let attributes_parameter = Parameter.choice ~equal:( = ) [
      "Keep first", Pdk.Ops.Keep_first;
      "Average numeric", Pdk.Ops.Average_numeric;
    ]
  let metric_parameter = Parameter.choice ~equal:( = ) [
      "Euclidean", Pdk.Ops.Euclidean;
      "Componentwise", Pdk.Ops.Componentwise;
    ]
  let condition_parameter = Parameter.choice ~equal:( = ) [
      "Equal", Pdk.Ops.Equal_attribute_values;
      "Unequal", Pdk.Ops.Unequal_attribute_values;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    target_group : string [@sop.default ""] [@sop.label "Target group"];
    targeting : targeting_mode [@sop.default Near_points]
      [@sop.label "Targeting"] [@sop.kind targeting_parameter];
    target_attribute : string [@sop.default "targetpoint"]
      [@sop.label "Target point attribute"];
    using : Pdk.Ops.fuse_using [@sop.default Pdk.Ops.Least_target_point]
      [@sop.label "Use target"] [@sop.kind using_parameter];
    tolerance : float [@sop.default 0.001] [@sop.label "Snap distance"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
    position : Pdk.Ops.fuse_position [@sop.default Pdk.Ops.Average_position]
      [@sop.label "Position"] [@sop.folder "Fuse"]
      [@sop.kind position_parameter];
    weight_attribute : string [@sop.default ""]
      [@sop.label "Weight attribute"] [@sop.folder "Fuse"];
    attributes : Pdk.Ops.fuse_attributes [@sop.default Pdk.Ops.Keep_first]
      [@sop.label "Attributes"] [@sop.folder "Fuse"]
      [@sop.kind attributes_parameter];
    metric : Pdk.Ops.fuse_metric [@sop.default Pdk.Ops.Euclidean]
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
    match_condition : Pdk.Ops.fuse_match_condition
      [@sop.default Pdk.Ops.Equal_attribute_values]
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
    [@@sop.node_category "Topology/Cleanup"] [@@sop.node_inputs 2]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let targeting parameters = match parameters.targeting with
    | Near_points -> Pdk.Ops.Near_points
    | Specified_points -> Pdk.Ops.Specified_points parameters.target_attribute

  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; target] ->
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
          ?target input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild
    | _ -> invalid_arg "Sop_catalog.Fuse requires its source input"

  and rebuild ~label ~inputs parameters = match inputs with
    | [input] -> build_slots ~label ~inputs:[Some input; None] parameters
    | [input; target] ->
        build_slots ~label ~inputs:[Some input; Some target] parameters
    | _ -> invalid_arg "Sop_catalog.Fuse has invalid physical inputs"

  let factory = parameters_factory build_slots
  let create ?label:node_label ?target input =
    build_slots ~label:(label "fuse" node_label) ~inputs:[Some input; target]
      parameters_default
end [@@sop.register]

module Ray = struct
  type direction = Direction_vector | Direction_normal | Direction_attribute
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Minimum distance", Pdk.Ops.Ray_minimum_distance;
      "Project rays", Pdk.Ops.Ray_project;
    ]
  let direction_parameter = Parameter.choice ~equal:( = ) [
      "Vector", Direction_vector; "Normal", Direction_normal;
      "Attribute", Direction_attribute;
    ]
  let direction_mode_parameter = Parameter.choice ~equal:( = ) [
      "Forward", Pdk.Ops.Ray_forward; "Reverse", Pdk.Ops.Ray_reverse;
      "Bidirectional closest", Pdk.Ops.Ray_bidirectional_closest;
      "Bidirectional farthest", Pdk.Ops.Ray_bidirectional_farthest;
    ]
  let surface_parameter = Parameter.choice ~equal:( = ) [
      "First surface", Pdk.Ops.Ray_first_surface;
      "Last surface", Pdk.Ops.Ray_last_surface;
    ]
  let combine_parameter = Parameter.choice ~equal:( = ) [
      "Average", Pdk.Ops.Ray_average; "Median", Pdk.Ops.Ray_median;
      "Shortest", Pdk.Ops.Ray_shortest; "Longest", Pdk.Ops.Ray_longest;
    ]

  type parameters = {
    group_owner : element_owner [@sop.default Element_point]
      [@sop.label "Group type"] [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    collision_group : string [@sop.default ""]
      [@sop.label "Collision primitive group"];
    method_ : Pdk.Ops.ray_method [@sop.default Pdk.Ops.Ray_project]
      [@sop.label "Method"] [@sop.kind method_parameter];
    direction : direction [@sop.default Direction_normal]
      [@sop.label "Direction"] [@sop.folder "Ray"]
      [@sop.kind direction_parameter];
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Ray/Vector"] [@sop.min (-1.)] [@sop.max 1.];
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Ray/Vector"] [@sop.min (-1.)] [@sop.max 1.];
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Ray/Vector"] [@sop.min (-1.)] [@sop.max 1.];
    direction_attribute : string [@sop.default "N"]
      [@sop.label "Direction attribute"] [@sop.folder "Ray"];
    direction_mode : Pdk.Ops.ray_direction_mode
      [@sop.default Pdk.Ops.Ray_forward]
      [@sop.label "Direction mode"] [@sop.folder "Ray"]
      [@sop.kind direction_mode_parameter];
    surface_hit : Pdk.Ops.ray_surface_hit
      [@sop.default Pdk.Ops.Ray_first_surface]
      [@sop.label "Surface hit"] [@sop.folder "Ray"]
      [@sop.kind surface_parameter];
    samples : int [@sop.default 1] [@sop.label "Samples"]
      [@sop.folder "Jitter"] [@sop.min 1] [@sop.max 1024]
      [@sop.hard_min 1];
    jitter_scale : float [@sop.default 1.] [@sop.label "Jitter scale"]
      [@sop.folder "Jitter"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.folder "Jitter"]
      [@sop.min 0] [@sop.max 999999];
    combine : Pdk.Ops.ray_combine [@sop.default Pdk.Ops.Ray_average]
      [@sop.label "Combine"] [@sop.folder "Jitter"]
      [@sop.kind combine_parameter];
    min_distance : float [@sop.default 0.] [@sop.label "Minimum distance"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 1000.]
      [@sop.hard_min 0.];
    limit_max_distance : bool [@sop.default false]
      [@sop.label "Limit maximum distance"] [@sop.folder "Distance"];
    max_distance : float [@sop.default 10.] [@sop.label "Maximum distance"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 1000.]
      [@sop.hard_min 0.];
    tolerance : float [@sop.default 0.] [@sop.label "Tolerance"]
      [@sop.folder "Distance"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.];
    scale : float [@sop.default 1.] [@sop.label "Scale"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.];
    lift : float [@sop.default 0.] [@sop.label "Lift"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.];
    distance_attribute : string [@sop.default ""]
      [@sop.label "Distance"] [@sop.folder "Output"];
    primitive_attribute : string [@sop.default ""]
      [@sop.label "Primitive"] [@sop.folder "Output"];
    source_vertex_numbers_attribute : string [@sop.default ""]
      [@sop.label "Source vertices"] [@sop.folder "Output"];
    source_vertex_weights_attribute : string [@sop.default ""]
      [@sop.label "Source weights"] [@sop.folder "Output"];
    hit_group : string [@sop.default ""] [@sop.label "Hit group"]
      [@sop.folder "Output"];
    normal_attribute : string [@sop.default ""] [@sop.label "Hit normal"]
      [@sop.folder "Output"];
    point_pattern : string [@sop.default ""] [@sop.label "Point attributes"]
      [@sop.folder "Transfer"];
    vertex_pattern : string [@sop.default ""] [@sop.label "Vertex attributes"]
      [@sop.folder "Transfer"];
    primitive_pattern : string [@sop.default ""]
      [@sop.label "Primitive attributes"] [@sop.folder "Transfer"];
    detail_pattern : string [@sop.default ""] [@sop.label "Detail attributes"]
      [@sop.folder "Transfer"];
    match_groups : bool [@sop.default false] [@sop.label "Match groups"]
      [@sop.folder "Transfer"];
  } [@@sop.node_key "ray"] [@@sop.node_label "Ray"]
    [@@sop.node_category "Modify/Project"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]

  let direction parameters = match parameters.direction with
    | Direction_vector -> Pdk.Ops.Ray_vector (Vec3.create
        parameters.direction_x parameters.direction_y parameters.direction_z)
    | Direction_normal -> Pdk.Ops.Ray_normal
    | Direction_attribute ->
        Pdk.Ops.Ray_attribute parameters.direction_attribute

  let rec build ~label ~inputs parameters = match inputs with
    | [source; collision] ->
        let max_distance = if parameters.limit_max_distance
          then Some parameters.max_distance else None in
        Sop.ray ~label
          ?selection:(optional_element_group parameters.group_owner
            parameters.group)
          ?collision_group:(optional_text parameters.collision_group)
          ~method_:parameters.method_ ~direction:(direction parameters)
          ~direction_mode:parameters.direction_mode
          ~surface_hit:parameters.surface_hit ~samples:parameters.samples
          ~jitter_scale:parameters.jitter_scale ~seed:parameters.seed
          ~combine:parameters.combine ~min_distance:parameters.min_distance
          ?max_distance ~tolerance:parameters.tolerance ~scale:parameters.scale
          ~lift:parameters.lift
          ?distance_attribute:(optional_text parameters.distance_attribute)
          ?primitive_attribute:(optional_text parameters.primitive_attribute)
          ?source_vertex_numbers_attribute:
            (optional_text parameters.source_vertex_numbers_attribute)
          ?source_vertex_weights_attribute:
            (optional_text parameters.source_vertex_weights_attribute)
          ?hit_group:(optional_text parameters.hit_group)
          ?normal_attribute:(optional_text parameters.normal_attribute)
          ?point_pattern:(optional_text parameters.point_pattern)
          ?vertex_pattern:(optional_text parameters.vertex_pattern)
          ?primitive_pattern:(optional_text parameters.primitive_pattern)
          ?detail_pattern:(optional_text parameters.detail_pattern)
          ~match_groups:parameters.match_groups ~collision source
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Ray expects source and collision inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~collision source =
    build ~label:(label "ray" node_label) ~inputs:[source; collision]
      parameters_default
end [@@sop.register]

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
    falloff : Pdk.Ops.soft_transform_falloff
      [@sop.default Pdk.Ops.Soft_linear]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let start = match optional_element_group parameters.start_owner
            parameters.start_group with
          | Some start -> start
          | None -> Sop.Point_group "start" in
        Sop.distance_along_geometry ~label
          ?affected:(optional_element_group parameters.affected_owner
            parameters.affected_group) ~falloff:parameters.falloff
          ~radius:(distance_radius parameters.radius_mode parameters.radius)
          ~distance_attribute:(optional_text parameters.distance_attribute)
          ?mask_attribute:(optional_text parameters.mask_attribute) ~start input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg
        "Sop_catalog.Distance_along_geometry expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "distance-along-geometry" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Distance_from_geometry = struct
  let reference_parameter = Parameter.choice ~equal:( = ) [
      "Points", Pdk.Ops.Distance_reference_points;
      "Primitives", Pdk.Ops.Distance_reference_primitives;
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
    reference_kind : Pdk.Ops.distance_from_geometry_reference
      [@sop.default Pdk.Ops.Distance_reference_primitives]
      [@sop.label "Reference type"] [@sop.folder "Reference"]
      [@sop.kind reference_parameter];
    falloff : Pdk.Ops.soft_transform_falloff
      [@sop.default Pdk.Ops.Soft_linear]
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
    [@@sop.node_category "Attribute/Distance"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [source; reference] ->
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
          ~reference source
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg
        "Sop_catalog.Distance_from_geometry expects source and reference inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~reference source =
    build ~label:(label "distance-from-geometry" node_label)
      ~inputs:[source; reference] parameters_default
end [@@sop.register]

module Distance_from_target = struct
  let projection_parameter = Parameter.choice ~equal:( = ) [
      "Spherical", Pdk.Ops.Distance_target_spherical;
      "Cylindrical", Pdk.Ops.Distance_target_cylindrical;
      "Planar", Pdk.Ops.Distance_target_planar;
    ]
  let metric_parameter = Parameter.choice ~equal:( = ) [
      "Absolute", Pdk.Ops.Distance_target_absolute;
      "Signed", Pdk.Ops.Distance_target_signed;
    ]

  type parameters = {
    affected_owner : element_owner [@sop.default Element_point]
      [@sop.label "Affected group type"] [@sop.kind element_owner_parameter];
    affected_group : string [@sop.default ""] [@sop.label "Affected group"];
    projection : Pdk.Ops.distance_from_target_projection
      [@sop.default Pdk.Ops.Distance_target_spherical]
      [@sop.label "Projection"] [@sop.kind projection_parameter];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Target/Origin"] [@sop.min (-100.)] [@sop.max 100.];
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Target/Origin"] [@sop.min (-100.)] [@sop.max 100.];
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Target/Origin"] [@sop.min (-100.)] [@sop.max 100.];
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Target/Direction"] [@sop.min (-1.)] [@sop.max 1.];
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Target/Direction"] [@sop.min (-1.)] [@sop.max 1.];
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Target/Direction"] [@sop.min (-1.)] [@sop.max 1.];
    metric : Pdk.Ops.distance_from_target_metric
      [@sop.default Pdk.Ops.Distance_target_absolute]
      [@sop.label "Metric"] [@sop.kind metric_parameter];
    falloff : Pdk.Ops.soft_transform_falloff
      [@sop.default Pdk.Ops.Soft_linear]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          ?mask_attribute:(optional_text parameters.mask_attribute) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Distance_from_target expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "distance-from-target" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.point_split ~label
          ?selection:(optional_element_group parameters.group_owner
            parameters.group) ~attributes:parameters.attributes
          ~tolerance:parameters.tolerance
          ~promote_attributes:parameters.promote_attributes input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Point_split expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "point-split" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Poly_bridge = struct
  let pairing_parameter = Parameter.choice ~equal:( = ) [
      "By order", Pdk.Ops.Bridge_by_order;
      "By centroid", Pdk.Ops.Bridge_by_centroid;
    ]
  let minimize_parameter = Parameter.choice ~equal:( = ) [
      "Two point distance", Pdk.Ops.Two_point_distance;
      "Three point distance", Pdk.Ops.Three_point_distance;
    ]

  type parameters = {
    source_group : string [@sop.default "source"]
      [@sop.label "Source edge group"];
    destination_group : string [@sop.default "destination"]
      [@sop.label "Destination edge group"];
    pairing : Pdk.Ops.poly_bridge_pairing
      [@sop.default Pdk.Ops.Bridge_by_order]
      [@sop.label "Pairing"] [@sop.kind pairing_parameter];
    connect_closest_ends : bool [@sop.default true]
      [@sop.label "Connect closest ends"];
    minimize : Pdk.Ops.poly_loft_minimize
      [@sop.default Pdk.Ops.Two_point_distance]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          ~recompute_normals:parameters.recompute_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Poly_bridge expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "poly-bridge" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Graph_color = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Primitives by point", Pdk.Ops.Graph_primitives_by_point;
      "Points by primitive", Pdk.Ops.Graph_points_by_primitive;
      "Primitives by edge", Pdk.Ops.Graph_primitives_by_edge;
    ]

  type parameters = {
    group_owner : element_owner [@sop.default Element_primitive]
      [@sop.label "Group type"] [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    connectivity : Pdk.Ops.graph_color_connectivity
      [@sop.default Pdk.Ops.Graph_primitives_by_point]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let worksets = if parameters.output_worksets then Some {
            Pdk.Ops.begin_attribute = parameters.workset_begin_attribute;
            length_attribute = parameters.workset_length_attribute }
          else None in
        Sop.graph_color ~label
          ?selection:(optional_element_group parameters.group_owner
            parameters.group) ~connectivity:parameters.connectivity
          ~color_attribute:parameters.color_attribute
          ~sort_output:parameters.sort_output ?worksets input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Graph_color expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "graph-color" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Edge_relax = struct
  let target_parameter = Parameter.choice ~equal:( = ) [
      "Individual lengths", Pdk.Ops.Individual_lengths;
      "Scale-independent distribution", Pdk.Ops.Scale_independent_distribution;
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
    target_mode : Pdk.Ops.edge_relax_target_mode
      [@sop.default Pdk.Ops.Individual_lengths]
      [@sop.label "Target mode"] [@sop.kind target_parameter];
    only_shorten : bool [@sop.default false] [@sop.label "Only shorten"];
    tolerance : float [@sop.default 0.000001] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.];
  } [@@sop.node_key "edge_relax"] [@@sop.node_label "Edge Relax"]
    [@@sop.node_category "Topology/Edge"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [source; reference] ->
        Sop.edge_relax ~label
          ?group:(optional_element_group parameters.group_owner parameters.group)
          ?pin_group:(optional_text parameters.pin_group)
          ~iterations:parameters.iterations ~step_size:parameters.step_size
          ~target_mode:parameters.target_mode
          ~only_shorten:parameters.only_shorten
          ~tolerance:parameters.tolerance ~reference source
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg
        "Sop_catalog.Edge_relax expects source and reference inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~reference source =
    build ~label:(label "edge-relax" node_label) ~inputs:[source; reference]
      parameters_default
end [@@sop.register]

module Poly_loft = struct
  let minimize_parameter = Parameter.choice ~equal:( = ) [
      "Two point distance", Pdk.Ops.Two_point_distance;
      "Three point distance", Pdk.Ops.Three_point_distance;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    connect_closest_ends : bool [@sop.default true]
      [@sop.label "Connect closest ends"];
    minimize : Pdk.Ops.poly_loft_minimize
      [@sop.default Pdk.Ops.Two_point_distance]
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
    [@@sop.node_category "Topology/Polygon"] [@@sop.node_inputs 2]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; rest] ->
        Sop.poly_loft ~label ?group:(optional_text parameters.group) ?rest
          ~connect_closest_ends:parameters.connect_closest_ends
          ~minimize:parameters.minimize ~u_wrap:parameters.u_wrap
          ~v_wrap:parameters.v_wrap ~keep_primitives:parameters.keep_primitives
          ?output_group:(optional_text parameters.output_group)
          ~collinearity_tolerance:parameters.collinearity_tolerance
          ~recompute_normals:parameters.recompute_normals input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild
    | _ -> invalid_arg "Sop_catalog.Poly_loft requires its source input"

  and rebuild ~label ~inputs parameters = match inputs with
    | [input] -> build_slots ~label ~inputs:[Some input; None] parameters
    | [input; rest] ->
        build_slots ~label ~inputs:[Some input; Some rest] parameters
    | _ -> invalid_arg "Sop_catalog.Poly_loft has invalid physical inputs"

  let factory = parameters_factory build_slots
  let create ?label:node_label ?rest input =
    build_slots ~label:(label "poly-loft" node_label) ~inputs:[Some input; rest]
      parameters_default
end [@@sop.register]

module Revolve = struct
  let type_parameter = Parameter.choice ~equal:( = ) [
      "Closed", Pdk.Ops.Revolve_closed;
      "Open arc", Pdk.Ops.Revolve_open_arc;
    ]
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Points", Pdk.Ops.Grid_points;
      "Rows", Pdk.Ops.Grid_rows;
      "Columns", Pdk.Ops.Grid_columns;
      "Rows and columns", Pdk.Ops.Grid_rows_and_columns;
      "Quads", Pdk.Ops.Grid_quads;
      "Triangles", Pdk.Ops.Grid_triangles;
      "Alternating triangles", Pdk.Ops.Grid_alternating_triangles;
      "Reverse triangles", Pdk.Ops.Grid_reverse_triangles;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    revolve_type : Pdk.Ops.revolve_type [@sop.default Pdk.Ops.Revolve_closed]
      [@sop.label "Revolve type"] [@sop.kind type_parameter];
    connectivity : Pdk.Ops.grid_connectivity [@sop.default Pdk.Ops.Grid_quads]
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
      [@sop.folder "Axis/Origin"] [@sop.min (-100.)] [@sop.max 100.];
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Axis/Origin"] [@sop.min (-100.)] [@sop.max 100.];
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Axis/Origin"] [@sop.min (-100.)] [@sop.max 100.];
    axis_x : float [@sop.default 0.] [@sop.label "Axis X"]
      [@sop.folder "Axis/Direction"] [@sop.min (-1.)] [@sop.max 1.];
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Axis/Direction"] [@sop.min (-1.)] [@sop.max 1.];
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Axis/Direction"] [@sop.min (-1.)] [@sop.max 1.];
  } [@@sop.node_key "revolve"] [@@sop.node_label "Revolve"]
    [@@sop.node_category "Topology/Surface"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.revolve ~label ?group:(optional_text parameters.group)
          ~revolve_type:parameters.revolve_type
          ~connectivity:parameters.connectivity
          ~start_angle:parameters.start_angle ~end_angle:parameters.end_angle
          ~reverse_cross_sections:parameters.reverse_cross_sections
          ~caps:parameters.caps ?cap_group:(optional_text parameters.cap_group)
          ~uv_attribute:(optional_text parameters.uv_attribute)
          ~divisions:parameters.divisions
          ~origin:(Vec3.create parameters.origin_x parameters.origin_y
            parameters.origin_z)
          ~axis:(Vec3.create parameters.axis_x parameters.axis_y
            parameters.axis_z) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Revolve expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "revolve" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Sweep = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Points", Pdk.Ops.Grid_points; "Rows", Pdk.Ops.Grid_rows;
      "Columns", Pdk.Ops.Grid_columns;
      "Rows and columns", Pdk.Ops.Grid_rows_and_columns;
      "Quads", Pdk.Ops.Grid_quads; "Triangles", Pdk.Ops.Grid_triangles;
      "Alternating triangles", Pdk.Ops.Grid_alternating_triangles;
      "Reverse triangles", Pdk.Ops.Grid_reverse_triangles;
    ]
  let tangent_parameter = Parameter.choice ~equal:( = ) [
      "Average edges", Pdk.Ops.Sweep_average_edges;
      "Central difference", Pdk.Ops.Sweep_central_difference;
      "Previous edge", Pdk.Ops.Sweep_previous_edge;
      "Next edge", Pdk.Ops.Sweep_next_edge;
      "Z axis", Pdk.Ops.Sweep_z_axis;
    ]

  type parameters = {
    backbone_group : string [@sop.default ""]
      [@sop.label "Backbone primitive group"];
    cross_section_group : string [@sop.default ""]
      [@sop.label "Cross-section primitive group"];
    connectivity : Pdk.Ops.grid_connectivity [@sop.default Pdk.Ops.Grid_quads]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    tangent : Pdk.Ops.sweep_tangent
      [@sop.default Pdk.Ops.Sweep_average_edges]
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
    [@@sop.node_category "Topology/Surface"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [backbone; cross_section] ->
        Sop.sweep ~label
          ?backbone_group:(optional_text parameters.backbone_group)
          ?cross_section_group:(optional_text parameters.cross_section_group)
          ~connectivity:parameters.connectivity ~tangent:parameters.tangent
          ~continuous_closed:parameters.continuous_closed
          ~transform_attributes:parameters.transform_attributes
          ~reverse_cross_sections:parameters.reverse_cross_sections
          ~scale:parameters.scale ~roll:parameters.roll ~twist:parameters.twist
          ~caps:parameters.caps ?cap_group:(optional_text parameters.cap_group)
          ~uv_attribute:(optional_text parameters.uv_attribute)
          ~cross_section_prefix:parameters.cross_section_prefix
          ~backbone ~cross_section ()
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg
        "Sop_catalog.Sweep expects backbone and cross-section inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~backbone ~cross_section () =
    build ~label:(label "sweep" node_label) ~inputs:[backbone; cross_section]
      parameters_default
end [@@sop.register]

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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          ~caps:parameters.caps ?cap_group:(optional_text parameters.cap_group)
          ~radius:parameters.radius input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Polywire expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "polywire" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
      [@sop.folder "Projection/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Projection/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Projection/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    axis_x : float [@sop.default 0.] [@sop.label "Axis X"]
      [@sop.folder "Projection/Axis"] [@sop.min (-1.)] [@sop.max 1.];
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Projection/Axis"] [@sop.min (-1.)] [@sop.max 1.];
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Projection/Axis"] [@sop.min (-1.)] [@sop.max 1.];
    seam_x : float [@sop.default 1.] [@sop.label "Seam X"]
      [@sop.folder "Projection/Seam"] [@sop.min (-1.)] [@sop.max 1.];
    seam_y : float [@sop.default 0.] [@sop.label "Seam Y"]
      [@sop.folder "Projection/Seam"] [@sop.min (-1.)] [@sop.max 1.];
    seam_z : float [@sop.default 0.] [@sop.label "Seam Z"]
      [@sop.folder "Projection/Seam"] [@sop.min (-1.)] [@sop.max 1.];
    planar_u_x : float [@sop.default 1.] [@sop.label "U axis X"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.];
    planar_u_y : float [@sop.default 0.] [@sop.label "U axis Y"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.];
    planar_u_z : float [@sop.default 0.] [@sop.label "U axis Z"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.];
    planar_v_x : float [@sop.default 0.] [@sop.label "V axis X"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.];
    planar_v_y : float [@sop.default 0.] [@sop.label "V axis Y"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.];
    planar_v_z : float [@sop.default 1.] [@sop.label "V axis Z"]
      [@sop.folder "Projection/Planar"] [@sop.min (-1.)] [@sop.max 1.];
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
    | Planar -> Pdk.Ops.Planar { origin;
        u_axis = Vec3.create parameters.planar_u_x parameters.planar_u_y
          parameters.planar_u_z;
        v_axis = Vec3.create parameters.planar_v_x parameters.planar_v_y
          parameters.planar_v_z }
    | Cylindrical -> Pdk.Ops.Cylindrical { origin;
        axis = Vec3.create parameters.axis_x parameters.axis_y parameters.axis_z;
        seam = Vec3.create parameters.seam_x parameters.seam_y parameters.seam_z;
        height = parameters.height }
    | Spherical -> Pdk.Ops.Spherical { origin;
        axis = Vec3.create parameters.axis_x parameters.axis_y parameters.axis_z;
        seam = Vec3.create parameters.seam_x parameters.seam_y parameters.seam_z }
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.uv_project ~label ~name:parameters.name
        ?group:(optional_text parameters.group)
        ~u_range:(parameters.u_min, parameters.u_max)
        ~v_range:(parameters.v_min, parameters.v_max)
        ~fix_seams:parameters.fix_seams ~fix_poles:parameters.fix_poles
        (projection parameters) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Uv_project expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "uv-project" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Uv_transform = struct
  type parameters = {
    name : string [@sop.default "uv"] [@sop.label "UV attribute"];
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Vertex]
      [@sop.label "Owner"] [@sop.kind uv_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    translate_u : float [@sop.default 0.] [@sop.label "Translate U"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.];
    translate_v : float [@sop.default 0.] [@sop.label "Translate V"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.];
    scale_u : float [@sop.default 1.] [@sop.label "Scale U"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.];
    scale_v : float [@sop.default 1.] [@sop.label "Scale V"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.];
    angle : float [@sop.default 0.] [@sop.label "Angle"]
      [@sop.folder "Transform"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    pivot_u : float [@sop.default 0.5] [@sop.label "Pivot U"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.];
    pivot_v : float [@sop.default 0.5] [@sop.label "Pivot V"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.];
  } [@@sop.node_key "uv_transform"] [@@sop.node_label "UV Transform"]
    [@@sop.node_category "UV/Modify"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.uv_transform ~label ~name:parameters.name
        ~owner:parameters.owner ?group:(optional_text parameters.group)
        ~translate:(Vec2.create parameters.translate_u parameters.translate_v)
        ~scale:(Vec2.create parameters.scale_u parameters.scale_v)
        ~angle:parameters.angle
        ~pivot:(Vec2.create parameters.pivot_u parameters.pivot_v) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Uv_transform expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "uv-transform" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.uv_auto_seam ~label ~name:parameters.name
        ?group:(optional_text parameters.group) ~angle:parameters.angle
        ~include_boundaries:parameters.include_boundaries
        ~include_non_manifold:parameters.include_non_manifold
        ?partition_attribute:(optional_text parameters.partition_attribute)
        ?existing_uv:(optional_text parameters.existing_uv)
        ~uv_tolerance:parameters.uv_tolerance
        ?island_attribute:(optional_text parameters.island_attribute) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Uv_auto_seam expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "uv-auto-seam" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Uv_unitize = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Per face", Pdk.Ops.Per_face; "Islands", Pdk.Ops.Islands;
    ]
  type parameters = {
    mode : Pdk.Ops.uv_unitize_mode [@sop.default Pdk.Ops.Per_face]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.uv_unitize ~label ~name:parameters.name
        ?group:(optional_text parameters.group)
        ?seams:(optional_text parameters.seams)
        ~tolerance:parameters.tolerance ~uniform:parameters.uniform
        parameters.mode input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Uv_unitize expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "uv-unitize" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.uv_flatten ~label ~name:parameters.name
        ?seams:(optional_text parameters.seams)
        ~iterations:parameters.iterations ~tolerance:parameters.tolerance input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Uv_flatten expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "uv-flatten" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.uv_relax ~label ~name:parameters.name
        ?seams:(optional_text parameters.seams)
        ~uv_tolerance:parameters.uv_tolerance
        ~iterations:parameters.iterations ~tolerance:parameters.tolerance input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Uv_relax expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "uv-relax" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Group_edges = struct
  let incidence_parameter = Parameter.choice ~equal:( = ) [
      "Any", Pdk.Ops.Any_edge; "Boundary", Pdk.Ops.Boundary_edge;
      "Manifold", Pdk.Ops.Manifold_edge;
      "Non-manifold", Pdk.Ops.Non_manifold_edge;
    ]
  let angle_basis_parameter = Parameter.choice ~equal:( = ) [
      "Primitive dihedral", Pdk.Ops.Primitive_dihedral;
      "Incident edges", Pdk.Ops.Incident_edges;
    ]
  type parameters = {
    name : string [@sop.default "edges"] [@sop.label "Group name"];
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    incidence : Pdk.Ops.edge_incidence [@sop.default Pdk.Ops.Any_edge]
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
    angle_basis : Pdk.Ops.edge_angle_basis
      [@sop.default Pdk.Ops.Primitive_dihedral]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_edges ~label ~name:parameters.name
        ?group:(optional_text parameters.group) ~incidence:parameters.incidence
        ?min_length:(if parameters.use_min_length then Some parameters.min_length
          else None)
        ?max_length:(if parameters.use_max_length then Some parameters.max_length
          else None)
        ~angle_basis:parameters.angle_basis
        ?min_angle:(if parameters.use_min_angle then Some parameters.min_angle
          else None)
        ?max_angle:(if parameters.use_max_angle then Some parameters.max_angle
          else None) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_edges expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-edges" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_random = struct
  type parameters = {
    owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_points]
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
    merge : Pdk.Ops.group_boolean_operation
      [@sop.default Pdk.Ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_random"] [@@sop.node_label "Group Random"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_random ~label
        ?seed:(if parameters.context_seed then None else Some parameters.seed)
        ?seed_attribute:(optional_text parameters.seed_attribute)
        ?base:(optional_text parameters.base) ~merge:parameters.merge
        ~probability:parameters.probability ~owner:parameters.owner
        ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_random expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-random" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_bounds = struct
  type shape = Box | Sphere
  let shape_parameter = Parameter.choice ~equal:( = ) [
      "Box", Box; "Sphere", Sphere;
    ]
  let containment_parameter = Parameter.choice ~equal:( = ) [
      "Fully contained", Pdk.Ops.Fully_contained;
      "Partially contained", Pdk.Ops.Partially_contained;
    ]
  type parameters = {
    owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_points]
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
    containment : Pdk.Ops.group_containment
      [@sop.default Pdk.Ops.Fully_contained] [@sop.label "Containment"]
      [@sop.folder "Combine"] [@sop.kind containment_parameter];
    merge : Pdk.Ops.group_boolean_operation
      [@sop.default Pdk.Ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_bounds"] [@@sop.node_label "Group by Bounds"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let bounds parameters =
    let center = Vec3.create parameters.center_x parameters.center_y
        parameters.center_z in
    match parameters.shape with
    | Sphere -> Pdk.Ops.Bounds_sphere { center; radius = parameters.radius }
    | Box -> let half = Vec3.create (parameters.size_x *. 0.5)
          (parameters.size_y *. 0.5) (parameters.size_z *. 0.5) in
        Pdk.Ops.Bounds_box { minimum = Vec3.sub center half;
          maximum = Vec3.add center half }
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_bounds ~label ?base:(optional_text parameters.base)
        ~containment:parameters.containment ~merge:parameters.merge
        (bounds parameters) ~owner:parameters.owner ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_bounds expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-bounds" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_normal = struct
  type parameters = {
    owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_primitives]
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
    merge : Pdk.Ops.group_boolean_operation
      [@sop.default Pdk.Ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_normal"] [@@sop.node_label "Group by Normal"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_normal ~label
        ?normal_attribute:(optional_text parameters.normal_attribute)
        ~use_existing_normal:parameters.use_existing_normal
        ?base:(optional_text parameters.base)
        ~include_opposite:parameters.include_opposite ~merge:parameters.merge
        ~direction:(Vec3.create parameters.direction_x parameters.direction_y
          parameters.direction_z) ~spread_angle:parameters.spread_angle
        ~owner:parameters.owner ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_normal expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-normal" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_non_planar = struct
  type parameters = {
    name : string [@sop.default "nonplanar"] [@sop.label "Group name"];
    tolerance : float [@sop.default 1e-6] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"];
    merge : Pdk.Ops.group_boolean_operation
      [@sop.default Pdk.Ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_non_planar"] [@@sop.node_label "Group Non-Planar"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_non_planar ~label
        ?base:(optional_text parameters.base) ~merge:parameters.merge
        ~tolerance:parameters.tolerance ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_non_planar expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-non-planar" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
    merge : Pdk.Ops.group_boolean_operation
      [@sop.default Pdk.Ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_backface"] [@@sop.node_label "Group Backfaces"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_backface ~label ?base:(optional_text parameters.base)
        ~merge:parameters.merge
        ~viewpoint:(Vec3.create parameters.viewpoint_x parameters.viewpoint_y
          parameters.viewpoint_z) ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_backface expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-backface" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_edge_depth = struct
  type parameters = {
    point_group : string [@sop.default "seed"] [@sop.label "Seed point group"];
    name : string [@sop.default "depth"] [@sop.label "Output group"];
    depth : int [@sop.default 1] [@sop.label "Depth"] [@sop.min 0]
      [@sop.max 100] [@sop.hard_min 0];
    merge : Pdk.Ops.group_boolean_operation
      [@sop.default Pdk.Ops.Group_replace] [@sop.label "Operation"]
      [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_edge_depth"] [@@sop.node_label "Group Edge Depth"]
    [@@sop.node_category "Group/Expand"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_edge_depth ~label ~merge:parameters.merge
        ~depth:parameters.depth ~point_group:parameters.point_group
        ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_edge_depth expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-edge-depth" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_unshared = struct
  type parameters = {
    owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_edges]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "unshared"] [@sop.label "Group name"];
    merge : Pdk.Ops.group_boolean_operation
      [@sop.default Pdk.Ops.Group_replace] [@sop.label "Operation"]
      [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_unshared"] [@@sop.node_label "Group Unshared"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_unshared ~label ~merge:parameters.merge
        ~owner:parameters.owner ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_unshared expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-unshared" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_boundary_components = struct
  let conflict_parameter = Parameter.choice ~equal:( = ) [
      "Replace", Pdk.Ops.Name_replace; "Union", Pdk.Ops.Name_union;
    ]
  type parameters = {
    prefix : string [@sop.default "boundary"] [@sop.label "Group prefix"];
    conflict : Pdk.Ops.group_name_conflict
      [@sop.default Pdk.Ops.Name_replace] [@sop.label "Conflict"]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_boundary_components ~label ~prefix:parameters.prefix
        ~conflict:parameters.conflict ~max_groups:parameters.max_groups
        ~max_payload_bytes:parameters.max_payload_bytes input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_boundary_components expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-boundary-components" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_from_attribute_boundary = struct
  type parameters = {
    owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_edges]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "attribute_boundary"]
      [@sop.label "Group name"];
    attributes : Pdk.Ops.group_boundary_attribute list [@sop.default []]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_from_attribute_boundary ~label
        ~attributes:parameters.attributes ~tolerance:parameters.tolerance
        ~include_unshared_edges:parameters.include_unshared_edges
        ~include_all_unshared_curve_edges:
          parameters.include_all_unshared_curve_edges
        ~include_all_primitives_sharing_boundary_points:
          parameters.include_all_primitives_sharing_boundary_points
        ~owner:parameters.owner ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg
        "Sop_catalog.Group_from_attribute_boundary expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-from-attribute-boundary" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Groups_from_name = struct
  let conflict_parameter = Parameter.choice ~equal:( = ) [
      "Replace", Pdk.Ops.Name_replace; "Union", Pdk.Ops.Name_union;
    ]
  let invalid_parameter = Parameter.choice ~equal:( = ) [
      "Ignore invalid", Pdk.Ops.Ignore_invalid;
      "Force valid", Pdk.Ops.Force_valid;
    ]
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Primitive]
      [@sop.label "Attribute owner"]
      [@sop.kind element_attribute_owner_parameter];
    attribute : string [@sop.default "name"] [@sop.label "Name attribute"];
    prefix : string [@sop.default ""] [@sop.label "Group prefix"];
    conflict : Pdk.Ops.group_name_conflict
      [@sop.default Pdk.Ops.Name_replace] [@sop.label "Conflict"]
      [@sop.kind conflict_parameter];
    invalid_names : Pdk.Ops.invalid_group_name_policy
      [@sop.default Pdk.Ops.Ignore_invalid] [@sop.label "Invalid names"]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.groups_from_name ~label ~prefix:parameters.prefix
        ~conflict:parameters.conflict ~invalid_names:parameters.invalid_names
        ~max_groups:parameters.max_groups
        ~max_payload_bytes:parameters.max_payload_bytes
        ~owner:parameters.owner ~attribute:parameters.attribute input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Groups_from_name expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "groups-from-name" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Name_from_groups = struct
  let overlap_parameter = Parameter.choice ~equal:( = ) [
      "First group", Pdk.Ops.First_group; "Last group", Pdk.Ops.Last_group;
      "Error on overlap", Pdk.Ops.Error_on_overlap;
    ]
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Primitive]
      [@sop.label "Group type"] [@sop.kind element_attribute_owner_parameter];
    attribute : string [@sop.default "name"] [@sop.label "Name attribute"];
    pattern : string [@sop.default "*"] [@sop.label "Group pattern"];
    default : string [@sop.default ""] [@sop.label "Default value"];
    overlap : Pdk.Ops.group_name_overlap [@sop.default Pdk.Ops.First_group]
      [@sop.label "Overlapping groups"] [@sop.kind overlap_parameter];
    delete_groups : bool [@sop.default false]
      [@sop.label "Delete source groups"];
  } [@@sop.node_key "name_from_groups"] [@@sop.node_label "Name from Groups"]
    [@@sop.node_category "Group/Convert"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.name_from_groups ~label ~attribute:parameters.attribute
        ~pattern:parameters.pattern ~default:parameters.default
        ~overlap:parameters.overlap ~delete_groups:parameters.delete_groups
        ~owner:parameters.owner input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Name_from_groups expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "name-from-groups" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_promote = struct
  type parameters = {
    source : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_points]
      [@sop.label "Source owner"] [@sop.kind group_owner_parameter];
    destination : Pdk.Ops.group_owner
      [@sop.default Pdk.Ops.Group_primitives]
      [@sop.label "Destination owner"] [@sop.kind group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Source group"];
    name : string [@sop.default ""] [@sop.label "New group name"];
    keep_original : bool [@sop.default false]
      [@sop.label "Keep original group"];
    output_attribute : string [@sop.default ""]
      [@sop.label "Output mask attribute"] [@sop.folder "Output"];
    mode : Pdk.Ops.group_promote_mode [@sop.default Pdk.Ops.Include_any]
      [@sop.label "Promotion mode"] [@sop.kind group_promote_mode_parameter];
  } [@@sop.node_key "group_promote"] [@@sop.node_label "Group Promote"]
    [@@sop.node_category "Group/Convert"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_promote ~label
        ?name:(optional_text parameters.name)
        ~keep_original:parameters.keep_original
        ?output_attribute:(optional_text parameters.output_attribute)
        ~mode:parameters.mode ~source:parameters.source
        ~destination:parameters.destination ~group:parameters.group input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_promote expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-promote" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_promote_boundary = struct
  type parameters = {
    source : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_primitives]
      [@sop.label "Source owner"] [@sop.kind group_owner_parameter];
    destination : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_edges]
      [@sop.label "Destination owner"] [@sop.kind group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Source group"];
    name : string [@sop.default ""] [@sop.label "New group name"];
    keep_original : bool [@sop.default false]
      [@sop.label "Keep original group"];
    output_attribute : string [@sop.default ""]
      [@sop.label "Output mask attribute"] [@sop.folder "Output"];
    attributes : Pdk.Ops.group_boundary_attribute list [@sop.default []]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_promote_boundary ~label
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
        ~group:parameters.group input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg
        "Sop_catalog.Group_promote_boundary expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-promote-boundary" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_promotions = struct
  let bool_token value = if value then "true" else "false"
  let bool_of_token = function
    | "true" | "1" | "yes" -> Ok true
    | "false" | "0" | "no" -> Ok false
    | token -> Error (Printf.sprintf "expected boolean, got %S" token)
  let encode_attributes attributes = encode_table (List.map
      (fun (attribute : Pdk.Ops.group_boundary_attribute) ->
        [attribute_owner_token attribute.boundary_attribute_owner;
         attribute.boundary_attribute_pattern]) attributes)
  let decode_attributes text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun attributes ->
        match row with
        | [owner; pattern] -> Result.map (fun boundary_attribute_owner ->
            { Pdk.Ops.boundary_attribute_owner;
              boundary_attribute_pattern = pattern } :: attributes)
            (attribute_owner_of_token
              (String.lowercase_ascii (String.trim owner)))
        | row -> Error (Printf.sprintf
            "boundary attribute needs owner and pattern, got %d columns"
            (List.length row)))) (Ok []) rows |> Result.map List.rev)
  let encode_operation = function
    | Pdk.Ops.Promote_elements mode ->
        let token = match mode with
          | Pdk.Ops.Include_any -> "any"
          | Pdk.Ops.Include_all -> "all"
          | Pdk.Ops.Include_shared_edge -> "shared_edge" in
        [token; "0"; "false"; "false"; "false"; ""]
    | Pdk.Ops.Promote_boundary options -> [
        "boundary"; Printf.sprintf "%.17g" options.promote_boundary_tolerance;
        bool_token options.promote_include_unshared_edges;
        bool_token options.promote_include_all_unshared_curve_edges;
        bool_token options.promote_include_all_primitives_sharing_boundary_points;
        encode_attributes options.promote_boundary_attributes;
      ]
  let decode_operation = function
    | [kind; tolerance; unshared; all_curve; all_primitives; attributes] ->
        (match String.lowercase_ascii (String.trim kind) with
         | "any" -> Ok (Pdk.Ops.Promote_elements Pdk.Ops.Include_any)
         | "all" -> Ok (Pdk.Ops.Promote_elements Pdk.Ops.Include_all)
         | "shared_edge" | "shared edge" ->
             Ok (Pdk.Ops.Promote_elements Pdk.Ops.Include_shared_edge)
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
                                Pdk.Ops.Promote_boundary {
                                  Pdk.Ops.promote_boundary_attributes;
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
  let encode_rule (rule : Pdk.Ops.group_promotion_rule) = [
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
                    Pdk.Ops.promotion_source; promotion_destination;
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
      Pdk.Ops.promotion_source = Pdk.Ops.Group_points;
      promotion_destination = Pdk.Ops.Group_primitives;
      promotion_pattern = "*"; promotion_new_name = None;
      promotion_keep_original = false;
      promotion_output_as_attribute = false;
      promotion_operation = Pdk.Ops.Promote_elements Pdk.Ops.Include_any;
    }]
  type parameters = {
    rules : Pdk.Ops.group_promotion_rule list [@sop.default default_rules]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_promotions ~label
        ~max_outputs:parameters.max_outputs
        ~max_payload_bytes:parameters.max_payload_bytes parameters.rules input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_promotions expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-promotions" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_invert = struct
  type owner = Any | Owner of Pdk.Ops.group_owner
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Any", Any; "Points", Owner Pdk.Ops.Group_points;
      "Vertices", Owner Pdk.Ops.Group_vertices;
      "Primitives", Owner Pdk.Ops.Group_primitives;
      "Edges", Owner Pdk.Ops.Group_edges;
    ]
  type parameters = {
    owner : owner [@sop.default Any] [@sop.label "Group type"]
      [@sop.kind owner_parameter];
    pattern : string [@sop.default "*"] [@sop.label "Group pattern"];
    new_name : string [@sop.default ""] [@sop.label "New name pattern"];
    conflict : Pdk.Ops.group_rename_conflict
      [@sop.default Pdk.Ops.Rename_overwrite] [@sop.label "Conflict"]
      [@sop.kind group_rename_conflict_parameter];
  } [@@sop.node_key "group_invert"] [@@sop.node_label "Group Invert"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let owner = match parameters.owner with Any -> None | Owner owner -> Some owner in
        Sop.group_invert ~label ~conflict:parameters.conflict ?owner
          ~pattern:parameters.pattern ?new_name:(optional_text parameters.new_name)
          input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_invert expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-invert" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_delete = struct
  let encode_rule (rule : Pdk.Ops.group_delete_rule) = [
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
          Pdk.Ops.delete_owner; delete_pattern = pattern }) owner
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
    rules : Pdk.Ops.group_delete_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern)"] [@sop.kind rules_parameter];
    delete_unused : bool [@sop.default false]
      [@sop.label "Delete unused groups"];
  } [@@sop.node_key "group_delete"] [@@sop.node_label "Group Delete"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_delete ~label
        ~delete_unused:parameters.delete_unused ~rules:parameters.rules input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_delete expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-delete" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_rename = struct
  let conflict_token = function
    | Pdk.Ops.Rename_skip -> "skip"
    | Pdk.Ops.Rename_error -> "error"
    | Pdk.Ops.Rename_overwrite -> "overwrite"
    | Pdk.Ops.Rename_union -> "union"
  let conflict_of_token = function
    | "skip" -> Ok Pdk.Ops.Rename_skip
    | "error" -> Ok Pdk.Ops.Rename_error
    | "overwrite" -> Ok Pdk.Ops.Rename_overwrite
    | "union" -> Ok Pdk.Ops.Rename_union
    | token -> Error (Printf.sprintf "unknown group rename conflict %S" token)
  let encode_rule (rule : Pdk.Ops.group_rename_rule) = [
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
            Pdk.Ops.rename_owner; rename_pattern = pattern;
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
    rules : Pdk.Ops.group_rename_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, replacement, conflict)"]
      [@sop.kind rules_parameter];
  } [@@sop.node_key "group_rename"] [@@sop.node_label "Group Rename"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_rename ~label ~rules:parameters.rules input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_rename expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-rename" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_copy = struct
  let encode_rule (rule : Pdk.Ops.group_copy_rule) = [
      group_owner_token rule.copy_owner; rule.copy_pattern; rule.copy_prefix;
      Option.value ~default:"" rule.match_attribute;
    ]
  let decode_rule = function
    | [owner; pattern; prefix; match_attribute] ->
        Result.map (fun copy_owner -> { Pdk.Ops.copy_owner;
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
    rules : Pdk.Ops.group_copy_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, prefix, match attribute)"]
      [@sop.kind rules_parameter];
    conflict : Pdk.Ops.group_copy_conflict
      [@sop.default Pdk.Ops.Copy_overwrite] [@sop.label "Conflict"]
      [@sop.kind group_copy_conflict_parameter];
    copy_empty : bool [@sop.default false] [@sop.label "Copy empty groups"];
  } [@@sop.node_key "group_copy"] [@@sop.node_label "Group Copy"]
    [@@sop.node_category "Group/Transfer"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [source; target] -> Sop.group_copy ~label
        ?rules:(if parameters.use_rules then Some parameters.rules else None)
        ~conflict:parameters.conflict ~copy_empty:parameters.copy_empty
        ~source ~target ()
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_copy expects two inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~source ~target () = build
      ~label:(label "group-copy" node_label) ~inputs:[source; target]
      parameters_default
end [@@sop.register]

module Group_transfer = struct
  let encode_rule (rule : Pdk.Ops.group_transfer_rule) = [
      group_owner_token rule.transfer_owner; rule.transfer_pattern;
      rule.transfer_prefix;
    ]
  let decode_rule = function
    | [owner; pattern; prefix] ->
        Result.map (fun transfer_owner -> { Pdk.Ops.transfer_owner;
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
    rules : Pdk.Ops.group_transfer_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, prefix)"]
      [@sop.kind rules_parameter];
    conflict : Pdk.Ops.group_copy_conflict
      [@sop.default Pdk.Ops.Copy_overwrite] [@sop.label "Conflict"]
      [@sop.kind group_copy_conflict_parameter];
    create_empty : bool [@sop.default false]
      [@sop.label "Create empty groups"];
    distance : float [@sop.default 0.001] [@sop.label "Maximum distance"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
  } [@@sop.node_key "group_transfer"] [@@sop.node_label "Group Transfer"]
    [@@sop.node_category "Group/Transfer"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [source; target] -> Sop.group_transfer ~label
        ?rules:(if parameters.use_rules then Some parameters.rules else None)
        ~conflict:parameters.conflict ~create_empty:parameters.create_empty
        ~distance:parameters.distance ~source ~target ()
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_transfer expects two inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~source ~target () = build
      ~label:(label "group-transfer" node_label) ~inputs:[source; target]
      parameters_default
end [@@sop.register]

module Group_combine = struct
  let bool_token value = if value then "true" else "false"
  let bool_of_token = function
    | "true" | "1" | "yes" -> Ok true
    | "false" | "0" | "no" -> Ok false
    | token -> Error (Printf.sprintf "expected boolean, got %S" token)
  let encode_step (step : Pdk.Ops.group_combine_step) = [
      group_boolean_token step.operation; step.operand.pattern;
      bool_token step.operand.inverted;
    ]
  let decode_step = function
    | [operation; pattern; inverted] ->
        Result.bind (group_boolean_of_token
          (String.lowercase_ascii (String.trim operation)))
          (fun operation -> Result.map (fun inverted -> {
            Pdk.Ops.operation; operand = { pattern; inverted } })
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
    owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "combined"] [@sop.label "Output group"];
    base_pattern : string [@sop.default "*"] [@sop.label "Base pattern"];
    base_inverted : bool [@sop.default false] [@sop.label "Invert base"];
    steps : Pdk.Ops.group_combine_step list [@sop.default []]
      [@sop.label "Steps (operation, pattern, invert)"]
      [@sop.kind steps_parameter];
  } [@@sop.node_key "group_combine"] [@@sop.node_label "Group Combine"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_combine ~label ~owner:parameters.owner
        ~name:parameters.name ~base:{ Pdk.Ops.pattern = parameters.base_pattern;
          inverted = parameters.base_inverted }
        ~steps:parameters.steps input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_combine expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-combine" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_expand = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Share points", Pdk.Ops.Primitive_share_points;
      "Share edges", Pdk.Ops.Primitive_share_edges;
    ]
  type parameters = {
    owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Source group"];
    name : string [@sop.default ""] [@sop.label "Output group"];
    steps : int [@sop.default 1] [@sop.label "Steps"]
      [@sop.min (-100)] [@sop.max 100];
    flood : bool [@sop.default false] [@sop.label "Flood fill"];
    step_attribute : string [@sop.default ""]
      [@sop.label "Step attribute"] [@sop.folder "Output"];
    primitive_connectivity : Pdk.Ops.primitive_group_connectivity
      [@sop.default Pdk.Ops.Primitive_share_points]
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
    connectivity_attributes : Pdk.Ops.group_boundary_attribute list
      [@sop.default []] [@sop.label "Boundary attributes (owner, pattern)"]
      [@sop.folder "Connectivity"] [@sop.kind boundary_attributes_parameter];
    connectivity_tolerance : float [@sop.default 0.00001]
      [@sop.label "Attribute tolerance"] [@sop.folder "Connectivity"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    use_collision : bool [@sop.default false]
      [@sop.label "Use collision group"] [@sop.folder "Collision"];
    collision_owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_edges]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let normal_attribute = if parameters.use_normal_attribute then Some {
            Pdk.Ops.expand_normal_owner = parameters.normal_owner;
            expand_normal_name = parameters.normal_name } else None
        and collision = if parameters.use_collision then Some {
            Pdk.Ops.expand_collision_owner = parameters.collision_owner;
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
          ~owner:parameters.owner ~group:parameters.group input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_expand expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-expand" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
    owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_points]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "range"] [@sop.label "Output group"];
    base : string [@sop.default ""] [@sop.label "Base group"];
    invert : bool [@sop.default false] [@sop.label "Invert range"];
    merge : Pdk.Ops.group_boolean_operation
      [@sop.default Pdk.Ops.Group_replace] [@sop.label "Merge"]
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
    collision_owner : Pdk.Ops.group_owner [@sop.default Pdk.Ops.Group_edges]
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
    | Start_end -> Pdk.Ops.Range_start_end {
        start = parameters.start; end_ = parameters.end_ }
    | From_ends -> Pdk.Ops.Range_from_ends {
        start = parameters.start; end_offset = parameters.end_offset }
    | Start_length -> Pdk.Ops.Range_start_length {
        start = parameters.start; length = parameters.length }
    | Partition -> Pdk.Ops.Range_partition {
        partition = parameters.partition; partitions = parameters.partitions }
  let filter parameters = if parameters.use_filter then Some {
      Pdk.Ops.select = parameters.filter_select; of_ = parameters.filter_of;
      offset = parameters.filter_offset } else None
  let connectivity parameters =
    let region = if parameters.use_region then Some parameters.region else None in
    match parameters.connectivity_mode with
    | No_connectivity -> None
    | Disconnected -> Some (Pdk.Ops.Range_disconnected { region })
    | Connected ->
        let collision = if parameters.use_collision then Some {
            Pdk.Ops.collision_owner = parameters.collision_owner;
            collision_pattern = parameters.collision_pattern;
            keep_boundary = parameters.keep_boundary } else None in
        Some (Pdk.Ops.Range_connected {
          connectivity_attributes =
            optional_text parameters.connectivity_attributes;
          connectivity_tolerance = parameters.connectivity_tolerance;
          collision; region;
          remove_other_regions = parameters.remove_other_regions })
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_range ~label ?base:(optional_text parameters.base)
        ~invert:parameters.invert ?filter:(filter parameters)
        ?connectivity:(connectivity parameters) ~merge:parameters.merge
        ~owner:parameters.owner ~name:parameters.name (range parameters) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_range expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-range" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_ranges = struct
  let encode_specification = function
    | Pdk.Ops.Range_start_end { start; end_ } ->
        ["start_end"; string_of_int start; string_of_int end_]
    | Pdk.Ops.Range_from_ends { start; end_offset } ->
        ["from_ends"; string_of_int start; string_of_int end_offset]
    | Pdk.Ops.Range_start_length { start; length } ->
        ["start_length"; string_of_int start; string_of_int length]
    | Pdk.Ops.Range_partition { partition; partitions } ->
        ["partition"; string_of_int partition; string_of_int partitions]
  let decode_specification = function
    | [kind; a; b] ->
        let ( let* ) = Result.bind in
        let* a = int_of_token a in
        let* b = int_of_token b in
        (match String.lowercase_ascii (String.trim kind) with
         | "start_end" -> Ok (Pdk.Ops.Range_start_end { start = a; end_ = b })
         | "from_ends" -> Ok (Pdk.Ops.Range_from_ends {
             start = a; end_offset = b })
         | "start_length" -> Ok (Pdk.Ops.Range_start_length {
             start = a; length = b })
         | "partition" -> Ok (Pdk.Ops.Range_partition {
             partition = a; partitions = b })
         | token -> Error (Printf.sprintf "unknown range kind %S" token))
    | columns -> Error (Printf.sprintf
        "range specification needs 3 columns, got %d" (List.length columns))
  let encode_filter = function
    | None -> ["none"; "0"; "1"; "0"]
    | Some filter -> ["filter"; string_of_int filter.Pdk.Ops.select;
        string_of_int filter.of_; string_of_int filter.offset]
  let decode_filter = function
    | [kind; select; of_; offset] ->
        if String.lowercase_ascii (String.trim kind) = "none" then Ok None
        else
          let ( let* ) = Result.bind in
          let* select = int_of_token select in
          let* of_ = int_of_token of_ in
          let* offset = int_of_token offset in
          Ok (Some { Pdk.Ops.select; of_; offset })
    | columns -> Error (Printf.sprintf
        "range filter needs 4 columns, got %d" (List.length columns))
  let encode_connectivity = function
    | None -> ["none"; ""; ""; "0"; "false"; "edge"; "";
        "false"; "false"]
    | Some (Pdk.Ops.Range_disconnected { region }) -> [
        "disconnected"; Option.fold ~none:"" ~some:string_of_int region;
        ""; "0"; "false"; "edge"; ""; "false"; "false"]
    | Some (Pdk.Ops.Range_connected connectivity) ->
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
         | "disconnected" -> Ok (Some (Pdk.Ops.Range_disconnected { region }))
         | "connected" ->
             let* connectivity_tolerance = float_of_token tolerance in
             let* collision_enabled = bool_of_token collision_enabled in
             let* collision = if not collision_enabled then Ok None else
               let* collision_owner = group_owner_of_token
                   (String.lowercase_ascii (String.trim collision_owner)) in
               let* keep_boundary = bool_of_token keep_boundary in
               Ok (Some { Pdk.Ops.collision_owner; collision_pattern;
                 keep_boundary }) in
             let* remove_other_regions = bool_of_token remove_other_regions in
             Ok (Some (Pdk.Ops.Range_connected {
               connectivity_attributes = optional_text attributes;
               connectivity_tolerance; collision; region;
               remove_other_regions }))
         | token -> Error (Printf.sprintf
             "unknown range connectivity %S" token))
    | columns -> Error (Printf.sprintf
        "range connectivity needs 9 columns, got %d" (List.length columns))
  let encode_rule (rule : Pdk.Ops.group_range_rule) =
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
        Ok { Pdk.Ops.range_owner; range_name = name;
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
  let default_rules = [Pdk.Ops.group_range_rule
      ~owner:Pdk.Ops.Group_points ~name:"range"
      (Pdk.Ops.Range_start_end { start = 0; end_ = -1 })]
  type parameters = {
    rules : Pdk.Ops.group_range_rule list [@sop.default default_rules]
      [@sop.label "Range rules"] [@sop.kind rules_parameter];
  } [@@sop.node_key "group_ranges"] [@@sop.node_label "Group Ranges"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_ranges ~label parameters.rules input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_ranges expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-ranges" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Group_find_path = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Through each", Pdk.Ops.Through_each;
      "Start/end pairs", Pdk.Ops.Start_end_pairs;
    ]
  let ending_parameter = Parameter.choice ~equal:( = ) [
      "Stop at end", Pdk.Ops.Stop_at_end; "Close path", Pdk.Ops.Close_path;
    ]
  type parameters = {
    owner : Pdk.Group.owner [@sop.default Pdk.Group.Point]
      [@sop.label "Group type"] [@sop.kind ordinary_group_owner_parameter];
    base_group : string [@sop.default "ordered"] [@sop.label "Base group"];
    name : string [@sop.default "path"] [@sop.label "Output group"];
    mode : Pdk.Ops.group_path_mode [@sop.default Pdk.Ops.Through_each]
      [@sop.label "Path mode"] [@sop.kind mode_parameter];
    ending : Pdk.Ops.group_path_ending [@sop.default Pdk.Ops.Stop_at_end]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.group_find_path ~label ~mode:parameters.mode
        ~ending:parameters.ending
        ~avoid_self_intersection:parameters.avoid_self_intersection
        ~owner:parameters.owner
        ?collision_group:(optional_text parameters.collision_group)
        ~contain:parameters.contain ~base_group:parameters.base_group
        ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Group_find_path expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "group-find-path" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Poly_cut = struct
  type detection = All | Crossing | Change
  let element_parameter = Parameter.choice ~equal:( = ) [
      "Points", Pdk.Ops.Poly_cut_points; "Edges", Pdk.Ops.Poly_cut_edges;
    ]
  let strategy_parameter = Parameter.choice ~equal:( = ) [
      "Remove", Pdk.Ops.Poly_cut_remove; "Cut", Pdk.Ops.Poly_cut_cut;
    ]
  let detection_parameter = Parameter.choice ~equal:( = ) [
      "All selected", All; "Attribute crossing", Crossing;
      "Attribute change", Change;
    ]
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    cut_group : string [@sop.default ""] [@sop.label "Cut group"];
    element : Pdk.Ops.poly_cut_element [@sop.default Pdk.Ops.Poly_cut_points]
      [@sop.label "Cut elements"] [@sop.kind element_parameter];
    strategy : Pdk.Ops.poly_cut_strategy
      [@sop.default Pdk.Ops.Poly_cut_remove]
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
    | All -> Pdk.Ops.Poly_cut_all
    | Crossing -> Pdk.Ops.Poly_cut_crossing {
        attribute = parameters.attribute; value = parameters.value }
    | Change -> Pdk.Ops.Poly_cut_change {
        attribute = parameters.attribute; threshold = parameters.threshold }
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.poly_cut ~label ?group:(optional_text parameters.group)
        ?cut_group:(optional_text parameters.cut_group)
        ~element:parameters.element ~strategy:parameters.strategy
        ~detection:(detection parameters) ~keep_closed:parameters.keep_closed
        input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Poly_cut expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "poly-cut" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Sort = struct
  type key = X | Y | Z | Distance | Vector | Attribute | Vertex_order
    | Primitive_index | Spatial | Random | Index_attribute | Reverse | Shift
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Points", Pdk.Ops.Points; "Primitives", Pdk.Ops.Primitives;
    ]
  let key_parameter = Parameter.choice ~equal:( = ) [
      "X", X; "Y", Y; "Z", Z; "Distance to point", Distance;
      "Along vector", Vector; "Attribute component", Attribute;
      "Vertex order", Vertex_order; "Primitive index", Primitive_index;
      "Spatial locality", Spatial; "Random", Random;
      "Index attribute", Index_attribute; "Reverse", Reverse;
      "Shift", Shift;
    ]
  type parameters = {
    owner : Pdk.Ops.sort_owner [@sop.default Pdk.Ops.Points]
      [@sop.label "Entity"] [@sop.kind owner_parameter];
    key : key [@sop.default X] [@sop.label "Sort by"]
      [@sop.kind key_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    descending : bool [@sop.default false] [@sop.label "Descending"];
    x : float [@sop.default 0.] [@sop.label "X"]
      [@sop.folder "Key/Point or vector"] [@sop.min (-10.)] [@sop.max 10.];
    y : float [@sop.default 0.] [@sop.label "Y"]
      [@sop.folder "Key/Point or vector"] [@sop.min (-10.)] [@sop.max 10.];
    z : float [@sop.default 1.] [@sop.label "Z"]
      [@sop.folder "Key/Point or vector"] [@sop.min (-10.)] [@sop.max 10.];
    attribute : string [@sop.default "id"] [@sop.label "Attribute"]
      [@sop.folder "Key/Attribute"];
    component : int [@sop.default 0] [@sop.label "Component"]
      [@sop.folder "Key/Attribute"] [@sop.min 0] [@sop.max 15]
      [@sop.hard_min 0];
    seed : int [@sop.default 0] [@sop.label "Random seed"]
      [@sop.folder "Key"] [@sop.min 0] [@sop.max 9999];
    shift : int [@sop.default 1] [@sop.label "Shift"]
      [@sop.folder "Key"] [@sop.min (-100)] [@sop.max 100];
    output_indices : string [@sop.default ""] [@sop.label "Output indices"]
      [@sop.folder "Output"];
    combine_indices : bool [@sop.default false] [@sop.label "Combine indices"]
      [@sop.folder "Output"];
  } [@@sop.node_key "sort"] [@@sop.node_label "Sort"]
    [@@sop.node_category "Utility"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let key parameters = match parameters.key with
    | X -> Pdk.Ops.X | Y -> Pdk.Ops.Y | Z -> Pdk.Ops.Z
    | Distance -> Pdk.Ops.Distance_to
        (Vec3.create parameters.x parameters.y parameters.z)
    | Vector -> Pdk.Ops.Along_vector
        (Vec3.create parameters.x parameters.y parameters.z)
    | Attribute -> Pdk.Ops.Attribute_component {
        name = parameters.attribute; component = parameters.component }
    | Vertex_order -> Pdk.Ops.By_vertex_order
    | Primitive_index -> Pdk.Ops.By_primitive_index
    | Spatial -> Pdk.Ops.Spatial_locality
    | Random -> Pdk.Ops.Random (Int64.of_int parameters.seed)
    | Index_attribute -> Pdk.Ops.Index_attribute parameters.attribute
    | Reverse -> Pdk.Ops.Reverse
    | Shift -> Pdk.Ops.Shift parameters.shift
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.sort ~label ?group:(optional_text parameters.group)
        ~descending:parameters.descending
        ?output_indices:(optional_text parameters.output_indices)
        ~combine_indices:parameters.combine_indices ~owner:parameters.owner
        ~key:(key parameters) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Sort expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "sort" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Noise_displace = struct
  type parameters = {
    context_seed : bool [@sop.default false] [@sop.label "Use context seed"];
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.min 0]
      [@sop.max 9999];
    amplitude : float [@sop.default 0.1] [@sop.label "Amplitude"]
      [@sop.min (-10.)] [@sop.max 10.];
    frequency : float [@sop.default 1.] [@sop.label "Frequency"]
      [@sop.min 0.] [@sop.max 20.] [@sop.hard_min 0.];
  } [@@sop.node_key "noise_displace"] [@@sop.node_label "Noise Displace"]
    [@@sop.node_category "Deform/Noise"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.noise_displace ~label
        ?seed:(if parameters.context_seed then None else Some parameters.seed)
        ~amplitude:parameters.amplitude ~frequency:parameters.frequency input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Noise_displace expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "noise-displace" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.color_by_height ~label
        ~low:(Color.rgb parameters.low_red parameters.low_green
          parameters.low_blue)
        ~high:(Color.rgb parameters.high_red parameters.high_green
          parameters.high_blue) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Color_by_height expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "color-by-height" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Scatter = struct
  type parameters = {
    count : int [@sop.default 100] [@sop.label "Count"] [@sop.min 1]
      [@sop.max 100000] [@sop.hard_min 0];
    context_seed : bool [@sop.default false] [@sop.label "Use context seed"]
      [@sop.folder "Random"];
    seed : int [@sop.default 0] [@sop.label "Seed"]
      [@sop.folder "Random"] [@sop.min 0] [@sop.max 9999];
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    use_density : bool [@sop.default false] [@sop.label "Use density"]
      [@sop.folder "Density"];
    density_owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Primitive]
      [@sop.label "Owner"] [@sop.folder "Density"]
      [@sop.kind attribute_owner_parameter];
    density_attribute : string [@sop.default "density"]
      [@sop.label "Attribute"] [@sop.folder "Density"];
    point_pattern : string [@sop.default ""] [@sop.label "Point attributes"]
      [@sop.folder "Transfer"];
    vertex_pattern : string [@sop.default ""] [@sop.label "Vertex attributes"]
      [@sop.folder "Transfer"];
    primitive_pattern : string [@sop.default ""]
      [@sop.label "Primitive attributes"] [@sop.folder "Transfer"];
    detail_pattern : string [@sop.default ""] [@sop.label "Detail attributes"]
      [@sop.folder "Transfer"];
    match_groups : bool [@sop.default false] [@sop.label "Match groups"]
      [@sop.folder "Transfer"];
    source_primitive_attribute : string [@sop.default ""]
      [@sop.label "Source primitive"] [@sop.folder "Provenance"];
    source_vertex_numbers_attribute : string [@sop.default ""]
      [@sop.label "Source vertex numbers"] [@sop.folder "Provenance"];
    source_vertex_weights_attribute : string [@sop.default ""]
      [@sop.label "Source vertex weights"] [@sop.folder "Provenance"];
  } [@@sop.node_key "scatter"] [@@sop.node_label "Scatter"]
    [@@sop.node_category "Create/Points"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let density = if not parameters.use_density then None else
          Some (Pdk.Ops.scatter_density ~owner:parameters.density_owner
            parameters.density_attribute) in
        Sop.scatter ~label
          ?seed:(if parameters.context_seed then None else Some parameters.seed)
          ?group:(optional_text parameters.group) ?density
          ?point_pattern:(optional_text parameters.point_pattern)
          ?vertex_pattern:(optional_text parameters.vertex_pattern)
          ?primitive_pattern:(optional_text parameters.primitive_pattern)
          ?detail_pattern:(optional_text parameters.detail_pattern)
          ~match_groups:parameters.match_groups
          ?source_primitive_attribute:
            (optional_text parameters.source_primitive_attribute)
          ?source_vertex_numbers_attribute:
            (optional_text parameters.source_vertex_numbers_attribute)
          ?source_vertex_weights_attribute:
            (optional_text parameters.source_vertex_weights_attribute)
          ~count:parameters.count input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Scatter expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "scatter" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Attribute_noise = struct
  type location = Position | Element_number | Attribute
  type range = Positive | Zero_centered | Min_max
  let kind_parameter = Parameter.choice ~equal:( = ) [
      "Float", Pdk.Attribute_ops.Noise_float;
      "Vector", Pdk.Attribute_ops.Noise_vector;
      "Quaternion", Pdk.Attribute_ops.Noise_quaternion;
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
      "Set initial", Pdk.Attribute_ops.Noise_set_initial;
      "Set", Pdk.Attribute_ops.Noise_set;
      "Add", Pdk.Attribute_ops.Noise_add;
      "Subtract", Pdk.Attribute_ops.Noise_subtract;
      "Multiply", Pdk.Attribute_ops.Noise_multiply;
      "Minimum", Pdk.Attribute_ops.Noise_minimum;
      "Maximum", Pdk.Attribute_ops.Noise_maximum;
    ]
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "noise"] [@sop.label "Attribute"];
    group : string [@sop.default ""] [@sop.label "Group"];
    kind : Pdk.Attribute_ops.noise_kind
      [@sop.default Pdk.Attribute_ops.Noise_float] [@sop.label "Type"]
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
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    min_y : float [@sop.default 0.] [@sop.label "Minimum Y"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    min_z : float [@sop.default 0.] [@sop.label "Minimum Z"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    min_w : float [@sop.default 0.] [@sop.label "Minimum W"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    max_x : float [@sop.default 1.] [@sop.label "Maximum X"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    max_y : float [@sop.default 1.] [@sop.label "Maximum Y"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    max_z : float [@sop.default 1.] [@sop.label "Maximum Z"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    max_w : float [@sop.default 1.] [@sop.label "Maximum W"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    operation : Pdk.Attribute_ops.noise_operation
      [@sop.default Pdk.Attribute_ops.Noise_set] [@sop.label "Operation"]
      [@sop.folder "Output"] [@sop.kind operation_parameter];
    blend : float [@sop.default 1.] [@sop.label "Blend"]
      [@sop.folder "Output"] [@sop.min 0.] [@sop.max 1.];
    frequency_x : float [@sop.default 1.] [@sop.label "Frequency X"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.];
    frequency_y : float [@sop.default 1.] [@sop.label "Frequency Y"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.];
    frequency_z : float [@sop.default 1.] [@sop.label "Frequency Z"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.];
    offset_x : float [@sop.default 0.] [@sop.label "Offset X"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    offset_y : float [@sop.default 0.] [@sop.label "Offset Y"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    offset_z : float [@sop.default 0.] [@sop.label "Offset Z"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.];
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
    | Pdk.Attribute_ops.Noise_float -> Numeric_scalar
    | Pdk.Attribute_ops.Noise_vector -> Numeric_vec3
    | Pdk.Attribute_ops.Noise_quaternion -> Numeric_vec4
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let location = match parameters.location with
          | Position -> Pdk.Attribute_ops.Noise_position
          | Element_number -> Pdk.Attribute_ops.Noise_element_number
          | Attribute -> Pdk.Attribute_ops.Noise_attribute
              parameters.location_attribute in
        let range = match parameters.range with
          | Positive -> Pdk.Attribute_ops.Noise_positive
          | Zero_centered -> Pdk.Attribute_ops.Noise_zero_centered
          | Min_max -> let kind = numeric_kind parameters.kind in
              Pdk.Attribute_ops.Noise_min_max
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
          ~name:parameters.name parameters.kind input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_noise expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "attribute-noise" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Attribute_remap = struct
  type input_range = Automatic | Explicit
  let input_parameter = Parameter.choice ~equal:( = ) [
      "Automatic", Automatic; "Explicit", Explicit;
    ]
  let policy_parameter = Parameter.choice ~equal:( = ) [
      "Clamp", Pdk.Attribute_ops.Remap_clamp;
      "Cycle", Pdk.Attribute_ops.Remap_cycle;
      "Extrapolate", Pdk.Attribute_ops.Remap_extrapolate;
    ]
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "value"] [@sop.label "Source attribute"];
    into : string [@sop.default ""] [@sop.label "Destination attribute"];
    group : string [@sop.default ""] [@sop.label "Group"];
    kind : numeric_kind [@sop.default Numeric_scalar] [@sop.label "Value type"]
      [@sop.kind numeric_kind_parameter];
    input_range : input_range [@sop.default Automatic]
      [@sop.label "Input range"] [@sop.kind input_parameter];
    input_min_x : float [@sop.default 0.] [@sop.label "Minimum X"]
      [@sop.folder "Input/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    input_min_y : float [@sop.default 0.] [@sop.label "Minimum Y"]
      [@sop.folder "Input/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    input_min_z : float [@sop.default 0.] [@sop.label "Minimum Z"]
      [@sop.folder "Input/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    input_min_w : float [@sop.default 0.] [@sop.label "Minimum W"]
      [@sop.folder "Input/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    input_max_x : float [@sop.default 1.] [@sop.label "Maximum X"]
      [@sop.folder "Input/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    input_max_y : float [@sop.default 1.] [@sop.label "Maximum Y"]
      [@sop.folder "Input/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    input_max_z : float [@sop.default 1.] [@sop.label "Maximum Z"]
      [@sop.folder "Input/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    input_max_w : float [@sop.default 1.] [@sop.label "Maximum W"]
      [@sop.folder "Input/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    output_min_x : float [@sop.default 0.] [@sop.label "Minimum X"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    output_min_y : float [@sop.default 0.] [@sop.label "Minimum Y"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    output_min_z : float [@sop.default 0.] [@sop.label "Minimum Z"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    output_min_w : float [@sop.default 0.] [@sop.label "Minimum W"]
      [@sop.folder "Output/Minimum"] [@sop.min (-10.)] [@sop.max 10.];
    output_max_x : float [@sop.default 1.] [@sop.label "Maximum X"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    output_max_y : float [@sop.default 1.] [@sop.label "Maximum Y"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    output_max_z : float [@sop.default 1.] [@sop.label "Maximum Z"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    output_max_w : float [@sop.default 1.] [@sop.label "Maximum W"]
      [@sop.folder "Output/Maximum"] [@sop.min (-10.)] [@sop.max 10.];
    policy : Pdk.Attribute_ops.remap_policy
      [@sop.default Pdk.Attribute_ops.Remap_clamp] [@sop.label "Outside range"]
      [@sop.kind policy_parameter];
  } [@@sop.node_key "attribute_remap"] [@@sop.node_label "Attribute Remap"]
    [@@sop.node_category "Attribute/Modify"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input_node] ->
        let value x y z w = numeric_value parameters.kind x y z w in
        let input = match parameters.input_range with
          | Automatic -> Pdk.Attribute_ops.Remap_auto
          | Explicit -> Pdk.Attribute_ops.Remap_explicit {
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
            parameters.output_max_z parameters.output_max_w) input_node
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_remap expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "attribute-remap" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
      "Set", Pdk.Attribute_ops.Random_set;
      "Add", Pdk.Attribute_ops.Random_add;
      "Minimum", Pdk.Attribute_ops.Random_minimum;
      "Maximum", Pdk.Attribute_ops.Random_maximum;
      "Multiply", Pdk.Attribute_ops.Random_multiply;
    ]
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
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
      [@sop.folder "Distribution/A"] [@sop.min (-10.)] [@sop.max 10.];
    a_y : float [@sop.default 0.] [@sop.label "A / minimum Y"]
      [@sop.folder "Distribution/A"] [@sop.min (-10.)] [@sop.max 10.];
    a_z : float [@sop.default 0.] [@sop.label "A / minimum Z"]
      [@sop.folder "Distribution/A"] [@sop.min (-10.)] [@sop.max 10.];
    a_w : float [@sop.default 0.] [@sop.label "A / minimum W"]
      [@sop.folder "Distribution/A"] [@sop.min (-10.)] [@sop.max 10.];
    b_x : float [@sop.default 1.] [@sop.label "B / maximum X"]
      [@sop.folder "Distribution/B"] [@sop.min (-10.)] [@sop.max 10.];
    b_y : float [@sop.default 1.] [@sop.label "B / maximum Y"]
      [@sop.folder "Distribution/B"] [@sop.min (-10.)] [@sop.max 10.];
    b_z : float [@sop.default 1.] [@sop.label "B / maximum Z"]
      [@sop.folder "Distribution/B"] [@sop.min (-10.)] [@sop.max 10.];
    b_w : float [@sop.default 1.] [@sop.label "B / maximum W"]
      [@sop.folder "Distribution/B"] [@sop.min (-10.)] [@sop.max 10.];
    step_x : float [@sop.default 1.] [@sop.label "Step X"]
      [@sop.folder "Distribution/Step"] [@sop.min 0.] [@sop.max 10.];
    step_y : float [@sop.default 1.] [@sop.label "Step Y"]
      [@sop.folder "Distribution/Step"] [@sop.min 0.] [@sop.max 10.];
    step_z : float [@sop.default 1.] [@sop.label "Step Z"]
      [@sop.folder "Distribution/Step"] [@sop.min 0.] [@sop.max 10.];
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
    operation : Pdk.Attribute_ops.random_operation
      [@sop.default Pdk.Attribute_ops.Random_set] [@sop.label "Operation"]
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
    | Constant -> Pdk.Attribute_ops.Random_constant a
    | Two_values -> Pdk.Attribute_ops.Random_two_values {
        a; b; probability_b = parameters.probability_b }
    | Uniform -> Pdk.Attribute_ops.Random_uniform { min = a; max = b }
    | Uniform_discrete -> Pdk.Attribute_ops.Random_uniform_discrete {
        min = a; max = b; step }
    | Normal -> Pdk.Attribute_ops.Random_normal { middle = a; scale = b }
    | Exponential -> Pdk.Attribute_ops.Random_exponential { median = a }
    | Log_normal -> Pdk.Attribute_ops.Random_log_normal {
        median = a; stddev = b }
    | Cauchy -> Pdk.Attribute_ops.Random_cauchy { median = a; scale = b }
    | Direction -> Pdk.Attribute_ops.Random_direction {
        direction = a; cone_angle = parameters.cone_angle }
    | Inside_sphere -> Pdk.Attribute_ops.Random_inside_sphere {
        dimensions = parameters.dimensions }
    | Inside_sphere_cone -> Pdk.Attribute_ops.Random_inside_sphere_cone {
        direction = a; cone_angle = parameters.cone_angle }
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          (distribution parameters) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_randomize expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "attribute-randomize" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Attribute_mirror = struct
  type method_ = Plane | Mapping
  type transform = Copy | Uv | Vector | Point
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Point", Pdk.Ops.Mirror_point_attributes;
      "Vertex", Pdk.Ops.Mirror_vertex_attributes;
      "Primitive", Pdk.Ops.Mirror_primitive_attributes;
    ]
  let group_use_parameter = Parameter.choice ~equal:( = ) [
      "Group is source", Pdk.Ops.Mirror_group_as_source;
      "Group is destination", Pdk.Ops.Mirror_group_as_destination;
    ]
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Plane", Plane; "Mapping attribute", Mapping;
    ]
  let transform_parameter = Parameter.choice ~equal:( = ) [
      "Copy", Copy; "UV", Uv; "Vector", Vector; "Point", Point;
    ]
  type parameters = {
    owner : Pdk.Ops.attribute_mirror_owner
      [@sop.default Pdk.Ops.Mirror_point_attributes]
      [@sop.label "Attribute owner"] [@sop.kind owner_parameter];
    attributes : string [@sop.default "Cd"] [@sop.label "Attributes"];
    group : string [@sop.default ""] [@sop.label "Selection group"];
    group_use : Pdk.Ops.attribute_mirror_group_use
      [@sop.default Pdk.Ops.Mirror_group_as_source]
      [@sop.label "Group use"] [@sop.kind group_use_parameter];
    method_ : method_ [@sop.default Plane] [@sop.label "Mirror method"]
      [@sop.kind method_parameter];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.];
    normal_x : float [@sop.default 1.] [@sop.label "Normal X"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.];
    normal_y : float [@sop.default 0.] [@sop.label "Normal Y"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.];
    normal_z : float [@sop.default 0.] [@sop.label "Normal Z"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.];
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
    | Copy -> Pdk.Ops.Mirror_copy
    | Uv -> Pdk.Ops.Mirror_uv { origin_u = parameters.uv_origin_u;
        origin_v = parameters.uv_origin_v;
        direction_u = parameters.uv_direction_u;
        direction_v = parameters.uv_direction_v }
    | Vector -> Pdk.Ops.Mirror_vector
    | Point -> Pdk.Ops.Mirror_point
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.attribute_mirror ~label
        ?group:(optional_text parameters.group) ~group_use:parameters.group_use
        ~attributes:parameters.attributes ~transform:(transform parameters)
        ?string_replace:(if parameters.replace_strings then
          Some (parameters.string_search, parameters.string_replacement)
          else None)
        ?output_mapping:(optional_text parameters.output_mapping)
        ?source_group:(optional_text parameters.source_group)
        ?destination_group:(optional_text parameters.destination_group)
        ~owner:parameters.owner ~method_:(method_ parameters) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_mirror expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "attribute-mirror" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Rewire_vertices = struct
  type parameters = {
    selection_owner : element_owner [@sop.default Element_vertex]
      [@sop.label "Selection owner"] [@sop.kind element_owner_parameter];
    selection : string [@sop.default ""] [@sop.label "Selection group"];
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Vertex]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.rewire_vertices ~label
        ?selection:(optional_element_group parameters.selection_owner
          parameters.selection)
        ~recursive:parameters.recursive
        ~delete_target_attribute:parameters.delete_target_attribute
        ~keep_unused_points:parameters.keep_unused_points
        ?original_point_attribute:
          (optional_text parameters.original_point_attribute)
        ~owner:parameters.owner ~target_attribute:parameters.target_attribute
        input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Rewire_vertices expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "rewire-vertices" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

type transport_roots = Transport_first | Transport_last | Transport_group
let transport_roots_parameter = Parameter.choice ~equal:( = ) [
    "First point", Transport_first; "Last point", Transport_last;
    "Root group", Transport_group;
  ]
let transport_roots mode group = match mode with
  | Transport_first -> None, Pdk.Ops.Transport_first_point
  | Transport_last -> None, Pdk.Ops.Transport_last_point
  | Transport_group -> optional_text group, Pdk.Ops.Transport_first_point

module Edge_transport = struct
  type parameters = {
    attribute : string [@sop.default "value"] [@sop.label "Attribute"];
    point_group : string [@sop.default ""] [@sop.label "Point group"];
    roots : transport_roots [@sop.default Transport_first]
      [@sop.label "Roots"] [@sop.kind transport_roots_parameter];
    root_group : string [@sop.default ""] [@sop.label "Root group"];
    direction : Pdk.Ops.edge_transport_direction
      [@sop.default Pdk.Ops.Transport_forward] [@sop.label "Direction"]
      [@sop.kind edge_transport_direction_parameter];
    operation : Pdk.Ops.edge_transport_operation
      [@sop.default Pdk.Ops.Transport] [@sop.label "Operation"]
      [@sop.kind edge_transport_operation_parameter];
    root_value : Pdk.Ops.edge_transport_root_value
      [@sop.default Pdk.Ops.Transport_root_zero] [@sop.label "Root value"]
      [@sop.kind edge_transport_root_value_parameter];
    integrate_constant : bool [@sop.default false]
      [@sop.label "Integrate constant"];
    scale_by_edge_length : bool [@sop.default false]
      [@sop.label "Scale by edge length"];
    split : Pdk.Ops.edge_transport_split [@sop.default Pdk.Ops.Transport_copy]
      [@sop.label "Branch split"] [@sop.kind edge_transport_split_parameter];
    merge : Pdk.Ops.edge_transport_merge
      [@sop.default Pdk.Ops.Transport_merge_add]
      [@sop.label "Branch merge"] [@sop.kind edge_transport_merge_parameter];
    normalization : Pdk.Ops.edge_transport_normalization
      [@sop.default Pdk.Ops.Transport_no_normalization]
      [@sop.label "Normalization"]
      [@sop.kind edge_transport_normalization_parameter];
  } [@@sop.node_key "edge_transport"] [@@sop.node_label "Edge Transport"]
    [@@sop.node_category "Attribute/Transport"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
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
          ~attribute:parameters.attribute input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Edge_transport expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "edge-transport" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Edge_transport_curves = struct
  type parameters = {
    attribute : string [@sop.default "value"] [@sop.label "Attribute"];
    primitive_group : string [@sop.default ""]
      [@sop.label "Primitive group"];
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Attribute owner"] [@sop.kind uv_owner_parameter];
    direction : Pdk.Ops.edge_transport_direction
      [@sop.default Pdk.Ops.Transport_forward] [@sop.label "Direction"]
      [@sop.kind edge_transport_direction_parameter];
    operation : Pdk.Ops.edge_transport_operation
      [@sop.default Pdk.Ops.Transport] [@sop.label "Operation"]
      [@sop.kind edge_transport_operation_parameter];
    root_value : Pdk.Ops.edge_transport_root_value
      [@sop.default Pdk.Ops.Transport_root_zero] [@sop.label "Root value"]
      [@sop.kind edge_transport_root_value_parameter];
    integrate_constant : bool [@sop.default false]
      [@sop.label "Integrate constant"];
    scale_by_edge_length : bool [@sop.default false]
      [@sop.label "Scale by edge length"];
    normalization : Pdk.Ops.edge_transport_normalization
      [@sop.default Pdk.Ops.Transport_no_normalization]
      [@sop.label "Normalization"]
      [@sop.kind edge_transport_normalization_parameter];
  } [@@sop.node_key "edge_transport_curves"]
    [@@sop.node_label "Edge Transport Curves"]
    [@@sop.node_category "Attribute/Transport"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.edge_transport_curves ~label
        ?primitive_group:(optional_text parameters.primitive_group)
        ~owner:parameters.owner ~direction:parameters.direction
        ~operation:parameters.operation ~root_value:parameters.root_value
        ~integrate_constant:parameters.integrate_constant
        ~scale_by_edge_length:parameters.scale_by_edge_length
        ~normalization:parameters.normalization
        ~attribute:parameters.attribute input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Edge_transport_curves expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "edge-transport-curves" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Edge_transport_parent = struct
  type parameters = {
    attribute : string [@sop.default "value"] [@sop.label "Attribute"];
    point_group : string [@sop.default ""] [@sop.label "Point group"];
    parent_attribute : string [@sop.default "parent"]
      [@sop.label "Parent attribute"];
    direction : Pdk.Ops.edge_transport_direction
      [@sop.default Pdk.Ops.Transport_forward] [@sop.label "Direction"]
      [@sop.kind edge_transport_direction_parameter];
    operation : Pdk.Ops.edge_transport_operation
      [@sop.default Pdk.Ops.Transport] [@sop.label "Operation"]
      [@sop.kind edge_transport_operation_parameter];
    root_value : Pdk.Ops.edge_transport_root_value
      [@sop.default Pdk.Ops.Transport_root_zero] [@sop.label "Root value"]
      [@sop.kind edge_transport_root_value_parameter];
    integrate_constant : bool [@sop.default false]
      [@sop.label "Integrate constant"];
    scale_by_edge_length : bool [@sop.default false]
      [@sop.label "Scale by edge length"];
    split : Pdk.Ops.edge_transport_split [@sop.default Pdk.Ops.Transport_copy]
      [@sop.label "Branch split"] [@sop.kind edge_transport_split_parameter];
    merge : Pdk.Ops.edge_transport_merge
      [@sop.default Pdk.Ops.Transport_merge_add]
      [@sop.label "Branch merge"] [@sop.kind edge_transport_merge_parameter];
    normalization : Pdk.Ops.edge_transport_normalization
      [@sop.default Pdk.Ops.Transport_no_normalization]
      [@sop.label "Normalization"]
      [@sop.kind edge_transport_normalization_parameter];
  } [@@sop.node_key "edge_transport_parent"]
    [@@sop.node_label "Edge Transport Parent"]
    [@@sop.node_category "Attribute/Transport"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.edge_transport_parent ~label
        ?point_group:(optional_text parameters.point_group)
        ~parent_attribute:parameters.parent_attribute
        ~direction:parameters.direction ~operation:parameters.operation
        ~root_value:parameters.root_value
        ~integrate_constant:parameters.integrate_constant
        ~scale_by_edge_length:parameters.scale_by_edge_length
        ~split:parameters.split ~merge:parameters.merge
        ~normalization:parameters.normalization
        ~attribute:parameters.attribute input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Edge_transport_parent expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "edge-transport-parent" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Blast_by_attribute = struct
  type mode = Below | Range | Width
  type output = Delete | Group
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Points", Pdk.Ops.Blast_points;
      "Primitives", Pdk.Ops.Blast_primitives;
    ]
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Below threshold", Below; "Range", Range; "Center and width", Width;
    ]
  let output_parameter = Parameter.choice ~equal:( = ) [
      "Delete elements", Delete; "Create group", Group;
    ]
  type parameters = {
    owner : Pdk.Ops.blast_attribute_owner [@sop.default Pdk.Ops.Blast_points]
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
    | Below -> Pdk.Ops.Blast_below parameters.threshold
    | Range -> Pdk.Ops.Blast_range {
        minimum = parameters.minimum; maximum = parameters.maximum }
    | Width -> Pdk.Ops.Blast_width {
        center = parameters.center; width = parameters.width }
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let output = match parameters.output with
          | Delete -> Pdk.Ops.Blast_delete
          | Group -> Pdk.Ops.Blast_group parameters.output_group in
        Sop.blast_by_attribute ~label
          ?group:(optional_text parameters.group) ~invert:parameters.invert
          ~remove_unused_points:parameters.remove_unused_points
          ~owner:parameters.owner ~attribute:parameters.attribute
          ~mode:(blast_mode parameters) ~output input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Blast_by_attribute expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "blast-by-attribute" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Blast = struct
  type parameters = {
    owner : Pdk.Group.owner [@sop.default Pdk.Group.Primitive]
      [@sop.label "Group type"] [@sop.kind ordinary_group_owner_parameter];
    group : string [@sop.default "group"] [@sop.label "Group"];
    selected : bool [@sop.default true] [@sop.label "Delete selected"];
    compact_points : bool [@sop.default false]
      [@sop.label "Remove unused points"];
    policy : Pdk.Ops.delete_topology_policy
      [@sop.default Pdk.Ops.Destroy_touched_primitives]
      [@sop.label "Point deletion policy"]
      [@sop.kind delete_topology_policy_parameter];
  } [@@sop.node_key "blast"] [@@sop.node_label "Blast"]
    [@@sop.node_category "Topology/Delete"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.blast ~label ~selected:parameters.selected
        ~compact_points:parameters.compact_points ~policy:parameters.policy
        ~owner:parameters.owner ~group:parameters.group input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Blast expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "blast" node_label) ~inputs:[input] parameters_default
end [@@sop.register]

module Compact_points = struct
  let factory = Edit_graph.factory ~key:"compact_points"
      ~label:"Compact Points" ~category:["Topology"; "Cleanup"] ~arity:1
      (function
        | [input] -> Sop.compact_points ~label:"compact-points" input
        | _ -> invalid_arg "Compact Points SOP expects one input")
  let create ?label:node_label input = Sop.compact_points
      ~label:(label "compact-points" node_label) input
end [@@sop.register]

module Bounding_box = struct
  type parameters = {
    padding_x : float [@sop.default 0.] [@sop.label "Padding X"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
    padding_y : float [@sop.default 0.] [@sop.label "Padding Y"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
    padding_z : float [@sop.default 0.] [@sop.label "Padding Z"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
  } [@@sop.node_key "bounding_box"] [@@sop.node_label "Bounding Box"]
    [@@sop.node_category "Create/Bounds"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.bounding_box ~label
        ~padding:(Vec3.create parameters.padding_x parameters.padding_y
          parameters.padding_z) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Bounding_box expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "bounding-box" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Rename_group = struct
  type parameters = {
    owner : Pdk.Group.owner [@sop.default Pdk.Group.Point]
      [@sop.label "Group type"] [@sop.kind ordinary_group_owner_parameter];
    from : string [@sop.default "group"] [@sop.label "From"];
    into : string [@sop.default "renamed"] [@sop.label "To"];
  } [@@sop.node_key "rename_group"] [@@sop.node_label "Rename Group"]
    [@@sop.node_category "Group/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.rename_group ~label ~owner:parameters.owner
        ~from:parameters.from ~into:parameters.into input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Rename_group expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "rename-group" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Delete_edge_group = struct
  type parameters = {
    name : string [@sop.default "edges"] [@sop.label "Edge group"];
  } [@@sop.node_key "delete_edge_group"]
    [@@sop.node_label "Delete Edge Group"]
    [@@sop.node_category "Group/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.delete_edge_group ~label ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Delete_edge_group expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "delete-edge-group" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Rename_edge_group = struct
  type parameters = {
    from : string [@sop.default "edges"] [@sop.label "From"];
    into : string [@sop.default "renamed"] [@sop.label "To"];
  } [@@sop.node_key "rename_edge_group"]
    [@@sop.node_label "Rename Edge Group"]
    [@@sop.node_category "Group/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.rename_edge_group ~label ~from:parameters.from
        ~into:parameters.into input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Rename_edge_group expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "rename-edge-group" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
    [@@sop.node_category "Attribute/Manage"] [@@sop.node_inputs 2]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]
  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; reference] -> Sop.delete_attributes ~label ?reference
        ~delete_non_selected:parameters.delete_non_selected
        ?point_pattern:(optional_text parameters.point_pattern)
        ?vertex_pattern:(optional_text parameters.vertex_pattern)
        ?primitive_pattern:(optional_text parameters.primitive_pattern)
        ?detail_pattern:(optional_text parameters.detail_pattern) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild
    | _ -> invalid_arg "Sop_catalog.Delete_attributes requires its source input"
  and rebuild ~label ~inputs parameters = match inputs with
    | [input] -> build_slots ~label ~inputs:[Some input; None] parameters
    | [input; reference] ->
        build_slots ~label ~inputs:[Some input; Some reference] parameters
    | _ -> invalid_arg "Sop_catalog.Delete_attributes has invalid physical inputs"
  let factory = parameters_factory build_slots
  let create ?label:node_label ?reference input = build_slots
      ~label:(label "delete-attributes" node_label)
      ~inputs:[Some input; reference] parameters_default
end [@@sop.register]

module Rename_attributes = struct
  let conflict_token = function
    | Pdk.Attribute_ops.Attribute_rename_skip -> "skip"
    | Pdk.Attribute_ops.Attribute_rename_error -> "error"
    | Pdk.Attribute_ops.Attribute_rename_overwrite -> "overwrite"
  let conflict_of_token = function
    | "skip" -> Ok Pdk.Attribute_ops.Attribute_rename_skip
    | "error" -> Ok Pdk.Attribute_ops.Attribute_rename_error
    | "overwrite" -> Ok Pdk.Attribute_ops.Attribute_rename_overwrite
    | token -> Error (Printf.sprintf
        "unknown attribute rename conflict %S" token)
  let encode_rule (rule : Pdk.Attribute_ops.rename_rule) = [
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
            Pdk.Attribute_ops.rename_attribute_owner;
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
    rules : Pdk.Attribute_ops.rename_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, replacement, conflict)"]
      [@sop.kind rules_parameter];
  } [@@sop.node_key "rename_attributes"]
    [@@sop.node_operation "attribute_rename_pattern"]
    [@@sop.node_label "Rename Attributes"]
    [@@sop.node_category "Attribute/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.rename_attributes ~label ~rules:parameters.rules input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Rename_attributes expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "rename-attributes" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Swap_attributes = struct
  let method_token = function
    | Pdk.Attribute_ops.Attribute_swap -> "swap"
    | Pdk.Attribute_ops.Attribute_move -> "move"
    | Pdk.Attribute_ops.Attribute_copy -> "copy"
  let method_of_token = function
    | "swap" -> Ok Pdk.Attribute_ops.Attribute_swap
    | "move" -> Ok Pdk.Attribute_ops.Attribute_move
    | "copy" -> Ok Pdk.Attribute_ops.Attribute_copy
    | token -> Error (Printf.sprintf "unknown attribute swap method %S" token)
  let encode_rule (rule : Pdk.Attribute_ops.swap_rule) = [
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
              Pdk.Attribute_ops.swap_attribute_owner;
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
    rules : Pdk.Attribute_ops.swap_rule list [@sop.default []]
      [@sop.label "Rules (owner, source, destination, method)"]
      [@sop.kind rules_parameter];
  } [@@sop.node_key "swap_attributes"]
    [@@sop.node_operation "attribute_swap"]
    [@@sop.node_label "Swap Attributes"]
    [@@sop.node_category "Attribute/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.swap_attributes ~label ~rules:parameters.rules input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Swap_attributes expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "swap-attributes" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

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
      [@sop.folder "Projection/Plane"] [@sop.min (-10.)] [@sop.max 10.];
    plane_origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Projection/Plane"] [@sop.min (-10.)] [@sop.max 10.];
    plane_origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Projection/Plane"] [@sop.min (-10.)] [@sop.max 10.];
    plane_normal_x : float [@sop.default 0.] [@sop.label "Normal X"]
      [@sop.folder "Projection/Plane"] [@sop.min (-1.)] [@sop.max 1.];
    plane_normal_y : float [@sop.default 0.] [@sop.label "Normal Y"]
      [@sop.folder "Projection/Plane"] [@sop.min (-1.)] [@sop.max 1.];
    plane_normal_z : float [@sop.default 1.] [@sop.label "Normal Z"]
      [@sop.folder "Projection/Plane"] [@sop.min (-1.)] [@sop.max 1.];
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
    | Best_fit -> Pdk.Ops.Triangulate_2d_best_fit
    | XY -> Pdk.Ops.Triangulate_2d_xy
    | YZ -> Pdk.Ops.Triangulate_2d_yz
    | ZX -> Pdk.Ops.Triangulate_2d_zx
    | Plane -> Pdk.Ops.Triangulate_2d_plane {
        origin = Vec3.create parameters.plane_origin_x parameters.plane_origin_y
          parameters.plane_origin_z;
        normal = Vec3.create parameters.plane_normal_x parameters.plane_normal_y
          parameters.plane_normal_z }
    | Point_attribute ->
        Pdk.Ops.Triangulate_2d_point_attribute parameters.point_attribute
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.triangulate_2d ~label
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
        ?constraint_group:(optional_text parameters.constraint_group) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Triangulate_2d expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "triangulate-2d" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Extract_point_from_curve = struct
  type cut = Constant | Primitive_attribute | Current_time
  let cut_parameter = Parameter.choice ~equal:( = ) [
      "Constant", Constant; "Primitive attribute", Primitive_attribute;
      "Current time", Current_time;
    ]
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    distance_attribute : string [@sop.default "distance"]
      [@sop.label "Distance attribute"];
    cut : cut [@sop.default Constant] [@sop.label "Cut value"]
      [@sop.kind cut_parameter];
    constant : float [@sop.default 0.] [@sop.label "Constant"]
      [@sop.folder "Cut"] [@sop.min (-10.)] [@sop.max 10.];
    primitive_attribute : string [@sop.default "cut"]
      [@sop.label "Primitive attribute"] [@sop.folder "Cut"];
    point_attributes : string [@sop.default "P"]
      [@sop.label "Point attributes"] [@sop.folder "Transfer"];
    copy_primitive_attributes : bool [@sop.default false]
      [@sop.label "Copy primitive attributes"] [@sop.folder "Transfer"];
    primitive_attributes : string [@sop.default "*"]
      [@sop.label "Primitive attributes"] [@sop.folder "Transfer"];
    curve_u_attribute : string [@sop.default ""] [@sop.label "Curve U"]
      [@sop.folder "Output"];
    number_cuts_attribute : string [@sop.default ""]
      [@sop.label "Number of cuts"] [@sop.folder "Output"];
    curve_number_attribute : string [@sop.default ""]
      [@sop.label "Curve number"] [@sop.folder "Output"];
  } [@@sop.node_key "extract_point_from_curve"]
    [@@sop.node_label "Extract Point from Curve"]
    [@@sop.node_category "Create/Points"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let cut parameters = match parameters.cut with
    | Constant -> Sop.Extract_point_constant parameters.constant
    | Primitive_attribute ->
        Sop.Extract_point_primitive_attribute parameters.primitive_attribute
    | Current_time -> Sop.Extract_point_current_time
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.extract_point_from_curve ~label
        ?group:(optional_text parameters.group) ~cut:(cut parameters)
        ~point_attributes:parameters.point_attributes
        ~copy_primitive_attributes:parameters.copy_primitive_attributes
        ~primitive_attributes:parameters.primitive_attributes
        ?curve_u_attribute:(optional_text parameters.curve_u_attribute)
        ?number_cuts_attribute:(optional_text parameters.number_cuts_attribute)
        ?curve_number_attribute:(optional_text parameters.curve_number_attribute)
        ~distance_attribute:parameters.distance_attribute input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Extract_point_from_curve expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "extract-point-from-curve" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Soft_transform = struct
  type metric = Radius | Edge | Attribute
  let order_parameter = Parameter.choice ~equal:( = ) [
      "SRT", Pdk.Ops.Transform_srt; "STR", Pdk.Ops.Transform_str;
      "RST", Pdk.Ops.Transform_rst; "RTS", Pdk.Ops.Transform_rts;
      "TSR", Pdk.Ops.Transform_tsr; "TRS", Pdk.Ops.Transform_trs;
    ]
  let rotation_order_parameter = Parameter.choice ~equal:( = ) [
      "XYZ", Pdk.Ops.Transform_xyz; "XZY", Pdk.Ops.Transform_xzy;
      "YXZ", Pdk.Ops.Transform_yxz; "YZX", Pdk.Ops.Transform_yzx;
      "ZXY", Pdk.Ops.Transform_zxy; "ZYX", Pdk.Ops.Transform_zyx;
    ]
  let metric_parameter = Parameter.choice ~equal:( = ) [
      "Radius", Radius; "Edge distance", Edge; "Attribute", Attribute;
    ]
  type parameters = {
    group_owner : element_owner [@sop.default Element_point]
      [@sop.label "Group type"] [@sop.folder "Selection"]
      [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"]
      [@sop.folder "Selection"];
    order : Pdk.Ops.transform_order [@sop.default Pdk.Ops.Transform_srt]
      [@sop.label "Transform order"] [@sop.folder "Transform"]
      [@sop.kind order_parameter];
    rotation_order : Pdk.Ops.transform_rotation_order
      [@sop.default Pdk.Ops.Transform_xyz] [@sop.label "Rotation order"]
      [@sop.folder "Transform/Rotate"] [@sop.kind rotation_order_parameter];
    translate_x : float [@sop.default 0.] [@sop.label "Translate X"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.];
    translate_y : float [@sop.default 0.] [@sop.label "Translate Y"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.];
    translate_z : float [@sop.default 0.] [@sop.label "Translate Z"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.];
    rotate_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    rotate_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    rotate_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    scale_x : float [@sop.default 1.] [@sop.label "Scale X"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.];
    scale_y : float [@sop.default 1.] [@sop.label "Scale Y"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.];
    scale_z : float [@sop.default 1.] [@sop.label "Scale Z"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.];
    shear_xy : float [@sop.default 0.] [@sop.label "Shear XY"]
      [@sop.folder "Transform/Shear"] [@sop.min (-4.)] [@sop.max 4.];
    shear_xz : float [@sop.default 0.] [@sop.label "Shear XZ"]
      [@sop.folder "Transform/Shear"] [@sop.min (-4.)] [@sop.max 4.];
    shear_yz : float [@sop.default 0.] [@sop.label "Shear YZ"]
      [@sop.folder "Transform/Shear"] [@sop.min (-4.)] [@sop.max 4.];
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.];
    pivot_x : float [@sop.default 0.] [@sop.label "Pivot X"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.];
    pivot_y : float [@sop.default 0.] [@sop.label "Pivot Y"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.];
    pivot_z : float [@sop.default 0.] [@sop.label "Pivot Z"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.];
    pivot_rotation_x : float [@sop.default 0.] [@sop.label "Pivot rotate X"]
      [@sop.folder "Transform/Pivot rotation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    pivot_rotation_y : float [@sop.default 0.] [@sop.label "Pivot rotate Y"]
      [@sop.folder "Transform/Pivot rotation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    pivot_rotation_z : float [@sop.default 0.] [@sop.label "Pivot rotate Z"]
      [@sop.folder "Transform/Pivot rotation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    invert : bool [@sop.default false] [@sop.label "Invert transform"]
      [@sop.folder "Transform"];
    metric : metric [@sop.default Radius] [@sop.label "Distance metric"]
      [@sop.folder "Soft selection"] [@sop.kind metric_parameter];
    metric_attribute : string [@sop.default "mask"]
      [@sop.label "Metric attribute"] [@sop.folder "Soft selection"];
    apply_rolloff : bool [@sop.default true] [@sop.label "Apply rolloff"]
      [@sop.folder "Soft selection"];
    falloff : Pdk.Ops.soft_transform_falloff
      [@sop.default Pdk.Ops.Soft_cubic] [@sop.label "Falloff"]
      [@sop.folder "Soft selection"] [@sop.kind soft_falloff_parameter];
    radius : float [@sop.default 1.] [@sop.label "Radius"]
      [@sop.folder "Soft selection"] [@sop.min 0.] [@sop.max 100.]
      [@sop.hard_min 0.];
    falloff_attribute : string [@sop.default ""]
      [@sop.label "Falloff output attribute"] [@sop.folder "Output"];
    recompute_normals : bool [@sop.default true]
      [@sop.label "Recompute normals"] [@sop.folder "Output"];
  } [@@sop.node_key "soft_transform"] [@@sop.node_label "Soft Transform"]
    [@@sop.node_category "Deform"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let metric parameters = match parameters.metric with
    | Radius -> Pdk.Ops.Soft_radius
    | Edge -> Pdk.Ops.Soft_edge
    | Attribute -> Pdk.Ops.Soft_attribute {
        attribute = parameters.metric_attribute;
        apply_rolloff = parameters.apply_rolloff }
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.soft_transform_trs ~label ~order:parameters.order
        ~rotation_order:parameters.rotation_order
        ~translate:(Vec3.create parameters.translate_x parameters.translate_y
          parameters.translate_z)
        ~rotate:(Vec3.create parameters.rotate_x parameters.rotate_y
          parameters.rotate_z)
        ~scale:(Vec3.create parameters.scale_x parameters.scale_y
          parameters.scale_z)
        ~shear:(Vec3.create parameters.shear_xy parameters.shear_xz
          parameters.shear_yz) ~uniform_scale:parameters.uniform_scale
        ~pivot:(Vec3.create parameters.pivot_x parameters.pivot_y
          parameters.pivot_z)
        ~pivot_rotation:(Vec3.create parameters.pivot_rotation_x
          parameters.pivot_rotation_y parameters.pivot_rotation_z)
        ~invert:parameters.invert
        ?selection:(optional_element_group parameters.group_owner
          parameters.group)
        ~metric:(metric parameters) ~falloff:parameters.falloff
        ~radius:parameters.radius
        ?falloff_attribute:(optional_text parameters.falloff_attribute)
        ~recompute_normals:parameters.recompute_normals input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Soft_transform expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "soft-transform" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Point_generate_from_input = struct
  type mode = Total | Per_point | Probability
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Total count", Total; "Per point", Per_point;
      "Probability attribute", Probability;
    ]
  type parameters = {
    mode : mode [@sop.default Per_point] [@sop.label "Generation mode"]
      [@sop.kind mode_parameter];
    group : string [@sop.default ""] [@sop.label "Point group"];
    keep_input : bool [@sop.default false] [@sop.label "Keep input"];
    total : int [@sop.default 100] [@sop.label "Total points"]
      [@sop.folder "Generation"] [@sop.min 0] [@sop.max 1000000]
      [@sop.hard_min 0];
    points_per_point : float [@sop.default 1.] [@sop.label "Points per point"]
      [@sop.folder "Generation"] [@sop.min 0.] [@sop.max 1000.]
      [@sop.hard_min 0.];
    scale_attribute : string [@sop.default ""] [@sop.label "Count scale"]
      [@sop.folder "Generation"];
    probability_attribute : string [@sop.default "probability"]
      [@sop.label "Probability attribute"] [@sop.folder "Generation"];
    context_seed : bool [@sop.default false] [@sop.label "Use context seed"]
      [@sop.folder "Random"];
    seed : int [@sop.default 0] [@sop.label "Seed"]
      [@sop.folder "Random"] [@sop.min 0] [@sop.max 9999];
    generated_group : string [@sop.default ""] [@sop.label "Generated group"]
      [@sop.folder "Output"];
    source_point_attribute : string [@sop.default "sourcepoint"]
      [@sop.label "Source point"] [@sop.folder "Output"];
    source_index_attribute : string [@sop.default "sourceindex"]
      [@sop.label "Source index"] [@sop.folder "Output"];
    copy_point_attributes : string [@sop.default "*"]
      [@sop.label "Point attributes"] [@sop.folder "Transfer"];
    copy_detail_attributes : string [@sop.default ""]
      [@sop.label "Detail attributes"] [@sop.folder "Transfer"];
  } [@@sop.node_key "point_generate"] [@@sop.node_label "Point Generate"]
    [@@sop.node_category "Create/Points"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let mode parameters = match parameters.mode with
    | Total -> Pdk.Ops.Generate_total parameters.total
    | Per_point -> Pdk.Ops.Generate_per_point {
        points_per_point = parameters.points_per_point;
        scale_attribute = optional_text parameters.scale_attribute }
    | Probability -> Pdk.Ops.Generate_probability {
        attribute = parameters.probability_attribute }
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.point_generate ~label
        ?group:(optional_text parameters.group) ~keep_input:parameters.keep_input
        ?seed:(if parameters.context_seed then None else Some parameters.seed)
        ?generated_group:(optional_text parameters.generated_group)
        ~source_point_attribute:parameters.source_point_attribute
        ~source_index_attribute:parameters.source_index_attribute
        ~copy_point_attributes:parameters.copy_point_attributes
        ~copy_detail_attributes:parameters.copy_detail_attributes
        ~mode:(mode parameters) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Point_generate_from_input expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "point-generate" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Point_replicate = struct
  let shape_parameter = Parameter.choice ~equal:( = ) [
      "Point", Pdk.Ops.Replicate_point; "Box", Pdk.Ops.Replicate_box;
      "Sphere", Pdk.Ops.Replicate_sphere; "Disk", Pdk.Ops.Replicate_disk;
      "Line", Pdk.Ops.Replicate_line; "Custom", Pdk.Ops.Replicate_custom;
    ]
  let velocity_parameter = Parameter.choice ~equal:( = ) [
      "None", Pdk.Ops.Replicate_no_velocity_stretch;
      "Scaled velocity", Pdk.Ops.Replicate_scaled_velocity;
      "Velocity only", Pdk.Ops.Replicate_velocity_only;
    ]
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    keep_input : bool [@sop.default false] [@sop.label "Keep input"];
    points_per_point : float [@sop.default 10.] [@sop.label "Points per point"]
      [@sop.min 0.] [@sop.max 10000.] [@sop.hard_min 0.];
    scale_attribute : string [@sop.default ""] [@sop.label "Count scale"];
    context_seed : bool [@sop.default false] [@sop.label "Use context seed"]
      [@sop.folder "Random"];
    seed : int [@sop.default 0] [@sop.label "Seed"]
      [@sop.folder "Random"] [@sop.min 0] [@sop.max 9999];
    id_attribute : string [@sop.default "id"] [@sop.label "ID attribute"]
      [@sop.folder "Random"];
    shape : Pdk.Ops.point_replicate_shape [@sop.default Pdk.Ops.Replicate_sphere]
      [@sop.label "Shape"] [@sop.folder "Shape"] [@sop.kind shape_parameter];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Shape/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Shape/Center"] [@sop.min (-10.)] [@sop.max 10.];
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Shape/Center"] [@sop.min (-10.)] [@sop.max 10.];
    size_x : float [@sop.default 1.] [@sop.label "Size X"]
      [@sop.folder "Shape/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    size_y : float [@sop.default 1.] [@sop.label "Size Y"]
      [@sop.folder "Shape/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    size_z : float [@sop.default 1.] [@sop.label "Size Z"]
      [@sop.folder "Shape/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    orientation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Shape/Orientation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    orientation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Shape/Orientation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    orientation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Shape/Orientation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793];
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Shape"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    quasi_stratified : bool [@sop.default false]
      [@sop.label "Quasi-stratified"] [@sop.folder "Random"];
    velocity_stretch : Pdk.Ops.point_replicate_velocity_stretch
      [@sop.default Pdk.Ops.Replicate_no_velocity_stretch]
      [@sop.label "Velocity stretch"] [@sop.folder "Velocity"]
      [@sop.kind velocity_parameter];
    velocity_scale : float [@sop.default 1.] [@sop.label "Velocity scale"]
      [@sop.folder "Velocity"] [@sop.min (-10.)] [@sop.max 10.];
    inherit_velocity : float [@sop.default 1.] [@sop.label "Inherit velocity"]
      [@sop.folder "Velocity"] [@sop.min (-10.)] [@sop.max 10.];
    radial_velocity : float [@sop.default 0.] [@sop.label "Radial velocity"]
      [@sop.folder "Velocity"] [@sop.min (-10.)] [@sop.max 10.];
    use_noise : bool [@sop.default false] [@sop.label "Enable noise"]
      [@sop.folder "Noise"];
    noise_amplitude_x : float [@sop.default 0.1] [@sop.label "Amplitude X"]
      [@sop.folder "Noise/Amplitude"] [@sop.min 0.] [@sop.max 10.];
    noise_amplitude_y : float [@sop.default 0.1] [@sop.label "Amplitude Y"]
      [@sop.folder "Noise/Amplitude"] [@sop.min 0.] [@sop.max 10.];
    noise_amplitude_z : float [@sop.default 0.1] [@sop.label "Amplitude Z"]
      [@sop.folder "Noise/Amplitude"] [@sop.min 0.] [@sop.max 10.];
    noise_frequency_x : float [@sop.default 1.] [@sop.label "Frequency X"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.];
    noise_frequency_y : float [@sop.default 1.] [@sop.label "Frequency Y"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.];
    noise_frequency_z : float [@sop.default 1.] [@sop.label "Frequency Z"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.];
    noise_offset_x : float [@sop.default 0.] [@sop.label "Offset X"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    noise_offset_y : float [@sop.default 0.] [@sop.label "Offset Y"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    noise_offset_z : float [@sop.default 0.] [@sop.label "Offset Z"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.];
    noise_roughness : float [@sop.default 0.5] [@sop.label "Roughness"]
      [@sop.folder "Noise"] [@sop.min 0.] [@sop.max 1.];
    noise_attenuation : float [@sop.default 1.] [@sop.label "Attenuation"]
      [@sop.folder "Noise"] [@sop.min 0.] [@sop.max 10.];
    noise_turbulence : int [@sop.default 3] [@sop.label "Turbulence"]
      [@sop.folder "Noise"] [@sop.min 1] [@sop.max 12]
      [@sop.hard_min 1];
    noise_context_seed : bool [@sop.default false]
      [@sop.label "Use context noise seed"] [@sop.folder "Noise"];
    noise_seed : int [@sop.default 1] [@sop.label "Noise seed"]
      [@sop.folder "Noise"] [@sop.min 0] [@sop.max 9999];
    generated_group : string [@sop.default ""] [@sop.label "Generated group"]
      [@sop.folder "Output"];
    copy_point_attributes : string [@sop.default "*"]
      [@sop.label "Copy point attributes"] [@sop.folder "Transfer"];
    keep_source_attributes : bool [@sop.default false]
      [@sop.label "Keep source attributes"] [@sop.folder "Transfer"];
    transform_attributes : string [@sop.default "P"]
      [@sop.label "Transform attributes"] [@sop.folder "Transfer"];
    source_point_attribute : string [@sop.default "sourcepoint"]
      [@sop.label "Source point"] [@sop.folder "Output"];
    source_index_attribute : string [@sop.default "sourceindex"]
      [@sop.label "Source index"] [@sop.folder "Output"];
  } [@@sop.node_key "point_replicate"] [@@sop.node_label "Point Replicate"]
    [@@sop.node_category "Create/Points"] [@@sop.node_inputs 2]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]
  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; custom_shape] ->
        let custom_shape = if parameters.shape = Pdk.Ops.Replicate_custom
          then custom_shape else None in
        Sop.point_replicate ~label ?group:(optional_text parameters.group)
          ~keep_input:parameters.keep_input
          ?seed:(if parameters.context_seed then None else Some parameters.seed)
          ~id_attribute:parameters.id_attribute
          ?generated_group:(optional_text parameters.generated_group)
          ~copy_point_attributes:parameters.copy_point_attributes
          ~keep_source_attributes:parameters.keep_source_attributes
          ~transform_attributes:parameters.transform_attributes
          ~source_point_attribute:parameters.source_point_attribute
          ~source_index_attribute:parameters.source_index_attribute
          ~shape:parameters.shape ?custom_shape
          ~center:(Vec3.create parameters.center_x parameters.center_y
            parameters.center_z)
          ~size:(Vec3.create parameters.size_x parameters.size_y parameters.size_z)
          ~orientation:(Vec3.create parameters.orientation_x
            parameters.orientation_y parameters.orientation_z)
          ~uniform_scale:parameters.uniform_scale
          ~quasi_stratified:parameters.quasi_stratified
          ~velocity_stretch:parameters.velocity_stretch
          ~velocity_scale:parameters.velocity_scale
          ~inherit_velocity:parameters.inherit_velocity
          ~radial_velocity:parameters.radial_velocity
          ?noise_amplitude:(if parameters.use_noise then Some
            (Vec3.create parameters.noise_amplitude_x
              parameters.noise_amplitude_y parameters.noise_amplitude_z)
            else None)
          ~noise_frequency:(Vec3.create parameters.noise_frequency_x
            parameters.noise_frequency_y parameters.noise_frequency_z)
          ~noise_offset:(Vec3.create parameters.noise_offset_x
            parameters.noise_offset_y parameters.noise_offset_z)
          ~noise_roughness:parameters.noise_roughness
          ~noise_attenuation:parameters.noise_attenuation
          ~noise_turbulence:parameters.noise_turbulence
          ?noise_seed:(if parameters.use_noise && not parameters.noise_context_seed
            then Some parameters.noise_seed else None)
          ~points_per_point:parameters.points_per_point
          ?scale_attribute:(optional_text parameters.scale_attribute) input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild
    | _ -> invalid_arg "Sop_catalog.Point_replicate requires its source input"
  and rebuild ~label ~inputs parameters = match inputs with
    | [input] -> build_slots ~label ~inputs:[Some input; None] parameters
    | [input; custom_shape] ->
        build_slots ~label ~inputs:[Some input; Some custom_shape] parameters
    | _ -> invalid_arg "Sop_catalog.Point_replicate has invalid physical inputs"
  let factory = parameters_factory build_slots
  let create ?label:node_label ?custom_shape input = build_slots
      ~label:(label "point-replicate" node_label)
      ~inputs:[Some input; custom_shape] parameters_default
end [@@sop.register]

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
    [@@sop.node_category "Attribute/Motion"] [@@sop.node_inputs 3]
    [@@sop.node_optional "1,2"] [@@deriving sop_params, sop_node]
  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; start_source; hold_source] ->
        let start_present = Option.is_some start_source
        and hold_present = Option.is_some hold_source in
        Sop.attribute_fade ~label ?group:(optional_text parameters.group)
          ?start_source ?hold_source ~fade_attribute:parameters.fade_attribute
          ?start_attribute:(optional_text parameters.start_attribute)
          ~start_retime:(parameters.start_retime_offset,
            parameters.start_retime_scale)
          ?hold_scale_attribute:
            (optional_text parameters.hold_scale_attribute)
          ~frame_offset:parameters.frame_offset ~fade_in:parameters.fade_in
          ~fade_hold:parameters.fade_hold ~fade_out:parameters.fade_out
          ~visualize:parameters.visualize input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:(rebuild_sparse start_present hold_present)
    | _ -> invalid_arg "Sop_catalog.Attribute_fade requires its source input"
  and rebuild_sparse start_present hold_present ~label ~inputs parameters =
    match inputs with
    | input :: rest ->
        let take present rest = if not present then None, rest else match rest with
          | value :: rest -> Some value, rest
          | [] -> invalid_arg "Attribute Fade lost a captured optional input" in
        let start_source, rest = take start_present rest in
        let hold_source, rest = take hold_present rest in
        if rest <> [] then invalid_arg "Attribute Fade has extra physical inputs";
        build_slots ~label ~inputs:[Some input; start_source; hold_source]
          parameters
    | [] -> invalid_arg "Attribute Fade lost its required input"
  let factory = parameters_factory build_slots
  let create ?label:node_label ?start_source ?hold_source input = build_slots
      ~label:(label "attribute-fade" node_label)
      ~inputs:[Some input; start_source; hold_source] parameters_default
end [@@sop.register]

module Point_velocity = struct
  type initialization = Compute | Keep | Set | From_attribute
  let approximation_parameter = Parameter.choice ~equal:( = ) [
      "Backward difference", Pdk.Motion.Backward_difference;
      "Central difference", Pdk.Motion.Central_difference;
      "Forward difference", Pdk.Motion.Forward_difference;
    ]
  let initialization_parameter = Parameter.choice ~equal:( = ) [
      "Compute from deformation", Compute; "Keep incoming", Keep;
      "Set value", Set; "From attribute", From_attribute;
    ]
  let unmatched_parameter = Parameter.choice ~equal:( = ) [
      "Error", Pdk.Motion.Velocity_unmatched_error;
      "Zero", Pdk.Motion.Velocity_unmatched_zero;
    ]
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    approximation : Pdk.Motion.velocity_approximation
      [@sop.default Pdk.Motion.Backward_difference]
      [@sop.label "Approximation"] [@sop.kind approximation_parameter];
    dt : float [@sop.default 0.016666666666666666] [@sop.label "Time step"]
      [@sop.min 0.000001] [@sop.max 10.] [@sop.hard_min 0.];
    initialization : initialization [@sop.default Compute]
      [@sop.label "Initialization"] [@sop.kind initialization_parameter];
    set_x : float [@sop.default 0.] [@sop.label "Velocity X"]
      [@sop.folder "Initialization/Value"] [@sop.min (-100.)]
      [@sop.max 100.];
    set_y : float [@sop.default 0.] [@sop.label "Velocity Y"]
      [@sop.folder "Initialization/Value"] [@sop.min (-100.)]
      [@sop.max 100.];
    set_z : float [@sop.default 0.] [@sop.label "Velocity Z"]
      [@sop.folder "Initialization/Value"] [@sop.min (-100.)]
      [@sop.max 100.];
    source_attribute : string [@sop.default "v"]
      [@sop.label "Source attribute"] [@sop.folder "Initialization/Attribute"];
    source_scale : float [@sop.default 1.] [@sop.label "Source scale"]
      [@sop.folder "Initialization/Attribute"] [@sop.min (-10.)]
      [@sop.max 10.];
    match_attribute : string [@sop.default ""] [@sop.label "Match attribute"]
      [@sop.folder "Matching"];
    unmatched : Pdk.Motion.velocity_unmatched
      [@sop.default Pdk.Motion.Velocity_unmatched_error]
      [@sop.label "Unmatched"] [@sop.folder "Matching"]
      [@sop.kind unmatched_parameter];
    velocity_attribute : string [@sop.default "v"]
      [@sop.label "Velocity attribute"] [@sop.folder "Output"];
    add_x : float [@sop.default 0.] [@sop.label "Add X"]
      [@sop.folder "Output/Add velocity"] [@sop.min (-100.)]
      [@sop.max 100.];
    add_y : float [@sop.default 0.] [@sop.label "Add Y"]
      [@sop.folder "Output/Add velocity"] [@sop.min (-100.)]
      [@sop.max 100.];
    add_z : float [@sop.default 0.] [@sop.label "Add Z"]
      [@sop.folder "Output/Add velocity"] [@sop.min (-100.)]
      [@sop.max 100.];
    compute_acceleration : bool [@sop.default false]
      [@sop.label "Compute acceleration"] [@sop.folder "Output"];
    acceleration_attribute : string [@sop.default "accel"]
      [@sop.label "Acceleration attribute"] [@sop.folder "Output"];
  } [@@sop.node_key "point_velocity"] [@@sop.node_label "Point Velocity"]
    [@@sop.node_category "Attribute/Motion"] [@@sop.node_inputs 3]
    [@@sop.node_optional "1,2"] [@@deriving sop_params, sop_node]
  let initialization parameters = match parameters.initialization with
    | Compute -> Pdk.Motion.Compute_from_deformation
    | Keep -> Pdk.Motion.Keep_incoming
    | Set -> Pdk.Motion.Set_value
        (Vec3.create parameters.set_x parameters.set_y parameters.set_z)
    | From_attribute -> Pdk.Motion.From_attribute {
        name = parameters.source_attribute; scale = parameters.source_scale }
  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; previous; next] ->
        let previous_present = Option.is_some previous
        and next_present = Option.is_some next in
        Sop.point_velocity ~label ?group:(optional_text parameters.group)
          ?previous ?next ~approximation:parameters.approximation
          ~dt:parameters.dt ~initialization:(initialization parameters)
          ?match_attribute:(optional_text parameters.match_attribute)
          ~unmatched:parameters.unmatched
          ~velocity_attribute:parameters.velocity_attribute
          ~add_velocity:(Vec3.create parameters.add_x parameters.add_y
            parameters.add_z)
          ~compute_acceleration:parameters.compute_acceleration
          ~acceleration_attribute:parameters.acceleration_attribute input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:(rebuild_sparse previous_present next_present)
    | _ -> invalid_arg "Sop_catalog.Point_velocity requires its source input"
  and rebuild_sparse previous_present next_present ~label ~inputs parameters =
    match inputs with
    | input :: rest ->
        let take present rest = if not present then None, rest else match rest with
          | value :: rest -> Some value, rest
          | [] -> invalid_arg "Point Velocity lost a captured optional input" in
        let previous, rest = take previous_present rest in
        let next, rest = take next_present rest in
        (match rest with
         | [] -> build_slots ~label ~inputs:[Some input; previous; next] parameters
         | _ -> invalid_arg "Point Velocity has extra physical inputs")
    | [] -> invalid_arg "Point Velocity lost its required input"
  let factory = parameters_factory build_slots
  let create ?label:node_label ?previous ?next input = build_slots
      ~label:(label "point-velocity" node_label)
      ~inputs:[Some input; previous; next] parameters_default
end [@@sop.register]

type transfer_mode = Transfer_nearest | Transfer_inverse | Transfer_links
  | Transfer_renderman | Transfer_hart
let transfer_mode_parameter = Parameter.choice ~equal:( = ) [
    "Nearest", Transfer_nearest; "Inverse distance", Transfer_inverse;
    "Links kernel", Transfer_links; "RenderMan kernel", Transfer_renderman;
    "Hart kernel", Transfer_hart;
  ]
type transfer_falloff = Transfer_linear | Transfer_smoothstep | Transfer_uniform
let transfer_falloff_parameter = Parameter.choice ~equal:( = ) [
    "Linear", Transfer_linear; "Smoothstep", Transfer_smoothstep;
    "Uniform", Transfer_uniform;
  ]
let transfer_unmatched_parameter = Parameter.choice ~equal:( = ) [
    "Keep target", Pdk.Attribute_ops.Keep_target;
    "Default value", Pdk.Attribute_ops.Default_value;
  ]
let transfer_mode mode neighbors power radius = match mode with
  | Transfer_nearest -> Pdk.Attribute_ops.Nearest
  | Transfer_inverse -> Pdk.Attribute_ops.Inverse_distance { neighbors; power }
  | Transfer_links -> Pdk.Attribute_ops.Kernel {
      neighbors; radius; kernel = Pdk.Attribute_ops.Links }
  | Transfer_renderman -> Pdk.Attribute_ops.Kernel {
      neighbors; radius; kernel = Pdk.Attribute_ops.RenderMan }
  | Transfer_hart -> Pdk.Attribute_ops.Kernel {
      neighbors; radius; kernel = Pdk.Attribute_ops.Hart }
let transfer_falloff falloff bias = match falloff with
  | Transfer_linear -> Pdk.Attribute_ops.Linear
  | Transfer_smoothstep -> Pdk.Attribute_ops.Smoothstep
  | Transfer_uniform -> Pdk.Attribute_ops.Uniform bias
let exact_or_pattern exact pattern = match optional_text pattern with
  | Some pattern -> None, Some pattern
  | None -> optional_text exact, None

module Attribute_copy = struct
  type match_ = Cyclic | By_values | To_element
  let match_parameter = Parameter.choice ~equal:( = ) [
      "Cyclic", Cyclic; "By attribute values", By_values;
      "To source element", To_element;
    ]
  let encode_rule (rule : Pdk.Attribute_ops.copy_rule) = [
      attribute_owner_token rule.copy_owner; rule.copy_pattern;
      Option.value ~default:"" rule.copy_into;
    ]
  let decode_rule = function
    | [owner; pattern; into] ->
        Result.map (fun copy_owner -> { Pdk.Attribute_ops.copy_owner;
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
  let default_rules = [{ Pdk.Attribute_ops.copy_owner = Pdk.Attribute.Point;
      copy_pattern = "*"; copy_into = None }]
  type parameters = {
    group_owner : Pdk.Group.owner [@sop.default Pdk.Group.Point]
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
    rules : Pdk.Attribute_ops.copy_rule list [@sop.default default_rules]
      [@sop.label "Rules (owner, pattern, destination)"]
      [@sop.folder "Attributes"] [@sop.kind rules_parameter];
  } [@@sop.node_key "attribute_copy"] [@@sop.node_label "Attribute Copy"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]
  let match_ parameters = match parameters.match_ with
    | Cyclic -> Pdk.Attribute_ops.Cyclic
    | By_values -> Pdk.Attribute_ops.By_values {
        source_attribute = parameters.source_match_attribute;
        target_attribute = parameters.target_match_attribute }
    | To_element -> Pdk.Attribute_ops.To_element {
        target_attribute = parameters.target_element_attribute }
  let rec build ~label ~inputs parameters = match inputs with
    | [source; target] ->
        let source_group, source_group_pattern = exact_or_pattern
            parameters.source_group parameters.source_group_pattern
        and target_group, target_group_pattern = exact_or_pattern
            parameters.target_group parameters.target_group_pattern in
        Sop.attribute_copy ~label ~match_:(match_ parameters)
          ~allow_position:parameters.allow_position ?source_group
          ?source_group_pattern ?target_group ?target_group_pattern
          ~group_owner:parameters.group_owner ~rules:parameters.rules
          ~source ~target ()
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_copy expects two inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~source ~target () = build
      ~label:(label "attribute-copy" node_label) ~inputs:[source; target]
      parameters_default
end [@@sop.register]

module Attribute_interpolate = struct
  type driver = Primitive_uvw | Point_weights | Vertex_weights
    | Primitive_weights
  let driver_parameter = Parameter.choice ~equal:( = ) [
      "Primitive UVW", Primitive_uvw; "Point weights", Point_weights;
      "Vertex weights", Vertex_weights;
      "Primitive weights", Primitive_weights;
    ]
  let encode_attribute (attribute : Pdk.Attribute_ops.interpolate_attribute) = [
      attribute_owner_token attribute.interpolate_owner;
      attribute.interpolate_source; attribute.interpolate_target;
    ]
  let decode_attribute = function
    | [owner; source; target] -> Result.map (fun interpolate_owner -> {
        Pdk.Attribute_ops.interpolate_owner; interpolate_source = source;
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
      Pdk.Attribute_ops.interpolate_owner = Pdk.Attribute.Point;
      interpolate_source = "Cd"; interpolate_target = "Cd" }]
  type parameters = {
    target_owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Target owner"] [@sop.kind attribute_owner_parameter];
    attributes : Pdk.Attribute_ops.interpolate_attribute list
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
    computed_owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
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
    unmatched : Pdk.Attribute_ops.unmatched
      [@sop.default Pdk.Attribute_ops.Keep_target] [@sop.label "Unmatched"]
      [@sop.kind transfer_unmatched_parameter];
  } [@@sop.node_key "attribute_interpolate"]
    [@@sop.node_label "Attribute Interpolate"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]
  let driver parameters = match parameters.driver with
    | Primitive_uvw -> Pdk.Attribute_ops.Primitive_uvw {
        primitive_attribute = parameters.primitive_attribute;
        uvw_attribute = parameters.uvw_attribute }
    | Point_weights -> Pdk.Attribute_ops.Point_weights {
        numbers_attribute = parameters.numbers_attribute;
        weights_attribute = parameters.weights_attribute }
    | Vertex_weights -> Pdk.Attribute_ops.Vertex_weights {
        numbers_attribute = parameters.numbers_attribute;
        weights_attribute = parameters.weights_attribute }
    | Primitive_weights -> Pdk.Attribute_ops.Primitive_weights {
        numbers_attribute = parameters.numbers_attribute;
        weights_attribute = parameters.weights_attribute }
  let rec build ~label ~inputs parameters = match inputs with
    | [source; target] ->
        let group, group_pattern = exact_or_pattern parameters.group
            parameters.group_pattern
        and compute_weights = if parameters.compute_weights then Some {
            Pdk.Attribute_ops.computed_owner = parameters.computed_owner;
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
          ~attributes:parameters.attributes ~source ~target ()
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_interpolate expects two inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~source ~target () = build
      ~label:(label "attribute-interpolate" node_label)
      ~inputs:[source; target] parameters_default
end [@@sop.register]

module Attribute_transfer = struct
  let vertex_selection_parameter = Parameter.choice ~equal:( = ) [
      "All triangle vertices", Pdk.Attribute_ops.All_triangle_vertices;
      "Any triangle vertex", Pdk.Attribute_ops.Any_triangle_vertex;
    ]
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
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
    unmatched : Pdk.Attribute_ops.unmatched
      [@sop.default Pdk.Attribute_ops.Keep_target] [@sop.label "Unmatched"]
      [@sop.kind transfer_unmatched_parameter];
    source_group : string [@sop.default ""] [@sop.label "Source group"]
      [@sop.folder "Groups/Source"];
    source_group_pattern : string [@sop.default ""]
      [@sop.label "Source group pattern"] [@sop.folder "Groups/Source"];
    source_vertex_group : string [@sop.default ""]
      [@sop.label "Source vertex group"] [@sop.folder "Groups/Source"];
    source_vertex_group_pattern : string [@sop.default ""]
      [@sop.label "Source vertex pattern"] [@sop.folder "Groups/Source"];
    source_vertex_selection : Pdk.Attribute_ops.surface_vertex_selection
      [@sop.default Pdk.Attribute_ops.All_triangle_vertices]
      [@sop.label "Vertex selection"] [@sop.folder "Groups/Source"]
      [@sop.kind vertex_selection_parameter];
    target_group : string [@sop.default ""] [@sop.label "Target group"]
      [@sop.folder "Groups/Target"];
    target_group_pattern : string [@sop.default ""]
      [@sop.label "Target group pattern"] [@sop.folder "Groups/Target"];
  } [@@sop.node_key "attribute_transfer"]
    [@@sop.node_label "Attribute Transfer"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [source; target] ->
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
          ?target_group ?target_group_pattern ~source ~target ()
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_transfer expects two inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~source ~target () = build
      ~label:(label "attribute-transfer" node_label) ~inputs:[source; target]
      parameters_default
end [@@sop.register]

module Attribute_transfer_surface = struct
  let vertex_selection_parameter = Parameter.choice ~equal:( = ) [
      "All triangle vertices", Pdk.Attribute_ops.All_triangle_vertices;
      "Any triangle vertex", Pdk.Attribute_ops.Any_triangle_vertex;
    ]
  let encode_attribute (attribute : Pdk.Attribute_ops.surface_attribute) = [
      attribute_owner_token attribute.source_owner; attribute.source_name;
      attribute.target_name;
    ]
  let decode_attribute = function
    | [owner; source_name; target_name] ->
        Result.map (fun source_owner -> {
          Pdk.Attribute_ops.source_owner; source_name; target_name })
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
  let default_attributes = [Pdk.Attribute_ops.surface_attribute
      ~owner:Pdk.Attribute.Point "Cd"]
  type parameters = {
    target_owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Target owner"]
      [@sop.kind element_attribute_owner_parameter];
    attributes : Pdk.Attribute_ops.surface_attribute list
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
    unmatched : Pdk.Attribute_ops.unmatched
      [@sop.default Pdk.Attribute_ops.Keep_target] [@sop.label "Unmatched"]
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
    source_vertex_selection : Pdk.Attribute_ops.surface_vertex_selection
      [@sop.default Pdk.Attribute_ops.All_triangle_vertices]
      [@sop.label "Vertex selection"] [@sop.folder "Groups/Source"]
      [@sop.kind vertex_selection_parameter];
    target_group : string [@sop.default ""] [@sop.label "Target group"]
      [@sop.folder "Groups/Target"];
    target_group_pattern : string [@sop.default ""]
      [@sop.label "Target group pattern"] [@sop.folder "Groups/Target"];
  } [@@sop.node_key "attribute_transfer_surface"]
    [@@sop.node_label "Attribute Transfer Surface"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [source; target] ->
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
          ~source ~target ()
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg
        "Sop_catalog.Attribute_transfer_surface expects two inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~source ~target () = build
      ~label:(label "attribute-transfer-surface" node_label)
      ~inputs:[source; target] parameters_default
end [@@sop.register]

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
    unmatched : Pdk.Attribute_ops.unmatched
      [@sop.default Pdk.Attribute_ops.Keep_target] [@sop.label "Unmatched"]
      [@sop.kind transfer_unmatched_parameter];
  } [@@sop.node_key "attribute_transfer_all"]
    [@@sop.node_label "Attribute Transfer All"]
    [@@sop.node_category "Attribute/Transfer"] [@@sop.node_inputs 2]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [source; target] -> Sop.attribute_transfer_all ~label
        ?point_pattern:(optional_text parameters.point_pattern)
        ?vertex_pattern:(optional_text parameters.vertex_pattern)
        ?primitive_pattern:(optional_text parameters.primitive_pattern)
        ?detail_pattern:(optional_text parameters.detail_pattern)
        ~mode:(transfer_mode parameters.mode parameters.neighbors
          parameters.power parameters.kernel_radius)
        ~max_distance:parameters.max_distance
        ~blend_width:parameters.blend_width
        ~falloff:(transfer_falloff parameters.falloff parameters.uniform_bias)
        ~unmatched:parameters.unmatched ~source ~target ()
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_transfer_all expects two inputs"
  let factory = parameters_factory build
  let create ?label:node_label ~source ~target () = build
      ~label:(label "attribute-transfer-all" node_label) ~inputs:[source; target]
      parameters_default
end [@@sop.register]

module Promote_attribute = struct
  type parameters = {
    source : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Source owner"] [@sop.kind attribute_owner_parameter];
    destination : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Primitive]
      [@sop.label "Destination owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "Cd"] [@sop.label "Attribute"];
    into : string [@sop.default ""] [@sop.label "New name"];
    method_ : Pdk.Attribute_ops.method_ [@sop.default Pdk.Attribute_ops.Average]
      [@sop.label "Promotion method"]
      [@sop.kind attribute_promotion_method_parameter];
    delete_source : bool [@sop.default false] [@sop.label "Delete source"];
    piece_attribute : string [@sop.default ""]
      [@sop.label "Piece attribute"] [@sop.folder "Partition"];
    index_attribute : string [@sop.default ""]
      [@sop.label "Index attribute"] [@sop.folder "Output"];
  } [@@sop.node_key "promote_attribute"]
    [@@sop.node_label "Promote Attribute"]
    [@@sop.node_category "Attribute/Promote"] [@@sop.node_inputs 1]
    [@@sop.node_operation "attribute_promote"]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.promote_attribute ~label
        ?into:(optional_text parameters.into) ~method_:parameters.method_
        ~delete_source:parameters.delete_source
        ?piece_attribute:(optional_text parameters.piece_attribute)
        ?index_attribute:(optional_text parameters.index_attribute)
        ~source:parameters.source ~destination:parameters.destination
        ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Promote_attribute expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "promote-attribute" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Promote_attributes = struct
  type parameters = {
    source : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Source owner"] [@sop.kind attribute_owner_parameter];
    destination : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Primitive]
      [@sop.label "Destination owner"] [@sop.kind attribute_owner_parameter];
    pattern : string [@sop.default "*"] [@sop.label "Attribute pattern"];
    method_ : Pdk.Attribute_ops.method_ [@sop.default Pdk.Attribute_ops.Average]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.promote_attributes ~label ~method_:parameters.method_
        ~delete_source:parameters.delete_source
        ?piece_attribute:(optional_text parameters.piece_attribute)
        ?into_pattern:(optional_text parameters.into_pattern)
        ?index_pattern:(optional_text parameters.index_pattern)
        ~source:parameters.source ~destination:parameters.destination
        ~pattern:parameters.pattern input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Promote_attributes expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "promote-attributes" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Measure = struct
  let kind_parameter = Parameter.choice ~equal:( = ) [
      "Perimeter", Pdk.Analysis.Perimeter;
      "Area", Pdk.Analysis.Area;
      "Signed volume", Pdk.Analysis.Signed_volume;
    ]
  let accumulation_parameter = Parameter.choice ~equal:( = ) [
      "Per element", Pdk.Analysis.Per_element;
      "Throughout", Pdk.Analysis.Throughout;
    ]
  type parameters = {
    kind : Pdk.Analysis.measure [@sop.default Pdk.Analysis.Area]
      [@sop.label "Measure"] [@sop.kind kind_parameter];
    group : string [@sop.default ""] [@sop.label "Primitive group"];
    accumulation : Pdk.Analysis.accumulation
      [@sop.default Pdk.Analysis.Per_element]
      [@sop.label "Accumulation"] [@sop.kind accumulation_parameter];
    attribute : string [@sop.default ""] [@sop.label "Attribute"]
      [@sop.folder "Output"];
    total_attribute : string [@sop.default ""]
      [@sop.label "Total attribute"] [@sop.folder "Output"];
  } [@@sop.node_key "measure"] [@@sop.node_label "Measure"]
    [@@sop.node_category "Attribute/Analysis"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.measure ~label ?group:(optional_text parameters.group)
          ~accumulation:parameters.accumulation
          ?name:(optional_text parameters.attribute)
          ?total_name:(optional_text parameters.total_attribute)
          parameters.kind input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Measure expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "measure" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Connectivity = struct
  type output = Integer | Text
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Points", Pdk.Analysis.Connectivity_points;
      "Primitives", Pdk.Analysis.Connectivity_primitives;
    ]
  let output_parameter = Parameter.choice ~equal:( = ) [
      "Integer", Integer; "Text", Text;
    ]
  type parameters = {
    owner : Pdk.Analysis.connectivity_owner
      [@sop.default Pdk.Analysis.Connectivity_primitives]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let attribute = match parameters.output with
          | Integer -> Pdk.Analysis.Connectivity_integer
          | Text -> Pdk.Analysis.Connectivity_text parameters.text_prefix in
        Sop.connectivity ~label
          ?primitive_group:(optional_text parameters.primitive_group)
          ?point_group:(optional_text parameters.point_group)
          ?seam_group:(optional_text parameters.seam_group)
          ?uv_attribute:(optional_text parameters.uv_attribute)
          ~owner:parameters.owner ?name:(optional_text parameters.name)
          ~attribute input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Connectivity expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input =
    build ~label:(label "connectivity" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Set_float = struct
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "value"] [@sop.label "Attribute"];
    value : float [@sop.default 0.] [@sop.label "Value"]
      [@sop.min (-10.)] [@sop.max 10.];
  } [@@sop.node_key "set_float"] [@@sop.node_label "Set Float"]
    [@@sop.node_category "Attribute/Set"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.set_float ~label ~owner:parameters.owner
        ~name:parameters.name parameters.value input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Set_float expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "set-float" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Set_int = struct
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "value"] [@sop.label "Attribute"];
    value : int [@sop.default 0] [@sop.label "Value"]
      [@sop.min (-100)] [@sop.max 100];
  } [@@sop.node_key "set_int"] [@@sop.node_label "Set Integer"]
    [@@sop.node_category "Attribute/Set"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.set_int ~label ~owner:parameters.owner
        ~name:parameters.name parameters.value input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Set_int expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "set-int" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Set_vector = struct
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.set_vector ~label ~owner:parameters.owner
        ~name:parameters.name (Vec3.create parameters.x parameters.y parameters.z)
        input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Set_vector expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "set-vector" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.set_orient ~label
        (Quat.create ~x:parameters.x ~y:parameters.y ~z:parameters.z
          ~w:parameters.w) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Set_orient expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "set-orient" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.set_transform ~label (matrix parameters) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Set_transform expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "set-transform" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Set_color = struct
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    red : int [@sop.default 255] [@sop.label "Red"] [@sop.min 0]
      [@sop.max 255] [@sop.hard_min 0] [@sop.hard_max 255];
    green : int [@sop.default 255] [@sop.label "Green"] [@sop.min 0]
      [@sop.max 255] [@sop.hard_min 0] [@sop.hard_max 255];
    blue : int [@sop.default 255] [@sop.label "Blue"] [@sop.min 0]
      [@sop.max 255] [@sop.hard_min 0] [@sop.hard_max 255];
    alpha : int [@sop.default 255] [@sop.label "Alpha"] [@sop.min 0]
      [@sop.max 255] [@sop.hard_min 0] [@sop.hard_max 255];
  } [@@sop.node_key "set_color"] [@@sop.node_label "Set Color"]
    [@@sop.node_category "Attribute/Set"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.set_color ~label ~owner:parameters.owner
        (Color.rgba parameters.red parameters.green parameters.blue
          parameters.alpha) input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Set_color expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "set-color" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Delete_attribute = struct
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    name : string [@sop.default "value"] [@sop.label "Attribute"];
  } [@@sop.node_key "delete_attribute"] [@@sop.node_label "Delete Attribute"]
    [@@sop.node_category "Attribute/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.delete_attribute ~label ~owner:parameters.owner
        ~name:parameters.name input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Delete_attribute expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "delete-attribute" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Rename_attribute = struct
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
      [@sop.label "Owner"] [@sop.kind attribute_owner_parameter];
    from : string [@sop.default "value"] [@sop.label "From"];
    into : string [@sop.default "renamed"] [@sop.label "To"];
  } [@@sop.node_key "rename_attribute"] [@@sop.node_label "Rename Attribute"]
    [@@sop.node_category "Attribute/Manage"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] -> Sop.rename_attribute ~label ~owner:parameters.owner
        ~from:parameters.from ~into:parameters.into input
      |> Node.parameterize ~schema:parameters_schema ~values:parameters
           ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Rename_attribute expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "rename-attribute" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Rest_position = struct
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Store", Pdk.Motion.Store_rest; "Extract", Pdk.Motion.Extract_rest;
      "Swap", Pdk.Motion.Swap_rest;
    ]
  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Pdk.Motion.No_rest_normals;
      "If present", Pdk.Motion.Rest_normals_if_present;
      "Always", Pdk.Motion.Rest_normals_always;
    ]
  type parameters = {
    mode : Pdk.Motion.rest_mode [@sop.default Pdk.Motion.Store_rest]
      [@sop.label "Mode"] [@sop.kind mode_parameter];
    rest_attribute : string [@sop.default "rest"] [@sop.label "Rest position"]
      [@sop.folder "Attributes"];
    normals : Pdk.Motion.rest_normals [@sop.default Pdk.Motion.No_rest_normals]
      [@sop.label "Rest normals"] [@sop.kind normals_parameter];
    normal_attribute : string [@sop.default "N"] [@sop.label "Normal"]
      [@sop.folder "Attributes"];
    rest_normal_attribute : string [@sop.default "restN"]
      [@sop.label "Rest normal"] [@sop.folder "Attributes"];
  } [@@sop.node_key "rest_position"] [@@sop.node_label "Rest Position"]
    [@@sop.node_category "Attribute/Motion"] [@@sop.node_inputs 2]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]
  let rec build_slots ~label ~inputs parameters = match inputs with
    | [Some input; reference] ->
        Sop.rest_position ~label ?reference
          ~rest_attribute:parameters.rest_attribute ~normals:parameters.normals
          ~normal_attribute:parameters.normal_attribute
          ~rest_normal_attribute:parameters.rest_normal_attribute
          parameters.mode input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild
    | _ -> invalid_arg "Sop_catalog.Rest_position requires its source input"
  and rebuild ~label ~inputs parameters = match inputs with
    | [input] -> build_slots ~label ~inputs:[Some input; None] parameters
    | [input; reference] ->
        build_slots ~label ~inputs:[Some input; Some reference] parameters
    | _ -> invalid_arg "Sop_catalog.Rest_position has invalid physical inputs"
  let factory = parameters_factory build_slots
  let create ?label:node_label ?reference input = build_slots
      ~label:(label "rest-position" node_label)
      ~inputs:[Some input; reference] parameters_default
end [@@sop.register]

module Enumerate = struct
  type storage = Integer | Text
  let storage_parameter = Parameter.choice ~equal:( = ) [
      "Integer", Integer; "Text", Text;
    ]
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Elements within pieces", Pdk.Attribute_ops.Enumerate_piece_elements;
      "Pieces", Pdk.Attribute_ops.Enumerate_pieces;
    ]
  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Point]
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
    mode : Pdk.Attribute_ops.enumeration_mode
      [@sop.default Pdk.Attribute_ops.Enumerate_piece_elements]
      [@sop.label "Piece mode"] [@sop.folder "Pieces"]
      [@sop.kind mode_parameter];
  } [@@sop.node_key "enumerate"] [@@sop.node_label "Enumerate"]
    [@@sop.node_category "Attribute/Generate"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let storage = match parameters.storage with
          | Integer -> Pdk.Attribute_ops.Integer
          | Text -> Pdk.Attribute_ops.Text { prefix = parameters.prefix } in
        Sop.enumerate ~label ?group:(optional_text parameters.group)
          ~start:parameters.start ~step:parameters.step ~storage
          ?piece_attribute:(optional_text parameters.piece_attribute)
          ~mode:parameters.mode ~owner:parameters.owner ~name:parameters.name
          input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Enumerate expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build ~label:(label "enumerate" node_label)
      ~inputs:[input] parameters_default
end [@@sop.register]

module Attribute_blur = struct
  type mode = Laplacian | Custom
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Uniform", Pdk.Attribute_ops.Uniform;
      "Edge length", Pdk.Attribute_ops.Edge_length;
    ]
  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Laplacian", Laplacian; "Custom steps", Custom;
    ]
  type parameters = {
    attributes : string [@sop.default "P"] [@sop.label "Attributes"];
    group : string [@sop.default ""] [@sop.label "Point group"];
    iterations : int [@sop.default 1] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 100] [@sop.hard_min 0];
    method_ : Pdk.Attribute_ops.blur_method
      [@sop.default Pdk.Attribute_ops.Uniform]
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
  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        let mode = match parameters.mode with
          | Laplacian -> Pdk.Attribute_ops.Laplacian parameters.laplacian_step
          | Custom -> Pdk.Attribute_ops.Custom_steps {
              odd = parameters.odd_step; even = parameters.even_step } in
        Sop.attribute_blur ~label ?group:(optional_text parameters.group)
          ~iterations:parameters.iterations ~method_:parameters.method_ ~mode
          ?weight_attribute:(optional_text parameters.weight_attribute)
          ?alpha_attribute:(optional_text parameters.alpha_attribute)
          ~pin_borders:parameters.pin_borders
          ~original_blend:parameters.original_blend
          ~blurred_blend:parameters.blurred_blend
          ~attributes:parameters.attributes input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Attribute_blur expects one input"
  let factory = parameters_factory build
  let create ?label:node_label input = build
      ~label:(label "attribute-blur" node_label) ~inputs:[input]
      parameters_default
end [@@sop.register]

module Null = struct
  let factory = Edit_graph.factory ~key:"null" ~label:"Null"
      ~category:["Utility"] ~arity:1 (function
        | [input] -> Sop.null input
        | _ -> invalid_arg "Null SOP expects one input")
end [@@sop.register]

module Normal = struct
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Point", Pdk.Attribute.Point;
      "Vertex", Pdk.Attribute.Vertex;
    ]

  let weighting_parameter = Parameter.choice ~equal:( = ) [
      "Vertex angle", Pdk.Ops.Vertex_angle;
      "Each vertex", Pdk.Ops.Each_vertex;
      "Face area", Pdk.Ops.Face_area;
    ]

  type parameters = {
    owner : Pdk.Attribute.owner [@sop.default Pdk.Attribute.Vertex]
      [@sop.label "Add normals to"] [@sop.kind owner_parameter];
    weighting : Pdk.Ops.normal_weighting
      [@sop.default Pdk.Ops.Vertex_angle]
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

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.normals ~label ~owner:parameters.owner
          ~weighting:parameters.weighting ~cusp_angle:parameters.cusp_angle
          ~keep_original_zero:parameters.keep_original_zero
          ~reverse:parameters.reverse ~attribute:parameters.attribute input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Normal expects one input"

  let factory = parameters_factory build

  let create ?label:node_label ?(owner = Pdk.Attribute.Vertex)
      ?(weighting = Pdk.Ops.Vertex_angle) ?(cusp_angle = Float.pi)
      ?(keep_original_zero = false) ?(reverse = false) ?(attribute = "N")
      input =
    build ~label:(label "normal" node_label) ~inputs:[input] {
      owner; weighting; cusp_angle; keep_original_zero; reverse; attribute }
end [@@sop.register]

module Exploded_view = struct
  type parameters = {
    amount : float [@sop.default 0.32] [@sop.label "Uniform scale"]
      [@sop.folder "Explosion"] [@sop.min (-0.95)] [@sop.max 1.2]
      [@sop.impact "view"];
    scale_x : float [@sop.default 1.] [@sop.label "Scale X"]
      [@sop.folder "Explosion/Scale"] [@sop.min (-2.)] [@sop.max 2.]
      [@sop.impact "view"];
    scale_y : float [@sop.default 1.] [@sop.label "Scale Y"]
      [@sop.folder "Explosion/Scale"] [@sop.min (-2.)] [@sop.max 2.]
      [@sop.impact "view"];
    scale_z : float [@sop.default 1.] [@sop.label "Scale Z"]
      [@sop.folder "Explosion/Scale"] [@sop.min (-2.)] [@sop.max 2.]
      [@sop.impact "view"];
    piece_attribute : string [@sop.default "piece"]
      [@sop.label "Piece attribute"] [@sop.folder "Pieces"];
    noise_amount : float [@sop.default 0.] [@sop.label "Noise amount"]
      [@sop.folder "Noise"] [@sop.min 0.] [@sop.max 1.]
      [@sop.impact "view"];
    noise_frequency : float [@sop.default 0.8]
      [@sop.label "Noise frequency"] [@sop.folder "Noise"]
      [@sop.min 0.02] [@sop.max 4.] [@sop.hard_min 0.]
      [@sop.impact "view"];
    noise_seed : int [@sop.default 0] [@sop.label "Noise seed"]
      [@sop.folder "Noise"] [@sop.min 0] [@sop.max 9999]
      [@sop.impact "view"];
  } [@@sop.node_key "exploded_view"] [@@sop.node_label "Exploded View"]
    [@@sop.node_category "Visualize"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let rec build ~label ~inputs parameters = match inputs with
    | [input] ->
        Sop.exploded_view ~label input
        |> Node.parameterize ~schema:parameters_schema ~values:parameters
             ~rebuild:build
    | _ -> invalid_arg "Sop_catalog.Exploded_view expects one input"

  let factory = parameters_factory build

  let create ?label:node_label ?(amount = parameters_default.amount)
      ?(scale = Vec3.create 1. 1. 1.)
      ?(piece_attribute = parameters_default.piece_attribute)
      ?(noise_amount = parameters_default.noise_amount)
      ?(noise_frequency = parameters_default.noise_frequency)
      ?(noise_seed = parameters_default.noise_seed) input =
    build ~label:(label "exploded-view" node_label) ~inputs:[input] {
      amount; scale_x = scale.x; scale_y = scale.y; scale_z = scale.z;
      piece_attribute; noise_amount; noise_frequency; noise_seed }
end [@@sop.register]
