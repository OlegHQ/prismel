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
      ~x:[|0.;1.;1.;0.;(-1.);(-2.)|]
      ~y:[|0.;0.;1.;1.;2.;3.|] ~z:(Array.make 6 0.) in
  let topology = Topology.create_owned ~point_count:6
      ~vertex_points:[|0;1;2;3; 3;4;5|]
      ~primitive_offsets:[|0;4;7|]
      ~primitive_kinds:[|Topology.Polygon; Topology.Open_polyline|]
      |> get_string in
  let vertex_n = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init 7 float_of_int) ~y:(Array.make 7 2.)
      ~z:(Array.make 7 3.) in
  let rows = Packed.Int_array.create_owned
      ~offsets:[|0;1;3;3;4;6;7;9|]
      ~values:[|10;11;111;13;14;114;15;16;116|] |> get_string in
  let attributes = [
    attribute Attribute.Point "N" (Attribute.Float3
      (Packed.Float3.Private.of_owned_exn ~x:(Array.make 6 0.)
        ~y:(Array.make 6 0.) ~z:(Array.make 6 1.)));
    attribute Attribute.Point "point_id" (Attribute.Int [|0;1;2;3;4;5|]);
    attribute Attribute.Vertex "N" (Attribute.Float3 vertex_n);
    attribute Attribute.Vertex "corner" (Attribute.Int [|10;11;12;13;14;15;16|]);
    attribute Attribute.Vertex "rows" (Attribute.Int_array rows);
    attribute Attribute.Primitive "material" (Attribute.Int [|7;9|]);
    attribute Attribute.Detail "tag" (Attribute.Text [|"reverse"|]);
  ] in
  let selected = Group.ordered ~owner:Group.Primitive ~name:"selected"
      ~length:2 [|0|] |> get_string
  and empty = Group.init ~owner:Group.Primitive ~name:"empty" 2 (fun _ -> false)
  and ordered_vertices = Group.ordered ~owner:Group.Vertex
      ~name:"ordered_vertices" ~length:7 [|6;4;1|] |> get_string in
  Geometry.create ~positions ~topology ~attributes
    ~groups:[selected; empty; ordered_vertices] () |> get_string
  |> Ops.group_edges ~name:"all_edges" |> get_pdk

let topology_points geometry =
  (Topology.Private.view (Geometry.topology geometry)).vertex_points

let int_values owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail ("wrong integer storage for " ^ name))
  | None -> fail ("missing integer attribute " ^ name)

let equal_storage left right = match Attribute.storage left, Attribute.storage right with
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
  && Array.for_all (fun index -> Group.mem index left = Group.mem index right)
       (Array.init (Group.length left) Fun.id)

let equal_geometry left right =
  topology_points left = topology_points right
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

let test_reverse () =
  let run domains = Parallel.run ~domains (fun () ->
    Ops.reverse ~grain:1 (fixture ()) |> get_pdk) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "Reverse differs across one and four domains";
  check (topology_points one = [|3;2;1;0; 5;4;3|])
    "Reverse did not reverse polygon and curve corners";
  check (int_values Attribute.Vertex "corner" one
      = [|13;12;11;10; 16;15;14|])
    "Reverse did not remap vertex payload";
  check (Geometry.find_attribute ~owner:Attribute.Point "N" one = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" one = None)
    "Reverse retained invalid normals";
  check (int_values Attribute.Point "point_id" one = [|0;1;2;3;4;5|]
      && int_values Attribute.Primitive "material" one = [|7;9|])
    "Reverse changed point/primitive payload";
  check (Edge_group.cardinality
      (Geometry.find_edge_group "all_edges" one |> Option.get) = 6)
    "Reverse changed native edge-group membership"

let test_local_and_shift () =
  let source = fixture () in
  let selected = group Group.Primitive "selected" source in
  let local = Ops.reverse ~grain:1 ~primitives:selected source |> get_pdk in
  check (topology_points local = [|3;2;1;0; 3;4;5|])
    "local Reverse changed an unselected curve";
  let shift domains offset = Parallel.run ~domains (fun () ->
    let source = fixture () in
    Ops.reverse ~grain:1 ~primitives:(group Group.Primitive "selected" source)
      ~operation:(Ops.Shift_vertices offset) source |> get_pdk) in
  let shifted = shift 1 1 and shifted_four = shift 4 1 in
  check (equal_geometry shifted shifted_four)
    "Shift Reverse differs across one and four domains";
  check (topology_points shifted = [|1;2;3;0; 3;4;5|]
      && int_values Attribute.Vertex "corner" shifted
         = [|11;12;13;10; 14;15;16|])
    "positive corner shift used the wrong wrapping permutation";
  check (topology_points (shift 1 (-1)) = [|3;0;1;2; 3;4;5|]
      && topology_points (shift 1 5) = topology_points shifted)
    "signed/large corner shift did not wrap per primitive";
  check (Geometry.find_attribute ~owner:Attribute.Point "N" shifted <> None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" shifted <> None)
    "corner shift invalidated unchanged normals";
  check (Group.ordered_elements
      (group Group.Vertex "ordered_vertices" shifted) = Some [|6;4;0|])
    "corner shift did not remap ordered vertex-group ancestry";
  let rows = Geometry.find_attribute ~owner:Attribute.Vertex "rows" shifted
      |> Option.get |> Attribute.storage in
  (match rows with
   | Attribute.Int_array rows ->
       let rows = Packed.Int_array.Private.view rows in
       check (rows.offsets = [|0;2;2;3;4;6;7;9|]
           && rows.values = [|11;111;13;10;14;114;15;16;116|])
         "corner shift did not remap CSR vertex rows"
   | _ -> fail "corner shift changed CSR storage");
  let identity = Ops.reverse ~grain:1 ~primitives:selected
      ~operation:(Ops.Shift_vertices 4) source |> get_pdk in
  check (Geometry.data_id identity = Geometry.data_id source)
    "whole-cycle corner shift did not preserve identity";
  let empty = group Group.Primitive "empty" source in
  let empty_output = Ops.reverse ~grain:1 ~primitives:empty source |> get_pdk in
  check (Geometry.data_id empty_output = Geometry.data_id source)
    "empty local Reverse did not preserve identity"

let test_errors_and_cancellation () =
  let source = fixture () in
  let wrong_owner = Group.init ~owner:Group.Point ~name:"wrong"
      (Geometry.point_count source) (fun _ -> false) in
  (match Ops.reverse ~primitives:wrong_owner source with
   | Error error -> check (Error.code error = "invalid_topology")
       "Reverse wrong-owner diagnostic code"
   | Ok _ -> fail "Reverse accepted a point selection");
  let wrong_length = Group.init ~owner:Group.Primitive ~name:"wrong" 1
      (fun _ -> true) in
  (match Ops.reverse ~primitives:wrong_length source with
   | Error error -> check (Error.code error = "invalid_topology")
       "Reverse wrong-length diagnostic code"
   | Ok _ -> fail "Reverse accepted a wrong-length selection");
  (match Ops.reverse ~grain:0 source with
   | Error error -> check (Error.code error = "invalid_topology")
       "Reverse invalid-grain diagnostic code"
   | Ok _ -> fail "Reverse accepted zero grain");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Ops.reverse ~cancel source with
   | Error error -> check (Error.code error = "cancelled")
       "Reverse cancellation diagnostic code"
   | Ok _ -> fail "Reverse ignored cancellation")

let () =
  test_reverse ();
  test_local_and_shift ();
  test_errors_and_cancellation ();
  print_endline "Reverse tests passed"
