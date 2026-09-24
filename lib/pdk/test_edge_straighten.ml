open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error message -> fail message
let get_pdk = function Ok value -> value | Error error -> fail (Error.to_string error)

let attribute owner name storage =
  Attribute.create_owned ~owner ~name storage |> get_ok

let edge_group_of_pairs topology name pairs =
  let index = Topology_index.create topology in
  let selected = Array.map (fun (a, b) ->
      let edge = Topology_index.find_edge_index index ~a ~b in
      if edge < 0 then fail "test edge is absent";
      edge) pairs in
  Edge_group.init ~grain:1 ~topology ~index ~name (fun edge ->
    Array.mem edge selected)

let geometry_owned ~kinds positions vertex_points primitive_offsets =
  let positions = Array.of_list positions in
  let point_count = Array.length positions in
  let x = Array.map (fun (x, _, _) -> x) positions
  and y = Array.map (fun (_, y, _) -> y) positions
  and z = Array.map (fun (_, _, z) -> z) positions in
  let topology = Topology.create_owned ~point_count ~vertex_points
      ~primitive_offsets ~primitive_kinds:kinds |> get_ok in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_ok

let positions geometry = Packed.Float3.Private.view (Geometry.positions geometry)

let equal_attribute left right =
  Attribute.owner left = Attribute.owner right
  && Attribute.name left = Attribute.name right
  && match Attribute.Private.storage left, Attribute.Private.storage right with
     | Attribute.Float a, Attribute.Float b -> a = b
     | Attribute.Int a, Attribute.Int b -> a = b
     | Attribute.Text a, Attribute.Text b -> a = b
     | Attribute.Float3 a, Attribute.Float3 b ->
         let a = Packed.Float3.Private.view a
         and b = Packed.Float3.Private.view b in
         a.x = b.x && a.y = b.y && a.z = b.z
     | _ -> false

let equal_group left right =
  Group.owner left = Group.owner right && Group.name left = Group.name right
  && Group.length left = Group.length right
  && Group.ordered_elements left = Group.ordered_elements right
  && let equal = ref true in
     for i = 0 to Group.length left - 1 do
       if Group.mem i left <> Group.mem i right then equal := false
     done;
     !equal

let equal_edge_group left right =
  Edge_group.name left = Edge_group.name right
  && Edge_group.length left = Edge_group.length right
  && let equal = ref true in
     for edge = 0 to Edge_group.length left - 1 do
       if Edge_group.mem edge left <> Edge_group.mem edge right then
         equal := false
     done;
     !equal

let equal_geometry left right =
  let lp = positions left and rp = positions right
  and lt = Topology.Private.view (Geometry.topology left)
  and rt = Topology.Private.view (Geometry.topology right) in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && lt.point_count = rt.point_count
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && List.equal equal_attribute (Geometry.attributes left)
       (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group (Geometry.edge_groups left)
       (Geometry.edge_groups right)

let expect_code code = function
  | Error error when Error.code error = code -> ()
  | Error error -> fail (Printf.sprintf "expected %s, received %s: %s"
      code (Error.code error) (Error.to_string error))
  | Ok _ -> fail ("expected error " ^ code)

let decorated_bend () =
  let base = Ops.polyline [|-1.,0.,0.; 0.,1.,0.; 1.,0.,0.|] |> get_pdk in
  let topology = Geometry.topology base in
  let bend = edge_group_of_pairs topology "bend" [|0,1;1,2|]
  and first = edge_group_of_pairs topology "first" [|0,1|] in
  let ordered = Group.ordered ~owner:Group.Point ~name:"ordered"
      ~length:3 [|2;0|] |> get_ok in
  Geometry.create ~positions:(Geometry.positions base) ~topology
    ~attributes:[
      attribute Attribute.Point "id" (Attribute.Int [|10;11;12|]);
      attribute Attribute.Point "N" (Attribute.Float3
        (Packed.Float3.Private.of_owned_exn ~x:[|0.;0.;0.|]
          ~y:[|0.;0.;0.|] ~z:[|1.;1.;1.|]));
      attribute Attribute.Vertex "corner" (Attribute.Float [|3.;4.;5.|]);
      attribute Attribute.Vertex "N" (Attribute.Float3
        (Packed.Float3.Private.of_owned_exn ~x:[|0.;0.;0.|]
          ~y:[|0.;0.;0.|] ~z:[|1.;1.;1.|]));
      attribute Attribute.Primitive "material" (Attribute.Text [|"wire"|]);
      attribute Attribute.Detail "meta" (Attribute.Int [|42|]);
    ] ~groups:[ordered] ~edge_groups:[bend;first] () |> get_ok

let many_bends count =
  let point_count = count * 3 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for component = 0 to count - 1 do
    let point = component * 3
    and ox = float_of_int (component mod 500) *. 4.
    and oy = float_of_int (component / 500) *. 3. in
    x.(point) <- ox -. 1.; y.(point) <- oy;
    x.(point + 1) <- ox; y.(point + 1) <- oy +. 1.;
    x.(point + 2) <- ox +. 1.; y.(point + 2) <- oy
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (count + 1) (fun primitive -> primitive * 3))
      ~primitive_kinds:(Array.make count Topology.Open_polyline) |> get_ok in
  Geometry.create ~positions ~topology
    ~attributes:[attribute Attribute.Point "id"
      (Attribute.Int (Array.init point_count Fun.id))] () |> get_ok

let () =
  let source = decorated_bend () in
  let bend = Geometry.find_edge_group "bend" source |> Option.get
  and first = Geometry.find_edge_group "first" source |> Option.get in
  let output = Ops.edge_straighten ~grain:1 ~edges:bend
      ~output_group:"straightened" source |> get_pdk in
  let output_positions = positions output in
  check (output_positions.x = [|-1.;0.;1.|]
      && output_positions.y = [|1. /. 3.;1. /. 3.;1. /. 3.|]
      && output_positions.z = [|0.;0.;0.|])
    "Edge Straighten least-squares projection";
  check (Geometry.topology output == Geometry.topology source
      && (Geometry.find_attribute ~owner:Attribute.Point "id" output
          |> Option.get)
         == (Geometry.find_attribute ~owner:Attribute.Point "id" source
             |> Option.get)
      && (Geometry.find_attribute ~owner:Attribute.Vertex "corner" output
          |> Option.get)
         == (Geometry.find_attribute ~owner:Attribute.Vertex "corner" source
             |> Option.get))
    "Edge Straighten structural payload sharing";
  check (Geometry.find_attribute ~owner:Attribute.Point "N" output = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" output = None)
    "Edge Straighten retained stale normals";
  let straightened = Geometry.find_edge_group "straightened" output
      |> Option.get in
  check (Edge_group.cardinality straightened = 2)
    "Edge Straighten output group";
  let ordered = Geometry.find_group ~owner:Group.Point "ordered" output
      |> Option.get in
  check (Group.ordered_elements ordered = Some [|2;0|])
    "Edge Straighten changed ordered groups";

  check (Ops.edge_straighten ~edges:first source |> get_pdk == source)
    "single-edge straighten was not an identity";
  let line = Ops.polyline [|0.,0.,0.;1.,2.,3.;2.,4.,6.;3.,6.,9.|]
      |> get_pdk in
  check (Ops.edge_straighten line |> get_pdk == line)
    "already-straight component was not an identity";
  let empty = Edge_group.init ~grain:1 ~topology:(Geometry.topology source)
      ~index:(Topology_index.create (Geometry.topology source)) ~name:"empty"
      (Fun.const false) in
  check (Ops.edge_straighten ~edges:empty source |> get_pdk == source)
    "empty Edge Straighten was not an identity";
  let with_empty_output = Ops.edge_straighten ~edges:empty
      ~output_group:"empty_output" source |> get_pdk in
  check (Geometry.find_edge_group "empty_output" with_empty_output
      |> Option.get |> Edge_group.cardinality = 0)
    "Edge Straighten omitted empty output group";

  let square = Ops.polyline ~closed:true
      [|-1.,-1.,0.;1.,-1.,0.;1.,1.,0.;-1.,1.,0.|] |> get_pdk in
  let square_output = Ops.edge_straighten square |> get_pdk in
  let square_positions = positions square_output in
  check (square_positions.y = [|0.;0.;0.;0.|])
    "Edge Straighten cycle did not use deterministic principal-axis tie";
  let branch = geometry_owned
      ~kinds:(Array.make 4 Topology.Open_polyline)
      [0.,0.,0.; -2.,0.,0.; 2.,0.,0.; 0.,-1.,0.; 0.,1.,0.]
      [|0;1; 0;2; 0;3; 0;4|] [|0;2;4;6;8|] in
  let branch_output = Ops.edge_straighten branch |> get_pdk in
  check ((positions branch_output).y = [|0.;0.;0.;0.;0.|])
    "Edge Straighten branch did not become collinear";
  let x_extent = sqrt 1.5 in
  let covariance_trap = Ops.polyline
      [|-.x_extent,0.,0.; x_extent,0.,0.; 0.,-1.,-1.; 0.,1.,1.|]
      |> get_pdk |> Ops.edge_straighten |> get_pdk in
  let covariance_positions = positions covariance_trap in
  check (Array.for_all (fun value -> abs_float value < 1e-12)
      covariance_positions.x
      && Array.for_all Fun.id (Array.init 4 (fun point ->
        abs_float (covariance_positions.y.(point)
          -. covariance_positions.z.(point)) < 1e-12)))
    "Edge Straighten power iteration selected a subdominant covariance axis";

  let other = decorated_bend () in
  let other_edges = Geometry.find_edge_group "bend" other |> Option.get in
  expect_code "invalid_geometry"
    (Ops.edge_straighten ~edges:other_edges source);
  expect_code "invalid_geometry"
    (Ops.edge_straighten ~output_group:" " source);
  expect_code "invalid_geometry" (Ops.edge_straighten ~grain:0 source);
  let non_finite = geometry_owned ~kinds:[|Topology.Open_polyline|]
      [0.,0.,0.;nan,1.,0.;2.,0.,0.] [|0;1;2|] [|0;3|] in
  expect_code "invalid_geometry" (Ops.edge_straighten non_finite);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled" (Ops.edge_straighten ~cancel:cancelled source);

  let large = many_bends 50_000 in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.edge_straighten ~grain:127 large |> get_pdk) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "Edge Straighten differs across domain counts";
  check (Geometry.point_count one = 150_000
      && Geometry.vertex_count one = 150_000
      && Geometry.primitive_count one = 50_000)
    "Edge Straighten scale cardinality";
  print_endline "edge straighten tests passed"
