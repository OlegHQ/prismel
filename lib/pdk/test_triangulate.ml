open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_string = function Ok value -> value | Error error -> fail error
let get_pdk = function Ok value -> value | Error error -> fail (Error.to_string error)

let attribute owner name storage =
  Attribute.create_owned ~owner ~name storage |> get_string

let fixture () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.;2.;3.;4.|]
      ~y:[|0.;0.;1.;1.;2.;2.;2.|] ~z:(Array.make 7 0.) in
  let topology = Topology.create_owned ~point_count:7
      ~vertex_points:[|0;1;2;3; 4;5;6|]
      ~primitive_offsets:[|0;4;7|]
      ~primitive_kinds:[|Topology.Polygon; Topology.Open_polyline|]
      |> get_string in
  let rows = Packed.Float_array.create_owned
      ~offsets:[|0;1;3;3;4;6;7;9|]
      ~values:[|10.;11.;111.;13.;14.;114.;15.;16.;116.|] |> get_string in
  let int_rows = Packed.Int_array.create_owned
      ~offsets:[|0;1;2;3;4;5;6;7|] ~values:[|0;1;2;3;4;5;6|]
      |> get_string in
  let sequence = Array.init 7 float_of_int in
  let attributes = [
    attribute Attribute.Point "point_id" (Attribute.Int [|0;1;2;3;4;5;6|]);
    attribute Attribute.Vertex "weight" (Attribute.Float (Array.copy sequence));
    attribute Attribute.Vertex "corner"
      (Attribute.Int [|10;11;12;13;14;15;16|]);
    attribute Attribute.Vertex "label"
      (Attribute.Text [|"0";"1";"2";"3";"4";"5";"6"|]);
    attribute Attribute.Vertex "uv" (Attribute.Float2
      (Packed.Float2.of_owned ~x:(Array.copy sequence)
        ~y:(Array.map (fun value -> value +. 10.) sequence) |> get_string));
    attribute Attribute.Vertex "vector" (Attribute.Float3
      (Packed.Float3.Private.of_owned_exn ~x:(Array.copy sequence)
        ~y:(Array.map (fun value -> value +. 10.) sequence)
        ~z:(Array.map (fun value -> value +. 20.) sequence)));
    attribute Attribute.Vertex "quaternion" (Attribute.Float4
      (Packed.Float4.of_owned ~x:(Array.copy sequence)
        ~y:(Array.map (fun value -> value +. 10.) sequence)
        ~z:(Array.map (fun value -> value +. 20.) sequence)
        ~w:(Array.map (fun value -> value +. 30.) sequence) |> get_string));
    attribute Attribute.Vertex "int_rows" (Attribute.Int_array int_rows);
    attribute Attribute.Vertex "rows" (Attribute.Float_array rows);
    attribute Attribute.Primitive "material" (Attribute.Int [|7;9|]);
    attribute Attribute.Detail "tag" (Attribute.Text [|"triangulate"|]);
  ] in
  let selected = Group.ordered ~owner:Group.Primitive ~name:"selected"
      ~length:2 [|0|] |> get_string
  and curve = Group.init ~owner:Group.Primitive ~name:"curve" 2
      (fun primitive -> primitive = 1)
  and empty = Group.init ~owner:Group.Primitive ~name:"empty" 2
      (fun _ -> false)
  and ordered_vertices = Group.ordered ~owner:Group.Vertex
      ~name:"ordered_vertices" ~length:7 [|6;4;1|] |> get_string in
  Geometry.create ~positions ~topology ~attributes
    ~groups:[selected; curve; empty; ordered_vertices] () |> get_string
  |> Ops.group_edges ~name:"all_edges" |> get_pdk

let int_values owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail ("wrong integer storage for " ^ name))
  | None -> fail ("missing integer attribute " ^ name)

let equal_storage left right =
  match Attribute.storage left, Attribute.storage right with
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
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)
  && Group.ordered_elements left = Group.ordered_elements right
  && Group.length left = Group.length right
  && Array.for_all (fun index -> Group.mem index left = Group.mem index right)
       (Array.init (Group.length left) Fun.id)

let equal_geometry left right =
  let left_positions = Packed.Float3.Private.view (Geometry.positions left)
  and right_positions = Packed.Float3.Private.view (Geometry.positions right)
  and left_topology = Topology.Private.view (Geometry.topology left)
  and right_topology = Topology.Private.view (Geometry.topology right) in
  left_positions.x = right_positions.x
  && left_positions.y = right_positions.y
  && left_positions.z = right_positions.z
  && left_topology.vertex_points = right_topology.vertex_points
  && left_topology.primitive_offsets = right_topology.primitive_offsets
  && left_topology.primitive_kinds = right_topology.primitive_kinds
  && List.equal (fun left right -> Attribute.owner left = Attribute.owner right
       && String.equal (Attribute.name left) (Attribute.name right)
       && equal_storage left right)
       (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.for_all2 (fun left right ->
       String.equal (Edge_group.name left) (Edge_group.name right)
       && Edge_group.length left = Edge_group.length right
       && Array.for_all (fun edge -> Edge_group.mem edge left = Edge_group.mem edge right)
            (Array.init (Edge_group.length left) Fun.id))
       (Geometry.edge_groups left) (Geometry.edge_groups right)

let group owner name geometry =
  Geometry.find_group ~owner name geometry |> Option.get

let test_grouped_mixed_geometry () =
  let run domains = Parallel.run ~domains (fun () ->
    let source = fixture () in
    Ops.triangulate ~grain:1
      ~primitives:(group Group.Primitive "selected" source) source |> get_pdk) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "Triangulate differs across one and four domains";
  let topology = Topology.Private.view (Geometry.topology one) in
  check (topology.vertex_points = [|3;0;1; 1;2;3; 4;5;6|]
      && topology.primitive_offsets = [|0;3;6;9|]
      && topology.primitive_kinds
         = Bytes.init 3 (fun primitive -> if primitive = 2 then '\001' else '\000'))
    "grouped Triangulate topology or curve pass-through";
  check (int_values Attribute.Vertex "corner" one
      = [|13;10;11; 11;12;13; 14;15;16|])
    "Triangulate did not remap vertex payload";
  let expected_map = [|3;0;1;1;2;3;4;5;6|] in
  let expected_float = Array.map float_of_int expected_map in
  let storage name = Geometry.find_attribute ~owner:Attribute.Vertex name one
      |> Option.get |> Attribute.storage in
  (match storage "weight", storage "label", storage "uv", storage "vector",
      storage "quaternion", storage "int_rows" with
   | Attribute.Float weight, Attribute.Text label, Attribute.Float2 uv,
       Attribute.Float3 vector, Attribute.Float4 quaternion,
       Attribute.Int_array int_rows ->
       let uv = Packed.Float2.Private.view uv
       and vector = Packed.Float3.Private.view vector
       and quaternion = Packed.Float4.Private.view quaternion
       and int_rows = Packed.Int_array.Private.view int_rows in
       check (weight = expected_float
           && label = Array.map string_of_int expected_map
           && uv.x = expected_float
           && uv.y = Array.map (fun value -> value +. 10.) expected_float
           && vector.x = expected_float
           && vector.y = Array.map (fun value -> value +. 10.) expected_float
           && vector.z = Array.map (fun value -> value +. 20.) expected_float
           && quaternion.x = expected_float
           && quaternion.y = Array.map (fun value -> value +. 10.) expected_float
           && quaternion.z = Array.map (fun value -> value +. 20.) expected_float
           && quaternion.w = Array.map (fun value -> value +. 30.) expected_float
           && int_rows.offsets = Array.init 10 Fun.id
           && int_rows.values = expected_map)
         "Triangulate did not remap every fixed/ragged vertex storage"
   | _ -> fail "Triangulate changed a vertex storage kind");
  check (int_values Attribute.Primitive "material" one = [|7;7;9|])
    "Triangulate did not replicate primitive payload";
  check (int_values Attribute.Point "point_id" one = [|0;1;2;3;4;5;6|])
    "Triangulate changed point payload";
  let rows = Geometry.find_attribute ~owner:Attribute.Vertex "rows" one
      |> Option.get |> Attribute.storage in
  (match rows with
   | Attribute.Float_array rows ->
       let rows = Packed.Float_array.Private.view rows in
       check (rows.offsets = [|0;1;2;4;6;6;7;9;10;12|]
           && rows.values
              = [|13.;10.;11.;111.;11.;111.;13.;14.;114.;15.;16.;116.|])
         "Triangulate did not remap ragged vertex payload"
   | _ -> fail "Triangulate changed ragged storage");
  check (Group.cardinality (group Group.Primitive "selected" one) = 2
      && Group.cardinality (group Group.Primitive "curve" one) = 1)
    "Triangulate did not remap primitive groups";
  let edges = Geometry.find_edge_group "all_edges" one |> Option.get in
  check (Edge_group.length edges = 7 && Edge_group.cardinality edges = 6)
    "Triangulate did not preserve source edges or exclude its diagonal"

let test_identity_and_errors () =
  let source = fixture () in
  let empty = group Group.Primitive "empty" source in
  let unchanged = Ops.triangulate ~primitives:empty source |> get_pdk in
  check (Geometry.data_id unchanged = Geometry.data_id source)
    "empty Triangulate selection did not preserve identity";
  (match Ops.triangulate source with
   | Error error -> check (Error.code error = "invalid_topology")
       "selected curve diagnostic code"
   | Ok _ -> fail "Triangulate accepted an implicitly selected curve");
  (match Ops.triangulate ~primitives:(group Group.Primitive "curve" source) source with
   | Error error -> check (Error.code error = "invalid_topology")
       "explicit curve diagnostic code"
   | Ok _ -> fail "Triangulate accepted an explicitly selected curve");
  let wrong_owner = Group.init ~owner:Group.Point ~name:"wrong"
      (Geometry.point_count source) (fun _ -> false) in
  (match Ops.triangulate ~primitives:wrong_owner source with
   | Error error -> check (Error.code error = "invalid_topology")
       "wrong-owner diagnostic code"
   | Ok _ -> fail "Triangulate accepted a point selection");
  let wrong_length = Group.init ~owner:Group.Primitive ~name:"wrong" 1
      (fun _ -> true) in
  (match Ops.triangulate ~primitives:wrong_length source with
   | Error error -> check (Error.code error = "invalid_topology")
       "wrong-length diagnostic code"
   | Ok _ -> fail "Triangulate accepted a wrong-length selection");
  (match Ops.triangulate ~grain:0 source with
   | Error error -> check (Error.code error = "invalid_topology")
       "invalid-grain diagnostic code"
   | Ok _ -> fail "Triangulate accepted zero grain");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Ops.triangulate ~cancel ~primitives:empty source with
   | Error error -> check (Error.code error = "cancelled")
       "cancellation diagnostic code"
   | Ok _ -> fail "Triangulate ignored cancellation")

let test_already_triangular_identity () =
  let source = fixture () in
  let selected = group Group.Primitive "selected" source in
  let triangulated = Ops.triangulate ~primitives:selected source |> get_pdk in
  let selected_triangles = group Group.Primitive "selected" triangulated in
  let unchanged = Ops.triangulate ~primitives:selected_triangles triangulated
      |> get_pdk in
  check (Geometry.data_id unchanged = Geometry.data_id triangulated)
    "already-triangular selection did not preserve identity"

let test_collapsed_quad_and_deterministic_failure () =
  let collapsed_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;0.;1.|] ~z:(Array.make 4 0.) in
  let collapsed_topology = Topology.polygons_owned ~point_count:4
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;4|] |> get_string in
  let collapsed = Geometry.create ~positions:collapsed_positions
      ~topology:collapsed_topology
      ~attributes:[attribute Attribute.Vertex "corner"
        (Attribute.Int [|10;11;12;13|])] () |> get_string
      |> Ops.triangulate |> get_pdk in
  let collapsed_view = Topology.Private.view (Geometry.topology collapsed) in
  check (collapsed_view.vertex_points = [|0;1;3|]
      && int_values Attribute.Vertex "corner" collapsed = [|10;11;13|])
    "Triangulate collapsed-edge quad policy";
  let degenerate_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;3.; 4.;5.;6.;7.|]
      ~y:(Array.make 8 0.) ~z:(Array.make 8 0.) in
  let degenerate_topology = Topology.polygons_owned ~point_count:8
      ~vertex_points:[|0;1;2;3; 4;5;6;7|]
      ~primitive_offsets:[|0;4;8|] |> get_string in
  let degenerate = Geometry.create ~positions:degenerate_positions
      ~topology:degenerate_topology () |> get_string in
  let run domains = Parallel.run ~domains (fun () ->
    match Ops.triangulate ~grain:1 degenerate with
    | Error error -> Error.message error
    | Ok _ -> fail "Triangulate accepted degenerate polygons") in
  let one = run 1 and four = run 4 in
  check (String.equal one four
      && String.equal one
         "Pdk.Ops.triangulate: primitive 0 has degenerate projected area")
    "Triangulate did not report the stable lowest failing primitive"

let () =
  test_grouped_mixed_geometry ();
  test_identity_and_errors ();
  test_already_triangular_identity ();
  test_collapsed_quad_and_deterministic_failure ();
  print_endline "Triangulate tests passed"
