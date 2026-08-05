open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error error -> fail (Error.to_string error)

let with_attribute owner name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> Result.get_ok in
  Geometry.with_attribute attribute geometry |> Result.get_ok

let with_float name values geometry =
  with_attribute Attribute.Point name (Attribute.Float values) geometry

let with_int name values geometry =
  with_attribute Attribute.Point name (Attribute.Int values) geometry

let open_curve count = Ops.polyline (Array.init count (fun point ->
    float_of_int point, 0., 0.)) |> get_ok

let topology_view geometry = Topology.Private.view (Geometry.topology geometry)
let position_view geometry = Packed.Float3.Private.view (Geometry.positions geometry)

let primitive_points geometry primitive =
  let topology = topology_view geometry in
  Array.sub topology.vertex_points topology.primitive_offsets.(primitive)
    (topology.primitive_offsets.(primitive + 1)
      - topology.primitive_offsets.(primitive))

let float_values owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail (name ^ " is not float"))
  | None -> fail (name ^ " is missing")

let int_values owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail (name ^ " is not integer"))
  | None -> fail (name ^ " is missing")

let check_float expected actual message =
  if expected <> actual then fail (Printf.sprintf
    "%s: expected %.17g, got %.17g" message expected actual)

let crossing_source () =
  open_curve 5
  |> with_float "signal" [|-1.;1.;2.;-1.;-2.|]
  |> with_float "weight" [|0.;10.;20.;30.;40.|]
  |> with_int "id" [|0;1;2;3;4|]
  |> with_attribute Attribute.Vertex "vertex_weight"
       (Attribute.Float [|0.;10.;20.;30.;40.|])
  |> with_attribute Attribute.Primitive "piece" (Attribute.Int [|17|])

let test_edge_remove_and_cut () =
  let source = crossing_source () in
  let removed = Ops.poly_cut ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_remove
      ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
      source |> get_ok in
  check (Geometry.point_count removed = 5
      && Geometry.primitive_count removed = 2
      && primitive_points removed 0 = [|1;2|]
      && primitive_points removed 1 = [|3;4|])
    "PolyCut edge removal fragments";
  let source = source |> Ops.group_edges ~name:"source_edges" |> get_ok in
  let cut = Ops.poly_cut ~grain:1 ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
      source |> get_ok in
  check (Geometry.point_count cut = 9 && Geometry.primitive_count cut = 3)
    "PolyCut crossing cut cardinality";
  let positions = position_view cut in
  let fragments = Array.init 3 (primitive_points cut) in
  check (Array.map Array.length fragments = [|2;4;3|])
    "PolyCut crossing fragment sizes";
  let first_cut = fragments.(0).(1)
  and second_copy = fragments.(1).(0)
  and second_cut = fragments.(1).(3)
  and third_copy = fragments.(2).(0) in
  check (first_cut <> second_copy && second_cut <> third_copy)
    "PolyCut did not disconnect interpolated cut endpoints";
  check_float 0.5 positions.x.(first_cut) "first crossing position";
  check_float 0.5 positions.x.(second_copy) "first crossing clone position";
  check_float (2. +. (2. /. 3.)) positions.x.(second_cut)
    "second crossing position";
  check_float positions.x.(second_cut) positions.x.(third_copy)
    "second crossing clone position";
  let weights = float_values Attribute.Point "weight" cut in
  check_float 5. weights.(first_cut) "point payload interpolation";
  check_float 5. weights.(second_copy) "point payload clone interpolation";
  let vertex_weights = float_values Attribute.Vertex "vertex_weight" cut in
  check_float 5. vertex_weights.(1) "vertex payload interpolation";
  check (int_values Attribute.Primitive "piece" cut = [|17;17;17|])
    "PolyCut primitive payload ancestry";
  let source_edges = Geometry.find_edge_group "source_edges" cut
      |> Option.get in
  check (Edge_group.cardinality source_edges = 6)
    "PolyCut subdivided edge-group ancestry"

let test_change_subdivision () =
  let source = open_curve 2
      |> with_attribute Attribute.Point "delta"
           (Attribute.Float2 (Packed.Float2.of_owned ~x:[|0.;3.|]
             ~y:[|0.;4.|] |> Result.get_ok)) in
  let cut = Ops.poly_cut ~grain:1 ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_change {attribute="delta"; threshold=2.})
      source |> get_ok in
  check (Geometry.primitive_count cut = 3 && Geometry.point_count cut = 6)
    "PolyCut tuple-change subdivision cardinality";
  let positions = position_view cut in
  let a = primitive_points cut 0 and b = primitive_points cut 1
  and c = primitive_points cut 2 in
  check_float (1. /. 3.) positions.x.(a.(1)) "change cut first third";
  check_float (1. /. 3.) positions.x.(b.(0)) "change cut first clone";
  check_float (2. /. 3.) positions.x.(b.(1)) "change cut second third";
  check_float (2. /. 3.) positions.x.(c.(0)) "change cut second clone";
  let extreme = open_curve 2 |> with_float "signal" [|-.max_float;max_float|] in
  let extreme = Ops.poly_cut ~grain:1 ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
      extreme |> get_ok in
  let extreme_positions = position_view extreme
  and extreme_fragment = primitive_points extreme 0 in
  check_float 0.5 extreme_positions.x.(extreme_fragment.(1))
    "scale-normalized extreme crossing"

let test_edge_cut_boundary_semantics () =
  let equal_endpoints = open_curve 3
      |> with_float "signal" [|0.;0.;1.|] in
  let equal_endpoints = Ops.poly_cut ~grain:1
      ~element:Ops.Poly_cut_edges ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
      equal_endpoints |> get_ok in
  check (Geometry.point_count equal_endpoints = 3
      && Geometry.primitive_count equal_endpoints = 1
      && primitive_points equal_endpoints 0 = [|1;2|])
    "PolyCut must remove an edge whose endpoint values both equal the crossing";
  let source = open_curve 4 in
  let removed = Ops.poly_cut ~grain:1 ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_remove ~detection:Ops.Poly_cut_all source |> get_ok
  and cut = Ops.poly_cut ~grain:1 ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_cut ~detection:Ops.Poly_cut_all source |> get_ok in
  check (topology_view removed = topology_view cut
      && position_view removed = position_view cut
      && Geometry.point_count cut = 4
      && Geometry.primitive_count cut = 0)
    "PolyCut locationless edge Cut must use removal semantics"

let test_discrete_ragged_payload_and_ordered_groups () =
  let attribute owner name storage =
    Attribute.create_owned ~owner ~name storage |> Result.get_ok in
  let source = open_curve 3
      |> with_float "signal" [|-1.;1.;1.|] in
  let source = Geometry.create ~positions:(Geometry.positions source)
      ~topology:(Geometry.topology source)
      ~attributes:(Geometry.attributes source @ [
        attribute Attribute.Point "label" (Attribute.Text [|"a";"b";"c"|]);
        attribute Attribute.Point "rows" (Attribute.Float_array
          (Packed.Float_array.create_owned ~offsets:[|0;1;3;4|]
            ~values:[|1.;2.;3.;4.|] |> Result.get_ok));
        attribute Attribute.Vertex "corner_label"
          (Attribute.Text [|"va";"vb";"vc"|]);
        attribute Attribute.Vertex "links" (Attribute.Int_array
          (Packed.Int_array.create_owned ~offsets:[|0;1;3;4|]
            ~values:[|10;20;21;30|] |> Result.get_ok));
        attribute Attribute.Detail "author" (Attribute.Text [|"polycut"|])])
      ~groups:[
        Group.ordered ~owner:Group.Point ~name:"marked_points" ~length:3 [|1|]
          |> Result.get_ok;
        Group.ordered ~owner:Group.Vertex ~name:"marked_vertices" ~length:3 [|1|]
          |> Result.get_ok;
        Group.ordered ~owner:Group.Primitive ~name:"marked_curve" ~length:1 [|0|]
          |> Result.get_ok] () |> Result.get_ok in
  let output = Ops.poly_cut ~grain:1 ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
      source |> get_ok in
  let text owner name = match Geometry.find_attribute ~owner name output with
    | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Text values -> values | _ -> fail (name ^ " storage"))
    | None -> fail (name ^ " missing") in
  check (text Attribute.Point "label" = [|"a";"b";"c";"b";"b"|])
    "PolyCut nearest point text interpolation";
  check (text Attribute.Vertex "corner_label"
      = [|"va";"vb";"vb";"vb";"vc"|])
    "PolyCut nearest vertex text interpolation";
  let rows = match Geometry.find_attribute ~owner:Attribute.Point "rows" output with
    | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Float_array values -> values | _ -> fail "rows storage")
    | None -> fail "rows missing"
  and links = match Geometry.find_attribute ~owner:Attribute.Vertex "links" output with
    | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Int_array values -> values | _ -> fail "links storage")
    | None -> fail "links missing" in
  check (Packed.Float_array.get rows 3 = [|2.;3.|]
      && Packed.Float_array.get rows 4 = [|2.;3.|]
      && Packed.Int_array.get links 1 = [|20;21|]
      && Packed.Int_array.get links 2 = [|20;21|])
    "PolyCut ragged nearest interpolation";
  let point_group = Geometry.find_group ~owner:Group.Point "marked_points" output
      |> Option.get
  and vertex_group = Geometry.find_group ~owner:Group.Vertex "marked_vertices" output
      |> Option.get
  and primitive_group = Geometry.find_group ~owner:Group.Primitive "marked_curve" output
      |> Option.get in
  check (Group.ordered_elements point_group = Some [|1;3;4|]
      && Group.ordered_elements vertex_group = Some [|1;2;3|]
      && Group.ordered_elements primitive_group = Some [|0;1|])
    "PolyCut ordered-group ancestry";
  check (text Attribute.Detail "author" = [|"polycut"|])
    "PolyCut detail payload"

let point_group name count member =
  Group.init ~owner:Group.Point ~name count member

let test_point_remove_and_cut () =
  let source = open_curve 5 in
  let middle = point_group "middle" 5 (fun point -> point = 2) in
  let removed = Ops.poly_cut ~grain:1 ~element:Ops.Poly_cut_points
      ~strategy:Ops.Poly_cut_remove ~cut_points:middle
      ~detection:Ops.Poly_cut_all source |> get_ok in
  check (Geometry.point_count removed = 4
      && Geometry.primitive_count removed = 2)
    "PolyCut point removal cardinality";
  let positions = position_view removed in
  check (positions.x = [|0.;1.;3.;4.|]
      && primitive_points removed 0 = [|0;1|]
      && primitive_points removed 1 = [|2;3|])
    "PolyCut point removal compaction/fragments";
  let cut = Ops.poly_cut ~grain:1 ~element:Ops.Poly_cut_points
      ~strategy:Ops.Poly_cut_cut ~cut_points:middle
      ~detection:Ops.Poly_cut_all source |> get_ok in
  check (Geometry.point_count cut = 6 && Geometry.primitive_count cut = 2)
    "PolyCut point-cut cardinality";
  let a = primitive_points cut 0 and b = primitive_points cut 1 in
  check (a = [|0;1;2|] && Array.length b = 3 && b.(0) <> 2
      && b.(1) = 3 && b.(2) = 4)
    "PolyCut point-cut disconnected endpoint ancestry";
  let endpoint = point_group "endpoint" 5 (fun point -> point = 0) in
  let identity = Ops.poly_cut ~element:Ops.Poly_cut_points
      ~strategy:Ops.Poly_cut_cut ~cut_points:endpoint
      ~detection:Ops.Poly_cut_all source |> get_ok in
  check (identity == source) "PolyCut endpoint-only no-op lost identity"

let test_closed_policy_and_restrictions () =
  let source = Ops.polyline ~closed:true
      [|(0.,0.,0.);(1.,0.,0.);(1.,1.,0.);(0.,1.,0.)|] |> get_ok in
  let topology = Geometry.topology source in
  let index = Topology_index.create topology in
  let one_edge = Edge_group.init ~topology ~index ~name:"one"
      (fun edge -> edge = 0) in
  let open_result = Ops.poly_cut ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_remove ~cut_edges:one_edge
      ~detection:Ops.Poly_cut_all ~keep_closed:false source |> get_ok
  and closed_result = Ops.poly_cut ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_remove ~cut_edges:one_edge
      ~detection:Ops.Poly_cut_all ~keep_closed:true source |> get_ok in
  check (Geometry.primitive_count open_result = 1
      && Topology.primitive_kind (Geometry.topology open_result) 0
           = Topology.Open_polyline)
    "PolyCut open fragment policy";
  check (Geometry.primitive_count closed_result = 1
      && Topology.primitive_kind (Geometry.topology closed_result) 0
           = Topology.Closed_polyline)
    "PolyCut closed fragment policy";
  let face = Ops.grid ~connectivity:Ops.Grid_quads ~columns:1 ~rows:1
      ~size:1. () |> get_ok in
  let face_topology = Geometry.topology face in
  let face_index = Topology_index.create face_topology in
  let face_edge = Edge_group.init ~topology:face_topology ~index:face_index
      ~name:"face_edge" (fun edge -> edge = 0) in
  let face_cut = Ops.poly_cut ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_remove ~cut_edges:face_edge
      ~detection:Ops.Poly_cut_all ~keep_closed:true face |> get_ok in
  check (Topology.primitive_kind (Geometry.topology face_cut) 0 = Topology.Polygon)
    "PolyCut did not preserve filled-polygon kind for a closed fragment"

let expect_invalid work message = match work () with
  | Error error -> check (Error.code error = "invalid_poly_cut") message
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_validation_and_cancellation () =
  let source = crossing_source () in
  expect_invalid (fun () -> Ops.poly_cut ~grain:0 source) "zero grain";
  expect_invalid (fun () -> Ops.poly_cut
      ~detection:(Ops.Poly_cut_crossing {attribute="missing"; value=0.}) source)
    "missing cut attribute";
  expect_invalid (fun () -> Ops.poly_cut
      ~detection:(Ops.Poly_cut_crossing {attribute="P"; value=0.}) source)
    "tuple crossing";
  expect_invalid (fun () -> Ops.poly_cut ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_change {attribute="signal"; threshold=0.}) source)
    "zero cut-at-change threshold";
  let overflow = open_curve 2
      |> with_float "signal" [|-.max_float;max_float|] in
  expect_invalid (fun () -> Ops.poly_cut ~grain:1
      ~element:Ops.Poly_cut_edges ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_change {attribute="signal"; threshold=1.})
      overflow) "unrepresentable change";
  let wrong_points = Group.init ~owner:Group.Primitive ~name:"wrong"
      (Geometry.primitive_count source) (fun _ -> true) in
  expect_invalid (fun () -> Ops.poly_cut ~cut_points:wrong_points source)
    "wrong point-selection owner";
  let wrong_primitive_owner = Group.init ~owner:Group.Point ~name:"wrong_owner"
      (Geometry.point_count source) (fun _ -> true) in
  expect_invalid (fun () -> Ops.poly_cut ~primitives:wrong_primitive_owner source)
    "wrong primitive-selection owner";
  let wrong_primitive_length = Group.init ~owner:Group.Primitive
      ~name:"wrong_length" 2 (fun _ -> true) in
  expect_invalid (fun () -> Ops.poly_cut ~primitives:wrong_primitive_length source)
    "wrong primitive-selection length";
  let other = open_curve 5 in
  let wrong_index = Topology_index.create (Geometry.topology other) in
  let wrong_edges = Edge_group.init ~topology:(Geometry.topology other)
      ~index:wrong_index ~name:"wrong" (fun _ -> true) in
  expect_invalid (fun () -> Ops.poly_cut ~element:Ops.Poly_cut_edges
      ~cut_edges:wrong_edges source) "wrong edge affinity";
  let malformed = source |> with_float "signal"
      [|-1.;Float.nan;1.;Float.infinity;1.|] in
  let error domains = Parallel.run ~domains (fun () ->
      Ops.poly_cut ~grain:1 ~element:Ops.Poly_cut_edges
        ~strategy:Ops.Poly_cut_remove
        ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
        malformed) in
  let message domains = match error domains with
    | Error error -> Error.message error
    | Ok _ -> fail "PolyCut accepted malformed operated field" in
  let one_message = message 1 and four_message = message 4 in
  check (one_message = four_message
      && String.ends_with ~suffix:"point 0" one_message)
    "PolyCut lowest malformed diagnostic differs across domain counts";
  let none = Group.init ~owner:Group.Primitive ~name:"none" 1
      (fun _ -> false) in
  let opaque = Ops.poly_cut ~primitives:none ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_remove
      ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
      malformed |> get_ok in
  check (opaque == malformed) "PolyCut rejected opaque unselected values";
  let no_points = Group.init ~owner:Group.Point ~name:"no_points" 5
      (fun _ -> false) in
  let opaque_points = Ops.poly_cut ~cut_points:no_points
      ~element:Ops.Poly_cut_points ~strategy:Ops.Poly_cut_remove
      ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
      malformed |> get_ok in
  check (opaque_points == malformed)
    "PolyCut rejected values outside an empty cut-point restriction";
  let malformed_topology = Geometry.topology malformed in
  let malformed_index = Topology_index.create malformed_topology in
  let no_edges = Edge_group.init ~topology:malformed_topology
      ~index:malformed_index ~name:"no_edges" (fun _ -> false) in
  let opaque_edges = Ops.poly_cut ~cut_edges:no_edges
      ~element:Ops.Poly_cut_edges ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
      malformed |> get_ok in
  check (opaque_edges == malformed)
    "PolyCut rejected values outside an empty cut-edge restriction";
  let bad_position_source = open_curve 2
      |> with_float "signal" [|-1.;1.|] in
  let bad_position_source = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn
        ~x:[|Float.nan;1.|] ~y:[|0.;0.|] ~z:[|0.;0.|])
      ~topology:(Geometry.topology bad_position_source)
      ~attributes:(Geometry.attributes bad_position_source) () |> Result.get_ok in
  expect_invalid (fun () -> Ops.poly_cut ~grain:1
      ~element:Ops.Poly_cut_edges ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
      bad_position_source) "non-finite interpolated position";
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Ops.poly_cut ~cancel source with
   | Error error -> check (Error.code error = "cancelled")
       "PolyCut cancellation code"
   | Ok _ -> fail "cancelled PolyCut published geometry")

let equal_float2 left right =
  let left = Packed.Float2.Private.view left and right = Packed.Float2.Private.view right in
  left.x = right.x && left.y = right.y

let equal_storage left right = match left, right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Float2 left, Attribute.Float2 right -> equal_float2 left right
  | Attribute.Float3 left, Attribute.Float3 right ->
      Packed.Float3.Private.view left = Packed.Float3.Private.view right
  | Attribute.Float4 left, Attribute.Float4 right ->
      Packed.Float4.Private.view left = Packed.Float4.Private.view right
  | Attribute.Text left, Attribute.Text right -> left = right
  | Attribute.Int_array left, Attribute.Int_array right ->
      Packed.Int_array.Private.view left = Packed.Int_array.Private.view right
  | Attribute.Float_array left, Attribute.Float_array right ->
      Packed.Float_array.Private.view left = Packed.Float_array.Private.view right
  | _ -> false

let equal_geometry left right =
  Packed.Float3.Private.view (Geometry.positions left)
    = Packed.Float3.Private.view (Geometry.positions right)
  && Topology.Private.view (Geometry.topology left)
    = Topology.Private.view (Geometry.topology right)
  && List.equal (fun left right -> Attribute.owner left = Attribute.owner right
      && Attribute.name left = Attribute.name right
      && equal_storage (Attribute.Private.storage left)
           (Attribute.Private.storage right))
      (Geometry.attributes left) (Geometry.attributes right)
  && List.equal (fun left right ->
      let values group =
        let output = ref [] in
        Group.iter_ordered (fun element -> output := element :: !output) group;
        !output in
      Group.owner left = Group.owner right
      && Group.name left = Group.name right
      && values left = values right)
      (Geometry.groups left) (Geometry.groups right)
  && List.equal (fun left right ->
      let values group =
        let output = ref [] in
        Edge_group.iter (fun edge -> output := edge :: !output) group;
        !output in
      Edge_group.name left = Edge_group.name right
      && values left = values right)
      (Geometry.edge_groups left) (Geometry.edge_groups right)

let test_dense_parallel_exactness () =
  let curves = 600 and points_per_curve = 241 in
  let point_count = curves * points_per_curve in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (curves + 1) (fun primitive ->
        primitive * points_per_curve))
      ~primitive_kinds:(Array.make curves Topology.Open_polyline)
      |> Result.get_ok in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        float_of_int (point mod points_per_curve) *. 0.01))
      ~y:(Array.init point_count (fun point ->
        float_of_int (point / points_per_curve) *. 0.02))
      ~z:(Array.make point_count 0.) in
  let source = Geometry.create ~positions ~topology () |> Result.get_ok
      |> with_float "signal" (Array.init point_count (fun point ->
           float_of_int (point mod 29) -. 14.5))
      |> with_int "id" (Array.init point_count Fun.id)
      |> with_attribute Attribute.Vertex "uv"
           (Attribute.Float2 (Packed.Float2.of_owned
             ~x:(Array.init point_count (fun point ->
               float_of_int (point mod points_per_curve)
               /. float_of_int (points_per_curve - 1)))
             ~y:(Array.make point_count 0.) |> Result.get_ok))
      |> with_attribute Attribute.Primitive "piece"
           (Attribute.Int (Array.init curves Fun.id)) in
  let selected = Group.init ~owner:Group.Point ~name:"selected" point_count
      (fun point -> point mod 7 <> 0) in
  let source = Geometry.with_group selected source |> Result.get_ok
      |> Ops.group_edges ~grain:257 ~name:"source_edges" |> get_ok in
  let cook domains = Parallel.run ~domains (fun () ->
      Ops.poly_cut ~grain:257 ~element:Ops.Poly_cut_edges
        ~strategy:Ops.Poly_cut_cut
        ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
        source |> get_ok) in
  let one = cook 1 and four = cook 4 in
  check (equal_geometry one four) "PolyCut one/four-domain geometry differs";
  let one_mesh = Prismel_mesh.to_mesh one |> get_ok
  and four_mesh = Prismel_mesh.to_mesh four |> get_ok in
  check (Mesh.Private.packed_view one_mesh = Mesh.Private.packed_view four_mesh)
    "PolyCut one/four-domain render mesh differs"

let () =
  test_edge_remove_and_cut ();
  test_change_subdivision ();
  test_edge_cut_boundary_semantics ();
  test_discrete_ragged_payload_and_ordered_groups ();
  test_point_remove_and_cut ();
  test_closed_policy_and_restrictions ();
  test_validation_and_cancellation ();
  test_dense_parallel_exactness ();
  print_endline "pdk PolyCut tests passed"
