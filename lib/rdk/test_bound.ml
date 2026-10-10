open Rays
open Rdk
open Rdk_test_support

let detail_float3 geometry name =
  match Geometry.find_attribute ~owner:Attribute.Detail name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail (name ^ " has unexpected storage"))
  | None -> fail ("missing detail float3 " ^ name)

let point_normals geometry =
  match Geometry.find_attribute ~owner:Attribute.Point "N" geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail "N has unexpected storage")
  | None -> fail "missing point normals"

let equal_geometry left right =
  let lp = positions left and rp = positions right
  and lt = Topology.Private.view (Geometry.topology left)
  and rt = Topology.Private.view (Geometry.topology right)
  and ln = point_normals left and rn = point_normals right in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && lt.primitive_kinds = rt.primitive_kinds
  && ln.x = rn.x && ln.y = rn.y && ln.z = rn.z
  && (match Geometry.find_group ~owner:Group.Primitive "bounds" left,
      Geometry.find_group ~owner:Group.Primitive "bounds" right with
      | Some left_group, Some right_group ->
          Group.cardinality left_group = Group.cardinality right_group
          && Group.cardinality left_group = Geometry.primitive_count left
      | None, None -> true | _ -> false)

let check_validation () =
  let source = Line_geometry.points [|(0.,0.,0.)|] in
  expect_code "invalid_geometry" (Bound.run source);
  expect_code "invalid_geometry" (Bound.run
      ~shape:(Bound.Bound_box { divisions = 0, 1, 1 }) source);
  expect_code "invalid_geometry" (Bound.run
      ~shape:(Bound.Bound_sphere { segments = 2; rings = 1;
        minimum_radius = -1. }) source);
  expect_code "invalid_geometry" (Bound.run
      ~lower_padding:(Vec3.create Float.nan 0. 0.) source);
  expect_code "invalid_geometry" (Bound.run ~center_attribute:"same"
      ~radii_attribute:"same" source);
  expect_code "invalid_geometry" (Bound.run ~bounds_group:"" source);
  expect_code "invalid_geometry" (Bound.run
      ~shape:(Bound.Bound_box { divisions = max_int, max_int, max_int })
      ~lower_padding:(Vec3.create 1. 1. 1.) source);
  let empty = Group.init ~owner:Group.Point ~name:"empty" 1 (fun _ -> false) in
  expect_code "invalid_geometry" (Bound.run
      ~selection:(Transform_ops.Selected_points empty) source);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled" (Bound.run ~cancel:cancelled
      ~shape:(Bound.Bound_sphere { segments = 64; rings = 32; minimum_radius = 0. })
      source)

let check_parallel_exact () =
  let source = Plane_generators.grid ~columns:500 ~rows:300 ~size:30. () |> get_ok
      |> Deform.noise_displace ~seed:929 ~amplitude:2. ~frequency:0.23 |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
    Bound.run ~grain:1024
      ~shape:(Bound.Bound_box { divisions = 256, 128, 64 })
      ~lower_padding:(Vec3.create 0.25 0.5 0.75)
      ~upper_padding:(Vec3.create 0.75 0.5 0.25)
      ~bounds_group:"bounds" source |> get_ok) in
  let one = run 1 and many = run 4 in
  check (equal_geometry one many)
    "one-domain and four-domain Bound geometry differ";
  check (Geometry.point_count one = 116_486
      && Geometry.primitive_count one = 229_376)
    "Bound scale cardinality";
  let run_sphere domains = Parallel.run ~domains (fun () ->
    Bound.run ~grain:1024 ~shape:(Bound.Bound_sphere {
        segments = 512; rings = 256; minimum_radius = 0. })
      ~bounds_group:"bounds" source |> get_ok) in
  let sphere_one = run_sphere 1 and sphere_many = run_sphere 4 in
  check (equal_geometry sphere_one sphere_many)
    "one-domain and four-domain Bound sphere differ";
  check (Geometry.point_count sphere_one = 130_562
      && Geometry.primitive_count sphere_one = 261_120)
    "Bound sphere scale cardinality"

let run () =
  check_validation ();
  check_parallel_exact ();
  print_endline "bound tests passed"
