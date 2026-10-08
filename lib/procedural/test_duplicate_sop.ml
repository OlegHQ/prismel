open Procedural

let fail message = prerr_endline ("test_duplicate_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let context domains = Context.create ~domains ~grain:2 ~seed:31L () |> get
let session () = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get
let contains value needle =
  let rec loop at = at + String.length needle <= String.length value
      && (String.sub value at (String.length needle) = needle || loop (at + 1)) in
  needle = "" || loop 0

let source () =
  let positions = Rdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;0.;1.;2.;9.|] ~y:[|0.;0.;0.;1.;1.;1.;9.|]
      ~z:(Array.make 7 0.) in
  let topology = Rdk.Topology.polygons_owned ~point_count:7
      ~vertex_points:[|0;1;4;3; 1;2;5;4|]
      ~primitive_offsets:[|0;4;8|] |> Result.get_ok in
  let selected = Rdk.Group.ordered ~owner:Rdk.Group.Primitive ~name:"right"
      ~length:2 [|1|] |> Result.get_ok
  and id = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"id"
      (Rdk.Attribute.Int (Array.init 7 (fun point -> 10 + point)))
      |> Result.get_ok in
  Rdk.Geometry.create ~positions ~topology ~attributes:[id] ~groups:[selected] ()
    |> Result.get_ok

let cook evaluator domains graph =
  match Session.cook evaluator ~context:(context domains) graph with
  | Ok output -> (Result.get_ok (Procedural.Payload.geometry output.payload))
  | Error error -> fail (Diagnostic.error_to_string error)

let point_ids geometry =
  match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "id" geometry with
  | Some attribute -> (match Rdk.Attribute.Private.storage attribute with
      | Rdk.Attribute.Int values -> values | _ -> fail "id storage")
  | None -> fail "missing id"

let equal left right =
  let lt = Rdk.Topology.Private.view (Rdk.Geometry.topology left)
  and rt = Rdk.Topology.Private.view (Rdk.Geometry.topology right)
  and lp = Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions left)
  and rp = Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions right) in
  lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && point_ids left = point_ids right

let run () =
  let graph = Sop.snapshot (source ())
      |> Sop.duplicate ~label:"duplicate-test" ~copies:2 ~group:"right"
           ~copy_group_prefix:"copy_"
           ~m03:10. ~m13:0. ~m23:0. in
  if Node.operation graph <> "duplicate"
      || not (contains (Node.parameters graph) "group=right")
      || not (contains (Node.parameters graph) "copy_group_prefix=copy_")
      || not (contains (Node.parameters graph) "preserve_groups=false") then
    fail ("cache identity: " ^ Node.parameters graph);
  let evaluator = session () in
  let one = cook evaluator 1 graph and four = cook evaluator 4 graph in
  if not (equal one four) then fail "one/four-domain output differs";
  let topology = Rdk.Topology.Private.view (Rdk.Geometry.topology one) in
  if Rdk.Geometry.point_count one <> 15
      || Rdk.Geometry.vertex_count one <> 16
      || Rdk.Geometry.primitive_count one <> 4
      || topology.vertex_points
           <> [|0;1;4;3;1;2;5;4; 7;8;10;9;11;12;14;13|]
      || point_ids one
           <> [|10;11;12;13;14;15;16;11;12;14;15;11;12;14;15|] then
    fail "selected duplicate result";
  let first = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "copy_1" one
      |> Option.get
  and second = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "copy_2" one
      |> Option.get in
  if Rdk.Group.cardinality first <> 1 || not (Rdk.Group.mem 2 first)
      || Rdk.Group.cardinality second <> 1 || not (Rdk.Group.mem 3 second) then
    fail "copy output groups";
  let misses = (Session.stats evaluator).misses in
  ignore (cook evaluator 4 graph);
  if (Session.stats evaluator).misses <> misses then fail "stable graph missed cache";
  Session.close evaluator;
  let missing = Sop.snapshot (source ())
      |> Sop.duplicate ~group:"absent" in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context 1) missing with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing group accepted");
  Session.close evaluator;
  print_endline "test_duplicate_sop: ok"
