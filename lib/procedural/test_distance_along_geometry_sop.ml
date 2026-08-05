open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error _ -> fail "unexpected error"
let context domains = Context.create ~domains ~grain:97 ~seed:83L () |> get

let contains text pattern =
  let rec search offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || search (offset + 1)) in
  pattern = "" || search 0

let source () =
  let geometry = Ops.grid ~columns:240 ~rows:160 ~size:12. ()
      |> function Ok value -> value | Error error -> fail (Error.to_string error) in
  let width = 241 and count = Geometry.point_count geometry in
  let start = Group.init ~grain:97 ~owner:Group.Point ~name:"distance_start" count
      (fun point -> point = (80 * width) + 120) in
  let affected = Group.init ~grain:97 ~owner:Group.Point
      ~name:"distance_affected" count (fun point -> point mod 5 <> 0) in
  Geometry.with_group start geometry |> Result.get_ok
  |> Geometry.with_group affected |> Result.get_ok

let cook domains graph =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:160_000_000 |> get in
  let output = match Session.cook session ~context:(context domains) graph with
    | Ok value -> value.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session;
  output

let float_attribute name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let same_float_array left right =
  Array.length left = Array.length right
  && let same = ref true in
     for index = 0 to Array.length left - 1 do
       if Int64.bits_of_float left.(index) <> Int64.bits_of_float right.(index)
       then same := false
     done;
     !same

let () =
  let graph = Sop.snapshot (source ())
      |> Sop.distance_along_geometry
           ~start:(Sop.Point_group "distance_start")
           ~affected:(Sop.Point_group "distance_affected")
           ~falloff:Pdk.Ops.Soft_cubic
           ~radius:(Pdk.Ops.Distance_fixed 3.5)
           ~distance_attribute:(Some "edge_distance") ~mask_attribute:"mask" in
  let parameters = Node.parameters graph in
  check (contains parameters "start=point:distance_start"
      && contains parameters "affected=point:distance_affected"
      && contains parameters "falloff=cubic"
      && contains parameters "radius=fixed:"
      && contains parameters "distance_attribute=edge_distance"
      && contains parameters "mask_attribute=mask")
    "Distance Along Geometry cache identity";
  let one = cook 1 graph and four = cook 4 graph in
  check (same_float_array (float_attribute "edge_distance" one)
      (float_attribute "edge_distance" four)
      && same_float_array (float_attribute "mask" one)
           (float_attribute "mask" four))
    "Distance Along Geometry SOP one/four-domain exactness";
  let missing = Sop.snapshot (source ())
      |> Sop.distance_along_geometry ~start:(Sop.Point_group "missing") in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:80_000_000 |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "missing_group")
       "Distance Along Geometry missing-start diagnostic"
   | Ok _ -> fail "Distance Along Geometry accepted missing start group");
  Session.close session;
  print_endline "distance along geometry SOP tests passed"
