open Procedural

let fail message = prerr_endline ("test_skin_sop: " ^ message); exit 1
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

let ring y radius = Sop.polyline ~closed:true
    (Array.init 8 (fun point ->
      let angle = 2. *. Float.pi *. float_of_int point /. 8. in
      radius *. cos angle, y, radius *. sin angle))

let sections () = Sop.merge [ring 0. 1.; ring 0.5 0.8; ring 1. 1.1]

let () =
  let graph = sections () |> Sop.skin ~output_group:"skin" ~v_wrap:true in
  let output = cook graph in
  if Pdk.Geometry.point_count output <> 24
     || Pdk.Geometry.vertex_count output <> 96
     || Pdk.Geometry.primitive_count output <> 24 then
    fail "Skin SOP cardinality";
  (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive "skin" output with
   | Some group when Pdk.Group.cardinality group = 24 -> ()
   | _ -> fail "Skin SOP output group");
  if Node.operation graph <> "skin" || not (contains (Node.parameters graph)
      "minimize=two_point") then fail "Skin cache identity";
  let invalid = sections () |> Sop.skin ~group:"missing" in
  let session = session () in
  (match Session.cook session ~context:(context ()) invalid with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing Skin group was accepted");
  Session.close session;
  print_endline "test_skin_sop: ok"
