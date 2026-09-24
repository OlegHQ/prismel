open Prismel
open Procedural

let fail message = prerr_endline ("test_motion_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message

let cook node =
  let context = Context.create ~domains:4 ~grain:1 () |> get in
  let session = Session.create ~max_entries:32 ~max_payload_bytes:16_000_000
      |> get in
  let output = match Session.cook session ~context node with
    | Ok value -> value
    | Error error -> fail error.Diagnostic.message in
  Session.close session;
  output.Session.geometry

let float3 name geometry =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point name geometry with
  | Some attribute ->
      (match Pdk.Attribute.Private.storage attribute with
       | Pdk.Attribute.Float3 values -> Pdk.Packed.Float3.Private.view values
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let () =
  let previous = Sop.points [|(0.,0.,0.); (1.,1.,1.)|]
  and current = Sop.points [|(1.,2.,3.); (3.,5.,7.)|] in
  let graph = current
      |> Sop.rest_position Pdk.Motion.Store_rest
      |> Sop.point_velocity ~previous ~dt:0.5
           ~add_velocity:(Vec3.create 1. 0. (-1.)) in
  let output = cook graph in
  let rest = float3 "rest" output and velocity = float3 "v" output in
  if rest.x <> [|1.;3.|] || rest.y <> [|2.;5.|] || rest.z <> [|3.;7.|]
  then fail "Rest Position SOP output";
  if velocity.x <> [|3.;5.|] || velocity.y <> [|4.;8.|]
     || velocity.z <> [|5.;11.|]
  then fail "Point Velocity SOP output";
  let invalid = Sop.point_velocity ~group:"missing" ~previous current in
  let context = Context.create () |> get
  and session = Session.create ~max_entries:8 ~max_payload_bytes:1_000_000
      |> get in
  (match Session.cook session ~context invalid with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "Point Velocity SOP accepted a missing group");
  Session.close session;
  print_endline "test_motion_sop: ok"
