open Procedural

let fail message = prerr_endline ("test_poly_bridge_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let contains value needle =
  let value_length = String.length value and needle_length = String.length needle in
  let rec loop index = index + needle_length <= value_length
      && (String.sub value index needle_length = needle || loop (index + 1)) in
  needle_length = 0 || loop 0

let context () = Context.create ~domains:4 ~grain:17 () |> get
let session () = Session.create ~max_entries:16 ~max_payload_bytes:8_000_000 |> get

let bridge_source () =
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|-1.;1.;1.;-1.; -1.;1.;1.;-1.|]
      ~y:[|0.;0.;0.;0.; 1.;1.;1.;1.|]
      ~z:[|-1.;-1.;1.;1.; -1.;-1.;1.;1.|] in
  let topology = Pdk.Topology.create_owned ~point_count:8
      ~vertex_points:[|0;1;2;3; 4;5;6;7|]
      ~primitive_offsets:[|0;4;8|]
      ~primitive_kinds:[|Pdk.Topology.Polygon;Pdk.Topology.Polygon|] |> get in
  let index = Pdk.Topology_index.create topology in
  let source = Pdk.Edge_group.init ~grain:1 ~topology ~index ~name:"source"
      (fun edge -> let a, _ = Pdk.Topology_index.edge_points index edge in a < 4)
  and destination = Pdk.Edge_group.init ~grain:1 ~topology ~index
      ~name:"destination" (fun edge ->
        let a, _ = Pdk.Topology_index.edge_points index edge in a >= 4) in
  Pdk.Geometry.create ~positions ~topology ~edge_groups:[source;destination] ()
  |> get

let cook graph =
  let session = session () in
  let output = match Session.cook session ~context:(context ()) graph with
    | Ok output -> output.Session.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session; output

let () =
  let graph = Sop.snapshot (bridge_source ())
      |> Sop.poly_bridge ~source_group:"source" ~destination_group:"destination"
           ~pairing:Pdk.Ops.Bridge_by_centroid ~reverse_destination:true
           ~divisions:3 ~output_group:"bridge" in
  let output = cook graph in
  if Pdk.Geometry.point_count output <> 16
     || Pdk.Geometry.vertex_count output <> 56
     || Pdk.Geometry.primitive_count output <> 14 then
    fail "PolyBridge SOP cardinality";
  (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive "bridge" output with
   | Some group when Pdk.Group.cardinality group = 12 -> ()
   | _ -> fail "PolyBridge SOP output group");
  if Node.operation graph <> "poly_bridge"
     || not (contains (Node.parameters graph) "pairing=centroid")
     || not (contains (Node.parameters graph) "reverse_destination=true")
     || not (contains (Node.parameters graph) "divisions=3") then
    fail "PolyBridge cache identity";
  let invalid = Sop.snapshot (bridge_source ())
      |> Sop.poly_bridge ~source_group:"missing" ~destination_group:"destination" in
  let session = session () in
  (match Session.cook session ~context:(context ()) invalid with
   | Error error when error.Diagnostic.code = "missing_edge_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing PolyBridge edge group accepted");
  Session.close session;
  print_endline "test_poly_bridge_sop: ok"
