open Procedural
open Rdk_test_support

let source () =
  let geometry = Rdk.Uv_sphere.run
      ~connectivity:Rdk.Uv_sphere.Sphere_alternating_triangles
      ~segments:160 ~rings:80 ~radius:2. () |> Result.get_ok in
  let selected = Rdk.Group.init ~grain:257 ~owner:Rdk.Group.Point
      ~name:"upper" (Rdk.Geometry.point_count geometry) (fun point ->
        let positions = Rdk.Packed.Float3.Private.view
            (Rdk.Geometry.positions geometry) in
        positions.y.(point) >= 0.) in
  Rdk.Geometry.with_group selected geometry |> Result.get_ok

let cook session domains node =
  let context = Context.create ~domains ~grain:257 () |> get in
  match Session.cook session ~context node with
  | Ok output -> (Result.get_ok (Procedural.Payload.geometry output.Session.payload))
  | Error error -> fail (Diagnostic.error_to_string error)

let fresh domains node =
  let session = Session.create ~max_entries:4 ~max_payload_bytes:64_000_000
      |> get in
  Fun.protect ~finally:(fun () -> Session.close session)
    (fun () -> cook session domains node)

let values name geometry =
  match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point name geometry with
  | Some attribute ->
      (match Rdk.Attribute.Private.storage attribute with
       | Rdk.Attribute.Float values -> values
       | _ -> fail (name ^ " output storage"))
  | None -> fail (name ^ " output missing")

let run () =
  let geometry = source () in
  let node = Sop.snapshot geometry
      |> Sop.measure_curvature ~label:"surface-curvature" ~point_group:"upper"
          ~boundary:Rdk.Curvature.Curvature_boundary_one_sided
          ~smoothing_iterations:2 ~smoothing_strength:0.25 ~mean:"mean" ~gaussian:"gaussian"
          ~minimum:"minimum" ~maximum:"maximum" ~curvedness:"curvedness" ~shape_index:"shape" in
  check (Node.operation node = "measure_curvature" && Node.version node = 1
      && Node.cook_mode node = Node.Duplicate_input 0
      && contains (Node.parameters node) "point_group=upper"
      && contains (Node.parameters node) "boundary=one_sided"
      && contains (Node.parameters node) "smoothing_iterations=2"
      && contains (Node.parameters node) "mean=mean"
      && contains (Node.parameters node) "shape_index=shape")
    "Measure Curvature SOP identity omits behavior parameters";
  let session = Session.create ~max_entries:4 ~max_payload_bytes:64_000_000
      |> get in
  let first = cook session 1 node and before = Session.stats session in
  let repeated = cook session 4 node and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Measure Curvature SOP missed immutable cache";
  Session.close session;
  let one = fresh 1 node and four = fresh 4 node in
  List.iter (fun name ->
    check (values name one = values name four)
      (name ^ " SOP output differs across domain counts"))
    ["mean";"gaussian";"minimum";"maximum";"curvedness";"shape"];
  check (Rdk.Geometry.topology one == Rdk.Geometry.topology geometry
      && Rdk.Geometry.positions one == Rdk.Geometry.positions geometry)
    "Measure Curvature SOP did not share source geometry";
  let missing = Sop.snapshot geometry
      |> Sop.measure_curvature ~point_group:"missing" in
  let session = Session.create ~max_entries:2 ~max_payload_bytes:1_000_000
      |> get in
  let context = Context.create ~domains:1 () |> get in
  (match Session.cook session ~context missing with
   | Error error -> check (error.code = "missing_group")
       "Measure Curvature missing-group diagnostic"
   | Ok _ -> fail "Measure Curvature accepted a missing point group");
  let curve = Rdk.Line_geometry.polyline ~closed:true
      [|0.,0.,0.;1.,0.,0.;0.,1.,0.|] |> Result.get_ok |> Sop.snapshot
      |> Sop.measure_curvature in
  (match Session.cook session ~context curve with
   | Error error -> check (error.code = "invalid_curvature")
       "Measure Curvature malformed-surface diagnostic"
   | Ok _ -> fail "Measure Curvature accepted curve topology");
  Session.close session;
  check (try ignore (Sop.measure_curvature ~point_group:" "
      (Sop.snapshot geometry)); false with Invalid_argument _ -> true)
    "Measure Curvature accepted an empty point group";
  check (try ignore (Sop.measure_curvature ~smoothing_strength:nan
      (Sop.snapshot geometry)); false with Invalid_argument _ -> true)
    "Measure Curvature accepted non-finite smoothing";
  check (try ignore (Sop.measure_curvature ~mean:"mean" ~gaussian:"mean"
      ~minimum:"minimum" ~maximum:"maximum" ~curvedness:"curvedness" ~shape_index:"shape" (Sop.snapshot geometry)); false
    with Invalid_argument _ -> true)
    "Measure Curvature accepted duplicate output names";
  print_endline "measure curvature SOP tests passed"
