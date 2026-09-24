open Prismel
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

let context domains = Context.create ~domains ~grain:37 ~seed:73L () |> get

let source () =
  let geometry = Ops.grid ~columns:200 ~rows:120 ~size:10. ()
      |> function Ok value -> value | Error error -> fail (Error.to_string error) in
  let points = Geometry.point_count geometry in
  let selected = Group.init ~grain:37 ~owner:Group.Point ~name:"checker" points
      (fun point -> point mod 3 = 0) in
  Geometry.with_group selected geometry |> Result.get_ok

let cook domains graph =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:128_000_000 |> get in
  let output = match Session.cook session ~context:(context domains) graph with
    | Ok value -> value.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session;
  output

let same_positions left right =
  let left = Packed.Float3.Private.view (Geometry.positions left)
  and right = Packed.Float3.Private.view (Geometry.positions right) in
  let same values other =
    Array.length values = Array.length other
    && let result = ref true in
       for index = 0 to Array.length values - 1 do
         if Int64.bits_of_float values.(index) <> Int64.bits_of_float other.(index)
         then result := false
       done;
       !result in
  same left.x right.x && same left.y right.y && same left.z right.z

let () =
  let graph = Sop.snapshot (source ())
      |> Sop.transform_trs ~order:Ops.Transform_str
           ~rotation_order:Ops.Transform_yzx
           ~translate:(Vec3.create 1. 2. 3.)
           ~rotate:(Vec3.create 0.2 (-0.3) 0.4)
           ~scale:(Vec3.create 1.2 0.7 1.1)
           ~shear:(Vec3.create 0.1 (-0.2) 0.3)
           ~pivot:(Vec3.create 0.5 0.2 (-0.1))
           ~selection:(Sop.Point_group "checker") in
  check (contains (Node.parameters graph) "selection=point:checker"
      && contains (Node.parameters graph) "preserve_normal_length=false"
      && contains (Node.parameters graph) "recompute_normals=false")
    "Transform graph omitted cache parameters";
  let one = cook 1 graph and four = cook 4 graph in
  check (same_positions one four) "Transform SOP one/four-domain exactness";
  let moved = Packed.Float3.Private.view (Geometry.positions one)
  and original = Packed.Float3.Private.view (Geometry.positions (source ())) in
  check (Int64.bits_of_float moved.x.(1) = Int64.bits_of_float original.x.(1)
      && Int64.bits_of_float moved.y.(1) = Int64.bits_of_float original.y.(1)
      && Int64.bits_of_float moved.z.(1) = Int64.bits_of_float original.z.(1))
    "Transform SOP moved an unselected point";
  let missing = Sop.snapshot (source ())
      |> Sop.transform_trs ~translate:Vec3.unit_x
           ~selection:(Sop.Point_group "missing") in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:64_000_000 |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "missing_group")
       "Transform SOP missing-group diagnostic"
   | Ok _ -> fail "Transform SOP accepted missing group");
  Session.close session;
  print_endline "transform SOP tests passed"
