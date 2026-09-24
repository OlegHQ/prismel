open Prismel
open Procedural

let fail message = prerr_endline ("test_poly_bevel_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let contains value needle =
  let n = String.length value and m = String.length needle in
  let rec loop index = index + m <= n
      && (String.sub value index m = needle || loop (index + 1)) in
  m = 0 || loop 0

let context () = Context.create ~domains:4 ~grain:3 () |> get
let session () = Session.create ~max_entries:16 ~max_payload_bytes:8_000_000 |> get

let source () =
  Pdk.Ops.box ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
    ~normals:Pdk.Ops.Box_no_normals ~size:(Vec3.create 2. 2. 2.) ()
  |> function Ok value -> value | Error error -> fail (Pdk.Error.to_string error)

let with_edges geometry =
  let topology = Pdk.Geometry.topology geometry in
  let index = Pdk.Topology_index.create topology in
  let group = Pdk.Edge_group.init ~topology ~index ~name:"bevel_edges"
      (Fun.const true) in
  Pdk.Geometry.with_edge_group group geometry |> get

let () =
  let graph = Sop.snapshot (with_edges (source ()))
      |> Sop.poly_bevel ~group:"bevel_edges"
           ~shape:(Pdk.Ops.Bevel_round { convexity = 0.75 }) ~divisions:3
           ~distance:0.2 ~edge_group:"edge_fillets"
           ~corner_group:"corner_fillets" ~offset_group:"offset_edges" in
  let evaluator = session () in
  let output = match Session.cook evaluator ~context:(context ()) graph with
    | Ok output -> output.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  if Pdk.Geometry.point_count output <> 72
      || Pdk.Geometry.primitive_count output <> 50
      || Pdk.Geometry.vertex_count output <> 240 then
    fail "PolyBevel SOP cardinality";
  let group_cardinality owner name =
    match Pdk.Geometry.find_group ~owner name output with
    | Some group -> Pdk.Group.cardinality group
    | None -> fail ("missing output group " ^ name) in
  if group_cardinality Pdk.Group.Primitive "edge_fillets" <> 36
      || group_cardinality Pdk.Group.Primitive "corner_fillets" <> 8
      || (match Pdk.Geometry.find_edge_group "offset_edges" output with
          | Some group -> Pdk.Edge_group.cardinality group <> 24
          | None -> true) then
    fail "PolyBevel SOP output groups";
  if Node.operation graph <> "poly_bevel"
      || not (contains (Node.parameters graph) "shape=round:")
      || not (contains (Node.parameters graph) "divisions=3")
      || not (contains (Node.parameters graph) "distance=") then
    fail "PolyBevel SOP cache identity";
  let misses = (Session.stats evaluator).misses in
  ignore (Session.cook evaluator ~context:(context ()) graph);
  if (Session.stats evaluator).misses <> misses then
    fail "PolyBevel SOP stable graph missed its cache";
  Session.close evaluator;
  let invalid = Sop.snapshot (source ())
      |> Sop.poly_bevel ~group:"missing" ~distance:0.1 in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context ()) invalid with
   | Error error when error.Diagnostic.code = "missing_edge_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing PolyBevel edge group accepted");
  Session.close evaluator;
  print_endline "test_poly_bevel_sop: ok"
