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

let geometry_owned positions vertex_points primitive_offsets =
  let positions = Array.of_list positions in
  let point_count = Array.length positions in
  let x = Array.map (fun (x, _, _) -> x) positions
  and y = Array.map (fun (_, y, _) -> y) positions
  and z = Array.map (fun (_, _, z) -> z) positions in
  let topology = Topology.polygons_owned ~point_count ~vertex_points
      ~primitive_offsets |> get_ok in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_ok

let vertex_points geometry =
  (Topology.Private.view (Geometry.topology geometry)).vertex_points

let point_int name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry
      |> Option.get |> Attribute.Private.storage with
  | Attribute.Int values -> values
  | _ -> fail (name ^ " is not point integer")

let point_normal geometry =
  match Geometry.find_attribute ~owner:Attribute.Point "N" geometry
      |> Option.get |> Attribute.Private.storage with
  | Attribute.Float3 values -> Packed.Float3.Private.view values
  | _ -> fail "N is not point float3"

let edge_cardinality name geometry =
  Geometry.find_edge_group name geometry |> Option.get |> Edge_group.cardinality

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
  let lp = Packed.Float3.Private.view (Geometry.positions left)
  and rp = Packed.Float3.Private.view (Geometry.positions right)
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

let decorated_patch () =
  let base = geometry_owned
      [0.,0.,0.; 1.,0.,0.; 1.,1.,0.; 0.,1.,0.]
      [|0;1;2; 0;2;3|] [|0;3;6|] in
  let topology = Geometry.topology base in
  let cusp = edge_group_of_pairs topology "cusp" [|0,2;2,3|]
  and diagonal = edge_group_of_pairs topology "diagonal" [|0,2|] in
  let marked = Group.ordered ~owner:Group.Point ~name:"marked"
      ~length:4 [|2;0|] |> get_ok in
  Geometry.create ~positions:(Geometry.positions base) ~topology
    ~attributes:[
      attribute Attribute.Point "id" (Attribute.Int [|10;11;12;13|]);
      attribute Attribute.Point "N" (Attribute.Float3
        (Packed.Float3.Private.of_owned_exn ~x:[|1.;1.;1.;1.|]
          ~y:[|0.;0.;0.;0.|] ~z:[|0.;0.;0.;0.|]));
      attribute Attribute.Vertex "corner"
        (Attribute.Float [|0.;1.;2.;3.;4.;5.|]);
      attribute Attribute.Vertex "N" (Attribute.Float3
        (Packed.Float3.Private.of_owned_exn
          ~x:[|0.;0.;0.;0.;0.;0.|] ~y:[|1.;1.;1.;1.;1.;1.|]
          ~z:[|0.;0.;0.;0.;0.;0.|]));
      attribute Attribute.Primitive "material" (Attribute.Text [|"a";"b"|]);
      attribute Attribute.Detail "meta" (Attribute.Int [|42|]);
    ] ~groups:[marked] ~edge_groups:[cusp;diagonal] () |> get_ok

let disconnected_patches count =
  let points = count * 4 and vertices = count * 6 in
  let x = Array.make points 0. and y = Array.make points 0.
  and z = Array.make points 0. and vertex_points = Array.make vertices 0 in
  for patch = 0 to count - 1 do
    let p = patch * 4 and v = patch * 6 in
    let ox = float_of_int (patch mod 200) *. 2.
    and oy = float_of_int (patch / 200) *. 2. in
    x.(p) <- ox; y.(p) <- oy;
    x.(p + 1) <- ox +. 1.; y.(p + 1) <- oy;
    x.(p + 2) <- ox +. 1.; y.(p + 2) <- oy +. 1.;
    x.(p + 3) <- ox; y.(p + 3) <- oy +. 1.;
    vertex_points.(v) <- p; vertex_points.(v + 1) <- p + 1;
    vertex_points.(v + 2) <- p + 2; vertex_points.(v + 3) <- p;
    vertex_points.(v + 4) <- p + 2; vertex_points.(v + 5) <- p + 3
  done;
  let topology = Topology.polygons_owned ~point_count:points ~vertex_points
      ~primitive_offsets:(Array.init (count * 2 + 1) (fun face -> face * 3))
      |> get_ok in
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let geometry = Geometry.create ~positions ~topology () |> get_ok in
  let index = Topology_index.create topology in
  let cusp = Edge_group.init ~grain:127 ~topology ~index ~name:"cusp"
      (fun edge ->
        let a, b = Topology_index.edge_points index edge in
        let a = min a b and b = max a b and local = a mod 4 in
        (b - a = 2 && local = 0) || (b - a = 1 && local = 2)) in
  geometry, cusp

let () =
  let source = decorated_patch () in
  let cusp = Geometry.find_edge_group "cusp" source |> Option.get
  and diagonal = Geometry.find_edge_group "diagonal" source |> Option.get in
  let output = Ops.edge_cusp ~grain:1 ~edges:cusp source |> get_pdk in
  check (Geometry.point_count output = 5 && Geometry.vertex_count output = 6
      && Geometry.primitive_count output = 2)
    "Edge Cusp cardinality";
  check (vertex_points output = [|0;1;2; 0;4;3|])
    "Edge Cusp endpoint topology";
  check (point_int "id" output = [|10;11;12;13;12|])
    "Edge Cusp point-payload duplication";
  let marked = Geometry.find_group ~owner:Group.Point "marked" output
      |> Option.get in
  check (Group.cardinality marked = 3 && Group.mem 2 marked
      && Group.mem 4 marked && Group.mem 0 marked)
    "Edge Cusp point-group duplication";
  check (Group.ordered_elements marked = Some [|2;4;0|])
    "Edge Cusp ordered point-group ancestry";
  check (edge_cardinality "cusp" output = 3
      && edge_cardinality "diagonal" output = 2)
    "Edge Cusp native edge ancestry";
  let normals = point_normal output in
  check (normals.x = [|0.;0.;0.;0.;0.|]
      && normals.y = [|0.;0.;0.;0.;0.|]
      && normals.z = [|1.;1.;1.;1.;1.|])
    "Edge Cusp point-normal update";
  check (Geometry.find_attribute ~owner:Attribute.Vertex "N" output = None)
    "Edge Cusp normal update retained conflicting vertex normals";

  let preserved = Ops.edge_cusp ~grain:1 ~edges:cusp
      ~update_point_normals:false source |> get_pdk in
  let normals = point_normal preserved in
  check (normals.x = [|1.;1.;1.;1.;1.|]
      && normals.y = [|0.;0.;0.;0.;0.|]
      && normals.z = [|0.;0.;0.;0.;0.|])
    "Edge Cusp ignored disabled normal update";
  check (Geometry.find_attribute ~owner:Attribute.Vertex "N" preserved <> None)
    "Edge Cusp removed vertex normals with normal update disabled";
  let no_normals = Geometry.without_attribute ~owner:Attribute.Point "N"
      source |> Ops.edge_cusp ~edges:cusp |> get_pdk in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" no_normals = None)
    "Edge Cusp invented point normals";
  check (Ops.edge_cusp source |> get_pdk == source
      && Ops.edge_cusp ~edges:diagonal source |> get_pdk == source)
    "Edge Cusp empty/single-edge identity";
  let all_edges = edge_group_of_pairs (Geometry.topology source) "all"
      [|0,1;1,2;0,2;2,3;0,3|] in
  let branched = Ops.edge_cusp ~edges:all_edges source |> get_pdk in
  let seen = Bytes.make (Geometry.point_count branched) '\000' in
  Array.iter (fun point -> Bytes.set seen point '\001') (vertex_points branched);
  check (Geometry.point_count branched = 6
      && Bytes.for_all (( = ) '\001') seen)
    "Edge Cusp branching path fan separation";
  let tetrahedron = geometry_owned
      [0.,0.,0.;1.,0.,0.;0.5,1.,0.;0.5,0.4,1.]
      [|0;2;1; 0;1;3; 1;2;3; 2;0;3|] [|0;3;6;9;12|] in
  let loop = edge_group_of_pairs (Geometry.topology tetrahedron) "loop"
      [|0,1;1,2;2,0|] in
  let loop_output = Ops.edge_cusp ~edges:loop tetrahedron |> get_pdk in
  check (Geometry.point_count loop_output = 7
      && Geometry.vertex_count loop_output = 12)
    "Edge Cusp closed-loop fan separation";
  let point_touching = geometry_owned
      [0.,0.,0.;1.,0.,0.;1.,1.,0.;0.,1.,0.;2.,0.,0.;2.,1.,0.]
      [|0;1;2; 0;2;3; 1;4;5|] [|0;3;6;9|] in
  let point_touching_edges = edge_group_of_pairs
      (Geometry.topology point_touching) "cusp" [|0,2;2,3|] in
  let point_touching_output = Ops.edge_cusp ~edges:point_touching_edges
      point_touching |> get_pdk in
  check (Geometry.point_count point_touching_output = 7
      && (vertex_points point_touching_output).(6) = 1)
    "Edge Cusp split an unaffected point-touching fan";

  let other = decorated_patch () in
  let other_group = Geometry.find_edge_group "cusp" other |> Option.get in
  expect_code "invalid_topology" (Ops.edge_cusp ~edges:other_group source);
  expect_code "invalid_topology" (Ops.edge_cusp ~grain:0 ~edges:cusp source);
  let curve = Ops.polyline [|0.,0.,0.;1.,0.,0.;2.,0.,0.|] |> get_pdk in
  let curve_edges = edge_group_of_pairs (Geometry.topology curve) "curve"
      [|0,1;1,2|] in
  expect_code "invalid_topology" (Ops.edge_cusp ~edges:curve_edges curve);
  let nonmanifold = geometry_owned
      [0.,0.,0.;1.,0.,0.;0.5,1.,0.;0.5,-1.,0.;0.5,0.,1.]
      [|0;1;2; 1;0;3; 0;1;4|] [|0;3;6;9|] in
  let nonmanifold_edges = edge_group_of_pairs (Geometry.topology nonmanifold)
      "bad" [|0,1;1,2|] in
  expect_code "invalid_topology"
    (Ops.edge_cusp ~edges:nonmanifold_edges nonmanifold);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect_code "cancelled" (Ops.edge_cusp ~cancel:cancelled ~edges:cusp source);

  let large, large_edges = disconnected_patches 10_000 in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.edge_cusp ~grain:127 ~edges:large_edges large |> get_pdk) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four) "Edge Cusp differs across domain counts";
  check (Geometry.point_count one = 50_000
      && Geometry.vertex_count one = 60_000
      && Geometry.primitive_count one = 20_000)
    "Edge Cusp scale cardinality";
  print_endline "edge cusp tests passed"
