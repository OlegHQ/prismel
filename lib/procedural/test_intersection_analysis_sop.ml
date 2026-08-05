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

let context domains = Context.create ~domains ~grain:31 ~seed:73L () |> get

let cook session domains graph =
  match Session.cook session ~context:(context domains) graph with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let graph () =
  let source = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:64 ~rows:48 ~size:12. () in
  let collision = Sop.transform (Mat4.rotation_x (Float.pi /. 2.)) source in
  Sop.intersection_analysis ~label:"intersection-points" ~collision
    ~tolerance:1e-9 ~include_coplanar:false source

let self_graph () =
  let source = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:48 ~rows:36 ~size:10. () in
  let collision = Sop.transform (Mat4.rotation_x (Float.pi /. 2.)) source in
  Sop.merge [source; collision]
  |> Sop.intersection_analysis ~label:"self-intersection-points"
       ~include_coplanar:false

let curve_graph () =
  let source = Sop.polyline [|-1.,0.,0.; 1.,0.,0.|]
  and collision = Sop.polyline [|0.,-1.,0.; 0.,1.,0.|] in
  Sop.intersection_analysis ~label:"curve-intersection-points" ~collision source

let int_rows name geometry =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point name geometry with
  | Some attribute ->
      (match Pdk.Attribute.Private.storage attribute with
       | Pdk.Attribute.Int_array rows -> Pdk.Packed.Int_array.Private.view rows
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let float_rows name geometry =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point name geometry with
  | Some attribute ->
      (match Pdk.Attribute.Private.storage attribute with
       | Pdk.Attribute.Float_array rows -> Pdk.Packed.Float_array.Private.view rows
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let signature geometry =
  let positions = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry)
  and inputs = int_rows "sourceinput" geometry
  and primitives = int_rows "sourceprim" geometry
  and uvw = float_rows "sourceprimuv" geometry
  and points = int_rows "sourcepoint" geometry in
  positions.x, positions.y, positions.z,
  inputs.offsets, inputs.values, primitives.values,
  uvw.offsets, uvw.values, points.values

let fresh graph domains =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:128_000_000
      |> get in
  let geometry = cook session domains graph in
  Session.close session;
  geometry

let test_identity_cache_and_parallel () =
  let graph = graph () in
  check (Node.operation graph = "intersection_analysis"
      && Node.cook_mode graph = Node.Generic
      && List.length (Node.inputs graph) = 2
      && contains (Node.parameters graph) "collision_input=true"
      && contains (Node.parameters graph) "include_coplanar=false"
      && contains (Node.parameters graph) "input_attribute=sourceinput"
      && contains (Node.parameters graph) "primitive_uvw_attribute=sourceprimuv")
    "Intersection Analysis SOP cache identity omits behavior controls";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:128_000_000
      |> get in
  let first = cook session 1 graph and before = Session.stats session in
  let repeated = cook session 4 graph and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Intersection Analysis SOP missed its static cook cache";
  Session.close session;
  let one = fresh graph 1 and four = fresh graph 4 in
  check (Pdk.Geometry.point_count one > 0 && signature one = signature four)
    "Intersection Analysis SOP AxB one/four-domain drift";
  let self = self_graph () in
  check (List.length (Node.inputs self) = 1
      && contains (Node.parameters self) "collision_input=false")
    "Intersection Analysis SOP AxA graph role";
  let one = fresh self 1 and four = fresh self 4 in
  check (Pdk.Geometry.point_count one > 0 && signature one = signature four)
    "Intersection Analysis SOP AxA one/four-domain drift";
  let curves = curve_graph () in
  let one = fresh curves 1 and four = fresh curves 4 in
  check (Pdk.Geometry.point_count one = 1 && signature one = signature four
      && (float_rows "sourceprimuv" one).values
        = [|0.5;0.;0.; 0.5;0.;0.|])
    "Intersection Analysis SOP curve one/four-domain drift"

let test_diagnostics_and_constructor_validation () =
  let source = Sop.grid ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:4 ~rows:4 ~size:2. ()
  and collision = Sop.grid ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:4 ~rows:4 ~size:2. () in
  let missing = Sop.intersection_analysis ~source_group:"missing" ~collision source in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:8_000_000
      |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.Diagnostic.code = "missing_group")
       "Intersection Analysis SOP missing-source-group diagnostic"
   | Ok _ -> fail "Intersection Analysis SOP accepted a missing source group");
  Session.close session;
  let invalid thunk = try ignore (thunk ()); false with Invalid_argument _ -> true in
  check (invalid (fun () -> Sop.intersection_analysis
      ~input_attribute:(Some "same") ~primitive_attribute:(Some "same") source))
    "Intersection Analysis SOP accepted conflicting output attributes";
  check (invalid (fun () -> Sop.intersection_analysis
      ~input_attribute:(Some "") source))
    "Intersection Analysis SOP accepted an empty output name";
  check (invalid (fun () -> Sop.intersection_analysis
      ~collision_group:"faces" source))
    "Intersection Analysis SOP accepted collision group without collision input";
  let no_attributes = Sop.intersection_analysis ~collision
      ~input_attribute:None ~primitive_attribute:None
      ~primitive_uvw_attribute:None ~point_attribute:None source in
  check (Node.operation no_attributes = "intersection_analysis")
    "Intersection Analysis SOP rejected point-only output"

let () =
  test_identity_cache_and_parallel ();
  test_diagnostics_and_constructor_validation ();
  print_endline "intersection analysis SOP tests passed"
