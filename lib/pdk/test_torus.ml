open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error error -> fail (Error.to_string error)
let near ?(epsilon = 1e-10) left right = abs_float (left -. right) <= epsilon
let positions geometry = Packed.Float3.Private.view (Geometry.positions geometry)

let expect_code code = function
  | Error error when String.equal (Error.code error) code -> ()
  | Error error -> fail (Printf.sprintf "expected %s, received %s" code
      (Error.to_string error))
  | Ok _ -> fail ("expected error " ^ code)

let float2_attribute geometry owner name =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float2 values -> Packed.Float2.Private.view values
       | _ -> fail (name ^ " has unexpected storage"))
  | None -> fail ("missing attribute " ^ name)

let float3_attribute geometry owner name =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail (name ^ " has unexpected storage"))
  | None -> fail ("missing attribute " ^ name)

let equal_storage left right = match Attribute.storage left, Attribute.storage right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
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
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | _ -> false

let equal_attribute left right =
  Attribute.owner left = Attribute.owner right
  && String.equal (Attribute.name left) (Attribute.name right)
  && String.equal (Attribute.kind_name left) (Attribute.kind_name right)
  && equal_storage left right

let equal_geometry left right =
  let left_positions = positions left and right_positions = positions right
  and left_topology = Topology.Private.view (Geometry.topology left)
  and right_topology = Topology.Private.view (Geometry.topology right) in
  left_positions.x = right_positions.x
  && left_positions.y = right_positions.y
  && left_positions.z = right_positions.z
  && left_topology.point_count = right_topology.point_count
  && left_topology.vertex_points = right_topology.vertex_points
  && left_topology.primitive_offsets = right_topology.primitive_offsets
  && Bytes.equal left_topology.primitive_kinds right_topology.primitive_kinds
  && List.equal equal_attribute (Geometry.attributes left)
       (Geometry.attributes right)

let check_vertex_normal_winding geometry message =
  let point = positions geometry
  and normal = float3_attribute geometry Attribute.Vertex "N"
  and topology = Topology.Private.view (Geometry.topology geometry) in
  for primitive = 0 to Geometry.primitive_count geometry - 1 do
    let first = topology.primitive_offsets.(primitive)
    and last = topology.primitive_offsets.(primitive + 1) in
    let nx = ref 0. and ny = ref 0. and nz = ref 0. in
    for vertex = first to last - 1 do
      let next = if vertex + 1 = last then first else vertex + 1 in
      let a = topology.vertex_points.(vertex)
      and b = topology.vertex_points.(next) in
      nx := !nx +. ((point.y.(a) -. point.y.(b))
          *. (point.z.(a) +. point.z.(b)));
      ny := !ny +. ((point.z.(a) -. point.z.(b))
          *. (point.x.(a) +. point.x.(b)));
      nz := !nz +. ((point.x.(a) -. point.x.(b))
          *. (point.y.(a) +. point.y.(b)))
    done;
    let alignment = (!nx *. normal.x.(first)) +. (!ny *. normal.y.(first))
        +. (!nz *. normal.z.(first)) in
    check (alignment > 1e-12)
      (Printf.sprintf "%s (primitive %d, alignment %.17g)"
        message primitive alignment)
  done

let check_default_and_connectivity () =
  let make ?(rows = 8) ?(columns = 4) connectivity =
    Ops.torus ~connectivity ~rows ~columns ~major_radius:2. ~minor_radius:1. ()
    |> get_ok in
  let triangles = make Ops.Torus_triangles
  and alternating = make Ops.Torus_alternating_triangles
  and quads = make Ops.Torus_quads
  and rows = make Ops.Torus_rows
  and columns = make Ops.Torus_columns
  and both = make Ops.Torus_rows_and_columns
  and points = make Ops.Torus_points in
  let point = positions triangles
  and normal = float3_attribute triangles Attribute.Point "N"
  and topology = Topology.Private.view (Geometry.topology triangles) in
  check (Geometry.point_count triangles = 32
      && Geometry.vertex_count triangles = 192
      && Geometry.primitive_count triangles = 64)
    "default Torus cardinality";
  check (near point.x.(0) 3. && near point.y.(0) 0. && near point.z.(0) 0.
      && near normal.x.(0) 1. && near normal.y.(0) 0.
      && near normal.z.(0) 0.)
    "default Torus frame or normal";
  check (Array.sub topology.vertex_points 0 6 = [|0; 1; 5; 0; 5; 4|]
      && topology.primitive_offsets = Array.init 65 (fun index -> index * 3))
    "default Torus topology/order";
  check (Geometry.point_count quads = 32 && Geometry.vertex_count quads = 128
      && Geometry.primitive_count quads = 32)
    "quad Torus cardinality";
  check (Geometry.vertex_count rows = 32 && Geometry.primitive_count rows = 4)
    "row Torus cardinality";
  check (Geometry.vertex_count columns = 32
      && Geometry.primitive_count columns = 8)
    "column Torus cardinality";
  check (Geometry.vertex_count both = 64 && Geometry.primitive_count both = 12)
    "combined-curve Torus cardinality";
  check (Geometry.vertex_count points = 0 && Geometry.primitive_count points = 0)
    "point Torus cardinality";
  for primitive = 0 to Geometry.primitive_count both - 1 do
    check (Topology.primitive_kind (Geometry.topology both) primitive
        = Topology.Closed_polyline)
      "wrapped Torus curve was not closed"
  done;
  let regular = Topology.Private.view (Geometry.topology triangles)
  and checker = Topology.Private.view (Geometry.topology alternating) in
  check (regular.vertex_points <> checker.vertex_points)
    "alternating Torus collapsed to regular triangles"

let check_open_sweeps_caps_and_bridge () =
  let make connectivity = Ops.torus ~connectivity
      ~normals:Ops.Torus_vertex_normals ~uv_attribute:"uv"
      ~u_start:0.2 ~u_end:2.4 ~v_start:(-.Float.pi /. 2.)
      ~v_end:(Float.pi /. 2.) ~u_wrap:false ~v_wrap:false
      ~u_end_caps:true ~v_end_cap:true ~rows:8 ~columns:5
      ~major_radius:3. ~minor_radius:1. () |> get_ok in
  let triangles = make Ops.Torus_triangles and quads = make Ops.Torus_quads in
  check (Geometry.point_count triangles = 40
      && Geometry.vertex_count triangles = 220
      && Geometry.primitive_count triangles = 72)
    "capped triangle Torus cardinality";
  check (Geometry.point_count quads = 40 && Geometry.vertex_count quads = 150
      && Geometry.primitive_count quads = 37)
    "capped quad Torus cardinality";
  let topology = Geometry.topology quads in
  check (Topology.primitive_size topology 35 = 5
      && Topology.primitive_size topology 36 = 5)
    "U end caps were not emitted as cross-section polygons";
  let normal = float3_attribute quads Attribute.Vertex "N"
  and uv = float2_attribute quads Attribute.Vertex "uv" in
  for vertex = 0 to Geometry.vertex_count quads - 1 do
    let length = sqrt ((normal.x.(vertex) *. normal.x.(vertex))
        +. (normal.y.(vertex) *. normal.y.(vertex))
        +. (normal.z.(vertex) *. normal.z.(vertex))) in
    check (near length 1. && uv.x.(vertex) >= 0. && uv.x.(vertex) <= 1.
        && uv.y.(vertex) >= 0. && uv.y.(vertex) <= 1.)
      "capped Torus emitted invalid vertex normal/UV"
  done;
  let mesh = Prismel_mesh.to_mesh quads |> get_ok in
  check (Mesh.index_count mesh > 0 && Mesh.normals mesh <> []
      && Mesh.tex_coords mesh <> [])
    "capped Torus failed terminal mesh conversion";
  check_vertex_normal_winding triangles
    "capped Torus winding disagrees with its vertex normals";
  let reversed_u = Ops.torus ~connectivity:Ops.Torus_quads
      ~normals:Ops.Torus_vertex_normals
      ~u_start:2.4 ~u_end:0.2 ~v_start:(-.Float.pi /. 2.)
      ~v_end:(Float.pi /. 2.) ~u_wrap:false ~v_wrap:false
      ~u_end_caps:true ~v_end_cap:true ~rows:8 ~columns:5
      ~major_radius:3. ~minor_radius:1. () |> get_ok in
  check_vertex_normal_winding reversed_u
    "descending U Torus winding disagrees with its vertex normals";
  let reversed_v = Ops.torus ~connectivity:Ops.Torus_alternating_triangles
      ~normals:Ops.Torus_vertex_normals
      ~u_start:0.2 ~u_end:2.4 ~v_start:(Float.pi /. 2.)
      ~v_end:(-.Float.pi /. 2.) ~u_wrap:false ~v_wrap:false
      ~u_end_caps:true ~v_end_cap:true ~rows:8 ~columns:5
      ~major_radius:3. ~minor_radius:1. () |> get_ok in
  check_vertex_normal_winding reversed_v
    "descending V Torus winding disagrees with its vertex normals";
  let open_rows = Ops.torus ~connectivity:Ops.Torus_rows
      ~u_wrap:false ~v_wrap:false ~rows:8 ~columns:5
      ~major_radius:3. ~minor_radius:1. () |> get_ok in
  for primitive = 0 to Geometry.primitive_count open_rows - 1 do
    check (Topology.primitive_kind (Geometry.topology open_rows) primitive
        = Topology.Open_polyline)
      "open U Torus rows were not open polylines"
  done

let check_uv_normals_and_winding () =
  let geometry = Ops.torus ~connectivity:Ops.Torus_quads
      ~normals:Ops.Torus_vertex_normals ~uv_attribute:"uv"
      ~rows:16 ~columns:8 ~major_radius:3. ~minor_radius:1. () |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" geometry = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" geometry <> None)
    "Torus vertex-normal ownership";
  let uv = float2_attribute geometry Attribute.Vertex "uv"
  and normal = float3_attribute geometry Attribute.Vertex "N"
  and point = positions geometry
  and topology = Topology.Private.view (Geometry.topology geometry) in
  for primitive = 0 to Geometry.primitive_count geometry - 1 do
    let first = topology.primitive_offsets.(primitive)
    and last = topology.primitive_offsets.(primitive + 1) in
    let minimum_u = ref infinity and maximum_u = ref neg_infinity
    and minimum_v = ref infinity and maximum_v = ref neg_infinity in
    for vertex = first to last - 1 do
      minimum_u := min !minimum_u uv.x.(vertex);
      maximum_u := max !maximum_u uv.x.(vertex);
      minimum_v := min !minimum_v uv.y.(vertex);
      maximum_v := max !maximum_v uv.y.(vertex);
      let length = sqrt ((normal.x.(vertex) *. normal.x.(vertex))
          +. (normal.y.(vertex) *. normal.y.(vertex))
          +. (normal.z.(vertex) *. normal.z.(vertex))) in
      check (near length 1.) "Torus normal is not unit length"
    done;
    check (!maximum_u -. !minimum_u <= 0.500000000001
        && !maximum_v -. !minimum_v <= 0.500000000001)
      "Torus polygon crosses a UV seam";
    let a = topology.vertex_points.(first)
    and b = topology.vertex_points.(first + 1)
    and c = topology.vertex_points.(first + 2) in
    let abx = point.x.(b) -. point.x.(a)
    and aby = point.y.(b) -. point.y.(a)
    and abz = point.z.(b) -. point.z.(a)
    and acx = point.x.(c) -. point.x.(a)
    and acy = point.y.(c) -. point.y.(a)
    and acz = point.z.(c) -. point.z.(a) in
    let nx = (aby *. acz) -. (abz *. acy)
    and ny = (abz *. acx) -. (abx *. acz)
    and nz = (abx *. acy) -. (aby *. acx) in
    check ((nx *. normal.x.(first)) +. (ny *. normal.y.(first))
        +. (nz *. normal.z.(first)) > 0.)
      "Torus polygon winding points inward"
  done;
  let point_output = Ops.torus ~connectivity:Ops.Torus_points
      ~uv_attribute:"uv" ~rows:8 ~columns:4 ~major_radius:2. ~minor_radius:1. ()
      |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "uv" point_output <> None
      && Geometry.find_attribute ~owner:Attribute.Vertex "uv" point_output = None)
    "point Torus UV ownership";
  let no_normals = Ops.torus ~connectivity:Ops.Torus_rows
      ~normals:Ops.Torus_no_normals ~rows:8 ~columns:4
      ~major_radius:2. ~minor_radius:1. () |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" no_normals = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" no_normals = None)
    "Torus no-normal mode emitted N"

let check_orientation_and_rotation () =
  let bounds orientation = Ops.torus ~connectivity:Ops.Torus_points
      ~orientation ~rows:16 ~columns:8 ~major_radius:3. ~minor_radius:1. ()
      |> get_ok |> Analysis.bounds |> Option.get in
  let x = bounds Ops.Torus_x and y = bounds Ops.Torus_y
  and z = bounds Ops.Torus_z
  and custom = bounds (Ops.Torus_axis (Vec3.create 0. max_float 0.)) in
  check (near x.size.x 2. && near x.size.y 8. && near x.size.z 8.
      && near y.size.x 8. && near y.size.y 2. && near y.size.z 8.
      && near z.size.x 8. && near z.size.y 8. && near z.size.z 2.
      && near custom.size.x y.size.x && near custom.size.y y.size.y
      && near custom.size.z y.size.z)
    "Torus orientation bounds";
  let rotation = Vec3.create 0.3 0.5 0.7 in
  let first order = Ops.torus ~connectivity:Ops.Torus_points
      ~rotation ~rotation_order:order ~center:(Vec3.create 3. (-2.) 5.)
      ~uniform_scale:2. ~rows:8 ~columns:4
      ~major_radius:2. ~minor_radius:1. () |> get_ok |> positions
      |> fun values -> Vec3.create values.x.(0) values.y.(0) values.z.(0) in
  let source = Vec3.create 6. 0. 0. in
  let cases = [
    Ops.Torus_xyz, Mat4.mul (Mat4.rotation_z rotation.z)
      (Mat4.mul (Mat4.rotation_y rotation.y) (Mat4.rotation_x rotation.x));
    Ops.Torus_xzy, Mat4.mul (Mat4.rotation_y rotation.y)
      (Mat4.mul (Mat4.rotation_z rotation.z) (Mat4.rotation_x rotation.x));
    Ops.Torus_yxz, Mat4.mul (Mat4.rotation_z rotation.z)
      (Mat4.mul (Mat4.rotation_x rotation.x) (Mat4.rotation_y rotation.y));
    Ops.Torus_yzx, Mat4.mul (Mat4.rotation_x rotation.x)
      (Mat4.mul (Mat4.rotation_z rotation.z) (Mat4.rotation_y rotation.y));
    Ops.Torus_zxy, Mat4.mul (Mat4.rotation_y rotation.y)
      (Mat4.mul (Mat4.rotation_x rotation.x) (Mat4.rotation_z rotation.z));
    Ops.Torus_zyx, Mat4.mul (Mat4.rotation_x rotation.x)
      (Mat4.mul (Mat4.rotation_y rotation.y) (Mat4.rotation_z rotation.z)) ] in
  List.iter (fun (order, matrix) ->
    let expected = Mat4.transform_point matrix source
        |> fun value -> Vec3.add value (Vec3.create 3. (-2.) 5.) in
    let actual = first order in
    check (near actual.x expected.x && near actual.y expected.y
        && near actual.z expected.z)
      "Torus Euler rotation order") cases;
  let rotated = Ops.torus ~connectivity:Ops.Torus_points ~rotation
      ~rotation_order:Ops.Torus_xyz ~rows:8 ~columns:4
      ~major_radius:2. ~minor_radius:1. () |> get_ok in
  let rotated_n = float3_attribute rotated Attribute.Point "N" in
  let expected_n = Mat4.transform_direction (List.assoc Ops.Torus_xyz cases)
      Vec3.unit_x in
  check (near rotated_n.x.(0) expected_n.x && near rotated_n.y.(0) expected_n.y
      && near rotated_n.z.(0) expected_n.z)
    "Torus rotated normal does not follow its frame";
  let x_axis = Ops.torus ~connectivity:Ops.Torus_points
      ~orientation:Ops.Torus_x ~rows:8 ~columns:4
      ~major_radius:2. ~minor_radius:1. () |> get_ok in
  let x_axis_n = float3_attribute x_axis Attribute.Point "N" in
  check (near x_axis_n.x.(0) 0. && near x_axis_n.y.(0) 1.
      && near x_axis_n.z.(0) 0.)
    "Torus X-axis normal frame"

let check_validation () =
  let make ?grain ?connectivity ?normals ?orientation ?center ?rotation
      ?uniform_scale ?u_start ?u_end ?v_start ?v_end ?u_wrap ?v_wrap
      ?u_end_caps ?v_end_cap ?uv_attribute ?rows ?columns ?(major_radius = 2.)
      ?(minor_radius = 1.) () =
    Ops.torus ?grain ?connectivity ?normals ?orientation ?center ?rotation
      ?uniform_scale ?u_start ?u_end ?v_start ?v_end ?u_wrap ?v_wrap
      ?u_end_caps ?v_end_cap ?uv_attribute ?rows ?columns
      ~major_radius ~minor_radius () in
  expect_code "invalid_parameter" (make ~grain:0 ());
  expect_code "invalid_parameter" (make ~rows:2 ());
  expect_code "invalid_parameter" (make ~columns:2 ());
  expect_code "invalid_parameter" (make ~major_radius:0. ());
  expect_code "invalid_parameter" (make ~minor_radius:Float.nan ());
  expect_code "invalid_parameter" (make ~uniform_scale:0. ());
  expect_code "invalid_parameter" (make ~u_end:0. ());
  expect_code "invalid_parameter" (make ~v_start:Float.infinity ());
  expect_code "invalid_parameter"
    (make ~center:(Vec3.create max_float 0. 0.) ~major_radius:max_float ());
  expect_code "invalid_parameter"
    (make ~rotation:(Vec3.create Float.nan 0. 0.) ());
  expect_code "invalid_parameter"
    (make ~orientation:(Ops.Torus_axis Vec3.zero) ());
  expect_code "invalid_parameter" (make ~uv_attribute:"N" ());
  expect_code "invalid_parameter"
    (make ~connectivity:Ops.Torus_points ~normals:Ops.Torus_vertex_normals ());
  expect_code "invalid_parameter"
    (make ~connectivity:Ops.Torus_rows ~u_end_caps:true ~u_wrap:false ());
  expect_code "invalid_parameter" (make ~u_end_caps:true ());
  expect_code "invalid_parameter" (make ~v_end_cap:true ());
  expect_code "invalid_parameter"
    (make ~connectivity:Ops.Torus_quads ~u_wrap:false ~v_wrap:false
       ~v_end_cap:true ~v_start:0. ~v_end:(2. *. Float.pi) ());
  expect_code "invalid_parameter"
    (make ~connectivity:Ops.Torus_quads ~u_wrap:false ~v_wrap:false
       ~u_end_caps:true ~columns:2 ());
  expect_code "invalid_parameter" (make ~rows:max_int ());
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled"
    (Ops.torus ~cancel:cancelled ~rows:1_000 ~columns:500
       ~major_radius:2. ~minor_radius:1. ())

let check_parallel_exact () =
  let run domains make = Parallel.run ~domains (fun () -> make () |> get_ok) in
  let cases = [
    (fun () -> Ops.torus ~grain:1024 ~connectivity:Ops.Torus_triangles
      ~rows:256 ~columns:128 ~major_radius:3. ~minor_radius:1. ());
    (fun () -> Ops.torus ~grain:1024
      ~connectivity:Ops.Torus_alternating_triangles
      ~normals:Ops.Torus_vertex_normals ~uv_attribute:"uv"
      ~orientation:(Ops.Torus_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7) ~rotation_order:Ops.Torus_yzx
      ~u_start:4.8 ~u_end:(-0.7) ~v_start:(-1.2) ~v_end:2.1
      ~u_wrap:false ~v_wrap:false ~u_end_caps:true ~v_end_cap:true
      ~rows:256 ~columns:128 ~major_radius:3. ~minor_radius:1. ());
    (fun () -> Ops.torus ~grain:1024 ~connectivity:Ops.Torus_quads
      ~normals:Ops.Torus_vertex_normals ~uv_attribute:"uv"
      ~rows:256 ~columns:128 ~major_radius:3. ~minor_radius:1. ());
    (fun () -> Ops.torus ~grain:1024
      ~connectivity:Ops.Torus_rows_and_columns
      ~normals:Ops.Torus_vertex_normals ~uv_attribute:"uv"
      ~rows:256 ~columns:128 ~major_radius:3. ~minor_radius:1. ());
    (fun () -> Ops.torus ~grain:1024 ~connectivity:Ops.Torus_points
      ~uv_attribute:"uv" ~rows:256 ~columns:128
      ~major_radius:3. ~minor_radius:1. ()) ] in
  List.iter (fun make ->
    let one = run 1 make and many = run 4 make in
    check (equal_geometry one many)
      "one-domain and four-domain Torus geometry differ") cases

let () =
  check_default_and_connectivity ();
  check_open_sweeps_caps_and_bridge ();
  check_uv_normals_and_winding ();
  check_orientation_and_rotation ();
  check_validation ();
  check_parallel_exact ();
  print_endline "Torus tests passed"
