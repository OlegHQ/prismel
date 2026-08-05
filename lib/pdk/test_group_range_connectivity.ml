open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let geometry_of_faces point_count faces =
  let positions = Packed.Float3.Builder.create point_count in
  for point = 0 to point_count - 1 do
    Packed.Float3.Builder.set positions point (float_of_int point) 0. 0.
  done;
  let topology = Topology.Builder.create ~point_count () in
  Array.iter (Topology.Builder.add_polygon topology) faces;
  Geometry.create ~positions:(Packed.Float3.Builder.freeze positions)
    ~topology:(Topology.Builder.freeze topology) ()
  |> function Ok geometry -> geometry | Error message -> fail message

let fixture () = geometry_of_faces 12 [|
  [|0; 1; 2|]; [|1; 3; 2|]; [|3; 4; 2|];
  [|5; 6; 7|]; [|6; 8; 7|];
  [|9; 10; 11|]
|]

let group owner name geometry = match Geometry.find_group ~owner name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let members group =
  let output = ref [] in
  Group.iter (fun element -> output := element :: !output) group;
  List.rev !output

let expect_members expected group message =
  if members group <> expected then fail message

let disconnected ?region () =
  Ops.Range_disconnected { region }

let connected ?attributes ?(tolerance = 1e-6) ?collision ?region
    ?(remove_other_regions = true) () =
  Ops.Range_connected {
    connectivity_attributes = attributes;
    connectivity_tolerance = tolerance;
    collision;
    region;
    remove_other_regions;
  }

let with_attribute name owner storage geometry =
  let attribute = Attribute.create_owned ~name ~owner storage
      |> function Ok value -> value | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok value -> value | Error message -> fail message

let with_group owner name predicate geometry =
  let count = match owner with
    | Group.Point -> Geometry.point_count geometry
    | Group.Vertex -> Geometry.vertex_count geometry
    | Group.Primitive -> Geometry.primitive_count geometry in
  Geometry.with_group (Group.init ~owner ~name count predicate) geometry
  |> function Ok value -> value | Error message -> fail message

let with_edge_group name ~a ~b geometry =
  let topology = Geometry.topology geometry in
  let index = Topology_index.create topology in
  let selected = Topology_index.find_edge_index index ~a ~b in
  if selected < 0 then fail "missing fixture edge";
  let edge_group = Edge_group.init ~topology ~index ~name
      (fun edge -> edge = selected) in
  Geometry.with_edge_group edge_group geometry
  |> function Ok value -> value | Error message -> fail message

let test_point_components () =
  let source = fixture () in
  let ranged = Ops.group_range ~grain:1 ~owner:Ops.Group_points
      ~name:"middle" ~connectivity:(disconnected ())
      (Ops.Range_start_end { start = 1; end_ = 2 }) source |> get_ok in
  expect_members [1; 2; 6; 7; 10; 11]
    (group Group.Point "middle" ranged)
    "Group Range did not evaluate point ranges per disconnected component";
  let filtered = Ops.group_range ~grain:1 ~owner:Ops.Group_points
      ~name:"alternating" ~connectivity:(disconnected ())
      ~filter:{ select = 1; of_ = 2; offset = 0 }
      (Ops.Range_start_end { start = 0; end_ = max_int }) source |> get_ok in
  expect_members [0; 2; 4; 5; 7; 9; 11]
    (group Group.Point "alternating" filtered)
    "Group Range filter phase was not reset per component";
  let inverted = Ops.group_range ~grain:1 ~owner:Ops.Group_points
      ~name:"outside" ~connectivity:(disconnected ()) ~invert:true
      (Ops.Range_start_length { start = 1; length = 2 }) source |> get_ok in
  expect_members [0; 3; 4; 5; 8; 9]
    (group Group.Point "outside" inverted)
    "Group Range inversion escaped its per-component domain";
  let partitioned = Ops.group_range ~grain:1 ~owner:Ops.Group_points
      ~name:"first_half" ~connectivity:(disconnected ())
      (Ops.Range_partition { partition = 0; partitions = 2 }) source |> get_ok in
  expect_members [0; 1; 2; 5; 6; 9; 10]
    (group Group.Point "first_half" partitioned)
    "Group Range did not balance partitions independently";
  let orphans = Ops.points [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.)|]
      |> Ops.group_range ~grain:1 ~owner:Ops.Group_points ~name:"each_first"
           ~connectivity:(disconnected ())
           (Ops.Range_start_end { start = 0; end_ = 0 }) |> get_ok in
  expect_members [0; 1; 2] (group Group.Point "each_first" orphans)
    "Group Range did not treat orphan points as stable components";
  let empty = Ops.points [||]
      |> Ops.group_range ~grain:1 ~owner:Ops.Group_points ~name:"empty"
           ~connectivity:(disconnected ())
           (Ops.Range_start_end { start = 0; end_ = 0 }) |> get_ok in
  check (Group.cardinality (group Group.Point "empty" empty) = 0)
    "Group Range connected empty geometry"

let test_region_and_primitive_modes () =
  let source = fixture () in
  let first_faces = Ops.group_range ~grain:1 ~owner:Ops.Group_primitives
      ~name:"first_faces" ~connectivity:(disconnected ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) source |> get_ok in
  expect_members [0; 3; 5] (group Group.Primitive "first_faces" first_faces)
    "Group Range primitive components were not stably indexed";
  let second_region = Ops.group_range ~grain:1 ~owner:Ops.Group_primitives
      ~name:"second_region" ~connectivity:(disconnected ~region:1 ())
      (Ops.Range_start_end { start = 0; end_ = max_int }) source |> get_ok in
  expect_members [3; 4] (group Group.Primitive "second_region" second_region)
    "Group Range region restriction selected the wrong component";
  let absent_region = Ops.group_range ~grain:1 ~owner:Ops.Group_points
      ~name:"absent" ~connectivity:(disconnected ~region:99 ())
      (Ops.Range_start_end { start = 0; end_ = max_int }) source |> get_ok in
  check (Group.cardinality (group Group.Point "absent" absent_region) = 0)
    "Group Range out-of-range connected region was not empty"

let test_attribute_components () =
  let quad = geometry_of_faces 4 [|[|0; 1; 2; 3|]|]
      |> with_attribute "piece" Attribute.Point
           (Attribute.Int [|0; 0; 1; 1|])
      |> with_attribute "weight" Attribute.Point
           (Attribute.Float [|0.; 0.05; 1.; 1.05|]) in
  let points = Ops.group_range ~grain:1 ~owner:Ops.Group_points
      ~name:"attribute_first"
      ~connectivity:(connected ~attributes:"piece weight" ~tolerance:0.1 ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) quad |> get_ok in
  expect_members [0; 2] (group Group.Point "attribute_first" points)
    "Group Range did not split point connectivity by multiple attributes";
  let loose = Ops.group_range ~grain:1 ~owner:Ops.Group_points
      ~name:"loose" ~connectivity:(connected ~attributes:"weight"
        ~tolerance:0.1 ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) quad |> get_ok in
  expect_members [0; 2] (group Group.Point "loose" loose)
    "Group Range float connectivity tolerance did not join nearby values";
  let strict = Ops.group_range ~grain:1 ~owner:Ops.Group_points
      ~name:"strict" ~connectivity:(connected ~attributes:"weight"
        ~tolerance:0. ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) quad |> get_ok in
  expect_members [0; 1; 2; 3] (group Group.Point "strict" strict)
    "Group Range exact float connectivity did not split unequal values";
  let combined_source = quad |> with_edge_group "extra_cut" ~a:0 ~b:1 in
  let combined = Ops.group_range ~grain:1 ~owner:Ops.Group_points
      ~name:"combined"
      ~connectivity:(connected ~attributes:"piece" ~collision:{
        Ops.collision_owner = Ops.Group_edges;
        collision_pattern = "extra_cut";
        keep_boundary = true } ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) combined_source |> get_ok in
  expect_members [0; 1; 2] (group Group.Point "combined" combined)
    "Group Range did not union attribute and collision boundaries";
  let strip = geometry_of_faces 10 [|
      [|0; 1; 6; 5|]; [|1; 2; 7; 6|];
      [|2; 3; 8; 7|]; [|3; 4; 9; 8|]
    |]
      |> with_attribute "class" Attribute.Primitive
           (Attribute.Text [|"a"; "a"; "b"; "b"|]) in
  let primitives = Ops.group_range ~grain:1 ~owner:Ops.Group_primitives
      ~name:"piece_first" ~connectivity:(connected ~attributes:"class" ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) strip |> get_ok in
  expect_members [0; 2] (group Group.Primitive "piece_first" primitives)
    "Group Range did not split primitive connectivity by text attribute"

let test_collision_and_region_policy () =
  let two_faces = geometry_of_faces 6 [|
      [|0; 1; 4; 3|]; [|1; 2; 5; 4|]
    |] |> with_edge_group "cut" ~a:1 ~b:4 in
  let collision = {
    Ops.collision_owner = Ops.Group_edges;
    collision_pattern = "cut";
    keep_boundary = true;
  } in
  let split = Ops.group_range ~grain:1 ~owner:Ops.Group_primitives
      ~name:"split" ~connectivity:(connected ~collision ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) two_faces |> get_ok in
  expect_members [0; 1] (group Group.Primitive "split" split)
    "Group Range collision edge did not split an independently owned output";
  let check_ordinary_collision source owner pattern message =
    let collision = {
      Ops.collision_owner = owner;
      collision_pattern = pattern;
      keep_boundary = true;
    } in
    let result = Ops.group_range ~grain:1 ~owner:Ops.Group_primitives
        ~name:"ordinary_split" ~connectivity:(connected ~collision ())
        (Ops.Range_start_end { start = 0; end_ = 0 }) source |> get_ok in
    expect_members [0; 1] (group Group.Primitive "ordinary_split" result) message
  in
  check_ordinary_collision
    (two_faces |> with_group Group.Point "point_cut" (fun point -> point = 1))
    Ops.Group_points "point_cut"
    "Group Range point collision boundary did not split primitives";
  check_ordinary_collision
    (two_faces |> with_group Group.Vertex "vertex_cut"
      (fun vertex -> vertex = 1 || vertex = 2))
    Ops.Group_vertices "vertex_cut"
    "Group Range vertex collision boundary did not split primitives";
  check_ordinary_collision
    (two_faces |> with_group Group.Primitive "primitive_cut"
      (fun primitive -> primitive = 0))
    Ops.Group_primitives "primitive_cut"
    "Group Range primitive collision boundary did not split primitives";
  let omitted = Ops.group_range ~grain:1 ~owner:Ops.Group_primitives
      ~name:"omitted"
      ~connectivity:(connected
        ~collision:{ collision with keep_boundary = false } ())
      (Ops.Range_start_end { start = 0; end_ = max_int }) two_faces |> get_ok in
  expect_members [] (group Group.Primitive "omitted" omitted)
    "Group Range did not disregard collision-boundary elements";
  let source = fixture () in
  let preserve = Ops.group_range ~grain:1 ~owner:Ops.Group_primitives
      ~name:"preserve"
      ~connectivity:(connected ~region:1 ~remove_other_regions:false ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) source |> get_ok in
  expect_members [0; 1; 2; 3; 5] (group Group.Primitive "preserve" preserve)
    "Group Range did not preserve components outside the affected region";
  let masked_source = source |> with_group Group.Primitive "mask"
      (fun primitive -> primitive = 0 || primitive = 3
        || primitive = 4 || primitive = 5) in
  let masked = Ops.group_range ~grain:1 ~base:"mask"
      ~owner:Ops.Group_primitives ~name:"masked_preserve"
      ~connectivity:(connected ~region:1 ~remove_other_regions:false ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) masked_source |> get_ok in
  expect_members [0; 3; 5] (group Group.Primitive "masked_preserve" masked)
    "Group Range preserved elements outside the base mask";
  let remove = Ops.group_range ~grain:1 ~owner:Ops.Group_primitives
      ~name:"remove"
      ~connectivity:(connected ~region:1 ~remove_other_regions:true ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) source |> get_ok in
  expect_members [3] (group Group.Primitive "remove" remove)
    "Group Range remove-other-regions policy retained unrelated components"

let test_validation_and_cancellation () =
  let source = fixture () in
  (match Ops.group_range ~owner:Ops.Group_vertices ~name:"bad"
      ~connectivity:(disconnected ())
      (Ops.Range_start_end { start = 0; end_ = 1 }) source with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Range connected owner error code"
   | Ok _ -> fail "Group Range accepted vertex connectivity");
  (match Ops.group_range ~owner:Ops.Group_points ~name:"bad"
      ~connectivity:(disconnected ~region:(-1) ())
      (Ops.Range_start_end { start = 0; end_ = 1 }) source with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Range negative region error code"
   | Ok _ -> fail "Group Range accepted a negative connected region");
  (match Ops.group_range ~owner:Ops.Group_points ~name:"bad"
      ~connectivity:(connected ~tolerance:Float.nan ())
      (Ops.Range_start_end { start = 0; end_ = 1 }) source with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Range tolerance error code"
   | Ok _ -> fail "Group Range accepted a non-finite connectivity tolerance");
  (match Ops.group_range ~owner:Ops.Group_points ~name:"bad"
      ~connectivity:(connected ~attributes:"missing" ())
      (Ops.Range_start_end { start = 0; end_ = 1 }) source with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Range missing connectivity attribute error code"
   | Ok _ -> fail "Group Range accepted an unmatched connectivity attribute");
  let nonfinite = with_attribute "bad" Attribute.Point
      (Attribute.Float (Array.init (Geometry.point_count source)
        (fun point -> if point = 3 then Float.nan else 0.))) source in
  (match Ops.group_range ~owner:Ops.Group_points ~name:"bad"
      ~connectivity:(connected ~attributes:"bad" ())
      (Ops.Range_start_end { start = 0; end_ = 1 }) nonfinite with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Range non-finite attribute error code"
   | Ok _ -> fail "Group Range accepted a non-finite connectivity attribute");
  (match Ops.group_range ~owner:Ops.Group_points ~name:"bad"
      ~connectivity:(connected ~collision:{
        Ops.collision_owner = Ops.Group_points;
        collision_pattern = " "; keep_boundary = true } ())
      (Ops.Range_start_end { start = 0; end_ = 1 }) source with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Range empty collision error code"
   | Ok _ -> fail "Group Range accepted an empty collision pattern");
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.group_range ~cancel:cancelled ~owner:Ops.Group_points ~name:"bad"
      ~connectivity:(disconnected ())
      (Ops.Range_start_end { start = 0; end_ = 1 }) source with
   | Error error -> check (Error.code error = "cancelled")
       "Group Range connected cancellation code"
   | Ok _ -> fail "cancelled connected Group Range published geometry")

let triangle_soup count =
  let faces = Array.init count (fun triangle ->
    let point = triangle * 3 in [|point; point + 1; point + 2|]) in
  geometry_of_faces (count * 3) faces

let test_parallel_exactness_and_scale () =
  let triangles = 50_000 and source = triangle_soup 50_000 in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.group_range ~grain:1_009 ~owner:Ops.Group_points ~name:"first"
      ~connectivity:(disconnected ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) source |> get_ok) in
  let one = group Group.Point "first" (run 1)
  and four = group Group.Point "first" (run 4) in
  check (Group.cardinality one = triangles)
    "Group Range connected scale cardinality";
  check (Bytes.equal (Group.Private.bits_view one)
      (Group.Private.bits_view four))
    "Group Range connected output differs by domain count";
  check (Group.mem 0 one && not (Group.mem 1 one)
      && Group.mem (3 * (triangles - 1)) one)
    "Group Range connected scale membership";
  let grid = Ops.grid ~columns:400 ~rows:250 ~size:10. () |> get_ok in
  let point_count = Geometry.point_count grid in
  let attributed = with_attribute "stripe" Attribute.Point
      (Attribute.Int (Array.init point_count (fun point -> point / 10_000)))
      grid in
  let run_attribute domains = Parallel.run ~domains (fun () ->
    Ops.group_range ~grain:1_009 ~owner:Ops.Group_points ~name:"stripe_first"
      ~connectivity:(connected ~attributes:"stripe" ())
      (Ops.Range_start_end { start = 0; end_ = 0 }) attributed |> get_ok) in
  let one_geometry = run_attribute 1 and four_geometry = run_attribute 4 in
  let one = group Group.Point "stripe_first" one_geometry
  and four = group Group.Point "stripe_first" four_geometry in
  check (Bytes.equal (Group.Private.bits_view one)
      (Group.Private.bits_view four))
    "attribute-connected Group Range differs by domain count";
  check (Group.cardinality one > 1
      && Topology.data_id (Geometry.topology one_geometry)
         = Topology.data_id (Geometry.topology attributed)
      && Attribute.data_id (Option.get (Geometry.find_attribute
           ~owner:Attribute.Point "stripe" one_geometry))
         = Attribute.data_id (Option.get (Geometry.find_attribute
           ~owner:Attribute.Point "stripe" attributed)))
    "attribute-connected Group Range did not preserve full geometry payloads"

let test_multiple_ranges () =
  let source = geometry_of_faces 10 [|
      [|0; 1; 6; 5|]; [|1; 2; 7; 6|];
      [|2; 3; 8; 7|]; [|3; 4; 9; 8|]
    |] in
  let rules = [
    Ops.group_range_rule ~owner:Ops.Group_points ~name:"first"
      (Ops.Range_start_end { start = 0; end_ = 4 });
    Ops.group_range_rule ~base:"first" ~owner:Ops.Group_points ~name:"middle"
      (Ops.Range_start_end { start = 2; end_ = 3 });
    Ops.group_range_rule ~owner:Ops.Group_points ~name:"ends"
      (Ops.Range_start_end { start = 0; end_ = 1 });
    Ops.group_range_rule ~merge:Ops.Group_union ~owner:Ops.Group_points
      ~name:"ends" (Ops.Range_from_ends { start = 8; end_offset = 0 });
    Ops.group_range_rule ~owner:Ops.Group_primitives ~name:"faces"
      (Ops.Range_partition { partition = 1; partitions = 2 });
  ] in
  let result = Ops.group_ranges ~grain:1 ~rules source |> get_ok in
  expect_members [0; 1; 2; 3; 4] (group Group.Point "first" result)
    "Group Ranges first ordered rule";
  expect_members [2; 3] (group Group.Point "middle" result)
    "Group Ranges later base did not observe an earlier output";
  expect_members [0; 1; 8; 9] (group Group.Point "ends" result)
    "Group Ranges ordered same-name merge";
  expect_members [2; 3] (group Group.Primitive "faces" result)
    "Group Ranges mixed-owner output";
  check (List.map Group.name (Geometry.groups result)
      = ["first"; "middle"; "ends"; "faces"])
    "Group Ranges changed stable publication order";
  let disabled = Ops.group_range_rule ~base:" "
      ~connectivity:(disconnected ~region:(-1) ())
      ~owner:Ops.Group_points ~name:" "
      (Ops.Range_start_end { start = 0; end_ = 0 }) in
  let identity = Ops.group_ranges ~rules:[disabled] source |> get_ok in
  check (identity == source) "Group Ranges disabled slot lost input identity";
  let invalid = Ops.group_range_rule ~connectivity:(disconnected ())
      ~owner:Ops.Group_vertices ~name:"invalid"
      (Ops.Range_start_end { start = 0; end_ = 0 }) in
  (match Ops.group_ranges ~rules:[List.hd rules; invalid] source with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Ranges atomic failure error code"
   | Ok _ -> fail "Group Ranges published a prefix before a later failure");
  check (Geometry.groups source = [])
    "Group Ranges failure mutated the immutable input";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.group_ranges ~cancel:cancelled ~rules source with
   | Error error -> check (Error.code error = "cancelled")
       "Group Ranges cancellation error code"
   | Ok _ -> fail "cancelled Group Ranges published geometry")

let test_multiple_ranges_parallel_exactness () =
  let source = Ops.grid ~columns:400 ~rows:250 ~size:10. () |> get_ok in
  let point_count = Geometry.point_count source in
  let source = with_attribute "stripe" Attribute.Point
      (Attribute.Int (Array.init point_count (fun point -> point / 10_000)))
      source in
  let rules = [
    Ops.group_range_rule ~filter:{ select = 3; of_ = 11; offset = 2 }
      ~owner:Ops.Group_points ~name:"periodic"
      (Ops.Range_from_ends { start = 7; end_offset = 9 });
    Ops.group_range_rule
      ~connectivity:(connected ~attributes:"stripe" ())
      ~owner:Ops.Group_points ~name:"pieces"
      (Ops.Range_start_end { start = 0; end_ = 2 });
    Ops.group_range_rule ~owner:Ops.Group_primitives ~name:"partition"
      (Ops.Range_partition { partition = 2; partitions = 7 });
  ] in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.group_ranges ~grain:1_009 ~rules source |> get_ok) in
  let one = run 1 and four = run 4 in
  check (Topology.data_id (Geometry.topology one)
      = Topology.data_id (Geometry.topology four)
      && List.map Group.name (Geometry.groups one)
         = List.map Group.name (Geometry.groups four))
    "Group Ranges parallel output metadata differs";
  List.iter (fun (owner, name) ->
    let left = group owner name one and right = group owner name four in
    check (Bytes.equal (Group.Private.bits_view left)
        (Group.Private.bits_view right))
      ("Group Ranges domain mismatch for " ^ name))
    [Group.Point, "periodic"; Group.Point, "pieces";
     Group.Primitive, "partition"]

let () =
  test_point_components ();
  test_region_and_primitive_modes ();
  test_attribute_components ();
  test_collision_and_region_policy ();
  test_validation_and_cancellation ();
  test_parallel_exactness_and_scale ();
  test_multiple_ranges ();
  test_multiple_ranges_parallel_exactness ();
  print_endline "group range connectivity tests passed"
