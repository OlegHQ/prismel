open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec loop offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || loop (offset + 1)) in
  pattern = "" || loop 0

let colored_source triangles =
  let point_count = triangles * 3 in
  let x = Array.init point_count (fun point -> float_of_int (point / 3))
  and y = Array.init point_count (fun point ->
      match point mod 3 with 0 -> 0. | 1 -> 1. | _ -> 0.)
  and z = Array.make point_count 0. in
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (triangles + 1) (fun primitive -> primitive * 3))
      ~primitive_kinds:(Array.make triangles Pdk.Topology.Polygon)
      |> Result.get_ok in
  let geometry = Pdk.Geometry.create
      ~positions:(Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z)
      ~topology () |> Result.get_ok in
  let selected = Pdk.Group.init ~grain:127 ~owner:Pdk.Group.Primitive
      ~name:"selected" triangles (fun primitive -> primitive land 1 = 0) in
  Pdk.Geometry.with_group selected geometry |> Result.get_ok

let cook session domains node =
  let context = Context.create ~domains ~grain:257 ~seed:19L () |> get in
  match Session.cook session ~context node with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let fresh domains node =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:100_000_000
      |> get in
  Fun.protect ~finally:(fun () -> Session.close session)
    (fun () -> cook session domains node)

let signature geometry =
  let colors = match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point
      "schedule" geometry with
    | Some attribute ->
        (match Pdk.Attribute.Private.storage attribute with
         | Pdk.Attribute.Int values -> Array.copy values
         | _ -> fail "Graph Color SOP output storage")
    | None -> fail "Graph Color SOP missing output" in
  let topology = Pdk.Topology.Private.view (Pdk.Geometry.topology geometry) in
  colors, Array.copy topology.vertex_points,
  Array.copy topology.primitive_offsets, Bytes.copy topology.primitive_kinds

let () =
  let source = Sop.snapshot (colored_source 20_000) in
  let graph = source |> Sop.graph_color ~label:"schedule-points"
      ~selection:(Sop.Primitive_group "selected")
      ~connectivity:Pdk.Ops.Graph_points_by_primitive
      ~color_attribute:"schedule" in
  check (Node.operation graph = "graph_color" && Node.version graph = 1
      && Node.cook_mode graph = Node.Duplicate_input 0
      && contains (Node.parameters graph) "selection=primitive:selected"
      && contains (Node.parameters graph) "connectivity=points_by_primitive"
      && contains (Node.parameters graph) "color_attribute=schedule"
      && contains (Node.parameters graph) "sort_output=false")
    "Graph Color SOP identity omits behavior parameters";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:100_000_000
      |> get in
  let first = cook session 1 graph and before = Session.stats session in
  let repeated = cook session 4 graph and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Graph Color SOP missed the immutable cache";
  Session.close session;
  let one = fresh 1 graph and four = fresh 4 graph in
  check (signature one = signature four)
    "Graph Color SOP differs across domain counts";
  check (Pdk.Geometry.point_count one = 60_000)
    "Graph Color SOP scale cardinality";

  let missing = Sop.snapshot (colored_source 1)
      |> Sop.graph_color ~selection:(Sop.Point_group "missing") in
  let session = Session.create ~max_entries:2 ~max_payload_bytes:1_000_000
      |> get in
  let context = Context.create ~domains:1 () |> get in
  (match Session.cook session ~context missing with
   | Error error -> check (error.code = "missing_group")
       "Graph Color SOP missing-group diagnostic"
   | Ok _ -> fail "Graph Color SOP accepted a missing group");
  Session.close session;
  check (try ignore (Sop.graph_color ~color_attribute:"P" source); false
    with Invalid_argument _ -> true)
    "Graph Color SOP accepted P as output";
  check (try ignore (Sop.graph_color
      ~selection:(Sop.Point_group " ") source); false
    with Invalid_argument _ -> true)
    "Graph Color SOP accepted an empty selection group";
  check (try ignore (Sop.graph_color
      ~worksets:{Pdk.Ops.begin_attribute="begin";length_attribute="length"}
      source); false with Invalid_argument _ -> true)
    "Graph Color SOP accepted unsorted worksets";
  print_endline "graph color SOP tests passed"
