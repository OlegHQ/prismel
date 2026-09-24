open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error error -> fail (Error.to_string error)
let get_string = function Ok value -> value | Error message -> fail message
let near ?(epsilon = 1e-10) left right = abs_float (left -. right) <= epsilon

let geometry ?(attributes = []) ?(groups = []) points triangles =
  let points = Array.of_list points and triangles = Array.of_list triangles in
  let point_count = Array.length points and primitive_count = Array.length triangles in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.map (fun (x,_,_) -> x) points)
      ~y:(Array.map (fun (_,y,_) -> y) points)
      ~z:(Array.map (fun (_,_,z) -> z) points) in
  let vertex_points = Array.make (primitive_count * 3) 0 in
  Array.iteri (fun primitive (a,b,c) ->
    vertex_points.(primitive * 3) <- a;
    vertex_points.((primitive * 3) + 1) <- b;
    vertex_points.((primitive * 3) + 2) <- c) triangles;
  let topology = Topology.create_owned ~point_count ~vertex_points
      ~primitive_offsets:(Array.init (primitive_count + 1)
        (fun primitive -> primitive * 3))
      ~primitive_kinds:(Array.make primitive_count Topology.Polygon)
      |> get_string in
  Geometry.create ~positions ~topology ~attributes ~groups () |> get_string

let octahedron ?(scale = 1.) ?(center = 0.,0.,0.) () =
  let cx,cy,cz = center in
  let p x y z = cx +. (x *. scale),cy +. (y *. scale),cz +. (z *. scale) in
  geometry [p 0. 0. 1.; p 1. 0. 0.; p 0. 1. 0.; p (-1.) 0. 0.;
    p 0. (-1.) 0.; p 0. 0. (-1.)]
    [(0,1,2);(0,2,3);(0,3,4);(0,4,1);
     (5,2,1);(5,3,2);(5,4,3);(5,1,4)]

let values name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail (name ^ " has non-float storage"))
  | None -> fail (name ^ " is missing")

let all_outputs = {
  Ops.mean = Some "mean";
  gaussian = Some "gaussian";
  minimum = Some "minimum";
  maximum = Some "maximum";
  curvedness = Some "curvedness";
  shape_index = Some "shape";
}

let test_closed_surface_and_scaling () =
  let output = Ops.measure_curvature ~grain:1 ~outputs:all_outputs
      (octahedron ()) |> get in
  let mean = values "mean" output and gaussian = values "gaussian" output
  and minimum = values "minimum" output and maximum = values "maximum" output
  and curvedness = values "curvedness" output
  and shape = values "shape" output in
  let expected_gaussian = Float.pi /. sqrt 3. in
  for point = 0 to 5 do
    check (near mean.(point) 1.) "unit octahedron mean curvature";
    check (near gaussian.(point) expected_gaussian)
      "unit octahedron Gaussian curvature";
    check (near minimum.(point) 1. && near maximum.(point) 1.)
      "unit octahedron principal curvature";
    check (near curvedness.(point) 1. && near shape.(point) 1.)
      "unit octahedron derived curvature"
  done;
  let scaled = Ops.measure_curvature ~outputs:all_outputs
      (octahedron ~scale:2. ()) |> get in
  let scaled_mean = values "mean" scaled
  and scaled_gaussian = values "gaussian" scaled in
  for point = 0 to 5 do
    check (near scaled_mean.(point) (mean.(point) /. 2.))
      "mean curvature did not scale inversely with length";
    check (near scaled_gaussian.(point) (gaussian.(point) /. 4.))
      "Gaussian curvature did not scale inversely with area"
  done;
  let translated = Ops.measure_curvature ~outputs:all_outputs
      (octahedron ~center:(1e12,-2e12,3e12) ()) |> get in
  Array.iter (fun value -> check (near ~epsilon:5e-4 value 1.)
      "large translation destabilized mean curvature") (values "mean" translated);
  Array.iter (fun value -> check
      (near ~epsilon:2e-3 value expected_gaussian)
      "large translation destabilized Gaussian curvature")
    (values "gaussian" translated);
  List.iter (fun scale ->
    let output = Ops.measure_curvature ~outputs:all_outputs
        (octahedron ~scale ()) |> get in
    Array.iter (fun value -> check
        (near ~epsilon:1e-9 (value *. scale) 1.)
        "extreme scale destabilized mean curvature") (values "mean" output);
    Array.iter (fun value -> check
        (near ~epsilon:1e-9 ((value *. scale) *. scale) expected_gaussian)
        "extreme scale destabilized Gaussian curvature")
      (values "gaussian" output)) [1e-150;1e150]

let test_orientation_and_saddle () =
  let source = octahedron () in
  let topology = Topology.Private.view (Geometry.topology source) in
  let reversed_vertices = Array.copy topology.vertex_points in
  for primitive = 0 to Geometry.primitive_count source - 1 do
    let at = primitive * 3 in
    let value = reversed_vertices.(at + 1) in
    reversed_vertices.(at + 1) <- reversed_vertices.(at + 2);
    reversed_vertices.(at + 2) <- value
  done;
  let reversed_topology = Topology.create_owned ~point_count:6
      ~vertex_points:reversed_vertices
      ~primitive_offsets:(Array.copy topology.primitive_offsets)
      ~primitive_kinds:(Array.make 8 Topology.Polygon) |> get_string in
  let reversed = Geometry.create ~positions:(Geometry.positions source)
      ~topology:reversed_topology () |> get_string
      |> Ops.measure_curvature ~outputs:all_outputs |> get in
  Array.iter (fun value -> check (near value (-1.))
      "reversed winding did not reverse signed curvature") (values "mean" reversed);
  Array.iter (fun value -> check (near value (Float.pi /. sqrt 3.))
      "reversed winding changed Gaussian curvature") (values "gaussian" reversed);
  let saddle = geometry
      [(0.,0.,0.);(1.,0.,1.);(0.,1.,-1.);(-1.,0.,1.);(0.,-1.,-1.)]
      [(0,1,2);(0,2,3);(0,3,4);(0,4,1)]
      |> Ops.measure_curvature ~boundary:Ops.Curvature_boundary_one_sided
          ~outputs:all_outputs |> get in
  check ((values "gaussian" saddle).(0) < 0.)
    "saddle center did not receive negative Gaussian curvature"

let test_boundary_smoothing_and_selection () =
  let grid = Ops.grid ~connectivity:Ops.Grid_quads ~columns:2 ~rows:2 ~size:2. ()
      |> get in
  let zero = Ops.measure_curvature ~outputs:all_outputs grid |> get in
  Array.iter (fun value -> check (near value 0.)
      "flat boundary-zero grid has nonzero curvature") (values "mean" zero);
  Array.iter (fun value -> check (near value 0.)
      "flat boundary-zero grid has nonzero Gaussian curvature")
    (values "gaussian" zero);
  let one_sided = Ops.measure_curvature
      ~boundary:Ops.Curvature_boundary_one_sided ~outputs:all_outputs grid |> get in
  check (Array.exists (fun value -> value > 0.) (values "gaussian" one_sided))
    "one-sided boundary policy did not retain boundary angle defect";
  let smoothed = Ops.measure_curvature
      ~boundary:Ops.Curvature_boundary_one_sided ~smoothing_iterations:3
      ~smoothing_strength:0.25 ~outputs:all_outputs grid |> get in
  check (Array.for_all Float.is_finite (values "gaussian" smoothed))
    "curvature smoothing produced non-finite output";
  let base = octahedron () in
  let selected = Group.init ~owner:Group.Point ~name:"selected" 6
      (fun point -> point = 0) in
  let existing = Attribute.create_owned ~owner:Attribute.Point ~name:"curvature"
      (Attribute.Float (Array.make 6 42.)) |> get_string in
  let base = Geometry.with_attribute existing base |> get_string in
  let selected_output = Ops.measure_curvature ~points:selected base |> get in
  let selected_values = values "curvature" selected_output in
  check (near selected_values.(0) 1.) "selected curvature was not written";
  for point = 1 to 5 do
    check (selected_values.(point) = 42.)
      "unselected existing curvature was changed"
  done

let test_exact_domains_and_cardinality () =
  let sphere = Ops.uv_sphere ~connectivity:Ops.Sphere_triangles
      ~segments:192 ~rings:96 ~radius:3. () |> get in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.measure_curvature ~grain:257 ~smoothing_iterations:2
        ~smoothing_strength:0.2 ~outputs:all_outputs sphere |> get) in
  let one = run 1 and four = run 4 in
  List.iter (fun name ->
    check (values name one = values name four)
      (name ^ " curvature differs across domain counts"))
    ["mean";"gaussian";"minimum";"maximum";"curvedness";"shape"];
  check (Geometry.topology one == Geometry.topology sphere
      && Geometry.positions one == Geometry.positions sphere)
    "curvature did not structurally share geometry";
  check (Geometry.point_count one = Geometry.point_count sphere)
    "curvature changed point cardinality"

let expect_invalid work message = match work () with
  | Error error when Error.code error = "invalid_curvature" -> ()
  | Error error -> fail (message ^ ": " ^ Error.to_string error)
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_validation_and_cancellation () =
  let source = octahedron () in
  expect_invalid (fun () -> Ops.measure_curvature ~grain:0 source)
    "zero grain";
  expect_invalid (fun () -> Ops.measure_curvature ~smoothing_iterations:(-1) source)
    "negative smoothing iterations";
  expect_invalid (fun () -> Ops.measure_curvature ~smoothing_strength:1.1 source)
    "invalid smoothing strength";
  expect_invalid (fun () -> Ops.measure_curvature ~outputs:{all_outputs with
      gaussian=Some "mean"} source) "duplicate output names";
  let primitive_group = Group.init ~owner:Group.Primitive ~name:"wrong" 8
      (fun _ -> true) in
  expect_invalid (fun () -> Ops.measure_curvature ~points:primitive_group source)
    "wrong selection owner";
  let wrong = Attribute.create_owned ~owner:Attribute.Point ~name:"curvature"
      (Attribute.Int (Array.make 6 0)) |> get_string in
  let wrong = Geometry.with_attribute wrong source |> get_string in
  expect_invalid (fun () -> Ops.measure_curvature wrong)
    "wrong existing output storage";
  let curve = Ops.polyline ~closed:true
      [|0.,0.,0.;1.,0.,0.;0.,1.,0.|] |> get in
  expect_invalid (fun () -> Ops.measure_curvature curve) "curve input";
  let inconsistent = geometry
      [(0.,0.,0.);(1.,0.,0.);(0.,1.,0.);(0.,-1.,0.)]
      [(0,1,2);(0,1,3)] in
  expect_invalid (fun () -> Ops.measure_curvature inconsistent)
    "inconsistent winding";
  let disconnected = geometry
      [(0.,0.,0.);(1.,0.,0.);(0.,1.,0.);(-1.,0.,0.);(0.,-1.,0.)]
      [(0,1,2);(0,3,4)] in
  expect_invalid (fun () -> Ops.measure_curvature disconnected)
    "disconnected point fans";
  let non_manifold = geometry
      [(0.,0.,0.);(1.,0.,0.);(0.,1.,0.);(0.,-1.,0.);(0.,0.,1.)]
      [(0,1,2);(1,0,3);(0,1,4)] in
  expect_invalid (fun () -> Ops.measure_curvature non_manifold)
    "non-manifold edge";
  let degenerate = geometry [(0.,0.,0.);(1.,0.,0.);(2.,0.,0.)] [(0,1,2)] in
  expect_invalid (fun () -> Ops.measure_curvature degenerate)
    "degenerate triangle";
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Ops.measure_curvature ~cancel source with
   | Error error -> check (Error.code error = "cancelled")
       "curvature cancellation code"
   | Ok _ -> fail "cancelled curvature unexpectedly succeeded")

let () =
  test_closed_surface_and_scaling ();
  test_orientation_and_saddle ();
  test_boundary_smoothing_and_selection ();
  test_exact_domains_and_cardinality ();
  test_validation_and_cancellation ();
  print_endline "curvature tests passed"
