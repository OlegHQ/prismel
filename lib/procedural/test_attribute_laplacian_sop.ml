open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec loop offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || loop (offset + 1)) in
  pattern = "" || loop 0

let source () =
  let geometry = Pdk.Ops.uv_sphere
      ~connectivity:Pdk.Ops.Sphere_alternating_triangles
      ~segments:160 ~rings:80 ~radius:2. () |> Result.get_ok in
  let positions = Pdk.Packed.Float3.Private.view
      (Pdk.Geometry.positions geometry) in
  let selected = Pdk.Group.init ~grain:257 ~owner:Pdk.Group.Point
      ~name:"upper" (Pdk.Geometry.point_count geometry)
      (fun point -> positions.y.(point) >= 0.) in
  Pdk.Geometry.with_group selected geometry |> Result.get_ok

let cook session domains node =
  let context = Context.create ~domains ~grain:257 () |> get in
  match Session.cook session ~context node with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let fresh domains node =
  let session = Session.create ~max_entries:4 ~max_payload_bytes:64_000_000
      |> get in
  Fun.protect ~finally:(fun () -> Session.close session)
    (fun () -> cook session domains node)

let values geometry =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point "delta_p" geometry with
  | Some attribute ->
      (match Pdk.Attribute.Private.storage attribute with
       | Pdk.Attribute.Float3 values -> Pdk.Packed.Float3.Private.view values
       | _ -> fail "Attribute Laplacian output storage")
  | None -> fail "Attribute Laplacian output missing"

let () =
  let geometry = source () in
  let node = Sop.snapshot geometry
      |> Sop.attribute_laplacian ~label:"surface-laplacian"
          ~point_group:"upper" ~weighting:Pdk.Ops.Laplacian_positive_cotan
          ~normalize:false ~source:"P" ~output:"delta_p" in
  check (Node.operation node = "attribute_laplacian" && Node.version node = 1
      && Node.cook_mode node = Node.Duplicate_input 0
      && contains (Node.parameters node) "point_group=upper"
      && contains (Node.parameters node) "weighting=positive_cotan"
      && contains (Node.parameters node) "normalize=false"
      && contains (Node.parameters node) "source=P"
      && contains (Node.parameters node) "output=delta_p")
    "Attribute Laplacian SOP identity omits behavior parameters";
  let session = Session.create ~max_entries:4 ~max_payload_bytes:64_000_000
      |> get in
  let first = cook session 1 node and before = Session.stats session in
  let repeated = cook session 4 node and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Attribute Laplacian SOP missed immutable cache";
  Session.close session;
  let one = fresh 1 node and four = fresh 4 node in
  let one_values = values one and four_values = values four in
  check (one_values.x = four_values.x && one_values.y = four_values.y
      && one_values.z = four_values.z)
    "Attribute Laplacian SOP differs across domain counts";
  check (Pdk.Geometry.topology one == Pdk.Geometry.topology geometry
      && Pdk.Geometry.positions one == Pdk.Geometry.positions geometry)
    "Attribute Laplacian SOP did not share source geometry";
  let missing = Sop.snapshot geometry
      |> Sop.attribute_laplacian ~point_group:"missing" ~source:"P" in
  let session = Session.create ~max_entries:2 ~max_payload_bytes:1_000_000
      |> get in
  let context = Context.create ~domains:1 () |> get in
  (match Session.cook session ~context missing with
   | Error error -> check (error.code = "missing_group")
       "Attribute Laplacian missing-group diagnostic"
   | Ok _ -> fail "Attribute Laplacian accepted a missing point group");
  let curve = Pdk.Ops.polyline ~closed:true
      [|0.,0.,0.;1.,0.,0.;0.,1.,0.|] |> Result.get_ok |> Sop.snapshot
      |> Sop.attribute_laplacian ~source:"P" in
  (match Session.cook session ~context curve with
   | Error error -> check (error.code = "invalid_laplacian")
       "Attribute Laplacian malformed-surface diagnostic"
   | Ok _ -> fail "Attribute Laplacian accepted curve topology");
  Session.close session;
  check (try ignore (Sop.attribute_laplacian ~point_group:" " ~source:"P"
      (Sop.snapshot geometry)); false with Invalid_argument _ -> true)
    "Attribute Laplacian accepted an empty point group";
  check (try ignore (Sop.attribute_laplacian ~source:" "
      (Sop.snapshot geometry)); false with Invalid_argument _ -> true)
    "Attribute Laplacian accepted an empty source";
  check (try ignore (Sop.attribute_laplacian ~source:"P" ~output:"P"
      (Sop.snapshot geometry)); false with Invalid_argument _ -> true)
    "Attribute Laplacian accepted canonical P as output";
  print_endline "attribute Laplacian SOP tests passed"
