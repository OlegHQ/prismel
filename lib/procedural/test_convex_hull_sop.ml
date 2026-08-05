open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec loop offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || loop (offset + 1)) in
  pattern = "" || loop 0

let source () = Sop.points [|
  -1.,-1.,-1.; 1.,-1.,-1.; 1.,1.,-1.; -1.,1.,-1.;
  -1.,-1.,1.; 1.,-1.,1.; 1.,1.,1.; -1.,1.,1.;
  0.,0.,0.; 0.2,-0.3,0.4
|]

let graph () = source ()
    |> Sop.convex_hull ~label:"proxy" ~source_point_attribute:"source"
      ~hull_group:"hull"

let signature geometry =
  let positions = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry)
  and topology = Pdk.Topology.Private.view (Pdk.Geometry.topology geometry) in
  Array.copy positions.x, Array.copy positions.y, Array.copy positions.z,
  Array.copy topology.vertex_points, Array.copy topology.primitive_offsets,
  Bytes.copy topology.primitive_kinds

let cook session domains node =
  let context = Context.create ~domains ~grain:2 ~seed:7L () |> get in
  match Session.cook session ~context node with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let fresh domains node =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get in
  Fun.protect ~finally:(fun () -> Session.close session)
    (fun () -> cook session domains node)

let () =
  let node = graph () in
  check (Node.operation node = "convex_hull"
      && Node.cook_mode node = Node.Generic
      && contains (Node.parameters node) "selection=all"
      && contains (Node.parameters node) "preserve_point_payload=true"
      && contains (Node.parameters node) "source_point_attribute=source"
      && contains (Node.parameters node) "hull_group=hull")
    "Convex Hull SOP identity omits a behavior parameter";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get in
  let first = cook session 1 node and before = Session.stats session in
  let repeated = cook session 4 node and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Convex Hull SOP missed the immutable session cache";
  Session.close session;
  let one = fresh 1 node and four = fresh 4 node in
  check (signature one = signature four)
    "Convex Hull SOP differs between one and four domains";
  check (Pdk.Geometry.point_count one = 8
      && Pdk.Geometry.primitive_count one = 12)
    "Convex Hull SOP cardinality";
  let selected = source ()
      |> Sop.group ~name:"bottom" (Select.point_indices [|0;1;2;3|])
      |> Sop.convex_hull ~selection:(Sop.Point_group "bottom") in
  let plane = fresh 1 selected in
  check (Pdk.Geometry.point_count plane = 4
      && Pdk.Geometry.primitive_count plane = 1)
    "Convex Hull SOP typed selection";
  let invalid = try
      ignore (Sop.convex_hull ~source_point_attribute:"P" (source ()));
      false
    with Invalid_argument _ -> true in
  check invalid "Convex Hull SOP accepted P as an ancestry field";
  print_endline "convex hull SOP tests passed"
