open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let attribute owner name storage geometry =
  Attribute.create_owned ~owner ~name storage |> Result.get_ok
  |> fun value -> Geometry.with_attribute value geometry |> Result.get_ok

let float_attribute owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some value ->
      (match Attribute.Private.storage value with
       | Attribute.Float values -> values
       | _ -> fail (name ^ " storage changed"))
  | None -> fail ("missing " ^ name)

let float4_attribute owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some value ->
      (match Attribute.Private.storage value with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail (name ^ " storage changed"))
  | None -> fail ("missing " ^ name)

let two_quads () =
  Ops.grid ~connectivity:Ops.Grid_quads ~columns:2 ~rows:1 ~size:2. () |> get_ok

let shared_edge geometry =
  let index = Topology_index.create (Geometry.topology geometry) in
  let edge = ref (-1) in
  for candidate = 0 to Topology_index.edge_count index - 1 do
    if Topology_index.edge_incidence_count index candidate = 2 then
      edge := candidate
  done;
  if !edge < 0 then fail "fixture has no shared edge";
  index, !edge

let edge_group geometry index selected =
  Edge_group.init ~grain:1 ~topology:(Geometry.topology geometry) ~index
    ~name:"crease_edges" selected

let incident_vertices index edge =
  Array.init (Topology_index.edge_incidence_count index edge)
    (fun local -> Topology_index.edge_vertex index ~edge ~local)

let test_add_set_delete () =
  let source = two_quads () in
  let index, shared = shared_edge source in
  let edges = edge_group source index (fun edge -> edge = shared) in
  let set = Ops.crease ~grain:1 ~edges ~operation:Ops.Crease_set ~weight:2.
      source |> get_ok in
  let values = float_attribute Attribute.Vertex "creaseweight" set in
  let incidents = incident_vertices index shared in
  check (Array.length incidents = 2) "shared-edge incidence fixture";
  Array.iteri (fun vertex value ->
    check (value = if Array.mem vertex incidents then 2. else 0.)
      "Crease Set changed the wrong corner") values;
  let asymmetric = Array.copy values in
  asymmetric.(incidents.(0)) <- 1.;
  asymmetric.(incidents.(1)) <- 3.;
  let asymmetric = attribute Attribute.Vertex "creaseweight"
      (Attribute.Float asymmetric) source in
  let added = Ops.crease ~grain:1 ~edges ~operation:Ops.Crease_add ~weight:0.5
      asymmetric |> get_ok in
  let values = float_attribute Attribute.Vertex "creaseweight" added in
  check (values.(incidents.(0)) = 3.5 && values.(incidents.(1)) = 3.5)
    "Crease Add did not reduce an edge by maximum and normalize incidents";
  let fresh_add = Ops.crease ~grain:1 ~edges ~operation:Ops.Crease_add
      ~weight:0.75 source |> get_ok in
  let fresh_values = float_attribute Attribute.Vertex "creaseweight" fresh_add in
  Array.iter (fun vertex -> check (fresh_values.(vertex) = 0.75)
      "Crease Add on a missing field did not author an incident corner")
    incidents;
  let preserved = ref (-1) in
  Array.iteri (fun vertex edge ->
    if edge >= 0 && edge <> shared && !preserved < 0 then preserved := vertex)
    (Topology_index.Private.view index).edge_of_vertex;
  check (values.(!preserved) = 0.) "Crease Add changed an unselected edge";
  let deleted = Ops.crease ~grain:1 ~edges ~operation:Ops.Crease_delete set
      |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Vertex "creaseweight" deleted
      = None) "Crease Delete retained a completely cleared field";
  let absent = Ops.crease ~edges ~operation:Ops.Crease_delete source |> get_ok in
  check (absent == source) "Crease Delete without a field lost identity";
  let partial_values = Array.copy values in
  partial_values.(!preserved) <- 4.25;
  let partial = attribute Attribute.Vertex "creaseweight"
      (Attribute.Float partial_values) source
      |> Ops.crease ~grain:1 ~edges ~operation:Ops.Crease_delete |> get_ok in
  let partial_values = float_attribute Attribute.Vertex "creaseweight" partial in
  check (partial_values.(!preserved) = 4.25
      && Array.for_all (fun vertex -> partial_values.(vertex) = 0.) incidents)
    "partial Crease Delete did not preserve unselected sharpness";
  let zero = Ops.crease ~edges ~operation:Ops.Crease_add ~weight:0. source
      |> get_ok in
  check (zero == source) "zero Crease Add lost identity";
  let same = Ops.crease ~edges ~operation:Ops.Crease_set ~weight:2. set
      |> get_ok in
  check (same == set) "idempotent Crease Set lost identity";
  let all = Ops.crease ~operation:Ops.Crease_set ~weight:1. source |> get_ok in
  let all_values = float_attribute Attribute.Vertex "creaseweight" all
  and view = Topology_index.Private.view index in
  Array.iteri (fun vertex edge ->
    check (all_values.(vertex) = if edge < 0 then 0. else 1.)
      "omitted Crease group did not select every topology edge")
    view.edge_of_vertex

let non_manifold () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 0.; 0.; 0.|]
      ~y:[|0.; 0.; 1.; -1.; 0.|]
      ~z:[|0.; 0.; 0.; 0.; 1.|] in
  let topology = Topology.polygons_owned ~point_count:5
      ~vertex_points:[|0; 1; 2; 1; 0; 3; 0; 1; 4|]
      ~primitive_offsets:[|0; 3; 6; 9|] |> Result.get_ok in
  Geometry.create ~positions ~topology () |> Result.get_ok

let test_non_manifold_and_visualization () =
  let source = non_manifold () in
  let index = Topology_index.create (Geometry.topology source) in
  let edge = Topology_index.find_edge_index index ~a:0 ~b:1 in
  check (edge >= 0 && Topology_index.edge_incidence_count index edge = 3)
    "non-manifold fixture";
  let edges = edge_group source index (fun candidate -> candidate = edge) in
  let output = Ops.crease ~grain:1 ~edges ~operation:Ops.Crease_set ~weight:2.
      source |> get_ok in
  let values = float_attribute Attribute.Vertex "creaseweight" output in
  Array.iter (fun vertex -> check (values.(vertex) = 2.)
      "non-manifold Crease missed an incident corner")
    (incident_vertices index edge);
  let quad = Ops.grid ~connectivity:Ops.Grid_quads ~columns:1 ~rows:1 ~size:1. ()
      |> get_ok in
  let quad_index = Topology_index.create (Geometry.topology quad) in
  let selected = edge_group quad quad_index (fun edge -> edge = 0) in
  let colored = Ops.crease ~grain:1 ~edges:selected ~operation:Ops.Crease_set
      ~weight:1. ~add_vertex_color:true quad |> get_ok in
  let colors = float4_attribute Attribute.Vertex "Cd" colored in
  let index_view = Topology_index.Private.view quad_index in
  let red_count = ref 0 in
  for vertex = 0 to Geometry.vertex_count colored - 1 do
    let previous = index_view.previous_vertex.(vertex) in
    let incoming = if previous < 0 then -1 else index_view.edge_of_vertex.(previous) in
    let red = index_view.edge_of_vertex.(vertex) = 0 || incoming = 0 in
    if red then incr red_count;
    check (colors.x.(vertex) = 1. && colors.y.(vertex) = (if red then 0. else 1.)
        && colors.z.(vertex) = (if red then 0. else 1.)
        && colors.w.(vertex) = 1.)
      "Crease vertex-color visualization did not color both edge endpoints"
  done;
  check (!red_count = 2) "Crease visualization endpoint cardinality";
  let point_count = Geometry.point_count quad in
  let point_colors = Packed.Float4.of_owned
      ~x:(Array.init point_count (fun point -> 0.1 *. float_of_int (point + 1)))
      ~y:(Array.make point_count 0.25) ~z:(Array.make point_count 0.5)
      ~w:(Array.make point_count 1.) |> Result.get_ok in
  let point_colored = attribute Attribute.Point "Cd"
      (Attribute.Float4 point_colors) quad
      |> Ops.crease ~grain:1 ~edges:selected ~operation:Ops.Crease_set
           ~weight:1. ~add_vertex_color:true |> get_ok in
  let expanded = float4_attribute Attribute.Vertex "Cd" point_colored
  and topology = Topology.Private.view (Geometry.topology quad) in
  for vertex = 0 to Geometry.vertex_count quad - 1 do
    let previous = index_view.previous_vertex.(vertex) in
    let incoming = if previous < 0 then -1 else index_view.edge_of_vertex.(previous) in
    let red = index_view.edge_of_vertex.(vertex) = 0 || incoming = 0 in
    if not red then begin
      let point = topology.vertex_points.(vertex) in
      check (expanded.x.(vertex) = 0.1 *. float_of_int (point + 1)
          && expanded.y.(vertex) = 0.25 && expanded.z.(vertex) = 0.5
          && expanded.w.(vertex) = 1.)
        "Crease visualization did not expand the uncreased point color"
    end
  done

let equal_float4 left right =
  let left = Packed.Float4.Private.view left
  and right = Packed.Float4.Private.view right in
  left.x = right.x && left.y = right.y && left.z = right.z && left.w = right.w

let equal_storage left right = match left, right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Float4 left, Attribute.Float4 right -> equal_float4 left right
  | Attribute.Float2 left, Attribute.Float2 right ->
      let left = Packed.Float2.Private.view left
      and right = Packed.Float2.Private.view right in
      left.x = right.x && left.y = right.y
  | Attribute.Float3 left, Attribute.Float3 right ->
      let left = Packed.Float3.Private.view left
      and right = Packed.Float3.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
  | Attribute.Text left, Attribute.Text right -> left = right
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | _ -> false

let equal_attributes left right =
  List.equal (fun left right -> Attribute.owner left = Attribute.owner right
      && String.equal (Attribute.name left) (Attribute.name right)
      && equal_storage (Attribute.Private.storage left)
           (Attribute.Private.storage right))
    (Geometry.attributes left) (Geometry.attributes right)

let test_subdivide_integration () =
  let source = two_quads () in
  let index, shared = shared_edge source in
  let edges = edge_group source index (fun edge -> edge = shared) in
  let authored = Ops.crease ~grain:1 ~edges ~operation:Ops.Crease_set ~weight:2.
      source |> get_ok in
  let manual_values = Array.make (Geometry.vertex_count source) 0. in
  Array.iter (fun vertex -> manual_values.(vertex) <- 2.)
    (incident_vertices index shared);
  let manual = attribute Attribute.Vertex "creaseweight"
      (Attribute.Float manual_values) source in
  let actual = Ops.subdivide ~grain:1 authored |> get_ok
  and expected = Ops.subdivide ~grain:1 manual |> get_ok in
  check (Geometry.positions actual = Geometry.positions expected
      || let a = Packed.Float3.Private.view (Geometry.positions actual)
         and b = Packed.Float3.Private.view (Geometry.positions expected) in
         a.x = b.x && a.y = b.y && a.z = b.z)
    "Crease/Subdivide positions diverged from manually authored weights";
  let a = Topology.Private.view (Geometry.topology actual)
  and b = Topology.Private.view (Geometry.topology expected) in
  check (a.vertex_points = b.vertex_points
      && a.primitive_offsets = b.primitive_offsets
      && a.primitive_kinds = b.primitive_kinds
      && equal_attributes actual expected)
    "Crease/Subdivide output diverged from manually authored weights"

let expect_invalid work message = match work () with
  | Error error -> check (Error.code error = "invalid_crease") message
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_errors_and_cancellation () =
  let source = two_quads () in
  let index, shared = shared_edge source in
  let edges = edge_group source index (fun edge -> edge = shared) in
  List.iter (fun weight -> expect_invalid (fun () ->
      Ops.crease ~edges ~operation:Ops.Crease_set ~weight source)
      "invalid Crease weight") [Float.nan; Float.infinity; -1.];
  expect_invalid (fun () -> Ops.crease ~grain:0 source) "zero Crease grain";
  let wrong_storage = attribute Attribute.Vertex "creaseweight"
      (Attribute.Int (Array.make (Geometry.vertex_count source) 1)) source in
  expect_invalid (fun () -> Ops.crease ~edges wrong_storage)
    "integer creaseweight";
  let bad_values = Array.make (Geometry.vertex_count source) 0. in
  bad_values.(1) <- Float.nan;
  bad_values.(3) <- -1.;
  let malformed = attribute Attribute.Vertex "creaseweight"
      (Attribute.Float bad_values) source in
  let error domains = Parallel.run ~domains (fun () -> Ops.crease ~grain:1
      ~edges ~operation:Ops.Crease_set ~weight:1. malformed) in
  List.iter (fun domains -> match error domains with
    | Error error -> check (Error.code error = "invalid_crease"
          && String.ends_with ~suffix:"vertex 1" (Error.message error))
        "Crease malformed-value diagnostic was not deterministic"
    | Ok _ -> fail "Crease accepted malformed existing weights") [1; 4];
  let huge = attribute Attribute.Vertex "creaseweight"
      (Attribute.Float (Array.make (Geometry.vertex_count source) max_float))
      source in
  expect_invalid (fun () -> Ops.crease ~edges ~operation:Ops.Crease_add
      ~weight:max_float huge) "Crease Add overflow";
  let other = two_quads () in
  let other_index, _ = shared_edge other in
  let wrong_edges = edge_group other other_index (fun _ -> true) in
  expect_invalid (fun () -> Ops.crease ~edges:wrong_edges source)
    "foreign Crease edge group";
  let wrong_color = attribute Attribute.Vertex "Cd"
      (Attribute.Float (Array.make (Geometry.vertex_count source) 1.)) source in
  expect_invalid (fun () -> Ops.crease ~edges ~operation:Ops.Crease_set
      ~weight:1. ~add_vertex_color:true wrong_color)
    "wrong Crease visualization color storage";
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Ops.crease ~cancel ~edges source with
   | Error error -> check (Error.code error = "cancelled")
       "Crease cancellation code"
   | Ok _ -> fail "cancelled Crease published geometry")

let test_dense_parallel_exactness () =
  let source = Ops.grid ~connectivity:Ops.Grid_quads ~columns:480 ~rows:300
      ~size:20. () |> get_ok in
  let topology = Geometry.topology source in
  let index = Topology_index.create topology in
  let edges = Edge_group.init ~grain:256 ~topology ~index ~name:"dense_edges"
      (fun edge -> edge mod 7 = 0) in
  let source = attribute Attribute.Vertex "creaseweight"
      (Attribute.Float (Array.init (Geometry.vertex_count source) (fun vertex ->
        if vertex mod 13 = 0 then 1.25 else 0.5))) source in
  let cook domains = Parallel.run ~domains (fun () ->
      Ops.crease ~grain:257 ~edges ~operation:Ops.Crease_add ~weight:2.
        ~add_vertex_color:true source |> get_ok) in
  let one = cook 1 and four = cook 4 in
  check (Geometry.point_count one = Geometry.point_count source
      && Geometry.vertex_count one = Geometry.vertex_count source
      && Geometry.primitive_count one = Geometry.primitive_count source)
    "dense Crease cardinality";
  check (Geometry.positions one == Geometry.positions source
      && Geometry.topology one == Geometry.topology source)
    "Crease copied unchanged core planes";
  check (equal_attributes one four)
    "Crease one/four-domain attributes differ";
  let one_mesh = Prismel_mesh.to_mesh one |> get_ok
  and four_mesh = Prismel_mesh.to_mesh four |> get_ok in
  check (Mesh.Private.packed_view one_mesh = Mesh.Private.packed_view four_mesh)
    "Crease one/four-domain render mesh differs"

let () =
  test_add_set_delete ();
  test_non_manifold_and_visualization ();
  test_subdivide_integration ();
  test_errors_and_cancellation ();
  test_dense_parallel_exactness ();
  print_endline "pdk crease tests passed"
