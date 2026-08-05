open Prismel
open Pdk

let fail message = prerr_endline ("test_ends: " ^ message); exit 1
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error error -> fail (Error.to_string error)
let attribute owner name storage =
  Attribute.create_owned ~owner ~name storage |> Result.get_ok

let point_int name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | Some value -> (match Attribute.Private.storage value with
      | Attribute.Int values -> values
      | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let vertex_int name geometry =
  match Geometry.find_attribute ~owner:Attribute.Vertex name geometry with
  | Some value -> (match Attribute.Private.storage value with
      | Attribute.Int values -> values
      | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let text_attribute owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some value -> (match Attribute.Private.storage value with
      | Attribute.Text values -> values
      | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let fixture () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.; 2.;3.;3.|]
      ~y:[|0.;0.;1.;1.; 0.;0.;1.|]
      ~z:(Array.make 7 0.) in
  let topology = Topology.create_owned ~point_count:7
      ~vertex_points:[|0;1;2;3; 4;5;6|]
      ~primitive_offsets:[|0;4;7|]
      ~primitive_kinds:[|Topology.Polygon;Topology.Open_polyline|]
      |> Result.get_ok in
  let geometry = Geometry.create ~positions ~topology
      ~attributes:[
        attribute Attribute.Point "id" (Attribute.Int [|10;11;12;13;20;21;22|]);
        attribute Attribute.Point "weights" (Attribute.Float_array
          (Packed.Float_array.create_owned
            ~offsets:[|0;2;3;3;4;5;7;8|]
            ~values:[|0.1;0.2;1.1;3.1;4.1;5.1;5.2;6.1|]
            |> Result.get_ok));
        attribute Attribute.Vertex "corner"
          (Attribute.Int [|100;101;102;103;200;201;202|]);
        attribute Attribute.Vertex "links" (Attribute.Int_array
          (Packed.Int_array.create_owned ~offsets:[|0;1;3;3;4;5;7;8|]
            ~values:[|1000;1010;1011;1030;2000;2010;2011;2020|]
            |> Result.get_ok));
        attribute Attribute.Primitive "piece" (Attribute.Text [|"face";"curve"|]);
        attribute Attribute.Detail "author" (Attribute.Text [|"ends"|])]
      ~groups:[
        Group.ordered ~owner:Group.Point ~name:"seam" ~length:7 [|0|]
          |> Result.get_ok;
        Group.ordered ~owner:Group.Vertex ~name:"first_corner" ~length:7 [|0|]
          |> Result.get_ok;
        Group.init ~grain:1 ~owner:Group.Primitive ~name:"face_only" 2
          (fun primitive -> primitive = 0);
        Group.init ~grain:1 ~owner:Group.Primitive ~name:"curve_only" 2
          (fun primitive -> primitive = 1)] () |> Result.get_ok in
  Ops.group_edges ~grain:1 ~name:"all_edges" geometry |> get

let primitive_group name geometry =
  Geometry.find_group ~owner:Group.Primitive name geometry |> Option.get

let edge_group geometry = Geometry.find_edge_group "all_edges" geometry
    |> Option.get

let test_modes_and_ancestry () =
  let source = fixture () in
  let face = primitive_group "face_only" source
  and curve = primitive_group "curve_only" source in
  let opened = Ops.ends ~grain:1 ~primitives:face Ops.Ends_open source |> get in
  check (Topology.primitive_kind (Geometry.topology opened) 0
      = Topology.Open_polyline && Geometry.point_count opened = 7
      && Geometry.vertex_count opened = 7
      && Edge_group.cardinality (edge_group opened) = 5)
    "open face topology/edge ancestry";
  let shared = Ops.ends ~grain:1 ~primitives:face Ops.Ends_unroll_shared source
      |> get in
  let shared_topology = Topology.Private.view (Geometry.topology shared) in
  check (Geometry.point_count shared = 7 && Geometry.vertex_count shared = 8
      && shared_topology.vertex_points = [|0;1;2;3;0;4;5;6|]
      && Edge_group.cardinality (edge_group shared) = 6)
    "shared unroll topology/edge ancestry";
  check (vertex_int "corner" shared
      = [|100;101;102;103;100;200;201;202|])
    "shared unroll vertex payload";
  let duplicated = Ops.ends ~grain:1 ~primitives:face Ops.Ends_unroll_new source
      |> get in
  let duplicated_topology = Topology.Private.view (Geometry.topology duplicated) in
  check (Geometry.point_count duplicated = 8 && Geometry.vertex_count duplicated = 8
      && duplicated_topology.vertex_points = [|0;1;2;3;7;4;5;6|]
      && point_int "id" duplicated = [|10;11;12;13;20;21;22;10|]
      && vertex_int "corner" duplicated
           = [|100;101;102;103;100;200;201;202|]
      && Edge_group.cardinality (edge_group duplicated) = 6)
    "new-point unroll payload/topology/edge ancestry";
  check (text_attribute Attribute.Primitive "piece" duplicated
        = [|"face";"curve"|]
      && text_attribute Attribute.Detail "author" duplicated = [|"ends"|])
    "primitive/detail payload sharing";
  let weights = match Geometry.find_attribute ~owner:Attribute.Point "weights"
      duplicated with
    | Some value -> (match Attribute.Private.storage value with
        | Attribute.Float_array values -> values
        | _ -> fail "weights storage")
    | None -> fail "missing weights"
  and links = match Geometry.find_attribute ~owner:Attribute.Vertex "links"
      duplicated with
    | Some value -> (match Attribute.Private.storage value with
        | Attribute.Int_array values -> values
        | _ -> fail "links storage")
    | None -> fail "missing links" in
  check (Packed.Float_array.get weights 7 = [|0.1;0.2|]
      && Packed.Int_array.get links 4 = [|1000|])
    "new-point unroll ragged payload";
  let seam = Geometry.find_group ~owner:Group.Point "seam" duplicated
      |> Option.get
  and first_corner = Geometry.find_group ~owner:Group.Vertex "first_corner"
      duplicated |> Option.get in
  check (Group.cardinality seam = 2 && Group.mem 0 seam && Group.mem 7 seam
      && Group.cardinality first_corner = 2 && Group.mem 0 first_corner
      && Group.mem 4 first_corner
      && Group.ordered_elements seam = Some [|0;7|]
      && Group.ordered_elements first_corner = Some [|0;4|])
    "new-point unroll ordered-group ancestry";
  let positions = Packed.Float3.Private.view (Geometry.positions duplicated) in
  check (positions.x.(7) = positions.x.(0) && positions.y.(7) = positions.y.(0)
      && positions.z.(7) = positions.z.(0)) "new seam point position";
  let closed = Ops.ends ~grain:1 ~primitives:curve Ops.Ends_close_straight source
      |> get in
  check (Topology.primitive_kind (Geometry.topology closed) 1 = Topology.Polygon
      && Edge_group.length (edge_group closed) = 7
      && Edge_group.cardinality (edge_group closed) = 6)
    "straight close generated-edge policy";
  let roundtrip = Ops.points [|0.,0.,0.;1.,0.,0.;1.,1.,0.;0.,1.,0.|]
      |> fun geometry ->
        let topology = Topology.polygons_owned ~point_count:4
            ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;4|]
            |> Result.get_ok in
        Geometry.create ~positions:(Geometry.positions geometry) ~topology ()
          |> Result.get_ok
      |> Ops.ends Ops.Ends_unroll_shared |> get
      |> Ops.ends Ops.Ends_close_straight |> get in
  check (Geometry.vertex_count roundtrip = 4
      && Topology.primitive_kind (Geometry.topology roundtrip) 0 = Topology.Polygon)
    "shared unroll/close roundtrip";
  let open_identity =
    Ops.ends ~grain:1 ~primitives:curve Ops.Ends_open source |> get
  and close_identity =
    Ops.ends ~grain:1 ~primitives:face Ops.Ends_close_straight source |> get in
  check (open_identity == source && close_identity == source)
    "identity-preserving closure no-ops"

let test_malformed_and_cancel () =
  let source = fixture () in
  let expect label = function
    | Error _ -> () | Ok _ -> fail ("accepted " ^ label) in
  let point_group = Group.init ~owner:Group.Point ~name:"wrong" 7 (fun _ -> true) in
  expect "point-owned primitive selection"
    (Ops.ends ~primitives:point_group Ops.Ends_open source);
  let short_selection =
    Group.init ~owner:Group.Primitive ~name:"short" 1 (fun _ -> true) in
  expect "wrong-length primitive selection"
    (Ops.ends ~primitives:short_selection Ops.Ends_open source);
  let short = Ops.polyline [|0.,0.,0.;1.,0.,0.|] |> get in
  expect "two-point straight close" (Ops.ends Ops.Ends_close_straight short);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.ends ~cancel:cancelled Ops.Ends_unroll_new source with
   | Error error when Error.code error = "cancelled" -> ()
   | Error error -> fail ("unexpected cancellation: " ^ Error.to_string error)
   | Ok _ -> fail "ignored cancellation")

let test_shared_topology_edge_fallback () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;0.;1.;2.|] ~y:[|0.;0.;0.;1.;1.;1.|]
      ~z:(Array.make 6 0.) in
  let topology = Topology.polygons_owned ~point_count:6
      ~vertex_points:[|0;1;4;3; 1;2;5;4|]
      ~primitive_offsets:[|0;4;8|] |> Result.get_ok in
  let source = Geometry.create ~positions ~topology () |> Result.get_ok
      |> Ops.group_edges ~grain:1 ~name:"all_edges" |> get in
  let output = Ops.ends ~grain:1 Ops.Ends_unroll_new source |> get in
  let edges = edge_group output in
  if Geometry.point_count output <> 8 || Geometry.vertex_count output <> 10
      || Edge_group.length edges <> 8 || Edge_group.cardinality edges <> 8 then
    fail (Printf.sprintf
      "shared-topology reverse-index edge ancestry: points=%d vertices=%d edges=%d selected=%d"
      (Geometry.point_count output) (Geometry.vertex_count output)
      (Edge_group.length edges) (Edge_group.cardinality edges))

let equal_large left right =
  let lp = Packed.Float3.Private.view (Geometry.positions left)
  and rp = Packed.Float3.Private.view (Geometry.positions right)
  and lt = Topology.Private.view (Geometry.topology left)
  and rt = Topology.Private.view (Geometry.topology right) in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && point_int "id" left = point_int "id" right
  && vertex_int "corner" left = vertex_int "corner" right
  && let lg = Geometry.find_group ~owner:Group.Point "marked" left |> Option.get
     and rg = Geometry.find_group ~owner:Group.Point "marked" right |> Option.get in
     Group.cardinality lg = Group.cardinality rg
     && let same_group = ref true in
        for point = 0 to Group.length lg - 1 do
          if Group.mem point lg <> Group.mem point rg then same_group := false
        done;
        !same_group
     && let le = edge_group left and re = edge_group right in
        Edge_group.length le = Edge_group.length re
        && Edge_group.cardinality le = Edge_group.cardinality re
        && let same = ref true in
           for edge = 0 to Edge_group.length le - 1 do
             if Edge_group.mem edge le <> Edge_group.mem edge re then same := false
           done;
           !same

let test_parallel_exact () =
  let quads = 100_000 and points = 400_000 in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init points (fun point ->
        float_of_int ((point / 4) mod 1_000) +.
          (if point land 3 = 1 || point land 3 = 2 then 0.75 else 0.)))
      ~y:(Array.init points (fun point ->
        float_of_int ((point / 4) / 1_000) +.
          (if point land 3 >= 2 then 0.75 else 0.)))
      ~z:(Array.make points 0.) in
  let topology = Topology.polygons_owned ~point_count:points
      ~vertex_points:(Array.init points Fun.id)
      ~primitive_offsets:(Array.init (quads + 1) (fun primitive -> primitive * 4))
      |> Result.get_ok in
  let source = Geometry.create ~positions ~topology
      ~attributes:[
        attribute Attribute.Point "id" (Attribute.Int (Array.init points Fun.id));
        attribute Attribute.Vertex "corner"
          (Attribute.Int (Array.init points (fun vertex -> vertex land 3)))]
      ~groups:[Group.init ~owner:Group.Point ~name:"marked" points
        (fun point -> point land 7 = 0)] () |> Result.get_ok
      |> Ops.group_edges ~name:"all_edges" |> get in
  let cook domains = Parallel.run ~domains (fun () ->
      Ops.ends ~grain:4_096 Ops.Ends_unroll_new source |> get) in
  let one = cook 1 and four = cook 4 in
  check (Geometry.point_count one = 500_000
      && Geometry.vertex_count one = 500_000
      && Geometry.primitive_count one = quads)
    "parallel fixture cardinality";
  check (equal_large one four) "one/four-domain output differs"

let () =
  test_modes_and_ancestry ();
  test_malformed_and_cancel ();
  test_shared_topology_edge_fallback ();
  test_parallel_exact ();
  print_endline "Ends tests passed"
