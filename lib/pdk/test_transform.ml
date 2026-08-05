open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let close left right = abs_float (left -. right) <= 1e-10

let point geometry index =
  let values = Packed.Float3.Private.view (Geometry.positions geometry) in
  values.x.(index), values.y.(index), values.z.(index)

let check_point geometry index (x, y, z) message =
  let ax, ay, az = point geometry index in
  check (close ax x && close ay y && close az z) message

let two_triangles () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;1.;1.|] ~z:(Array.make 4 0.) in
  let topology = Topology.Builder.create ~point_count:4 ~vertex_capacity:6
      ~primitive_capacity:2 () in
  Topology.Builder.add_triangle topology 0 1 2;
  Topology.Builder.add_triangle topology 0 2 3;
  let point_n = Packed.Float3.Private.of_owned_exn
      ~x:(Array.make 4 2.) ~y:(Array.make 4 2.) ~z:(Array.make 4 0.) in
  let vertex_n = Packed.Float3.Private.of_owned_exn
      ~x:(Array.make 6 0.) ~y:(Array.make 6 0.) ~z:(Array.make 6 2.) in
  let point_n = Attribute.create_key_owned (Attribute.normal ~owner:Attribute.Point)
      point_n |> Result.get_ok
  and vertex_n = Attribute.create_key_owned
      (Attribute.normal ~owner:Attribute.Vertex) vertex_n |> Result.get_ok in
  Geometry.create ~positions ~topology:(Topology.Builder.freeze topology)
    ~attributes:[point_n; vertex_n] () |> Result.get_ok

let normal owner geometry =
  match Geometry.find_attribute ~owner "N" geometry with
  | None -> fail "missing normal"
  | Some attribute ->
      (match Attribute.get (Attribute.normal ~owner) attribute with
       | Some value -> Packed.Float3.Private.view value
       | None -> fail "invalid normal storage")

let same_float_array left right =
  Array.length left = Array.length right
  && let equal = ref true in
     for index = 0 to Array.length left - 1 do
       if Int64.bits_of_float left.(index) <> Int64.bits_of_float right.(index)
       then equal := false
     done;
     !equal

let same_float3 left right =
  let left = Packed.Float3.Private.view left
  and right = Packed.Float3.Private.view right in
  same_float_array left.x right.x && same_float_array left.y right.y
  && same_float_array left.z right.z

let same_geometry left right =
  Geometry.topology left == Geometry.topology right
  && same_float3 (Geometry.positions left) (Geometry.positions right)
  && List.for_all (fun owner ->
      match Geometry.find_attribute ~owner "N" left,
          Geometry.find_attribute ~owner "N" right with
      | None, None -> true
      | Some left, Some right ->
          (match Attribute.get (Attribute.normal ~owner) left,
              Attribute.get (Attribute.normal ~owner) right with
           | Some left, Some right -> same_float3 left right
           | None, None -> true
           | None, Some _ | Some _, None -> false)
      | None, Some _ | Some _, None -> false)
      [Attribute.Point; Attribute.Vertex]

let test_composition () =
  let translation = Vec3.create 10. 0. 0. and rotation = Vec3.create 0. 0. (Float.pi /. 2.)
  and scale = Vec3.create 2. 1. 1. in
  let srt = Ops.compose_transform ~order:Ops.Transform_srt
      ~translate:translation ~rotate:rotation ~scale () |> get_ok in
  let x, y, z = Mat4.transform_point srt (Vec3.create 1. 0. 0.) |> fun v -> v.x,v.y,v.z in
  check (close x 10. && close y 2. && close z 0.)
    "Transform SRT application order";
  let trs = Ops.compose_transform ~order:Ops.Transform_trs
      ~translate:translation ~rotate:rotation ~scale () |> get_ok in
  let value = Mat4.transform_point trs (Vec3.create 1. 0. 0.) in
  check (close value.x 0. && close value.y 11. && close value.z 0.)
    "Transform TRS application order";
  let s = Mat4.scaling scale and r = Mat4.mul (Mat4.rotation_z rotation.z)
      (Mat4.mul (Mat4.rotation_y rotation.y) (Mat4.rotation_x rotation.x))
  and t = Mat4.translation translation in
  let applied matrices = List.fold_left (fun matrix operation ->
      Mat4.mul operation matrix) Mat4.identity matrices in
  List.iter (fun (order, expected) ->
    let actual = Ops.compose_transform ~order ~translate:translation
        ~rotate:rotation ~scale () |> get_ok in
    check (Mat4.nearly_equal actual (applied expected) ~eps:1e-12)
      "Transform affine-order matrix")
    [Ops.Transform_srt, [s;r;t]; Ops.Transform_str, [s;t;r];
     Ops.Transform_rst, [r;s;t]; Ops.Transform_rts, [r;t;s];
     Ops.Transform_tsr, [t;s;r]; Ops.Transform_trs, [t;r;s]];
  let rx = Mat4.rotation_x 0.2 and ry = Mat4.rotation_y (-0.3)
  and rz = Mat4.rotation_z 0.4 and angles = Vec3.create 0.2 (-0.3) 0.4 in
  List.iter (fun (rotation_order, expected) ->
    let actual = Ops.compose_transform ~rotation_order ~rotate:angles ()
        |> get_ok in
    check (Mat4.nearly_equal actual (applied expected) ~eps:1e-12)
      "Transform Euler-order matrix")
    [Ops.Transform_xyz, [rx;ry;rz]; Ops.Transform_xzy, [rx;rz;ry];
     Ops.Transform_yxz, [ry;rx;rz]; Ops.Transform_yzx, [ry;rz;rx];
     Ops.Transform_zxy, [rz;rx;ry]; Ops.Transform_zyx, [rz;ry;rx]];
  let pivoted = Ops.compose_transform ~scale:(Vec3.create 2. 2. 2.)
      ~pivot:(Vec3.create 1. 0. 0.) () |> get_ok in
  let value = Mat4.transform_point pivoted (Vec3.create 2. 0. 0.) in
  check (close value.x 3. && close value.y 0. && close value.z 0.)
    "Transform pivot";
  let forward = Ops.compose_transform ~translate:(Vec3.create 3. (-2.) 5.)
      ~rotate:(Vec3.create 0.2 (-0.4) 0.7)
      ~scale:(Vec3.create 2. 3. 4.) ~shear:(Vec3.create 0.1 (-0.2) 0.3) ()
      |> get_ok in
  let inverse = Ops.compose_transform ~translate:(Vec3.create 3. (-2.) 5.)
      ~rotate:(Vec3.create 0.2 (-0.4) 0.7)
      ~scale:(Vec3.create 2. 3. 4.) ~shear:(Vec3.create 0.1 (-0.2) 0.3)
      ~invert:true () |> get_ok in
  let source = Vec3.create (-1.2) 4.1 0.7 in
  let round_trip = Mat4.transform_point inverse (Mat4.transform_point forward source) in
  check (close source.x round_trip.x && close source.y round_trip.y
      && close source.z round_trip.z) "Transform inverse round trip";
  (match Ops.compose_transform ~scale:Vec3.zero ~invert:true () with
   | Error error -> check (Error.code error = "invalid_transform")
       "singular inverse error code"
   | Ok _ -> fail "Transform accepted singular inversion")

let test_selection_and_normals () =
  let source = two_triangles () in
  let primitive = Group.init ~grain:1 ~owner:Group.Primitive ~name:"first" 2
      (fun primitive -> primitive = 0) in
  let matrix = Ops.compose_transform ~translate:(Vec3.create 2. 0. 0.) ()
      |> get_ok in
  let moved = Ops.transform_selected ~grain:1
      ~selection:(Ops.Selected_primitives primitive) matrix source |> get_ok in
  check_point moved 0 (2.,0.,0.) "selected primitive point 0";
  check_point moved 1 (3.,0.,0.) "selected primitive point 1";
  check_point moved 2 (3.,1.,0.) "selected primitive point 2";
  check_point moved 3 (0.,1.,0.) "unselected primitive-only point";
  let vertex = Group.init ~grain:1 ~owner:Group.Vertex ~name:"corner" 6
      (fun vertex -> vertex = 4) in
  let moved_vertex = Ops.transform_selected ~grain:1
      ~selection:(Ops.Selected_vertices vertex) matrix source |> get_ok in
  check_point moved_vertex 2 (3.,1.,0.) "selected vertex referenced point";
  check_point moved_vertex 0 (0.,0.,0.) "unselected vertex point";
  let topology = Geometry.topology source in
  let index = Topology_index.create topology
  and reverse = Topology_index.Private.view (Topology_index.create topology) in
  let edge = Edge_group.init ~grain:1 ~topology ~index ~name:"edge01"
      (fun edge -> let a = reverse.edge_a.(edge) and b = reverse.edge_b.(edge) in
        (a = 0 && b = 1) || (a = 1 && b = 0)) in
  let moved_edge = Ops.transform_selected ~grain:1
      ~selection:(Ops.Selected_edges edge) matrix source |> get_ok in
  check_point moved_edge 0 (2.,0.,0.) "selected edge endpoint 0";
  check_point moved_edge 1 (3.,0.,0.) "selected edge endpoint 1";
  check_point moved_edge 2 (1.,1.,0.) "unselected edge point";
  let one_point = Group.init ~grain:1 ~owner:Group.Point ~name:"one" 4
      (fun point -> point = 1) in
  let scale = Ops.compose_transform ~scale:(Vec3.create 2. 1. 1.) () |> get_ok in
  let normalized = Ops.transform_selected ~grain:1
      ~selection:(Ops.Selected_points one_point) scale source |> get_ok in
  let normals = normal Attribute.Point normalized in
  check (close (sqrt (normals.x.(1) ** 2. +. normals.y.(1) ** 2.)) 1.
      && close normals.x.(0) 2. && close normals.y.(0) 2.)
    "selected inverse-transpose normalized normals";
  let preserved = Ops.transform_selected ~grain:1 ~preserve_normal_length:true
      ~selection:(Ops.Selected_points one_point) scale source |> get_ok in
  let normals = normal Attribute.Point preserved in
  check (close (sqrt (normals.x.(1) ** 2. +. normals.y.(1) ** 2.))
      (sqrt 8.)) "preserved selected normal length";
  let singular = Ops.compose_transform ~scale:(Vec3.create 0. 1. 1.) () |> get_ok in
  let singular = Ops.transform_selected ~grain:1 singular source |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" singular = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" singular = None)
    "singular transform invalidates normals";
  let empty = Group.init ~grain:1 ~owner:Group.Point ~name:"empty" 4
      (fun _ -> false) in
  let unchanged = Ops.transform_selected ~grain:1
      ~selection:(Ops.Selected_points empty) matrix source |> get_ok in
  check (unchanged == source) "empty Transform selection structural sharing"

let test_errors_and_parallel () =
  let source = two_triangles () in
  let invalid = Mat4.of_rows (Float.nan,0.,0.,0.) (0.,1.,0.,0.)
      (0.,0.,1.,0.) (0.,0.,0.,1.) in
  (match Ops.transform_selected invalid source with
   | Error error -> check (Error.code error = "invalid_transform")
       "non-finite matrix error code"
   | Ok _ -> fail "Transform accepted non-finite matrix");
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.transform_selected ~cancel:cancelled (Mat4.translation Vec3.unit_x)
      source with
   | Error error -> check (Error.code error = "cancelled")
       "Transform cancellation code"
   | Ok _ -> fail "cancelled Transform published geometry");
  let dense = Ops.grid ~columns:500 ~rows:300 ~size:20. () |> get_ok in
  let count = Geometry.primitive_count dense in
  let selection = Group.init ~grain:257 ~owner:Group.Primitive ~name:"bands" count
      (fun primitive -> primitive mod 7 < 3) in
  let matrix = Ops.compose_transform ~order:Ops.Transform_rts
      ~rotation_order:Ops.Transform_zyx ~translate:(Vec3.create 1. 2. 3.)
      ~rotate:(Vec3.create 0.2 0.4 (-0.1))
      ~scale:(Vec3.create 1.2 0.8 1.1) ~shear:(Vec3.create 0.1 0.2 (-0.1))
      ~pivot:(Vec3.create 0.3 (-0.2) 0.7) () |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.transform_selected ~grain:257
        ~selection:(Ops.Selected_primitives selection) matrix dense |> get_ok) in
  let one = run 1 and four = run 4 in
  check (same_geometry one four) "Transform one/four-domain exactness"

let () =
  test_composition ();
  test_selection_and_normals ();
  test_errors_and_parallel ();
  print_endline "transform tests passed"
