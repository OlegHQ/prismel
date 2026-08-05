open Prismel
open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error _ -> fail "unexpected error"
let context domains = Context.create ~domains ~grain:97 ~seed:81L () |> get

let contains text pattern =
  let rec search offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || search (offset + 1)) in
  pattern = "" || search 0

let source () =
  let geometry = Ops.grid ~columns:240 ~rows:160 ~size:12. ()
      |> function Ok value -> value | Error error -> fail (Error.to_string error) in
  let width = 241 and count = Geometry.point_count geometry in
  let seed = Group.init ~grain:97 ~owner:Group.Point ~name:"soft_seed" count
      (fun point -> point = (80 * width) + 120) in
  Geometry.with_group seed geometry |> Result.get_ok

let cook domains graph =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:160_000_000 |> get in
  let output = match Session.cook session ~context:(context domains) graph with
    | Ok value -> value.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session;
  output

let same_float_array left right =
  Array.length left = Array.length right
  && let same = ref true in
     for index = 0 to Array.length left - 1 do
       if Int64.bits_of_float left.(index) <> Int64.bits_of_float right.(index)
       then same := false
     done;
     !same

let same_output left right =
  let left_p = Packed.Float3.Private.view (Geometry.positions left)
  and right_p = Packed.Float3.Private.view (Geometry.positions right) in
  let weight geometry = match Geometry.find_attribute ~owner:Attribute.Point
      "soft_weight" geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float values -> values | _ -> fail "wrong weight storage")
    | None -> fail "missing weight" in
  same_float_array left_p.x right_p.x && same_float_array left_p.y right_p.y
  && same_float_array left_p.z right_p.z
  && same_float_array (weight left) (weight right)

let () =
  let graph = Sop.snapshot (source ())
      |> Sop.soft_transform_trs ~metric:Pdk.Ops.Soft_edge
           ~falloff:Pdk.Ops.Soft_quadratic ~radius:3.5
           ~falloff_attribute:"soft_weight"
           ~translate:(Vec3.create 0. 1.2 0.)
           ~rotate:(Vec3.create 0. 0.25 0.)
           ~selection:(Sop.Point_group "soft_seed") in
  let parameters = Node.parameters graph in
  check (contains parameters "metric=edge" && contains parameters "falloff=quadratic"
      && contains parameters "selection=point:soft_seed"
      && contains parameters "falloff_attribute=soft_weight")
    "Soft Transform cache identity";
  let one = cook 1 graph and four = cook 4 graph in
  check (same_output one four) "Soft Transform SOP one/four-domain exactness";
  let missing = Sop.snapshot (source ())
      |> Sop.soft_transform_trs ~radius:2. ~translate:Vec3.unit_y
           ~selection:(Sop.Point_group "missing") in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:80_000_000 |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "missing_group")
       "Soft Transform missing-group diagnostic"
   | Ok _ -> fail "Soft Transform accepted missing group");
  Session.close session;
  print_endline "soft transform SOP tests passed"
