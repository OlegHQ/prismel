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

let context domains = Context.create ~domains ~grain:1 ~seed:91L () |> get

let cook session domains graph =
  match Session.cook session ~context:(context domains) graph with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let graph () =
  let left = Sop.box ~size:(Vec3.create 2. 2. 2.)
      ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true ()
  and right = Sop.box ~size:(Vec3.create 2. 2. 2.)
      ~center:(Vec3.create 0.5 0.5 0.5)
      ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true () in
  Sop.boolean ~label:"exact-union" ~operation:Pdk.Boolean.Union
    ~detriangulation:Pdk.Boolean.Unchanged_polygons ~right left

let signature geometry =
  let positions = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry)
  and topology = Pdk.Topology.Private.view (Pdk.Geometry.topology geometry) in
  Array.copy positions.x, Array.copy positions.y, Array.copy positions.z,
  Array.copy topology.vertex_points, Array.copy topology.primitive_offsets,
  Bytes.copy topology.primitive_kinds

let fresh graph domains =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:64_000_000
      |> get in
  let geometry = cook session domains graph in
  Session.close session;
  geometry

let test_identity_cache_and_parallel () =
  let graph = graph () in
  check (Node.operation graph = "boolean"
      && Node.cook_mode graph = Node.Generic
      && List.length (Node.inputs graph) = 2
      && contains (Node.parameters graph) "operation=union"
      && contains (Node.parameters graph) "left_treatment=solid"
      && contains (Node.parameters graph) "right_treatment=solid"
      && contains (Node.parameters graph)
           "detriangulation=unchanged_polygons"
      && contains (Node.parameters graph) "point_conflict=promote_to_vertex")
    "Boolean SOP cache identity omits behavior controls";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:64_000_000
      |> get in
  let first = cook session 1 graph and before = Session.stats session in
  let repeated = cook session 4 graph and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Boolean SOP missed its static cook cache";
  Session.close session;
  let one = fresh graph 1 and four = fresh graph 4 in
  check (signature one = signature four)
    "Boolean SOP differs between one and four domains";
  check (Pdk.Geometry.primitive_count one > 0)
    "Boolean SOP produced an empty overlapping-box union"

let test_surface_policy_and_diagnostic () =
  let left = Sop.box ~size:(Vec3.create 2. 2. 2.)
      ~connectivity:Pdk.Ops.Box_triangles ~consolidate_points:true () in
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|-2.;2.;-2.;2.|] ~y:[|0.;0.;0.;0.|] ~z:[|-0.5;-0.5;0.5;0.5|] in
  let topology = Pdk.Topology.polygons_owned ~point_count:4
      ~vertex_points:[|0;1;2;1;3;2|] ~primitive_offsets:[|0;3;6|] |> get in
  let sheet = Pdk.Geometry.create ~positions ~topology () |> get |> Sop.snapshot in
  let graph = Sop.boolean ~operation:Pdk.Boolean.Difference
      ~right_treatment:Pdk.Boolean.Surface ~right:sheet left in
  let output = fresh graph 1 in
  check (Pdk.Geometry.primitive_count output > 12)
    "Boolean SOP lost solid-minus-surface cut walls";
  let invalid = try
      ignore (Sop.boolean ~point_tolerance:(0. /. 0.) ~right:sheet left);
      false
    with Invalid_argument _ -> true in
  check invalid "Boolean SOP accepted a non-finite point tolerance"

let test_shatter_identity () =
  let left = Sop.box ~size:(Vec3.create 2. 2. 2.)
      ~connectivity:Pdk.Ops.Box_triangles ~consolidate_points:true ()
  and right = Sop.box ~size:(Vec3.create 2. 2. 2.)
      ~center:(Vec3.create 0.5 0.5 0.5)
      ~connectivity:Pdk.Ops.Box_triangles ~consolidate_points:true () in
  let graph = Sop.boolean ~operation:Pdk.Boolean.Shatter
      ~tiny_seam_threshold:1e-9 ~cleanup_max_batches:6
      ~strict_cleanup:false
      ~left_piece_group:(Some "left_piece")
      ~overlap_piece_group:(Some "overlap_piece")
      ~right_piece_group:(Some "right_piece") ~right left in
  check (contains (Node.parameters graph) "operation=shatter"
      && contains (Node.parameters graph) "left_piece_group=left_piece"
      && contains (Node.parameters graph) "overlap_piece_group=overlap_piece"
      && contains (Node.parameters graph) "right_piece_group=right_piece"
      && contains (Node.parameters graph) "cleanup_max_batches=6"
      && contains (Node.parameters graph) "strict_cleanup=false")
    "Boolean SOP shatter naming is absent from cache identity";
  let output = fresh graph 1 in
  List.iter (fun name -> check
      (Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name output <> None)
      "Boolean SOP shatter lost a named piece group")
    ["left_piece"; "overlap_piece"; "right_piece"];
  let invalid = try
      ignore (Sop.boolean ~operation:Pdk.Boolean.Shatter
        ~left_piece_group:(Some "same") ~right_piece_group:(Some "same")
        ~right left);
      false
    with Invalid_argument _ -> true in
  check invalid "Boolean SOP accepted duplicate shatter group names"

let test_seam_node () =
  let left = Sop.box ~size:(Vec3.create 2. 2. 2.)
      ~connectivity:Pdk.Ops.Box_triangles ~consolidate_points:true ()
  and right = Sop.box ~size:(Vec3.create 2. 2. 2.)
      ~center:(Vec3.create 0.5 0.5 0.5)
      ~connectivity:Pdk.Ops.Box_triangles ~consolidate_points:true () in
  let graph = Sop.boolean_seam ~between_group:(Some "cut_curves")
      ~left_self_group:None ~right_self_group:None ~right left in
  check (Node.operation graph = "boolean_seam"
      && Node.cook_mode graph = Node.Generic
      && List.length (Node.inputs graph) = 2
      && contains (Node.parameters graph) "output=curves"
      && contains (Node.parameters graph) "between_group=cut_curves")
    "Boolean Seam SOP cache identity omits output policy";
  let one = fresh graph 1 and four = fresh graph 4 in
  check (signature one = signature four)
    "Boolean Seam SOP differs between one and four domains";
  let group = Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive
      "cut_curves" one |> Option.get in
  check (Pdk.Group.cardinality group > 0)
    "Boolean Seam SOP lost between-input curves"

let () =
  test_identity_cache_and_parallel ();
  test_surface_policy_and_diagnostic ();
  test_shatter_identity ();
  test_seam_node ();
  print_endline "boolean SOP tests passed"
