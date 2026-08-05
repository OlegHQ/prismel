open Prismel
open Pdk

let fail message = prerr_endline message; exit 1
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error error -> fail (Error.to_string error)

let attribute owner name storage =
  Attribute.create_owned ~owner ~name storage |> Result.get_ok

let base ?(delta = 1.) () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.;2.|] ~y:[|0.;0.;1.;1.;2.|]
      ~z:(Array.make 5 0.) in
  let topology = Topology.polygons_owned ~point_count:5
      ~vertex_points:[|0;1;2;0;2;3|] ~primitive_offsets:[|0;3;6|]
      |> Result.get_ok in
  let uv = Packed.Float2.of_owned
      ~x:[|0.;1.;1.;delta;1. +. delta;0.|]
      ~y:[|0.;0.;1.;delta;1. +. delta;1.|] |> Result.get_ok in
  let weights = Packed.Float_array.create_owned
      ~offsets:[|0;2;4;6;8;10;12|]
      ~values:[|0.;10.; 1.;11.; 2.;12.; delta;13.;
                2. +. delta;14.; 3.;15.|] |> Result.get_ok in
  let seam_points = Group.ordered ~owner:Group.Point ~name:"seam_points"
      ~length:5 [|2;0|] |> Result.get_ok
  and one_corner = Group.init ~grain:1 ~owner:Group.Vertex ~name:"one_corner" 6
      (fun vertex -> vertex = 3)
  and first_face = Group.init ~grain:1 ~owner:Group.Primitive ~name:"first_face" 2
      (fun primitive -> primitive = 0) in
  let index = Topology_index.create topology in
  let diagonal = Topology_index.find_edge_index index ~a:0 ~b:2 in
  check (diagonal >= 0) "Point Split fixture diagonal missing";
  let diagonal = Edge_group.init ~grain:1 ~topology ~index ~name:"diagonal"
      (fun edge -> edge = diagonal) in
  Geometry.create ~positions ~topology
    ~attributes:[
      attribute Attribute.Point "id" (Attribute.Int [|0;1;2;3;4|]);
      attribute Attribute.Vertex "uv" (Attribute.Float2 uv);
      attribute Attribute.Vertex "tag"
        (Attribute.Text [|"a";"b";"c";"z";"w";"d"|]);
      attribute Attribute.Vertex "weights" (Attribute.Float_array weights);
      attribute Attribute.Primitive "material" (Attribute.Int [|0;1|]);
      attribute Attribute.Detail "source" (Attribute.Text [|"split"|]);
    ] ~groups:[seam_points;one_corner;first_face] ~edge_groups:[diagonal] ()
    |> Result.get_ok

let group owner name geometry =
  match Geometry.find_group ~owner name geometry with
  | Some value -> value | None -> fail ("missing group " ^ name)

let attr owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some value -> value | None -> fail ("missing attribute " ^ name)

let float2 attribute = match Attribute.Private.storage attribute with
  | Attribute.Float2 values -> Packed.Float2.Private.view values
  | _ -> fail "expected float2 attribute"

let int_values attribute = match Attribute.Private.storage attribute with
  | Attribute.Int values -> values | _ -> fail "expected integer attribute"

let text_values attribute = match Attribute.Private.storage attribute with
  | Attribute.Text values -> values | _ -> fail "expected text attribute"

let float_rows attribute = match Attribute.Private.storage attribute with
  | Attribute.Float_array values -> Packed.Float_array.Private.view values
  | _ -> fail "expected float-array attribute"

let row values row =
  Array.sub values.Packed.Float_array.Private.values values.offsets.(row)
    (values.offsets.(row + 1) - values.offsets.(row))

let equal_storage left right =
  match Attribute.Private.storage left, Attribute.Private.storage right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Text left, Attribute.Text right -> left = right
  | Attribute.Float2 left, Attribute.Float2 right ->
      let left = Packed.Float2.Private.view left
      and right = Packed.Float2.Private.view right in
      left.x = right.x && left.y = right.y
  | Attribute.Float3 left, Attribute.Float3 right ->
      let left = Packed.Float3.Private.view left
      and right = Packed.Float3.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
  | Attribute.Float4 left, Attribute.Float4 right ->
      let left = Packed.Float4.Private.view left
      and right = Packed.Float4.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z && left.w = right.w
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | _ -> false

let equal_group left right =
  Group.owner left = Group.owner right && Group.name left = Group.name right
  && Group.ordered_elements left = Group.ordered_elements right
  && Group.length left = Group.length right
  && let equal = ref true in
     for element = 0 to Group.length left - 1 do
       if Group.mem element left <> Group.mem element right then equal := false
     done;
     !equal

let equal_edge_group left right =
  Edge_group.name left = Edge_group.name right
  && Edge_group.length left = Edge_group.length right
  && let equal = ref true in
     for edge = 0 to Edge_group.length left - 1 do
       if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
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
  && List.equal (fun left right -> Attribute.owner left = Attribute.owner right
      && Attribute.name left = Attribute.name right && equal_storage left right)
      (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group (Geometry.edge_groups left)
      (Geometry.edge_groups right)

let test_unique_and_selection () =
  let source = base () in
  let all = Ops.point_split source |> get in
  check (Geometry.point_count all = 7) "Point Split unique cardinality";
  let topology = Topology.Private.view (Geometry.topology all) in
  check (topology.vertex_points = [|0;1;2;5;6;3|])
    "Point Split unique stable topology";
  let point_selection = Ops.Selected_points (group Group.Point "seam_points" source) in
  let points = Ops.point_split ~selection:point_selection source |> get in
  check (Geometry.point_count points = 7)
    "Point Split selected-point cardinality";
  let vertex_selection = Ops.Selected_vertices
      (group Group.Vertex "one_corner" source) in
  let vertex = Ops.point_split ~selection:vertex_selection source |> get in
  check (Geometry.point_count vertex = 6)
    "Point Split selected-vertex cardinality";
  let primitive_selection = Ops.Selected_primitives
      (group Group.Primitive "first_face" source) in
  let primitive = Ops.point_split ~selection:primitive_selection source |> get in
  check (Geometry.point_count primitive = 7)
    "Point Split selected-primitive cardinality";
  let empty = Group.init ~grain:1 ~owner:Group.Point ~name:"empty" 5
      (Fun.const false) in
  check (Ops.point_split ~selection:(Ops.Selected_points empty) source |> get == source)
    "Point Split empty selection identity"

let test_attribute_clusters_and_tolerance () =
  let source = base () in
  let split = Ops.point_split ~attributes:"u*" source |> get in
  check (Geometry.point_count split = 7) "Point Split float2 seam clustering";
  let exact = base ~delta:0. () in
  check (Ops.point_split ~attributes:"uv" exact |> get == exact)
    "Point Split equal attribute identity";
  let near = base ~delta:0.005 () in
  check (Ops.point_split ~attributes:"uv" ~tolerance:0.01 near |> get == near)
    "Point Split inclusive tolerance merge";
  check (Geometry.point_count
      (Ops.point_split ~attributes:"uv" ~tolerance:0.001 near |> get) = 7)
    "Point Split tolerance separation";
  check (Geometry.point_count
      (Ops.point_split ~attributes:"material" source |> get) = 7)
    "Point Split primitive integer clustering";
  check (Geometry.point_count
      (Ops.point_split ~attributes:"weights" source |> get) = 7)
    "Point Split float-array clustering";
  check (Geometry.point_count
      (Ops.point_split ~attributes:"tag" source |> get) = 7)
    "Point Split text clustering"

let test_group_clusters () =
  let source = base ~delta:0. () in
  let vertex = Ops.point_split ~attributes:"one_corner" source |> get in
  check (Geometry.point_count vertex = 6)
    "Point Split vertex-group seam clustering";
  let primitive = Ops.point_split ~attributes:"first_face" source |> get in
  check (Geometry.point_count primitive = 7)
    "Point Split primitive-group seam clustering";
  let both = Ops.point_split ~attributes:"*_corner first_*" source |> get in
  check (Geometry.point_count both = 7)
    "Point Split wildcard group seam clustering";
  let excluded = Ops.point_split
      ~attributes:"*_corner first_* ^first_face" source |> get in
  check (Geometry.point_count excluded = 6)
    "Point Split ordered group exclusion";
  let promoted = Ops.point_split ~attributes:"first_face"
      ~promote_attributes:true source |> get in
  check (Geometry.find_attribute ~owner:Attribute.Point "first_face" promoted
      = None)
    "Point Split promoted a group as an attribute";
  let seam_points = group Group.Point "seam_points" source in
  check (match Ops.point_split ~attributes:(Group.name seam_points) source with
    | Error _ -> true | Ok _ -> false)
    "Point Split accepted a point group as a seam criterion"

let test_partial_attribute_selection () =
  let exact = base ~delta:0. () in
  let selected = Ops.Selected_vertices
      (group Group.Vertex "one_corner" exact) in
  check (Ops.point_split ~selection:selected ~attributes:"uv" exact |> get == exact)
    "Point Split separated an equal selected/unselected seam";
  let differing = base () in
  let selected = Ops.Selected_vertices
      (group Group.Vertex "one_corner" differing) in
  let split = Ops.point_split ~selection:selected ~attributes:"uv" differing
      |> get in
  check (Geometry.point_count split = 6)
    "Point Split did not separate a differing selected corner";
  let topology = Topology.Private.view (Geometry.topology split) in
  check (topology.vertex_points = [|0;1;2;5;2;3|])
    "Point Split partial-selection topology is not stable"

let test_all_storage_kinds () =
  let source = base ~delta:0. () in
  let values = [|0.;0.;0.;1.;1.;0.|] in
  let scalar = attribute Attribute.Vertex "scalar" (Attribute.Float values)
  and vector3 = attribute Attribute.Vertex "vector3" (Attribute.Float3
      (Packed.Float3.Private.of_owned_exn ~x:(Array.copy values)
        ~y:(Array.make 6 2.) ~z:(Array.make 6 3.)))
  and vector4 = attribute Attribute.Vertex "vector4" (Attribute.Float4
      (Packed.Float4.of_owned ~x:(Array.copy values) ~y:(Array.make 6 2.)
        ~z:(Array.make 6 3.) ~w:(Array.make 6 4.) |> Result.get_ok))
  and integer_rows = attribute Attribute.Vertex "integer_rows"
      (Attribute.Int_array (Packed.Int_array.create_owned
        ~offsets:[|0;1;2;3;4;5;6|] ~values:[|0;0;0;1;1;0|]
        |> Result.get_ok)) in
  let source = source |> Geometry.with_attribute scalar |> Result.get_ok
      |> Geometry.with_attribute vector3 |> Result.get_ok
      |> Geometry.with_attribute vector4 |> Result.get_ok
      |> Geometry.with_attribute integer_rows |> Result.get_ok in
  List.iter (fun name ->
    check (Geometry.point_count
        (Ops.point_split ~attributes:name source |> get) = 7)
      ("Point Split storage clustering failed for " ^ name))
    ["scalar";"vector3";"vector4";"integer_rows"];
  let promoted = Ops.point_split
      ~attributes:"scalar vector3 vector4 integer_rows"
      ~promote_attributes:true source |> get in
  List.iter (fun name ->
    check (Geometry.find_attribute ~owner:Attribute.Point name promoted <> None
        && Geometry.find_attribute ~owner:Attribute.Vertex name promoted = None)
      ("Point Split storage promotion failed for " ^ name))
    ["scalar";"vector3";"vector4";"integer_rows"]

let test_payload_promotion_and_groups () =
  let source = base () in
  let output = Ops.point_split ~attributes:"uv tag weights"
      ~promote_attributes:true source |> get in
  check (Geometry.point_count output = 7) "Point Split promoted cardinality";
  check (Geometry.find_attribute ~owner:Attribute.Vertex "uv" output = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "tag" output = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "weights" output = None)
    "Point Split promotion retained source-owner fields";
  let source_uv = float2 (attr Attribute.Vertex "uv" source)
  and target_uv = float2 (attr Attribute.Point "uv" output)
  and source_tag = text_values (attr Attribute.Vertex "tag" source)
  and target_tag = text_values (attr Attribute.Point "tag" output)
  and source_weights = float_rows (attr Attribute.Vertex "weights" source)
  and target_weights = float_rows (attr Attribute.Point "weights" output)
  and target_topology = Topology.Private.view (Geometry.topology output) in
  for vertex = 0 to Geometry.vertex_count source - 1 do
    let point = target_topology.vertex_points.(vertex) in
    check (source_uv.x.(vertex) = target_uv.x.(point)
        && source_uv.y.(vertex) = target_uv.y.(point))
      "Point Split promoted UV mismatch";
    check (source_tag.(vertex) = target_tag.(point))
      "Point Split promoted text mismatch";
    check (row source_weights vertex = row target_weights point)
      "Point Split promoted array row mismatch"
  done;
  let free_row = row target_weights 4 in
  check (target_uv.x.(4) = 0. && target_uv.y.(4) = 0.
      && target_tag.(4) = "" && Array.length free_row = 0)
    (Printf.sprintf
      "Point Split free-point promotion defaults (uv=%g,%g tag=%S row=%d)"
      target_uv.x.(4) target_uv.y.(4) target_tag.(4) (Array.length free_row));
  let ids = int_values (attr Attribute.Point "id" output) in
  check (ids = [|0;1;2;3;4;0;2|]) "Point Split point ancestry";
  check (attr Attribute.Primitive "material" output
      == attr Attribute.Primitive "material" source)
    "Point Split copied unchanged primitive storage";
  check (attr Attribute.Detail "source" output == attr Attribute.Detail "source" source)
    "Point Split copied unchanged detail storage";
  let seam_points = group Group.Point "seam_points" output in
  check (Group.cardinality seam_points = 4
      && Group.ordered_elements seam_points = Some [|2;6;0;5|])
    "Point Split ordered point-group ancestry";
  let diagonal = Geometry.find_edge_group "diagonal" output |> Option.get in
  check (Edge_group.cardinality diagonal = 2)
    "Point Split native edge-group ancestry"

let test_malformed_and_cancellation () =
  let source = base () in
  let expect_error label result = match result with
    | Error _ -> () | Ok _ -> fail ("Point Split accepted " ^ label) in
  expect_error "negative tolerance" (Ops.point_split ~tolerance:(-1.) source);
  expect_error "non-finite tolerance" (Ops.point_split ~tolerance:nan source);
  expect_error "missing attribute pattern"
    (Ops.point_split ~attributes:"missing" source);
  expect_error "malformed pattern" (Ops.point_split ~attributes:"[" source);
  let wrong = group Group.Primitive "first_face" source in
  expect_error "wrong selection owner"
    (Ops.point_split ~selection:(Ops.Selected_points wrong) source);
  let index = Topology_index.create (Geometry.topology source) in
  let edge = Edge_group.init ~grain:1 ~topology:(Geometry.topology source)
      ~index ~name:"edge" (fun edge -> edge = 0) in
  expect_error "native edge selection"
    (Ops.point_split ~selection:(Ops.Selected_edges edge) source);
  let bad = Geometry.with_attribute
      (attribute Attribute.Vertex "bad"
        (Attribute.Float [|0.;0.;0.;nan;0.;0.|])) source |> Result.get_ok in
  expect_error "non-finite seam value" (Ops.point_split ~attributes:"bad" bad);
  let duplicate = source
      |> Geometry.with_attribute
          (attribute Attribute.Vertex "duplicate" (Attribute.Int [|0;0;0;1;1;0|]))
      |> Result.get_ok
      |> Geometry.with_attribute
          (attribute Attribute.Primitive "duplicate" (Attribute.Int [|0;1|]))
      |> Result.get_ok in
  expect_error "ambiguous promoted owner"
    (Ops.point_split ~attributes:"duplicate" ~promote_attributes:true duplicate);
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Ops.point_split ~cancel source with
   | Error error when Error.code error = "cancelled" -> ()
   | Error error -> fail ("Point Split cancellation code: " ^ Error.to_string error)
   | Ok _ -> fail "Point Split ignored cancellation")

let large_fixture () =
  let geometry = Ops.grid ~connectivity:Ops.Grid_quads ~columns:160 ~rows:120
      ~size:10. () |> get in
  let material = attribute Attribute.Primitive "material"
      (Attribute.Int (Array.init (Geometry.primitive_count geometry)
        (fun primitive -> (primitive / 7) mod 3))) in
  let seam_region = Group.init ~grain:1 ~owner:Group.Primitive
      ~name:"seam_region" (Geometry.primitive_count geometry)
      (fun primitive -> primitive land 3 < 2) in
  geometry |> Geometry.with_attribute material |> Result.get_ok
      |> Geometry.with_group seam_region |> Result.get_ok

let test_parallel_exact () =
  let source = large_fixture () in
  let cook domains = Parallel.run ~domains (fun () ->
    Ops.point_split ~grain:257 ~attributes:"material seam_region"
      ~promote_attributes:true source |> get) in
  let one = cook 1 and four = cook 4 in
  check (equal_geometry one four)
    "Point Split one/four-domain geometry differs";
  check (Geometry.point_count one > Geometry.point_count source)
    "Point Split scale fixture did not split"

let () =
  test_unique_and_selection ();
  test_attribute_clusters_and_tolerance ();
  test_group_clusters ();
  test_partial_attribute_selection ();
  test_all_storage_kinds ();
  test_payload_promotion_and_groups ();
  test_malformed_and_cancellation ();
  test_parallel_exact ();
  print_endline "point split tests passed"
