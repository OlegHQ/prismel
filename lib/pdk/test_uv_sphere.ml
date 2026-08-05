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
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)

let check_default_compatibility () =
  let geometry = Ops.uv_sphere ~segments:4 ~rings:2 ~radius:2. () |> get_ok in
  let point = positions geometry
  and topology = Topology.Private.view (Geometry.topology geometry)
  and normal = float3_attribute geometry Attribute.Point "N" in
  check (Geometry.point_count geometry = 6
      && Geometry.vertex_count geometry = 24
      && Geometry.primitive_count geometry = 8)
    "default UV Sphere cardinality changed";
  check (point.x.(0) = 0. && point.y.(0) = 2. && point.z.(0) = 0.
      && point.x.(5) = 0. && point.y.(5) = -2. && point.z.(5) = 0.)
    "default UV Sphere poles changed";
  check (Array.sub topology.vertex_points 0 6 = [|0; 2; 1; 0; 3; 2|]
      && Array.sub topology.vertex_points 12 6 = [|5; 1; 2; 5; 2; 3|]
      && topology.primitive_offsets = Array.init 9 (fun index -> index * 3))
    "default UV Sphere topology/order changed";
  check (normal.x = Array.map (fun value -> value /. 2.) point.x
      && normal.y = Array.map (fun value -> value /. 2.) point.y
      && normal.z = Array.map (fun value -> value /. 2.) point.z)
    "default UV Sphere normals changed"

let check_connectivity_and_poles () =
  let make ?(unique = false) ?(triangular = true) connectivity =
    Ops.uv_sphere ~connectivity ~unique_points_per_pole:unique
      ~triangular_poles:triangular ~segments:8 ~rings:4 ~radius:1. () |> get_ok in
  let triangles = make Ops.Sphere_triangles
  and alternating = make Ops.Sphere_alternating_triangles
  and quads = make Ops.Sphere_quads
  and degenerate_quads = make ~triangular:false Ops.Sphere_quads
  and unique_quads = make ~unique:true ~triangular:false Ops.Sphere_quads
  and rows = make Ops.Sphere_rows
  and columns = make Ops.Sphere_columns
  and both = make Ops.Sphere_rows_and_columns
  and points = make Ops.Sphere_points
  and unique_points = make ~unique:true Ops.Sphere_points in
  check (Geometry.point_count triangles = 26
      && Geometry.vertex_count triangles = 144
      && Geometry.primitive_count triangles = 48)
    "triangle UV Sphere cardinality";
  check (Geometry.point_count alternating = 26
      && Geometry.vertex_count alternating = 144
      && Geometry.primitive_count alternating = 48)
    "alternating UV Sphere cardinality";
  check (Geometry.point_count quads = 26 && Geometry.vertex_count quads = 112
      && Geometry.primitive_count quads = 32)
    "triangular-pole quad UV Sphere cardinality";
  check (Geometry.vertex_count degenerate_quads = 128
      && Geometry.primitive_count degenerate_quads = 32)
    "logical-quad pole cardinality";
  let shared_topology = Topology.Private.view (Geometry.topology degenerate_quads)
  and unique_topology = Topology.Private.view (Geometry.topology unique_quads) in
  check (Array.sub shared_topology.vertex_points 0 4 = [|0; 0; 2; 1|]
      && Geometry.point_count unique_quads = 40
      && Array.sub unique_topology.vertex_points 0 4 = [|0; 1; 9; 8|])
    "shared/unique logical-quad pole topology";
  let rendered_quads = Prismel_mesh.to_mesh degenerate_quads |> get_ok in
  check (Mesh.index_count rendered_quads = 144)
    "logical pole quads failed the terminal mesh bridge";
  check (Geometry.point_count rows = 24 && Geometry.vertex_count rows = 24
      && Geometry.primitive_count rows = 3)
    "row-curve UV Sphere cardinality";
  check (Geometry.point_count columns = 26 && Geometry.vertex_count columns = 40
      && Geometry.primitive_count columns = 8)
    "column-curve UV Sphere cardinality";
  check (Geometry.point_count both = 26 && Geometry.vertex_count both = 64
      && Geometry.primitive_count both = 11)
    "combined-curve UV Sphere cardinality";
  check (Geometry.point_count points = 26 && Geometry.vertex_count points = 0
      && Geometry.point_count unique_points = 40)
    "point UV Sphere pole cardinality";
  for primitive = 0 to Geometry.primitive_count both - 1 do
    check (Topology.primitive_kind (Geometry.topology both) primitive
        = Topology.Open_polyline)
      "row/column sphere emitted a closed curve"
  done;
  let regular_topology = Topology.Private.view (Geometry.topology triangles)
  and alternating_topology = Topology.Private.view (Geometry.topology alternating) in
  check (regular_topology.vertex_points <> alternating_topology.vertex_points)
    "alternating UV Sphere collapsed to regular triangulation"

let check_uv_normals_and_winding () =
  let geometry = Ops.uv_sphere ~connectivity:Ops.Sphere_quads
      ~unique_points_per_pole:true ~triangular_poles:false
      ~normals:Ops.Sphere_vertex_normals ~uv_attribute:"uv"
      ~radius_x:2. ~radius_y:1. ~radius_z:0.5
      ~segments:16 ~rings:8 ~radius:1. () |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" geometry = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" geometry <> None)
    "UV Sphere vertex-normal ownership";
  let uv = float2_attribute geometry Attribute.Vertex "uv"
  and normal = float3_attribute geometry Attribute.Vertex "N"
  and point = positions geometry
  and topology = Topology.Private.view (Geometry.topology geometry) in
  let rendered = Prismel_mesh.to_mesh geometry |> get_ok in
  check (Mesh.index_count rendered = 16 * ((2 * (8 - 2)) + 2) * 3
      && Mesh.normals rendered <> [] && Mesh.tex_coords rendered <> [])
    "attributed logical-pole quads failed terminal triangulation";
  for vertex = 0 to Geometry.vertex_count geometry - 1 do
    let length = sqrt ((normal.x.(vertex) *. normal.x.(vertex))
        +. (normal.y.(vertex) *. normal.y.(vertex))
        +. (normal.z.(vertex) *. normal.z.(vertex))) in
    check (near length 1. && uv.x.(vertex) >= 0. && uv.x.(vertex) <= 1.
        && uv.y.(vertex) >= 0. && uv.y.(vertex) <= 1.)
      "UV Sphere emitted invalid UV/normal"
  done;
  for primitive = 0 to Geometry.primitive_count geometry - 1 do
    let first = topology.primitive_offsets.(primitive)
    and last = topology.primitive_offsets.(primitive + 1) in
    let minimum = ref infinity and maximum = ref neg_infinity in
    for vertex = first to last - 1 do
      minimum := min !minimum uv.x.(vertex);
      maximum := max !maximum uv.x.(vertex)
    done;
    check (!maximum -. !minimum <= 0.500000000001)
      "UV Sphere primitive crosses its UV seam";
    let nx = ref 0. and ny = ref 0. and nz = ref 0.
    and cx = ref 0. and cy = ref 0. and cz = ref 0. in
    for vertex = first to last - 1 do
      let next = if vertex + 1 = last then first else vertex + 1 in
      let a = topology.vertex_points.(vertex)
      and b = topology.vertex_points.(next) in
      nx := !nx +. ((point.y.(a) -. point.y.(b))
          *. (point.z.(a) +. point.z.(b)));
      ny := !ny +. ((point.z.(a) -. point.z.(b))
          *. (point.x.(a) +. point.x.(b)));
      nz := !nz +. ((point.x.(a) -. point.x.(b))
          *. (point.y.(a) +. point.y.(b)));
      cx := !cx +. point.x.(a); cy := !cy +. point.y.(a);
      cz := !cz +. point.z.(a)
    done;
    check ((!nx *. !cx) +. (!ny *. !cy) +. (!nz *. !cz) > 0.)
      "UV Sphere polygon winding points inward"
  done;
  let points = Ops.uv_sphere ~connectivity:Ops.Sphere_points
      ~unique_points_per_pole:true ~uv_attribute:"uv" ~segments:8 ~rings:4
      ~radius:1. () |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "uv" points <> None
      && Geometry.find_attribute ~owner:Attribute.Vertex "uv" points = None)
    "point UV Sphere UV ownership";
  let no_normals = Ops.uv_sphere ~connectivity:Ops.Sphere_rows
      ~normals:Ops.Sphere_no_normals ~segments:8 ~rings:4 ~radius:1. ()
      |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" no_normals = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" no_normals = None)
    "UV Sphere no-normal mode emitted N";
  let analytic = Ops.uv_sphere ~connectivity:Ops.Sphere_points
      ~radius_x:2. ~radius_y:1. ~radius_z:0.5
      ~segments:8 ~rings:4 ~radius:1. () |> get_ok in
  let analytic_n = float3_attribute analytic Attribute.Point "N" in
  check (near analytic_n.x.(1) (1. /. sqrt 5.)
      && near analytic_n.y.(1) (2. /. sqrt 5.)
      && near analytic_n.z.(1) 0.)
    "ellipsoid inverse-radius normal is incorrect";
  let extreme = Ops.uv_sphere ~connectivity:Ops.Sphere_points
      ~radius_x:Float.min_float ~radius_y:max_float ~radius_z:max_float
      ~segments:8 ~rings:4 ~radius:1. () |> get_ok in
  let extreme_n = float3_attribute extreme Attribute.Point "N" in
  for point = 0 to Geometry.point_count extreme - 1 do
    let length = sqrt ((extreme_n.x.(point) *. extreme_n.x.(point))
        +. (extreme_n.y.(point) *. extreme_n.y.(point))
        +. (extreme_n.z.(point) *. extreme_n.z.(point))) in
    check (Float.is_finite length && near length 1.)
      "extreme finite ellipsoid produced an invalid normal"
  done

let check_transform_and_orientation () =
  let bounds orientation = Ops.uv_sphere ~connectivity:Ops.Sphere_quads
      ~orientation ~radius_x:2. ~radius_y:3. ~radius_z:4.
      ~segments:16 ~rings:8 ~radius:1. () |> get_ok
      |> Analysis.bounds |> Option.get in
  let x = bounds Ops.Sphere_x and y = bounds Ops.Sphere_y
  and z = bounds Ops.Sphere_z
  and custom = bounds (Ops.Sphere_axis (Vec3.create 0. max_float 0.)) in
  check (near x.size.x 6. && near x.size.y 4. && near x.size.z 8.
      && near y.size.x 4. && near y.size.y 6. && near y.size.z 8.
      && near z.size.x 4. && near z.size.y 8. && near z.size.z 6.
      && near custom.size.x y.size.x && near custom.size.y y.size.y
      && near custom.size.z y.size.z)
    "UV Sphere orientation/radii bounds";
  let rotation = Vec3.create 0.3 0.5 0.7 in
  let first order = Ops.uv_sphere ~connectivity:Ops.Sphere_points
      ~rotation ~rotation_order:order ~center:(Vec3.create 3. (-2.) 5.)
      ~uniform_scale:2. ~segments:8 ~rings:4 ~radius:1. () |> get_ok
      |> positions |> fun values ->
      Vec3.create values.x.(0) values.y.(0) values.z.(0) in
  let source = Vec3.create 0. 2. 0. in
  let cases = [
    Ops.Sphere_xyz,
      Mat4.mul (Mat4.rotation_z rotation.z)
        (Mat4.mul (Mat4.rotation_y rotation.y) (Mat4.rotation_x rotation.x));
    Ops.Sphere_xzy,
      Mat4.mul (Mat4.rotation_y rotation.y)
        (Mat4.mul (Mat4.rotation_z rotation.z) (Mat4.rotation_x rotation.x));
    Ops.Sphere_yxz,
      Mat4.mul (Mat4.rotation_z rotation.z)
        (Mat4.mul (Mat4.rotation_x rotation.x) (Mat4.rotation_y rotation.y));
    Ops.Sphere_yzx,
      Mat4.mul (Mat4.rotation_x rotation.x)
        (Mat4.mul (Mat4.rotation_z rotation.z) (Mat4.rotation_y rotation.y));
    Ops.Sphere_zxy,
      Mat4.mul (Mat4.rotation_y rotation.y)
        (Mat4.mul (Mat4.rotation_x rotation.x) (Mat4.rotation_z rotation.z));
    Ops.Sphere_zyx,
      Mat4.mul (Mat4.rotation_x rotation.x)
        (Mat4.mul (Mat4.rotation_y rotation.y) (Mat4.rotation_z rotation.z)) ] in
  List.iter (fun (order, matrix) ->
    let expected = Mat4.transform_point matrix source
        |> fun value -> Vec3.add value (Vec3.create 3. (-2.) 5.) in
    let actual = first order in
    check (near actual.x expected.x && near actual.y expected.y
        && near actual.z expected.z)
      "UV Sphere Euler rotation order") cases;
  let actual = first Ops.Sphere_xyz and other = first Ops.Sphere_zyx in
  check (not (near actual.x other.x && near actual.y other.y
      && near actual.z other.z))
    "UV Sphere rotation orders collapsed"

let check_validation () =
  expect_code "invalid_parameter" (Ops.uv_sphere ~grain:0 ~radius:1. ());
  expect_code "invalid_parameter" (Ops.uv_sphere ~segments:2 ~radius:1. ());
  expect_code "invalid_parameter" (Ops.uv_sphere ~rings:1 ~radius:1. ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~segments:max_int ~radius:1. ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~rings:max_int ~radius:1. ());
  expect_code "invalid_parameter" (Ops.uv_sphere ~radius:Float.nan ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~radius_x:(-1.) ~radius:1. ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~uniform_scale:0. ~radius:1. ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~center:(Vec3.create Float.nan 0. 0.) ~radius:1. ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~rotation:(Vec3.create Float.infinity 0. 0.) ~radius:1. ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~orientation:(Ops.Sphere_axis Vec3.zero) ~radius:1. ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~orientation:(Ops.Sphere_axis
       (Vec3.create Float.nan 0. 0.)) ~radius:1. ());
  expect_code "invalid_parameter" (Ops.uv_sphere ~uv_attribute:"N" ~radius:1. ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~connectivity:Ops.Sphere_points
       ~normals:Ops.Sphere_vertex_normals ~radius:1. ());
  expect_code "invalid_parameter"
    (Ops.uv_sphere ~center:(Vec3.create max_float 0. 0.)
       ~radius:max_float ());
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled"
    (Ops.uv_sphere ~cancel:cancelled ~segments:1_000 ~rings:500 ~radius:1. ())

let check_parallel_exact () =
  let run domains make = Parallel.run ~domains (fun () -> make () |> get_ok) in
  let cases = [
    (fun () -> Ops.uv_sphere ~grain:1024
      ~connectivity:Ops.Sphere_triangles ~segments:256 ~rings:128 ~radius:2. ());
    (fun () -> Ops.uv_sphere ~grain:1024
      ~connectivity:Ops.Sphere_alternating_triangles
      ~unique_points_per_pole:true ~normals:Ops.Sphere_vertex_normals
      ~uv_attribute:"uv" ~orientation:(Ops.Sphere_axis
        (Vec3.create 1. 2. 3.)) ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7) ~rotation_order:Ops.Sphere_yzx
      ~radius_x:3. ~radius_y:2. ~radius_z:1. ~segments:256 ~rings:128
      ~radius:1. ());
    (fun () -> Ops.uv_sphere ~grain:1024 ~connectivity:Ops.Sphere_quads
      ~triangular_poles:false ~uv_attribute:"uv" ~segments:256 ~rings:128
      ~radius:2. ());
    (fun () -> Ops.uv_sphere ~grain:1024
      ~connectivity:Ops.Sphere_rows_and_columns
      ~normals:Ops.Sphere_vertex_normals ~uv_attribute:"uv"
      ~segments:256 ~rings:128 ~radius:2. ());
    (fun () -> Ops.uv_sphere ~grain:1024 ~connectivity:Ops.Sphere_points
      ~unique_points_per_pole:true ~uv_attribute:"uv"
      ~segments:256 ~rings:128 ~radius:2. ()) ] in
  List.iter (fun make ->
    let one = run 1 make and many = run 4 make in
    check (equal_geometry one many)
      "one-domain and four-domain UV Sphere geometry differ") cases

let () =
  check_default_compatibility ();
  check_connectivity_and_poles ();
  check_uv_normals_and_winding ();
  check_transform_and_orientation ();
  check_validation ();
  check_parallel_exact ();
  print_endline "UV Sphere tests passed"
