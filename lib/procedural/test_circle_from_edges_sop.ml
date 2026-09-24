open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec loop offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || loop (offset + 1)) in
  pattern = "" || loop 0

let loop_geometry count vertices_per_loop =
  let point_count = count * vertices_per_loop in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for component = 0 to count - 1 do
    let cx = float_of_int (component mod 200) *. 4.
    and cy = float_of_int (component / 200) *. 4. in
    for local = 0 to vertices_per_loop - 1 do
      let point = (component * vertices_per_loop) + local
      and angle = 2. *. Float.pi *. float_of_int local
          /. float_of_int vertices_per_loop in
      let radius = 1. +. (0.12 *. cos (3. *. angle)) in
      x.(point) <- cx +. (radius *. cos angle);
      y.(point) <- cy +. (radius *. sin angle);
      z.(point) <- 0.04 *. sin (2. *. angle)
    done
  done;
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (count + 1)
        (fun primitive -> primitive * vertices_per_loop))
      ~primitive_kinds:(Array.make count Pdk.Topology.Closed_polyline)
      |> Result.get_ok in
  let geometry = Pdk.Geometry.create
      ~positions:(Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z)
      ~topology () |> Result.get_ok in
  let index = Pdk.Topology_index.create topology in
  let edges = Pdk.Edge_group.init ~grain:127 ~topology ~index
      ~name:"loops" (Fun.const true) in
  Pdk.Geometry.with_edge_group edges geometry |> Result.get_ok

let cook session domains node =
  let context = Context.create ~domains ~grain:257 ~seed:17L () |> get in
  match Session.cook session ~context node with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let fresh domains node =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:80_000_000
      |> get in
  Fun.protect ~finally:(fun () -> Session.close session)
    (fun () -> cook session domains node)

let signature geometry =
  let p = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
  let group = Pdk.Geometry.find_edge_group "fitted" geometry |> Option.get in
  Array.copy p.x, Array.copy p.y, Array.copy p.z,
  Array.init (Pdk.Edge_group.length group) (fun edge ->
    Pdk.Edge_group.mem edge group)

let () =
  let source = Sop.snapshot (loop_geometry 2_000 16) in
  let graph = source |> Sop.circle_from_edges ~label:"fit-loops"
      ~group:"loops" ~radius:1.5 ~scale:(Vec3.create 1. 0.75 1.)
      ~output_group:"fitted" in
  check (Node.operation graph = "circle_from_edges" && Node.version graph = 1
      && Node.cook_mode graph = Node.Duplicate_input 0
      && contains (Node.parameters graph) "group=loops"
      && contains (Node.parameters graph) "radius=some:"
      && contains (Node.parameters graph) "scale="
      && contains (Node.parameters graph) "output_group=fitted")
    "Circle from Edges SOP identity omits behavior parameters";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:80_000_000
      |> get in
  let first = cook session 1 graph and before = Session.stats session in
  let repeated = cook session 4 graph and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Circle from Edges SOP missed the immutable cache";
  Session.close session;
  let one = fresh 1 graph and four = fresh 4 graph in
  check (signature one = signature four)
    "Circle from Edges SOP differs across domain counts";
  check (Pdk.Geometry.point_count one = 32_000
      && (Pdk.Geometry.find_edge_group "fitted" one |> Option.get
          |> Pdk.Edge_group.cardinality) = 32_000)
    "Circle from Edges SOP output cardinality";

  let missing = Sop.snapshot (loop_geometry 1 8)
      |> Sop.circle_from_edges ~group:"missing" in
  let session = Session.create ~max_entries:2 ~max_payload_bytes:1_000_000
      |> get in
  let context = Context.create ~domains:1 () |> get in
  (match Session.cook session ~context missing with
   | Error error -> check (error.code = "missing_group")
       "Circle from Edges SOP missing-group diagnostic"
   | Ok _ -> fail "Circle from Edges SOP accepted a missing group");
  Session.close session;
  check (try ignore (Sop.circle_from_edges ~group:" " source); false
    with Invalid_argument _ -> true)
    "Circle from Edges SOP accepted an empty group";
  check (try ignore (Sop.circle_from_edges ~radius:0. source); false
    with Invalid_argument _ -> true)
    "Circle from Edges SOP accepted a zero radius";
  check (try ignore (Sop.circle_from_edges
      ~scale:(Vec3.create 1. nan 1.) source); false
    with Invalid_argument _ -> true)
    "Circle from Edges SOP accepted non-finite scale";
  check (try ignore (Sop.circle_from_edges ~output_group:" " source); false
    with Invalid_argument _ -> true)
    "Circle from Edges SOP accepted an empty output group";
  print_endline "circle from edges SOP tests passed"
