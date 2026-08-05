open Procedural

let fail message = prerr_endline ("test_dissolve_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message

let context () = Context.create ~domains:4 ~grain:17 () |> get
let session () = Session.create ~max_entries:16 ~max_payload_bytes:8_000_000 |> get

let cook graph =
  let session = session () in
  let output = match Session.cook session ~context:(context ()) graph with
    | Ok output -> output.Session.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session; output

let () =
  let graph = Sop.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:8 ~rows:6 ~size:2. ()
      |> Sop.group_edges ~name:"interior" ~incidence:Pdk.Ops.Manifold_edge
      |> Sop.dissolve ~group:"interior" ~remove_inline_points:true
           ~collinearity_tolerance:1e-10 in
  let output = cook graph in
  if Pdk.Geometry.point_count output <> 4
     || Pdk.Geometry.vertex_count output <> 4
     || Pdk.Geometry.primitive_count output <> 1 then
    fail "Dissolve SOP cardinality";
  let invalid = Sop.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:2 ~rows:2 ~size:1. () |> Sop.dissolve ~group:"missing" in
  let session = session () in
  (match Session.cook session ~context:(context ()) invalid with
   | Error error when error.Diagnostic.code = "missing_edge_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing Dissolve group was accepted");
  Session.close session;
  print_endline "test_dissolve_sop: ok"
