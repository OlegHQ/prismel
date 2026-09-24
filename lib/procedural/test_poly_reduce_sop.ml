open Procedural

let fail message = prerr_endline ("test_poly_reduce_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let contains value needle =
  let value_length = String.length value and needle_length = String.length needle in
  let rec loop index = index + needle_length <= value_length
      && (String.sub value index needle_length = needle || loop (index + 1)) in
  needle_length = 0 || loop 0

let context () = Context.create ~domains:4 ~grain:31 () |> get
let session () = Session.create ~max_entries:16 ~max_payload_bytes:32_000_000 |> get

let cook graph =
  let session = session () in
  let output = match Session.cook session ~context:(context ()) graph with
    | Ok output -> output.Session.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session; output

let () =
  let graph = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:32 ~rows:24 ~size:8. ()
      |> Sop.poly_reduce ~target:(Pdk.Ops.Reduce_ratio 0.4)
           ~preserve_boundary:true ~equalize_lengths:1e-8
           ~max_normal_deviation:0.5 ~output_group:"reduced" in
  let output = cook graph in
  if Pdk.Geometry.primitive_count output >= (31 * 23 * 2) then
    fail "PolyReduce SOP did not reduce its input";
  (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive "reduced" output with
   | Some group when Pdk.Group.cardinality group
       = Pdk.Geometry.primitive_count output -> ()
   | _ -> fail "PolyReduce SOP output group");
  if Node.operation graph <> "poly_reduce"
     || not (contains (Node.parameters graph) "target=ratio:")
     || not (contains (Node.parameters graph) "preserve_boundary=true")
     || not (contains (Node.parameters graph) "equalize_lengths=") then
    fail "PolyReduce cache identity";
  let invalid = Sop.grid ~connectivity:Pdk.Ops.Grid_triangles
      ~columns:4 ~rows:4 ~size:1. ()
      |> Sop.poly_reduce ~hard_edge_group:"missing" in
  let session = session () in
  (match Session.cook session ~context:(context ()) invalid with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing PolyReduce hard edge group accepted");
  Session.close session;
  print_endline "test_poly_reduce_sop: ok"
