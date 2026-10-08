open Rays
open Rdk
open Procedural
open Rdk_test_support

let get = function Ok value -> value | Error _ -> fail "unexpected error"
let context domains = Context.create ~domains ~grain:97 ~seed:89L () |> get

let source () =
  let geometry = Rdk.Plane_generators.grid ~columns:220 ~rows:140 ~size:12. () |> function
    | Ok value -> Transform_ops.transform (Mat4.translation (Vec3.create 0. 1. 0.)) value
    | Error error -> fail (Error.to_string error) in
  let affected = Group.init ~grain:97 ~owner:Group.Point
      ~name:"distance_affected" (Geometry.point_count geometry)
      (fun point -> point mod 5 <> 0) in
  Geometry.with_group affected geometry |> Result.get_ok

let reference () =
  let geometry = Rdk.Uv_sphere.run ~rings:48 ~segments:72 ~radius:4. () |> function
    | Ok value -> value | Error error -> fail (Error.to_string error) in
  let primitives = Group.init ~grain:97 ~owner:Group.Primitive
      ~name:"reference_surface" (Geometry.primitive_count geometry) (fun _ -> true) in
  Geometry.with_group primitives geometry |> Result.get_ok

let cook domains graph =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:160_000_000 |> get in
  let output = match Session.cook session ~context:(context domains) graph with
    | Ok value -> (Result.get_ok (Procedural.Payload.geometry value.payload))
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

let run () =
  let graph = Sop.snapshot (source ())
      |> (fun source -> Sop.distance_from_geometry ~affected_group:"distance_affected" ~reference_group:"reference_surface"
           ~reference_kind:Rdk.Transform_ops.Distance_reference_primitives ~falloff:Rdk.Transform_ops.Soft_cubic
           ~radius_mode:Sop.Radius_fixed ~radius:3.5 ~distance_attribute:"surface_distance" ~mask_attribute:"mask"
           source (Sop.snapshot (reference ()))) in
  let parameters = Node.parameters graph in
  check (contains parameters "affected_owner=point;affected_group=distance_affected"
      && contains parameters "reference_owner=primitive;reference_group=reference_surface"
      && contains parameters "reference_kind=primitives"
      && contains parameters "falloff=cubic"
      && contains parameters "distance_attribute=surface_distance"
      && contains parameters "mask_attribute=mask")
    "Distance From Geometry cache identity";
  let one = cook 1 graph and four = cook 4 graph in
  check (same_float_array (float_attribute "surface_distance" one)
      (float_attribute "surface_distance" four)
      && same_float_array (float_attribute "mask" one)
           (float_attribute "mask" four))
    "Distance From Geometry SOP one/four-domain exactness";
  let missing = Sop.snapshot (source ())
      |> (fun source -> Sop.distance_from_geometry ~reference_group:"missing" source (Sop.snapshot (reference ()))) in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:80_000_000 |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "missing_group")
       "Distance From Geometry missing-reference diagnostic"
   | Ok _ -> fail "Distance From Geometry accepted missing reference group");
  Session.close session;
  print_endline "distance from geometry SOP tests passed"
