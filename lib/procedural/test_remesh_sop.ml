open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec loop offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || loop (offset + 1)) in
  pattern = "" || loop 0

let context domains = Context.create ~domains ~grain:31 ~seed:41L () |> get

let cook session domains graph =
  match Session.cook session ~context:(context domains) graph with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let graph () =
  Sop.grid ~counts:Pdk.Ops.Grid_point_counts
    ~connectivity:Pdk.Ops.Grid_alternating_triangles
    ~columns:28 ~rows:22 ~size:8. ()
  |> Sop.remesh ~label:"isotropic-remesh" ~target_length:0.28 ~iterations:1
       ~smoothing:0.35 ~project:true ~preserve_uv_seams:true
       ~output_hard_edges:"hard" ~output_mesh_size:"mesh_size"
       ~output_quality:"quality"

let signature geometry =
  let positions = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry)
  and topology = Pdk.Topology.Private.view (Pdk.Geometry.topology geometry) in
  let quality = match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
      "quality" geometry with
    | Some attribute ->
        (match Pdk.Attribute.Private.storage attribute with
         | Pdk.Attribute.Float values -> values
         | _ -> fail "Remesh SOP quality has wrong storage")
    | None -> fail "Remesh SOP quality is missing" in
  positions.x, positions.y, positions.z, topology.vertex_points,
  topology.primitive_offsets, topology.primitive_kinds, quality

let () =
  let graph = graph () in
  check (Node.operation graph = "remesh"
      && Node.cook_mode graph = Node.Duplicate_input 0
      && contains (Node.parameters graph) "target_length="
      && contains (Node.parameters graph) "iterations=1"
      && contains (Node.parameters graph) "smoothing="
      && contains (Node.parameters graph) "project=true"
      && contains (Node.parameters graph) "output_quality=quality")
    "Remesh SOP cache identity omits behavior controls";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:128_000_000
      |> get in
  let first = cook session 1 graph and before = Session.stats session in
  let repeated = cook session 4 graph and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Remesh SOP missed its static cook cache";
  Session.close session;
  let fresh domains =
    let session = Session.create ~max_entries:8 ~max_payload_bytes:128_000_000
        |> get in
    let output = cook session domains graph in
    Session.close session;
    output in
  let one = fresh 1 and four = fresh 4 in
  check (signature one = signature four)
    "Remesh SOP differs across one and four domains";
  let hard = Pdk.Geometry.find_edge_group "hard" one |> Option.get
  and index = Pdk.Topology_index.create (Pdk.Geometry.topology one) in
  check (Pdk.Edge_group.cardinality hard
      = Pdk.Topology_index.boundary_edge_count index)
    "Remesh SOP hard-edge diagnostic is incomplete";
  let missing = Sop.grid ~connectivity:Pdk.Ops.Grid_triangles
      ~columns:4 ~rows:4 ~size:1. ()
      |> Sop.remesh ~target_length:0.2 ~hard_edge_group:"missing" in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:8_000_000
      |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.Diagnostic.code = "missing_group")
       "Remesh SOP missing-group diagnostic"
   | Ok _ -> fail "Remesh SOP accepted a missing hard-edge group");
  Session.close session;
  check (try ignore (Sop.grid ~columns:2 ~rows:2 ~size:1. ()
      |> Sop.remesh ~target_length:0.2 ~output_quality:""); false
    with Invalid_argument _ -> true)
    "Remesh SOP accepted an empty output name";
  print_endline "remesh SOP tests passed"
