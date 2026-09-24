open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error error -> fail (Error.to_string error)
let get_string = function Ok value -> value | Error message -> fail message
let near ?(epsilon = 1e-10) left right = abs_float (left -. right) <= epsilon

let with_attribute name storage geometry =
  let attribute = Attribute.create_owned ~owner:Attribute.Point ~name storage
      |> get_string in
  Geometry.with_attribute attribute geometry |> get_string

let scalar name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail (name ^ " is not a scalar float field"))
  | None -> fail (name ^ " is missing")

let float3 name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail (name ^ " is not a float3 field"))
  | None -> fail (name ^ " is missing")

let grid ?(size = 2.) () =
  Ops.grid ~connectivity:Ops.Grid_quads ~columns:2 ~rows:2 ~size () |> get

let degenerate_triangle () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.|] ~y:[|0.;0.;0.|] ~z:[|0.;0.;0.|] in
  let topology = Topology.create_owned ~point_count:3 ~vertex_points:[|0;1;2|]
      ~primitive_offsets:[|0;3|] ~primitive_kinds:[|Topology.Polygon|]
      |> get_string in
  Geometry.create ~positions ~topology () |> get_string

let center_group geometry =
  Group.init ~owner:Group.Point ~name:"center" (Geometry.point_count geometry)
    (fun point -> point = 4)

let test_constant_linear_and_quadratic () =
  let source = grid () in
  let count = Geometry.point_count source in
  let source = with_attribute "constant" (Attribute.Float (Array.make count 7.))
      source in
  let constant = Ops.attribute_laplacian ~source:"constant" source |> get in
  Array.iter (fun value -> check (value = 0.)
      "cotangent Laplacian did not annihilate a constant")
    (scalar "constant_laplacian" constant);
  let positions = Packed.Float3.Private.view (Geometry.positions source) in
  let linear = Array.init count (fun point ->
      (2. *. positions.x.(point)) -. (3. *. positions.y.(point)) +. 5.)
  and quadratic = Array.init count (fun point ->
      (positions.x.(point) *. positions.x.(point))
      +. (positions.y.(point) *. positions.y.(point))) in
  let source = source |> with_attribute "linear" (Attribute.Float linear)
      |> with_attribute "quadratic" (Attribute.Float quadratic) in
  let center = center_group source in
  let linear = Ops.attribute_laplacian ~points:center ~source:"linear" source
      |> get |> scalar "linear_laplacian" in
  check (near linear.(4) 0.) "cotangent Laplacian lost planar linear precision";
  let quadratic = Ops.attribute_laplacian ~points:center ~source:"quadratic"
      source |> get |> scalar "quadratic_laplacian" in
  let quadratic_sum = Ops.attribute_laplacian ~points:center ~normalize:false
      ~source:"quadratic" ~output:"quadratic_sum" source
      |> get |> scalar "quadratic_sum" in
  check (quadratic.(4) > 0. && quadratic_sum.(4) > 0.)
    "cotangent Laplacian did not preserve positive quadratic bending";
  List.iter (fun radius ->
    let octahedron = Ops.platonic ~kind:Ops.Platonic_octahedron ~radius ()
        |> get in
    let laplacian = Ops.attribute_laplacian ~source:"P" octahedron
        |> get |> float3 "laplacian" in
    let positions = Packed.Float3.Private.view (Geometry.positions octahedron) in
    for point = 0 to Geometry.point_count octahedron - 1 do
      check (near ~epsilon:1e-8 (laplacian.x.(point) *. radius)
            (-2. *. positions.x.(point) /. radius)
          && near ~epsilon:1e-8 (laplacian.y.(point) *. radius)
            (-2. *. positions.y.(point) /. radius)
          && near ~epsilon:1e-8 (laplacian.z.(point) *. radius)
            (-2. *. positions.z.(point) /. radius))
        "position Laplacian disagrees with the scaled-octahedron curvature identity"
    done) [1.;2.;1e-150;1e150]

let test_uniform_and_integrated () =
  let source = grid () in
  let values = Array.make 9 0. in values.(4) <- 1.;
  let source = with_attribute "impulse" (Attribute.Float values) source in
  let center = center_group source in
  let average = Ops.attribute_laplacian ~points:center
      ~weighting:Ops.Laplacian_uniform ~source:"impulse" source
      |> get |> scalar "impulse_laplacian" in
  check (average.(4) = -1.) "normalized uniform Laplacian is not neighbor average";
  let sum = Ops.attribute_laplacian ~points:center
      ~weighting:Ops.Laplacian_uniform ~normalize:false ~source:"impulse"
      ~output:"sum" source |> get |> scalar "sum" in
  check (sum.(4) = -4.) "integrated uniform Laplacian has wrong valence sum";
  let cotan = Ops.attribute_laplacian ~points:center ~normalize:false
      ~source:"impulse" ~output:"cotan_sum" source
      |> get |> scalar "cotan_sum" in
  check (cotan.(4) < 0. && Float.is_finite cotan.(4))
    "integrated cotangent Laplacian did not retain a finite negative impulse"

let test_position_scale_and_storage () =
  let source = Ops.uv_sphere ~connectivity:Ops.Sphere_triangles
      ~segments:32 ~rings:16 ~radius:1. () |> get in
  let position = Ops.attribute_laplacian ~source:"P" source |> get in
  let values = float3 "laplacian" position in
  let positions = Packed.Float3.Private.view (Geometry.positions source) in
  for point = 0 to Geometry.point_count source - 1 do
    let dot = (values.x.(point) *. positions.x.(point))
        +. (values.y.(point) *. positions.y.(point))
        +. (values.z.(point) *. positions.z.(point)) in
    check (dot < 0.) "position Laplacian does not point inward on a sphere"
  done;
  let base = grid () in
  let count = Geometry.point_count base in
  let float2 = Packed.Float2.of_owned
      ~x:(Array.init count float_of_int)
      ~y:(Array.init count (fun point -> float_of_int (point * point)))
      |> get_string in
  let float4 = Packed.Float4.of_owned
      ~x:(Array.make count 1.) ~y:(Array.make count 2.)
      ~z:(Array.make count 3.) ~w:(Array.make count 4.) |> get_string in
  let base = base |> with_attribute "integer" (Attribute.Int (Array.init count Fun.id))
      |> with_attribute "pair" (Attribute.Float2 float2)
      |> with_attribute "tuple" (Attribute.Float4 float4) in
  let integer = Ops.attribute_laplacian ~weighting:Ops.Laplacian_uniform
      ~source:"integer" base |> get in
  ignore (scalar "integer_laplacian" integer);
  let pair = Ops.attribute_laplacian ~source:"pair" base |> get in
  (match Geometry.find_attribute ~owner:Attribute.Point "pair_laplacian" pair with
   | Some attribute ->
       (match Attribute.Private.storage attribute with Attribute.Float2 _ -> ()
        | _ -> fail "float2 Laplacian changed width")
   | None -> fail "float2 Laplacian is missing");
  let tuple = Ops.attribute_laplacian ~source:"tuple" base |> get in
  (match Geometry.find_attribute ~owner:Attribute.Point "tuple_laplacian" tuple with
   | Some attribute ->
       (match Attribute.Private.storage attribute with Attribute.Float4 _ -> ()
        | _ -> fail "float4 Laplacian changed width")
   | None -> fail "float4 Laplacian is missing")

let test_selection_and_exact_domains () =
  let source = grid () in
  let source = with_attribute "value"
      (Attribute.Float (Array.init 9 float_of_int)) source in
  let source = with_attribute "result" (Attribute.Float (Array.make 9 42.))
      source in
  let center = center_group source in
  let output = Ops.attribute_laplacian ~points:center ~source:"value"
      ~output:"result" source |> get in
  let result = scalar "result" output in
  for point = 0 to 8 do
    if point <> 4 then check (result.(point) = 42.)
        "Laplacian changed an existing value outside the point group"
  done;
  check (Geometry.topology output == Geometry.topology source
      && Geometry.positions output == Geometry.positions source)
    "Laplacian did not structurally share topology and positions";
  let sphere = Ops.uv_sphere ~connectivity:Ops.Sphere_triangles
      ~segments:192 ~rings:96 ~radius:3. () |> get in
  let run domains weighting = Parallel.run ~domains (fun () ->
      Ops.attribute_laplacian ~grain:257 ~weighting ~source:"P" sphere |> get) in
  List.iter (fun weighting ->
    let one = float3 "laplacian" (run 1 weighting)
    and four = float3 "laplacian" (run 4 weighting) in
    check (one.x = four.x && one.y = four.y && one.z = four.z)
      "Laplacian differs across domain counts")
    [Ops.Laplacian_cotan;Ops.Laplacian_positive_cotan;Ops.Laplacian_uniform]

let expect_invalid work message = match work () with
  | Error error when Error.code error = "invalid_laplacian" -> ()
  | Error error -> fail (message ^ ": " ^ Error.to_string error)
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_validation_and_cancellation () =
  let source = grid () in
  expect_invalid (fun () -> Ops.attribute_laplacian ~grain:0 ~source:"P" source)
    "zero grain";
  expect_invalid (fun () -> Ops.attribute_laplacian ~source:"missing" source)
    "missing source";
  expect_invalid (fun () -> Ops.attribute_laplacian ~source:"P" ~output:"P" source)
    "position output";
  let primitive_group = Group.init ~owner:Group.Primitive ~name:"wrong"
      (Geometry.primitive_count source) (fun _ -> true) in
  expect_invalid (fun () -> Ops.attribute_laplacian ~points:primitive_group
      ~source:"P" source) "wrong group owner";
  let text = with_attribute "text" (Attribute.Text (Array.make 9 "x")) source in
  expect_invalid (fun () -> Ops.attribute_laplacian ~source:"text" text)
    "text source";
  let nonfinite = with_attribute "bad"
      (Attribute.Float [|0.;0.;0.;0.;Float.nan;0.;0.;0.;0.|]) source in
  expect_invalid (fun () -> Ops.attribute_laplacian ~source:"bad" nonfinite)
    "non-finite source";
  let curve = Ops.polyline ~closed:true [|0.,0.,0.;1.,0.,0.;0.,1.,0.|] |> get in
  expect_invalid (fun () -> Ops.attribute_laplacian ~source:"P" curve)
    "curve input";
  let degenerate = degenerate_triangle () in
  expect_invalid (fun () -> Ops.attribute_laplacian ~source:"P" degenerate)
    "degenerate metric";
  let cancel = Cancel.create () in Cancel.cancel cancel;
  (match Ops.attribute_laplacian ~cancel ~source:"P" source with
   | Error error -> check (Error.code error = "cancelled")
       "Laplacian cancellation code"
   | Ok _ -> fail "cancelled Laplacian unexpectedly succeeded")

let () =
  test_constant_linear_and_quadratic ();
  test_uniform_and_integrated ();
  test_position_scale_and_storage ();
  test_selection_and_exact_domains ();
  test_validation_and_cancellation ();
  print_endline "attribute Laplacian tests passed"
