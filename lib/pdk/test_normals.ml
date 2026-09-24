open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_string = function Ok value -> value | Error error -> fail error
let get_pdk = function Ok value -> value | Error error -> fail (Error.to_string error)
let near a b = abs_float (a -. b) <= 1e-10

let attribute owner name storage =
  Attribute.create_owned ~owner ~name storage |> get_string

let source () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;0.;0.;4.|] ~y:[|0.;0.;1.;0.;4.|]
      ~z:[|0.;0.;0.;2.;4.|] in
  let topology = Topology.polygons_owned ~point_count:5
      ~vertex_points:[|0;1;2; 0;2;3|]
      ~primitive_offsets:[|0;3;6|] |> get_string in
  let selected_point = Group.ordered ~owner:Group.Point ~name:"selected_point"
      ~length:5 [|0|] |> get_string
  and selected_vertex = Group.ordered ~owner:Group.Vertex ~name:"selected_vertex"
      ~length:6 [|0;3|] |> get_string
  and single_vertex = Group.ordered ~owner:Group.Vertex ~name:"single_vertex"
      ~length:6 [|1|] |> get_string
  and selected_primitive = Group.ordered ~owner:Group.Primitive
      ~name:"selected_primitive" ~length:2 [|1|] |> get_string in
  Geometry.create ~positions ~topology
    ~groups:[selected_point; selected_vertex; single_vertex; selected_primitive] ()
    |> get_string
  |> Ops.group_edges ~name:"all_edges" |> get_pdk

let normal owner ?(name = "N") geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some value ->
      (match Attribute.Private.storage value with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail "normal attribute has wrong storage")
  | None -> fail "normal attribute is missing"

let check_vec values index (x, y, z) message =
  check (near values.Packed.Float3.Private.x.(index) x
      && near values.y.(index) y && near values.z.(index) z) message

let group owner name geometry =
  Geometry.find_group ~owner name geometry |> Option.get

let equal_normals owner left right =
  let left = normal owner left and right = normal owner right in
  left.x = right.x && left.y = right.y && left.z = right.z

let test_owners_and_weighting () =
  let geometry = source () in
  let area = Ops.normals ~weighting:Ops.Face_area geometry |> get_pdk in
  let equal = Ops.normals ~weighting:Ops.Each_vertex geometry |> get_pdk in
  let angle = Ops.normals ~weighting:Ops.Vertex_angle geometry |> get_pdk in
  let area_n = normal Attribute.Point area
  and equal_n = normal Attribute.Point equal
  and angle_n = normal Attribute.Point angle in
  let sqrt5 = sqrt 5. and sqrt2 = sqrt 2. in
  check_vec area_n 0 (2. /. sqrt5, 0., 1. /. sqrt5)
    "face-area point normal";
  check_vec equal_n 0 (1. /. sqrt2, 0., 1. /. sqrt2)
    "equal-corner point normal";
  check_vec angle_n 0 (1. /. sqrt2, 0., 1. /. sqrt2)
    "vertex-angle point normal";
  check (not (near angle_n.x.(2) equal_n.x.(2)))
    "vertex-angle weighting did not account for corner angle";
  check_vec area_n 4 (0., 0., 0.) "isolated point normal";
  let primitive = Ops.normals ~owner:Attribute.Primitive geometry |> get_pdk
      |> normal Attribute.Primitive in
  check_vec primitive 0 (0., 0., 1.) "first primitive normal";
  check_vec primitive 1 (1., 0., 0.) "second primitive normal";
  let detail = Ops.normals ~owner:Attribute.Detail geometry |> get_pdk
      |> normal Attribute.Detail in
  check_vec detail 0 (2. /. sqrt5, 0., 1. /. sqrt5)
    "area-weighted detail normal"

let test_vertex_cusp () =
  let geometry = source () in
  let hard = Ops.normals ~owner:Attribute.Vertex ~weighting:Ops.Each_vertex
      ~cusp_angle:0. geometry |> get_pdk |> normal Attribute.Vertex in
  for vertex = 0 to 2 do
    check_vec hard vertex (0., 0., 1.) "hard first-face vertex normal"
  done;
  for vertex = 3 to 5 do
    check_vec hard vertex (1., 0., 0.) "hard second-face vertex normal"
  done;
  let smooth = Ops.normals ~owner:Attribute.Vertex ~weighting:Ops.Each_vertex
      ~cusp_angle:Float.pi geometry |> get_pdk |> normal Attribute.Vertex in
  let diagonal = 1. /. sqrt 2. in
  List.iter (fun vertex -> check_vec smooth vertex (diagonal, 0., diagonal)
      "smooth shared vertex normal") [0;2;3;4];
  check_vec smooth 1 (0.,0.,1.) "smooth unique first-face normal";
  check_vec smooth 5 (1.,0.,0.) "smooth unique second-face normal";
  let cusped = Ops.normals ~owner:Attribute.Vertex ~weighting:Ops.Each_vertex
      ~cusp_angle:(Float.pi /. 4.) geometry |> get_pdk
      |> normal Attribute.Vertex in
  check_vec cusped 0 (0.,0.,1.) "cusped first face";
  check_vec cusped 3 (1.,0.,0.) "cusped second face"

let with_constant_normal owner geometry =
  let count = match owner with
    | Attribute.Point -> Geometry.point_count geometry
    | Vertex -> Geometry.vertex_count geometry
    | Primitive -> Geometry.primitive_count geometry
    | Detail -> 1 in
  let values = Packed.Float3.Private.of_owned_exn
      ~x:(Array.make count 0.) ~y:(Array.make count 1.)
      ~z:(Array.make count 0.) in
  Geometry.with_attribute
    (attribute owner "N" (Attribute.Float3 values)) geometry |> get_string

let test_selection_and_existing_values () =
  let geometry = source () |> with_constant_normal Attribute.Vertex in
  let selection = Ops.Selected_points (group Group.Point "selected_point" geometry) in
  let selected = Ops.normals ~owner:Attribute.Vertex ~weighting:Ops.Each_vertex
      ~cusp_angle:0. ~selection ~reverse:true geometry |> get_pdk
      |> normal Attribute.Vertex in
  check_vec selected 0 (0.,0.,-1.) "selected reversed first vertex";
  check_vec selected 3 (-1.,0.,0.) "selected reversed second vertex";
  List.iter (fun vertex -> check_vec selected vertex (0.,1.,0.)
      "unselected existing vertex normal changed") [1;2;4;5];
  let missing = source () in
  let selection = Ops.Selected_points
      (group Group.Point "selected_point" missing) in
  let initialized = Ops.normals ~owner:Attribute.Vertex
      ~weighting:Ops.Each_vertex ~cusp_angle:0. ~selection missing |> get_pdk
      |> normal Attribute.Vertex in
  check_vec initialized 0 (0.,0.,1.) "selected hard initialization";
  check_vec initialized 3 (1.,0.,0.) "selected second hard initialization";
  let diagonal = 1. /. sqrt 2. in
  check_vec initialized 2 (diagonal,0.,diagonal)
    "unselected vertex did not receive smooth initialization";
  let point_missing = Ops.normals ~selection missing |> get_pdk
      |> normal Attribute.Point in
  check (not (near point_missing.z.(1) 0.)
      && not (near point_missing.x.(3) 0.))
    "missing point N incorrectly restricted computation to the group";
  let point_existing = source () |> with_constant_normal Attribute.Point in
  let point_selection = Ops.Selected_points
      (group Group.Point "selected_point" point_existing) in
  let point_selected = Ops.normals ~selection:point_selection point_existing
      |> get_pdk |> normal Attribute.Point in
  check_vec point_selected 1 (0.,1.,0.)
    "unselected existing point normal changed"

let test_edge_selection_zero_and_custom_name () =
  let geometry = source () in
  let topology = Geometry.topology geometry in
  let index = Topology_index.create topology in
  let shared_edge = Topology_index.find_edge_index index ~a:0 ~b:2 in
  let edge = Edge_group.init ~topology ~index ~name:"shared"
      (fun value -> value = shared_edge) in
  let geometry = Geometry.with_edge_group edge geometry |> get_string
      |> with_constant_normal Attribute.Primitive in
  let selected = Ops.normals ~owner:Attribute.Primitive
      ~selection:(Ops.Selected_edges edge) ~reverse:true geometry |> get_pdk
      |> normal Attribute.Primitive in
  check_vec selected 0 (0.,0.,-1.) "edge-selected first primitive";
  check_vec selected 1 (-1.,0.,0.) "edge-selected second primitive";
  let point_existing = source () |> with_constant_normal Attribute.Point in
  let kept = Ops.normals ~keep_original_zero:true point_existing |> get_pdk
      |> normal Attribute.Point in
  check_vec kept 4 (0.,1.,0.) "zero normal did not preserve existing value";
  let cleared = Ops.normals point_existing |> get_pdk |> normal Attribute.Point in
  check_vec cleared 4 (0.,0.,0.) "zero normal was unexpectedly preserved";
  let custom = Ops.normals ~owner:Attribute.Detail ~attribute:"flow"
      ~reverse:true (source ()) |> get_pdk in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" custom = None)
    "custom normal unexpectedly created N";
  let custom = normal ~name:"flow" Attribute.Detail custom in
  let sqrt5 = sqrt 5. in
  check_vec custom 0 (-2. /. sqrt5, 0., -1. /. sqrt5)
    "custom reversed detail normal"

let changed_indices owner geometry =
  let values = normal owner geometry in
  let changed = ref [] in
  for index = 0 to Array.length values.x - 1 do
    if not (near values.x.(index) 0. && near values.y.(index) 1.
        && near values.z.(index) 0.) then changed := index :: !changed
  done;
  List.rev !changed

let test_selection_promotion_matrix () =
  let base = source () in
  let topology = Geometry.topology base and index =
      Topology_index.create (Geometry.topology base) in
  let shared = Topology_index.find_edge_index index ~a:0 ~b:2 in
  let edge = Edge_group.init ~topology ~index ~name:"shared"
      (fun value -> value = shared) in
  let base = Geometry.with_edge_group edge base |> get_string in
  let point = Ops.Selected_points (group Group.Point "selected_point" base)
  and vertex = Ops.Selected_vertices (group Group.Vertex "single_vertex" base)
  and primitive = Ops.Selected_primitives
      (group Group.Primitive "selected_primitive" base)
  and edge = Ops.Selected_edges edge in
  let run owner selection = base |> with_constant_normal owner
      |> Ops.normals ~owner ~selection |> get_pdk |> changed_indices owner in
  check (run Attribute.Point point = [0]) "point-to-point selection promotion";
  check (run Attribute.Vertex point = [0;3]) "point-to-vertex selection promotion";
  check (run Attribute.Primitive point = [0;1])
    "point-to-primitive selection promotion";
  check (run Attribute.Point vertex = [1]) "vertex-to-point selection promotion";
  check (run Attribute.Vertex vertex = [1]) "vertex-to-vertex selection promotion";
  check (run Attribute.Primitive vertex = [0])
    "vertex-to-primitive selection promotion";
  check (run Attribute.Point primitive = [0;2;3])
    "primitive-to-point selection promotion";
  check (run Attribute.Vertex primitive = [3;4;5])
    "primitive-to-vertex selection promotion";
  check (run Attribute.Primitive primitive = [1])
    "primitive-to-primitive selection promotion";
  check (run Attribute.Point edge = [0;2]) "edge-to-point selection promotion";
  check (run Attribute.Vertex edge = [0;2;3;4])
    "edge-to-vertex selection promotion";
  check (run Attribute.Primitive edge = [0;1])
    "edge-to-primitive selection promotion"

let test_parallel_and_errors () =
  let run domains = Parallel.run ~domains (fun () ->
    Ops.grid ~connectivity:Ops.Grid_quads ~columns:220 ~rows:180 ~size:10. ()
    |> get_pdk
    |> Ops.normals ~grain:257 ~owner:Attribute.Vertex
         ~weighting:Ops.Vertex_angle ~cusp_angle:(Float.pi /. 3.)
    |> get_pdk) in
  let one = run 1 and four = run 4 in
  check (equal_normals Attribute.Vertex one four)
    "vertex normals differ across one and four domains";
  let geometry = source () in
  let point_group = group Group.Point "selected_point" geometry in
  let wrong = Group.Private.with_owner Group.Vertex point_group in
  List.iter (fun operation -> match operation () with
    | Error error -> check (Error.code error = "invalid_topology")
        "normal validation error code"
    | Ok _ -> fail "Normals accepted invalid input") [
      (fun () -> Ops.normals ~grain:0 geometry);
      (fun () -> Ops.normals ~cusp_angle:(-0.1) geometry);
      (fun () -> Ops.normals ~cusp_angle:Float.nan geometry);
      (fun () -> Ops.normals ~attribute:"" geometry);
      (fun () -> Ops.normals ~selection:(Ops.Selected_points wrong) geometry);
    ];
  let scalar = Geometry.with_attribute
      (attribute Attribute.Point "N" (Attribute.Float (Array.make 5 1.))) geometry
      |> get_string in
  (match Ops.normals scalar with
   | Error error -> check (Error.code error = "invalid_topology")
       "scalar N diagnostic code"
   | Ok _ -> fail "Normals accepted scalar N");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Ops.normals ~cancel geometry with
   | Error error -> check (Error.code error = "cancelled")
       "normal cancellation code"
   | Ok _ -> fail "Normals ignored cancellation")

let () =
  test_owners_and_weighting ();
  test_vertex_cusp ();
  test_selection_and_existing_values ();
  test_edge_selection_zero_and_custom_name ();
  test_selection_promotion_matrix ();
  test_parallel_and_errors ();
  print_endline "Normals tests passed"
