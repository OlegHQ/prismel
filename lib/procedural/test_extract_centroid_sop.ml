open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec loop offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || loop (offset + 1)) in
  pattern = "" || loop 0

let source_geometry () =
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;0.;10.;14.;10.|] ~y:[|0.;0.;2.;0.;0.;2.|]
      ~z:(Array.make 6 0.) in
  let topology = Pdk.Topology.polygons_owned ~point_count:6
      ~vertex_points:[|0;1;2;3;4;5|] ~primitive_offsets:[|0;3;6|]
      |> Result.get_ok in
  let piece = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Primitive
      ~name:"piece" (Pdk.Attribute.Int [|9;12|]) |> Result.get_ok in
  Pdk.Geometry.create ~positions ~topology ~attributes:[piece] () |> Result.get_ok

let graph () = Sop.snapshot (source_geometry ())
    |> Sop.extract_centroid ~label:"centers"
      ~run_over:(Pdk.Ops.Centroid_pieces {
        owner=Pdk.Ops.Centroid_piece_primitives; attribute="piece"})
      ~method_:Pdk.Ops.Centroid_bounding_box
      ~piece_output_attribute:"island"

let cook session domains node =
  let context = Context.create ~domains ~grain:1 ~seed:9L () |> get in
  match Session.cook session ~context node with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let signature geometry =
  let p = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
  let piece = match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point
      "island" geometry with
    | Some attribute -> (match Pdk.Attribute.Private.storage attribute with
        | Pdk.Attribute.Int values -> values | _ -> fail "island storage")
    | None -> fail "island missing" in
  Array.copy p.x, Array.copy p.y, Array.copy p.z, Array.copy piece

let fresh domains node =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get in
  Fun.protect ~finally:(fun () -> Session.close session)
    (fun () -> cook session domains node)

let () =
  let node = graph () in
  check (Node.operation node = "extract_centroid"
      && Node.cook_mode node = Node.Generic
      && contains (Node.parameters node) "run_over=pieces:primitives:piece"
      && contains (Node.parameters node) "method=bounding_box"
      && contains (Node.parameters node) "piece_output_attribute=island")
    "Extract Centroid SOP identity omits a behavior parameter";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get in
  let first = cook session 1 node and before = Session.stats session in
  let repeated = cook session 4 node and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Extract Centroid SOP missed the immutable cache";
  Session.close session;
  let one = fresh 1 node and four = fresh 4 node in
  check (signature one = signature four) "Extract Centroid SOP domain drift";
  check (Pdk.Geometry.point_count one = 2) "Extract Centroid SOP cardinality";
  let invalid = try
      ignore (Sop.extract_centroid
        ~run_over:(Pdk.Ops.Centroid_pieces {
          owner=Pdk.Ops.Centroid_piece_points; attribute="P"})
        (Sop.points [|0.,0.,0.|])); false
    with Invalid_argument _ -> true in
  check invalid "Extract Centroid SOP accepted P as piece identity";
  print_endline "extract centroid SOP tests passed"
