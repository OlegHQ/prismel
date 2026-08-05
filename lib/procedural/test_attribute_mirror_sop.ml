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
  let half = count / 2 in
  let geometry = Ops.points (Array.init count (fun point ->
      if point < half then (-. float_of_int (half - point), 0., 0.)
      else (float_of_int (point - half + 1), 0., 0.))) in
  let map = Attribute.create_owned ~owner:Attribute.Point ~name:"map"
      (Attribute.Int (Array.init count (fun point ->
        if point < half then -1 else count - point - 1))) |> Result.get_ok
  and value = Attribute.create_owned ~owner:Attribute.Point ~name:"value"
      (Attribute.Float4 (Packed.Float4.of_owned
        ~x:(Array.init count (fun point -> float_of_int (point mod 251)))
        ~y:(Array.init count (fun point -> float_of_int (point mod 127)))
        ~z:(Array.init count (fun point -> float_of_int (point mod 67)))
        ~w:(Array.make count 1.) |> Result.get_ok)) |> Result.get_ok
  and destination = Group.init ~grain:257 ~owner:Group.Point ~name:"destination"
      count (fun point -> point >= half) in
  geometry |> Geometry.with_attribute map |> Result.get_ok
  |> Geometry.with_attribute value |> Result.get_ok
  |> Geometry.with_group destination |> Result.get_ok

let context domains = Context.create ~domains ~grain:257 ~seed:991L () |> get

let cook session domains graph =
  match Session.cook session ~context:(context domains) graph with
  | Ok value -> value.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let color geometry =
  match Geometry.find_attribute ~owner:Attribute.Point "value" geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail "mirrored value changed storage")
  | None -> fail "mirrored value is missing"

let mapping geometry =
  match Geometry.find_attribute ~owner:Attribute.Point "pair" geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail "mapping output changed storage")
  | None -> fail "mapping output is missing"

let make_graph geometry =
  Sop.snapshot geometry
  |> Sop.attribute_mirror ~label:"mirror-values"
       ~owner:Pdk.Ops.Mirror_point_attributes
       ~method_:(Sop.Attribute_mirror_mapping {
         mapping_attribute = "map"; destination_group = "destination" })
       ~attributes:"value" ~output_mapping:"pair"
       ~source_group:"mirror_source" ~destination_group:"mirror_destination"

let () =
  let graph = make_graph (source 100_000) in
  check (Node.operation graph = "attribute_mirror"
      && Node.cook_mode graph = Node.Duplicate_input 0
      && contains (Node.parameters graph) "owner=point"
      && contains (Node.parameters graph) "mapping:map:destination"
      && contains (Node.parameters graph) "attributes=\"value\""
      && contains (Node.parameters graph) "output_mapping=pair")
    "Attribute Mirror SOP cache identity omits controls";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:96_000_000
      |> get in
  let first = cook session 1 graph and before = Session.stats session in
  let repeated = cook session 4 graph and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Attribute Mirror SOP missed its static cook cache";
  Session.close session;
  let cook_fresh domains =
    let session = Session.create ~max_entries:8 ~max_payload_bytes:96_000_000
        |> get in
    let output = cook session domains graph in
    Session.close session;
    output in
  let one = cook_fresh 1 and four = cook_fresh 4 in
  let one_color = color one and four_color = color four in
  check (one_color = four_color && mapping one = mapping four)
    "Attribute Mirror SOP differs across domain counts";
  check (Geometry.point_count one = 100_000
      && Geometry.topology one == Geometry.topology four)
    "Attribute Mirror SOP changed cardinality or topology";
  let missing = Sop.snapshot (source 10)
      |> Sop.attribute_mirror ~owner:Pdk.Ops.Mirror_point_attributes
           ~method_:(Sop.Attribute_mirror_mapping {
             mapping_attribute = "map"; destination_group = "missing" }) in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:8_000_000
      |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "missing_group")
       "Attribute Mirror SOP missing-group diagnostic"
   | Ok _ -> fail "Attribute Mirror SOP accepted a missing group");
  Session.close session;
  check (try ignore (Sop.snapshot (source 10)
      |> Sop.attribute_mirror ~owner:Pdk.Ops.Mirror_point_attributes
           ~method_:(Sop.Attribute_mirror_mapping {
             mapping_attribute = ""; destination_group = "destination" })); false
    with Invalid_argument _ -> true)
    "Attribute Mirror SOP accepted an empty mapping attribute";
  print_endline "attribute mirror SOP tests passed"
