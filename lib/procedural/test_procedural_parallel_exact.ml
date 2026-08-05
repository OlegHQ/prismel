open Prismel
open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error message -> fail message
let get_pdk = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let with_detail name storage geometry =
  let attribute = Attribute.create_owned ~owner:Attribute.Detail ~name storage
      |> get_ok in
  Geometry.with_attribute attribute geometry |> get_ok

let equal_storage left right =
  match Attribute.storage left, Attribute.storage right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Text left, Attribute.Text right -> left = right
  | Attribute.Float2 left, Attribute.Float2 right ->
      let left = Packed.Float2.Private.view left
      and right = Packed.Float2.Private.view right in
      left.x = right.x && left.y = right.y
  | Attribute.Float3 left, Attribute.Float3 right ->
      let left = Packed.Float3.Private.view left
      and right = Packed.Float3.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
  | Attribute.Float4 left, Attribute.Float4 right ->
      let left = Packed.Float4.Private.view left
      and right = Packed.Float4.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
      && left.w = right.w
  | _ -> false

let equal_attribute left right =
  Attribute.owner left = Attribute.owner right
  && String.equal (Attribute.name left) (Attribute.name right)
  && String.equal (Attribute.kind_name left) (Attribute.kind_name right)
  && equal_storage left right

let equal_group left right =
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)
  && Group.length left = Group.length right
  && begin
    let equal = ref true in
    for index = 0 to Group.length left - 1 do
      if Group.mem index left <> Group.mem index right then equal := false
    done;
    !equal
  end
  && Group.ordered_elements left = Group.ordered_elements right

let equal_edge_group left right =
  String.equal (Edge_group.name left) (Edge_group.name right)
  && Edge_group.length left = Edge_group.length right
  && begin
    let equal = ref true in
    for edge = 0 to Edge_group.length left - 1 do
      if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
    done;
    !equal
  end

let equal_geometry left right =
  let left_positions = Packed.Float3.Private.view (Geometry.positions left)
  and right_positions = Packed.Float3.Private.view (Geometry.positions right)
  and left_topology = Topology.Private.view (Geometry.topology left)
  and right_topology = Topology.Private.view (Geometry.topology right) in
  left_positions.x = right_positions.x
  && left_positions.y = right_positions.y
  && left_positions.z = right_positions.z
  && left_topology.point_count = right_topology.point_count
  && left_topology.vertex_points = right_topology.vertex_points
  && left_topology.primitive_offsets = right_topology.primitive_offsets
  && Bytes.equal left_topology.primitive_kinds right_topology.primitive_kinds
  && List.equal equal_attribute (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group (Geometry.edge_groups left)
       (Geometry.edge_groups right)

let cook domains graph =
  let context = Context.create ~domains ~grain:97 ~seed:42L () |> get_ok in
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(256 * 1024 * 1024) |> get_ok in
  let result = match Session.cook session ~context graph with
    | Ok output -> output.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session;
  result

let inline_geometry polygons =
  let point_count = polygons * 6 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for primitive = 0 to polygons - 1 do
    let point = primitive * 6 and base = float_of_int primitive *. 4. in
    x.(point) <- base;
    x.(point + 1) <- base +. 1.;
    x.(point + 2) <- base +. 2.;
    x.(point + 3) <- base +. 3.;
    x.(point + 4) <- base +. 3.; z.(point + 4) <- 1.;
    x.(point + 5) <- base; z.(point + 5) <- 1.
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.polygons_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (polygons + 1)
        (fun primitive -> primitive * 6)) |> get_ok in
  Geometry.create ~positions ~topology () |> get_ok

let edge_flip_geometry pairs =
  let point_count = pairs * 4 and vertex_count = pairs * 6 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0.
  and vertex_points = Array.make vertex_count 0 in
  for pair = 0 to pairs - 1 do
    let point = pair * 4 and vertex = pair * 6 in
    let origin_x = float_of_int (pair mod 250) *. 2.
    and origin_y = float_of_int (pair / 250) *. 2. in
    x.(point) <- origin_x; y.(point) <- origin_y;
    x.(point + 1) <- origin_x +. 1.; y.(point + 1) <- origin_y;
    x.(point + 2) <- origin_x +. 1.; y.(point + 2) <- origin_y +. 1.;
    x.(point + 3) <- origin_x; y.(point + 3) <- origin_y +. 1.;
    vertex_points.(vertex) <- point;
    vertex_points.(vertex + 1) <- point + 1;
    vertex_points.(vertex + 2) <- point + 2;
    vertex_points.(vertex + 3) <- point;
    vertex_points.(vertex + 4) <- point + 2;
    vertex_points.(vertex + 5) <- point + 3
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.polygons_owned ~point_count ~vertex_points
      ~primitive_offsets:(Array.init (pairs * 2 + 1) (fun face -> face * 3))
      |> get_ok in
  let index = Topology_index.create topology in
  let flip = Edge_group.init ~grain:97 ~topology ~index ~name:"flip_edges"
      (fun edge ->
        let a, b = Topology_index.edge_points index edge in
        abs (a - b) = 2 && min a b mod 4 = 0) in
  Geometry.create ~positions ~topology ~edge_groups:[flip] () |> get_ok

let edge_equalize_geometry edge_count =
  let point_count = edge_count * 2 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for edge = 0 to edge_count - 1 do
    let point = edge * 2 and base = float_of_int edge *. 3.
    and length = 0.5 +. float_of_int (edge mod 17) *. 0.1 in
    x.(point) <- base;
    x.(point + 1) <- base +. length
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (edge_count + 1) (fun edge -> edge * 2))
      ~primitive_kinds:(Array.make edge_count Topology.Open_polyline) |> get_ok in
  Geometry.create ~positions ~topology () |> get_ok

let edge_relax_reference geometry =
  let source = Packed.Float3.Private.view (Geometry.positions geometry) in
  let x = Array.copy source.x in
  for edge = 0 to Geometry.point_count geometry / 2 - 1 do
    let point = edge * 2 in
    x.(point + 1) <- x.(point) +. 0.8 +. float_of_int (edge mod 11) *. 0.1
  done;
  Geometry.with_positions
    (Packed.Float3.Private.of_shared_exn ~x ~y:source.y ~z:source.z)
    geometry |> get_ok

let curve_chain_geometry segments =
  let point_count = segments + 1 in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point -> float_of_int point *. 0.002))
      ~y:(Array.init point_count (fun point ->
        sin (float_of_int point *. 0.017)))
      ~z:(Array.init point_count (fun point ->
        cos (float_of_int point *. 0.011) *. 0.25)) in
  let vertex_points = Array.init (segments * 2) (fun vertex ->
      let primitive = vertex / 2 in primitive + (vertex land 1)) in
  let topology = Topology.create_owned ~point_count ~vertex_points
      ~primitive_offsets:(Array.init (segments + 1) (fun primitive -> primitive * 2))
      ~primitive_kinds:(Array.make segments Topology.Open_polyline) |> get_ok in
  let point_sample = Attribute.create_owned ~owner:Attribute.Point
      ~name:"curve_sample"
      (Attribute.Float (Array.init point_count (fun point ->
        let value = float_of_int (point mod 257) in value *. value))) |> get_ok
  and vertex_sample = Attribute.create_owned ~owner:Attribute.Vertex
      ~name:"curve_u"
      (Attribute.Float (Array.init (segments * 2) (fun vertex ->
        float_of_int (vertex land 1)))) |> get_ok
  and primitive_sample = Attribute.create_owned ~owner:Attribute.Primitive
      ~name:"curve_id" (Attribute.Int (Array.init segments Fun.id)) |> get_ok in
  Geometry.create ~positions ~topology
    ~attributes:[point_sample; vertex_sample; primitive_sample] () |> get_ok

let () =
  let generated_line = Sop.line ~points:500_001
      ~origin:(Vec3.create (-10.) 2. 3.)
      ~direction:(Vec3.create 1. 2. 3.) ~length:25. () in
  let one = cook 1 generated_line and many = cook 4 generated_line in
  check (equal_geometry one many)
    "one-domain and four-domain Line geometry differ";
  check (Geometry.point_count one = 500_001
      && Geometry.vertex_count one = 500_001)
    "Line exactness fixture cardinality";
  let generated_resample = Sop.polyline (Array.init 5_001 (fun point ->
      let t = float_of_int point *. 0.003 in
      t, sin (t *. 0.7), cos (t *. 0.43) *. 0.6))
      |> Sop.resample ~maximum_segment_length:0.0009
           ~curve_u_attribute:"curveu" ~curve_number_attribute:"curvenum"
           ~distance_attribute:"distance" ~tangent_attribute:"tangent" in
  let one = cook 1 generated_resample and many = cook 4 generated_resample in
  check (equal_geometry one many)
    "one-domain and four-domain advanced Resample geometry differ";
  check (Geometry.point_count one > 5_001
      && Geometry.find_attribute ~owner:Attribute.Point "tangent" one <> None)
    "advanced Resample exactness fixture cardinality";
  let generated_polyframe = Sop.grid ~columns:401 ~rows:301
      ~uv_attribute:"uv" ~size:20. ()
      |> Sop.polyframe ~orthogonal:true
           (Ops.Attribute_gradient "uv") in
  let one = cook 1 generated_polyframe and many = cook 4 generated_polyframe in
  check (equal_geometry one many)
    "one-domain and four-domain PolyFrame geometry differ";
  check (Geometry.find_attribute ~owner:Attribute.Vertex "N" one <> None
      && Geometry.find_attribute ~owner:Attribute.Vertex "tangentu" one <> None
      && Geometry.find_attribute ~owner:Attribute.Vertex "tangentv" one <> None)
    "PolyFrame exactness fixture attributes";
  let generated_facet = Sop.grid ~columns:401 ~rows:301
      ~uv_attribute:"uv" ~size:20. ()
      |> Sop.facet ~pre_compute_normals:true ~make_normals_unit_length:true
           ~unique_points:true ~consolidate_normals_distance:0.
           ~reverse_normals:true in
  let one = cook 1 generated_facet and many = cook 4 generated_facet in
  check (equal_geometry one many)
    "one-domain and four-domain Facet geometry differ";
  check (Geometry.point_count one = Geometry.vertex_count one
      && Geometry.find_attribute ~owner:Attribute.Point "uv" one <> None)
    "Facet exactness fixture cardinality";
  let generated_grouped_facet = Sop.grid ~columns:401 ~rows:301
      ~uv_attribute:"uv" ~size:20. ()
      |> Sop.group ~name:"facet_even"
           (Select.primitive_indices
             (Array.init (400 * 300) (fun primitive -> primitive * 2)))
      |> Sop.facet ~group:"facet_even" ~pre_compute_normals:true
           ~unique_points:true ~reverse_normals:true in
  let one = cook 1 generated_grouped_facet
  and many = cook 4 generated_grouped_facet in
  check (equal_geometry one many)
    "one-domain and four-domain grouped Facet geometry differ";
  let generated_inline_facet = Sop.snapshot (inline_geometry 40_000)
      |> Sop.facet ~remove_inline_points:true in
  let one = cook 1 generated_inline_facet
  and many = cook 4 generated_inline_facet in
  check (equal_geometry one many)
    "one-domain and four-domain Facet inline removal differ";
  check (Geometry.point_count one = 160_000
      && Geometry.vertex_count one = 160_000)
    "Facet inline exactness fixture cardinality";
  let generated_grid = Sop.grid ~counts:Ops.Grid_point_counts
      ~connectivity:Ops.Grid_alternating_triangles
      ~orientation:(Ops.Grid_axes {
        horizontal = Vec3.create 1. 2. 0.5;
        vertical = Vec3.create (-0.25) 0.75 2. })
      ~center:(Vec3.create 3. (-2.) 5.) ~width:40. ~height:25.
      ~rotation:0.37 ~uv_attribute:"uv" ~columns:701 ~rows:501 ~size:1. () in
  let one = cook 1 generated_grid and many = cook 4 generated_grid in
  check (equal_geometry one many)
    "one-domain and four-domain advanced Grid geometry differ";
  check (Geometry.point_count one = 351_201
      && Geometry.primitive_count one = 700_000)
    "advanced Grid exactness fixture cardinality";
  let generated_circle = Sop.circle
      ~arc:(Ops.Circle_sliced_arc {
        start_angle = -0.7; end_angle = 5.2 })
      ~orientation:(Ops.Circle_axes {
        horizontal = Vec3.create 1. 2. 0.5;
        vertical = Vec3.create (-0.25) 0.75 2. })
      ~reverse:true ~center:(Vec3.create 3. (-2.) 5.)
      ~radius_x:40. ~radius_y:25. ~rotation:0.37 ~uniform_scale:1.2
      ~segments:500_000 ~radius:1. () in
  let one = cook 1 generated_circle and many = cook 4 generated_circle in
  check (equal_geometry one many)
    "one-domain and four-domain advanced Circle geometry differ";
  check (Geometry.point_count one = 500_002
      && Topology.primitive_kind (Geometry.topology one) 0
         = Topology.Closed_polyline)
    "advanced Circle exactness fixture cardinality";
  let generated_box = Sop.box ~connectivity:Ops.Box_quads
      ~consolidate_points:true ~normals:Ops.Box_vertex_normals
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7) ~rotation_order:Ops.Box_zxy
      ~uniform_scale:1.2 ~x_divisions:256 ~y_divisions:192 ~z_divisions:128
      ~uv_attribute:"uv" ~face_groups:"face"
      ~size:(Vec3.create 40. 25. 18.) () in
  let one = cook 1 generated_box and many = cook 4 generated_box in
  check (equal_geometry one many)
    "one-domain and four-domain advanced Box geometry differ";
  check (Geometry.point_count one = 212_994
      && Geometry.primitive_count one = 212_992
      && List.length (Geometry.groups one) = 6)
    "advanced Box exactness fixture cardinality";
  let generated_sphere = Sop.uv_sphere
      ~connectivity:Ops.Sphere_alternating_triangles
      ~unique_points_per_pole:true ~normals:Ops.Sphere_vertex_normals
      ~orientation:(Ops.Sphere_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7) ~rotation_order:Ops.Sphere_yzx
      ~radius_x:3. ~radius_y:2. ~radius_z:1. ~uv_attribute:"uv"
      ~segments:256 ~rings:128 ~radius:1. () in
  let one = cook 1 generated_sphere and many = cook 4 generated_sphere in
  check (equal_geometry one many)
    "one-domain and four-domain advanced UV Sphere geometry differ";
  check (Geometry.point_count one = 33_024
      && Geometry.vertex_count one = 195_072
      && Geometry.primitive_count one = 65_024)
    "advanced UV Sphere exactness fixture cardinality";
  let generated_torus = Sop.torus
      ~connectivity:Ops.Torus_alternating_triangles
      ~normals:Ops.Torus_vertex_normals ~uv_attribute:"uv"
      ~orientation:(Ops.Torus_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7) ~rotation_order:Ops.Torus_yzx
      ~u_start:(-0.7) ~u_end:4.8 ~v_start:(-1.2) ~v_end:2.1
      ~u_wrap:false ~v_wrap:false ~u_end_caps:true ~v_end_cap:true
      ~rows:256 ~columns:128 ~major_radius:3. ~minor_radius:1. () in
  let one = cook 1 generated_torus and many = cook 4 generated_torus in
  check (equal_geometry one many)
    "one-domain and four-domain advanced Torus geometry differ";
  check (Geometry.point_count one = 32_768
      && Geometry.vertex_count one = 196_096
      && Geometry.primitive_count one = 65_282)
    "advanced Torus exactness fixture cardinality";
  let generated_tube = Sop.tube
      ~connectivity:Ops.Tube_alternating_triangles ~end_caps:true
      ~consolidate_cap_points:false ~normals:Ops.Tube_vertex_normals
      ~orientation:(Ops.Tube_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7) ~rotation_order:Ops.Tube_yzx
      ~radius_scale:1.2 ~uv_attribute:"uv" ~cap_group:"caps"
      ~rows:256 ~columns:128 ~top_radius:0. ~bottom_radius:3. ~height:5. () in
  let one = cook 1 generated_tube and many = cook 4 generated_tube in
  check (equal_geometry one many)
    "one-domain and four-domain advanced Tube geometry differ";
  check (Geometry.point_count one = 32_769
      && Geometry.vertex_count one = 195_584
      && Geometry.primitive_count one = 65_153)
    "advanced Tube exactness fixture cardinality";
  let generated_platonic = Sop.platonic
      ~kind:Ops.Platonic_soccer_ball ~normals:Ops.Platonic_vertex_normals
      ~orientation:(Ops.Platonic_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7)
      ~rotation_order:Ops.Platonic_yzx ~face_groups:"face" ~radius:4. () in
  let one = cook 1 generated_platonic and many = cook 4 generated_platonic in
  check (equal_geometry one many)
    "one-domain and four-domain advanced Platonic geometry differ";
  check (Geometry.point_count one = 60 && Geometry.vertex_count one = 180
      && Geometry.primitive_count one = 32)
    "advanced Platonic exactness fixture cardinality";
  let generated_spiral = Sop.spiral
      ~extent:(Ops.Spiral_height_pitch { height = -18.; pitch = -0.37 })
      ~radius:(Ops.Spiral_logarithmic_end {
        start_radius = 0.35; end_radius = 8. })
      ~height_ramp:[0., 0.8; 0.35, 1.2; 0.7, 0.55; 1., 1.]
      ~radius_scale:1.3 ~radius_ramp:[0., 1.; 0.4, 0.6; 1., 1.15]
      ~direction:Ops.Spiral_clockwise ~start_angle:(-0.7)
      ~divisions:(Ops.Spiral_divisions_per_curve 20_000)
      ~uniform_angle:false ~spiral_count:5
      ~orientation:(Ops.Spiral_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7)
      ~rotation_order:Ops.Spiral_yzx ~uniform_scale:1.2
      ~angle_attribute:"angle" ~x_axis_attribute:"xaxis"
      ~y_axis_attribute:"yaxis" ~tangent_attribute:"tangent"
      ~orient_attribute:"orient" ~distance_attribute:"distance" () in
  let one = cook 1 generated_spiral and many = cook 4 generated_spiral in
  check (equal_geometry one many)
    "one-domain and four-domain advanced Spiral geometry differ";
  check (Geometry.point_count one = 100_005
      && Geometry.vertex_count one = 100_005
      && Geometry.primitive_count one = 5)
    "advanced Spiral exactness fixture cardinality";
  let matrix = Mat4.mul (Mat4.translation (Vec3.create 2. 3. 4.))
      (Mat4.mul (Mat4.rotation ~axis:(Vec3.create 1. 2. 3.) 0.7)
         (Mat4.scaling (Vec3.create 1.25 0.75 1.5))) in
  let graph =
    Sop.grid ~columns:320 ~rows:256 ~size:20. ()
    |> Sop.transform matrix
    |> Sop.color_by_height ~low:(Color.rgb 45 36 114)
         ~high:(Color.rgb 244 124 42)
    |> Sop.group ~name:"middle"
         (Select.points_in_bounds ~min:(Vec3.create (-5.) (-100.) (-5.))
            ~max:(Vec3.create 5. 100. 5.))
    |> Sop.group_edge_depth ~depth:2 ~point_group:"middle"
         ~name:"middle_grown"
    |> Sop.group_unshared ~owner:Ops.Group_points ~name:"surface_boundary"
    |> Sop.group_boundary_components ~prefix:"boundary_loop"
    |> Sop.group ~name:"all_faces" Select.all_primitives
    |> Sop.group_range ~owner:Ops.Group_primitives ~name:"connected_faces"
         ~connectivity:(Ops.Range_connected {
           connectivity_attributes = None;
           connectivity_tolerance = 1e-6;
           collision = Some {
             Ops.collision_owner = Ops.Group_points;
             collision_pattern = "middle";
             keep_boundary = true };
           region = None;
           remove_other_regions = true })
         ~filter:{ select = 3; of_ = 11; offset = 2 }
         (Ops.Range_start_end { start = 7; end_ = 40_000 })
    |> Sop.group_promote_boundary ~keep_original:true
         ~include_unshared_edges:true ~name:"connected_outline"
         ~source:Ops.Group_primitives ~destination:Ops.Group_edges
         ~group:"connected_faces"
    |> Sop.group_edges ~name:"surface_edges"
         ~angle_basis:Ops.Incident_edges ~min_angle:0.1 ~max_angle:2.9
    |> Sop.group_unshared ~owner:Ops.Group_edges ~name:"unshared_edges"
  in
  let one = cook 1 graph and many = cook 4 graph in
  check (equal_geometry one many)
    "one-domain and four-domain procedural geometry differ";
  check (Geometry.find_attribute ~owner:Attribute.Point "N" one <> None)
    "normal attribute missing from exactness fixture";
  check (Geometry.find_attribute ~owner:Attribute.Point "Cd" one <> None)
    "color attribute missing from exactness fixture";
  check (List.map Group.name (Geometry.groups one)
      = ["middle"; "middle_grown"; "surface_boundary"; "boundary_loop__0";
         "all_faces"; "connected_faces"])
    "group ordering changed";
  let lifecycle_reference = Sop.grid ~columns:8 ~rows:4 ~size:2. ()
      |> Sop.set_float ~owner:Attribute.Point ~name:"reference_keep" 1.
      |> Sop.set_float ~owner:Attribute.Point ~name:"reference_drop" 2. in
  let lifecycle = Sop.grid ~columns:8 ~rows:4 ~size:2. ()
      |> Sop.set_float ~owner:Attribute.Point ~name:"reference_keep" 1.
      |> Sop.set_float ~owner:Attribute.Point ~name:"reference_drop" 2.
      |> Sop.set_float ~owner:Attribute.Point ~name:"temporary_point" 3.
      |> Sop.set_float ~owner:Attribute.Vertex ~name:"temporary_vertex" 4.
      |> Sop.set_float ~owner:Attribute.Primitive ~name:"temporary_primitive" 5.
      |> Sop.set_int ~owner:Attribute.Detail ~name:"temporary_detail" 6
      |> Sop.delete_attributes ~reference:lifecycle_reference
           ~point_pattern:"^reference_keep"
      |> Sop.rename_attributes ~rules:[{
          Attribute_ops.rename_attribute_owner = None;
          rename_attribute_pattern = "temporary_*";
          rename_attribute_replacement = "final_*";
          rename_attribute_conflict = Attribute_ops.Attribute_rename_error;
        }]
      |> Sop.swap_attributes ~rules:[
          { Attribute_ops.swap_attribute_owner = Attribute.Point;
            swap_attribute_source = "final_point";
            swap_attribute_destination = "reference_keep";
            swap_attribute_method = Attribute_ops.Attribute_swap };
          { swap_attribute_owner = Attribute.Point;
            swap_attribute_source = "P";
            swap_attribute_destination = "rest";
            swap_attribute_method = Attribute_ops.Attribute_copy };
          { swap_attribute_owner = Attribute.Detail;
            swap_attribute_source = "final_detail";
            swap_attribute_destination = "stored_detail";
            swap_attribute_method = Attribute_ops.Attribute_move }]
  in
  let one = cook 1 lifecycle and many = cook 4 lifecycle in
  check (equal_geometry one many)
    "one-domain and four-domain Attribute Delete/Rename/Swap geometry differ";
  check (Geometry.find_attribute ~owner:Attribute.Point "reference_keep" one
      <> None
      && Geometry.find_attribute ~owner:Attribute.Point "reference_drop" one
         = None
      && Geometry.find_attribute ~owner:Attribute.Point "final_point" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Vertex "final_vertex" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Primitive "final_primitive" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Detail "final_detail" one
         = None
      && Geometry.find_attribute ~owner:Attribute.Detail "stored_detail" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Point "rest" one
         <> None)
    "Attribute Delete/Rename/Swap exactness fixture outputs";
  let blurred = Sop.grid ~columns:240 ~rows:160 ~size:14. ()
      |> Sop.noise_displace ~seed:311 ~amplitude:0.9 ~frequency:0.45
      |> Sop.color_by_height ~low:(Color.hex_exn "#1d4ed8")
           ~high:(Color.hex_exn "#f97316")
      |> Sop.set_float ~owner:Attribute.Point ~name:"blur_weight" 0.8
      |> Sop.set_float ~owner:Attribute.Point ~name:"blur_alpha" 0.9
      |> Sop.group ~name:"blur_points" Select.all_points
      |> Sop.attribute_blur ~group:"blur_points" ~iterations:6
           ~method_:Attribute_ops.Edge_length
           ~mode:(Attribute_ops.Custom_steps { odd = 0.42; even = -0.44 })
           ~weight_attribute:"blur_weight" ~alpha_attribute:"blur_alpha"
           ~pin_borders:true ~attributes:"P Cd" in
  let one = cook 1 blurred and many = cook 4 blurred in
  check (equal_geometry one many)
    "one-domain and four-domain Attribute Blur geometry differ";
  check (Geometry.find_attribute ~owner:Attribute.Point "Cd" one <> None)
    "Attribute Blur exactness fixture dropped color";
  let smoothed = Sop.grid ~columns:300 ~rows:220 ~size:18. ()
      |> Sop.noise_displace ~seed:313 ~amplitude:1.1 ~frequency:0.52
      |> Sop.color_by_height ~low:(Color.hex_exn "#0e7490")
           ~high:(Color.hex_exn "#facc15")
      |> Sop.set_float ~owner:Attribute.Point ~name:"smooth_weight" 0.82
      |> Sop.group_random ~seed:317 ~probability:0.72
           ~owner:Ops.Group_primitives ~name:"smooth_faces"
      |> Sop.group_unshared ~owner:Ops.Group_points ~name:"smooth_locks"
      |> Sop.smooth ~group:"smooth_faces" ~constrained_points:"smooth_locks"
           ~boundary:Ops.Smooth_group_boundary ~iterations:8
           ~method_:Attribute_ops.Edge_length
           ~mode:(Attribute_ops.Custom_steps { odd = 0.43; even = -0.45 })
           ~weight_attribute:"smooth_weight" ~attributes:"P Cd" in
  let one = cook 1 smoothed and many = cook 4 smoothed in
  check (equal_geometry one many)
    "one-domain and four-domain Smooth geometry differ";
  check (Geometry.find_attribute ~owner:Attribute.Point "Cd" one <> None
      && Geometry.point_count one = 301 * 221)
    "Smooth exactness fixture changed payload/cardinality";
  let ray_collision = Sop.grid ~columns:320 ~rows:240 ~size:20. ()
      |> Sop.noise_displace ~seed:319 ~amplitude:0.9 ~frequency:0.37
      |> Sop.color_by_height ~low:(Color.hex_exn "#06b6d4")
           ~high:(Color.hex_exn "#f43f5e") in
  let projected = Sop.grid ~columns:320 ~rows:240 ~size:20. ()
      |> Sop.transform (Mat4.translation (Vec3.create 0. 3. 0.))
      |> Sop.ray ~collision:ray_collision
           ~direction:(Ops.Ray_vector (Vec3.neg Vec3.unit_y))
           ~tolerance:1e-9 ~distance_attribute:"ray_distance"
           ~primitive_attribute:"source_primitive"
           ~source_vertex_numbers_attribute:"source_vertices"
           ~source_vertex_weights_attribute:"source_weights"
           ~normal_attribute:"hit_N" ~point_pattern:"Cd" in
  let one = cook 1 projected and many = cook 4 projected in
  check (equal_geometry one many)
    "one-domain and four-domain Ray geometry differ";
  check (Geometry.point_count one = 321 * 241
      && Geometry.find_attribute ~owner:Attribute.Point "Cd" one <> None)
    "Ray exactness fixture changed payload/cardinality";
  let grid_snapped = Sop.grid ~columns:500 ~rows:300 ~size:20. ()
      |> Sop.noise_displace ~seed:321 ~amplitude:0.37 ~frequency:0.29
      |> Sop.snap_to_grid ~spacing:(Vec3.create 0.03125 0.03125 0.03125)
           ~offset:(Vec3.create 0.25 0.5 0.75) ~snapped_group:"snapped" in
  let one = cook 1 grid_snapped and many = cook 4 grid_snapped in
  check (equal_geometry one many)
    "one-domain and four-domain procedural grid snap differ";
  check (Geometry.find_group ~owner:Group.Point "snapped" one <> None)
    "procedural grid snap exactness fixture dropped output group";
  let bounded = Sop.grid ~columns:500 ~rows:300 ~size:30. ()
      |> Sop.noise_displace ~seed:323 ~amplitude:2. ~frequency:0.23
      |> Sop.bound ~shape:(Ops.Bound_box { divisions = 256, 128, 64 })
           ~lower_padding:(Vec3.create 0.25 0.5 0.75)
           ~upper_padding:(Vec3.create 0.75 0.5 0.25)
           ~bounds_group:"bounds" ~center_attribute:"bound_center"
           ~radii_attribute:"bound_radii" in
  let one = cook 1 bounded and many = cook 4 bounded in
  check (equal_geometry one many)
    "one-domain and four-domain procedural Bound geometry differ";
  check (Geometry.point_count one = 116_486
      && Geometry.primitive_count one = 229_376)
    "procedural Bound exactness cardinality";
  let expanded_groups = Sop.grid ~columns:400 ~rows:300 ~size:20. ()
      |> Sop.group ~name:"seed"
           (Select.points_in_bounds ~min:(Vec3.create (-0.03) (-1.) (-20.))
              ~max:(Vec3.create 0.03 1. 20.))
      |> Sop.group_expand ~steps:24 ~step_attribute:"grow_step"
           ~owner:Ops.Group_points ~group:"seed"
      |> Sop.group_promotions [
           Ops.group_promote_rule ~new_name:"grown_faces" ~keep_original:true
             ~mode:Ops.Include_shared_edge ~source:Ops.Group_points
             ~destination:Ops.Group_primitives ~pattern:"seed" ();
           Ops.group_promote_rule ~new_name:"grown_edges" ~keep_original:true
             ~mode:Ops.Include_all ~source:Ops.Group_points
             ~destination:Ops.Group_edges ~pattern:"seed" ()]
      |> Sop.group_expand ~steps:3 ~owner:Ops.Group_edges ~group:"grown_edges" in
  let one = cook 1 expanded_groups and many = cook 4 expanded_groups in
  check (equal_geometry one many)
    "one-domain and four-domain Group Expand/Promote geometry differ";
  check (Geometry.find_group ~owner:Group.Primitive "grown_faces" one <> None
      && Geometry.find_edge_group "grown_edges" one <> None)
    "Group Expand/Promote exactness fixture dropped outputs";
  let constrained_source = Ops.grid ~columns:400 ~rows:300 ~size:20. ()
      |> get_pdk in
  let constrained_primitive_count = Geometry.primitive_count constrained_source in
  let region_attribute = Attribute.create_owned ~owner:Attribute.Primitive
      ~name:"region" (Attribute.Int (Array.init constrained_primitive_count
        (fun primitive -> if primitive < (3 * constrained_primitive_count / 4)
          then 0 else 1))) |> get_ok in
  let flow_attribute = Attribute.create_owned ~owner:Attribute.Primitive
      ~name:"flow" (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.make constrained_primitive_count 0.)
        ~y:(Array.make constrained_primitive_count 0.)
        ~z:(Array.make constrained_primitive_count 1.))) |> get_ok in
  let constrained_source = constrained_source
      |> Geometry.with_attribute region_attribute |> get_ok
      |> Geometry.with_attribute flow_attribute |> get_ok in
  let seed = Group.init ~grain:97 ~owner:Group.Primitive ~name:"seed"
      constrained_primitive_count (fun primitive -> primitive = 0)
  and containment = Group.init ~grain:97 ~owner:Group.Primitive
      ~name:"containment" constrained_primitive_count
      (fun primitive -> primitive < constrained_primitive_count / 2) in
  let constrained_source = constrained_source
      |> Geometry.with_group seed |> get_ok
      |> Geometry.with_group containment |> get_ok in
  let constrained_expand = Sop.snapshot constrained_source
      |> Sop.group_expand ~flood:true ~step_attribute:"constraint_step"
           ~primitive_connectivity:Ops.Primitive_share_edges
           ~normal_spread:0.1
           ~normal_attribute:{ Ops.expand_normal_owner = Attribute.Primitive;
             expand_normal_name = "flow" }
           ~connectivity_attributes:[{
             Ops.boundary_attribute_owner = Attribute.Primitive;
             boundary_attribute_pattern = "region" }]
           ~collision:{ Ops.expand_collision_owner = Ops.Group_primitives;
             expand_collision_group = "containment";
             expand_collision_contain = true;
             expand_collision_allow_boundary = true }
           ~owner:Ops.Group_primitives ~group:"seed" in
  let one = cook 1 constrained_expand and many = cook 4 constrained_expand in
  check (equal_geometry one many)
    "one-domain and four-domain constrained Group Expand geometry differ";
  let constrained_group = Geometry.find_group ~owner:Group.Primitive "seed" one
      |> Option.get in
  check (Group.cardinality constrained_group > 0
      && Group.cardinality constrained_group < constrained_primitive_count
      && Geometry.find_attribute ~owner:Attribute.Primitive "constraint_step" one
         <> None)
    "constrained Group Expand exactness fixture ignored constraints";
  let instances = Sop.copy_to_points
      ~source:(Sop.box () |> Sop.group_edges ~name:"instance_edges")
      ~targets:(Sop.grid ~columns:80 ~rows:60 ~size:12. ()
        |> Sop.noise_displace ~seed:17 ~amplitude:0.8 ~frequency:0.3) () in
  let one = cook 1 instances and many = cook 4 instances in
  check (equal_geometry one many)
    "one-domain and four-domain copy-to-points geometry differ";
  check (Geometry.point_count one = 81 * 61 * 24)
    "copy-to-points exactness fixture cardinality";
  let mirrored = Sop.box ()
      |> Sop.group_edges ~name:"box_edges"
      |> Sop.fuse ~tolerance:1e-9 ~attributes:Pdk.Ops.Average_numeric
      |> Sop.mirror ~origin:Vec3.zero ~normal:(Vec3.create 1. 1. 0.) in
  let one = cook 1 mirrored and many = cook 4 mirrored in
  check (equal_geometry one many)
    "one-domain and four-domain fuse/mirror geometry differ";
  let clipped = Sop.uv_sphere ~segments:96 ~rings:64 ~radius:2. ()
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.group_edges ~name:"sphere_edges"
      |> Sop.clip ~keep:Ops.All ~fill:true ~split_connectivity:true
           ~selection:(Sop.Edge_group "sphere_edges")
           ~distance:0.075 ~clipped_edge_group:"clip_edges"
           ~cap_group:"caps" ~above_group:"above" ~below_group:"below"
           ~origin:(Vec3.create 0. 0.15 0.)
           ~normal:(Vec3.create 0.3 1. 0.2) in
  let one = cook 1 clipped and many = cook 4 clipped in
  check (equal_geometry one many)
    "one-domain and four-domain filled clip geometry differ";
  (match Geometry.find_group ~owner:Group.Primitive "caps" one with
   | Some group -> check (Group.cardinality group = 2)
       "filled keep-all clip cap count"
   | None -> fail "filled keep-all clip cap group missing");
  (match Geometry.find_edge_group "clip_edges" one with
   | Some group -> check (Edge_group.cardinality group > 0)
       "filled keep-all clip edge count"
   | None -> fail "filled keep-all clip edge group missing");
  let subdivided = Sop.box ~size:(Vec3.create 2. 1.5 1.) ()
      |> Sop.fuse ~tolerance:0. ~attributes:Ops.Average_numeric
      |> Sop.set_color ~owner:Attribute.Point (Color.hex_exn "#38bdf8")
      |> Sop.group_edges ~name:"subdivision_edges"
      |> Sop.subdivide ~scheme:Ops.Catmull_clark ~iterations:3
      |> Sop.normals in
  let one = cook 1 subdivided and many = cook 4 subdivided in
  check (equal_geometry one many)
    "one-domain and four-domain Catmull-Clark geometry differ";
  check (Geometry.primitive_count one = 576)
    (Printf.sprintf "Catmull-Clark procedural fixture cardinality: %d"
      (Geometry.primitive_count one));
  let creased_subdivision = Sop.grid ~columns:120 ~rows:80 ~size:8. ()
      |> Sop.set_float ~owner:Attribute.Vertex ~name:"creaseweight" 1.5
      |> Sop.subdivide ~scheme:Ops.Catmull_clark in
  let one = cook 1 creased_subdivision and many = cook 4 creased_subdivision in
  check (equal_geometry one many)
    "one-domain and four-domain semi-sharp subdivision differ";
  check (Geometry.find_attribute ~owner:Attribute.Vertex "creaseweight" one
    <> None) "semi-sharp subdivision did not emit residual creases";
  let chaikin_subdivision = Sop.grid ~columns:120 ~rows:80 ~size:8. ()
      |> Sop.attribute_randomize ~seed:8_191 ~owner:Attribute.Vertex
           ~name:"creaseweight" (Attribute_ops.Random_uniform {
             min = Attribute_ops.Scalar 0.;
             max = Attribute_ops.Scalar 4.;
           })
      |> Sop.subdivide ~scheme:Ops.Catmull_clark ~iterations:2
           ~creasing_method:Ops.Subdivide_creasing_chaikin
           ~resulting_crease_group:"chaikin_creases" in
  let one = cook 1 chaikin_subdivision and many = cook 4 chaikin_subdivision in
  check (equal_geometry one many)
    "one-domain and four-domain Chaikin subdivision differ";
  check (match Geometry.find_edge_group "chaikin_creases" one with
    | Some group -> Edge_group.cardinality group > 0 | None -> false)
    "parallel Chaikin subdivision omitted its resulting crease group";
  let all_edge_source = Ops.grid ~connectivity:Ops.Grid_quads
      ~columns:120 ~rows:80 ~size:8. () |> get_pdk in
  let all_edge_source_count = Array.length
      ((Topology_index.create (Geometry.topology all_edge_source)
        |> Topology_index.Private.view).edge_a) in
  let all_edge_subdivision = Sop.snapshot all_edge_source
      |> Sop.subdivide ~scheme:Ops.Catmull_clark ~iterations:2
           ~crease_weight:3. ~resulting_crease_group:"all_edge_creases" in
  let one = cook 1 all_edge_subdivision and many = cook 4 all_edge_subdivision in
  check (equal_geometry one many)
    "one-domain and four-domain all-edge crease override differ";
  check (match Geometry.find_edge_group "all_edge_creases" one with
    | Some group -> Edge_group.cardinality group = all_edge_source_count * 4
    | None -> false)
    "parallel all-edge crease override omitted source-edge descendants";
  let dense_curve_source = curve_chain_geometry 50_000 in
  let shared_curves = Sop.snapshot dense_curve_source
      |> Sop.subdivide ~scheme:Ops.Catmull_clark ~iterations:2 in
  let one = cook 1 shared_curves and many = cook 4 shared_curves in
  check (equal_geometry one many)
    "one-domain and four-domain shared polygon-curve subdivision differ";
  check (Geometry.point_count one = 200_001
      && Geometry.vertex_count one = 250_000)
    "parallel shared polygon-curve subdivision cardinality";
  let independent_curves = Sop.snapshot dense_curve_source
      |> Sop.subdivide ~scheme:Ops.Catmull_clark ~iterations:2
           ~treat_curves_as_independent:true in
  let one = cook 1 independent_curves and many = cook 4 independent_curves in
  check (equal_geometry one many)
    "one-domain and four-domain independent polygon-curve subdivision differ";
  check (Geometry.point_count one = 250_000
      && Geometry.vertex_count one = 250_000)
    "parallel independent polygon-curve subdivision cardinality";
  let crease_topology = Sop.grid ~columns:120 ~rows:80 ~size:8. ()
      |> Sop.set_float ~owner:Attribute.Vertex ~name:"creaseweight" 2.5 in
  let second_input_subdivision = Sop.grid ~columns:120 ~rows:80 ~size:8. ()
      |> Sop.subdivide ~creases:crease_topology
           ~resulting_crease_group:"dense_creases" in
  let one = cook 1 second_input_subdivision
  and many = cook 4 second_input_subdivision in
  check (equal_geometry one many)
    "one-domain and four-domain second-input subdivision differ";
  check (match Geometry.find_edge_group "dense_creases" one with
    | Some group -> Edge_group.cardinality group > 0 | None -> false)
    "parallel second-input subdivision omitted its resulting crease group";
  let hole_indices = Array.init ((120 * 80 + 6) / 7) (fun index -> index * 7)
      |> Array.to_list
      |> List.filter (fun primitive -> primitive < 120 * 80)
      |> Array.of_list in
  let holed_subdivision = Sop.grid ~connectivity:Ops.Grid_quads
      ~columns:120 ~rows:80 ~size:8. ()
      |> Sop.group ~name:"subdivision_hole"
           (Select.primitive_indices hole_indices)
      |> Sop.subdivide ~scheme:Ops.Catmull_clark ~iterations:2 in
  let one = cook 1 holed_subdivision and many = cook 4 holed_subdivision in
  check (equal_geometry one many)
    "one-domain and four-domain recursive hole subdivision differ";
  check (Geometry.primitive_count one = (120 * 80 - Array.length hole_indices) * 16)
    "parallel recursive hole subdivision cardinality";
  let boundary_fixture policy = Sop.grid ~connectivity:Ops.Grid_quads
      ~columns:120 ~rows:80 ~size:8. ()
      |> Sop.set_float ~owner:Attribute.Point ~name:"boundary_sample" 2.5
      |> Sop.subdivide ~scheme:Ops.Catmull_clark
           ~boundary_interpolation:policy in
  List.iter (fun policy ->
    let one = cook 1 (boundary_fixture policy)
    and many = cook 4 (boundary_fixture policy) in
    check (equal_geometry one many)
      "one-domain and four-domain point-boundary subdivision differ")
    [Ops.Subdivide_boundary_edge_only;
     Ops.Subdivide_boundary_edge_and_corner;
     Ops.Subdivide_boundary_none];
  let no_boundary_surface = cook 4
      (boundary_fixture Ops.Subdivide_boundary_none) in
  check (Geometry.primitive_count no_boundary_surface = (120 - 2) * (80 - 2) * 4)
    "parallel None point-boundary subdivision cardinality";
  let fvar_source = Ops.grid ~connectivity:Ops.Grid_quads
      ~columns:120 ~rows:80 ~size:8. () |> get_pdk in
  let fvar_topology = Topology.Private.view (Geometry.topology fvar_source) in
  let fvar_index = Topology_index.create (Geometry.topology fvar_source)
      |> Topology_index.Private.view in
  let fvar_values = Packed.Float2.of_owned
      ~x:(Array.init (Geometry.vertex_count fvar_source) (fun vertex ->
        float_of_int fvar_topology.vertex_points.(vertex)))
      ~y:(Array.init (Geometry.vertex_count fvar_source) (fun vertex ->
        let primitive = fvar_index.primitive_of_vertex.(vertex) in
        float_of_int ((primitive mod 120) / 40))) |> get_ok in
  let fvar_attribute = Attribute.create_owned ~owner:Attribute.Vertex
      ~name:"fvar_uv" (Attribute.Float2 fvar_values) |> get_ok in
  let fvar_source = Geometry.with_attribute fvar_attribute fvar_source |> get_ok in
  let fvar_fixture policy = Sop.snapshot fvar_source
      |> Sop.subdivide ~scheme:Ops.Catmull_clark
           ~face_varying_interpolation:policy in
  List.iter (fun policy ->
    let one = cook 1 (fvar_fixture policy)
    and many = cook 4 (fvar_fixture policy) in
    check (equal_geometry one many)
      "one-domain and four-domain face-varying subdivision differ")
    [Ops.Subdivide_fvar_none; Ops.Subdivide_fvar_corners_only;
     Ops.Subdivide_fvar_corners_plus1; Ops.Subdivide_fvar_corners_plus2;
     Ops.Subdivide_fvar_boundaries; Ops.Subdivide_fvar_all];
  let smooth_triangles = Sop.grid ~connectivity:Ops.Grid_triangles
      ~columns:120 ~rows:80 ~size:8. ()
      |> Sop.set_float ~owner:Attribute.Vertex ~name:"fvar_sample" 2.5
      |> Sop.subdivide ~scheme:Ops.Catmull_clark
           ~face_varying_interpolation:Ops.Subdivide_fvar_none
           ~triangle_policy:Ops.Subdivide_triangles_smooth in
  let one = cook 1 smooth_triangles and many = cook 4 smooth_triangles in
  check (equal_geometry one many)
    "one-domain and four-domain Smooth Triangles subdivision differ";
  check (Geometry.primitive_count one = 120 * 80 * 2 * 3)
    "parallel Smooth Triangles subdivision cardinality";
  let detail_source = Ops.grid ~connectivity:Ops.Grid_triangles
      ~columns:120 ~rows:80 ~size:8. () |> get_pdk in
  let detail_vertex_count = Geometry.vertex_count detail_source in
  let detail_source = Geometry.with_attribute
      (Attribute.create_owned ~owner:Attribute.Vertex ~name:"fvar_sample"
        (Attribute.Float (Array.init detail_vertex_count (fun vertex ->
           let value = float_of_int (vertex mod 127) in value *. value)))
       |> get_ok) detail_source |> get_ok in
  let detail_source = Geometry.with_attribute
      (Attribute.create_owned ~owner:Attribute.Vertex ~name:"creaseweight"
        (Attribute.Float (Array.init detail_vertex_count (fun vertex ->
           float_of_int ((vertex * 17) mod 41) /. 10.)))
       |> get_ok) detail_source |> get_ok in
  let detail_source = detail_source
      |> with_detail "osd_scheme" (Attribute.Text [|"catmull-clark"|])
      |> with_detail "osd_vtxboundaryinterpolation" (Attribute.Int [|2|])
      |> with_detail "osd_fvarlinearinterpolation" (Attribute.Int [|0|])
      |> with_detail "osd_creasingmethod" (Attribute.Int [|1|])
      |> with_detail "osd_trianglesubdiv" (Attribute.Int [|1|]) in
  let detail_overridden = Sop.snapshot detail_source
      |> Sop.subdivide ~iterations:2 ~scheme:Ops.Bilinear
           ~boundary_interpolation:Ops.Subdivide_boundary_none
           ~face_varying_interpolation:Ops.Subdivide_fvar_all
           ~creasing_method:Ops.Subdivide_creasing_uniform
           ~triangle_policy:Ops.Subdivide_triangles_catmull_clark
           ~resulting_crease_group:"detail_override_creases" in
  let one = cook 1 detail_overridden and many = cook 4 detail_overridden in
  check (equal_geometry one many)
    "one-domain and four-domain detail-overridden subdivision differ";
  check (List.for_all (fun name ->
      Geometry.find_attribute ~owner:Attribute.Detail name one <> None)
      ["osd_scheme"; "osd_vtxboundaryinterpolation";
       "osd_fvarlinearinterpolation"; "osd_creasingmethod";
       "osd_trianglesubdiv"])
    "parallel detail-overridden subdivision dropped its controls";
  check (match Geometry.find_edge_group "detail_override_creases" one with
    | Some group -> Edge_group.cardinality group > 0 | None -> false)
    "parallel detail-overridden Chaikin subdivision dropped residual creases";
  let promoted = Sop.grid ~columns:240 ~rows:160 ~size:12. ()
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.promote_attribute ~source:Attribute.Point
           ~destination:Attribute.Primitive ~name:"Cd" in
  let one = cook 1 promoted and many = cook 4 promoted in
  check (equal_geometry one many)
    "one-domain and four-domain attribute promotion differ";
  let promoted_arrays = Sop.grid ~columns:240 ~rows:160 ~size:12. ()
      |> Sop.enumerate ~owner:Attribute.Point ~name:"point_number"
      |> Sop.promote_attribute ~method_:Attribute_ops.Array_all
           ~delete_source:false ~source:Attribute.Point
           ~destination:Attribute.Primitive ~name:"point_number"
           ~into:"primitive_points" in
  let one = cook 1 promoted_arrays and many = cook 4 promoted_arrays in
  check (equal_geometry one many)
    "one-domain and four-domain array promotion differ";
  (match Geometry.find_attribute ~owner:Attribute.Primitive
      "primitive_points" one with
   | Some attribute ->
       (match Attribute.Private.storage attribute with
        | Attribute.Int_array values ->
            let values = Packed.Int_array.Private.view values in
            check (Array.length values.offsets = Geometry.primitive_count one + 1
                && Array.length values.values = Geometry.vertex_count one)
              "procedural array promotion cardinality"
        | _ -> fail "procedural array promotion storage")
   | None -> fail "procedural array promotion output missing");
  let promoted_patterns = Sop.grid ~columns:180 ~rows:120 ~size:10. ()
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.set_float ~owner:Attribute.Point ~name:"weight" 3.
      |> Sop.set_float ~owner:Attribute.Point ~name:"temporary" 9.
      |> Sop.promote_attributes ~source:Attribute.Point
           ~destination:Attribute.Primitive ~pattern:"* ^temporary" in
  let one = cook 1 promoted_patterns and many = cook 4 promoted_patterns in
  check (equal_geometry one many
      && Geometry.find_attribute ~owner:Attribute.Primitive "Cd" one <> None
      && Geometry.find_attribute ~owner:Attribute.Primitive "weight" one <> None
      && Geometry.find_attribute ~owner:Attribute.Primitive "temporary" one = None)
    "one-domain and four-domain pattern promotion differ";
  let renamed_patterns = Sop.grid ~columns:180 ~rows:120 ~size:10. ()
      |> Sop.set_float ~owner:Attribute.Point ~name:"sample_a" 3.
      |> Sop.set_float ~owner:Attribute.Point ~name:"sample_b" 9.
      |> Sop.promote_attributes ~method_:Attribute_ops.First
           ~source:Attribute.Point
           ~destination:Attribute.Primitive ~pattern:"sample_*"
           ~into_pattern:"reduced_*" ~index_pattern:"source_*" in
  let one = cook 1 renamed_patterns and many = cook 4 renamed_patterns in
  check (equal_geometry one many
      && Geometry.find_attribute ~owner:Attribute.Primitive "reduced_a" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Primitive "reduced_b" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Primitive "source_a" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Primitive "source_b" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Point "sample_a" one = None)
    "one-domain and four-domain renamed pattern promotion differ";
  let piece_geometry = Ops.grid ~columns:200 ~rows:120 ~size:12. () |> get_pdk in
  let point_count = Geometry.point_count piece_geometry in
  let piece_values = Attribute.create_owned ~name:"piece_value"
      ~owner:Attribute.Point (Attribute.Int (Array.init point_count
        (fun point -> (point * 37) mod 211))) |> get_ok
  and piece_ids = Attribute.create_owned ~name:"piece_id"
      ~owner:Attribute.Point (Attribute.Int (Array.init point_count
        (fun point -> point / 48))) |> get_ok in
  let piece_geometry = piece_geometry
      |> Geometry.with_attribute piece_values |> get_ok
      |> Geometry.with_attribute piece_ids |> get_ok in
  let piece_promoted = Sop.snapshot piece_geometry
      |> Sop.promote_attribute ~method_:Attribute_ops.Median
           ~piece_attribute:"piece_id" ~into:"piece_median" ~delete_source:false
           ~source:Attribute.Point ~destination:Attribute.Point
           ~name:"piece_value" in
  let one = cook 1 piece_promoted and many = cook 4 piece_promoted in
  check (equal_geometry one many)
    "one-domain and four-domain piece median promotion differ";
  let transfer_source = Sop.grid ~columns:180 ~rows:120 ~size:12. ()
      |> Sop.noise_displace ~seed:81 ~amplitude:0.3 ~frequency:0.4
      |> Sop.normals
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.group ~name:"transfer_source" Select.all_points in
  let transfer_target = Sop.grid ~columns:160 ~rows:100 ~size:11.5 ()
      |> Sop.group ~name:"transfer_target" Select.all_points in
  let transferred = Sop.attribute_transfer ~pattern:"C* N"
      ~mode:(Attribute_ops.Inverse_distance { neighbors = 4; power = 2. })
      ~max_distance:0.2 ~source_group:"transfer_source"
      ~target_group:"transfer_target" ~source:transfer_source
      ~target:transfer_target () in
  let one = cook 1 transferred and many = cook 4 transferred in
  check (equal_geometry one many)
    "one-domain and four-domain attribute transfer differ";
  let owner_transfer_source = Sop.grid ~columns:120 ~rows:80 ~size:8. ()
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.enumerate ~owner:Attribute.Primitive ~name:"primitive_id"
      |> Sop.enumerate ~owner:Attribute.Vertex ~name:"corner_id"
      |> Sop.group ~name:"transfer_vertex_patch"
           (Select.vertex_indices (Array.init 1_000 Fun.id))
      |> Sop.set_int ~owner:Attribute.Detail ~name:"revision" 17 in
  let owner_transfer_target = Sop.grid ~columns:100 ~rows:64 ~size:7.5 () in
  let directly_copied = Sop.attribute_copy ~group_owner:Group.Primitive
      ~rules:[
        Attribute_ops.copy_rule ~owner:Attribute.Point "Cd";
        Attribute_ops.copy_rule ~owner:Attribute.Vertex "corner_id";
        Attribute_ops.copy_rule ~owner:Attribute.Primitive "primitive_id";
        Attribute_ops.copy_rule ~owner:Attribute.Detail "revision";
      ] ~source:owner_transfer_source ~target:owner_transfer_target () in
  let one = cook 1 directly_copied and many = cook 4 directly_copied in
  check (equal_geometry one many
      && Geometry.find_attribute ~owner:Attribute.Point "Cd" one <> None
      && Geometry.find_attribute ~owner:Attribute.Vertex "corner_id" one <> None
      && Geometry.find_attribute ~owner:Attribute.Primitive "primitive_id" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Detail "revision" one <> None)
    "one-domain and four-domain cross-owner Attribute Copy differ";
  let combined = Sop.attribute_combine ~owner:Attribute.Point ~destination:"Cd"
      ~layers:[
        Attribute_ops.combine_layer ~source:"Cd" ~source_input:1
          Attribute_ops.Combine_add;
        Attribute_ops.combine_layer ~add:0.75
          Attribute_ops.Combine_multiply;
      ] ~sources:[owner_transfer_source] ~target:owner_transfer_target () in
  let one = cook 1 combined and many = cook 4 combined in
  check (equal_geometry one many
      && Geometry.find_attribute ~owner:Attribute.Point "Cd" one <> None)
    "one-domain and four-domain Attribute Combine differ";
  let interpolate_source = Sop.grid ~columns:2 ~rows:2 ~size:2. ()
      |> Sop.normals
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.group ~name:"hot" Select.all_points in
  let interpolate_target = Sop.grid ~columns:400 ~rows:250 ~size:8. ()
      |> Sop.set_int ~owner:Attribute.Point ~name:"source_primitive" 0
      |> Sop.set_vector ~owner:Attribute.Point ~name:"source_uvw"
           (Vec3.create 0.25 0.25 0.) in
  let computed = Sop.attribute_interpolate ~target_owner:Attribute.Point
      ~compute_weights:{
        Attribute_ops.computed_owner=Attribute.Point;
        computed_numbers_attribute="computed_points";
        computed_weights_attribute="computed_weights" }
      ~attributes:[] ~source:interpolate_source ~target:interpolate_target () in
  let interpolated = Sop.attribute_interpolate ~target_owner:Attribute.Point
      ~driver:(Attribute_ops.Point_weights {
        numbers_attribute="computed_points";
        weights_attribute="computed_weights" })
      ~point_pattern:"P N Cd hot" ~match_groups:true ~attributes:[]
      ~source:interpolate_source ~target:computed () in
  let one = cook 1 interpolated and many = cook 4 interpolated in
  check (equal_geometry one many)
    "one-domain and four-domain Attribute Interpolate differ";
  let primitive_transferred = Sop.attribute_transfer ~owner:Attribute.Primitive
      ~names:["primitive_id"] ~max_distance:0.25
      ~source:owner_transfer_source ~target:owner_transfer_target () in
  let one = cook 1 primitive_transferred and many = cook 4 primitive_transferred in
  check (equal_geometry one many
      && Geometry.find_attribute ~owner:Attribute.Primitive "primitive_id" one
         <> None)
    "one-domain and four-domain primitive-barycenter transfer differ";
  let vertex_transferred = Sop.attribute_transfer ~owner:Attribute.Vertex
      ~names:["corner_id"] ~max_distance:0.25
      ~source_vertex_group_pattern:"transfer_vertex_*"
      ~source:owner_transfer_source ~target:owner_transfer_target () in
  let one = cook 1 vertex_transferred and many = cook 4 vertex_transferred in
  check (equal_geometry one many
      && Geometry.find_attribute ~owner:Attribute.Vertex "corner_id" one <> None)
    "one-domain and four-domain vertex attribute transfer differ";
  let detail_transferred = Sop.attribute_transfer ~owner:Attribute.Detail
      ~names:["revision"] ~source:owner_transfer_source
      ~target:owner_transfer_target () in
  let one = cook 1 detail_transferred and many = cook 4 detail_transferred in
  check (equal_geometry one many
      && Geometry.find_attribute ~owner:Attribute.Detail "revision" one <> None)
    "one-domain and four-domain detail attribute transfer differ";
  let all_transferred = Sop.attribute_transfer_all ~point_pattern:"Cd"
      ~vertex_pattern:"corner_*" ~primitive_pattern:"primitive_*"
      ~detail_pattern:"revision" ~max_distance:0.1 ~blend_width:0.4
      ~falloff:(Attribute_ops.Uniform 0.75)
      ~source:owner_transfer_source ~target:owner_transfer_target () in
  let one = cook 1 all_transferred and many = cook 4 all_transferred in
  check (equal_geometry one many
      && Geometry.find_attribute ~owner:Attribute.Point "Cd" one <> None
      && Geometry.find_attribute ~owner:Attribute.Vertex "corner_id" one <> None
      && Geometry.find_attribute ~owner:Attribute.Primitive "primitive_id" one
         <> None
      && Geometry.find_attribute ~owner:Attribute.Detail "revision" one <> None)
    "one-domain and four-domain multi-owner attribute transfer differ";
  let surface_source = Sop.grid ~columns:160 ~rows:100 ~size:10. ()
      |> Sop.noise_displace ~seed:29 ~amplitude:0.4 ~frequency:0.5
      |> Sop.normals
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.measure_area
      |> Sop.group ~name:"surface_source" Select.all_primitives
      |> Sop.group ~name:"surface_vertex_patch"
           (Select.vertex_indices (Array.init 1_000 Fun.id)) in
  let surface_target = Sop.grid ~columns:140 ~rows:90 ~size:9.5 ()
      |> Sop.transform (Mat4.translation (Vec3.create 0. 0.35 0.))
      |> Sop.group ~name:"surface_target" Select.all_points in
  let surface_transferred = Sop.attribute_transfer_surface
      ~attributes:[
        Attribute_ops.surface_attribute ~owner:Attribute.Point "Cd";
        Attribute_ops.surface_attribute ~owner:Attribute.Point "N";
        Attribute_ops.surface_attribute ~into:"source_area"
          ~owner:Attribute.Primitive "area";
      ] ~max_distance:0.2 ~blend_width:0.8
      ~falloff:Attribute_ops.Smoothstep
      ~distance_attribute:"surface_distance" ~source_group:"surface_source"
      ~source_vertex_group_pattern:"surface_vertex_*"
      ~target_group:"surface_target"
      ~source:surface_source ~target:surface_target () in
  let one = cook 1 surface_transferred and many = cook 4 surface_transferred in
  check (equal_geometry one many)
    "one-domain and four-domain surface attribute transfer differ";
  check (Geometry.find_attribute ~owner:Attribute.Point "surface_distance" one
    <> None) "surface transfer distance attribute missing";
  let surface_vertex_target = Sop.grid ~columns:140 ~rows:90 ~size:9.5 ()
      |> Sop.transform (Mat4.translation (Vec3.create 0. 0.35 0.))
      |> Sop.group ~name:"surface_vertices" Select.all_vertices in
  let vertex_transferred = Sop.attribute_transfer_surface
      ~target_owner:Attribute.Vertex
      ~attributes:[
        Attribute_ops.surface_attribute ~owner:Attribute.Point "Cd";
        Attribute_ops.surface_attribute ~owner:Attribute.Point "N";
        Attribute_ops.surface_attribute ~into:"source_area"
          ~owner:Attribute.Primitive "area";
      ] ~max_distance:0.2 ~blend_width:0.8
      ~distance_attribute:"surface_distance" ~source_group:"surface_source"
      ~source_vertex_group:"surface_vertex_patch"
      ~target_group:"surface_vertices" ~source:surface_source
      ~target:surface_vertex_target () in
  let one = cook 1 vertex_transferred and many = cook 4 vertex_transferred in
  check (equal_geometry one many)
    "one-domain and four-domain vertex surface transfer differ";
  check (Geometry.find_attribute ~owner:Attribute.Vertex "surface_distance" one
    <> None) "vertex surface transfer distance attribute missing";
  let enumerate_source = Ops.grid ~columns:500 ~rows:300 ~size:20. ()
      |> get_pdk in
  let enumerate_count = Geometry.point_count enumerate_source in
  let enumerate_piece = Attribute.create_owned ~owner:Attribute.Point
      ~name:"piece" (Attribute.Int (Array.init enumerate_count (fun point ->
        (point * 31) mod 4093))) |> get_ok in
  let enumerate_source = Geometry.with_attribute enumerate_piece enumerate_source
      |> get_ok in
  let enumerated = Sop.snapshot enumerate_source
      |> Sop.group ~name:"middle"
           (Select.points_in_bounds ~min:(Vec3.create (-5.) (-1.) (-10.))
             ~max:(Vec3.create 5. 1. 10.))
      |> Sop.enumerate ~group:"middle" ~start:7 ~step:3
           ~piece_attribute:"piece"
           ~mode:Attribute_ops.Enumerate_piece_elements
           ~owner:Attribute.Point ~name:"selection_index"
      |> Sop.sort ~group:"middle" ~descending:true ~owner:Ops.Points
           ~key:(Ops.Attribute_component { name = "selection_index"; component = 0 }) in
  let one = cook 1 enumerated and many = cook 4 enumerated in
  check (equal_geometry one many)
    "one-domain and four-domain restricted piece enumeration/sort differ";
  let generated_attributes = Sop.grid ~columns:500 ~rows:300 ~size:20. ()
      |> Sop.attribute_randomize ~seed:31_337 ~owner:Attribute.Point
           ~name:"sample" (Attribute_ops.Random_log_normal {
             median = Attribute_ops.Vec4 (1., 2., 3., 4.);
             stddev = Attribute_ops.Vec4 (0.2, 0.4, 0.6, 0.8);
           })
      |> Sop.attribute_remap ~owner:Attribute.Point ~name:"sample"
           ~into:"mapped" ~input:Attribute_ops.Remap_auto
           ~output_min:(Attribute_ops.Vec4 (0., 0., 0., 0.))
           ~output_max:(Attribute_ops.Vec4 (1., 1., 1., 1.))
           ~ramp:[0., 0.; 0.35, 0.15; 0.7, 0.85; 1., 1.] in
  let one = cook 1 generated_attributes and many = cook 4 generated_attributes in
  check (equal_geometry one many)
    "one-domain and four-domain Attribute Randomize/Remap differ";
  let extended_random = Sop.grid ~connectivity:Ops.Grid_triangles
      ~columns:500 ~rows:300 ~size:20. ()
      |> Sop.group ~name:"randomize_vertices"
           (Select.vertex_indices [|0; 5; 11; 17; 23; 29|])
      |> Sop.attribute_randomize
           ~selection:(Sop.Vertex_group "randomize_vertices") ~seed:31_338
           ~minimum:(Attribute_ops.Vec2 (Vec2.create (-12.) (-12.)))
           ~maximum:(Attribute_ops.Vec2 (Vec2.create 12. 12.))
           ~owner:Attribute.Point ~name:"cauchy2"
           (Attribute_ops.Random_cauchy {
             median = Attribute_ops.Vec2 Vec2.zero;
             scale = Attribute_ops.Vec2 (Vec2.create 1. 1.);
           })
      |> Sop.attribute_randomize ~seed:31_339
           ~owner:Attribute.Primitive ~name:"label"
           (Attribute_ops.Random_custom_discrete_text [
             "low", 1.; "high", 3.;
           ]) in
  let one = cook 1 extended_random and many = cook 4 extended_random in
  check (equal_geometry one many)
    "one-domain and four-domain extended Attribute Randomize differ";
  let deformed = Sop.grid ~columns:500 ~rows:300 ~size:20. ()
      |> Sop.group ~name:"deform_center"
           (Select.points_in_bounds ~min:(Vec3.create (-8.) (-1.) (-8.))
              ~max:(Vec3.create 8. 1. 8.))
      |> Sop.mountain ~group:"deform_center" ~seed:711 ~height:0.8
           ~frequency:(Vec3.create 0.31 0.67 0.43)
           ~offset:(Vec3.create 2. 3. 5.) ~octaves:6 ~lacunarity:2.05
           ~roughness:0.48 ~height_attribute:"mountain_height"
      |> Sop.peak ~selection:(Sop.Point_group "deform_center") ~distance:0.05
           ~recompute_normals:true in
  let one = cook 1 deformed and many = cook 4 deformed in
  check (equal_geometry one many)
    "one-domain and four-domain Peak/Mountain geometry differ";
  let bent = Sop.grid ~columns:500 ~rows:300 ~size:20. ()
      |> Sop.group ~name:"bend_center"
           (Select.points_in_bounds ~min:(Vec3.create (-8.) (-1.) (-10.))
              ~max:(Vec3.create 8. 1. 10.))
      |> Sop.bend ~selection:(Sop.Point_group "bend_center")
           ~origin:(Vec3.create 0. 0. (-10.)) ~direction:Vec3.unit_z
           ~up:Vec3.unit_y ~length:20. ~bend_angle:1.3 ~twist_angle:2.1
           ~capture_attribute:"bend_capture" ~recompute_normals:true in
  let one = cook 1 bent and many = cook 4 bent in
  check (equal_geometry one many)
    "one-domain and four-domain Bend geometry differ";
  let scattered = Sop.grid ~columns:400 ~rows:250 ~size:20. ()
      |> Sop.attribute_randomize ~seed:1_337 ~owner:Attribute.Point
           ~name:"scatter_density" (Attribute_ops.Random_uniform {
             min = Attribute_ops.Scalar 0.05;
             max = Attribute_ops.Scalar 1.;
           })
      |> Sop.group_random ~seed:1_338 ~probability:0.73
           ~owner:Ops.Group_primitives ~name:"scatter_surface"
      |> Sop.scatter ~seed:1_339 ~group:"scatter_surface" ~count:100_000
           ~density:(Ops.scatter_density ~owner:Attribute.Point
             "scatter_density")
           ~point_pattern:"N scatter_density"
           ~source_primitive_attribute:"source_primitive"
           ~source_vertex_numbers_attribute:"source_vertices"
           ~source_vertex_weights_attribute:"source_weights" in
  let one = cook 1 scattered and many = cook 4 scattered in
  check (equal_geometry one many)
    "one-domain and four-domain weighted Scatter geometry differ";
  let duplicated = Sop.grid ~columns:120 ~rows:80 ~size:4. ()
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.group_edges ~name:"duplicate_edges"
      |> Sop.duplicate ~copies:5
           ~transform:(Mat4.translation (Vec3.create 0. 0.4 0.)) in
  let one = cook 1 duplicated and many = cook 4 duplicated in
  check (equal_geometry one many)
    "one-domain and four-domain materialized duplicate differ";
  let match_target = Sop.box ~size:(Vec3.create 4. 3. 5.) ()
      |> Sop.group ~name:"target_bounds" Select.all_points in
  let utilities = Sop.grid ~columns:120 ~rows:80 ~size:8. ()
      |> Sop.delete ~compact_points:true
           (Select.primitive_indices (Array.init 1_000 (fun index -> index * 2)))
      |> Sop.match_axis ~from:Vec3.unit_z ~into:(Vec3.create 1. 1. 0.)
      |> Sop.group ~name:"move" Select.all_points
      |> Sop.group ~name:"source_bounds" Select.all_points
      |> Sop.match_size ~fit:Ops.Match_z
           ~selection:(Sop.Point_group "move")
           ~source_selection:(Sop.Point_group "source_bounds")
           ~target_selection:(Sop.Point_group "target_bounds")
           ~translate_axes:(true, false, true)
           ~justify:(Vec3.create (-1.) 0. 1.)
           ~target_justify:(Vec3.create 1. 0. (-1.))
           ~offset:(Vec3.create 0.25 0. (-0.5)) ~target:match_target in
  let one = cook 1 utilities and many = cook 4 utilities in
  check (equal_geometry one many)
    "one-domain and four-domain compact/match-size geometry differ";
  let blasted = Sop.grid ~columns:180 ~rows:120 ~size:12. ()
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.group ~name:"left_half"
           (Select.points_in_bounds ~min:(Vec3.create (-6.) (-1.) (-6.))
             ~max:(Vec3.create 0. 1. 6.))
      |> Sop.blast ~owner:Group.Point ~group:"left_half"
           ~compact_points:true in
  let one = cook 1 blasted and many = cook 4 blasted in
  check (equal_geometry one many)
    "one-domain and four-domain point Blast geometry differ";
  let curve_points = Array.init 2_001 (fun index ->
      let x = float_of_int index *. 0.01 in
      x, sin x, 0.) in
  let healed_curve = Sop.polyline curve_points
      |> Sop.delete ~policy:Ops.Heal_primitives
           (Select.vertex_indices
             (Array.init 400 (fun index -> 1 + (index * 5)))) in
  let one = cook 1 healed_curve and many = cook 4 healed_curve in
  check (equal_geometry one many)
    "one-domain and four-domain vertex-healed curve differ";
  check (Geometry.vertex_count one = 1_601)
    "vertex-healed curve cardinality";
  let curve_samples = Array.init 20_001 (fun index ->
      let x = float_of_int index *. 0.001 in
      x, sin (x *. 0.7), cos (x *. 0.31)) in
  let carved_curve = Sop.polyline curve_samples
      |> Sop.group_edges ~name:"curve_edges"
      |> Sop.carve ~first:0.137 ~last:0.863
      |> Sop.curve_ends Ops.Close_curve in
  let one = cook 1 carved_curve and many = cook 4 carved_curve in
  check (equal_geometry one many)
    "one-domain and four-domain carve/curve-ends geometry differ";
  check (Geometry.point_count one > 10_000)
    "carve exactness fixture unexpectedly small";
  let grouped_carve = Sop.merge [
      Sop.polyline curve_samples |> Sop.normals;
      Sop.grid ~connectivity:Ops.Grid_quads ~columns:128 ~rows:96 ~size:8. ();
    ] |> Sop.group ~name:"carve_curve" (Select.primitive_indices [|0|])
      |> Sop.carve ~group:"carve_curve" ~first:0.137 ~last:0.863 in
  let one = cook 1 grouped_carve and many = cook 4 grouped_carve in
  check (equal_geometry one many)
    "one-domain and four-domain grouped Carve geometry differ";
  check (Geometry.primitive_count one = 12_289
      && Topology.primitive_kind (Geometry.topology one) 1 = Topology.Polygon)
    "grouped Carve unselected polygon/cardinality behavior";
  let cut_pieces = grouped_carve |> Sop.carve ~group:"carve_curve"
      ~first:0.2 ~last:0.8 ~keep:Ops.Keep_inside_and_outside in
  let one = cook 1 cut_pieces and many = cook 4 cut_pieces in
  check (equal_geometry one many)
    "one-domain and four-domain Carve inside/outside pieces differ";
  check (Geometry.primitive_count one = 12_291
      && Topology.primitive_kind (Geometry.topology one) 3 = Topology.Polygon)
    "Carve inside/outside exactness cardinality/order";
  let extracted_points = grouped_carve |> Sop.carve ~group:"carve_curve"
      ~first:0.1 ~last:0.9 ~extract_points:true ~divisions:10_001 in
  let one = cook 1 extracted_points and many = cook 4 extracted_points in
  check (equal_geometry one many)
    "one-domain and four-domain Carve point extraction differ";
  check (Geometry.primitive_count one = 12_288
      && Geometry.point_count one > 10_001
      && Geometry.vertex_count one = 49_152)
    "Carve point extraction exactness cardinality";
  let joined_curve_parts = List.init 64 (fun slot ->
      let part = if slot = 0 then 0 else 1 + ((slot * 20) mod 63) in
      let points = Array.init 129 (fun local ->
        let index = (part * 128) + local in
        let x = float_of_int index *. 0.002 in
        x, sin (x *. 0.9), cos (x *. 0.37)) in
      Sop.polyline points |> Sop.group_edges ~name:"joined_edges") in
  let joined_curves = Sop.merge joined_curve_parts
      |> Sop.join_curves ~connect_closest_ends:true ~group_size:9
           ~keep_originals:true in
  let one = cook 1 joined_curves and many = cook 4 joined_curves in
  check (equal_geometry one many)
    "one-domain and four-domain global closest Curve Join geometry differ";
  check (Geometry.primitive_count one = 72
      && Geometry.vertex_count one = 16_456)
    "Curve Join subgroup/keep exactness fixture cardinality";
  (match Geometry.find_edge_group "joined_edges" one with
   | Some group -> check (Edge_group.cardinality group = 8_248)
       "Curve Join keep-original/substituted-edge ancestry"
   | None -> fail "Curve Join dropped native edge group");
  let picked_ends = Array.init 64 (fun order -> {
      Ops.primitive = (order * 13) mod 64;
      end_ = if order land 1 = 0 then Ops.Join_curve_start
        else Ops.Join_curve_end;
    }) in
  let picked_curves = Sop.merge joined_curve_parts
      |> Sop.join_curves ~picked_ends ~group_size:11 ~keep_originals:true in
  let one = cook 1 picked_curves and many = cook 4 picked_curves in
  check (equal_geometry one many)
    "one-domain and four-domain picked-end Curve Join geometry differ";
  check (Geometry.primitive_count one = 70
      && Geometry.vertex_count one >= 16_400)
    "picked-end Curve Join subgroup/keep exactness fixture cardinality";
  let converted_lines = Sop.grid ~columns:256 ~rows:192 ~size:16. ()
      |> Sop.group_edges ~name:"converted_edges"
      |> Sop.convert_line ~length_attribute:"edge_length" in
  let one = cook 1 converted_lines and many = cook 4 converted_lines in
  check (equal_geometry one many)
    "one-domain and four-domain Convert Line geometry differ";
  check (Geometry.primitive_count one = 147_904
      && Geometry.vertex_count one = 295_808)
    "Convert Line exactness fixture cardinality";
  (match Geometry.find_edge_group "converted_edges" one with
   | Some group -> check (Edge_group.cardinality group = 147_904)
       "Convert Line lost native edge membership"
   | None -> fail "Convert Line dropped native edge group");
  let connected_lines = Sop.grid ~columns:256 ~rows:192 ~size:16. ()
      |> Sop.group_edges ~name:"connected_edges"
      |> Sop.convert_line ~connect_path:true ~maximum_distance:0.
           ~length_attribute:"path_length" in
  let one = cook 1 connected_lines and many = cook 4 connected_lines in
  check (equal_geometry one many)
    "one-domain and four-domain connected Convert Line geometry differ";
  check (Geometry.primitive_count one > 0
      && Geometry.primitive_count one < 147_904
      && Geometry.find_attribute ~owner:Attribute.Primitive "path_length" one
           <> None)
    "connected Convert Line exactness fixture cardinality/length";
  (match Geometry.find_edge_group "connected_edges" one with
   | Some group -> check (Edge_group.cardinality group = 147_904)
       "connected Convert Line lost native edge membership"
   | None -> fail "connected Convert Line dropped native edge group");
  let many_wires = Sop.grid ~columns:64 ~rows:48 ~size:10. ()
      |> Sop.set_float ~owner:Attribute.Point ~name:"wire_scale" 0.75
      |> Sop.set_float ~owner:Attribute.Point ~name:"wire_v" 0.25
      |> Sop.set_int ~owner:Attribute.Point ~name:"wire_seam" 2
      |> Sop.set_vector ~owner:Attribute.Point ~name:"wire_up" Vec3.unit_y
      |> Sop.convert_line
      |> Sop.sweep_circle ~sides:6 ~scale_attribute:"wire_scale"
           ~seam_offset:(-1) ~seam_attribute:"wire_seam"
           ~v_attribute:"wire_v" ~up_attribute:"wire_up" ~caps:true
           ~cap_group:"wire_caps" ~radius:0.02 in
  let one = cook 1 many_wires and many = cook 4 many_wires in
  check (equal_geometry one many)
    "one-domain and four-domain many-curve sweep geometry differ";
  check (Geometry.primitive_count one = 74_624)
    "many-curve sweep exactness fixture cardinality";
  (match Geometry.find_group ~owner:Group.Primitive "wire_caps" one with
   | Some group -> check (Group.cardinality group = 18_656)
       "many-curve sweep cap group cardinality"
   | None -> fail "many-curve sweep cap group missing");
  let general_backbone = Sop.polyline (Array.init 5_001 (fun point ->
      let t = float_of_int point *. 0.002 in
      0.3 *. sin (t *. 0.71), 0.2 *. cos (t *. 0.43), t))
      |> Sop.set_float ~owner:Attribute.Point ~name:"pscale" 0.85
      |> Sop.group_edges ~name:"backbone_edges"
  and general_profile = Sop.polyline ~closed:true (Array.init 24 (fun point ->
      let angle = 2. *. Float.pi *. float_of_int point /. 24. in
      0.08 *. cos angle, 0.08 *. sin angle, 0.))
      |> Sop.set_int ~owner:Attribute.Point ~name:"profile_id" 17
      |> Sop.group_edges ~name:"profile_edges" in
  let general_sweep = Sop.sweep
      ~connectivity:Ops.Grid_alternating_triangles ~twist:2.3 ~caps:true
      ~cap_group:"sweep_caps" ~backbone:general_backbone
      ~cross_section:general_profile () in
  let one = cook 1 general_sweep and many = cook 4 general_sweep in
  check (equal_geometry one many)
    "one-domain and four-domain general-profile Sweep geometry differ";
  check (Geometry.point_count one = 120_024
      && Geometry.primitive_count one = 240_002
      && Geometry.find_attribute ~owner:Attribute.Point
           "cross_section_profile_id" one <> None)
    "general-profile Sweep exactness fixture cardinality/payload";
  let split_source = Sop.grid ~columns:20 ~rows:10 ~size:4. ()
      |> Sop.group_edges ~name:"split_edges" in
  let selected_branch, remainder_branch = Sop.split ~compact_points:true
      (Select.primitive_indices (Array.init 100 Fun.id)) split_source in
  let selected_one = cook 1 selected_branch and selected_many = cook 4 selected_branch
  and remainder_one = cook 1 remainder_branch
  and remainder_many = cook 4 remainder_branch in
  check (equal_geometry selected_one selected_many
    && equal_geometry remainder_one remainder_many)
    "one-domain and four-domain split branches differ";
  check (Geometry.primitive_count selected_one = 100
    && Geometry.primitive_count remainder_one = 300)
    "split selected/remainder cardinality";
  let merged = Sop.merge [graph; Sop.transform
      (Mat4.translation (Vec3.create 30. 0. 0.)) graph] in
  let one = cook 1 merged and many = cook 4 merged in
  check (equal_geometry one many)
    "one-domain and four-domain merge geometry differ";
  let transfer_source = Sop.grid ~columns:40 ~rows:30 ~size:8. ()
      |> Sop.group ~name:"transfer_points"
           (Select.point_indices (Array.init 200 (fun index -> index * 6)))
      |> Sop.group ~name:"transfer_faces"
           (Select.primitive_indices (Array.init 300 (fun index -> index * 4)))
      |> Sop.group_edges ~name:"transfer_edges" ~min_length:0.1 in
  let transfer_target = transfer_source
      |> Sop.transform (Mat4.translation (Vec3.create 0.001 0. 0.001)) in
  let transferred = Sop.group_transfer ~distance:0.01
      ~conflict:Pdk.Ops.Copy_overwrite
      ~rules:[
        { Pdk.Ops.transfer_owner = Pdk.Ops.Group_points;
          transfer_pattern = "transfer_points"; transfer_prefix = "mapped_" };
        { Pdk.Ops.transfer_owner = Pdk.Ops.Group_primitives;
          transfer_pattern = "transfer_faces"; transfer_prefix = "mapped_" };
        { Pdk.Ops.transfer_owner = Pdk.Ops.Group_edges;
          transfer_pattern = "transfer_edges"; transfer_prefix = "mapped_" }]
      ~source:transfer_source ~target:transfer_target () in
  let one = cook 1 transferred and many = cook 4 transferred in
  check (equal_geometry one many)
    "one-domain and four-domain Group Transfer geometry differ";
  let columns = 121 in
  let base_elements = Array.init 32 (fun index ->
    let pair = index / 2 in
    if index land 1 = 0 then (pair * 5) * columns
    else ((pair * 5) * columns) + 120) in
  let paths = Sop.grid ~columns:120 ~rows:90 ~size:20. ()
      |> Sop.ordered_group ~owner:Pdk.Group.Point ~name:"waypoints" base_elements
      |> Sop.group_find_path ~mode:Pdk.Ops.Start_end_pairs
           ~avoid_self_intersection:false ~base_group:"waypoints" ~name:"paths" in
  let one = cook 1 paths and many = cook 4 paths in
  check (equal_geometry one many)
    "one-domain and four-domain Group Find Path geometry differ";
  let primitive_elements = Array.init 16 (fun index ->
    let row = (index / 2) * 10 in
    if index land 1 = 0 then (row * 120) * 2
    else (((row * 120) + 119) * 2) + 1) in
  let primitive_paths = Sop.grid ~columns:120 ~rows:90 ~size:20. ()
      |> Sop.ordered_group ~owner:Pdk.Group.Primitive
           ~name:"face_waypoints" primitive_elements
      |> Sop.group_find_path ~owner:Pdk.Group.Primitive
           ~mode:Pdk.Ops.Start_end_pairs ~avoid_self_intersection:false
           ~base_group:"face_waypoints" ~name:"face_paths" in
  let one = cook 1 primitive_paths and many = cook 4 primitive_paths in
  check (equal_geometry one many)
    "one-domain and four-domain primitive Group Find Path geometry differ";
  let attribute_boundaries = Sop.grid ~columns:120 ~rows:90 ~size:20. ()
      |> Sop.enumerate ~owner:Pdk.Attribute.Primitive ~name:"face_id"
      |> Sop.group_from_attribute_boundary ~owner:Pdk.Ops.Group_edges
           ~name:"attribute_seams" ~attributes:[{
             Pdk.Ops.boundary_attribute_owner = Pdk.Attribute.Primitive;
             boundary_attribute_pattern = "face_id" }] in
  let one = cook 1 attribute_boundaries and many = cook 4 attribute_boundaries in
  check (equal_geometry one many)
    "one-domain and four-domain Group from Attribute Boundary geometry differ";
  let named_count = 200_003 in
  let named_source = Ops.points (Array.init named_count (fun point ->
      float_of_int point, 0., 0.)) in
  let piece_names = Attribute.create_owned ~owner:Attribute.Point
      ~name:"piece_name" (Attribute.Text (Array.init named_count (fun point ->
        if point mod 101 = 0 then ""
        else Printf.sprintf "piece_%02d" (point mod 32)))) |> Result.get_ok in
  let named_source = Geometry.with_attribute piece_names named_source
      |> Result.get_ok in
  let named = Sop.snapshot named_source
      |> Sop.groups_from_name ~owner:Attribute.Point ~attribute:"piece_name" in
  let one = cook 1 named and many = cook 4 named in
  check (equal_geometry one many)
    "one-domain and four-domain Groups from Name geometry differ";
  let round_trip = named
      |> Sop.name_from_groups ~attribute:"round_trip" ~delete_groups:true
           ~owner:Attribute.Point in
  let one = cook 1 round_trip and many = cook 4 round_trip in
  check (equal_geometry one many)
    "one-domain and four-domain Name from Groups geometry differ";
  let random_groups = Sop.grid ~columns:180 ~rows:120 ~size:20. ()
      |> Sop.group_random ~seed:917 ~probability:0.431
           ~owner:Ops.Group_points ~name:"random_points"
      |> Sop.group_random ~seed:918 ~probability:0.379
           ~owner:Ops.Group_vertices ~name:"random_vertices"
      |> Sop.group_random ~seed:919 ~probability:0.293
           ~owner:Ops.Group_primitives ~name:"random_primitives"
      |> Sop.group_random ~seed:920 ~probability:0.217
           ~owner:Ops.Group_edges ~name:"random_edges" in
  let one = cook 1 random_groups and many = cook 4 random_groups in
  check (equal_geometry one many)
    "one-domain and four-domain Group Random geometry differ";
  let bounded_groups = random_groups
      |> Sop.group_bounds ~containment:Ops.Partially_contained
           (Ops.Bounds_sphere { center = Vec3.create 1. 0. (-2.); radius = 7.5 })
           ~owner:Ops.Group_points ~name:"bounded_points"
      |> Sop.group_bounds ~containment:Ops.Partially_contained
           (Ops.Bounds_box { minimum = Vec3.create (-6.) (-1.) (-5.);
             maximum = Vec3.create 5. 1. 7. })
           ~owner:Ops.Group_vertices ~name:"bounded_vertices"
      |> Sop.group_bounds ~containment:Ops.Partially_contained
           (Ops.Bounds_sphere { center = Vec3.zero; radius = 8. })
           ~owner:Ops.Group_primitives ~name:"bounded_primitives"
      |> Sop.group_bounds ~containment:Ops.Partially_contained
           (Ops.Bounds_box { minimum = Vec3.create (-4.) (-1.) (-4.);
             maximum = Vec3.create 4. 1. 4. })
           ~owner:Ops.Group_edges ~name:"bounded_edges" in
  let one = cook 1 bounded_groups and many = cook 4 bounded_groups in
  check (equal_geometry one many)
    "one-domain and four-domain Group Bounds geometry differ";
  let normal_groups = Sop.box ~size:(Vec3.create 5. 4. 3.) ()
      |> Sop.mountain ~seed:929 ~height:0.21
           ~frequency:(Vec3.create 0.7 1.1 0.9) ~octaves:4
      |> Sop.group_normal ~direction:Vec3.unit_y
           ~spread_angle:(Float.pi /. 3.) ~include_opposite:true
           ~owner:Ops.Group_points ~name:"vertical_points"
      |> Sop.group_normal ~direction:Vec3.unit_y
           ~spread_angle:(Float.pi /. 3.) ~include_opposite:true
           ~owner:Ops.Group_primitives ~name:"vertical_faces"
      |> Sop.group_normal ~direction:Vec3.unit_y
           ~spread_angle:(Float.pi /. 3.) ~include_opposite:true
           ~owner:Ops.Group_edges ~name:"vertical_edges"
      |> Sop.group_non_planar ~tolerance:0.001 ~name:"warped_faces"
      |> Sop.group_backface ~viewpoint:(Vec3.create 4. 3. 5.)
           ~name:"backfaces" in
  let one = cook 1 normal_groups and many = cook 4 normal_groups in
  check (equal_geometry one many)
    "one-domain and four-domain Group Normal/Non-Planar geometry differ";
  let extruded = Sop.grid ~columns:40 ~rows:30 ~size:8. ()
      |> Sop.group ~name:"all" Select.all_primitives
      |> Sop.group_edges ~name:"extruded_edges"
      |> Sop.poly_extrude ~group:"all"
           ~divide:Ops.Extrude_connected_components ~divisions:3
           ~front_group:"extrude_front" ~side_group:"extrude_side"
           ~front_boundary_group:"front_rim" ~back_boundary_group:"back_rim"
           ~distance:0.4
      |> Sop.measure ~total_name:"surface_area" Analysis.Area
      |> Sop.measure ~name:"boundary_length" ~total_name:"perimeter"
           Analysis.Perimeter
      |> Sop.connectivity in
  let one = cook 1 extruded and many = cook 4 extruded in
  check (equal_geometry one many)
    "one-domain and four-domain extrude/analysis geometry differ";
  let cleaned = Sop.grid ~columns:320 ~rows:240 ~size:12. ()
      |> Sop.set_float ~owner:Attribute.Point ~name:"temporary_weight" 1.
      |> Sop.group_random ~seed:77 ~probability:0.
           ~owner:Ops.Group_points ~name:"empty_points"
      |> Sop.clean ~reverse_winding:true ~delete_unused_groups:true
           ~point_attributes:"temporary*" in
  let one = cook 1 cleaned and many = cook 4 cleaned in
  check (equal_geometry one many)
    "one-domain and four-domain Clean geometry differ";
  let volume_graph = Sop.box ~size:(Vec3.create 2. 3. 4.) ()
      |> Sop.duplicate ~copies:20_000
           ~transform:(Mat4.translation (Vec3.create 3. 0. 0.))
      |> Sop.measure ~total_name:"signed_volume" Analysis.Signed_volume in
  let one = cook 1 volume_graph and many = cook 4 volume_graph in
  check (equal_geometry one many)
    "one-domain and four-domain signed-volume geometry differ";
  let compacted = Sop.merge [
      Sop.polyline [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.)|]
        |> Sop.group_edges ~name:"compact_edges";
      Sop.points [|(8., 0., 0.)|]
        |> Sop.group_edges ~name:"compact_edges";
    ] |> Sop.compact_points in
  let one = cook 1 compacted and many = cook 4 compacted in
  check (equal_geometry one many)
    "one-domain and four-domain edge-aware point compaction differ";
  check (Geometry.point_count one = 3)
    "point compaction did not remove the unreferenced point";
  (match Geometry.find_edge_group "compact_edges" one with
   | Some group -> check (Edge_group.cardinality group = 2)
       "point compaction did not preserve native edge membership"
   | None -> fail "point compaction dropped its native edge group");
  let collapsed = Sop.grid ~columns:240 ~rows:180 ~size:12. ()
      |> Sop.set_int ~owner:Attribute.Point ~name:"piece" 1
      |> Sop.group_random ~seed:911 ~probability:0.045
           ~owner:Ops.Group_edges ~name:"collapse_edges"
      |> Sop.edge_collapse ~group:"collapse_edges"
           ~connectivity_attribute:"piece" in
  let one = cook 1 collapsed and many = cook 4 collapsed in
  check (equal_geometry one many)
    "one-domain and four-domain Edge Collapse geometry differ";
  check (Geometry.point_count one < 241 * 181
      && Geometry.primitive_count one > 0)
    "parallel Edge Collapse fixture did not retain useful output";
  let reduced = Sop.grid ~counts:Ops.Grid_point_counts
      ~connectivity:Ops.Grid_alternating_triangles
      ~columns:120 ~rows:90 ~size:12. ()
      |> Sop.set_int ~owner:Attribute.Point ~name:"source_id" 17
      |> Sop.group_edges ~name:"boundary" ~incidence:Ops.Boundary_edge
      |> Sop.poly_reduce ~target:(Ops.Reduce_ratio 0.37)
           ~preserve_boundary:true ~only_original_positions:false
           ~equalize_lengths:1e-8 ~max_normal_deviation:0.4
           ~output_group:"reduced" in
  let one = cook 1 reduced and many = cook 4 reduced in
  check (equal_geometry one many)
    "one-domain and four-domain PolyReduce geometry differ";
  check (Geometry.primitive_count one < 119 * 89 * 2
      && Geometry.find_group ~owner:Group.Primitive "reduced" one <> None
      && Geometry.find_edge_group "boundary" one <> None)
    "parallel PolyReduce fixture lost cardinality or ancestry";
  let beveled = Sop.box ~connectivity:Ops.Box_quads ~consolidate_points:true
      ~normals:Ops.Box_no_normals ~size:(Vec3.create 1. 1. 1.) ()
      |> Sop.duplicate ~copies:2_000
           ~transform:(Mat4.translation (Vec3.create 1.5 0. 0.))
      |> Sop.set_float ~owner:Attribute.Point ~name:"pscale" 1.
      |> Sop.group_edges ~name:"bevel_edges"
      |> Sop.poly_bevel ~group:"bevel_edges"
           ~shape:(Ops.Bevel_round { convexity = 0.8 }) ~divisions:3
           ~point_scale_attribute:"pscale" ~distance:0.08
           ~edge_group:"edge_fillets" ~corner_group:"corner_fillets"
           ~offset_group:"offset_edges" in
  let one = cook 1 beveled and many = cook 4 beveled in
  check (equal_geometry one many)
    "one-domain and four-domain PolyBevel geometry differ";
  check (Geometry.point_count one = 2_001 * 72
      && Geometry.primitive_count one = 2_001 * 50
      && Geometry.find_group ~owner:Group.Primitive "edge_fillets" one <> None
      && Geometry.find_edge_group "offset_edges" one <> None)
    "parallel PolyBevel fixture lost cardinality or ancestry";
  let point_split = Sop.grid ~connectivity:Ops.Grid_quads
      ~columns:400 ~rows:300 ~size:12. ()
      |> Sop.point_split in
  let one = cook 1 point_split and many = cook 4 point_split in
  check (equal_geometry one many)
    "one-domain and four-domain Point Split geometry differ";
  check (Geometry.point_count one = 400 * 300 * 4
      && Geometry.vertex_count one = 400 * 300 * 4)
    "parallel Point Split fixture cardinality";
  let emission_points = Array.init 100_000 (fun point ->
      float_of_int (point mod 1_000) *. 0.01,
      float_of_int (point / 1_000) *. 0.01,
      float_of_int (point mod 17) *. 0.001) in
  let point_generate = Sop.points emission_points
      |> Sop.set_float ~owner:Attribute.Point ~name:"density" 6.
      |> Sop.set_int ~owner:Attribute.Point ~name:"source_id" 17
      |> Sop.point_generate ~label:"parallel-point-generate" ~seed:929
           ~generated_group:"emitted" ~copy_point_attributes:"density source_id"
           ~mode:(Ops.Generate_per_point {
             points_per_point = 1.; scale_attribute = Some "density" }) in
  let one = cook 1 point_generate and many = cook 4 point_generate in
  check (equal_geometry one many)
    "one-domain and four-domain Point Generate geometry differ";
  check (Geometry.point_count one = 600_000
      && Geometry.find_group ~owner:Group.Point "emitted" one <> None)
    "parallel Point Generate fixture cardinality";
  let point_replicate = Sop.points emission_points
      |> Sop.set_float ~owner:Attribute.Point ~name:"density" 6.
      |> Sop.enumerate ~owner:Attribute.Point ~name:"id"
      |> Sop.set_vector ~owner:Attribute.Point ~name:"flow"
           (Vec3.create 1. 2. 3.)
      |> Sop.set_vector ~owner:Attribute.Point ~name:"scale"
           (Vec3.create 0.75 1.25 1.5)
      |> Sop.point_replicate ~label:"parallel-point-replicate" ~seed:937
           ~shape:Ops.Replicate_sphere ~quasi_stratified:true
           ~generated_group:"cloud"
           ~copy_point_attributes:"density id flow scale"
           ~transform_attributes:"flow"
           ~points_per_point:1. ~scale_attribute:"density" in
  let one = cook 1 point_replicate and many = cook 4 point_replicate in
  check (equal_geometry one many)
    "one-domain and four-domain Point Replicate geometry differ";
  check (Geometry.point_count one = 600_000
      && Geometry.find_group ~owner:Group.Point "cloud" one <> None)
    "parallel Point Replicate fixture cardinality";
  let flipped = Sop.snapshot (edge_flip_geometry 20_000)
      |> Sop.edge_flip ~group:"flip_edges" ~cycles:1 in
  let one = cook 1 flipped and many = cook 4 flipped in
  check (equal_geometry one many)
    "one-domain and four-domain Edge Flip geometry differ";
  check (Geometry.point_count one = 80_000
      && Geometry.vertex_count one = 120_000
      && Geometry.primitive_count one = 40_000)
    "parallel Edge Flip fixture cardinality";
  let cusped = Sop.grid ~connectivity:Ops.Grid_triangles
      ~columns:320 ~rows:240 ~size:12. ()
      |> Sop.set_int ~owner:Attribute.Point ~name:"source_id" 17
      |> Sop.group_edges ~name:"cusp_edges"
      |> Sop.edge_cusp ~group:"cusp_edges" in
  let one = cook 1 cusped and many = cook 4 cusped in
  check (equal_geometry one many)
    "one-domain and four-domain Edge Cusp geometry differ";
  check (Geometry.point_count one > 321 * 241
      && Geometry.vertex_count one = 320 * 240 * 6)
    "parallel Edge Cusp fixture cardinality";
  let straightened = Sop.grid ~connectivity:Ops.Grid_triangles
      ~columns:400 ~rows:300 ~width:14. ~height:9. ~size:1. ()
      |> Sop.mountain ~seed:919 ~height:0.8
           ~frequency:(Vec3.create 0.7 1.1 0.9) ~octaves:4
      |> Sop.group_edges ~name:"straighten_edges"
      |> Sop.edge_straighten ~group:"straighten_edges"
           ~output_group:"straightened" in
  let one = cook 1 straightened and many = cook 4 straightened in
  check (equal_geometry one many)
    "one-domain and four-domain Edge Straighten geometry differ";
  check (Geometry.point_count one = 401 * 301
      && (Geometry.find_edge_group "straightened" one
          |> Option.get |> Edge_group.cardinality) > 0)
    "parallel Edge Straighten fixture cardinality";
  let equalized = Sop.snapshot (edge_equalize_geometry 50_000)
      |> Sop.group_edges ~name:"equalize_edges"
      |> Sop.edge_equalize ~group:"equalize_edges"
           ~method_:Ops.Equalize_average ~output_group:"equalized" in
  let one = cook 1 equalized and many = cook 4 equalized in
  check (equal_geometry one many)
    "one-domain and four-domain Edge Equalize geometry differ";
  check (Geometry.point_count one = 100_000
      && (Geometry.find_edge_group "equalized" one
          |> Option.get |> Edge_group.cardinality) = 50_000)
    "parallel Edge Equalize fixture cardinality";
  let relax_source = edge_equalize_geometry 50_000 in
  let relaxed = Sop.snapshot relax_source
      |> Sop.edge_relax ~reference:(Sop.snapshot
           (edge_relax_reference relax_source)) in
  let one = cook 1 relaxed and many = cook 4 relaxed in
  check (equal_geometry one many)
    "one-domain and four-domain Edge Relax geometry differ";
  check (Geometry.point_count one = 100_000
      && Geometry.primitive_count one = 50_000)
    "parallel Edge Relax fixture cardinality";
  let uv_mapped = Sop.uv_sphere ~segments:192 ~rings:96 ~radius:2. ()
      |> Sop.group ~name:"uv_faces" Select.all_primitives
      |> Sop.group_edges ~name:"boundary_edges" ~incidence:Ops.Boundary_edge
      |> Sop.uv_project ~group:"uv_faces" ~u_range:(0.1, 0.9)
           ~v_range:(0.2, 0.8)
           (Ops.Spherical { origin = Vec3.zero; axis = Vec3.unit_y;
             seam = Vec3.unit_x })
      |> Sop.uv_transform ~scale:(Vec2.create 3. 2.)
           ~angle:0.17 ~pivot:(Vec2.create 0.5 0.5)
      |> Sop.uv_auto_seam ~angle:(Float.pi /. 3.) ~existing_uv:"uv"
           ~island_attribute:"uv_island"
      |> Sop.uv_unitize ~seams:"uv_seams" Ops.Islands in
  let one = cook 1 uv_mapped and many = cook 4 uv_mapped in
  check (equal_geometry one many)
    "one-domain and four-domain UV projection/transform/seam/unitize differ";
  check (Geometry.find_attribute ~owner:Attribute.Vertex "uv" one <> None)
    "parallel UV fixture missing vertex coordinates";
  let parameterized = Sop.grid ~columns:96 ~rows:64 ~size:8. ()
      |> Sop.uv_flatten ~iterations:400 ~tolerance:1e-10
      |> Sop.uv_relax ~iterations:50 ~tolerance:1e-12 in
  let one = cook 1 parameterized and many = cook 4 parameterized in
  check (equal_geometry one many)
    "one-domain and four-domain UV flatten/relax differ";
  print_endline "procedural parallel exactness test passed"
