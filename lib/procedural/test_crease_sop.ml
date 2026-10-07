open Rdk
open Procedural
open Rdk_test_support

let get = function Ok value -> value | Error _ -> fail "unexpected error"
let context domains = Context.create ~domains ~grain:257 ~seed:211L () |> get

let source () =
  let geometry = Rdk.Plane_generators.grid ~connectivity:Rdk.Plane_generators.Grid_quads ~columns:260 ~rows:160
      ~size:12. () |> function
    | Ok value -> value
    | Error error -> fail (Error.to_string error) in
  let topology = Geometry.topology geometry in
  let index = Topology_index.create topology in
  let edges = Edge_group.init ~grain:257 ~topology ~index ~name:"crease_edges"
      (fun edge -> edge mod 7 = 0) in
  Geometry.with_edge_group edges geometry |> Result.get_ok

let cook session domains graph =
  match Session.cook session ~context:(context domains) graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let crease_values geometry =
  match Geometry.find_attribute ~owner:Attribute.Vertex "creaseweight" geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail "Crease SOP storage changed")
  | None -> fail "Crease SOP omitted creaseweight"

let color_values geometry =
  match Geometry.find_attribute ~owner:Attribute.Vertex "Cd" geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail "Crease SOP color storage changed")
  | None -> fail "Crease SOP omitted visualization color"

let run () =
  let graph = Sop.snapshot (source ())
      |> Sop.crease ~group:"crease_edges" ~operation:Crease.Crease_add ~weight:2.
           ~add_vertex_color:true in
  let parameters = Node.parameters graph in
  check (contains parameters "group=crease_edges"
      && contains parameters "operation=add"
      && contains parameters "add_vertex_color=true")
    "Crease SOP cache identity";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:180_000_000
      |> get in
  let one = cook session 1 graph in
  let stats_before = Session.stats session in
  let repeated = cook session 1 graph in
  let stats_after = Session.stats session in
  check (one == repeated && stats_after.hits > stats_before.hits)
    "Crease SOP stable graph missed its bounded-session cache";
  Session.close session;
  let cook_fresh graph domains =
    let session = Session.create ~max_entries:8 ~max_payload_bytes:180_000_000
        |> get in
    let output = cook session domains graph in
    Session.close session;
    output in
  let one = cook_fresh graph 1 and four = cook_fresh graph 4 in
  check (crease_values one = crease_values four)
    "Crease SOP one/four-domain weights differ";
  let one_color = color_values one and four_color = color_values four in
  check (one_color.x = four_color.x && one_color.y = four_color.y
      && one_color.z = four_color.z && one_color.w = four_color.w)
    "Crease SOP one/four-domain colors differ";
  let subdivided = graph |> (fun subdivision_source -> Sop.subdivide ~crease_weight_mode:Procedural.Sop.Kernel_auto ~face_varying_interpolation:(Rdk.Subdivide.Subdivide_fvar_all) ~boundary_interpolation:(Rdk.Subdivide.Subdivide_boundary_edge_only) ~remove_holes:(true) ~generate_resulting_creases:(true) ~hole_group:("") ~scheme:(Subdivide.Catmull_clark) subdivision_source None) in
  let one_subdivided = cook_fresh subdivided 1
  and four_subdivided = cook_fresh subdivided 4 in
  let one_mesh = Rdk_rays.Rays_mesh.to_mesh one_subdivided |> function
    | Ok value -> value | Error error -> fail (Error.to_string error)
  and four_mesh = Rdk_rays.Rays_mesh.to_mesh four_subdivided |> function
    | Ok value -> value | Error error -> fail (Error.to_string error) in
  check (Rays.Mesh.Private.packed_view one_mesh
      = Rays.Mesh.Private.packed_view four_mesh)
    "Crease/Subdivide SOP one/four-domain render mesh differs";
  let missing = Sop.snapshot (source ()) |> Sop.crease ~group:"missing" in
  check (match Sop.crease ~group:"crease_edges" ~operation:Crease.Crease_set
      ~weight:(-1.) (Sop.snapshot (source ())) with
    | _ -> false | exception Invalid_argument _ -> true)
    "Crease SOP refuses a negative weight at construction";
  let session = Session.create ~max_entries:4 ~max_payload_bytes:90_000_000
      |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "missing_group")
       "Crease SOP missing-group diagnostic"
   | Ok _ -> fail "Crease SOP accepted a missing edge group");
  Session.close session;
  check (match Sop.crease ~operation:Crease.Crease_delete ~weight:Float.nan
      (Sop.snapshot (source ())) with
    | _ -> false | exception Invalid_argument _ -> true)
    "Crease Delete refuses a non-finite weight at construction";
  print_endline "crease SOP tests passed"
