open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let attribute owner name storage =
  Pdk.Attribute.create_owned ~owner ~name storage |> Result.get_ok

let source_geometry () =
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;10.;14.|] ~y:(Array.make 4 0.) ~z:(Array.make 4 0.) in
  let topology = Pdk.Topology.create_owned ~point_count:4
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;2;4|]
      ~primitive_kinds:[|Pdk.Topology.Open_polyline;
        Pdk.Topology.Open_polyline|] |> Result.get_ok in
  let first = Pdk.Group.init ~owner:Pdk.Group.Primitive ~name:"first" 2
      (fun primitive -> primitive = 0) in
  Pdk.Geometry.create ~positions ~topology ~groups:[first] ~attributes:[
    attribute Pdk.Attribute.Point "distance"
      (Pdk.Attribute.Float [|-1.;1.;-1.;1.|]);
    attribute Pdk.Attribute.Point "weight"
      (Pdk.Attribute.Float [|0.;20.;100.;140.|]);
    attribute Pdk.Attribute.Primitive "cut"
      (Pdk.Attribute.Float [|0.;0.5|]);
    attribute Pdk.Attribute.Primitive "material"
      (Pdk.Attribute.Int [|7;9|])
  ] () |> Result.get_ok

let context ?(time = 0.) domains =
  Context.create ~time ~domains ~grain:1 ~seed:13L () |> get

let cook session context node =
  match Session.cook session ~context node with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let fresh context node =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get in
  Fun.protect ~finally:(fun () -> Session.close session)
    (fun () -> cook session context node)

let positions geometry =
  Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry)

let float_values name geometry =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point name geometry with
  | Some attribute -> (match Pdk.Attribute.Private.storage attribute with
      | Pdk.Attribute.Float values -> values
      | _ -> fail (name ^ " storage"))
  | None -> fail (name ^ " missing")

let int_values name geometry =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point name geometry with
  | Some attribute -> (match Pdk.Attribute.Private.storage attribute with
      | Pdk.Attribute.Int values -> values
      | _ -> fail (name ^ " storage"))
  | None -> fail (name ^ " missing")

let signature geometry =
  let p = positions geometry in
  Array.copy p.x, Array.copy p.y, Array.copy p.z,
  Array.copy (float_values "weight" geometry),
  Array.copy (int_values "material" geometry),
  Array.copy (float_values "u" geometry),
  Array.copy (int_values "cuts" geometry),
  Array.copy (int_values "curve" geometry)

let static_node () = Sop.snapshot (source_geometry ())
    |> Sop.extract_point_from_curve ~label:"cuts"
      ~cut:(Sop.Extract_point_primitive_attribute "cut")
      ~distance_attribute:"distance" ~point_attributes:"weight"
      ~copy_primitive_attributes:true ~primitive_attributes:"material"
      ~curve_u_attribute:"u" ~number_cuts_attribute:"cuts"
      ~curve_number_attribute:"curve"

let test_static_identity_cache_and_parallel () =
  let node = static_node () in
  check (Node.operation node = "extract_point_from_curve"
      && Node.cook_mode node = Node.Generic
      && Context.Dependencies.to_list (Node.dependencies node) = []
      && String.length (Node.parameters node) > 0)
    "static Extract Point from Curve identity/dependencies";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get in
  let first = cook session (context ~time:0. 1) node in
  let before = Session.stats session in
  let repeated = cook session (context ~time:0.75 4) node in
  let after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "static Extract Point from Curve missed immutable cache";
  Session.close session;
  let one = fresh (context 1) node and four = fresh (context 4) node in
  check (signature one = signature four)
    "Extract Point from Curve one/four-domain output differs";
  check (Pdk.Geometry.point_count one = 2) "static output cardinality";
  let p = positions one in
  check (p.x = [|1.;13.|] && float_values "weight" one = [|10.;130.|]
      && int_values "material" one = [|7;9|]
      && float_values "u" one = [|0.5;0.75|]
      && int_values "cuts" one = [|1;1|]
      && int_values "curve" one = [|0;1|])
    "static output payload"

let test_selection_and_current_time () =
  let selected = Sop.snapshot (source_geometry ())
      |> Sop.extract_point_from_curve ~group:"first"
        ~distance_attribute:"distance" in
  let output = fresh (context 1) selected in
  check (Pdk.Geometry.point_count output = 1 && (positions output).x = [|1.|])
    "primitive group restriction";
  let timed = Sop.snapshot (source_geometry ())
      |> Sop.extract_point_from_curve ~cut:Sop.Extract_point_current_time
        ~distance_attribute:"distance" in
  check (Context.Dependencies.mem Context.Dependencies.Time
      (Node.dependencies timed)) "current-time dependency missing";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get in
  let at_zero = cook session (context ~time:0. 1) timed in
  let at_half = cook session (context ~time:0.5 4) timed in
  check (at_zero != at_half && (positions at_zero).x = [|1.;12.|]
      && (positions at_half).x = [|1.5;13.|])
    "current-time recook/output";
  Session.close session

let test_errors () =
  let invalid work message =
    let rejected = try work (); false with Invalid_argument _ -> true in
    check rejected message in
  invalid (fun () -> ignore (Sop.extract_point_from_curve
      ~cut:(Sop.Extract_point_constant Float.nan)
      ~distance_attribute:"distance" (Sop.snapshot (source_geometry ()))))
    "non-finite constant accepted";
  invalid (fun () -> ignore (Sop.extract_point_from_curve
      ~distance_attribute:"P" (Sop.snapshot (source_geometry ()))))
    "canonical P accepted as distance";
  let missing = Sop.snapshot (source_geometry ())
      |> Sop.extract_point_from_curve ~group:"absent"
        ~distance_attribute:"distance" in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:4_000_000 |> get in
  let result = Session.cook session ~context:(context 1) missing in
  Session.close session;
  match result with
  | Error error -> check (error.Diagnostic.code = "missing_group")
      "missing group diagnostic code"
  | Ok _ -> fail "missing primitive group accepted"

let () =
  test_static_identity_cache_and_parallel ();
  test_selection_and_current_time ();
  test_errors ();
  print_endline "extract point from curve SOP tests passed"
