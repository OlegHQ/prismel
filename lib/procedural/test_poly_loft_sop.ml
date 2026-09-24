open Procedural

let fail message = prerr_endline ("test_poly_loft_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let contains value needle =
  let value_length = String.length value and needle_length = String.length needle in
  let rec loop index = index + needle_length <= value_length
      && (String.sub value index needle_length = needle || loop (index + 1)) in
  needle_length = 0 || loop 0

let context () = Context.create ~domains:4 ~grain:17 () |> get
let session () = Session.create ~max_entries:16 ~max_payload_bytes:8_000_000 |> get

let cook graph =
  let session = session () in
  let output = match Session.cook session ~context:(context ()) graph with
    | Ok output -> output.Session.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session; output

let sections () = Sop.merge [
  Sop.polyline [|0.,0.,0.; 1.,0.,0.; 2.,0.,0.|];
  Sop.polyline [|0.,1.,0.; 0.6,1.,0.2; 1.4,1.,0.2; 2.,1.,0.|];
]

let () =
  let graph = sections () |> Sop.poly_loft
      ~minimize:Pdk.Ops.Three_point_distance ~output_group:"loft" in
  let output = cook graph in
  if Pdk.Geometry.point_count output <> 7
     || Pdk.Geometry.vertex_count output <> 15
     || Pdk.Geometry.primitive_count output <> 5 then
    fail "PolyLoft SOP cardinality";
  (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive "loft" output with
   | Some group when Pdk.Group.cardinality group = 5 -> ()
   | _ -> fail "PolyLoft SOP output group");
  if not (contains (Node.parameters graph) "minimize=three_point") then
    fail "PolyLoft cache identity omits minimize policy";
  let invalid = sections () |> Sop.poly_loft ~group:"missing" in
  let session = session () in
  (match Session.cook session ~context:(context ()) invalid with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing PolyLoft group was accepted");
  Session.close session;
  print_endline "test_poly_loft_sop: ok"
