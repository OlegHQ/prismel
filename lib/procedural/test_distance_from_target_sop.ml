open Prismel
open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error _ -> fail "unexpected error"
let context domains = Context.create ~domains ~grain:97 ~seed:97L () |> get

let contains text pattern =
  let rec search offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || search (offset + 1)) in
  pattern = "" || search 0

let source () =
  let geometry = Ops.grid ~columns:260 ~rows:160 ~size:12. () |> function
    | Ok value -> Ops.transform (Mat4.translation (Vec3.create 0. 1. 0.)) value
    | Error error -> fail (Error.to_string error) in
  let affected = Group.init ~grain:97 ~owner:Group.Point
      ~name:"distance_affected" (Geometry.point_count geometry)
      (fun point -> point mod 5 <> 0) in
  Geometry.with_group affected geometry |> Result.get_ok

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
      |> Sop.distance_from_target
           ~affected:(Sop.Point_group "distance_affected")
           ~projection:Pdk.Ops.Distance_target_planar
           ~origin:(Vec3.create 0.5 (-0.25) 1.)
           ~direction:(Vec3.create 1. 2. (-1.))
           ~metric:Pdk.Ops.Distance_target_signed
           ~falloff:Pdk.Ops.Soft_quadratic
           ~radius:(Pdk.Ops.Distance_fixed 4.)
           ~distance_attribute:(Some "target_distance") ~mask_attribute:"mask" in
  let parameters = Node.parameters graph in
  check (contains parameters "affected=point:distance_affected"
      && contains parameters "projection=planar"
      && contains parameters "metric=signed"
      && contains parameters "falloff=quadratic"
      && contains parameters "distance_attribute=target_distance"
      && contains parameters "mask_attribute=mask")
    "Distance From Target cache identity";
  let one = cook 1 graph and four = cook 4 graph in
  check (same_float_array (float_attribute "target_distance" one)
      (float_attribute "target_distance" four)
      && same_float_array (float_attribute "mask" one)
           (float_attribute "mask" four))
    "Distance From Target SOP one/four-domain exactness";
  let missing = Sop.snapshot (source ())
      |> Sop.distance_from_target ~affected:(Sop.Point_group "missing") in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:80_000_000 |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "missing_group")
       "Distance From Target missing-group diagnostic"
   | Ok _ -> fail "Distance From Target accepted missing affected group");
  Session.close session;
  print_endline "distance from target SOP tests passed"
