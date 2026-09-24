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

let equal_geometry left right =
  let lp = positions left and rp = positions right
  and lt = Topology.Private.view (Geometry.topology left)
  and rt = Topology.Private.view (Geometry.topology right) in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && lt.point_count = rt.point_count
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && List.equal (fun left right ->
       Attribute.owner left = Attribute.owner right
       && String.equal (Attribute.name left) (Attribute.name right)
       && String.equal (Attribute.kind_name left) (Attribute.kind_name right)
       && equal_storage left right) (Geometry.attributes left)
       (Geometry.attributes right)
  && List.equal (fun left right ->
       Group.owner left = Group.owner right
       && String.equal (Group.name left) (Group.name right)
       && Group.length left = Group.length right
       && begin
         let equal = ref true in
         for element = 0 to Group.length left - 1 do
           if Group.mem element left <> Group.mem element right then equal := false
         done;
         !equal
       end
       && Group.ordered_elements left = Group.ordered_elements right)
       (Geometry.groups left) (Geometry.groups right)

let make ?kind ?normals ?orientation ?center ?rotation ?rotation_order
    ?face_groups ?(radius = 2.) () =
  Ops.platonic ?kind ?normals ?orientation ?center ?rotation ?rotation_order
    ?face_groups ~radius () |> get_ok

let check_outward_and_regular name radius geometry =
  let point = positions geometry and topology = Geometry.topology geometry in
  let edge_length = ref None in
  for p = 0 to Geometry.point_count geometry - 1 do
    let length = sqrt ((point.x.(p) *. point.x.(p))
        +. (point.y.(p) *. point.y.(p)) +. (point.z.(p) *. point.z.(p))) in
    check (near length radius) (name ^ " circumsphere radius")
  done;
  for primitive = 0 to Geometry.primitive_count geometry - 1 do
    let first, last = Topology.primitive_vertex_range topology primitive in
    let nx = ref 0. and ny = ref 0. and nz = ref 0.
    and cx = ref 0. and cy = ref 0. and cz = ref 0. in
    for vertex = first to last - 1 do
      let next = if vertex + 1 = last then first else vertex + 1 in
      let a = Topology.point_of_vertex topology vertex
      and b = Topology.point_of_vertex topology next in
      nx := !nx +. ((point.y.(a) -. point.y.(b))
          *. (point.z.(a) +. point.z.(b)));
      ny := !ny +. ((point.z.(a) -. point.z.(b))
          *. (point.x.(a) +. point.x.(b)));
      nz := !nz +. ((point.x.(a) -. point.x.(b))
          *. (point.y.(a) +. point.y.(b)));
      cx := !cx +. point.x.(a); cy := !cy +. point.y.(a);
      cz := !cz +. point.z.(a);
      let dx = point.x.(a) -. point.x.(b)
      and dy = point.y.(a) -. point.y.(b)
      and dz = point.z.(a) -. point.z.(b) in
      let length = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
      (match !edge_length with
       | None -> edge_length := Some length
       | Some expected -> check (near expected length) (name ^ " edge length"))
    done;
    check ((!nx *. !cx) +. (!ny *. !cy) +. (!nz *. !cz) > 1e-12)
      (name ^ " inward polygon")
  done

let check_catalog () =
  let cases = [
    "tetrahedron", Ops.Platonic_tetrahedron, 4, 12, 4, 6;
    "cube", Ops.Platonic_cube, 8, 24, 6, 12;
    "octahedron", Ops.Platonic_octahedron, 6, 24, 8, 12;
    "icosahedron", Ops.Platonic_icosahedron, 12, 60, 20, 30;
    "dodecahedron", Ops.Platonic_dodecahedron, 20, 60, 12, 30;
    "soccer ball", Ops.Platonic_soccer_ball, 60, 180, 32, 90;
  ] in
  List.iter (fun (name, kind, points, vertices, primitives, edges) ->
    let geometry = make ~kind () in
    check (Geometry.point_count geometry = points
        && Geometry.vertex_count geometry = vertices
        && Geometry.primitive_count geometry = primitives)
      (name ^ " cardinality");
    check_outward_and_regular name 2. geometry;
    let index = Topology_index.create (Geometry.topology geometry) in
    check (Topology_index.edge_count index = edges) (name ^ " edge count");
    for edge = 0 to Topology_index.edge_count index - 1 do
      check (Topology_index.edge_incidence_count index edge = 2)
        (name ^ " is not closed two-manifold")
    done) cases

let check_normals_groups_colors_and_bridge () =
  let none = make ~normals:Ops.Platonic_no_normals () in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" none = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" none = None)
    "Platonic_no_normals emitted N";
  let smooth = make ~kind:Ops.Platonic_dodecahedron
      ~normals:Ops.Platonic_point_normals () in
  let point = positions smooth
  and normal = float3_attribute smooth Attribute.Point "N" in
  for p = 0 to Geometry.point_count smooth - 1 do
    check (near normal.x.(p) (point.x.(p) /. 2.)
        && near normal.y.(p) (point.y.(p) /. 2.)
        && near normal.z.(p) (point.z.(p) /. 2.))
      "Platonic point normal is not radial"
  done;
  let soccer = make ~kind:Ops.Platonic_soccer_ball
      ~normals:Ops.Platonic_vertex_normals ~face_groups:"face" () in
  let normal = float3_attribute soccer Attribute.Vertex "N"
  and color = float3_attribute soccer Attribute.Primitive "Cd" in
  for primitive = 0 to 31 do
    let expected = if primitive < 12 then 0. else 1. in
    check (near color.x.(primitive) expected
        && near color.y.(primitive) expected && near color.z.(primitive) expected)
      "soccer-ball primitive color"
  done;
  for primitive = 0 to Geometry.primitive_count soccer - 1 do
    let first, last = Topology.primitive_vertex_range
        (Geometry.topology soccer) primitive in
    for vertex = first + 1 to last - 1 do
      check (normal.x.(vertex) = normal.x.(first)
          && normal.y.(vertex) = normal.y.(first)
          && normal.z.(vertex) = normal.z.(first))
        "Platonic vertex normals are not hard per face"
    done
  done;
  (match Geometry.find_group ~owner:Group.Primitive "face_pentagons" soccer,
      Geometry.find_group ~owner:Group.Primitive "face_hexagons" soccer with
   | Some pentagons, Some hexagons ->
       check (Group.cardinality pentagons = 12 && Group.cardinality hexagons = 20)
         "soccer-ball face groups"
   | _ -> fail "soccer-ball face groups are missing");
  let mesh = Prismel_mesh.to_mesh soccer |> get_ok in
  check (Mesh.index_count mesh = 348 && Mesh.normals mesh <> [])
    "soccer ball failed terminal triangulation"

let check_orientation_rotation_and_validation () =
  let rotation = Vec3.create 0.3 0.5 0.7 and center = Vec3.create 3. (-2.) 5. in
  let source = Vec3.scale (Vec3.create 1. 1. 1.) (2. /. sqrt 3.) in
  let first order =
    let p = make ~kind:Ops.Platonic_tetrahedron ~rotation
        ~rotation_order:order ~center () |> positions in
    Vec3.create p.x.(0) p.y.(0) p.z.(0) in
  let cases = [
    Ops.Platonic_xyz, Mat4.mul (Mat4.rotation_z rotation.z)
      (Mat4.mul (Mat4.rotation_y rotation.y) (Mat4.rotation_x rotation.x));
    Ops.Platonic_xzy, Mat4.mul (Mat4.rotation_y rotation.y)
      (Mat4.mul (Mat4.rotation_z rotation.z) (Mat4.rotation_x rotation.x));
    Ops.Platonic_yxz, Mat4.mul (Mat4.rotation_z rotation.z)
      (Mat4.mul (Mat4.rotation_x rotation.x) (Mat4.rotation_y rotation.y));
    Ops.Platonic_yzx, Mat4.mul (Mat4.rotation_x rotation.x)
      (Mat4.mul (Mat4.rotation_z rotation.z) (Mat4.rotation_y rotation.y));
    Ops.Platonic_zxy, Mat4.mul (Mat4.rotation_y rotation.y)
      (Mat4.mul (Mat4.rotation_x rotation.x) (Mat4.rotation_z rotation.z));
    Ops.Platonic_zyx, Mat4.mul (Mat4.rotation_x rotation.x)
      (Mat4.mul (Mat4.rotation_y rotation.y) (Mat4.rotation_z rotation.z));
  ] in
  List.iter (fun (order, matrix) ->
    let expected = Vec3.add (Mat4.transform_point matrix source) center
    and actual = first order in
    check (near actual.x expected.x && near actual.y expected.y
        && near actual.z expected.z) "Platonic Euler rotation order") cases;
  let custom = make ~orientation:(Ops.Platonic_axis
      (Vec3.create 0. max_float 0.)) () in
  check_outward_and_regular "custom-axis tetrahedron" 2. custom;
  expect_code "invalid_parameter" (Ops.platonic ~radius:0. ());
  expect_code "invalid_parameter" (Ops.platonic ~radius:Float.nan ());
  expect_code "invalid_parameter" (Ops.platonic ~radius:max_float
      ~center:(Vec3.create max_float 0. 0.) ());
  expect_code "invalid_parameter" (Ops.platonic ~radius:1.
      ~rotation:(Vec3.create Float.infinity 0. 0.) ());
  expect_code "invalid_parameter" (Ops.platonic ~radius:1.
      ~orientation:(Ops.Platonic_axis Vec3.zero) ());
  expect_code "invalid_parameter" (Ops.platonic ~radius:1. ~face_groups:"" ());
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled" (Ops.platonic ~cancel:cancelled ~radius:1. ())

let check_parallel_exact () =
  let run domains = Parallel.run ~domains (fun () ->
    Ops.platonic ~kind:Ops.Platonic_soccer_ball
      ~normals:Ops.Platonic_vertex_normals
      ~orientation:(Ops.Platonic_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7)
      ~rotation_order:Ops.Platonic_yzx ~face_groups:"face" ~radius:4. ()
    |> get_ok) in
  check (equal_geometry (run 1) (run 4))
    "one-domain and four-domain Platonic geometry differ"

let () =
  check_catalog ();
  check_normals_groups_colors_and_bridge ();
  check_orientation_rotation_and_validation ();
  check_parallel_exact ();
  print_endline "Platonic tests passed"
