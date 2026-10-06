open Rays_math
open Procedural
open Shared

module Box = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Rdk.Box_generator.Box_triangles;
      "Quads", Rdk.Box_generator.Box_quads;
      "Surface points", Rdk.Box_generator.Box_surface_points;
      "Lattice points", Rdk.Box_generator.Box_lattice_points;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Box_generator.Box_no_normals;
      "Point", Rdk.Box_generator.Box_point_normals;
      "Vertex", Rdk.Box_generator.Box_vertex_normals;
    ]

  let rotation_order_parameter = Parameter.choice ~equal:( = ) [
      "XYZ", Rdk.Box_generator.Box_xyz; "XZY", Rdk.Box_generator.Box_xzy;
      "YXZ", Rdk.Box_generator.Box_yxz; "YZX", Rdk.Box_generator.Box_yzx;
      "ZXY", Rdk.Box_generator.Box_zxy; "ZYX", Rdk.Box_generator.Box_zyx;
    ]

  type parameters = {
    connectivity : Rdk.Box_generator.box_connectivity
      [@sop.default Rdk.Box_generator.Box_quads]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    normals : Rdk.Box_generator.box_normals [@sop.default Rdk.Box_generator.Box_vertex_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    size_x : float [@sop.default 1.] [@sop.label "Size X"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.]; [@sop.vec3 "size"] [@sop.primary]
    size_y : float [@sop.default 1.] [@sop.label "Size Y"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.]; [@sop.vec3 "size"] [@sop.primary]
    size_z : float [@sop.default 1.] [@sop.label "Size Z"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.]; [@sop.vec3 "size"] [@sop.primary]
    x_divisions : int [@sop.default 1] [@sop.label "X divisions"]
      [@sop.folder "Divisions"] [@sop.min 1] [@sop.max 24] [@sop.hard_min 1];
    y_divisions : int [@sop.default 1] [@sop.label "Y divisions"]
      [@sop.folder "Divisions"] [@sop.min 1] [@sop.max 24] [@sop.hard_min 1];
    z_divisions : int [@sop.default 1] [@sop.label "Z divisions"]
      [@sop.folder "Divisions"] [@sop.min 1] [@sop.max 24] [@sop.hard_min 1];
    consolidate_points : bool [@sop.default false]
      [@sop.label "Consolidate points"] [@sop.folder "Topology"];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"] [@sop.unit "rad"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"] [@sop.unit "rad"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"] [@sop.unit "rad"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_order : Rdk.Box_generator.box_rotation_order
      [@sop.default Rdk.Box_generator.Box_xyz]
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

  let build = parameters_build (fun ~label parameters ->
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
      ?face_groups:(optional_text parameters.face_groups) ())

  let factory = parameters_factory build

  let create ?label:node_label
      ?(size = Vec3.create parameters_default.size_x parameters_default.size_y
          parameters_default.size_z)
      ?(connectivity = parameters_default.connectivity)
      ?(consolidate_points = parameters_default.consolidate_points)
      ?normals
      ?(center = Vec3.create parameters_default.center_x
          parameters_default.center_y parameters_default.center_z)
      ?(rotation = Vec3.create parameters_default.rotation_x
          parameters_default.rotation_y parameters_default.rotation_z)
      ?(rotation_order = parameters_default.rotation_order)
      ?(uniform_scale = parameters_default.uniform_scale)
      ?(x_divisions = parameters_default.x_divisions)
      ?(y_divisions = parameters_default.y_divisions)
      ?(z_divisions = parameters_default.z_divisions)
      ?(uv_attribute = parameters_default.uv_attribute)
      ?(face_groups = parameters_default.face_groups) () =
    (* Point output cannot carry the surface default's normals. *)
    let normals = match normals, connectivity with
      | Some normals, _ -> normals
      | None, (Rdk.Box_generator.Box_triangles | Box_quads) -> parameters_default.normals
      | None, (Box_surface_points | Box_lattice_points) -> Box_no_normals in
    build ~label:(label "box" node_label) ~inputs:[] {
      connectivity; normals;
      size_x = size.x; size_y = size.y; size_z = size.z;
      x_divisions; y_divisions; z_divisions; consolidate_points;
      center_x = center.x; center_y = center.y; center_z = center.z;
      rotation_x = rotation.x; rotation_y = rotation.y;
      rotation_z = rotation.z; rotation_order; uniform_scale;
      uv_attribute; face_groups }
end

module Platonic = struct
  type orientation_mode = Axis_x | Axis_y | Axis_z | Axis_custom

  let kind_parameter = Parameter.choice ~equal:( = ) [
      "Tetrahedron", Rdk.Parametric_generators.Platonic_tetrahedron;
      "Cube", Rdk.Parametric_generators.Platonic_cube;
      "Octahedron", Rdk.Parametric_generators.Platonic_octahedron;
      "Icosahedron", Rdk.Parametric_generators.Platonic_icosahedron;
      "Dodecahedron", Rdk.Parametric_generators.Platonic_dodecahedron;
      "Soccer ball", Rdk.Parametric_generators.Platonic_soccer_ball;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Parametric_generators.Platonic_no_normals;
      "Point", Rdk.Parametric_generators.Platonic_point_normals;
      "Vertex", Rdk.Parametric_generators.Platonic_vertex_normals;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Axis_x; "Y axis", Axis_y; "Z axis", Axis_z;
      "Custom axis", Axis_custom;
    ]

  let rotation_order_parameter = Parameter.choice ~equal:( = ) [
      "XYZ", Rdk.Parametric_generators.Platonic_xyz; "XZY", Rdk.Parametric_generators.Platonic_xzy;
      "YXZ", Rdk.Parametric_generators.Platonic_yxz; "YZX", Rdk.Parametric_generators.Platonic_yzx;
      "ZXY", Rdk.Parametric_generators.Platonic_zxy; "ZYX", Rdk.Parametric_generators.Platonic_zyx;
    ]

  type parameters = {
    kind : Rdk.Parametric_generators.platonic_kind
      [@sop.default Rdk.Parametric_generators.Platonic_dodecahedron]
      [@sop.label "Type"] [@sop.kind kind_parameter]; [@sop.primary]
    normals : Rdk.Parametric_generators.platonic_normals
      [@sop.default Rdk.Parametric_generators.Platonic_vertex_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    radius : float [@sop.default 1.] [@sop.label "Radius"]
      [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.]; [@sop.primary]
    orientation : orientation_mode [@sop.default Axis_y]
      [@sop.label "Orientation"] [@sop.folder "Transform"]
      [@sop.kind orientation_parameter];
    axis_x : float [@sop.default 0.] [@sop.label "Axis X"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_order : Rdk.Parametric_generators.platonic_rotation_order
      [@sop.default Rdk.Parametric_generators.Platonic_xyz]
      [@sop.label "Rotation order"] [@sop.folder "Transform/Rotate"]
      [@sop.kind rotation_order_parameter];
    face_groups : string [@sop.default ""] [@sop.label "Face group prefix"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "platonic"] [@@sop.node_label "Platonic Solid"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let rdk_orientation parameters = match parameters.orientation with
    | Axis_x -> Rdk.Parametric_generators.Platonic_x
    | Axis_y -> Rdk.Parametric_generators.Platonic_y
    | Axis_z -> Rdk.Parametric_generators.Platonic_z
    | Axis_custom -> Rdk.Parametric_generators.Platonic_axis (Vec3.create parameters.axis_x
        parameters.axis_y parameters.axis_z)

  let build = parameters_build (fun ~label parameters ->
    Sop.platonic ~label ~kind:parameters.kind ~normals:parameters.normals
      ~orientation:(rdk_orientation parameters)
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z)
      ~rotation:(Vec3.create parameters.rotation_x parameters.rotation_y
        parameters.rotation_z) ~rotation_order:parameters.rotation_order
      ?face_groups:(optional_text parameters.face_groups)
      ~radius:parameters.radius ())

  let factory = parameters_factory build

  let create ?label:node_label ?(kind = Rdk.Parametric_generators.Platonic_tetrahedron)
      ?(normals = Rdk.Parametric_generators.Platonic_no_normals)
      ?(orientation = Rdk.Parametric_generators.Platonic_y) ?(center = Vec3.zero)
      ?(rotation = Vec3.zero) ?(rotation_order = Rdk.Parametric_generators.Platonic_xyz)
      ?(face_groups = "") ~radius () =
    let orientation, axis = match orientation with
      | Rdk.Parametric_generators.Platonic_x -> Axis_x, Vec3.create 1. 0. 0.
      | Rdk.Parametric_generators.Platonic_y -> Axis_y, Vec3.create 0. 1. 0.
      | Rdk.Parametric_generators.Platonic_z -> Axis_z, Vec3.create 0. 0. 1.
      | Rdk.Parametric_generators.Platonic_axis axis -> Axis_custom, axis in
    build ~label:(label "platonic" node_label) ~inputs:[] {
      kind; normals; radius; orientation;
      axis_x = axis.x; axis_y = axis.y; axis_z = axis.z;
      center_x = center.x; center_y = center.y; center_z = center.z;
      rotation_x = rotation.x; rotation_y = rotation.y;
      rotation_z = rotation.z; rotation_order; face_groups }
end

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
      "Counterclockwise", Rdk.Spiral.Spiral_counterclockwise;
      "Clockwise", Rdk.Spiral.Spiral_clockwise;
    ]
  let divisions_parameter = Parameter.choice ~equal:( = ) [
      "Per curve", Per_curve; "Per turn", Per_turn;
    ]
  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Axis_x; "Y axis", Axis_y; "Z axis", Axis_z;
      "Custom axis", Axis_custom;
    ]
  let rotation_order_parameter = Parameter.choice ~equal:( = ) [
      "XYZ", Rdk.Spiral.Spiral_xyz; "XZY", Rdk.Spiral.Spiral_xzy;
      "YXZ", Rdk.Spiral.Spiral_yxz; "YZX", Rdk.Spiral.Spiral_yzx;
      "ZXY", Rdk.Spiral.Spiral_zxy; "ZYX", Rdk.Spiral.Spiral_zyx;
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
    direction : Rdk.Spiral.direction
      [@sop.default Rdk.Spiral.Spiral_counterclockwise]
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
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Transform/Custom axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_order : Rdk.Spiral.rotation_order
      [@sop.default Rdk.Spiral.Spiral_xyz]
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
    | Turns_height -> Rdk.Spiral.Spiral_turns {
        turns = parameters.turns; height = parameters.height }
    | Height_pitch -> Rdk.Spiral.Spiral_height_pitch {
        height = parameters.height; pitch = parameters.pitch }

  let radius parameters = match parameters.radius_mode with
    | Archimedean_change -> Rdk.Spiral.Spiral_archimedean_change {
        start_radius = parameters.start_radius;
        increase_per_turn = parameters.radius_change }
    | Archimedean_end -> Rdk.Spiral.Spiral_archimedean_end {
        start_radius = parameters.start_radius; end_radius = parameters.end_radius }
    | Logarithmic_change -> Rdk.Spiral.Spiral_logarithmic_change {
        start_radius = parameters.start_radius;
        scale_per_turn = parameters.logarithmic_scale }
    | Logarithmic_end -> Rdk.Spiral.Spiral_logarithmic_end {
        start_radius = parameters.start_radius; end_radius = parameters.end_radius }

  let divisions parameters = match parameters.divisions_mode with
    | Per_curve -> Rdk.Spiral.Spiral_divisions_per_curve parameters.divisions
    | Per_turn -> Rdk.Spiral.Spiral_divisions_per_turn parameters.divisions

  let orientation parameters = match parameters.orientation with
    | Axis_x -> Rdk.Spiral.Spiral_x
    | Axis_y -> Rdk.Spiral.Spiral_y
    | Axis_z -> Rdk.Spiral.Spiral_z
    | Axis_custom -> Rdk.Spiral.Spiral_axis (Vec3.create parameters.axis_x
        parameters.axis_y parameters.axis_z)

  let build = parameters_build (fun ~label parameters ->
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
      ?distance_attribute:(optional_text parameters.distance_attribute) ())

  let factory = parameters_factory build
end

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
      ~slots:["a"; "b"]
      ~category:["Utility"] ~arity:2 (fun inputs -> create inputs)
end

module Circle = struct
  type arc_mode = Closed | Open | Chord | Sliced

  let arc_parameter = Parameter.choice ~equal:( = ) [
      "Closed", Closed; "Open arc", Open; "Chord closed", Chord;
      "Sliced", Sliced;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "XZ", Rdk.Plane_generators.Circle_xz; "XY", Rdk.Plane_generators.Circle_xy;
      "YZ", Rdk.Plane_generators.Circle_yz;
    ]

  type parameters = {
    arc : arc_mode [@sop.default Closed] [@sop.label "Arc"]
      [@sop.kind arc_parameter];
    start_angle : float [@sop.default 0.] [@sop.label "Start angle"]
      [@sop.folder "Arc"] [@sop.min (-6.283185)] [@sop.max 6.283185];
    end_angle : float [@sop.default 6.283185307179586]
      [@sop.label "End angle"] [@sop.folder "Arc"]
      [@sop.min (-6.283185)] [@sop.max 6.283185];
    orientation : Rdk.Plane_generators.circle_orientation
      [@sop.default Rdk.Plane_generators.Circle_xz] [@sop.label "Orientation"]
      [@sop.kind orientation_parameter];
    reverse : bool [@sop.default false] [@sop.label "Reverse"];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    radius_x : float [@sop.default 1.] [@sop.label "Radius X"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.primary]
    radius_y : float [@sop.default 1.] [@sop.label "Radius Y"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.primary]
    rotation : float [@sop.default 0.] [@sop.label "Rotation"]
      [@sop.folder "Transform"] [@sop.min (-3.14159)] [@sop.max 3.14159];
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    segments : int [@sop.default 48] [@sop.label "Segments"]
      [@sop.min 3] [@sop.max 256] [@sop.hard_min 3]; [@sop.primary]
  } [@@sop.node_key "circle"] [@@sop.node_label "Circle"]
    [@@sop.node_category "Create/Curve"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let arc parameters = match parameters.arc with
    | Closed -> Rdk.Plane_generators.Circle_closed
    | Open -> Rdk.Plane_generators.Circle_open_arc {
        start_angle = parameters.start_angle; end_angle = parameters.end_angle }
    | Chord -> Rdk.Plane_generators.Circle_closed_arc {
        start_angle = parameters.start_angle; end_angle = parameters.end_angle }
    | Sliced -> Rdk.Plane_generators.Circle_sliced_arc {
        start_angle = parameters.start_angle; end_angle = parameters.end_angle }

  let build = parameters_build (fun ~label parameters ->
    Sop.circle ~label ~arc:(arc parameters) ~orientation:parameters.orientation
      ~reverse:parameters.reverse
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z) ~radius_x:parameters.radius_x
      ~radius_y:parameters.radius_y ~rotation:parameters.rotation
      ~uniform_scale:parameters.uniform_scale ~segments:parameters.segments
      ~radius:1. ())

  let factory = parameters_factory build
end

module Grid = struct
  let counts_parameter = Parameter.choice ~equal:( = ) [
      "Divisions", Rdk.Plane_generators.Grid_divisions;
      "Point counts", Rdk.Plane_generators.Grid_point_counts;
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

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "XY", Rdk.Plane_generators.Grid_xy;
      "XZ", Rdk.Plane_generators.Grid_xz;
      "YZ", Rdk.Plane_generators.Grid_yz;
    ]

  type parameters = {
    counts : Rdk.Plane_generators.grid_counts [@sop.default Rdk.Plane_generators.Grid_divisions]
      [@sop.label "Counts"] [@sop.kind counts_parameter];
    connectivity : Rdk.Plane_generators.grid_connectivity
      [@sop.default Rdk.Plane_generators.Grid_triangles]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    orientation : Rdk.Plane_generators.grid_orientation [@sop.default Rdk.Plane_generators.Grid_xz]
      [@sop.label "Orientation"] [@sop.kind orientation_parameter];
    columns : int [@sop.default 10] [@sop.label "Columns"]
      [@sop.folder "Resolution"] [@sop.min 1] [@sop.max 64]
      [@sop.hard_min 1]; [@sop.primary]
    rows : int [@sop.default 10] [@sop.label "Rows"]
      [@sop.folder "Resolution"] [@sop.min 1] [@sop.max 64]
      [@sop.hard_min 1]; [@sop.primary]
    size : float [@sop.default 1.] [@sop.label "Size"]
      [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.];
    width : float [@sop.default 1.] [@sop.label "Width"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.primary]
    height : float [@sop.default 1.] [@sop.label "Height"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.primary]
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    rotation : float [@sop.default 0.] [@sop.label "Rotation"]
      [@sop.folder "Transform"] [@sop.min (-3.14159)] [@sop.max 3.14159];
    uv_attribute : string [@sop.default ""] [@sop.label "UV attribute"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "grid"] [@@sop.node_label "Grid"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters ->
    Sop.grid ~label ~counts:parameters.counts
      ~connectivity:parameters.connectivity ~orientation:parameters.orientation
      ~center:(Vec3.create parameters.center_x parameters.center_y
        parameters.center_z) ~width:parameters.width ~height:parameters.height
      ~rotation:parameters.rotation
      ?uv_attribute:(optional_text parameters.uv_attribute)
      ~columns:parameters.columns ~rows:parameters.rows ~size:parameters.size ())

  let factory = parameters_factory build

  let create ?label:node_label ?(counts = Rdk.Plane_generators.Grid_divisions)
      ?(connectivity = Rdk.Plane_generators.Grid_triangles)
      ?(orientation = Rdk.Plane_generators.Grid_xz) ?(center = Vec3.zero) ?width ?height
      ?(rotation = 0.) ?(uv_attribute = "") ~columns ~rows ~size () =
    build ~label:(label "grid" node_label) ~inputs:[] {
      counts; connectivity; orientation; columns; rows; size;
      width = Option.value ~default:size width;
      height = Option.value ~default:size height;
      center_x = center.x; center_y = center.y; center_z = center.z;
      rotation; uv_attribute }
end

module Uv_sphere = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Rdk.Uv_sphere.Sphere_triangles;
      "Alternating triangles", Rdk.Uv_sphere.Sphere_alternating_triangles;
      "Quads", Rdk.Uv_sphere.Sphere_quads;
      "Rows", Rdk.Uv_sphere.Sphere_rows;
      "Columns", Rdk.Uv_sphere.Sphere_columns;
      "Rows and columns", Rdk.Uv_sphere.Sphere_rows_and_columns;
      "Points", Rdk.Uv_sphere.Sphere_points;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Uv_sphere.Sphere_no_normals;
      "Point", Rdk.Uv_sphere.Sphere_point_normals;
      "Vertex", Rdk.Uv_sphere.Sphere_vertex_normals;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Rdk.Uv_sphere.Sphere_x;
      "Y axis", Rdk.Uv_sphere.Sphere_y;
      "Z axis", Rdk.Uv_sphere.Sphere_z;
    ]

  type parameters = {
    connectivity : Rdk.Uv_sphere.sphere_connectivity
      [@sop.default Rdk.Uv_sphere.Sphere_triangles]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    normals : Rdk.Uv_sphere.sphere_normals
      [@sop.default Rdk.Uv_sphere.Sphere_point_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    orientation : Rdk.Uv_sphere.sphere_orientation
      [@sop.default Rdk.Uv_sphere.Sphere_y]
      [@sop.label "Pole axis"] [@sop.kind orientation_parameter];
    unique_points_per_pole : bool [@sop.default false]
      [@sop.label "Unique pole points"] [@sop.folder "Topology"];
    triangular_poles : bool [@sop.default true]
      [@sop.label "Triangular poles"] [@sop.folder "Topology"];
    radius_x : float [@sop.default 1.] [@sop.label "Radius X"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "radius"] [@sop.primary]
    radius_y : float [@sop.default 1.] [@sop.label "Radius Y"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "radius"] [@sop.primary]
    radius_z : float [@sop.default 1.] [@sop.label "Radius Z"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "radius"] [@sop.primary]
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    segments : int [@sop.default 48] [@sop.label "Segments"]
      [@sop.folder "Resolution"] [@sop.min 3] [@sop.max 256]
      [@sop.hard_min 3]; [@sop.primary]
    rings : int [@sop.default 24] [@sop.label "Rings"]
      [@sop.folder "Resolution"] [@sop.min 2] [@sop.max 128]
      [@sop.hard_min 2]; [@sop.primary]
    uv_attribute : string [@sop.default "uv"] [@sop.label "UV attribute"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "uv_sphere"] [@@sop.node_label "UV Sphere"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters ->
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
      ~segments:parameters.segments ~rings:parameters.rings ~radius:1. ())

  let factory = parameters_factory build
end

module Torus = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Rdk.Parametric_generators.Torus_triangles;
      "Alternating triangles", Rdk.Parametric_generators.Torus_alternating_triangles;
      "Quads", Rdk.Parametric_generators.Torus_quads;
      "Rows", Rdk.Parametric_generators.Torus_rows;
      "Columns", Rdk.Parametric_generators.Torus_columns;
      "Rows and columns", Rdk.Parametric_generators.Torus_rows_and_columns;
      "Points", Rdk.Parametric_generators.Torus_points;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Parametric_generators.Torus_no_normals;
      "Point", Rdk.Parametric_generators.Torus_point_normals;
      "Vertex", Rdk.Parametric_generators.Torus_vertex_normals;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Rdk.Parametric_generators.Torus_x;
      "Y axis", Rdk.Parametric_generators.Torus_y;
      "Z axis", Rdk.Parametric_generators.Torus_z;
    ]

  type parameters = {
    connectivity : Rdk.Parametric_generators.torus_connectivity
      [@sop.default Rdk.Parametric_generators.Torus_triangles]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    normals : Rdk.Parametric_generators.torus_normals
      [@sop.default Rdk.Parametric_generators.Torus_point_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    orientation : Rdk.Parametric_generators.torus_orientation
      [@sop.default Rdk.Parametric_generators.Torus_y]
      [@sop.label "Hole axis"] [@sop.kind orientation_parameter];
    major_radius : float [@sop.default 1.] [@sop.label "Major radius"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.primary]
    minor_radius : float [@sop.default 0.25] [@sop.label "Minor radius"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 5.]
      [@sop.hard_min 0.]; [@sop.primary]
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
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
      [@sop.hard_min 2]; [@sop.primary]
    columns : int [@sop.default 24] [@sop.label "Columns"]
      [@sop.folder "Resolution"] [@sop.min 3] [@sop.max 256]
      [@sop.hard_min 2]; [@sop.primary]
    uv_attribute : string [@sop.default "uv"] [@sop.label "UV attribute"]
      [@sop.folder "Attributes"];
  } [@@sop.node_key "torus"] [@@sop.node_label "Torus"]
    [@@sop.node_category "Create/Primitive"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters ->
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
      ())

  let factory = parameters_factory build
end

module Tube = struct
  let connectivity_parameter = Parameter.choice ~equal:( = ) [
      "Triangles", Rdk.Parametric_generators.Tube_triangles;
      "Alternating triangles", Rdk.Parametric_generators.Tube_alternating_triangles;
      "Quads", Rdk.Parametric_generators.Tube_quads;
      "Rows", Rdk.Parametric_generators.Tube_rows;
      "Columns", Rdk.Parametric_generators.Tube_columns;
      "Rows and columns", Rdk.Parametric_generators.Tube_rows_and_columns;
      "Points", Rdk.Parametric_generators.Tube_points;
    ]

  let normals_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Parametric_generators.Tube_no_normals;
      "Point", Rdk.Parametric_generators.Tube_point_normals;
      "Vertex", Rdk.Parametric_generators.Tube_vertex_normals;
    ]

  let orientation_parameter = Parameter.choice ~equal:( = ) [
      "X axis", Rdk.Parametric_generators.Tube_x;
      "Y axis", Rdk.Parametric_generators.Tube_y;
      "Z axis", Rdk.Parametric_generators.Tube_z;
    ]

  type parameters = {
    connectivity : Rdk.Parametric_generators.tube_connectivity
      [@sop.default Rdk.Parametric_generators.Tube_triangles]
      [@sop.label "Connectivity"] [@sop.kind connectivity_parameter];
    normals : Rdk.Parametric_generators.tube_normals
      [@sop.default Rdk.Parametric_generators.Tube_point_normals]
      [@sop.label "Normals"] [@sop.kind normals_parameter];
    orientation : Rdk.Parametric_generators.tube_orientation
      [@sop.default Rdk.Parametric_generators.Tube_y]
      [@sop.label "Primary axis"] [@sop.kind orientation_parameter];
    top_radius : float [@sop.default 1.] [@sop.label "Top radius"]
      [@sop.folder "Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.primary]
    bottom_radius : float [@sop.default 1.] [@sop.label "Bottom radius"]
      [@sop.folder "Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.primary]
    height : float [@sop.default 2.] [@sop.label "Height"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.primary]
    radius_scale : float [@sop.default 1.] [@sop.label "Radius scale"]
      [@sop.folder "Size"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.];
    end_caps : bool [@sop.default true] [@sop.label "End caps"]
      [@sop.folder "Caps"];
    consolidate_cap_points : bool [@sop.default false]
      [@sop.label "Consolidate cap points"] [@sop.folder "Caps"];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Transform/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    rotation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rotation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.14159)]
      [@sop.max 3.14159]; [@sop.vec3 "rotation"]
    rows : int [@sop.default 2] [@sop.label "Rows"]
      [@sop.folder "Resolution"] [@sop.min 2] [@sop.max 128]
      [@sop.hard_min 2];
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

  let build = parameters_build (fun ~label parameters ->
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
      ~height:parameters.height ())

  let factory = parameters_factory build
end

module Transform = struct
  type parameters = {
    translate_x : float [@sop.default 0.] [@sop.label "Translate X"]
      [@sop.folder "Translate"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "translate"]
    translate_y : float [@sop.default 0.] [@sop.label "Translate Y"]
      [@sop.folder "Translate"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "translate"]
    translate_z : float [@sop.default 0.] [@sop.label "Translate Z"]
      [@sop.folder "Translate"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "translate"]
    rotate_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Rotate"] [@sop.min (-3.14159)] [@sop.max 3.14159]; [@sop.vec3 "rotate"]
    rotate_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Rotate"] [@sop.min (-3.14159)] [@sop.max 3.14159]; [@sop.vec3 "rotate"]
    rotate_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Rotate"] [@sop.min (-3.14159)] [@sop.max 3.14159]; [@sop.vec3 "rotate"]
    scale_x : float [@sop.default 1.] [@sop.label "Scale X"]
      [@sop.folder "Scale"] [@sop.min 0.01] [@sop.max 10.]; [@sop.vec3 "scale"]
    scale_y : float [@sop.default 1.] [@sop.label "Scale Y"]
      [@sop.folder "Scale"] [@sop.min 0.01] [@sop.max 10.]; [@sop.vec3 "scale"]
    scale_z : float [@sop.default 1.] [@sop.label "Scale Z"]
      [@sop.folder "Scale"] [@sop.min 0.01] [@sop.max 10.]; [@sop.vec3 "scale"]
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Scale"] [@sop.min 0.01] [@sop.max 10.] [@sop.hard_min 0.];
    preserve_normal_length : bool [@sop.default false]
      [@sop.label "Preserve normal length"] [@sop.folder "Normals"];
    recompute_normals : bool [@sop.default false]
      [@sop.label "Recompute normals"] [@sop.folder "Normals"];
  } [@@sop.node_key "transform"] [@@sop.node_label "Transform"]
    [@@sop.node_category "Modify"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.transform_trs ~label
      ~translate:(Vec3.create parameters.translate_x parameters.translate_y
        parameters.translate_z)
      ~rotate:(Vec3.create parameters.rotate_x parameters.rotate_y
        parameters.rotate_z)
      ~scale:(Vec3.create parameters.scale_x parameters.scale_y
        parameters.scale_z)
      ~uniform_scale:parameters.uniform_scale
      ~preserve_normal_length:parameters.preserve_normal_length
      ~recompute_normals:parameters.recompute_normals input)

  let factory = parameters_factory build

  let create ?label:node_label ?(translate = Vec3.zero) ?(rotate = Vec3.zero)
      ?(scale = Vec3.create 1. 1. 1.) ?(uniform_scale = 1.) input =
    build ~label:(label "transform" node_label) ~inputs:[input]
      { parameters_default with
        translate_x = translate.Vec3.x; translate_y = translate.y; translate_z = translate.z;
        rotate_x = rotate.Vec3.x; rotate_y = rotate.y; rotate_z = rotate.z;
        scale_x = scale.Vec3.x; scale_y = scale.y; scale_z = scale.z; uniform_scale }

end

module Match_size = struct
  let fit_parameter = Parameter.choice ~equal:( = ) [
      "Translate only", Rdk.Match_size.Translate_only;
      "Stretch", Rdk.Match_size.Stretch;
      "Contain", Rdk.Match_size.Contain;
      "Cover", Rdk.Match_size.Cover;
      "Match X", Rdk.Match_size.Match_x;
      "Match Y", Rdk.Match_size.Match_y;
      "Match Z", Rdk.Match_size.Match_z;
      "Match perimeter", Rdk.Match_size.Match_perimeter;
      "Match area", Rdk.Match_size.Match_area;
      "Match volume", Rdk.Match_size.Match_volume;
    ]

  type parameters = {
    fit : Rdk.Match_size.match_size_fit [@sop.default Rdk.Match_size.Contain]
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
      [@sop.hard_min (-1.)] [@sop.hard_max 1.]; [@sop.vec3 "justify"]
    justify_y : float [@sop.default 0.] [@sop.label "Justify Y"]
      [@sop.folder "Justify/Source"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.]; [@sop.vec3 "justify"]
    justify_z : float [@sop.default 0.] [@sop.label "Justify Z"]
      [@sop.folder "Justify/Source"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.]; [@sop.vec3 "justify"]
    target_justify_x : float [@sop.default 0.] [@sop.label "Justify X"]
      [@sop.folder "Justify/Target"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.]; [@sop.vec3 "target_justify"]
    target_justify_y : float [@sop.default 0.] [@sop.label "Justify Y"]
      [@sop.folder "Justify/Target"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.]; [@sop.vec3 "target_justify"]
    target_justify_z : float [@sop.default 0.] [@sop.label "Justify Z"]
      [@sop.folder "Justify/Target"] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.hard_min (-1.)] [@sop.hard_max 1.]; [@sop.vec3 "target_justify"]
    offset_x : float [@sop.default 0.] [@sop.label "Offset X"]
      [@sop.folder "Transform/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "offset"]
    offset_y : float [@sop.default 0.] [@sop.label "Offset Y"]
      [@sop.folder "Transform/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "offset"]
    offset_z : float [@sop.default 0.] [@sop.label "Offset Z"]
      [@sop.folder "Transform/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "offset"]
    scale : float [@sop.default 1.] [@sop.label "Scale"]
      [@sop.folder "Transform"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    target_center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Numeric target/Center"] [@sop.min (-10.)]
      [@sop.max 10.]; [@sop.vec3 "target_center"]
    target_center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Numeric target/Center"] [@sop.min (-10.)]
      [@sop.max 10.]; [@sop.vec3 "target_center"]
    target_center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Numeric target/Center"] [@sop.min (-10.)]
      [@sop.max 10.]; [@sop.vec3 "target_center"]
    target_size_x : float [@sop.default 1.] [@sop.label "Size X"]
      [@sop.folder "Numeric target/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "target_size"]
    target_size_y : float [@sop.default 1.] [@sop.label "Size Y"]
      [@sop.folder "Numeric target/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "target_size"]
    target_size_z : float [@sop.default 1.] [@sop.label "Size Z"]
      [@sop.folder "Numeric target/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "target_size"]
  } [@@sop.node_key "match_size"] [@@sop.node_label "Match Size"]
    [@@sop.node_category "Modify"] [@@sop.node_inputs 2] [@@sop.node_slots "input, target"]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input target ->
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
      ?target input)

  let factory = parameters_factory build
end

module Clip = struct
  let keep_parameter = Parameter.choice ~equal:( = ) [
      "Above", Rdk.Plane_clip.Above;
      "Below", Rdk.Plane_clip.Below;
      "All", Rdk.Plane_clip.All;
    ]

  type parameters = {
    keep : Rdk.Plane_clip.keep [@sop.default Rdk.Plane_clip.Above]
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
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    normal_x : float [@sop.default 0.] [@sop.label "Normal X"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "normal"]
    normal_y : float [@sop.default 1.] [@sop.label "Normal Y"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "normal"]
    normal_z : float [@sop.default 0.] [@sop.label "Normal Z"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "normal"]
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

  let build = parameters_build (fun ~label parameters input ->
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
        parameters.normal_z) input)

  let factory = parameters_factory build
end

module Copy_to_points = struct
  type parameters = {
    source_group : string [@sop.default ""] [@sop.label "Source group"]
      [@sop.folder "Selection"];
    target_group : string [@sop.default ""] [@sop.label "Target group"]
      [@sop.folder "Selection"];
    piece_attribute : string [@sop.default ""] [@sop.label "Piece attribute"]
      [@sop.folder "Matching"];
    pack : bool [@sop.default false] [@sop.label "Pack and instance"];
  } [@@sop.node_key "copy_to_points"] [@@sop.node_label "Copy to Points"]
    [@@sop.node_category "Copy"] [@@sop.node_inputs 2] [@@sop.node_slots "source, targets"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters source targets ->
    Sop.copy_to_points ~label
      ?source_group:(optional_text parameters.source_group)
      ?target_group:(optional_text parameters.target_group)
      ?piece_attribute:(optional_text parameters.piece_attribute)
      ~pack:parameters.pack ~source ~targets ())

  let factory = parameters_factory build

  let create ?label:node_label ?(source_group = "") ?(target_group = "")
      ?(piece_attribute = "") ?(pack = false) ~source ~targets () =
    build ~label:(label "copy-to-points" node_label) ~inputs:[source; targets] {
      source_group; target_group; piece_attribute; pack }
end

module Mountain = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Group"];
    direction_attribute : string [@sop.default ""]
      [@sop.label "Direction attribute"];
    mask_attribute : string [@sop.default ""] [@sop.label "Mask attribute"];
    height_attribute : string [@sop.default ""] [@sop.label "Height attribute"];
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.min 0]
      [@sop.max 9999];
    height : float [@sop.default 1.] [@sop.label "Height"]
      [@sop.min 0.] [@sop.max 2.] [@sop.hard_min 0.];
    frequency_x : float [@sop.default 1.] [@sop.label "Frequency X"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.]; [@sop.vec3 "frequency"]
    frequency_y : float [@sop.default 1.] [@sop.label "Frequency Y"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.]; [@sop.vec3 "frequency"]
    frequency_z : float [@sop.default 1.] [@sop.label "Frequency Z"]
      [@sop.folder "Frequency"] [@sop.min 0.01] [@sop.max 4.]
      [@sop.hard_min 0.]; [@sop.vec3 "frequency"]
    octaves : int [@sop.default 4] [@sop.label "Octaves"]
      [@sop.folder "Fractal"] [@sop.min 1] [@sop.max 8]
      [@sop.hard_min 1];
    lacunarity : float [@sop.default 2.] [@sop.label "Lacunarity"]
      [@sop.folder "Fractal"] [@sop.min 1.] [@sop.max 4.]
      [@sop.hard_min 0.];
    roughness : float [@sop.default 0.5] [@sop.label "Roughness"]
      [@sop.folder "Fractal"] [@sop.min 0.] [@sop.max 1.]
      [@sop.hard_min 0.];
    recompute_normals : bool [@sop.default false]
      [@sop.label "Recompute normals"];
  } [@@sop.node_key "mountain"] [@@sop.node_label "Mountain"]
    [@@sop.node_category "Deform"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.mountain ~label ?group:(optional_text parameters.group)
      ~seed:parameters.seed
      ?direction_attribute:(optional_text parameters.direction_attribute)
      ?mask_attribute:(optional_text parameters.mask_attribute)
      ~height:parameters.height
      ~frequency:(Vec3.create parameters.frequency_x parameters.frequency_y
        parameters.frequency_z) ~octaves:parameters.octaves
      ~lacunarity:parameters.lacunarity ~roughness:parameters.roughness
      ?height_attribute:(optional_text parameters.height_attribute)
      ~recompute_normals:parameters.recompute_normals input)

  let factory = parameters_factory build

  let create ?label:node_label ?group ?direction_attribute ?mask_attribute
      ?height_attribute
      ?(recompute_normals = parameters_default.recompute_normals)
      ~seed ~height ~frequency
      ~octaves ~lacunarity ~roughness input =
    build ~label:(label "mountain" node_label) ~inputs:[input] {
        group = Option.value ~default:parameters_default.group group;
        direction_attribute = Option.value
          ~default:parameters_default.direction_attribute direction_attribute;
        mask_attribute = Option.value
          ~default:parameters_default.mask_attribute mask_attribute;
        height_attribute = Option.value
          ~default:parameters_default.height_attribute height_attribute;
        seed; height; frequency_x = frequency.Vec3.x;
        frequency_y = frequency.y; frequency_z = frequency.z;
        octaves; lacunarity; roughness; recompute_normals }
end

module Peak = struct
  type parameters = {
    direction_attribute : string [@sop.default "N"]
      [@sop.label "Direction attribute"] [@sop.folder "Direction"];
    normalize_direction : bool [@sop.default true]
      [@sop.label "Normalize direction"] [@sop.folder "Direction"];
    mask_attribute : string [@sop.default ""] [@sop.label "Mask attribute"];
    distance : float [@sop.default 0.1] [@sop.label "Distance"]
      [@sop.min (-10.)] [@sop.max 10.]; [@sop.primary]
    recompute_normals : bool [@sop.default false]
      [@sop.label "Recompute normals"];
  } [@@sop.node_key "peak"] [@@sop.node_label "Peak"]
    [@@sop.node_category "Deform"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.peak ~label
      ?direction_attribute:(optional_text parameters.direction_attribute)
      ~normalize_direction:parameters.normalize_direction
      ?mask_attribute:(optional_text parameters.mask_attribute)
      ~distance:parameters.distance
      ~recompute_normals:parameters.recompute_normals input)

  let factory = parameters_factory build
end

module Bend = struct
  type parameters = {
    mask_attribute : string [@sop.default ""] [@sop.label "Mask attribute"];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Capture/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Capture/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Capture/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Capture/Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Capture/Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Capture/Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    up_x : float [@sop.default 0.] [@sop.label "Up X"]
      [@sop.folder "Capture/Up"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "up"]
    up_y : float [@sop.default 0.] [@sop.label "Up Y"]
      [@sop.folder "Capture/Up"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "up"]
    up_z : float [@sop.default 1.] [@sop.label "Up Z"]
      [@sop.folder "Capture/Up"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "up"]
    length : float [@sop.default 1.] [@sop.label "Length"]
      [@sop.folder "Capture"] [@sop.min 0.01] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.primary]
    bend_angle : float [@sop.default 0.] [@sop.label "Bend angle"]
      [@sop.folder "Deformation"] [@sop.min (-6.283185)] [@sop.max 6.283185]; [@sop.primary]
    twist_angle : float [@sop.default 0.] [@sop.label "Twist angle"]
      [@sop.folder "Deformation"] [@sop.min (-6.283185)] [@sop.max 6.283185]; [@sop.primary]
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

  let build = parameters_build (fun ~label parameters input ->
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
      ~recompute_normals:parameters.recompute_normals input)

  let factory = parameters_factory build
end

module Smooth = struct
  type mode = Laplacian | Custom

  let boundary_parameter = Parameter.choice ~equal:( = ) [
      "Free", Rdk.Smooth.Smooth_free;
      "Pin unshared", Rdk.Smooth.Smooth_unshared;
      "Pin group boundary", Rdk.Smooth.Smooth_group_boundary;
    ]

  let method_parameter = Parameter.choice ~equal:( = ) [
      "Uniform", Rdk.Attribute_ops.Uniform;
      "Edge length", Rdk.Attribute_ops.Edge_length;
    ]

  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Laplacian", Laplacian; "Custom steps", Custom;
    ]

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    constrained_points : string [@sop.default ""]
      [@sop.label "Constrained points"];
    boundary : Rdk.Smooth.boundary [@sop.default Rdk.Smooth.Smooth_free]
      [@sop.label "Boundary"] [@sop.kind boundary_parameter];
    iterations : int [@sop.default 10] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 200] [@sop.hard_min 1];
    method_ : Rdk.Attribute_ops.blur_method
      [@sop.default Rdk.Attribute_ops.Uniform]
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

  let build = parameters_build (fun ~label parameters input ->
    let mode = match parameters.mode with
      | Laplacian -> Rdk.Attribute_ops.Laplacian parameters.step
      | Custom -> Rdk.Attribute_ops.Custom_steps {
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
      ~attributes:parameters.attributes input)

  let factory = parameters_factory build
end

module Separate_pieces = struct
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Point", Rdk.Attribute.Point;
      "Primitive", Rdk.Attribute.Primitive;
    ]

  let mode_parameter = Parameter.choice ~equal:( = ) [
      "Separate", Rdk.Separate_pieces.Separate_pieces_separate;
      "Move back", Rdk.Separate_pieces.Separate_pieces_move_back;
    ]

  type parameters = {
    owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Primitive]
      [@sop.label "Piece owner"] [@sop.kind owner_parameter];
    piece_attribute : string [@sop.default "piece"]
      [@sop.label "Piece attribute"];
    translation_attribute : string [@sop.default "piece_translation"]
      [@sop.label "Translation attribute"];
    axis_x : float [@sop.default 1.] [@sop.label "Axis X"]
      [@sop.folder "Axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_y : float [@sop.default 0.] [@sop.label "Axis Y"]
      [@sop.folder "Axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    axis_z : float [@sop.default 0.] [@sop.label "Axis Z"]
      [@sop.folder "Axis"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "axis"]
    gap : float [@sop.default 0.001] [@sop.label "Gap"]
      [@sop.min 0.] [@sop.max 1.] [@sop.hard_min 0.];
    mode : Rdk.Separate_pieces.mode
      [@sop.default Rdk.Separate_pieces.Separate_pieces_separate]
      [@sop.label "Mode"] [@sop.kind mode_parameter];
  } [@@sop.node_key "separate_pieces"] [@@sop.node_label "Separate Pieces"]
    [@@sop.node_category "Modify/Pieces"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.separate_pieces ~label ~owner:parameters.owner
      ~translation_attribute:parameters.translation_attribute
      ~axis:(Vec3.create parameters.axis_x parameters.axis_y
        parameters.axis_z) ~gap:parameters.gap ~mode:parameters.mode
      ~piece_attribute:parameters.piece_attribute input)

  let factory = parameters_factory build
end

module Snap_to_grid = struct
  let rounding_parameter = Parameter.choice ~equal:( = ) [
      "Nearest", Rdk.Fuse_grid.Grid_nearest;
      "Down", Rdk.Fuse_grid.Grid_down;
      "Up", Rdk.Fuse_grid.Grid_up;
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

  type parameters = {
    group : string [@sop.default ""] [@sop.label "Point group"];
    spacing_x : float [@sop.default 1.] [@sop.label "Spacing X"]
      [@sop.folder "Grid/Spacing"] [@sop.min 0.001] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "spacing"]
    spacing_y : float [@sop.default 1.] [@sop.label "Spacing Y"]
      [@sop.folder "Grid/Spacing"] [@sop.min 0.001] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "spacing"]
    spacing_z : float [@sop.default 1.] [@sop.label "Spacing Z"]
      [@sop.folder "Grid/Spacing"] [@sop.min 0.001] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "spacing"]
    offset_x : float [@sop.default 0.] [@sop.label "Offset X"]
      [@sop.folder "Grid/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "offset"]
    offset_y : float [@sop.default 0.] [@sop.label "Offset Y"]
      [@sop.folder "Grid/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "offset"]
    offset_z : float [@sop.default 0.] [@sop.label "Offset Z"]
      [@sop.folder "Grid/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "offset"]
    rounding : Rdk.Fuse_grid.grid_rounding [@sop.default Rdk.Fuse_grid.Grid_nearest]
      [@sop.label "Rounding"] [@sop.kind rounding_parameter];
    limit_distance : bool [@sop.default false]
      [@sop.label "Limit snapping distance"];
    max_distance : float [@sop.default 1.] [@sop.label "Maximum distance"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
    fuse_points : bool [@sop.default false] [@sop.label "Fuse points"]
      [@sop.folder "Fuse"];
    position : Rdk.Fuse_reduce.position
      [@sop.default Rdk.Fuse_reduce.Average_position]
      [@sop.label "Position"] [@sop.folder "Fuse"]
      [@sop.kind position_parameter];
    weight_attribute : string [@sop.default ""]
      [@sop.label "Weight attribute"] [@sop.folder "Fuse"];
    attributes : Rdk.Fuse_reduce.attributes
      [@sop.default Rdk.Fuse_reduce.Keep_first]
      [@sop.label "Attributes"] [@sop.folder "Fuse"]
      [@sop.kind attributes_parameter];
    snapped_group : string [@sop.default ""] [@sop.label "Snapped group"]
      [@sop.folder "Output"];
  } [@@sop.node_key "snap_to_grid"] [@@sop.node_label "Snap to Grid"]
    [@@sop.node_category "Point"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
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
      ?snapped_group:(optional_text parameters.snapped_group) input)

  let factory = parameters_factory build
end

module Point_generate = struct
  type parameters = {
    points : int [@sop.default 50] [@sop.label "Points"]
      [@sop.min 1] [@sop.max 50] [@sop.hard_min 1] [@sop.hard_max 50];
  } [@@sop.node_key "points"] [@@sop.node_label "Point Generate"]
    [@@sop.node_operation "point_generate"]
    [@@sop.node_category "Create/Point"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters ->
    Sop.point_generate_origin ~label ~points:parameters.points ())

  let factory = parameters_factory build

  let origin ?label:node_label ~points () =
    build ~label:(label "point-generate" node_label) ~inputs:[] { points }
end

module Point_jitter = struct
  type parameters = {
    group : string [@sop.default ""] [@sop.label "Group"];
    mask_attribute : string [@sop.default ""] [@sop.label "Mask attribute"];
    id_attribute : string [@sop.default ""] [@sop.label "ID attribute"];
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.min 0]
      [@sop.max 9999];
    scale : float [@sop.default 1.] [@sop.label "Scale"]
      [@sop.min 0.] [@sop.max 2.] [@sop.hard_min 0.];
    axis_x : float [@sop.default 1.] [@sop.label "Axis X"]
      [@sop.folder "Axis scales"] [@sop.min 0.] [@sop.max 2.]
      [@sop.hard_min 0.]; [@sop.vec3 "axis"]
    axis_y : float [@sop.default 1.] [@sop.label "Axis Y"]
      [@sop.folder "Axis scales"] [@sop.min 0.] [@sop.max 2.]
      [@sop.hard_min 0.]; [@sop.vec3 "axis"]
    axis_z : float [@sop.default 1.] [@sop.label "Axis Z"]
      [@sop.folder "Axis scales"] [@sop.min 0.] [@sop.max 2.]
      [@sop.hard_min 0.]; [@sop.vec3 "axis"]
  } [@@sop.node_key "point_jitter"] [@@sop.node_label "Point Jitter"]
    [@@sop.node_category "Point"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    Sop.point_jitter ~label ?group:(optional_text parameters.group)
      ?mask_attribute:(optional_text parameters.mask_attribute)
      ?id_attribute:(optional_text parameters.id_attribute)
      ~seed:parameters.seed ~scale:parameters.scale
      ~axis_scales:(Vec3.create parameters.axis_x parameters.axis_y
        parameters.axis_z) input)

  let factory = parameters_factory build

  let create ?label:node_label ?group ?mask_attribute ?id_attribute ~seed ~scale
      ?(axis_scales = Vec3.create parameters_default.axis_x
          parameters_default.axis_y parameters_default.axis_z) input =
    build ~label:(label "point-jitter" node_label) ~inputs:[input] {
        group = Option.value ~default:parameters_default.group group;
        mask_attribute = Option.value
          ~default:parameters_default.mask_attribute mask_attribute;
        id_attribute = Option.value
          ~default:parameters_default.id_attribute id_attribute;
        seed; scale; axis_x = axis_scales.Vec3.x; axis_y = axis_scales.y;
        axis_z = axis_scales.z }
end

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

  let build = parameters_build (fun ~label parameters input ->
    Sop.duplicate ~label ~copies:parameters.copies
      ~cumulative:parameters.cumulative ~transform:(matrix parameters)
      ?group:(optional_text parameters.group)
      ?copy_group_prefix:(optional_text parameters.copy_group_prefix)
      ~preserve_groups:parameters.preserve_groups input)

  let factory = parameters_factory build

  let create ?label:node_label ?(copies = parameters_default.copies)
      ?(cumulative = parameters_default.cumulative)
      ?(transform = matrix parameters_default) input =
    let m row column = Mat4.get transform ~row ~column in
    build ~label:(label "duplicate" node_label) ~inputs:[input]
      { parameters_default with copies; cumulative;
        m00 = m 0 0; m01 = m 0 1; m02 = m 0 2; m03 = m 0 3;
        m10 = m 1 0; m11 = m 1 1; m12 = m 1 2; m13 = m 1 3;
        m20 = m 2 0; m21 = m 2 1; m22 = m 2 2; m23 = m 2 3;
        m30 = m 3 0; m31 = m 3 1; m32 = m 3 2; m33 = m 3 3 }
end

module Extract_centroid = struct
  type run_mode = Detail | Primitives | Point_pieces | Primitive_pieces
  let run_parameter = Parameter.choice ~equal:( = ) [
      "Detail", Detail; "Primitives", Primitives;
      "Point pieces", Point_pieces; "Primitive pieces", Primitive_pieces;
    ]
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Point mass", Rdk.Curve_topology.Centroid_point_mass;
      "Bounding box", Rdk.Curve_topology.Centroid_bounding_box;
      "Convex hull", Rdk.Curve_topology.Centroid_convex_hull;
    ]

  type parameters = {
    run_over : run_mode [@sop.default Detail]
      [@sop.label "Run over"] [@sop.kind run_parameter];
    piece_attribute : string [@sop.default "piece"]
      [@sop.label "Piece attribute"];
    method_ : Rdk.Curve_topology.centroid_method
      [@sop.default Rdk.Curve_topology.Centroid_point_mass]
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
    | Detail -> Rdk.Curve_topology.Centroid_detail
    | Primitives -> Rdk.Curve_topology.Centroid_primitives
    | Point_pieces -> Rdk.Curve_topology.Centroid_pieces {
        owner = Rdk.Curve_topology.Centroid_piece_points;
        attribute = parameters.piece_attribute }
    | Primitive_pieces -> Rdk.Curve_topology.Centroid_pieces {
        owner = Rdk.Curve_topology.Centroid_piece_primitives;
        attribute = parameters.piece_attribute }

  let build = parameters_build (fun ~label parameters input ->
    Sop.extract_centroid ~label ~run_over:(run_over parameters)
      ~method_:parameters.method_
      ?source_primitive_attribute:
        (optional_text parameters.source_primitive_attribute)
      ?piece_output_attribute:
        (optional_text parameters.piece_output_attribute) input)
  let factory = parameters_factory build
end

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
      [@sop.folder "Padding/Lower"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "lower"]
    lower_y : float [@sop.default 0.] [@sop.label "Lower Y"]
      [@sop.folder "Padding/Lower"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "lower"]
    lower_z : float [@sop.default 0.] [@sop.label "Lower Z"]
      [@sop.folder "Padding/Lower"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "lower"]
    upper_x : float [@sop.default 0.] [@sop.label "Upper X"]
      [@sop.folder "Padding/Upper"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "upper"]
    upper_y : float [@sop.default 0.] [@sop.label "Upper Y"]
      [@sop.folder "Padding/Upper"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "upper"]
    upper_z : float [@sop.default 0.] [@sop.label "Upper Z"]
      [@sop.folder "Padding/Upper"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "upper"]
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
    | Box -> Rdk.Bound.Bound_box { divisions =
        parameters.divisions_x, parameters.divisions_y, parameters.divisions_z }
    | Sphere -> Rdk.Bound.Bound_sphere { segments = parameters.segments;
        rings = parameters.rings; minimum_radius = parameters.minimum_radius }

  let build = parameters_build (fun ~label parameters input ->
    Sop.bound ~label
      ?selection:(optional_element_group parameters.group_owner
        parameters.group) ~shape:(shape parameters)
      ~lower_padding:(Vec3.create parameters.lower_x parameters.lower_y
        parameters.lower_z)
      ~upper_padding:(Vec3.create parameters.upper_x parameters.upper_y
        parameters.upper_z)
      ?bounds_group:(optional_text parameters.bounds_group)
      ?center_attribute:(optional_text parameters.center_attribute)
      ?radii_attribute:(optional_text parameters.radii_attribute) input)
  let factory = parameters_factory build
end

module Ray = struct
  type direction = Direction_vector | Direction_normal | Direction_attribute
  let method_parameter = Parameter.choice ~equal:( = ) [
      "Minimum distance", Rdk.Ray.Ray_minimum_distance;
      "Project rays", Rdk.Ray.Ray_project;
    ]
  let direction_parameter = Parameter.choice ~equal:( = ) [
      "Vector", Direction_vector; "Normal", Direction_normal;
      "Attribute", Direction_attribute;
    ]
  let direction_mode_parameter = Parameter.choice ~equal:( = ) [
      "Forward", Rdk.Ray.Ray_forward; "Reverse", Rdk.Ray.Ray_reverse;
      "Bidirectional closest", Rdk.Ray.Ray_bidirectional_closest;
      "Bidirectional farthest", Rdk.Ray.Ray_bidirectional_farthest;
    ]
  let surface_parameter = Parameter.choice ~equal:( = ) [
      "First surface", Rdk.Ray.Ray_first_surface;
      "Last surface", Rdk.Ray.Ray_last_surface;
    ]
  let combine_parameter = Parameter.choice ~equal:( = ) [
      "Average", Rdk.Ray.Ray_average; "Median", Rdk.Ray.Ray_median;
      "Shortest", Rdk.Ray.Ray_shortest; "Longest", Rdk.Ray.Ray_longest;
    ]

  type parameters = {
    group_owner : element_owner [@sop.default Element_point]
      [@sop.label "Group type"] [@sop.kind element_owner_parameter];
    group : string [@sop.default ""] [@sop.label "Group"];
    collision_group : string [@sop.default ""]
      [@sop.label "Collision primitive group"];
    method_ : Rdk.Ray.method_ [@sop.default Rdk.Ray.Ray_project]
      [@sop.label "Method"] [@sop.kind method_parameter];
    direction : direction [@sop.default Direction_normal]
      [@sop.label "Direction"] [@sop.folder "Ray"]
      [@sop.kind direction_parameter];
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Ray/Vector"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction_vector"]
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Ray/Vector"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction_vector"]
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Ray/Vector"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction_vector"]
    direction_attribute : string [@sop.default "N"]
      [@sop.label "Direction attribute"] [@sop.folder "Ray"];
    direction_mode : Rdk.Ray.direction_mode
      [@sop.default Rdk.Ray.Ray_forward]
      [@sop.label "Direction mode"] [@sop.folder "Ray"]
      [@sop.kind direction_mode_parameter];
    surface_hit : Rdk.Ray.surface_hit
      [@sop.default Rdk.Ray.Ray_first_surface]
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
    combine : Rdk.Ray.combine [@sop.default Rdk.Ray.Ray_average]
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
    [@@sop.node_category "Modify/Project"] [@@sop.node_inputs 2] [@@sop.node_slots "source, collision"]
    [@@deriving sop_params, sop_node]

  let direction parameters = match parameters.direction with
    | Direction_vector -> Rdk.Ray.Ray_vector (Vec3.create
        parameters.direction_x parameters.direction_y parameters.direction_z)
    | Direction_normal -> Rdk.Ray.Ray_normal
    | Direction_attribute ->
        Rdk.Ray.Ray_attribute parameters.direction_attribute

  let build = parameters_build (fun ~label parameters source collision ->
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
      ~match_groups:parameters.match_groups ~collision source)
  let factory = parameters_factory build
end

module Sort = struct
  type key = X | Y | Z | Distance | Vector | Attribute | Vertex_order
    | Primitive_index | Spatial | Random | Index_attribute | Reverse | Shift
  let owner_parameter = Parameter.choice ~equal:( = ) [
      "Points", Rdk.Ordering.Points; "Primitives", Rdk.Ordering.Primitives;
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
    owner : Rdk.Ordering.owner [@sop.default Rdk.Ordering.Points]
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
    | X -> Rdk.Ordering.X | Y -> Rdk.Ordering.Y | Z -> Rdk.Ordering.Z
    | Distance -> Rdk.Ordering.Distance_to
        (Vec3.create parameters.x parameters.y parameters.z)
    | Vector -> Rdk.Ordering.Along_vector
        (Vec3.create parameters.x parameters.y parameters.z)
    | Attribute -> Rdk.Ordering.Attribute_component {
        name = parameters.attribute; component = parameters.component }
    | Vertex_order -> Rdk.Ordering.By_vertex_order
    | Primitive_index -> Rdk.Ordering.By_primitive_index
    | Spatial -> Rdk.Ordering.Spatial_locality
    | Random -> Rdk.Ordering.Random (Int64.of_int parameters.seed)
    | Index_attribute -> Rdk.Ordering.Index_attribute parameters.attribute
    | Reverse -> Rdk.Ordering.Reverse
    | Shift -> Rdk.Ordering.Shift parameters.shift
  let build = parameters_build (fun ~label parameters input ->
    Sop.sort ~label ?group:(optional_text parameters.group)
        ~descending:parameters.descending
        ?output_indices:(optional_text parameters.output_indices)
        ~combine_indices:parameters.combine_indices ~owner:parameters.owner
        ~key:(key parameters) input)
  let factory = parameters_factory build
end

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
    density_owner : Rdk.Attribute.owner [@sop.default Rdk.Attribute.Primitive]
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
  let build = parameters_build (fun ~label parameters input ->
    let density = if not parameters.use_density then None else
      Some (Rdk.Scatter.density ~owner:parameters.density_owner
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
      ~count:parameters.count input)
  let factory = parameters_factory build
end

module Merge = struct
  (* One rest slot: any number of inputs, the first required. *)
  let factory = Edit_graph.factory_slots ~key:"merge" ~label:"Merge"
      ~slots:["input"]
      ~category:["Copy"] ~inputs:Edit_graph.[Rest]
      (fun inputs -> Sop.merge ~label:"merge" (List.filter_map Fun.id inputs))

  let create ?label:node_label inputs =
    Sop.merge ~label:(label "merge" node_label) inputs
end

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
  let build = parameters_build (fun ~label parameters input ->
    Sop.extract_point_from_curve ~label
        ?group:(optional_text parameters.group) ~cut:(cut parameters)
        ~point_attributes:parameters.point_attributes
        ~copy_primitive_attributes:parameters.copy_primitive_attributes
        ~primitive_attributes:parameters.primitive_attributes
        ?curve_u_attribute:(optional_text parameters.curve_u_attribute)
        ?number_cuts_attribute:(optional_text parameters.number_cuts_attribute)
        ?curve_number_attribute:(optional_text parameters.curve_number_attribute)
        ~distance_attribute:parameters.distance_attribute input)
  let factory = parameters_factory build
end

module Soft_transform = struct
  type metric = Radius | Edge | Attribute
  let order_parameter = Parameter.choice ~equal:( = ) [
      "SRT", Rdk.Transform_ops.Transform_srt; "STR", Rdk.Transform_ops.Transform_str;
      "RST", Rdk.Transform_ops.Transform_rst; "RTS", Rdk.Transform_ops.Transform_rts;
      "TSR", Rdk.Transform_ops.Transform_tsr; "TRS", Rdk.Transform_ops.Transform_trs;
    ]
  let rotation_order_parameter = Parameter.choice ~equal:( = ) [
      "XYZ", Rdk.Transform_ops.Transform_xyz; "XZY", Rdk.Transform_ops.Transform_xzy;
      "YXZ", Rdk.Transform_ops.Transform_yxz; "YZX", Rdk.Transform_ops.Transform_yzx;
      "ZXY", Rdk.Transform_ops.Transform_zxy; "ZYX", Rdk.Transform_ops.Transform_zyx;
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
    order : Rdk.Transform_ops.transform_order [@sop.default Rdk.Transform_ops.Transform_srt]
      [@sop.label "Transform order"] [@sop.folder "Transform"]
      [@sop.kind order_parameter];
    rotation_order : Rdk.Transform_ops.transform_rotation_order
      [@sop.default Rdk.Transform_ops.Transform_xyz] [@sop.label "Rotation order"]
      [@sop.folder "Transform/Rotate"] [@sop.kind rotation_order_parameter];
    translate_x : float [@sop.default 0.] [@sop.label "Translate X"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "translate"]
    translate_y : float [@sop.default 0.] [@sop.label "Translate Y"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "translate"]
    translate_z : float [@sop.default 0.] [@sop.label "Translate Z"]
      [@sop.folder "Transform/Translate"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "translate"]
    rotate_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.vec3 "rotate"]
    rotate_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.vec3 "rotate"]
    rotate_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Transform/Rotate"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.vec3 "rotate"]
    scale_x : float [@sop.default 1.] [@sop.label "Scale X"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "scale"]
    scale_y : float [@sop.default 1.] [@sop.label "Scale Y"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "scale"]
    scale_z : float [@sop.default 1.] [@sop.label "Scale Z"]
      [@sop.folder "Transform/Scale"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "scale"]
    shear_xy : float [@sop.default 0.] [@sop.label "Shear XY"]
      [@sop.folder "Transform/Shear"] [@sop.min (-4.)] [@sop.max 4.];
    shear_xz : float [@sop.default 0.] [@sop.label "Shear XZ"]
      [@sop.folder "Transform/Shear"] [@sop.min (-4.)] [@sop.max 4.];
    shear_yz : float [@sop.default 0.] [@sop.label "Shear YZ"]
      [@sop.folder "Transform/Shear"] [@sop.min (-4.)] [@sop.max 4.];
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Transform"] [@sop.min (-10.)] [@sop.max 10.];
    pivot_x : float [@sop.default 0.] [@sop.label "Pivot X"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "pivot"]
    pivot_y : float [@sop.default 0.] [@sop.label "Pivot Y"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "pivot"]
    pivot_z : float [@sop.default 0.] [@sop.label "Pivot Z"]
      [@sop.folder "Transform/Pivot"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "pivot"]
    pivot_rotation_x : float [@sop.default 0.] [@sop.label "Pivot rotate X"]
      [@sop.folder "Transform/Pivot rotation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.vec3 "pivot_rotation"]
    pivot_rotation_y : float [@sop.default 0.] [@sop.label "Pivot rotate Y"]
      [@sop.folder "Transform/Pivot rotation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.vec3 "pivot_rotation"]
    pivot_rotation_z : float [@sop.default 0.] [@sop.label "Pivot rotate Z"]
      [@sop.folder "Transform/Pivot rotation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.vec3 "pivot_rotation"]
    invert : bool [@sop.default false] [@sop.label "Invert transform"]
      [@sop.folder "Transform"];
    metric : metric [@sop.default Radius] [@sop.label "Distance metric"]
      [@sop.folder "Soft selection"] [@sop.kind metric_parameter];
    metric_attribute : string [@sop.default "mask"]
      [@sop.label "Metric attribute"] [@sop.folder "Soft selection"];
    apply_rolloff : bool [@sop.default true] [@sop.label "Apply rolloff"]
      [@sop.folder "Soft selection"];
    falloff : Rdk.Transform_ops.soft_transform_falloff
      [@sop.default Rdk.Transform_ops.Soft_cubic] [@sop.label "Falloff"]
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
    | Radius -> Rdk.Transform_ops.Soft_radius
    | Edge -> Rdk.Transform_ops.Soft_edge
    | Attribute -> Rdk.Transform_ops.Soft_attribute {
        attribute = parameters.metric_attribute;
        apply_rolloff = parameters.apply_rolloff }
  let build = parameters_build (fun ~label parameters input ->
    Sop.soft_transform_trs ~label ~order:parameters.order
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
        ~recompute_normals:parameters.recompute_normals input)
  let factory = parameters_factory build
end

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
    | Total -> Rdk.Point_generate.Generate_total parameters.total
    | Per_point -> Rdk.Point_generate.Generate_per_point {
        points_per_point = parameters.points_per_point;
        scale_attribute = optional_text parameters.scale_attribute }
    | Probability -> Rdk.Point_generate.Generate_probability {
        attribute = parameters.probability_attribute }
  let build = parameters_build (fun ~label parameters input ->
    Sop.point_generate ~label
        ?group:(optional_text parameters.group) ~keep_input:parameters.keep_input
        ?seed:(if parameters.context_seed then None else Some parameters.seed)
        ?generated_group:(optional_text parameters.generated_group)
        ~source_point_attribute:parameters.source_point_attribute
        ~source_index_attribute:parameters.source_index_attribute
        ~copy_point_attributes:parameters.copy_point_attributes
        ~copy_detail_attributes:parameters.copy_detail_attributes
        ~mode:(mode parameters) input)
  let factory = parameters_factory build
end

module Point_replicate = struct
  let shape_parameter = Parameter.choice ~equal:( = ) [
      "Point", Rdk.Point_replication.Replicate_point; "Box", Rdk.Point_replication.Replicate_box;
      "Sphere", Rdk.Point_replication.Replicate_sphere; "Disk", Rdk.Point_replication.Replicate_disk;
      "Line", Rdk.Point_replication.Replicate_line; "Custom", Rdk.Point_replication.Replicate_custom;
    ]
  let velocity_parameter = Parameter.choice ~equal:( = ) [
      "None", Rdk.Point_replication.Replicate_no_velocity_stretch;
      "Scaled velocity", Rdk.Point_replication.Replicate_scaled_velocity;
      "Velocity only", Rdk.Point_replication.Replicate_velocity_only;
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
    shape : Rdk.Point_replication.shape [@sop.default Rdk.Point_replication.Replicate_sphere]
      [@sop.label "Shape"] [@sop.folder "Shape"] [@sop.kind shape_parameter];
    center_x : float [@sop.default 0.] [@sop.label "Center X"]
      [@sop.folder "Shape/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_y : float [@sop.default 0.] [@sop.label "Center Y"]
      [@sop.folder "Shape/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    center_z : float [@sop.default 0.] [@sop.label "Center Z"]
      [@sop.folder "Shape/Center"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "center"]
    size_x : float [@sop.default 1.] [@sop.label "Size X"]
      [@sop.folder "Shape/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "size"]
    size_y : float [@sop.default 1.] [@sop.label "Size Y"]
      [@sop.folder "Shape/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "size"]
    size_z : float [@sop.default 1.] [@sop.label "Size Z"]
      [@sop.folder "Shape/Size"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.]; [@sop.vec3 "size"]
    orientation_x : float [@sop.default 0.] [@sop.label "Rotate X"]
      [@sop.folder "Shape/Orientation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.vec3 "orientation"]
    orientation_y : float [@sop.default 0.] [@sop.label "Rotate Y"]
      [@sop.folder "Shape/Orientation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.vec3 "orientation"]
    orientation_z : float [@sop.default 0.] [@sop.label "Rotate Z"]
      [@sop.folder "Shape/Orientation"] [@sop.min (-3.141592653589793)]
      [@sop.max 3.141592653589793]; [@sop.vec3 "orientation"]
    uniform_scale : float [@sop.default 1.] [@sop.label "Uniform scale"]
      [@sop.folder "Shape"] [@sop.min 0.] [@sop.max 10.]
      [@sop.hard_min 0.];
    quasi_stratified : bool [@sop.default false]
      [@sop.label "Quasi-stratified"] [@sop.folder "Random"];
    velocity_stretch : Rdk.Point_replication.velocity_stretch
      [@sop.default Rdk.Point_replication.Replicate_no_velocity_stretch]
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
      [@sop.folder "Noise/Amplitude"] [@sop.min 0.] [@sop.max 10.]; [@sop.vec3 "noise_amplitude"]
    noise_amplitude_y : float [@sop.default 0.1] [@sop.label "Amplitude Y"]
      [@sop.folder "Noise/Amplitude"] [@sop.min 0.] [@sop.max 10.]; [@sop.vec3 "noise_amplitude"]
    noise_amplitude_z : float [@sop.default 0.1] [@sop.label "Amplitude Z"]
      [@sop.folder "Noise/Amplitude"] [@sop.min 0.] [@sop.max 10.]; [@sop.vec3 "noise_amplitude"]
    noise_frequency_x : float [@sop.default 1.] [@sop.label "Frequency X"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.]; [@sop.vec3 "noise_frequency"]
    noise_frequency_y : float [@sop.default 1.] [@sop.label "Frequency Y"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.]; [@sop.vec3 "noise_frequency"]
    noise_frequency_z : float [@sop.default 1.] [@sop.label "Frequency Z"]
      [@sop.folder "Noise/Frequency"] [@sop.min 0.] [@sop.max 20.]; [@sop.vec3 "noise_frequency"]
    noise_offset_x : float [@sop.default 0.] [@sop.label "Offset X"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "noise_offset"]
    noise_offset_y : float [@sop.default 0.] [@sop.label "Offset Y"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "noise_offset"]
    noise_offset_z : float [@sop.default 0.] [@sop.label "Offset Z"]
      [@sop.folder "Noise/Offset"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "noise_offset"]
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
    [@@sop.node_category "Create/Points"] [@@sop.node_inputs 2] [@@sop.node_slots "input, custom_shape"]
    [@@sop.node_optional "1"] [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input custom_shape ->
    let custom_shape = if parameters.shape = Rdk.Point_replication.Replicate_custom
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
      ?scale_attribute:(optional_text parameters.scale_attribute) input)

  let factory = parameters_factory build
end

module Null = struct
  let factory = Edit_graph.factory ~key:"null" ~label:"Null"
      ~category:["Utility"] ~arity:1 (function
        | [input] -> Sop.null input
        | _ -> invalid_arg "Null SOP expects one input")
end

(* Terminal Exploded View marker: cooking is a geometry passthrough, so a
   renderer with packed-piece support updates rigid per-piece transforms from
   these view-only parameters without recooking upstream topology. *)
module Exploded_view = struct
  type parameters = {
    amount : float [@sop.default 0.32] [@sop.label "Uniform scale"]
      [@sop.folder "Explosion"] [@sop.min (-0.95)] [@sop.max 8.]
      [@sop.impact "view"];
    scale_x : float [@sop.default 1.] [@sop.label "Scale X"]
      [@sop.folder "Explosion/Scale"] [@sop.min (-2.)] [@sop.max 2.]
      [@sop.impact "view"]; [@sop.vec3 "scale"]
    scale_y : float [@sop.default 1.] [@sop.label "Scale Y"]
      [@sop.folder "Explosion/Scale"] [@sop.min (-2.)] [@sop.max 2.]
      [@sop.impact "view"]; [@sop.vec3 "scale"]
    scale_z : float [@sop.default 1.] [@sop.label "Scale Z"]
      [@sop.folder "Explosion/Scale"] [@sop.min (-2.)] [@sop.max 2.]
      [@sop.impact "view"]; [@sop.vec3 "scale"]
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

  let build = parameters_build (fun ~label _parameters input ->
    operator ~label ~operation:"exploded_view" ~cook_mode:(Node.Passthrough 0)
      [|input|] (fun ~node_id:_ _context inputs -> cooked inputs.(0)))

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
end
