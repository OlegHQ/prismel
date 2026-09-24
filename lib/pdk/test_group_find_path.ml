open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let geometry positions curves =
  let packed = Packed.Float3.Private.of_owned_exn
      ~x:(Array.map (fun (x, _, _) -> x) positions)
      ~y:(Array.map (fun (_, y, _) -> y) positions)
      ~z:(Array.map (fun (_, _, z) -> z) positions) in
  let topology = Topology.Builder.create ~point_count:(Array.length positions) () in
  Array.iter (Topology.Builder.add_open_polyline topology) curves;
  Geometry.create ~positions:packed ~topology:(Topology.Builder.freeze topology) ()
  |> function Ok value -> value | Error message -> fail message

let ordered name length elements =
  Group.ordered ~owner:Group.Point ~name ~length elements
  |> function Ok value -> value | Error message -> fail message

let ordinary name geometry =
  match Geometry.find_group ~owner:Group.Point name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let order group =
  match Group.ordered_elements group with
  | Some values -> values
  | None -> fail ("group " ^ Group.name group ^ " is not ordered")

let primitive_fan () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; -1.; 1.; 1.; -1.|]
      ~y:[|0.; 0.; 0.; 0.; 0.|]
      ~z:[|0.; -1.; -1.; 1.; 1.|] in
  let topology = Topology.Builder.create ~point_count:5 () in
  Topology.Builder.add_triangle topology 0 1 2;
  Topology.Builder.add_triangle topology 0 2 3;
  Topology.Builder.add_triangle topology 0 3 4;
  Topology.Builder.add_triangle topology 0 4 1;
  Geometry.create ~positions ~topology:(Topology.Builder.freeze topology) ()
  |> function Ok value -> value | Error message -> fail message

let ordered_primitives name length elements =
  Group.ordered ~owner:Group.Primitive ~name ~length elements
  |> function Ok value -> value | Error message -> fail message

let diamond ?(upper_y = 2.) ?(lower_y = 0.1) () =
  geometry
    [|(0., 0., 0.); (1., upper_y, 0.); (1., lower_y, 0.);
      (2., 0., 0.); (3., 0., 0.)|]
    [|[|0; 1; 3|]; [|0; 2; 3|]; [|3; 4|]|]

let test_shortest_and_modes () =
  let source = diamond () in
  let through = Ops.group_find_path ~grain:1
      ~base:(ordered "base" 5 [|0; 3; 4|]) ~name:"path" source |> get_ok in
  check (order (ordinary "path" through) = [|0; 2; 3; 4|])
    "through mode minimizes hops then length and joins contiguous segments";
  let tied = diamond ~upper_y:1. ~lower_y:(-1.) () in
  let tie = Ops.group_find_path ~grain:1
      ~base:(ordered "base" 5 [|0; 3|]) ~name:"path" tied |> get_ok in
  check (order (ordinary "path" tie) = [|0; 1; 3|])
    "equal hop/equal length path uses stable lower-point predecessor";
  let pairs = Ops.group_find_path ~grain:1 ~mode:Ops.Start_end_pairs
      ~avoid_self_intersection:false
      ~base:(ordered "base" 5 [|0; 3; 1; 4|]) ~name:"pairs" source |> get_ok in
  check (order (ordinary "pairs" pairs) = [|0; 2; 3; 1; 4|])
    "pair mode preserves pair order and first point occurrence";
  (match Ops.group_find_path ~grain:1 ~mode:Ops.Start_end_pairs
      ~base:(ordered "base" 5 [|0; 3; 1; 4|]) ~name:"blocked" source with
   | Error error -> check (Error.code error = "invalid_group")
       "self-intersection failure has structured code"
   | Ok _ -> fail "self-intersection avoidance reused an earlier path point")

let test_collision_constraints () =
  let source = diamond () in
  let base = ordered "base" 5 [|0; 3|] in
  let avoid = Group.init ~owner:Group.Point ~name:"avoid" 5
      (fun point -> point = 2) in
  let avoided = Ops.group_find_path ~grain:1 ~collision:avoid ~base
      ~name:"avoided" source |> get_ok in
  check (order (ordinary "avoided" avoided) = [|0; 1; 3|])
    "collision group excludes points";
  let region = Group.init ~owner:Group.Point ~name:"region" 5
      (fun point -> point = 0 || point = 2 || point = 3) in
  let contained = Ops.group_find_path ~grain:1 ~collision:region ~contain:true
      ~base ~name:"contained" source |> get_ok in
  check (order (ordinary "contained" contained) = [|0; 2; 3|])
    "contain mode restricts traversal to the collision group";
  (match Ops.group_find_path ~grain:1 ~contain:true ~base ~name:"bad" source with
   | Error error -> check (Error.code error = "invalid_group")
       "contain-without-group structured code"
   | Ok _ -> fail "contain mode accepted a missing collision group");
  (match Ops.group_find_path ~grain:1 ~collision:avoid
      ~base:(ordered "single" 5 [|2|]) ~name:"bad" source with
   | Error _ -> ()
   | Ok _ -> fail "single constrained base point bypassed validation")

let test_closure () =
  let square = geometry
      [|(0.,0.,0.); (1.,0.,0.); (1.,1.,0.); (0.,1.,0.)|]
      [|[|0; 1; 2|]; [|0; 3; 2|]|] in
  let closed = Ops.group_find_path ~grain:1 ~ending:Ops.Close_path
      ~base:(ordered "base" 4 [|0; 2|]) ~name:"loop" square |> get_ok in
  check (order (ordinary "loop" closed) = [|0; 1; 2; 3|])
    "close mode finds a non-overlapping secondary path";
  let line = geometry [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
      [|[|0; 1; 2|]|] in
  (match Ops.group_find_path ~grain:1 ~ending:Ops.Close_path
      ~base:(ordered "base" 3 [|0; 2|]) ~name:"loop" line with
   | Error error -> check (Error.code error = "invalid_group")
       "missing closure structured code"
   | Ok _ -> fail "close mode reused the primary line")

let test_primitive_paths () =
  let source = primitive_fan () in
  let base = ordered_primitives "base" 4 [|0; 2|] in
  let path = Ops.group_find_path ~grain:1 ~base ~name:"path" source |> get_ok in
  let path = Geometry.find_group ~owner:Group.Primitive "path" path
      |> Option.get in
  check (order path = [|0; 1; 2|])
    "primitive path uses stable shared-edge dual traversal";
  let collision = Group.init ~owner:Group.Primitive ~name:"avoid" 4
      (fun primitive -> primitive = 1) in
  let avoided = Ops.group_find_path ~grain:1 ~collision ~base
      ~name:"avoided" source |> get_ok in
  check (order (Geometry.find_group ~owner:Group.Primitive "avoided" avoided
      |> Option.get) = [|0; 3; 2|])
    "primitive collision group excludes dual-graph faces";
  let region = Group.init ~owner:Group.Primitive ~name:"region" 4
      (fun primitive -> primitive <> 1) in
  let contained = Ops.group_find_path ~grain:1 ~collision:region ~contain:true
      ~base ~name:"contained" source |> get_ok in
  check (order (Geometry.find_group ~owner:Group.Primitive "contained" contained
      |> Option.get) = [|0; 3; 2|])
    "primitive collision containment restricts the dual graph";
  let closed = Ops.group_find_path ~grain:1 ~ending:Ops.Close_path ~base
      ~name:"loop" source |> get_ok in
  check (order (Geometry.find_group ~owner:Group.Primitive "loop" closed
      |> Option.get) = [|0; 1; 2; 3|])
    "primitive close mode blocks primary shared edges";
  let nonmanifold_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 0.; 0.;|] ~y:[|0.; 0.; 1.; -1.|]
      ~z:[|0.; 0.; 0.; 1.|] in
  let nonmanifold_topology = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_triangle nonmanifold_topology 0 1 2;
  Topology.Builder.add_triangle nonmanifold_topology 1 0 3;
  Topology.Builder.add_triangle nonmanifold_topology 0 1 3;
  let nonmanifold = Geometry.create ~positions:nonmanifold_positions
      ~topology:(Topology.Builder.freeze nonmanifold_topology) ()
      |> function Ok value -> value | Error message -> fail message in
  (match Ops.group_find_path
      ~base:(ordered_primitives "base" 3 [|0; 2|]) ~name:"path"
      nonmanifold with
   | Error error -> check (Error.code error = "invalid_group")
       "non-manifold primitive path structured code"
   | Ok _ -> fail "primitive path accepted non-manifold shared edges")

let test_validation_and_cancellation () =
  let source = diamond () in
  let unordered = Group.init ~owner:Group.Point ~name:"base" 5
      (fun point -> point = 0 || point = 3) in
  (match Ops.group_find_path ~base:unordered ~name:"path" source with
   | Error error -> check (Error.code error = "invalid_group")
       "unordered base structured code"
   | Ok _ -> fail "Group Find Path accepted an unordered base");
  (match Ops.group_find_path ~mode:Ops.Start_end_pairs
      ~base:(ordered "base" 5 [|0; 3; 4|]) ~name:"path" source with
   | Error _ -> () | Ok _ -> fail "pair mode accepted an odd base count");
  let disconnected = geometry
      [|(0.,0.,0.); (1.,0.,0.); (5.,0.,0.); (6.,0.,0.)|]
      [|[|0; 1|]; [|2; 3|]|] in
  (match Ops.group_find_path ~base:(ordered "base" 4 [|0; 3|])
      ~name:"path" disconnected with
   | Error _ -> () | Ok _ -> fail "disconnected path unexpectedly succeeded");
  let nonfinite = geometry [|(0.,0.,0.); (Float.nan,0.,0.)|] [|[|0; 1|]|] in
  (match Ops.group_find_path ~base:(ordered "base" 2 [|0; 1|])
      ~name:"path" nonfinite with
   | Error _ -> () | Ok _ -> fail "non-finite path geometry succeeded");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Ops.group_find_path ~cancel ~base:(ordered "base" 5 [|0; 3|])
      ~name:"path" source with
   | Error error -> check (Error.code error = "cancelled")
       "cancelled path structured code"
   | Ok _ -> fail "cancelled Group Find Path published geometry")

let test_parallel_exactness () =
  let source = Ops.grid ~columns:120 ~rows:90 ~size:20. () |> get_ok in
  let columns = 121 in
  let point row column = (row * columns) + column in
  let pair_count = 16 in
  let elements = Array.init (pair_count * 2) (fun index ->
    let pair = index / 2 in
    if index land 1 = 0 then point (pair * 5) 0
    else point (pair * 5) 120) in
  let base = ordered "base" (Geometry.point_count source) elements in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.group_find_path ~grain:257 ~mode:Ops.Start_end_pairs
      ~avoid_self_intersection:false ~base ~name:"paths" source |> get_ok) in
  let one = ordinary "paths" (run 1) and four = ordinary "paths" (run 4) in
  check (order one = order four)
    "Group Find Path one/four-domain ordered result exactness";
  let primitive_count = Geometry.primitive_count source in
  let primitive_elements = Array.init 16 (fun index ->
    let first = (index / 2) * 2_000 in
    if index land 1 = 0 then first else min (primitive_count - 1) (first + 239)) in
  let primitive_base = ordered_primitives "primitive_base" primitive_count
      primitive_elements in
  let run_primitives domains = Parallel.run ~domains (fun () ->
    Ops.group_find_path ~grain:257 ~mode:Ops.Start_end_pairs
      ~avoid_self_intersection:false ~base:primitive_base
      ~name:"primitive_paths" source |> get_ok) in
  let one = Geometry.find_group ~owner:Group.Primitive "primitive_paths"
      (run_primitives 1) |> Option.get
  and four = Geometry.find_group ~owner:Group.Primitive "primitive_paths"
      (run_primitives 4) |> Option.get in
  check (order one = order four)
    "primitive Group Find Path one/four-domain ordered exactness"

let () =
  test_shortest_and_modes ();
  test_collision_constraints ();
  test_closure ();
  test_primitive_paths ();
  test_validation_and_cancellation ();
  test_parallel_exactness ();
  print_endline "group find path tests passed"
