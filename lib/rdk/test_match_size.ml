open Rays
open Rdk
open Rdk_test_support

let normal_values owner geometry =
  match Geometry.find_attribute ~owner "N" geometry with
  | Some attribute ->
      (match Attribute.get (Attribute.normal ~owner) attribute with
       | Some values -> Packed.Float3.Private.view values
       | None -> fail "N has incompatible storage")
  | None -> fail "N is missing"

let equal_storage left right = match Attribute.storage left, Attribute.storage right with
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
  && List.equal equal_attribute (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group (Geometry.edge_groups left)
       (Geometry.edge_groups right)

let with_group group geometry = Geometry.with_group group geometry |> Result.get_ok

let check_normals () =
  let source = Line_geometry.polyline [|(0.,0.,0.); (1.,1.,0.)|] |> get_ok in
  let root = 1. /. sqrt 2. in
  let normal owner = Attribute.create_key_owned (Attribute.normal ~owner)
      (Packed.Float3.Private.of_owned_exn ~x:[|root; root|]
         ~y:[|root; root|] ~z:[|0.; 0.|]) |> Result.get_ok in
  let selected = Group.init ~owner:Group.Point ~name:"first" 2
      (fun point -> point = 0) in
  let source = source |> Geometry.with_attribute (normal Attribute.Point)
      |> Result.get_ok |> Geometry.with_attribute (normal Attribute.Vertex)
      |> Result.get_ok |> with_group selected in
  let output = Match_size.run ~fit:Match_size.Stretch
      ~selection:(Transform_ops.Selected_points selected)
      ~translate_axes:(false, false, false)
      ~target_center:Vec3.zero ~target_size:(Vec3.create 2. 1. 1.) source
      |> get_ok in
  let expected_x = 1. /. sqrt 5. and expected_y = 2. /. sqrt 5. in
  List.iter (fun owner ->
    let normals = normal_values owner output in
    check (near normals.x.(0) expected_x && near normals.y.(0) expected_y
        && near normals.x.(1) root && near normals.y.(1) root)
      "selected inverse-transpose normal transform")
    [Attribute.Point; Attribute.Vertex]

let check_validation () =
  let source = Box_generator.box ~size:(Vec3.create 1. 1. 1.) () |> get_ok
  and target = Box_generator.box ~size:(Vec3.create 2. 2. 2.) () |> get_ok in
  expect_code "invalid_geometry" (Match_size.run ~grain:0 ~target source);
  expect_code "invalid_geometry" (Match_size.run
      ~justify:(Vec3.create 2. 0. 0.) ~target source);
  expect_code "invalid_geometry" (Match_size.run
      ~offset:(Vec3.create Float.nan 0. 0.) ~target source);
  expect_code "invalid_geometry" (Match_size.run ~scale:(-1.) ~target source);
  expect_code "invalid_geometry" (Match_size.run
      ~target_size:(Vec3.create 1. (-1.) 1.) source);
  expect_code "invalid_geometry" (Match_size.run ~target
      ~target_center:Vec3.zero source);
  let target_points = Group.init ~owner:Group.Point ~name:"target" 24
      (fun point -> point = 0) in
  expect_code "invalid_geometry" (Match_size.run
      ~target_selection:(Transform_ops.Selected_points target_points) source);
  let malformed = Group.init ~owner:Group.Point ~name:"bad" 1 (fun _ -> true) in
  expect_code "invalid_geometry" (Match_size.run
      ~selection:(Transform_ops.Selected_points malformed) ~target source);
  let empty = Group.init ~owner:Group.Point ~name:"empty" 24 (fun _ -> false) in
  expect_code "invalid_geometry" (Match_size.run
      ~source_selection:(Transform_ops.Selected_points empty) ~target source);
  expect_code "invalid_geometry" (Match_size.run ~fit:Match_size.Match_area source);
  expect_code "invalid_geometry" (Match_size.run ~fit:Match_size.Match_x
      (Line_geometry.points [|(0.,0.,0.); (0.,1.,0.)|]));
  let points = Group.init ~owner:Group.Point ~name:"points" 24 (fun _ -> true) in
  expect_code "invalid_geometry" (Match_size.run ~fit:Match_size.Match_area
      ~source_selection:(Transform_ops.Selected_points points) ~target source);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled" (Match_size.run ~cancel:cancelled ~target source)

let check_parallel_exact () =
  let source = Plane_generators.grid ~columns:800 ~rows:600 ~size:30. () |> get_ok
      |> Deform.noise_displace ~seed:934 ~amplitude:1.75 ~frequency:0.21 |> get_ok
      |> Normal_ops.run |> get_ok in
  let target = Box_generator.box ~size:(Vec3.create 8. 5. 12.) () |> get_ok
      |> Transform_ops.transform (Mat4.translation (Vec3.create 3. 7. (-2.))) in
  let run domains = Parallel.run ~domains (fun () ->
    Match_size.run ~grain:1024 ~fit:Match_size.Stretch
      ~scale_axes:(true, false, true)
      ~justify:(Vec3.create (-1.) 0. 1.)
      ~target_justify:(Vec3.create 1. (-1.) 0.)
      ~offset:(Vec3.create 0.25 0.5 (-0.75)) ~target source |> get_ok) in
  let one = run 1 and many = run 4 in
  check (equal_geometry one many)
    "one-domain and four-domain Match Size geometry differ";
  check (Geometry.point_count one = 481_401
      && Geometry.primitive_count one = 960_000)
    "Match Size scale fixture cardinality";
  let faces = Group.init ~owner:Group.Primitive ~name:"alternating_faces"
      (Geometry.primitive_count source) (fun primitive -> primitive mod 3 <> 0) in
  let run_selected domains = Parallel.run ~domains (fun () ->
    Match_size.run ~grain:1024 ~selection:(Transform_ops.Selected_primitives faces)
      ~source_selection:(Transform_ops.Selected_primitives faces) ~fit:Match_size.Contain
      ~target source |> get_ok) in
  let selected_one = run_selected 1 and selected_many = run_selected 4 in
  check (equal_geometry selected_one selected_many)
    "one-domain and four-domain incidence-selected Match Size differ"

let run () =
  check_normals ();
  check_validation ();
  check_parallel_exact ();
  print_endline "match size tests passed"
