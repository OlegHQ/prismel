open Procedural

let fail message = prerr_endline ("test_ends_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let context domains = Context.create ~domains ~grain:2 ~seed:17L () |> get
let session () = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get
let contains value needle =
  let rec loop at = at + String.length needle <= String.length value
      && (String.sub value at (String.length needle) = needle || loop (at + 1)) in
  needle = "" || loop 0

let source () =
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.; 2.;3.;3.;2.|]
      ~y:[|0.;0.;1.;1.; 0.;0.;1.;1.|]
      ~z:(Array.make 8 0.) in
  let topology = Pdk.Topology.polygons_owned ~point_count:8
      ~vertex_points:(Array.init 8 Fun.id) ~primitive_offsets:[|0;4;8|]
      |> Result.get_ok in
  let selected = Pdk.Group.ordered ~owner:Pdk.Group.Primitive ~name:"selected"
      ~length:2 [|0|] |> Result.get_ok
  and id = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"id"
      (Pdk.Attribute.Int (Array.init 8 (fun point -> 100 + point)))
      |> Result.get_ok in
  Pdk.Geometry.create ~positions ~topology ~attributes:[id] ~groups:[selected] ()
    |> Result.get_ok

let cook evaluator domains graph =
  match Session.cook evaluator ~context:(context domains) graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let point_ids geometry =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point "id" geometry with
  | Some attribute -> (match Pdk.Attribute.Private.storage attribute with
      | Pdk.Attribute.Int values -> values
      | _ -> fail "id storage")
  | None -> fail "missing id"

let equal left right =
  let lt = Pdk.Topology.Private.view (Pdk.Geometry.topology left)
  and rt = Pdk.Topology.Private.view (Pdk.Geometry.topology right) in
  let lp = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions left)
  and rp = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions right) in
  lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && point_ids left = point_ids right

let () =
  let graph = Sop.snapshot (source ())
      |> Sop.ends ~label:"ends-test" ~group:"selected"
           Pdk.Ops.Ends_unroll_new in
  if Node.operation graph <> "ends"
      || not (contains (Node.parameters graph) "group=\"selected\"")
      || not (contains (Node.parameters graph) "mode=unroll_new") then
    fail ("cache identity: " ^ Node.parameters graph);
  let evaluator = session () in
  let one = cook evaluator 1 graph and four = cook evaluator 4 graph in
  if not (equal one four) then fail "one/four-domain output differs";
  let topology = Pdk.Topology.Private.view (Pdk.Geometry.topology one) in
  if Pdk.Geometry.point_count one <> 9 || Pdk.Geometry.vertex_count one <> 9
      || topology.vertex_points <> [|0;1;2;3;8;4;5;6;7|]
      || Pdk.Topology.primitive_kind (Pdk.Geometry.topology one) 0
           <> Pdk.Topology.Open_polyline
      || Pdk.Topology.primitive_kind (Pdk.Geometry.topology one) 1
           <> Pdk.Topology.Polygon
      || point_ids one <> [|100;101;102;103;104;105;106;107;100|] then
    fail "selected new-point unroll result";
  let misses = (Session.stats evaluator).misses in
  ignore (cook evaluator 4 graph);
  if (Session.stats evaluator).misses <> misses then fail "stable graph missed cache";
  Session.close evaluator;
  let missing = Sop.snapshot (source ())
      |> Sop.ends ~group:"absent" Pdk.Ops.Ends_open in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context 1) missing with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing group accepted");
  Session.close evaluator;
  print_endline "test_ends_sop: ok"
