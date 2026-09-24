open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error _ -> fail "unexpected error"

let contains text pattern =
  let rec search offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || search (offset + 1)) in
  pattern = "" || search 0

let source count =
  let count = count - (count mod 3) in
  let primitive_count = count / 3 in
  let topology = Topology.polygons_owned ~point_count:count
      ~vertex_points:(Array.init count Fun.id)
      ~primitive_offsets:(Array.init (primitive_count + 1) (fun primitive ->
        primitive * 3)) |> Result.get_ok in
  let geometry = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn
        ~x:(Array.init count float_of_int) ~y:(Array.make count 0.)
        ~z:(Array.make count 0.)) ~topology () |> Result.get_ok in
  let target = Attribute.create_owned ~owner:Attribute.Point ~name:"target"
      (Attribute.Int (Array.init count (fun point ->
        if point mod 3 = 0 then point + 1 else -1))) |> Result.get_ok
  and selected = Group.init ~grain:257 ~owner:Group.Point ~name:"selected"
      count (fun point -> point mod 3 = 0) in
  geometry |> Geometry.with_attribute target |> Result.get_ok
  |> Geometry.with_group selected |> Result.get_ok

let context domains = Context.create ~domains ~grain:257 ~seed:1201L () |> get

let cook session domains graph =
  match Session.cook session ~context:(context domains) graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let vertex_points geometry =
  (Topology.Private.view (Geometry.topology geometry)).vertex_points

let int_attribute name geometry =
  match Geometry.find_attribute ~owner:Attribute.Vertex name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let () =
  let graph = Sop.snapshot (source 300_000)
      |> Sop.rewire_vertices ~label:"rewire-selected"
           ~selection:(Sop.Point_group "selected") ~recursive:false
           ~delete_target_attribute:true ~keep_unused_points:true
           ~original_point_attribute:"origpt" ~owner:Attribute.Point
           ~target_attribute:"target" in
  let parameters = Node.parameters graph in
  check (Node.operation graph = "rewire_vertices"
      && Node.cook_mode graph = Node.Duplicate_input 0
      && contains parameters "owner=point"
      && contains parameters "selection=point:selected"
      && contains parameters "delete_target_attribute=true"
      && contains parameters "keep_unused_points=true"
      && contains parameters "original_point_attribute=origpt")
    "Rewire Vertices SOP cache identity omits controls";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:96_000_000
      |> get in
  let first = cook session 1 graph and before = Session.stats session in
  let repeated = cook session 4 graph and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Rewire Vertices SOP missed its static cache";
  Session.close session;
  let cook_fresh domains =
    let session = Session.create ~max_entries:8 ~max_payload_bytes:96_000_000
        |> get in
    let output = cook session domains graph in
    Session.close session;
    output in
  let one = cook_fresh 1 and four = cook_fresh 4 in
  check (vertex_points one = vertex_points four
      && int_attribute "origpt" one = int_attribute "origpt" four)
    "Rewire Vertices SOP differs across domain counts";
  check (Geometry.find_attribute ~owner:Attribute.Point "target" one = None)
    "Rewire Vertices SOP did not delete its target field";
  let missing_group = Sop.snapshot (source 12)
      |> Sop.rewire_vertices ~selection:(Sop.Point_group "missing")
           ~owner:Attribute.Point ~target_attribute:"target" in
  let missing_attribute = Sop.snapshot (source 12)
      |> Sop.rewire_vertices ~owner:Attribute.Point
           ~target_attribute:"missing" in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:8_000_000
      |> get in
  (match Session.cook session ~context:(context 1) missing_group with
   | Error error -> check (error.code = "missing_group")
       "Rewire Vertices SOP missing-group diagnostic"
   | Ok _ -> fail "Rewire Vertices SOP accepted a missing group");
  (match Session.cook session ~context:(context 1) missing_attribute with
   | Error error -> check (error.code = "invalid_rewire_vertices")
       "Rewire Vertices SOP missing-attribute diagnostic"
   | Ok _ -> fail "Rewire Vertices SOP accepted a missing target field");
  Session.close session;
  print_endline "rewire vertices SOP tests passed"
