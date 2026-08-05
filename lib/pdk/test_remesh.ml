open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error error -> fail (Error.to_string error)
let get_string = function Ok value -> value | Error message -> fail message

let add_attribute ~owner ~name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> get_string in
  Geometry.with_attribute attribute geometry |> get_string

let grid ?(columns = 7) ?(rows = 6) ?(size = 6.) () =
  Ops.grid ~counts:Ops.Grid_point_counts
    ~connectivity:Ops.Grid_alternating_triangles ~columns ~rows ~size () |> get

let attribute_equal left right =
  Attribute.owner left = Attribute.owner right
  && Attribute.name left = Attribute.name right
  && match Attribute.Private.storage left, Attribute.Private.storage right with
  | Attribute.Float a, Attribute.Float b -> a = b
  | Attribute.Int a, Attribute.Int b -> a = b
  | Attribute.Text a, Attribute.Text b -> a = b
  | Attribute.Float2 a, Attribute.Float2 b ->
      let a = Packed.Float2.Private.view a and b = Packed.Float2.Private.view b in
      a.x = b.x && a.y = b.y
  | Attribute.Float3 a, Attribute.Float3 b ->
      let a = Packed.Float3.Private.view a and b = Packed.Float3.Private.view b in
      a.x = b.x && a.y = b.y && a.z = b.z
  | Attribute.Float4 a, Attribute.Float4 b ->
      let a = Packed.Float4.Private.view a and b = Packed.Float4.Private.view b in
      a.x = b.x && a.y = b.y && a.z = b.z && a.w = b.w
  | Attribute.Int_array a, Attribute.Int_array b ->
      let a = Packed.Int_array.Private.view a
      and b = Packed.Int_array.Private.view b in
      a.offsets = b.offsets && a.values = b.values
  | Attribute.Float_array a, Attribute.Float_array b ->
      let a = Packed.Float_array.Private.view a
      and b = Packed.Float_array.Private.view b in
      a.offsets = b.offsets && a.values = b.values
  | _ -> false

let group_equal left right =
  Group.owner left = Group.owner right && Group.name left = Group.name right
  && Group.length left = Group.length right
  && Group.ordered_elements left = Group.ordered_elements right
  && let same = ref true in
     for element = 0 to Group.length left - 1 do
       if Group.mem element left <> Group.mem element right then same := false
     done;
     !same

let edge_pairs geometry group =
  let index = Topology_index.create (Geometry.topology geometry) in
  let pairs = ref [] in
  Edge_group.iter (fun edge ->
    let a, b = Topology_index.edge_points index edge in
    pairs := (a, b) :: !pairs) group;
  List.sort compare !pairs

let geometry_equal left right =
  let lp = Packed.Float3.Private.view (Geometry.positions left)
  and rp = Packed.Float3.Private.view (Geometry.positions right)
  and lt = Topology.Private.view (Geometry.topology left)
  and rt = Topology.Private.view (Geometry.topology right) in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && lt.point_count = rt.point_count
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && List.equal attribute_equal (Geometry.attributes left)
      (Geometry.attributes right)
  && List.equal group_equal (Geometry.groups left) (Geometry.groups right)
  && List.map Edge_group.name (Geometry.edge_groups left)
      = List.map Edge_group.name (Geometry.edge_groups right)
  && List.for_all2 (fun left_group right_group ->
       edge_pairs left left_group = edge_pairs right right_group)
       (Geometry.edge_groups left) (Geometry.edge_groups right)

let scalar owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing attribute " ^ name)

let check_triangles geometry =
  let topology = Topology.Private.view (Geometry.topology geometry) in
  for primitive = 0 to Geometry.primitive_count geometry - 1 do
    check (Bytes.get topology.primitive_kinds primitive = '\000'
      && topology.primitive_offsets.(primitive + 1)
         - topology.primitive_offsets.(primitive) = 3)
      "Remesh emitted a non-triangle primitive"
  done

let test_uniform_outputs_and_projection () =
  let source = grid () in
  let source_primitives = Geometry.primitive_count source in
  let output = Ops.remesh ~grain:7 ~iterations:2 ~target_length:0.72
      ~output_hard_edges:"hard" ~output_mesh_size:"mesh_size"
      ~output_quality:"quality" source |> get in
  check_triangles output;
  check (Geometry.primitive_count output > source_primitives)
    "Remesh did not refine a coarse grid";
  let sizes = scalar Attribute.Point "mesh_size" output in
  Array.iter (fun value -> check (value = 0.72)
    "Remesh uniform mesh-size output drift") sizes;
  let quality = scalar Attribute.Primitive "quality" output in
  Array.iter (fun value -> check (Float.is_finite value && value >= 0. && value <= 1.)
    "Remesh emitted an invalid quality value") quality;
  let hard = Geometry.find_edge_group "hard" output |> Option.get in
  let index = Topology_index.create (Geometry.topology output) in
  check (Edge_group.cardinality hard = Topology_index.boundary_edge_count index)
    "Remesh hard-edge output does not match the open boundary";
  check (Geometry.find_attribute ~owner:Attribute.Point "N" output <> None)
    "Remesh did not generate requested point normals";
  let surface = Surface_index.create source |> get in
  let positions = Packed.Float3.Private.view (Geometry.positions output) in
  for point = 0 to Geometry.point_count output - 1 do
    match Surface_index.closest surface ~x:positions.x.(point)
        ~y:positions.y.(point) ~z:positions.z.(point) with
    | Error error -> fail (Error.to_string error)
    | Ok None -> fail "Remesh projection point missed its source surface"
    | Ok (Some hit) -> check (hit.distance <= 1e-8)
        "Remesh projection left a point off the source surface"
  done

let seam_fixture () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;1.;1.|] ~z:[|0.;0.;0.;0.|] in
  let topology = Topology.polygons_owned ~point_count:4
      ~vertex_points:[|0;1;2; 0;2;3|] ~primitive_offsets:[|0;3;6|]
      |> get_string in
  let uv = Packed.Float2.Private.of_shared ~x:[|0.;1.;1.; 2.;3.;2.|]
      ~y:[|0.;0.;1.; 0.;1.;1.|] |> get_string in
  let geometry = Geometry.create ~positions ~topology () |> get_string
      |> add_attribute ~owner:Attribute.Vertex ~name:"uv" (Attribute.Float2 uv)
      |> add_attribute ~owner:Attribute.Point ~name:"target"
           (Attribute.Float [|0.4;0.4;0.4;0.4|])
      |> add_attribute ~owner:Attribute.Detail ~name:"tag"
           (Attribute.Text [|"fixture"|]) in
  let hard_points = Group.init ~owner:Group.Point ~name:"pin" 4
      (fun point -> point = 0) in
  geometry, hard_points

let test_adaptive_hard_and_uv_seams () =
  let source, hard_points = seam_fixture () in
  let detail = Geometry.find_attribute ~owner:Attribute.Detail "tag" source
      |> Option.get in
  let output = Ops.remesh ~grain:3 ~iterations:2 ~target_length:1.
      ~target_size_attribute:"target" ~hard_points
      ~output_hard_edges:"features" ~output_mesh_size:"effective_size"
      ~output_quality:"quality" source |> get in
  check_triangles output;
  let sizes = scalar Attribute.Point "effective_size" output in
  Array.iter (fun value -> check (value = 0.4)
    "Remesh adaptive target-size ancestry drift") sizes;
  let output_detail = Geometry.find_attribute ~owner:Attribute.Detail "tag" output
      |> Option.get in
  check (Attribute.storage_id detail = Attribute.storage_id output_detail)
    "Remesh copied immutable detail payload";
  let features = Geometry.find_edge_group "features" output |> Option.get
  and index = Topology_index.create (Geometry.topology output) in
  check (Edge_group.cardinality features > Topology_index.boundary_edge_count index)
    "Remesh did not preserve the UV discontinuity as a hard interior feature";
  let positions = Packed.Float3.Private.view (Geometry.positions output) in
  let pinned = ref false in
  for point = 0 to Geometry.point_count output - 1 do
    if positions.x.(point) = 0. && positions.y.(point) = 0.
        && positions.z.(point) = 0. then pinned := true
  done;
  check !pinned "Remesh removed or moved an explicit hard point"

let test_input_points_only () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;2.;0.|] ~y:[|0.;0.;1.;1.|] ~z:[|0.;0.;0.;0.|] in
  let topology = Topology.polygons_owned ~point_count:4
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;4|] |> get_string in
  let source = Geometry.create ~positions ~topology () |> get_string in
  let output = Ops.remesh ~iterations:2 ~smoothing:0.
      ~use_input_points_only:true ~target_length:0.1
      ~recompute_point_normals:false source |> get in
  check (Geometry.point_count output = 4 && Geometry.primitive_count output = 2)
    "Remesh input-points-only mode changed point cardinality";
  check_triangles output

let test_fused_split_matches_composed_reference () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;1.|] ~y:[|0.;0.;sqrt 3.|] ~z:[|0.;0.;0.|] in
  let topology = Topology.polygons_owned ~point_count:3
      ~vertex_points:[|0;1;2|] ~primitive_offsets:[|0;3|] |> get_string in
  let index = Topology_index.create topology in
  let all_edges = Edge_group.init ~topology ~index ~name:"authored_edges"
      (fun _ -> true) in
  let point_id = Attribute.create_owned ~owner:Attribute.Point ~name:"point_id"
      (Attribute.Int [|10;20;30|]) |> get_string
  and uv = Attribute.create_owned ~owner:Attribute.Vertex ~name:"uv"
      (Attribute.Float2 (Packed.Float2.of_owned ~x:[|0.;1.;0.5|]
        ~y:[|0.;0.;1.|] |> get_string)) |> get_string
  and rows = Attribute.create_owned ~owner:Attribute.Vertex ~name:"rows"
      (Attribute.Int_array (Packed.Int_array.create_owned
        ~offsets:[|0;1;3;4|] ~values:[|7;8;9;10|] |> get_string)) |> get_string
  and material = Attribute.create_owned ~owner:Attribute.Primitive ~name:"material"
      (Attribute.Text [|"red"|]) |> get_string
  and detail = Attribute.create_owned ~owner:Attribute.Detail ~name:"tag"
      (Attribute.Text [|"split-reference"|]) |> get_string in
  let point_group = Group.ordered ~owner:Group.Point ~name:"ordered_points"
      ~length:3 [|2;0;1|] |> get_string
  and vertex_group = Group.init ~owner:Group.Vertex ~name:"corners" 3
      (fun vertex -> vertex <> 1)
  and primitive_group = Group.init ~owner:Group.Primitive ~name:"face" 1
      (fun _ -> true) in
  let source = Geometry.create ~positions ~topology
      ~attributes:[point_id;uv;rows;material;detail]
      ~groups:[point_group;vertex_group;primitive_group]
      ~edge_groups:[all_edges] () |> get_string in
  let divided = Ops.edge_divide ~grain:1 ~edges:all_edges ~divisions:2
      ~share_points:true source |> get in
  let reference = Ops.triangulate ~grain:1 divided |> get in
  let fused = Ops.remesh ~grain:1 ~iterations:1 ~smoothing:0. ~project:false
      ~preserve_uv_seams:false ~recompute_point_normals:false
      ~target_length:1.4 source |> get in
  let rp = Packed.Float3.Private.view (Geometry.positions reference)
  and fp = Packed.Float3.Private.view (Geometry.positions fused)
  and ft = Topology.Private.view (Geometry.topology fused) in
  check (rp.x = fp.x && rp.y = fp.y && rp.z = fp.z
      && Geometry.point_count reference = Geometry.point_count fused
      && Geometry.vertex_count reference = Geometry.vertex_count fused
      && Geometry.primitive_count reference = Geometry.primitive_count fused)
    "Remesh fused split changed composed cardinality or midpoint positions";
  check (ft.vertex_points = [|0;3;5; 3;1;4; 5;4;2; 3;4;5|])
    "Remesh fused all-edge split lost its deterministic four-triangle pattern";
  let point_ids geometry = match Geometry.find_attribute
      ~owner:Attribute.Point "point_id" geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Int values -> values | _ -> assert false)
    | None -> assert false in
  check (point_ids reference = point_ids fused)
    "Remesh fused split changed point payload interpolation";
  let materials geometry = match Geometry.find_attribute
      ~owner:Attribute.Primitive "material" geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Text values -> values | _ -> assert false)
    | None -> assert false in
  check (materials reference = materials fused)
    "Remesh fused split changed primitive ancestry";
  let detail geometry = Geometry.find_attribute ~owner:Attribute.Detail "tag"
      geometry |> Option.get in
  check (Attribute.storage_id (detail reference) = Attribute.storage_id (detail fused))
    "Remesh fused split copied detail payload";
  let edge_group geometry = Geometry.find_edge_group "authored_edges" geometry
      |> Option.get in
  check (edge_pairs reference (edge_group reference)
      = edge_pairs fused (edge_group fused))
    "Remesh fused split changed native source-edge ancestry";
  let point_group geometry = Geometry.find_group ~owner:Group.Point
      "ordered_points" geometry |> Option.get in
  check (Group.ordered_elements (point_group reference)
      = Group.ordered_elements (point_group fused))
    "Remesh fused split changed ordered point-group ancestry";
  let vertex_group geometry = Geometry.find_group ~owner:Group.Vertex "corners"
      geometry |> Option.get in
  check (Group.cardinality (vertex_group fused) = 5)
    "Remesh fused split violated endpoint-intersection vertex-group interpolation"

let test_errors_and_cancellation () =
  let source = grid ~columns:4 ~rows:4 () in
  let expect code result = match result with
    | Error error -> check (Error.code error = code)
        ("Remesh returned unexpected error code " ^ Error.code error)
    | Ok _ -> fail ("Remesh accepted invalid input for " ^ code) in
  expect "invalid_remesh" (Ops.remesh ~target_length:0. source);
  expect "invalid_remesh" (Ops.remesh ~target_length:1. ~iterations:(-1) source);
  expect "invalid_remesh" (Ops.remesh ~target_length:1. ~smoothing:1.1 source);
  let wrong = Group.init ~owner:Group.Vertex ~name:"wrong"
      (Geometry.vertex_count source) (fun _ -> true) in
  expect "invalid_remesh" (Ops.remesh ~target_length:1. ~hard_points:wrong source);
  let bad_size = source |> add_attribute ~owner:Attribute.Point ~name:"size"
      (Attribute.Float (Array.init (Geometry.point_count source)
        (fun point -> if point = 2 then Float.nan else 1.))) in
  expect "invalid_remesh"
    (Ops.remesh ~target_length:1. ~target_size_attribute:"size" bad_size);
  let curve = Ops.polyline [|0.,0.,0.;1.,0.,0.;2.,0.,0.|] |> get in
  expect "invalid_remesh" (Ops.remesh ~target_length:1. curve);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  expect "cancelled" (Ops.remesh ~cancel:cancelled ~target_length:1. source)

let test_parallel_exact () =
  let source = grid ~columns:14 ~rows:12 ~size:6. () in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.remesh ~grain:31 ~iterations:1 ~target_length:0.45
      ~output_hard_edges:"hard" ~output_mesh_size:"size"
      ~output_quality:"quality" source |> get) in
  let one = run 1 and four = run 4 in
  check (geometry_equal one four)
    "Remesh one-domain/multi-domain geometry drift"

let () =
  test_uniform_outputs_and_projection ();
  test_adaptive_hard_and_uv_seams ();
  test_input_points_only ();
  test_fused_split_matches_composed_reference ();
  test_errors_and_cancellation ();
  test_parallel_exact ();
  print_endline "remesh tests passed"
