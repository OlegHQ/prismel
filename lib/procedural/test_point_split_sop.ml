open Procedural

let fail message = prerr_endline ("test_point_split_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let context () = Context.create ~domains:4 ~grain:3 () |> get
let session () = Session.create ~max_entries:16 ~max_payload_bytes:8_000_000 |> get

let contains value needle =
  let rec loop at = at + String.length needle <= String.length value
      && (String.sub value at (String.length needle) = needle || loop (at + 1)) in
  needle = "" || loop 0

let source () =
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;1.;1.|] ~z:(Array.make 4 0.) in
  let topology = Pdk.Topology.polygons_owned ~point_count:4
      ~vertex_points:[|0;1;2;0;2;3|] ~primitive_offsets:[|0;3;6|]
      |> Result.get_ok in
  let uv = Pdk.Packed.Float2.of_owned
      ~x:[|0.;1.;1.;2.;3.;0.|] ~y:[|0.;0.;1.;2.;3.;1.|]
      |> Result.get_ok in
  let uv = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Vertex ~name:"uv"
      (Pdk.Attribute.Float2 uv) |> Result.get_ok
  and selected = Pdk.Group.init ~grain:1 ~owner:Pdk.Group.Point
      ~name:"split_points" 4 (fun point -> point = 0 || point = 2)
  and seam_face = Pdk.Group.init ~grain:1 ~owner:Pdk.Group.Primitive
      ~name:"seam_face" 2 (fun primitive -> primitive = 0) in
  Pdk.Geometry.create ~positions ~topology ~attributes:[uv]
    ~groups:[selected;seam_face] ()
  |> Result.get_ok

let cook evaluator graph =
  match Session.cook evaluator ~context:(context ()) graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let () =
  let graph = Sop.snapshot (source ())
      |> Sop.point_split ~selection:(Sop.Point_group "split_points")
           ~attributes:"uv" ~tolerance:1e-6 ~promote_attributes:true in
  let evaluator = session () in
  let output = cook evaluator graph in
  if Pdk.Geometry.point_count output <> 6 then fail "SOP cardinality";
  if Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point "uv" output = None
      || Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Vertex "uv" output <> None
  then fail "SOP promotion";
  if Node.operation graph <> "point_split"
      || not (contains (Node.parameters graph) "selection=point:split_points")
      || not (contains (Node.parameters graph) "attributes=uv")
      || not (contains (Node.parameters graph) "promote=true") then
    fail "SOP cache identity";
  let misses = (Session.stats evaluator).misses in
  ignore (cook evaluator graph);
  if (Session.stats evaluator).misses <> misses then
    fail "stable SOP graph missed cache";
  Session.close evaluator;
  let group_graph = Sop.snapshot (source ())
      |> Sop.point_split ~attributes:"seam_*" in
  let evaluator = session () in
  let group_output = cook evaluator group_graph in
  if Pdk.Geometry.point_count group_output <> 6 then
    fail "SOP primitive-group seam cardinality";
  if not (contains (Node.parameters group_graph) "attributes=seam_*") then
    fail "SOP group-seam cache identity";
  Session.close evaluator;
  let missing = Sop.snapshot (source ())
      |> Sop.point_split ~selection:(Sop.Vertex_group "missing") in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context ()) missing with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing selection group accepted");
  Session.close evaluator;
  let missing_attribute = Sop.snapshot (source ())
      |> Sop.point_split ~attributes:"missing" in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context ()) missing_attribute with
   | Error error when error.Diagnostic.code = "invalid_geometry" -> ()
   | Error error -> fail ("unexpected attribute diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing seam attribute accepted");
  Session.close evaluator;
  print_endline "test_point_split_sop: ok"
