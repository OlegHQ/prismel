open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error _ -> fail "unexpected error"
let context domains = Context.create ~domains ~grain:257 ~seed:101L () |> get

let contains text pattern =
  let rec search offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || search (offset + 1)) in
  pattern = "" || search 0

let source () =
  let values = Array.init 60_001 (fun point ->
      sin (float_of_int point *. 0.003), 0., 0.) in
  let geometry = Ops.points values in
  let ids = Attribute.create_owned ~owner:Attribute.Point ~name:"id"
      (Attribute.Int (Array.init (Geometry.point_count geometry) Fun.id))
      |> Result.get_ok in
  Geometry.with_attribute ids geometry |> Result.get_ok

let cook domains graph =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:160_000_000 |> get in
  let output = match Session.cook session ~context:(context domains) graph with
    | Ok value -> value.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session;
  output

let int_attribute name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let same_int_array left right =
  Array.length left = Array.length right
  && let same = ref true in
     for index = 0 to Array.length left - 1 do
       if left.(index) <> right.(index) then same := false
     done;
     !same

let () =
  let graph = Sop.snapshot (source ())
      |> Sop.sort ~owner:Pdk.Ops.Points ~key:(Pdk.Ops.Random 73421L)
      |> Sop.sort ~owner:Pdk.Ops.Points ~key:Pdk.Ops.X
           ~output_indices:"rank" in
  let parameters = Node.parameters graph in
  let input_parameters = match Node.inputs graph with
    | [input] -> Node.parameters input
    | _ -> fail "extended Sort SOP input graph shape" in
  check (contains parameters "key=x" && contains parameters "output_indices=rank"
      && contains input_parameters "random:73421")
    "extended Sort SOP cache identity";
  let one = cook 1 graph and four = cook 4 graph in
  check (same_int_array (int_attribute "id" one) (int_attribute "id" four)
      && same_int_array (int_attribute "rank" one)
           (int_attribute "rank" four))
    "extended Sort SOP one/four-domain exactness";
  let missing = Sop.snapshot (source ())
      |> Sop.sort ~owner:Pdk.Ops.Points
           ~key:(Pdk.Ops.Index_attribute "missing") in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:80_000_000 |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "invalid_sort")
       "extended Sort SOP missing-index diagnostic"
   | Ok _ -> fail "extended Sort SOP accepted missing index");
  Session.close session;
  print_endline "extended Sort SOP tests passed"
