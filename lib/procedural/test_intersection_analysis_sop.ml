open Rays
open Procedural
open Rdk_test_support

let context domains = Context.create ~domains ~grain:31 ~seed:73L () |> get

let cook session domains graph =
  match Session.cook session ~context:(context domains) graph with
  | Ok output -> (Result.get_ok (Procedural.Payload.geometry output.Session.payload))
  | Error error -> fail (Diagnostic.error_to_string error)

let graph () =
  let source = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~counts:Rdk.Plane_generators.Grid_point_counts
      ~connectivity:Rdk.Plane_generators.Grid_alternating_triangles
      ~columns:64 ~rows:48 ~size:12. () in
  let collision = (let migration_matrix = Mat4.rotation_x (Float.pi /. 2.) in
Sop.transform ~mode:Sop.Transform_matrix
  ~m11:(Mat4.get migration_matrix ~row:1 ~column:1)
  ~m12:(Mat4.get migration_matrix ~row:1 ~column:2)
  ~m21:(Mat4.get migration_matrix ~row:2 ~column:1)
  ~m22:(Mat4.get migration_matrix ~row:2 ~column:2) source) in
  (Sop.intersection_analysis ~label:("intersection-points") ~tolerance:(1e-9) ~include_coplanar:(false) (source) (Some (collision)))

let self_graph () =
  let source = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~counts:Rdk.Plane_generators.Grid_point_counts
      ~connectivity:Rdk.Plane_generators.Grid_alternating_triangles
      ~columns:48 ~rows:36 ~size:10. () in
  let collision = (let migration_matrix = Mat4.rotation_x (Float.pi /. 2.) in
Sop.transform ~mode:Sop.Transform_matrix
  ~m11:(Mat4.get migration_matrix ~row:1 ~column:1)
  ~m12:(Mat4.get migration_matrix ~row:1 ~column:2)
  ~m21:(Mat4.get migration_matrix ~row:2 ~column:1)
  ~m22:(Mat4.get migration_matrix ~row:2 ~column:2) source) in
  Sop.merge [source; collision]
  |> (fun intersection_source -> Sop.intersection_analysis ~label:("self-intersection-points") ~include_coplanar:(false) intersection_source None)

let curve_graph () =
  let source = Sop.polyline [|-1.,0.,0.; 1.,0.,0.|]
  and collision = Sop.polyline [|0.,-1.,0.; 0.,1.,0.|] in
  (Sop.intersection_analysis ~label:("curve-intersection-points") (source) (Some (collision)))

let int_rows name geometry =
  match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point name geometry with
  | Some attribute ->
      (match Rdk.Attribute.Private.storage attribute with
       | Rdk.Attribute.Int_array rows -> Rdk.Packed.Int_array.Private.view rows
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let float_rows name geometry =
  match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point name geometry with
  | Some attribute ->
      (match Rdk.Attribute.Private.storage attribute with
       | Rdk.Attribute.Float_array rows -> Rdk.Packed.Float_array.Private.view rows
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let signature geometry =
  let positions = Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions geometry)
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
      && contains (Node.parameters graph) "collision_group="
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
  check (Rdk.Geometry.point_count one > 0 && signature one = signature four)
    "Intersection Analysis SOP AxB one/four-domain drift";
  let self = self_graph () in
  check (List.length (Node.inputs self) = 1
      && contains (Node.parameters self) "collision_group=")
    "Intersection Analysis SOP AxA graph role";
  let one = fresh self 1 and four = fresh self 4 in
  check (Rdk.Geometry.point_count one > 0 && signature one = signature four)
    "Intersection Analysis SOP AxA one/four-domain drift";
  let curves = curve_graph () in
  let one = fresh curves 1 and four = fresh curves 4 in
  check (Rdk.Geometry.point_count one = 1 && signature one = signature four
      && (float_rows "sourceprimuv" one).values
        = [|0.5;0.;0.; 0.5;0.;0.|])
    "Intersection Analysis SOP curve one/four-domain drift"

let test_diagnostics_and_constructor_validation () =
  let source = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~connectivity:Rdk.Plane_generators.Grid_alternating_triangles
      ~columns:4 ~rows:4 ~size:2. ()
  and collision = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~connectivity:Rdk.Plane_generators.Grid_alternating_triangles
      ~columns:4 ~rows:4 ~size:2. () in
  let missing = (Sop.intersection_analysis ~source_group:("missing") (source) (Some (collision))) in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:8_000_000
      |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.Diagnostic.code = "missing_group")
       "Intersection Analysis SOP missing-source-group diagnostic"
   | Ok _ -> fail "Intersection Analysis SOP accepted a missing source group");
  Session.close session;
  let invalid thunk = try ignore (thunk ()); false with Invalid_argument _ -> true in
  check (invalid (fun () -> (Sop.intersection_analysis ~input_attribute:("same") ~primitive_attribute:("same") (source) None)))
    "Intersection Analysis SOP accepted conflicting output attributes";
  let curves = curve_graph () in
  let disabled_input = Node.apply_parameters curves
      ["input_attribute", Parameter.Text_value ""] |> get |> fst
      |> fun graph -> fresh graph 1 in
  check (Rdk.Geometry.point_count disabled_input = 1
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "sourceinput" disabled_input = None
      && (int_rows "sourceprim" disabled_input).values = [|0;0|])
    "Intersection Analysis SOP blank input name did not disable its output";
  let self = self_graph () in
  let ignored_group = Node.apply_parameters self
      ["collision_group", Parameter.Text_value "faces"] |> get |> fst in
  let expected = fresh self 1 and actual = fresh ignored_group 1 in
  check (Rdk.Geometry.point_count expected > 0 && equal_geometry actual expected
      && signature actual = signature expected)
    "Intersection Analysis SOP did not ignore its disconnected collision group";
  let no_attributes = (Sop.intersection_analysis ~input_attribute:("") ~primitive_attribute:("") ~primitive_uvw_attribute:("") ~point_attribute:("") (source) (Some (collision))) in
  check (Node.operation no_attributes = "intersection_analysis")
    "Intersection Analysis SOP rejected point-only output";
  let point_only = Node.apply_parameters curves
      (List.map (fun name -> name, Parameter.Text_value "")
        ["input_attribute"; "primitive_attribute"; "primitive_uvw_attribute"; "point_attribute"])
      |> get |> fst |> fun graph -> fresh graph 1 in
  check (Rdk.Geometry.point_count point_only = 1
      && List.for_all (fun name -> Rdk.Geometry.find_attribute
          ~owner:Rdk.Attribute.Point name point_only = None)
        ["sourceinput"; "sourceprim"; "sourceprimuv"; "sourcepoint"])
    "Intersection Analysis SOP blank output names did not produce point-only geometry"

let run () =
  test_identity_cache_and_parallel ();
  test_diagnostics_and_constructor_validation ();
  print_endline "intersection analysis SOP tests passed"
