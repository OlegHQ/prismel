open Rays
open Procedural
open Rdk_test_support

let get_ok = function Ok value -> value | Error _ -> fail "unexpected error"
let edit_parameters graph ~node_id changes =
  Result.bind (Edit_graph.apply_parameters (Edit_graph.of_graph graph)
      ~node_id changes) (fun (document, effects) ->
    Result.map (fun graph -> graph, effects) (Edit_graph.compile document))
let cook_ok session context graph =
  match Session.cook session ~context graph with
  | Ok output -> output
  | Error error -> fail (Diagnostic.error_to_string error)

let context ?frame ?time ?seed ?domains ?grain ?cancel () =
  Context.create ?frame ?time ?seed ?domains ?grain ?cancel () |> get_ok

let session ?(entries = 64) ?(bytes = 64 * 1024 * 1024) () =
  Session.create ~max_entries:entries ~max_payload_bytes:bytes |> get_ok

let equal_positions left right =
  let left = Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions left)
  and right = Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions right) in
  left.x = right.x && left.y = right.y && left.z = right.z

let contains text pattern =
  let text_length = String.length text and pattern_length = String.length pattern in
  let rec search index =
    index + pattern_length <= text_length
    && (String.sub text index pattern_length = pattern || search (index + 1))
  in
  pattern_length = 0 || search 0

(* a failure bound, never a pace: a loaded machine only takes longer *)
let wait_until ?(seconds = 60.) operation =
  let deadline = Unix.gettimeofday () +. seconds in
  let rec loop () =
    match operation () with
    | Some value -> value
    | None when Unix.gettimeofday () < deadline ->
        Unix.sleepf 0.001;
        loop ()
    | None -> fail "timed out waiting for background procedural cook"
  in
  loop ()

type inspectable_parameters = {
  translate_x : float;
  display_gain : float;
}

type encoded_parameters = { rules : int list }

let encoded_rules = Parameter.encoded ~equal:( = )
    ~encode:(fun values -> String.concat "," (List.map string_of_int values))
    ~decode:(fun text ->
      let text = String.trim text in
      if text = "" then Ok []
      else
        String.split_on_char ',' text
        |> List.fold_left (fun result token -> Result.bind result (fun values ->
          match int_of_string_opt (String.trim token) with
          | Some value -> Ok (value :: values)
          | None -> Error (Printf.sprintf "invalid integer %S" token))) (Ok [])
        |> Result.map List.rev)

let encoded_schema = Parameter.schema ~name:"encoded_rules"
    ~default:{ rules = [1; 2] } [
  Parameter.field ~name:"rules" ~kind:encoded_rules ~default:[1; 2]
    ~get:(fun value -> value.rules)
    ~set:(fun rules _value -> { rules }) ();
]

let inspectable_default = { translate_x = 0.; display_gain = 1. }

let inspectable_schema = Parameter.schema ~name:"inspectable_transform"
    ~default:inspectable_default [
  Parameter.field ~name:"translate_x" ~label:"Translate X"
    ~folder:["Transform"] ~kind:(Parameter.floating ~min:(-2.) ~max:2. ())
    ~default:0. ~get:(fun value -> value.translate_x)
    ~set:(fun translate_x value -> { value with translate_x }) ();
  Parameter.field ~name:"display_gain" ~label:"Display gain"
    ~folder:["Viewport"] ~impact:Parameter.View
    ~kind:(Parameter.floating ~min:0. ~max:2. ()) ~default:1.
    ~get:(fun value -> value.display_gain)
    ~set:(fun display_gain value -> { value with display_gain }) ();
]

let rec inspectable_transform ~label input parameters =
  Sop.transform ~label
    (Mat4.translation (Vec3.create parameters.translate_x 0. 0.)) input
  |> Node.parameterize ~schema:inspectable_schema ~values:parameters
       ~rebuild:(fun ~label ~inputs parameters -> match inputs with
         | [input] -> inspectable_transform ~label input parameters
         | _ -> invalid_arg "inspectable_transform expects one input")

let test_node_owned_parameters_and_graph_edit () =
  let source = Sop.points [|0., 0., 0.|] in
  let editable = inspectable_transform ~label:"move" source inspectable_default in
  let graph = Sop.merge [Sop.null ~label:"left" editable;
                         Sop.null ~label:"right" editable] in
  let evaluator = session () in
  let original_infos = Session.inspect evaluator graph in
  check (Session.inspect evaluator graph == original_infos)
    "session graph inspection did not reuse retained metadata";
  let other = session () in
  check (Session.inspect other graph != original_infos)
    "graph inspection cache leaked across sessions";
  Session.close other;
  Gc.full_major();
  let inspect_before=Gc.allocated_bytes()in
  for _=1 to 10_000 do ignore(Session.inspect evaluator graph)done;
  let inspect_per_call=(Gc.allocated_bytes()-.inspect_before)/.10_000. in
  check (inspect_per_call<=40.)
    (Printf.sprintf"session graph inspection allocates %.1f bytes/call"
      inspect_per_call);
  check (List.length (Node.parameter_fields editable) = 2
      && Node.has_parameters editable)
    "node-owned parameter metadata was not exposed";
  let translated, effects = edit_parameters graph
      ~node_id:(Node.id editable)
      ["translate_x", Parameter.Float_value 1.5] |> get_ok in
  check (Session.inspect evaluator translated != original_infos)
    "rebuilt graph reused stale retained metadata";
  check (effects.cook && not effects.view && not effects.export)
    "graph edit lost cook impact";
  let edited = Option.get (Graph.find translated ~node_id:(Node.id editable)) in
  check (Node.id edited = Node.id editable
      && List.map (fun info -> info.Graph.id) (Session.inspect evaluator translated)
         = List.map (fun info -> info.Graph.id) original_infos)
    "graph edit did not preserve logical node identities";
  let merge_inputs = Node.inputs translated in
  let left_input = Node.inputs (List.nth merge_inputs 0) |> List.hd
  and right_input = Node.inputs (List.nth merge_inputs 1) |> List.hd in
  check (left_input == right_input && Node.id left_input = Node.id editable)
    "graph edit duplicated a shared subgraph";
  let current = context () in
  ignore (cook_ok evaluator current graph);
  let before_edit = Session.stats evaluator in
  let output = cook_ok evaluator current translated in
  let after_edit = Session.stats evaluator in
  let positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions output.geometry) in
  check (positions.x = [|1.5; 1.5|])
    "edited node did not rebuild its cook closure";
  check (after_edit.hits > before_edit.hits)
    "stable graph edit did not reuse an unaffected cached input";
  let view_only, view_effects = edit_parameters translated
      ~node_id:(Node.id editable)
      ["display_gain", Parameter.Float_value 1.75] |> get_ok in
  check (not view_effects.cook && view_effects.view && not view_effects.export)
    "view-only node edit requested a cook";
  let before_view = Session.stats evaluator in
  ignore (cook_ok evaluator current view_only);
  let after_view = Session.stats evaluator in
  check (after_view.cooks = before_view.cooks)
    "view-only metadata invalidated cooked geometry";
  let view_node = Option.get (Graph.find view_only ~node_id:(Node.id editable)) in
  let display = List.find (fun field -> field.Parameter.name = "display_gain")
      (Node.parameter_fields view_node) in
  check (display.current = Parameter.Float_value 1.75)
    "view-only node value was not retained for the inspector";
  Session.clear evaluator;
  check (Session.inspect evaluator graph != original_infos)
    "clearing a session retained graph inspection metadata";
  Session.close evaluator

let test_encoded_parameter () =
  let initial = { rules = [1; 2] } in
  let field = Parameter.view encoded_schema initial |> List.hd in
  check (field.kind = Parameter.Text_view
      && field.current = Parameter.Text_value "1,2")
    "encoded parameter did not expose its deterministic text form";
  let edited, effects = Parameter.apply_all encoded_schema initial
      ["rules", Parameter.Text_value "3, 5, 8"] |> get_ok in
  check (edited.rules = [3; 5; 8] && effects.cook)
    "encoded parameter did not decode an inspector edit";
  check (Parameter.key encoded_schema initial
      <> Parameter.key encoded_schema edited)
    "encoded parameter did not participate in cache identity";
  check (Result.is_error (Parameter.apply encoded_schema initial ~name:"rules"
      (Parameter.Text_value "3,nope")))
    "encoded parameter accepted an invalid structured edit"

let test_async_cook_latest_request () =
  let worker = Async_cook.create ~max_entries:4
      ~max_payload_bytes:4_000_000 |> get_ok in
  let slow = Sop.custom ~operation:"async_test_slow" ~version:1
      ~parameters:"delay=0.3" [Sop.points [|0., 0., 0.|]]
      (fun ~context geometries ->
        Unix.sleepf 0.3;
        if Context.cancelled context then Error "cancelled"
        else Ok geometries.(0)) in
  let prepare output = Ok (Rdk.Geometry.point_count output.Session.geometry) in
  let first = Async_cook.submit worker ~context:(context ~domains:2 ())
      ~node:slow ~prepare |> get_ok in
  ignore (wait_until (fun () -> match Async_cook.status worker with
    | Async_cook.Cooking _ -> Some ()
    | Idle -> None));
  let second = Async_cook.submit worker ~context:(context ~domains:2 ())
      ~node:(Sop.points [|0., 0., 0.; 1., 0., 0.; 2., 0., 0.|])
      ~prepare |> get_ok in
  let completion = wait_until (fun () -> Async_cook.poll worker) in
  check (first <> second && completion.request_id = second)
    "async cook published a stale request";
  (match completion.result with
   | Ok 3 -> ()
   | Ok _ -> fail "async cook latest request returned the wrong geometry"
   | Error error -> fail (Async_cook.error_to_string error));
  check (Async_cook.status worker = Idle)
    "async cook remained busy after publishing the latest result";
  Async_cook.close worker;
  Async_cook.close worker;
  check (Async_cook.is_closed worker) "async cook did not close idempotently"

let test_static_context_cache () =
  let graph =
    Sop.grid ~label:"terrain" ~columns:4 ~rows:3 ~size:5. ()
    |> Sop.transform ~label:"move" (Mat4.translation (Vec3.create 1. 2. 3.))
  in
  let evaluator = session () in
  let first = cook_ok evaluator (context ~frame:0L ~time:0. ~seed:1L
      ~domains:1 ~grain:1 ()) graph in
  let after_first = Session.stats evaluator in
  check (after_first.cooks = 2 && after_first.misses = 2)
    "static graph first cook statistics";
  let second = cook_ok evaluator (context ~frame:99L ~time:42. ~seed:999L
      ~domains:4 ~grain:32 ()) graph in
  let after_second = Session.stats evaluator in
  check (after_second.cooks = 2 && after_second.hits = 2)
    "static graph was invalidated by unrelated context facts";
  check (first.geometry == second.geometry) "static cache did not retain snapshot identity";
  Session.close evaluator

let test_grid_generator_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let graph = Sop.grid ~label:"oriented-grid"
      ~counts:Rdk.Plane_generators.Grid_point_counts
      ~connectivity:Rdk.Plane_generators.Grid_alternating_triangles
      ~orientation:Rdk.Plane_generators.Grid_xy ~center:(Vec3.create 2. 3. 4.)
      ~width:6. ~height:2. ~rotation:0.25 ~uv_attribute:"st"
      ~columns:5 ~rows:3 ~size:1. () in
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 15
      && Rdk.Geometry.vertex_count output.geometry = 48
      && Rdk.Geometry.primitive_count output.geometry = 16)
    "procedural Grid advanced cardinality";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "st"
      output.geometry <> None)
    "procedural Grid dropped normalized lattice coordinates";
  let rows_and_columns = Sop.grid
      ~counts:Rdk.Plane_generators.Grid_point_counts
      ~connectivity:Rdk.Plane_generators.Grid_rows_and_columns
      ~orientation:Rdk.Plane_generators.Grid_yz ~columns:4 ~rows:3 ~size:2. ()
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count rows_and_columns.geometry = 12
      && Rdk.Geometry.vertex_count rows_and_columns.geometry = 24
      && Rdk.Geometry.primitive_count rows_and_columns.geometry = 7)
    "procedural Grid row-and-column topology";
  let invalid = Sop.grid ~label:"bad-axes"
      ~orientation:(Rdk.Plane_generators.Grid_axes {
        horizontal = Vec3.unit_x; vertical = Vec3.unit_x })
      ~columns:2 ~rows:2 ~size:1. () in
  (match Session.cook evaluator ~context:current invalid with
   | Ok _ -> fail "procedural Grid accepted collinear custom axes"
   | Error error ->
       check (error.code = "invalid_parameter")
         "procedural Grid custom-axis diagnostic code";
       check (List.map (fun trace -> trace.Diagnostic.label) error.trace
              = ["bad-axes"])
         "procedural Grid custom-axis diagnostic trace");
  Session.close evaluator

let test_circle_generator_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let graph = Sop.circle ~label:"sliced-ellipse"
      ~arc:(Rdk.Plane_generators.Circle_sliced_arc {
        start_angle = -0.4; end_angle = 2.2 })
      ~orientation:Rdk.Plane_generators.Circle_xy ~reverse:true
      ~center:(Vec3.create 2. 3. 4.) ~radius_x:3. ~radius_y:1.
      ~rotation:0.25 ~uniform_scale:2. ~segments:8 ~radius:1. () in
  check (contains (Node.parameters graph) "arc=sliced")
    "procedural Circle cache identity omitted arc mode";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 10
      && Rdk.Geometry.vertex_count output.geometry = 10
      && Rdk.Geometry.primitive_count output.geometry = 1
      && Rdk.Topology.primitive_kind (Rdk.Geometry.topology output.geometry) 0
         = Rdk.Topology.Closed_polyline)
    "procedural sliced Circle topology";
  let open_arc = Sop.circle ~arc:(Rdk.Plane_generators.Circle_open_arc {
        start_angle = 0.; end_angle = Float.pi })
      ~orientation:Rdk.Plane_generators.Circle_yz ~segments:12 ~radius:2. ()
      |> cook_ok evaluator current in
  (match Rdk_rays.Rays_mesh.to_mesh open_arc.geometry with
   | Ok mesh -> check (Mesh.mode mesh = Mesh.Lines
         && Mesh.index_count mesh = 24)
       "procedural open Circle bridge"
   | Error error -> fail (Rdk.Error.to_string error));
  let invalid = Sop.circle ~label:"bad-circle-axes"
      ~orientation:(Rdk.Plane_generators.Circle_axes {
        horizontal = Vec3.unit_x; vertical = Vec3.unit_x })
      ~segments:8 ~radius:1. () in
  (match Session.cook evaluator ~context:current invalid with
   | Ok _ -> fail "procedural Circle accepted collinear custom axes"
   | Error error ->
       check (error.code = "invalid_parameter")
         "procedural Circle custom-axis diagnostic code";
       check (List.map (fun trace -> trace.Diagnostic.label) error.trace
              = ["bad-circle-axes"])
         "procedural Circle custom-axis diagnostic trace");
  Session.close evaluator

let test_box_generator_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let graph = Sop.box ~label:"divided-box" ~connectivity:Rdk.Box_generator.Box_quads
      ~consolidate_points:true ~normals:Rdk.Box_generator.Box_vertex_normals
      ~center:(Vec3.create 2. 3. 4.)
      ~rotation:(Vec3.create 0.2 0.3 0.4)
      ~rotation_order:Rdk.Box_generator.Box_yzx ~uniform_scale:1.5
      ~x_divisions:2 ~y_divisions:3 ~z_divisions:4
      ~uv_attribute:"uv" ~face_groups:"side"
      ~size:(Vec3.create 2. 3. 4.) () in
  check (contains (Node.parameters graph) "connectivity=quads"
      && contains (Node.parameters graph) "rotation_order=yzx")
    "procedural Box cache identity omitted advanced parameters";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 54
      && Rdk.Geometry.vertex_count output.geometry = 208
      && Rdk.Geometry.primitive_count output.geometry = 52
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "N"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "uv"
         output.geometry <> None
      && List.length (Rdk.Geometry.groups output.geometry) = 6)
    "procedural divided Box output contract";
  let lattice = Sop.box ~connectivity:Rdk.Box_generator.Box_lattice_points
      ~x_divisions:2 ~y_divisions:3 ~z_divisions:4
      ~size:(Vec3.create 2. 3. 4.) () |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count lattice.geometry = 60
      && Rdk.Geometry.vertex_count lattice.geometry = 0)
    "procedural Box volume lattice";
  let invalid = Sop.box ~label:"bad-box-divisions" ~x_divisions:0 () in
  (match Session.cook evaluator ~context:current invalid with
   | Ok _ -> fail "procedural Box accepted zero divisions"
   | Error error ->
       check (error.code = "invalid_parameter")
         "procedural Box division diagnostic code";
       check (List.map (fun trace -> trace.Diagnostic.label) error.trace
              = ["bad-box-divisions"])
         "procedural Box division diagnostic trace");
  Session.close evaluator

let test_uv_sphere_generator_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let graph = Sop.uv_sphere ~label:"advanced-sphere"
      ~connectivity:Rdk.Uv_sphere.Sphere_quads ~unique_points_per_pole:true
      ~triangular_poles:false ~normals:Rdk.Uv_sphere.Sphere_vertex_normals
      ~orientation:(Rdk.Uv_sphere.Sphere_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 2. 3. 4.) ~rotation:(Vec3.create 0.2 0.3 0.4)
      ~rotation_order:Rdk.Uv_sphere.Sphere_zxy ~uniform_scale:1.5
      ~radius_x:2. ~radius_y:1.5 ~radius_z:0.75 ~uv_attribute:"uv"
      ~segments:12 ~rings:6 ~radius:1. () in
  check (contains (Node.parameters graph) "connectivity=quads"
      && contains (Node.parameters graph) "unique_points_per_pole=true"
      && contains (Node.parameters graph) "rotation_order=zxy")
    "procedural UV Sphere cache identity omitted advanced parameters";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 84
      && Rdk.Geometry.vertex_count output.geometry = 288
      && Rdk.Geometry.primitive_count output.geometry = 72
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "N"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "uv"
         output.geometry <> None)
    "procedural advanced UV Sphere output contract";
  let points = Sop.uv_sphere ~connectivity:Rdk.Uv_sphere.Sphere_points
      ~unique_points_per_pole:true ~uv_attribute:"uv"
      ~segments:12 ~rings:6 ~radius:1. () |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count points.geometry = 84
      && Rdk.Geometry.vertex_count points.geometry = 0
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "uv"
         points.geometry <> None)
    "procedural UV Sphere point lattice";
  let invalid = Sop.uv_sphere ~label:"bad-sphere-axis"
      ~orientation:(Rdk.Uv_sphere.Sphere_axis Vec3.zero) ~radius:1. () in
  (match Session.cook evaluator ~context:current invalid with
   | Ok _ -> fail "procedural UV Sphere accepted a zero pole axis"
   | Error error ->
       check (error.code = "invalid_parameter")
         "procedural UV Sphere axis diagnostic code";
       check (List.map (fun trace -> trace.Diagnostic.label) error.trace
              = ["bad-sphere-axis"])
         "procedural UV Sphere axis diagnostic trace");
  Session.close evaluator

let test_torus_generator_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let graph = Sop.torus ~label:"capped-torus"
      ~connectivity:Rdk.Parametric_generators.Torus_alternating_triangles
      ~normals:Rdk.Parametric_generators.Torus_vertex_normals
      ~orientation:(Rdk.Parametric_generators.Torus_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 2. 3. 4.) ~rotation:(Vec3.create 0.2 0.3 0.4)
      ~rotation_order:Rdk.Parametric_generators.Torus_zxy ~uniform_scale:1.5
      ~u_start:0.2 ~u_end:2.4 ~v_start:(-.Float.pi /. 2.)
      ~v_end:(Float.pi /. 2.) ~u_wrap:false ~v_wrap:false
      ~u_end_caps:true ~v_end_cap:true ~uv_attribute:"uv"
      ~rows:8 ~columns:5 ~major_radius:3. ~minor_radius:1. () in
  check (contains (Node.parameters graph) "connectivity=alternating_triangles"
      && contains (Node.parameters graph) "rotation_order=zxy"
      && contains (Node.parameters graph) "u_end_caps=true"
      && contains (Node.parameters graph) "v_end_cap=true")
    "procedural Torus cache identity omitted advanced parameters";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 40
      && Rdk.Geometry.vertex_count output.geometry = 220
      && Rdk.Geometry.primitive_count output.geometry = 72
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "N"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "uv"
         output.geometry <> None)
    "procedural capped Torus output contract";
  let points = Sop.torus ~connectivity:Rdk.Parametric_generators.Torus_points
      ~uv_attribute:"uv" ~rows:8 ~columns:5
      ~major_radius:3. ~minor_radius:1. () |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count points.geometry = 40
      && Rdk.Geometry.vertex_count points.geometry = 0
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "uv"
         points.geometry <> None)
    "procedural Torus point lattice";
  let invalid = Sop.torus ~label:"bad-torus-axis"
      ~orientation:(Rdk.Parametric_generators.Torus_axis Vec3.zero)
      ~major_radius:2. ~minor_radius:1. () in
  (match Session.cook evaluator ~context:current invalid with
   | Ok _ -> fail "procedural Torus accepted a zero hole axis"
   | Error error ->
       check (error.code = "invalid_parameter")
         "procedural Torus axis diagnostic code";
       check (List.map (fun trace -> trace.Diagnostic.label) error.trace
              = ["bad-torus-axis"])
         "procedural Torus axis diagnostic trace");
  Session.close evaluator

let test_tube_generator_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let graph = Sop.tube ~label:"capped-cone"
      ~connectivity:Rdk.Parametric_generators.Tube_alternating_triangles ~end_caps:true
      ~consolidate_cap_points:false ~normals:Rdk.Parametric_generators.Tube_vertex_normals
      ~orientation:(Rdk.Parametric_generators.Tube_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 2. 3. 4.) ~rotation:(Vec3.create 0.2 0.3 0.4)
      ~rotation_order:Rdk.Parametric_generators.Tube_zxy ~radius_scale:1.5
      ~uv_attribute:"uv" ~cap_group:"caps" ~rows:8 ~columns:5
      ~top_radius:0. ~bottom_radius:3. ~height:4. () in
  check (contains (Node.parameters graph) "connectivity=alternating_triangles"
      && contains (Node.parameters graph) "consolidate_cap_points=false"
      && contains (Node.parameters graph) "rotation_order=zxy"
      && contains (Node.parameters graph) "cap_group=caps")
    "procedural Tube cache identity omitted advanced parameters";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 41
      && Rdk.Geometry.vertex_count output.geometry = 200
      && Rdk.Geometry.primitive_count output.geometry = 66
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "N"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "uv"
         output.geometry <> None
      && Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "caps"
         output.geometry <> None)
    "procedural capped Tube output contract";
  let points = Sop.tube ~connectivity:Rdk.Parametric_generators.Tube_points
      ~uv_attribute:"uv" ~rows:8 ~columns:5
      ~top_radius:0. ~bottom_radius:3. ~height:4. ()
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count points.geometry = 36
      && Rdk.Geometry.vertex_count points.geometry = 0
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "uv"
         points.geometry <> None)
    "procedural Tube point lattice";
  let invalid = Sop.tube ~label:"bad-tube-axis"
      ~orientation:(Rdk.Parametric_generators.Tube_axis Vec3.zero)
      ~top_radius:1. ~bottom_radius:1. ~height:2. () in
  (match Session.cook evaluator ~context:current invalid with
   | Ok _ -> fail "procedural Tube accepted a zero primary axis"
   | Error error ->
       check (error.code = "invalid_parameter")
         "procedural Tube axis diagnostic code";
       check (List.map (fun trace -> trace.Diagnostic.label) error.trace
              = ["bad-tube-axis"])
         "procedural Tube axis diagnostic trace");
  Session.close evaluator

let test_platonic_generator_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let graph = Sop.platonic ~label:"soccer"
      ~kind:Rdk.Parametric_generators.Platonic_soccer_ball
      ~normals:Rdk.Parametric_generators.Platonic_vertex_normals
      ~orientation:(Rdk.Parametric_generators.Platonic_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 2. 3. 4.) ~rotation:(Vec3.create 0.2 0.3 0.4)
      ~rotation_order:Rdk.Parametric_generators.Platonic_zxy ~face_groups:"face" ~radius:3. () in
  check (contains (Node.parameters graph) "kind=soccer_ball"
      && contains (Node.parameters graph) "normals=vertex"
      && contains (Node.parameters graph) "rotation_order=zxy"
      && contains (Node.parameters graph) "face_groups=face")
    "procedural Platonic cache identity omitted parameters";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 60
      && Rdk.Geometry.vertex_count output.geometry = 180
      && Rdk.Geometry.primitive_count output.geometry = 32
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "N"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "Cd"
         output.geometry <> None
      && Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "face_pentagons"
         output.geometry <> None)
    "procedural Platonic output contract";
  let invalid = Sop.platonic ~label:"bad-platonic-axis"
      ~orientation:(Rdk.Parametric_generators.Platonic_axis Vec3.zero) ~radius:1. () in
  (match Session.cook evaluator ~context:current invalid with
   | Ok _ -> fail "procedural Platonic accepted a zero up axis"
   | Error error ->
       check (error.code = "invalid_parameter")
         "procedural Platonic axis diagnostic code";
       check (List.map (fun trace -> trace.Diagnostic.label) error.trace
              = ["bad-platonic-axis"])
         "procedural Platonic axis diagnostic trace");
  Session.close evaluator

let test_spiral_generator_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let graph = Sop.spiral ~label:"ramped-spirals"
      ~extent:(Rdk.Spiral.Spiral_height_pitch { height = -6.; pitch = -0.75 })
      ~radius:(Rdk.Spiral.Spiral_logarithmic_end {
        start_radius = 0.4; end_radius = 3. })
      ~height_ramp:[0., 0.8; 0.5, 1.2; 1., 1.]
      ~radius_scale:1.3 ~radius_ramp:[0., 1.; 0.4, 0.7; 1., 1.1]
      ~direction:Rdk.Spiral.Spiral_clockwise ~start_angle:0.3
      ~divisions:(Rdk.Spiral.Spiral_divisions_per_curve 40)
      ~uniform_angle:false ~spiral_count:3
      ~orientation:(Rdk.Spiral.Spiral_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 2. 3. 4.) ~rotation:(Vec3.create 0.2 0.3 0.4)
      ~rotation_order:Rdk.Spiral.Spiral_zxy ~uniform_scale:1.2
      ~angle_attribute:"angle" ~x_axis_attribute:"xaxis"
      ~y_axis_attribute:"yaxis" ~tangent_attribute:"tangent"
      ~orient_attribute:"orient" ~distance_attribute:"distance" () in
  check (contains (Node.parameters graph) "extent=height_pitch"
      && contains (Node.parameters graph) "radius=logarithmic_end"
      && contains (Node.parameters graph) "height_ramp="
      && contains (Node.parameters graph) "uniform_angle=false"
      && contains (Node.parameters graph) "rotation_order=zxy"
      && contains (Node.parameters graph) "orient=orient")
    "procedural Spiral cache identity omitted advanced parameters";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 123
      && Rdk.Geometry.vertex_count output.geometry = 123
      && Rdk.Geometry.primitive_count output.geometry = 3
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "angle"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "xaxis"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "yaxis"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "tangent"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "orient"
         output.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "distance"
         output.geometry <> None)
    "procedural Spiral output contract";
  let invalid = Sop.spiral ~label:"bad-spiral-axis"
      ~orientation:(Rdk.Spiral.Spiral_axis Vec3.zero) () in
  (match Session.cook evaluator ~context:current invalid with
   | Ok _ -> fail "procedural Spiral accepted a zero central axis"
   | Error error ->
       check (error.code = "invalid_parameter")
         "procedural Spiral axis diagnostic code";
       check (List.map (fun trace -> trace.Diagnostic.label) error.trace
              = ["bad-spiral-axis"])
         "procedural Spiral axis diagnostic trace");
  Session.close evaluator

let test_declared_seed_dependency () =
  let graph =
    Sop.grid ~columns:5 ~rows:5 ~size:4. ()
    |> Sop.noise_displace ~amplitude:0.8 ~frequency:0.3
  in
  let evaluator = session () in
  let first = cook_ok evaluator (context ~seed:10L ~domains:1 ()) graph in
  let second = cook_ok evaluator (context ~seed:11L ~domains:4 ~time:8. ()) graph in
  check (not (equal_positions first.geometry second.geometry))
    "context seed did not change implicit noise";
  let stats = Session.stats evaluator in
  check (stats.cooks = 3 && stats.hits = 1)
    "seed-dependent node did not reuse its static input";
  let third = cook_ok evaluator (context ~seed:11L ~domains:2 ~grain:3
      ~time:200. ~frame:55L ()) graph in
  let stats = Session.stats evaluator in
  check (stats.cooks = 3 && stats.hits = 3)
    "noise node depended on undeclared context facts";
  check (second.geometry == third.geometry) "seed cache identity";
  Session.close evaluator

let test_labeled_random_identity () =
  let make () = Sop.grid ~columns:8 ~rows:8 ~size:4. ()
      |> Sop.noise_displace ~label:"terrain-noise"
           ~amplitude:0.5 ~frequency:0.2 in
  let first_graph = make () in
  ignore (Array.init 32 (fun index ->
    Sop.points [|(float_of_int index, 0., 0.)|]));
  let second_graph = make () in
  let cook graph =
    let evaluator = session () in
    let output = cook_ok evaluator (context ~seed:88L ()) graph in
    Session.close evaluator;
    output.geometry in
  check (equal_positions (cook first_graph) (cook second_graph))
    "explicit noise label did not stabilize random identity"

let test_switch_is_lazy () =
  let bad = Sop.grid ~label:"must-not-cook" ~columns:0 ~rows:1 ~size:1. () in
  let good = Sop.points ~label:"chosen" [| (0., 0., 0.) |] in
  let graph = Sop.switch ~index:1 [bad; good] in
  let evaluator = session () in
  let output = cook_ok evaluator (context ()) graph in
  check (Rdk.Geometry.point_count output.geometry = 1) "switch selected wrong input";
  check ((Session.stats evaluator).cooks = 2) "switch eagerly cooked unselected input";
  Session.close evaluator

let test_lru_limits_and_lifetime () =
  let graph = Sop.box () |> Sop.null in
  let evaluator = session ~entries:1 () in
  ignore (cook_ok evaluator (context ()) graph);
  let stats = Session.stats evaluator in
  check (stats.retained_entries = 1 && stats.evictions >= 1)
    "entry-bounded LRU did not evict";
  Session.clear evaluator;
  let stats = Session.stats evaluator in
  check (stats.retained_entries = 0 && stats.retained_payload_bytes = 0)
    "Session.clear retained payload";
  Session.close evaluator;
  check (Session.is_closed evaluator) "Session.close did not close";
  (match Session.cook evaluator ~context:(context ()) graph with
   | Ok _ -> fail "closed session cooked"
   | Error error -> check (error.code = "session_closed") "closed session error code");
  let uncached = session ~entries:8 ~bytes:0 () in
  ignore (cook_ok uncached (context ()) (Sop.box ()));
  check ((Session.stats uncached).retained_entries = 0)
    "payload budget retained oversized entry";
  Session.close uncached

let test_shared_payload_accounting () =
  let source = Sop.grid ~columns:30 ~rows:20 ~size:3. () in
  let moved = Sop.transform (Mat4.translation (Vec3.create 1. 0. 0.)) source in
  let evaluator = session () and current = context () in
  let source_output = cook_ok evaluator current source in
  let moved_output = cook_ok evaluator current moved in
  let naive = Rdk.Geometry.payload_bytes source_output.geometry
      + Rdk.Geometry.payload_bytes moved_output.geometry in
  let retained = (Session.stats evaluator).retained_payload_bytes in
  check (retained < naive) "session double-counted structurally shared RDK buffers";
  Session.clear evaluator;
  check ((Session.stats evaluator).retained_payload_bytes = 0)
    "payload reference accounting survived Session.clear";
  Session.close evaluator

let test_error_trace_and_cancellation () =
  let graph =
    Sop.grid ~label:"bad-grid" ~columns:0 ~rows:2 ~size:1. ()
    |> Sop.null ~label:"output"
  in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context ()) graph with
   | Ok _ -> fail "invalid grid cooked"
   | Error error ->
       check (error.code = "invalid_parameter") "grid error code";
       check (List.map (fun trace -> trace.Diagnostic.label) error.trace
              = ["output"; "bad-grid"])
         "node trace does not describe root-to-failure path";
       check (error.cause <> None) "RDK cause was not preserved");
  let cancel = Context.Cancel.create () in
  Context.Cancel.cancel cancel;
  let cancelled = Sop.points ~label:"cancelled-source" [| (0., 0., 0.) |] in
  (match Session.cook evaluator ~context:(context ~cancel ()) cancelled with
   | Ok _ -> fail "cancelled graph cooked"
   | Error error -> check (error.code = "cancelled") "cancellation error code");
  Session.close evaluator

let test_inspection_sharing_and_bridge () =
  let shared = Sop.box ~label:"prototype" () in
  let graph = Sop.merge ~label:"twice" [shared; shared] in
  let infos = Graph.inspect graph in
  check (List.length infos = 2) "graph inspection duplicated shared subgraph";
  check (Node.id shared > 0 && Node.label shared = "prototype") "node identity/label";
  let evaluator = session () in
  let output = cook_ok evaluator (context ()) graph in
  check (Rdk.Geometry.point_count output.geometry = 48
      && Rdk.Geometry.primitive_count output.geometry = 24)
    "real merge cardinality";
  let colored = Sop.box ()
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red in
  let colored = cook_ok evaluator (context ()) colored in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "Cd"
      colored.geometry <> None) "color_by_height did not create Cd";
  (match Rdk_rays.Rays_mesh.to_mesh colored.geometry with
   | Error error -> fail (Rdk.Error.to_string error)
   | Ok mesh -> check (Mesh.index_count mesh = 36) "mesh bridge index count");
  Session.close evaluator

let test_packed_instances () =
  let prototype = Sop.box ~label:"packed-prototype" () in
  let source_transforms =
    [|Mat4.scaling (Vec3.create 2. 1. 1.)|]
  in
  let packed = Instances.create ~transforms:source_transforms prototype in
  source_transforms.(0) <- Mat4.translation (Vec3.create 99. 0. 0.);
  let stored = Instances.transforms packed in
  check (Mat4.nearly_equal stored.(0)
      (Mat4.scaling (Vec3.create 2. 1. 1.)) ~eps:0.)
    "packed instances retained the caller's transform array";
  stored.(0) <- Mat4.translation (Vec3.create 77. 0. 0.);
  check (Mat4.nearly_equal (Instances.transforms packed).(0)
      (Mat4.scaling (Vec3.create 2. 1. 1.)) ~eps:0.)
    "packed instances exposed a mutable transform alias";
  let duplicated = Instances.duplicate ~copies:2
      ~transform:(Mat4.translation (Vec3.create 1. 0. 0.)) packed in
  check (Instances.source duplicated == prototype)
    "packed duplication replaced its prototype node";
  check (Instances.count duplicated = 3
      && Instances.payload_bytes duplicated = 3 * 16 * 8)
    "packed duplication cardinality/payload";
  let transforms = Instances.transforms duplicated in
  let copy_one_origin = Mat4.transform_point transforms.(1) Vec3.zero
  and copy_two_origin = Mat4.transform_point transforms.(2) Vec3.zero in
  check (Vec3.nearly_equal copy_one_origin (Vec3.create 1. 0. 0.) ~eps:1e-12
      && Vec3.nearly_equal copy_two_origin (Vec3.create 2. 0. 0.) ~eps:1e-12)
    "packed duplication transform composition/order"

let test_snapshot_feedback_boundary () =
  let evaluator = session ~entries:4 () and current = context () in
  let initial = cook_ok evaluator current (Sop.points [|(1., 0., 0.)|]) in
  let previous = Sop.snapshot ~label:"previous-frame" initial.geometry in
  let step = Sop.custom ~label:"solver-step" ~operation:"translate_step"
      ~version:1 ~parameters:"dx=0.25" [previous]
      (fun ~context:_ inputs ->
        match inputs with
        | [|geometry|] -> Ok (Rdk.Transform_ops.transform
            (Mat4.translation (Vec3.create 0.25 0. 0.)) geometry)
        | _ -> Error "solver step requires one snapshot") in
  let output = cook_ok evaluator current step in
  let x, _, _ = Rdk.Packed.Float3.get
      (Rdk.Geometry.positions output.geometry) 0 in
  check (x = 1.25) "snapshot feedback source/custom step";
  let source = List.hd (Node.inputs step) in
  check (Node.operation source = "snapshot"
      && contains (Node.parameters source)
           (string_of_int (Rdk.Geometry.data_id initial.geometry)))
    "snapshot source inspection identity";
  Session.close evaluator

let test_parallel_geometry_exactness () =
  let graph = Sop.grid ~columns:80 ~rows:70 ~size:10. ()
      |> Sop.noise_displace ~seed:42 ~amplitude:0.6 ~frequency:0.2
      |> Sop.color_by_height ~low:Color.black ~high:Color.white in
  let cook domains =
    let evaluator = session () in
    let output = cook_ok evaluator (context ~domains ~grain:97 ()) graph in
    Session.close evaluator;
    output.geometry
  in
  let one = cook 1 and many = cook 4 in
  check (equal_positions one many) "one/multi-domain positions differ";
  let colors geometry =
    match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "Cd" geometry with
    | None -> fail "missing Cd"
    | Some attribute -> Rdk.Attribute.storage attribute
  in
  (match colors one, colors many with
   | Rdk.Attribute.Float4 left, Rdk.Attribute.Float4 right ->
       let left = Rdk.Packed.Float4.Private.view left
       and right = Rdk.Packed.Float4.Private.view right in
       check (left.x = right.x && left.y = right.y && left.z = right.z
           && left.w = right.w) "one/multi-domain colors differ"
   | _ -> fail "Cd has unexpected storage")

let test_generators_selections_and_delete () =
  let evaluator = session () and current = context () in
  let selected = Select.primitive_indices [|0; 2|] in
  let kept = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.group ~name:"alternating" selected
      |> Sop.blast ~selected:false ~owner:Rdk.Group.Primitive ~group:"alternating"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.primitive_count kept.geometry = 2)
    "primitive selection/delete cardinality";
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "alternating"
      kept.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 2)
       "primitive group was not remapped through delete"
   | None -> fail "named primitive group was dropped");
  let point_selection = Select.points_in_bounds
      ~min:(Vec3.create (-0.1) (-0.1) (-0.1))
      ~max:(Vec3.create 1.1 0.1 1.1) in
  let grouped = Sop.points [|(-1.,0.,0.); (0.,0.,0.); (1.,0.,1.); (2.,0.,0.)|]
      |> Sop.group ~name:"inside" point_selection
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "inside" grouped.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 2) "point bounds selection"
   | None -> fail "point selection group missing");
  let compacted = Sop.grid ~columns:1 ~rows:1 ~size:2. ()
      |> Sop.group ~name:"doomed" (Select.primitive_indices [|0|])
      |> Sop.blast ~compact_points:true ~owner:Rdk.Group.Primitive ~group:"doomed"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.primitive_count compacted.geometry = 1
      && Rdk.Geometry.point_count compacted.geometry = 3)
    "delete with orphan-point compaction";
  let bounded = Sop.box ~size:(Vec3.create 2. 3. 4.) ()
      |> Sop.bound ~lower_padding:(Vec3.create 0.5 0.5 0.5)
           ~upper_padding:(Vec3.create 0.5 0.5 0.5)
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count bounded.geometry = 24)
    "procedural box Bound";
  let divided_bound = Sop.box ~size:(Vec3.create 2. 3. 4.) ()
      |> Sop.group ~name:"bound_faces"
           (Select.primitive_indices [|0;1;2;3|])
      |> Sop.bound ~selection:(Sop.Primitive_group "bound_faces")
           ~shape:(Rdk.Bound.Bound_box { divisions = 2, 3, 4 })
           ~lower_padding:(Vec3.create 0.2 0.3 0.4)
           ~upper_padding:(Vec3.create 0.4 0.3 0.2)
           ~bounds_group:"bounds" ~center_attribute:"bound_center"
           ~radii_attribute:"bound_radii"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count divided_bound.geometry = 94
      && Rdk.Geometry.primitive_count divided_bound.geometry = 104
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Detail "bound_center"
         divided_bound.geometry <> None)
    "procedural divided Bound output/metadata";
  let bound_sphere = Sop.box ~size:(Vec3.create 2. 3. 4.) ()
      |> Sop.bound ~shape:(Rdk.Bound.Bound_sphere {
           segments = 16; rings = 8; minimum_radius = 0. })
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count bound_sphere.geometry = 114
      && Rdk.Geometry.primitive_count bound_sphere.geometry = 224)
    "procedural Bound sphere cardinality";
  let missing_bound_group = Sop.box ()
      |> Sop.bound ~selection:(Sop.Point_group "missing") in
  (match Session.cook evaluator ~context:current missing_bound_group with
   | Error error -> check (error.code = "missing_group")
       "Bound missing-group diagnostic"
   | Ok _ -> fail "Bound accepted a missing selection group");
  let target_bounds = Sop.box ~size:(Vec3.create 5. 6. 7.) ()
      |> Sop.transform (Mat4.translation (Vec3.create 3. 4. 5.)) in
  let matched = Sop.box ~size:(Vec3.create 1. 2. 3.) ()
      |> Sop.match_size ~fit:Rdk.Match_size.Stretch ~target:target_bounds
      |> cook_ok evaluator current in
  let matched_bounds = Rdk.Analysis.bounds matched.geometry |> Option.get in
  check (abs_float (matched_bounds.center.x -. 3.) < 1e-12
      && abs_float (matched_bounds.size.z -. 7.) < 1e-12)
    "procedural match size";
  let advanced_target = Sop.box ~size:(Vec3.create 4. 6. 8.) ()
      |> Sop.transform (Mat4.translation (Vec3.create 8. 4. 2.))
      |> Sop.group ~name:"target_bounds" Select.all_points in
  let advanced = Sop.box ~size:(Vec3.create 1. 2. 3.) ()
      |> Sop.group ~name:"move" Select.all_points
      |> Sop.group ~name:"source_bounds" Select.all_points
      |> Sop.match_size ~selection:(Sop.Point_group "move")
           ~source_selection:(Sop.Point_group "source_bounds")
           ~target_selection:(Sop.Point_group "target_bounds")
           ~fit:Rdk.Match_size.Match_y ~justify:(Vec3.create 1. 0. 0.)
           ~target_justify:(Vec3.create (-1.) 0. 0.)
           ~offset:(Vec3.create 0.25 0. 0.) ~target:advanced_target
      |> cook_ok evaluator current |> fun cooked ->
      Rdk.Analysis.bounds cooked.geometry |> Option.get in
  check (abs_float (advanced.size.x -. 3.) < 1e-12
      && abs_float (advanced.size.y -. 6.) < 1e-12
      && abs_float (advanced.max.x -. 6.25) < 1e-12)
    "procedural selected/cross-anchor Match Size";
  let numeric_match = Sop.box ~size:(Vec3.create 2. 4. 8.) ()
      |> Sop.match_size ~target_center:(Vec3.create (-3.) 2. 5.)
           ~target_size:(Vec3.create 1. 1. 1.)
      |> cook_ok evaluator current |> fun cooked ->
      Rdk.Analysis.bounds cooked.geometry |> Option.get in
  check (abs_float (numeric_match.center.x +. 3.) < 1e-12
      && abs_float (numeric_match.size.z -. 1.) < 1e-12)
    "procedural numeric/unit Match Size";
  let missing_match_source = Sop.box ()
      |> Sop.match_size ~source_selection:(Sop.Point_group "missing") in
  (match Session.cook evaluator ~context:current missing_match_source with
   | Error error -> check (error.code = "missing_group")
       "Match Size missing source-group diagnostic"
   | Ok _ -> fail "Match Size accepted a missing source group");
  let missing_match_target = Sop.box ()
      |> Sop.match_size ~target_selection:(Sop.Point_group "missing")
           ~target:(Sop.box ()) in
  (match Session.cook evaluator ~context:current missing_match_target with
   | Error error -> check (error.code = "missing_group")
       "Match Size missing target-group diagnostic"
   | Ok _ -> fail "Match Size accepted a missing target group");
  let circle = Sop.circle ~segments:20 ~radius:2. () |> cook_ok evaluator current in
  (match Rdk_rays.Rays_mesh.to_mesh circle.geometry with
   | Ok mesh -> check (Mesh.mode mesh = Mesh.Lines && Mesh.index_count mesh = 40)
       "circle render bridge"
   | Error error -> fail (Rdk.Error.to_string error));
  let line_node = Sop.line ~points:17 ~origin:(Vec3.create 1. 2. 3.)
      ~direction:(Vec3.create 0. 2. 0.) ~length:4. () in
  check (contains (Node.parameters line_node) "points=17")
    "Line node parameter identity";
  let line = cook_ok evaluator current line_node in
  let line_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions line.geometry) in
  check (Rdk.Geometry.vertex_count line.geometry = 17
      && line_positions.y.(0) = 2. && line_positions.y.(16) = 6.)
    "procedural Line source";
  let polyframe_node = Sop.grid ~columns:4 ~rows:3 ~uv_attribute:"uv"
      ~size:2. ()
      |> Sop.polyframe ~orthogonal:true ~left_handed:true
           ~normal_attribute:"frame_n"
           ~tangent_attribute:(Some "frame_u")
           ~bitangent_attribute:(Some "frame_v")
           (Rdk.Polyframe.Texture_uv_gradient "uv") in
  check (contains (Node.parameters polyframe_node)
      "style=texture_uv_gradient:uv"
      && contains (Node.parameters polyframe_node) "orthogonal=true"
      && contains (Node.parameters polyframe_node) "left_handed=true"
      && contains (Node.parameters polyframe_node) "normal_attribute=frame_n")
    "PolyFrame node parameter identity";
  let polyframed = polyframe_node |> cook_ok evaluator current in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "frame_n"
           polyframed.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "frame_u"
           polyframed.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "frame_v"
           polyframed.geometry <> None)
    "procedural PolyFrame vertex outputs";
  let missing_polyframe = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.polyframe ~selection:(Sop.Point_group "missing")
           Rdk.Polyframe.First_edge in
  (match Session.cook evaluator ~context:current missing_polyframe with
   | Error error -> check (error.code = "missing_group")
       "PolyFrame missing-group diagnostic"
   | Ok _ -> fail "PolyFrame accepted a missing selection group");
  let resample_node = Sop.circle ~segments:12 ~radius:1. ()
      |> Sop.resample ~segments:48 in
  check (contains (Node.parameters resample_node) "segments=48")
    "resample node parameter identity";
  let resampled_circle = resample_node |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count resampled_circle.geometry = 48)
    "procedural closed-curve resample";
  let length_resample = Sop.polyline
      [|(0., 0., 0.); (1., 0., 0.); (1., 2., 0.)|]
      |> Sop.resample ~maximum_segment_length:0.6 ~even_last_segment:false
           ~curve_u_attribute:"curveu" ~curve_number_attribute:"curvenum"
           ~distance_attribute:"distance" ~tangent_attribute:"tangent" in
  check (contains (Node.parameters length_resample)
      "maximum_segment_length=some:"
      && contains (Node.parameters length_resample) "curve_u_attribute=curveu")
    "advanced Resample node parameter identity";
  let length_resampled = length_resample |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count length_resampled.geometry = 6
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "curveu"
           length_resampled.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "tangent"
           length_resampled.geometry <> None)
    "procedural length Resample diagnostics";
  let restricted_resample = Sop.merge [
      Sop.polyline [|(0., 0., 0.); (2., 0., 0.)|];
      Sop.polyline [|(10., 0., 0.); (11., 1., 0.); (12., 0., 0.)|];
    ]
    |> Sop.group ~name:"first_curve" (Select.primitive_indices [|0|])
    |> Sop.resample ~group:"first_curve" ~segments:4 in
  check (contains (Node.parameters restricted_resample) "group=first_curve")
    "group-restricted Resample cache identity";
  let restricted = restricted_resample |> cook_ok evaluator current in
  let restricted_topology = Rdk.Geometry.topology restricted.geometry in
  let a0, a1 = Rdk.Topology.primitive_vertex_range restricted_topology 0
  and b0, b1 = Rdk.Topology.primitive_vertex_range restricted_topology 1 in
  check (a1 - a0 = 5 && b1 - b0 = 3)
    "procedural group-restricted Resample";
  let sweep_node = Sop.polyline [|(0.,0.,0.); (0.,1.,0.); (1.,2.,0.)|]
      |> Sop.resample ~segments:16 |> Sop.sweep_circle ~sides:8 ~radius:0.1 in
  check (contains (Node.parameters sweep_node) "sides=8")
    "sweep node parameter identity";
  let tube = sweep_node |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count tube.geometry = 136
      && Rdk.Geometry.primitive_count tube.geometry = 128)
    "procedural curve sweep";
  let polywire_node = Sop.polyline [|(0.,0.,0.); (0.,1.,0.); (0.,2.,0.)|]
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"width" 0.5
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"wire_v" 2.
      |> Sop.set_int ~owner:Rdk.Attribute.Point ~name:"wire_seam" 1
      |> Sop.set_vector ~owner:Rdk.Attribute.Point ~name:"wire_up" Vec3.unit_x
      |> Sop.polywire ~sides:8 ~scale_attribute:"width" ~seam_offset:(-2)
           ~seam_attribute:"wire_seam" ~v_attribute:"wire_v"
           ~up_attribute:"wire_up" ~caps:true ~cap_group:"tube_caps"
           ~radius:0.2 in
  check (Node.operation polywire_node = "polywire"
      && contains (Node.parameters polywire_node) "seam_offset=-2"
      && contains (Node.parameters polywire_node) "v_attribute=\"wire_v\""
      && contains (Node.parameters polywire_node) "up_attribute=\"wire_up\"")
    "PolyWire node operation/cache identity";
  let scaled_tube = cook_ok evaluator current polywire_node in
  check (Rdk.Geometry.point_count scaled_tube.geometry = 24
      && Rdk.Geometry.primitive_count scaled_tube.geometry = 18)
    "procedural scaled curve sweep";
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "tube_caps"
      scaled_tube.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 2)
       "procedural sweep cap group"
   | None -> fail "procedural sweep cap group missing");
  let converted_lines = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.group_edges ~name:"all_grid_edges"
      |> Sop.convert_line ~group:"all_grid_edges" ~remove_unused_points:true
           ~length_attribute:"edge_length"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.primitive_count converted_lines.geometry = 9
      && Rdk.Geometry.vertex_count converted_lines.geometry = 18
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive
           "edge_length" converted_lines.geometry <> None)
    "procedural Convert Line";
  let connected_path_node = Sop.polyline
      [|(0.,0.,0.); (1.,0.,0.); (3.,0.,0.)|]
      |> Sop.convert_line ~connect_path:true ~maximum_distance:0.
           ~connect_only_to_other_end_points:true
           ~make_isolated_loops_closed:true ~length_attribute:"path_length" in
  check (Node.version connected_path_node = 2
      && contains (Node.parameters connected_path_node) "connect_path=true"
      && contains (Node.parameters connected_path_node) "maximum_distance=0"
      && contains (Node.parameters connected_path_node)
           "connect_only_to_other_end_points=true"
      && contains (Node.parameters connected_path_node)
           "make_isolated_loops_closed=true")
    "procedural Convert Line connected-path cache identity";
  let connected_path = cook_ok evaluator current connected_path_node in
  let connected_length = Rdk.Geometry.find_attribute
      ~owner:Rdk.Attribute.Primitive "path_length" connected_path.geometry
      |> Option.get
      |> Rdk.Attribute.get (Rdk.Attribute.key ~name:"path_length"
           ~owner:Rdk.Attribute.Primitive Rdk.Attribute.float)
      |> Option.get in
  check (Rdk.Geometry.primitive_count connected_path.geometry = 1
      && Rdk.Geometry.vertex_count connected_path.geometry = 3
      && connected_length = [|3.|])
    "procedural Convert Line connected path/final length";
  let carved = Sop.polyline [|(0.,0.,0.); (1.,0.,0.); (3.,0.,0.);
      (6.,0.,0.)|] |> Sop.carve ~first:0.2 ~last:0.6
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count carved.geometry = 3
      && Rdk.Topology.primitive_kind (Rdk.Geometry.topology carved.geometry) 0
         = Rdk.Topology.Open_polyline)
    "procedural curve carve";
  let grouped_carve_source = Sop.merge [
      Sop.polyline [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.); (3.,0.,0.)|]
        |> Sop.normals;
      Sop.grid ~connectivity:Rdk.Plane_generators.Grid_quads ~columns:1 ~rows:1 ~size:1. ();
    ]
      |> Sop.set_float ~owner:Rdk.Attribute.Primitive ~name:"first_u" 0.25
      |> Sop.set_float ~owner:Rdk.Attribute.Primitive ~name:"second_u" 0.5
      |> Sop.group ~name:"carve_curve" (Select.primitive_indices [|0|])
  in
  let grouped_carve_node = grouped_carve_source
      |> Sop.carve ~group:"carve_curve" ~relative_arc_length:false
           ~first:0.25 ~last:0.75 in
  check (Node.version grouped_carve_node = 7
      && contains (Node.parameters grouped_carve_node) "group=\"carve_curve\"")
    "procedural grouped Carve cache identity";
  let grouped_carve = cook_ok evaluator current grouped_carve_node in
  check (Rdk.Geometry.primitive_count grouped_carve.geometry = 2
      && Rdk.Topology.primitive_kind (Rdk.Geometry.topology grouped_carve.geometry)
           1 = Rdk.Topology.Polygon)
    "procedural grouped Carve preserved unselected polygon";
  let divided_carve_node = grouped_carve_source
      |> Sop.carve ~group:"carve_curve" ~relative_arc_length:false
           ~first:0.25 ~last:0.75 ~divisions:3 in
  check (contains (Node.parameters divided_carve_node) "divisions=3")
    "procedural divided Carve cache identity";
  let divided_carve = cook_ok evaluator current divided_carve_node in
  check (Rdk.Geometry.primitive_count divided_carve.geometry = 4
      && Rdk.Geometry.vertex_count divided_carve.geometry = 12)
    "procedural divided Carve cook";
  (match
     try
       ignore (Sop.carve ~divisions:0 grouped_carve_source);
       None
     with Invalid_argument message -> Some message
   with
   | Some "Sop.carve: divisions must be positive" -> ()
   | _ -> fail "procedural Carve accepted zero divisions");
  let attributed_carve_node = grouped_carve_source
      |> Sop.carve ~group:"carve_curve" ~relative_arc_length:false
           ~first_attribute:"first_u" ~last_attribute:"second_u" in
  check (contains (Node.parameters attributed_carve_node)
        "first_attribute=\"first_u\""
      && contains (Node.parameters attributed_carve_node)
           "last_attribute=\"second_u\""
      && contains (Node.parameters attributed_carve_node) "attribute_mode=replace")
    "procedural attributed Carve cache identity";
  let attributed_carve = cook_ok evaluator current attributed_carve_node in
  let attributed_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions attributed_carve.geometry) in
  check (Rdk.Geometry.point_count attributed_carve.geometry = 11
      && Rdk.Geometry.vertex_count attributed_carve.geometry = 7
      && attributed_positions.x.(8) = 0.75
      && attributed_positions.x.(10) = 1.5)
    "procedural attributed Carve replace behavior";
  let scaled_carve_node = grouped_carve_source
      |> Sop.carve ~group:"carve_curve" ~relative_arc_length:false
           ~first:0.5 ~last:1. ~first_attribute:"first_u"
           ~last_attribute:"second_u"
           ~attribute_mode:Rdk.Curve_ops.Scale in
  check (contains (Node.parameters scaled_carve_node) "attribute_mode=scale")
    "procedural scaled Carve cache identity";
  let scaled_carve = cook_ok evaluator current scaled_carve_node in
  let scaled_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions scaled_carve.geometry) in
  check (Rdk.Geometry.point_count scaled_carve.geometry = 11
      && scaled_positions.x.(8) = 0.375
      && scaled_positions.x.(10) = 1.5)
    "procedural attributed Carve scale behavior";
  let missing_carve_attribute = grouped_carve_source
      |> Sop.carve ~group:"carve_curve" ~first_attribute:"missing" in
  (match Session.cook evaluator ~context:current missing_carve_attribute with
   | Error error -> check (error.code = "invalid_geometry")
       "Carve missing-attribute diagnostic"
   | Ok _ -> fail "Carve accepted a missing primitive parameter attribute");
  let breakpoint_node = grouped_carve_source
      |> Sop.carve ~group:"carve_curve" ~relative_arc_length:false
           ~first:0. ~last:1. ~only_at_breakpoints:true
           ~cut_at_all_internal_breakpoints:true in
  check (contains (Node.parameters breakpoint_node) "only_at_breakpoints=true"
      && contains (Node.parameters breakpoint_node)
           "cut_at_all_internal_breakpoints=true")
    "procedural breakpoint Carve cache identity";
  let breakpoint_cut = cook_ok evaluator current breakpoint_node in
  check (Rdk.Geometry.primitive_count breakpoint_cut.geometry = 4
      && Rdk.Geometry.vertex_count breakpoint_cut.geometry = 10)
    "procedural cut-at-all breakpoint Carve";
  let breakpoint_extract = grouped_carve_source
      |> Sop.carve ~group:"carve_curve" ~relative_arc_length:false
           ~first_attribute:"first_u" ~last_attribute:"second_u"
           ~only_at_breakpoints:true ~extract_points:true
      |> cook_ok evaluator current in
  let breakpoint_extract_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions breakpoint_extract.geometry) in
  check (Rdk.Geometry.primitive_count breakpoint_extract.geometry = 1
      && Rdk.Geometry.point_count breakpoint_extract.geometry = 9
      && breakpoint_extract_positions.x.(8) = 1.)
    "procedural attributed breakpoint extraction";
  let outside_node = grouped_carve_source
      |> Sop.carve ~group:"carve_curve" ~relative_arc_length:false
           ~first:0.25 ~last:0.75 ~keep:Rdk.Curve_ops.Outside in
  check (contains (Node.parameters outside_node) "keep=outside")
    "procedural Carve outside cache identity";
  let outside = cook_ok evaluator current outside_node in
  check (Rdk.Geometry.primitive_count outside.geometry = 3
      && Rdk.Topology.primitive_kind (Rdk.Geometry.topology outside.geometry)
           2 = Rdk.Topology.Polygon)
    "procedural Carve outside pieces";
  let extracted_node = grouped_carve_source
      |> Sop.carve ~group:"carve_curve" ~relative_arc_length:false
           ~first:0.25 ~last:0.75 ~extract_points:true ~divisions:5 in
  check (contains (Node.parameters extracted_node) "extract_points=true"
      && contains (Node.parameters extracted_node) "divisions=5"
      && contains (Node.parameters extracted_node) "keep_original=false")
    "procedural Carve extraction cache identity";
  let extracted = cook_ok evaluator current extracted_node in
  check (Rdk.Geometry.primitive_count extracted.geometry = 1
      && Rdk.Geometry.vertex_count extracted.geometry = 4
      && Rdk.Geometry.point_count extracted.geometry = 13
      && Rdk.Topology.primitive_kind (Rdk.Geometry.topology extracted.geometry)
           0 = Rdk.Topology.Polygon)
    "procedural Carve free-point extraction";
  let missing_carve_group = Sop.polyline [|(0.,0.,0.); (1.,0.,0.)|]
      |> Sop.carve ~group:"missing" ~first:0.2 ~last:0.8 in
  (match Session.cook evaluator ~context:current missing_carve_group with
   | Error error -> check (error.code = "missing_group")
       "Carve missing-group diagnostic"
   | Ok _ -> fail "Carve accepted a missing primitive group");
  let unrolled = Sop.circle ~segments:12 ~radius:1. ()
      |> Sop.ends Rdk.Curve_topology.Ends_unroll_shared |> cook_ok evaluator current in
  check (Rdk.Geometry.vertex_count unrolled.geometry = 13
      && Rdk.Topology.primitive_kind (Rdk.Geometry.topology unrolled.geometry) 0
         = Rdk.Topology.Open_polyline)
    "procedural curve ends";
  let joined = Sop.merge [
      Sop.polyline [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|];
      Sop.polyline [|(4.,0.,0.); (3.,0.,0.); (2.,0.,0.)|];
    ] |> Sop.join_curves |> cook_ok evaluator current in
  check (Rdk.Geometry.primitive_count joined.geometry = 1
      && Rdk.Geometry.vertex_count joined.geometry = 5)
    "procedural curve join/orientation/weld";
  let globally_joined_node = Sop.merge [
      Sop.polyline [|(0.,0.,0.); (1.,0.,0.)|];
      Sop.polyline [|(10.,0.,0.); (11.,0.,0.)|];
      Sop.polyline [|(3.,0.,0.); (2.,0.,0.)|];
    ] |> Sop.join_curves ~connect_closest_ends:true in
  check (Node.version globally_joined_node = 4
      && contains (Node.parameters globally_joined_node)
           "connect_closest_ends=true")
    "procedural global closest Curve Join cache identity";
  let globally_joined = cook_ok evaluator current globally_joined_node in
  let topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology globally_joined.geometry) in
  check (topology.vertex_points = [|0;1;5;4;2;3|])
    "procedural global closest Curve Join order";
  let picked_source = Sop.merge [
      Sop.polyline [|(0.,0.,0.); (1.,0.,0.)|];
      Sop.polyline [|(10.,0.,0.); (11.,0.,0.)|];
      Sop.polyline [|(3.,0.,0.); (2.,0.,0.)|];
      Sop.polyline [|(12.,0.,0.); (11.,0.,0.)|];
    ] in
  let ordered_join = picked_source
      |> Sop.ordered_group ~owner:Rdk.Group.Primitive ~name:"authored_order"
           [|2;0;3|]
      |> Sop.join_curves ~group:"authored_order" ~orient_closest:false
      |> cook_ok evaluator current in
  let ordered_topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology ordered_join.geometry) in
  check (ordered_topology.primitive_offsets = [|0;2;8|]
      && ordered_topology.vertex_points = [|2;3;4;5;0;1;6;7|])
    "procedural Curve Join ignored ordered primitive-group traversal";
  let picked_ends = [|
      { Rdk.Curve_topology.primitive = 2; end_ = Rdk.Curve_topology.Join_curve_start };
      { Rdk.Curve_topology.primitive = 0; end_ = Rdk.Curve_topology.Join_curve_start };
      { Rdk.Curve_topology.primitive = 3; end_ = Rdk.Curve_topology.Join_curve_end };
    |] in
  let picked_node = picked_source |> Sop.join_curves ~picked_ends in
  picked_ends.(0) <-
    { Rdk.Curve_topology.primitive = 1; end_ = Rdk.Curve_topology.Join_curve_end };
  check (Node.version picked_node = 4
      && contains (Node.parameters picked_node)
           "picked_ends=2:start,0:start,3:end")
    "procedural picked-end Curve Join cache identity/ownership";
  let picked = cook_ok evaluator current picked_node in
  let picked_topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology picked.geometry) in
  check (picked_topology.primitive_offsets = [|0;2;8|]
      && picked_topology.vertex_points = [|2;3;5;4;0;1;7;6|])
    "procedural picked-end Curve Join order/orientation";
  (match try Some (picked_source |> Sop.join_curves ~group:"curves"
      ~picked_ends) with Invalid_argument _ -> None with
   | None -> ()
   | Some _ -> fail "procedural Curve Join accepted group and picked ends");
  (match try Some (picked_source |> Sop.join_curves ~picked_ends
      ~connect_closest_ends:true) with Invalid_argument _ -> None with
   | None -> ()
   | Some _ -> fail "procedural Curve Join accepted picks and closest ordering");
  let duplicate_picks = picked_source |> Sop.join_curves ~picked_ends:[|
      { Rdk.Curve_topology.primitive = 1; end_ = Rdk.Curve_topology.Join_curve_start };
      { Rdk.Curve_topology.primitive = 1; end_ = Rdk.Curve_topology.Join_curve_end };
    |] in
  (match Session.cook evaluator ~context:current duplicate_picks with
   | Error error -> check (error.code = "invalid_geometry")
       "Curve Join duplicate-pick diagnostic"
   | Ok _ -> fail "procedural Curve Join cooked duplicate picks");
  let retained_subgroups_node = Sop.merge [
      Sop.polyline [|(0.,0.,0.); (1.,0.,0.)|];
      Sop.polyline [|(10.,0.,0.); (11.,0.,0.)|];
      Sop.polyline [|(3.,0.,0.); (2.,0.,0.)|];
    ] |> Sop.join_curves ~connect_closest_ends:true ~group_size:2
         ~keep_originals:true in
  check (contains (Node.parameters retained_subgroups_node) "group_size=2"
      && contains (Node.parameters retained_subgroups_node)
           "keep_originals=true")
    "procedural Curve Join subgroup/keep cache identity";
  let retained_subgroups = cook_ok evaluator current retained_subgroups_node in
  check (Rdk.Geometry.primitive_count retained_subgroups.geometry = 5
      && Rdk.Geometry.vertex_count retained_subgroups.geometry = 12)
    "procedural Curve Join subgroup/keep topology";
  (match try Some (Sop.polyline [|(0.,0.,0.); (1.,0.,0.)|]
      |> Sop.join_curves ~group_size:0) with Invalid_argument _ -> None with
   | None -> ()
   | Some _ -> fail "procedural Curve Join accepted invalid subgroup size");
  let missing_curve_group = Sop.circle ~segments:12 ~radius:1. ()
      |> Sop.ends ~group:"missing" Rdk.Curve_topology.Ends_open in
  (match Session.cook evaluator ~context:current missing_curve_group with
   | Error error -> check (error.code = "missing_group")
       "Curve Ends missing-group diagnostic"
   | Ok _ -> fail "Curve Ends accepted a missing primitive group");
  let missing_join_group = Sop.polyline [|(0.,0.,0.); (1.,0.,0.)|]
      |> Sop.join_curves ~group:"missing" in
  (match Session.cook evaluator ~context:current missing_join_group with
   | Error error -> check (error.code = "missing_group")
       "Curve Join missing-group diagnostic"
   | Ok _ -> fail "Curve Join accepted a missing primitive group");
  let missing_line_group = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.convert_line ~group:"missing" in
  (match Session.cook evaluator ~context:current missing_line_group with
   | Error error -> check (error.code = "missing_group")
       "Convert Line missing-group diagnostic"
   | Ok _ -> fail "Convert Line accepted a missing edge group");
  let reverse_base = Rdk.Plane_generators.grid ~connectivity:Rdk.Plane_generators.Grid_quads
      ~columns:2 ~rows:1 ~size:2. () |> Result.get_ok in
  let reverse_group = Rdk.Group.ordered ~owner:Rdk.Group.Primitive
      ~name:"reverse_first" ~length:2 [|0|] |> Result.get_ok in
  let reverse_source = Rdk.Geometry.with_group reverse_group reverse_base
      |> Result.get_ok in
  let triangulate_graph = Sop.snapshot reverse_source
      |> Sop.triangulate ~group:"reverse_first" in
  check (Node.version triangulate_graph = 2
      && contains (Node.parameters triangulate_graph) "group=reverse_first")
    "procedural Triangulate cache identity";
  let triangulated = cook_ok evaluator current triangulate_graph in
  let expected_triangulate = Rdk.Triangulate.run ~grain:1
      ~primitives:(Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive
        "reverse_first" reverse_source |> Option.get) reverse_source
      |> Result.get_ok in
  let triangulated_topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology triangulated.geometry)
  and expected_triangulated_topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology expected_triangulate) in
  check (triangulated_topology.vertex_points
      = expected_triangulated_topology.vertex_points
      && triangulated_topology.primitive_offsets
         = expected_triangulated_topology.primitive_offsets)
    "procedural Triangulate did not forward its primitive group";
  let missing_triangulate = Sop.snapshot reverse_source
      |> Sop.triangulate ~group:"missing" in
  (match Session.cook evaluator ~context:current missing_triangulate with
   | Error error -> check (error.code = "missing_group")
       "Triangulate missing-group diagnostic"
   | Ok _ -> fail "Triangulate accepted a missing primitive group");
  let reverse_graph = Sop.snapshot reverse_source
      |> Sop.reverse ~group:"reverse_first"
           ~operation:(Rdk.Reverse_faces.Shift_vertices (-1)) in
  check (Node.version reverse_graph = 2
      && contains (Node.parameters reverse_graph) "group=reverse_first"
      && contains (Node.parameters reverse_graph) "operation=shift:-1")
    "procedural Reverse cache identity";
  let reversed = cook_ok evaluator current reverse_graph in
  let expected_reverse = Rdk.Reverse_faces.run ~grain:1
      ~primitives:(Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive
        "reverse_first" reverse_source |> Option.get)
      ~operation:(Rdk.Reverse_faces.Shift_vertices (-1)) reverse_source
      |> Result.get_ok in
  let actual_topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology reversed.geometry)
  and expected_topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology expected_reverse) in
  check (actual_topology.vertex_points = expected_topology.vertex_points)
    "procedural Reverse did not forward group/shift controls";
  let missing_reverse = Sop.snapshot reverse_source
      |> Sop.reverse ~group:"missing" in
  (match Session.cook evaluator ~context:current missing_reverse with
   | Error error -> check (error.code = "missing_group")
       "Reverse missing-group diagnostic"
   | Ok _ -> fail "Reverse accepted a missing primitive group");
  let normal_graph = Sop.snapshot reverse_source
      |> Sop.normals ~selection:(Sop.Primitive_group "reverse_first")
           ~owner:Rdk.Attribute.Vertex ~weighting:Rdk.Normal_ops.Vertex_angle
           ~cusp_angle:(Float.pi /. 4.) ~keep_original_zero:true
           ~reverse:true ~attribute:"custom_n" in
  check (Node.version normal_graph = 2
      && contains (Node.parameters normal_graph) "selection=primitive:"
      && contains (Node.parameters normal_graph) "owner=vertex"
      && contains (Node.parameters normal_graph) "weighting=vertex_angle"
      && contains (Node.parameters normal_graph) "keep_zero=true"
      && contains (Node.parameters normal_graph) "reverse=true"
      && contains (Node.parameters normal_graph) "attribute=\"custom_n\"")
    "procedural Normals cache identity";
  let normal_output = cook_ok evaluator current normal_graph in
  let expected_normals = Rdk.Normal_ops.run ~grain:1
      ~selection:(Rdk.Transform_ops.Selected_primitives
        (Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive
          "reverse_first" reverse_source |> Option.get))
      ~owner:Rdk.Attribute.Vertex ~weighting:Rdk.Normal_ops.Vertex_angle
      ~cusp_angle:(Float.pi /. 4.) ~keep_original_zero:true
      ~reverse:true ~attribute:"custom_n" reverse_source |> Result.get_ok in
  let actual_n = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex
      "custom_n" normal_output.geometry |> Option.get
  and expected_n = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex
      "custom_n" expected_normals |> Option.get in
  (match Rdk.Attribute.Private.storage actual_n,
      Rdk.Attribute.Private.storage expected_n with
   | Rdk.Attribute.Float3 actual, Rdk.Attribute.Float3 expected ->
       let actual = Rdk.Packed.Float3.Private.view actual
       and expected = Rdk.Packed.Float3.Private.view expected in
       check (actual.x = expected.x && actual.y = expected.y
           && actual.z = expected.z)
         "procedural Normals did not forward its controls"
   | _ -> fail "procedural Normals changed output storage");
  let missing_normals = Sop.snapshot reverse_source
      |> Sop.normals ~selection:(Sop.Point_group "missing") in
  (match Session.cook evaluator ~context:current missing_normals with
   | Error error -> check (error.code = "missing_group")
       "Normals missing-group diagnostic"
   | Ok _ -> fail "Normals accepted a missing point group");
  let sphere = Sop.uv_sphere ~segments:10 ~rings:5 ~radius:1. ()
      |> Sop.reverse |> Sop.normals |> Sop.measure Rdk.Analysis.Area |> Sop.connectivity
      |> cook_ok evaluator current in
  check (Rdk.Geometry.primitive_count sphere.geometry = 80)
    "sphere/reverse/normals pipeline";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "area"
      sphere.geometry <> None) "measure area attribute";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "class"
      sphere.geometry <> None) "connectivity attribute";
  let point_connectivity = Sop.grid ~columns:2 ~rows:2 ~size:2. ()
      |> Sop.connectivity ~owner:Rdk.Analysis.Connectivity_points
           ~name:"point_island"
           ~attribute:(Rdk.Analysis.Connectivity_text "piece_")
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "point_island"
      point_connectivity.geometry with
   | Some attribute ->
       (match Rdk.Attribute.storage attribute with
        | Rdk.Attribute.Text values ->
            check (values = Array.make 9 "piece_0")
              "procedural point text Connectivity output"
        | _ -> fail "procedural point Connectivity output kind")
   | None -> fail "procedural point Connectivity dropped output");
  let seam_connectivity = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.group_edges ~name:"every_edge"
      |> Sop.connectivity ~seam_group:"every_edge" ~name:"seam_island"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive
      "seam_island" seam_connectivity.geometry with
   | Some attribute ->
       (match Rdk.Attribute.storage attribute with
        | Rdk.Attribute.Int values ->
            check (values = [|0; 1|])
              "procedural seam Connectivity did not split triangles"
        | _ -> fail "procedural seam Connectivity output kind")
   | None -> fail "procedural seam Connectivity dropped output");
  let missing_connectivity_group = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.connectivity ~owner:Rdk.Analysis.Connectivity_points
           ~point_group:"missing" in
  (match Session.cook evaluator ~context:current missing_connectivity_group with
   | Error error -> check (error.code = "missing_group")
       "Connectivity missing-group diagnostic"
   | Ok _ -> fail "Connectivity accepted a missing point group");
  let measured_box = Sop.box ~size:(Vec3.create 2. 4. 6.) ()
      |> Sop.measure ~name:"edge_total" Rdk.Analysis.Perimeter
      |> Sop.measure ~name:"face_area" ~total_name:"surface_area"
           Rdk.Analysis.Area
      |> Sop.measure ~name:"signed_piece_volume" ~total_name:"signed_volume"
           Rdk.Analysis.Signed_volume
      |> cook_ok evaluator current in
  let detail_float name =
    match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Detail name
        measured_box.geometry with
    | Some attribute ->
        (match Rdk.Attribute.storage attribute with
         | Rdk.Attribute.Float [|value|] -> value
         | _ -> fail ("unexpected detail storage for " ^ name))
    | None -> fail ("missing detail measure " ^ name) in
  check (abs_float (detail_float "surface_area" -. 88.) < 1e-12)
    "procedural total surface area";
  check (abs_float (abs_float (detail_float "signed_volume") -. 48.) < 1e-12)
    "procedural total signed volume";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive
      "edge_total" measured_box.geometry <> None)
    "procedural perimeter attribute";
  let throughout = Sop.grid ~columns:1 ~rows:1 ~size:2. ()
      |> Sop.measure ~accumulation:Rdk.Analysis.Throughout ~name:"whole_area"
           Rdk.Analysis.Area
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "whole_area"
      throughout.geometry with
   | Some attribute ->
       (match Rdk.Attribute.storage attribute with
        | Rdk.Attribute.Float values ->
            check (values = [|4.; 4.|]) "procedural throughout accumulation"
        | _ -> fail "procedural throughout measure has wrong storage")
   | None -> fail "procedural throughout measure missing");
  let missing_measure_group = Sop.box ()
      |> Sop.measure ~group:"missing" Rdk.Analysis.Area in
  (match Session.cook evaluator ~context:current missing_measure_group with
   | Error error -> check (error.code = "missing_group")
       "Measure missing-group diagnostic"
   | Ok _ -> fail "Measure accepted a missing primitive group");
  (match try ignore (Sop.box ()
      |> Sop.measure ~name:" " Rdk.Analysis.Area); None
    with Invalid_argument message -> Some message with
   | Some message -> check (contains message "empty attribute name")
       "Measure empty-name validation"
   | None -> fail "Measure accepted an empty attribute name");
  let rough_graph = Sop.grid ~columns:12 ~rows:10 ~size:4. ()
      |> Sop.noise_displace ~seed:77 ~amplitude:0.7 ~frequency:0.8 in
  let rough = cook_ok evaluator current rough_graph in
  let smooth = rough_graph
      |> Sop.attribute_blur ~iterations:4 ~attributes:"P"
           ~method_:Rdk.Attribute_ops.Edge_length
           ~mode:(Rdk.Attribute_ops.Laplacian 0.35)
      |> cook_ok evaluator current in
  check (not (equal_positions rough.geometry smooth.geometry))
    "procedural Attribute Blur did not smooth P";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "N"
      smooth.geometry = None) "procedural Attribute Blur retained stale normals";
  let restricted_blur = rough_graph
      |> Sop.group ~name:"blur_center"
           (Select.points_in_bounds ~min:(Vec3.create (-1.) (-10.) (-1.))
              ~max:(Vec3.create 1. 10. 1.))
      |> Sop.attribute_blur ~group:"blur_center" ~iterations:2 ~attributes:"P"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count restricted_blur.geometry
      = Rdk.Geometry.point_count rough.geometry)
    "procedural restricted Attribute Blur cardinality";
  let missing_blur_group = rough_graph
      |> Sop.attribute_blur ~group:"missing" ~attributes:"P" in
  (match Session.cook evaluator ~context:current missing_blur_group with
   | Error error -> check (error.code = "missing_group")
       "Attribute Blur missing-group diagnostic"
   | Ok _ -> fail "Attribute Blur accepted a missing point group");
  (match try ignore (rough_graph
      |> Sop.attribute_blur ~attributes:"broken["); None
    with Invalid_argument message -> Some message with
   | Some message -> check (contains message "Attribute_pattern")
       "Attribute Blur pattern validation"
   | None -> fail "Attribute Blur accepted a malformed attribute pattern");
  let modeled_smooth = rough_graph
      |> Sop.group ~name:"smooth_faces" Select.all_primitives
      |> Sop.group_unshared ~owner:Rdk.Group_ops.Group_points ~name:"smooth_locks"
      |> Sop.smooth ~group:"smooth_faces" ~constrained_points:"smooth_locks"
           ~boundary:Rdk.Smooth.Smooth_group_boundary ~iterations:4
           ~method_:Rdk.Attribute_ops.Edge_length
           ~mode:(Rdk.Attribute_ops.Custom_steps { odd = 0.42; even = -0.44 })
           ~attributes:"P"
      |> cook_ok evaluator current in
  check (not (equal_positions rough.geometry modeled_smooth.geometry))
    "procedural Smooth did not update selected interior points";
  check (Rdk.Geometry.point_count modeled_smooth.geometry
      = Rdk.Geometry.point_count rough.geometry)
    "procedural Smooth changed topology cardinality";
  let missing_smooth_group = rough_graph
      |> Sop.smooth ~group:"missing" ~attributes:"P" in
  (match Session.cook evaluator ~context:current missing_smooth_group with
   | Error error -> check (error.code = "missing_group")
       "Smooth missing primitive-group diagnostic"
   | Ok _ -> fail "Smooth accepted a missing primitive group");
  let missing_smooth_locks = rough_graph
      |> Sop.smooth ~constrained_points:"missing" ~attributes:"P" in
  (match Session.cook evaluator ~context:current missing_smooth_locks with
   | Error error -> check (error.code = "missing_constrained_points")
       "Smooth missing constrained-point diagnostic"
   | Ok _ -> fail "Smooth accepted a missing constrained point group");
  (match try ignore (rough_graph |> Sop.smooth ~attributes:"broken["); None
    with Invalid_argument message -> Some message with
   | Some message -> check (contains message "Attribute_pattern")
       "Smooth pattern validation"
   | None -> fail "Smooth accepted a malformed attribute pattern");
  let ray_collision = Sop.grid ~columns:16 ~rows:12 ~size:4. ()
      |> Sop.noise_displace ~seed:79 ~amplitude:0.4 ~frequency:0.7
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red
      |> Sop.group ~name:"collision_faces" Select.all_primitives in
  let ray_graph = Sop.grid ~columns:16 ~rows:12 ~size:4. ()
      |> Sop.transform (Mat4.translation (Vec3.create 0. 2. 0.))
      |> Sop.ray ~collision:ray_collision ~collision_group:"collision_faces"
           ~direction:(Rdk.Ray.Ray_vector (Vec3.neg Vec3.unit_y))
           ~samples:5 ~jitter_scale:0.08 ~seed:313
           ~combine:Rdk.Ray.Ray_average
           ~distance_attribute:"ray_distance" ~hit_group:"ray_hits"
           ~point_pattern:"Cd" in
  check (Node.version ray_graph = 2
      && contains (Node.parameters ray_graph) "samples=5"
      && contains (Node.parameters ray_graph) "combine=average"
      && contains (Node.parameters ray_graph) "seed=313")
    "procedural multi-sample Ray identity";
  let ray_output = cook_ok evaluator current ray_graph in
  check (Array.for_all (fun distance -> distance >= 0.)
      (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point
          "ray_distance" ray_output.geometry with
       | Some attribute ->
           (match Rdk.Attribute.Private.storage attribute with
            | Rdk.Attribute.Float values -> values
            | _ -> fail "procedural Ray distance storage")
       | None -> fail "procedural Ray distance missing"))
    "procedural Ray unexpectedly missed";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "Cd"
      ray_output.geometry <> None)
    "procedural Ray did not import collision color";
  let missing_ray_selection = rough_graph
      |> Sop.ray ~selection:(Sop.Point_group "missing")
           ~collision:ray_collision in
  (match Session.cook evaluator ~context:current missing_ray_selection with
   | Error error -> check (error.code = "missing_group")
       "Ray missing source-group diagnostic"
   | Ok _ -> fail "Ray accepted a missing source group");
  let missing_ray_collision = rough_graph
      |> Sop.ray ~collision_group:"missing" ~collision:ray_collision in
  (match Session.cook evaluator ~context:current missing_ray_collision with
   | Error error -> check (error.code = "missing_collision_group")
       "Ray missing collision-group diagnostic"
   | Ok _ -> fail "Ray accepted a missing collision group");
  (match try ignore (rough_graph
      |> Sop.ray ~point_pattern:"broken[" ~collision:ray_collision); None
    with Invalid_argument message -> Some message with
   | Some message -> check (contains message "Attribute_pattern")
       "Ray pattern validation"
   | None -> fail "Ray accepted a malformed attribute pattern");
  let peak_source = Sop.grid ~columns:10 ~rows:8 ~size:4. ()
      |> Sop.group ~name:"peak_center"
           (Select.points_in_bounds ~min:(Vec3.create (-1.) (-1.) (-1.))
              ~max:(Vec3.create 1. 1. 1.)) in
  let peak_input = cook_ok evaluator current peak_source in
  let peaked = peak_source
      |> Sop.peak ~selection:(Sop.Point_group "peak_center") ~distance:0.4
           ~recompute_normals:true
      |> cook_ok evaluator current in
  check (not (equal_positions peak_input.geometry peaked.geometry))
    "procedural Peak did not move its selected points";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "N"
      peaked.geometry <> None) "procedural Peak did not recompute normals";
  let missing_peak_group = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.peak ~selection:(Sop.Edge_group "missing") ~distance:1. in
  (match Session.cook evaluator ~context:current missing_peak_group with
   | Error error -> check (error.code = "missing_group")
       "Peak missing-edge-group diagnostic"
   | Ok _ -> fail "Peak accepted a missing edge group");
  let mountain_graph = Sop.grid ~columns:20 ~rows:16 ~size:5. ()
      |> Sop.mountain ~label:"seeded-mountain" ~height:0.7
           ~frequency:(Vec3.create 0.4 0.8 0.55) ~octaves:5
           ~height_attribute:"mountain_height" in
  let mountain_a = cook_ok evaluator (context ~seed:201L ()) mountain_graph
  and mountain_b = cook_ok evaluator (context ~seed:202L ()) mountain_graph in
  check (not (equal_positions mountain_a.geometry mountain_b.geometry))
    "procedural Mountain ignored its context-seed dependency";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point
      "mountain_height" mountain_a.geometry <> None)
    "procedural Mountain did not publish its height attribute";
  let fixed_mountain = Sop.grid ~columns:20 ~rows:16 ~size:5. ()
      |> Sop.mountain ~seed:19 ~height:0.7 ~octaves:5 in
  let fixed_a = cook_ok evaluator (context ~seed:1L ()) fixed_mountain
  and fixed_b = cook_ok evaluator (context ~seed:2L ()) fixed_mountain in
  check (equal_positions fixed_a.geometry fixed_b.geometry)
    "explicit Mountain seed retained a context dependency";
  let jitter_source = Sop.grid ~columns:4 ~rows:3 ~size:3. ()
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"jitter_mask" 0.5
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"pscale" 2.
      |> Sop.set_int ~owner:Rdk.Attribute.Point ~name:"stable_id" 17
      |> Sop.group ~name:"jitter_points" (Select.point_indices [|0; 1|]) in
  let jitter_graph = jitter_source
      |> Sop.point_jitter ~label:"solver-step" ~group:"jitter_points"
           ~mask_attribute:"jitter_mask" ~id_attribute:"stable_id"
           ~use_point_scale:true ~scale:0.8
           ~axis_scales:(Vec3.create 1. 0.5 0.25) in
  check (Node.version jitter_graph = 1
      && contains (Node.parameters jitter_graph) "group=jitter_points"
      && contains (Node.parameters jitter_graph) "seed=context"
      && contains (Node.parameters jitter_graph) "use_point_scale=true")
    "procedural Point Jitter omitted cache identity parameters";
  let jitter_input = cook_ok evaluator current jitter_source
  and jitter_a = cook_ok evaluator (context ~seed:301L ()) jitter_graph
  and jitter_b = cook_ok evaluator (context ~seed:302L ()) jitter_graph in
  check (not (equal_positions jitter_a.geometry jitter_b.geometry))
    "procedural Point Jitter ignored its context-seed dependency";
  let source_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions jitter_input.geometry)
  and jitter_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions jitter_a.geometry) in
  for point = 0 to Array.length source_positions.x - 1 do
    let changed = source_positions.x.(point) <> jitter_positions.x.(point)
        || source_positions.y.(point) <> jitter_positions.y.(point)
        || source_positions.z.(point) <> jitter_positions.z.(point) in
    check (changed = (point = 0 || point = 1))
      (Printf.sprintf "procedural Point Jitter selection at point %d" point)
  done;
  let fixed_jitter = jitter_source
      |> Sop.point_jitter ~label:"fixed-step" ~seed:19 ~scale:0.8 in
  let fixed_jitter_a = cook_ok evaluator (context ~seed:1L ()) fixed_jitter
  and fixed_jitter_b = cook_ok evaluator (context ~seed:2L ()) fixed_jitter in
  check (equal_positions fixed_jitter_a.geometry fixed_jitter_b.geometry)
    "explicit Point Jitter seed retained a context dependency";
  let missing_jitter_group = jitter_source
      |> Sop.point_jitter ~group:"absent" ~seed:1 ~scale:1. in
  (match Session.cook evaluator ~context:current missing_jitter_group with
   | Error error -> check (error.code = "missing_group")
       "Point Jitter missing-group diagnostic"
   | Ok _ -> fail "Point Jitter accepted a missing group");
  let randomized_graph = Sop.grid ~columns:8 ~rows:6 ~size:4. ()
      |> Sop.attribute_randomize ~label:"random-values"
           ~owner:Rdk.Attribute.Point ~name:"value"
           (Rdk.Attribute_ops.Random_uniform {
             min = Rdk.Attribute_ops.Scalar (-2.);
             max = Rdk.Attribute_ops.Scalar 3.;
           })
      |> Sop.attribute_remap ~owner:Rdk.Attribute.Point ~name:"value"
           ~into:"mapped" ~input:Rdk.Attribute_ops.Remap_auto
           ~output_min:(Rdk.Attribute_ops.Scalar 0.)
           ~output_max:(Rdk.Attribute_ops.Scalar 1.) in
  let random_a = cook_ok evaluator (context ~seed:101L ()) randomized_graph
  and random_b = cook_ok evaluator (context ~seed:102L ()) randomized_graph in
  let float_attribute name geometry =
    match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point name geometry with
    | Some attribute ->
        (match Rdk.Attribute.storage attribute with
         | Rdk.Attribute.Float values -> values
         | _ -> fail ("procedural attribute has wrong storage: " ^ name))
    | None -> fail ("procedural attribute is missing: " ^ name) in
  let values_a = float_attribute "value" random_a.geometry
  and values_b = float_attribute "value" random_b.geometry
  and mapped = float_attribute "mapped" random_a.geometry in
  check (values_a <> values_b)
    "procedural Attribute Randomize ignored its context-seed dependency";
  check (Array.for_all (fun value -> value >= 0. && value <= 1.) mapped)
    "procedural Attribute Remap escaped its output range";
  let explicit_random = Sop.grid ~columns:8 ~rows:6 ~size:4. ()
      |> Sop.attribute_randomize ~seed:77 ~owner:Rdk.Attribute.Point
           ~name:"fixed" (Rdk.Attribute_ops.Random_normal {
             middle = Rdk.Attribute_ops.Scalar 0.;
             scale = Rdk.Attribute_ops.Scalar 1.;
           }) in
  let fixed_a = cook_ok evaluator (context ~seed:1L ()) explicit_random
  and fixed_b = cook_ok evaluator (context ~seed:2L ()) explicit_random in
  check (float_attribute "fixed" fixed_a.geometry
      = float_attribute "fixed" fixed_b.geometry)
    "explicit Attribute Randomize seed retained a context dependency";
  let orient_graph = Sop.point_generate_origin ~points:32 ()
      |> Sop.attribute_noise ~label:"orient-noise" ~seed:91
           ~owner:Rdk.Attribute.Point ~name:"orient"
           ~location:Rdk.Attribute_ops.Noise_element_number
           ~range:Rdk.Attribute_ops.Noise_zero_centered
           ~frequency:(Vec3.create 0.13 0.13 0.13) ~octaves:2
           Rdk.Attribute_ops.Noise_quaternion in
  let orient_a = cook_ok evaluator (context ~seed:1L ()) orient_graph
  and orient_b = cook_ok evaluator (context ~seed:999L ()) orient_graph in
  check (orient_a.geometry == orient_b.geometry)
    "explicit Attribute Noise seed retained a context dependency";
  let orient_values = match Rdk.Geometry.find_attribute
      ~owner:Rdk.Attribute.Point "orient" orient_a.geometry with
    | Some attribute ->
        (match Rdk.Attribute.storage attribute with
         | Rdk.Attribute.Float4 values -> Rdk.Packed.Float4.Private.view values
         | _ -> fail "Attribute Noise produced non-quaternion orient storage")
    | None -> fail "Attribute Noise omitted orient" in
  for point = 0 to Array.length orient_values.x - 1 do
    let length = sqrt ((orient_values.x.(point) ** 2.)
        +. (orient_values.y.(point) ** 2.) +. (orient_values.z.(point) ** 2.)
        +. (orient_values.w.(point) ** 2.)) in
    check (abs_float (length -. 1.) < 1e-12)
      (Printf.sprintf "Attribute Noise orient %d is not normalized" point)
  done;
  let fraction_attribute = Rdk.Attribute.create_owned ~name:"fraction"
      ~owner:Rdk.Attribute.Point (Rdk.Attribute.Float [|0.; 0.25; 0.5; 0.75; 1.|])
      |> get_ok in
  let fraction_geometry = Rdk.Line_geometry.points (Array.make 5 (0., 0., 0.))
      |> Rdk.Geometry.with_attribute fraction_attribute |> get_ok in
  let fraction_graph = Sop.snapshot fraction_geometry
      |> Sop.attribute_randomize ~fraction_attribute:"fraction"
           ~owner:Rdk.Attribute.Point ~name:"quantile"
           (Rdk.Attribute_ops.Random_custom_ramp {
             ramp = [0., 0.; 0.5, 0.2; 1., 1.];
             fit_min = Rdk.Attribute_ops.Scalar 10.;
             fit_max = Rdk.Attribute_ops.Scalar 20.;
           }) in
  let fraction_a = cook_ok evaluator (context ~seed:1L ()) fraction_graph
  and fraction_b = cook_ok evaluator (context ~seed:999L ()) fraction_graph in
  check (fraction_a.geometry == fraction_b.geometry)
    "fraction Attribute Randomize retained a context-seed dependency";
  check (float_attribute "quantile" fraction_a.geometry
      = [|10.; 11.; 12.; 16.; 20.|])
    "procedural fraction Attribute Randomize quantiles";
  let limited_graph = Sop.snapshot fraction_geometry
      |> Sop.attribute_randomize ~fraction_attribute:"fraction"
           ~minimum:(Rdk.Attribute_ops.Scalar (-2.))
           ~maximum:(Rdk.Attribute_ops.Scalar 2.)
           ~owner:Rdk.Attribute.Point ~name:"limited"
           (Rdk.Attribute_ops.Random_normal {
             middle = Rdk.Attribute_ops.Scalar 0.;
             scale = Rdk.Attribute_ops.Scalar 1.;
           }) in
  check (Node.version limited_graph = 2)
    "Attribute Randomize node version did not include the extended contract";
  let limited = cook_ok evaluator current limited_graph
      |> fun output -> float_attribute "limited" output.geometry in
  check (limited.(0) = -2. && limited.(2) = 0. && limited.(4) = 2.)
    "procedural Attribute Randomize tail limits";
  let typed_text = Sop.grid ~connectivity:Rdk.Plane_generators.Grid_triangles
      ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.group ~name:"first_face" (Select.primitive_indices [|0|])
      |> Sop.attribute_randomize
           ~selection:(Sop.Primitive_group "first_face") ~seed:71
           ~owner:Rdk.Attribute.Point ~name:"region"
           (Rdk.Attribute_ops.Random_custom_discrete_text ["marked", 1.]) in
  let typed_text = cook_ok evaluator current typed_text in
  let regions = match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point
      "region" typed_text.geometry with
    | Some attribute ->
        (match Rdk.Attribute.storage attribute with
         | Rdk.Attribute.Text values -> values
         | _ -> fail "typed Attribute Randomize text storage")
    | None -> fail "typed Attribute Randomize text output missing" in
  check (Array.exists (String.equal "marked") regions
      && Array.exists (String.equal "") regions)
    "typed Attribute Randomize selection was not promoted to points";
  (match try ignore (Sop.snapshot fraction_geometry
      |> Sop.attribute_randomize ~seed:1 ~fraction_attribute:"fraction"
           ~owner:Rdk.Attribute.Point ~name:"bad"
           (Rdk.Attribute_ops.Random_uniform {
             min = Rdk.Attribute_ops.Scalar 0.;
             max = Rdk.Attribute_ops.Scalar 1.;
           })); None
    with Invalid_argument message -> Some message with
   | Some message -> check (contains message "does not accept seed")
       "fraction Attribute Randomize seed validation"
   | None -> fail "fraction Attribute Randomize accepted an explicit seed");
  (match try ignore (Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.attribute_randomize ~group:"a"
           ~selection:(Sop.Point_group "b") ~owner:Rdk.Attribute.Point
           ~name:"bad" (Rdk.Attribute_ops.Random_constant
             (Rdk.Attribute_ops.Scalar 1.))); None
    with Invalid_argument message -> Some message with
   | Some message -> check (contains message "mutually exclusive")
       "Attribute Randomize typed/group exclusivity"
   | None -> fail "Attribute Randomize accepted two group selectors");
  let missing_randomize_group = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.attribute_randomize ~group:"missing" ~owner:Rdk.Attribute.Point
           ~name:"value" (Rdk.Attribute_ops.Random_constant
             (Rdk.Attribute_ops.Scalar 1.)) in
  (match Session.cook evaluator ~context:current missing_randomize_group with
   | Error error -> check (error.code = "missing_group")
       "Attribute Randomize missing-group diagnostic"
   | Ok _ -> fail "Attribute Randomize accepted a missing point group");
  (match try ignore (Sop.points [|(0., 0., 0.)|]
      |> Sop.attribute_remap ~owner:Rdk.Attribute.Point ~name:" "
           ~input:Rdk.Attribute_ops.Remap_auto
           ~output_min:(Rdk.Attribute_ops.Scalar 0.)
           ~output_max:(Rdk.Attribute_ops.Scalar 1.)); None
    with Invalid_argument message -> Some message with
   | Some message -> check (contains message "empty source attribute")
       "Attribute Remap empty-name validation"
   | None -> fail "Attribute Remap accepted an empty attribute name");
  let extruded = Sop.grid ~columns:3 ~rows:2 ~size:2. ()
      |> Sop.group ~name:"extrude_faces" Select.all_primitives
      |> Sop.poly_extrude ~group:"extrude_faces"
           ~divide:Rdk.Poly_extrude.Extrude_connected_components ~divisions:2
           ~front_group:"extrude_front" ~back_group:"extrude_back"
           ~side_group:"extrude_side" ~front_boundary_group:"front_rim"
           ~back_boundary_group:"back_rim" ~distance:0.3
      |> cook_ok evaluator current in
  let primitive_group_size name =
    Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive name extruded.geometry
    |> Option.map Rdk.Group.cardinality |> Option.value ~default:(-1)
  and edge_group_size name =
    Rdk.Geometry.find_edge_group name extruded.geometry
    |> Option.map Rdk.Edge_group.cardinality |> Option.value ~default:(-1) in
  check (Rdk.Geometry.point_count extruded.geometry = 36
      && Rdk.Geometry.primitive_count extruded.geometry = 44
      && primitive_group_size "extrude_front" = 12
      && primitive_group_size "extrude_back" = 12
      && primitive_group_size "extrude_side" = 20
      && edge_group_size "front_rim" = 10
      && edge_group_size "back_rim" = 10)
    "procedural connected poly extrude groups/cardinality";
  let missing_extrude_group = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.poly_extrude ~group:"missing_faces"
           ~divide:Rdk.Poly_extrude.Extrude_connected_components ~distance:0.3 in
  (match Session.cook evaluator ~context:current missing_extrude_group with
   | Error error -> check (error.code = "missing_group")
       "Poly Extrude missing primitive-group diagnostic"
   | Ok _ -> fail "Poly Extrude accepted a missing primitive group");
  let cleaned = Sop.snapshot
      (Rdk.Line_geometry.points [|(nan, 0., 0.); (0., 0., 0.); (0., 0., 0.)|])
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"temporary" 1.
      |> Sop.group_random ~seed:1 ~probability:0.
           ~owner:Rdk.Group_ops.Group_points ~name:"empty"
      |> Sop.clean ~remove_degenerate:false ~remove_nan_points:true
           ~consolidate_distance:0. ~delete_unused_groups:true
           ~point_attributes:"temporary"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count cleaned.geometry = 1
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "temporary"
         cleaned.geometry = None
      && Rdk.Geometry.find_group ~owner:Rdk.Group.Point "empty"
         cleaned.geometry = None)
    "procedural Clean pipeline";
  let facet_node = Sop.grid ~columns:2 ~rows:1 ~uv_attribute:"uv" ~size:2. ()
      |> Sop.facet ~pre_compute_normals:true ~make_normals_unit_length:true
           ~unique_points:true ~orient_polygons:true ~reverse_normals:true in
  check (contains (Node.parameters facet_node) "unique_points=true"
      && contains (Node.parameters facet_node) "orient_polygons=true"
      && contains (Node.parameters facet_node) "reverse_normals=true")
    "Facet node parameter identity";
  let faceted = facet_node |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count faceted.geometry = 12
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "N"
           faceted.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "uv"
           faceted.geometry <> None)
    "procedural Facet Unique Points pipeline";
  let grouped_facet_input = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.group ~name:"facet_faces" (Select.primitive_indices [|0|]) in
  let grouped_facet_node = grouped_facet_input
      |> Sop.facet ~group:"facet_faces" ~unique_points:true in
  check (contains (Node.parameters grouped_facet_node)
      "selection=primitive:facet_faces"
      && not (Node.id grouped_facet_node = Node.id facet_node))
    "grouped Facet node parameter identity";
  let equivalent_group_node = grouped_facet_input
    |> Sop.facet ~selection:(Sop.Primitive_group "facet_faces")
         ~unique_points:true in
  check (Node.parameters equivalent_group_node
      = Node.parameters grouped_facet_node)
    "Facet primitive convenience and typed selection have different parameters";
  let grouped_facet = grouped_facet_node |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count grouped_facet.geometry = 8
      && Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "facet_faces"
           grouped_facet.geometry <> None)
    "procedural grouped Facet Unique Points";
  let missing_facet_group = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.facet ~group:"missing_faces" ~unique_points:true in
  (match Session.cook evaluator ~context:current missing_facet_group with
   | Error error -> check (error.code = "missing_group")
       "Facet missing primitive-group diagnostic"
   | Ok _ -> fail "Facet accepted a missing primitive group");
  let point_facet_node = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.group ~name:"facet_points" (Select.point_indices [|0|])
      |> Sop.facet ~selection:(Sop.Point_group "facet_points")
           ~unique_points:true in
  check (contains (Node.parameters point_facet_node)
      "selection=point:facet_points")
    "point-selected Facet parameter identity";
  let point_faceted = point_facet_node |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count point_faceted.geometry > 6
      && Rdk.Geometry.point_count point_faceted.geometry < 12)
    "procedural point-selected Facet promotion";
  let missing_point_group = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.facet ~selection:(Sop.Point_group "missing_points")
           ~unique_points:true in
  (match Session.cook evaluator ~context:current missing_point_group with
   | Error error -> check (error.code = "missing_group")
       "Facet missing typed-group diagnostic"
   | Ok _ -> fail "Facet accepted a missing typed group");
  let planar_positions = Rdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;1.;1.|] ~z:[|0.;0.;0.5;0.|] in
  let planar_topology = Rdk.Topology.polygons_owned ~point_count:4
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;4|]
      |> Result.get_ok in
  let planar_geometry = Rdk.Geometry.create ~positions:planar_positions
      ~topology:planar_topology () |> Result.get_ok in
  let planar_node = Sop.snapshot planar_geometry |> Sop.facet ~make_planar:true in
  check (contains (Node.parameters planar_node) "make_planar=true")
    "Facet Make Planar parameter identity";
  let planar = planar_node |> cook_ok evaluator current in
  let positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions planar.geometry) in
  let ux = positions.x.(1) -. positions.x.(0)
  and uy = positions.y.(1) -. positions.y.(0)
  and uz = positions.z.(1) -. positions.z.(0)
  and vx = positions.x.(2) -. positions.x.(0)
  and vy = positions.y.(2) -. positions.y.(0)
  and vz = positions.z.(2) -. positions.z.(0)
  and wx = positions.x.(3) -. positions.x.(0)
  and wy = positions.y.(3) -. positions.y.(0)
  and wz = positions.z.(3) -. positions.z.(0) in
  let determinant = wx *. ((uy *. vz) -. (uz *. vy))
      +. wy *. ((uz *. vx) -. (ux *. vz))
      +. wz *. ((ux *. vy) -. (uy *. vx)) in
  check (abs_float determinant <= 1e-12)
    "procedural Facet Make Planar output";
  let inline_positions = Rdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;2.;0.|] ~y:[|0.;0.;0.;0.;0.|]
      ~z:[|0.;0.;0.;2.;2.|] in
  let inline_topology = Rdk.Topology.polygons_owned ~point_count:5
      ~vertex_points:[|0;1;2;3;4|] ~primitive_offsets:[|0;5|]
      |> Result.get_ok in
  let inline_geometry = Rdk.Geometry.create ~positions:inline_positions
      ~topology:inline_topology () |> Result.get_ok in
  let inline_node = Sop.snapshot inline_geometry
      |> Sop.facet ~remove_inline_points:true ~inline_distance:0. in
  check (contains (Node.parameters inline_node) "remove_inline_points=true"
      && contains (Node.parameters inline_node) "inline_distance=0")
    "Facet inline parameter identity";
  let inline = inline_node |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count inline.geometry = 4
      && Rdk.Geometry.vertex_count inline.geometry = 4)
    "procedural Facet Remove Inline Points";
  let normal_geometry = Rdk.Line_geometry.points [|(0.,0.,0.); (0.,0.,0.)|]
      |> Rdk.Geometry.with_attribute
        (Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"N"
          (Rdk.Attribute.Float3 (Rdk.Packed.Float3.Private.of_owned_exn
            ~x:[|1.;0.|] ~y:[|0.;1.|] ~z:[|0.;0.|])) |> Result.get_ok)
      |> Result.get_ok in
  let normal_node = Sop.snapshot normal_geometry
      |> Sop.facet ~consolidate_normals_distance:0. in
  check (contains (Node.parameters normal_node)
      "consolidate_normals_distance=0")
    "Facet normal consolidation parameter identity";
  let consolidated_normals = normal_node |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "N"
      consolidated_normals.geometry with
   | Some attribute ->
       (match Rdk.Attribute.storage attribute with
        | Rdk.Attribute.Float3 values ->
            check (Rdk.Packed.Float3.get values 0 = (0.5, 0.5, 0.)
                && Rdk.Packed.Float3.get values 1 = (0.5, 0.5, 0.))
              "procedural Facet Consolidate Normals values"
        | _ -> fail "procedural Facet Consolidate Normals storage")
   | None -> fail "procedural Facet Consolidate Normals lost N");
  let cusp_node = Sop.box ~connectivity:Rdk.Box_generator.Box_quads
      ~consolidate_points:true ~size:(Vec3.create 2. 2. 2.) ()
      |> Sop.facet ~cusp_angle:1. ~post_compute_normals:true in
  check (contains (Node.parameters cusp_node)
      "cusp_angle=4607182418800017408")
    "Facet cusp parameter identity";
  let cusped = cusp_node |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count cusped.geometry = 24
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "N"
           cusped.geometry <> None)
    "procedural Facet Cusp Polygons";
  let fused_mirror = Sop.box ()
      |> Sop.fuse ~tolerance:1e-9
      |> Sop.mirror ~origin:Vec3.zero ~normal:Vec3.unit_x
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count fused_mirror.geometry = 16
      && Rdk.Geometry.primitive_count fused_mirror.geometry = 24)
    "procedural fuse/mirror cardinality";
  let fuse_target = Sop.points [|(0.,0.,0.); (1.,0.,0.); (3.,0.,0.)|]
      |> Sop.group ~name:"targets" (Select.point_indices [|0;1|]) in
  let targeted_fuse = Sop.points
      [|(0.1,0.,0.); (0.9,0.,0.); (2.,0.,0.); (5.,0.,0.)|]
      |> Sop.group ~name:"queries" (Select.point_indices [|0;1;2|])
      |> Sop.fuse ~group:"queries" ~target_group:"targets"
           ~target:fuse_target ~using:Rdk.Fuse_grid.Closest_target_point
           ~tolerance:1. ~fuse_points:false ~snapped_group:"snapped"
           ~snapped_destination_attribute:"destination" in
  check (Node.version targeted_fuse = 6
      && contains (Node.parameters targeted_fuse) "target_group=targets"
      && contains (Node.parameters targeted_fuse) "using=closest"
      && contains (Node.parameters targeted_fuse) "target=true")
    "procedural targeted Fuse identity";
  let rule_input = Sop.points [|(0.,0.,0.); (0.,0.,0.)|] in
  let average_rule = Rdk.Fuse_grid.fuse_attribute_rule ~pattern:"Cd"
      Rdk.Fuse_reduce.Attribute_average
  and sum_rule = Rdk.Fuse_grid.fuse_attribute_rule ~pattern:"Cd"
      Rdk.Fuse_reduce.Attribute_sum
  and union_rule = Rdk.Fuse_grid.fuse_group_rule ~pattern:"selected*"
      Rdk.Fuse_reduce.Group_union in
  let average_node = Sop.fuse ~attribute_rules:[average_rule]
      ~group_rules:[union_rule] rule_input
  and sum_node = Sop.fuse ~attribute_rules:[sum_rule]
      ~group_rules:[union_rule] rule_input in
  check (Node.parameters average_node <> Node.parameters sum_node
      && contains (Node.parameters average_node) "Cd,average"
      && contains (Node.parameters average_node) "selected*,union")
    "procedural Fuse rules are absent from node cache identity";
  let targeted = cook_ok evaluator current targeted_fuse in
  let targeted_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions targeted.geometry) in
  check (targeted_positions.x = [|0.;1.;1.;5.|])
    "procedural targeted Fuse positions";
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "destination"
      targeted.geometry with
   | Some attribute ->
       (match Rdk.Attribute.storage attribute with
        | Rdk.Attribute.Int values ->
            check (values = [|0;1;1;-1|])
              "procedural targeted Fuse destination"
        | _ -> fail "procedural targeted Fuse destination storage")
   | None -> fail "procedural targeted Fuse destination missing");
  let missing_target_group = Sop.points [|(0.,0.,0.)|]
      |> Sop.fuse ~target:fuse_target ~target_group:"missing" in
  (match Session.cook evaluator ~context:current missing_target_group with
   | Error error -> check (error.code = "missing_group")
       "targeted Fuse missing target-group diagnostic"
   | Ok _ -> fail "targeted Fuse accepted a missing target group");
  let grid_snapped = Sop.points [|(0.2,0.,0.); (0.3,0.,0.); (1.2,0.,0.)|]
      |> Sop.group ~name:"snap_points" (Select.point_indices [|0;1|])
      |> Sop.snap_to_grid ~group:"snap_points" ~fuse_points:true
           ~snapped_group:"snapped"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count grid_snapped.geometry = 2)
    "procedural grid snap/fuse cardinality";
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "snapped"
      grid_snapped.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 1)
       "procedural grid snapped group"
   | None -> fail "procedural grid snapped group missing");
  let missing_snap_group = Sop.points [|(0.2,0.,0.)|]
      |> Sop.snap_to_grid ~group:"missing" in
  (match Session.cook evaluator ~context:current missing_snap_group with
   | Error error -> check (error.code = "missing_group")
       "grid snap missing-group diagnostic"
   | Ok _ -> fail "grid snap accepted a missing point group");
  let clip_node = Sop.box ~size:(Vec3.create 2. 2. 2.) ()
      |> Sop.fuse ~tolerance:0. ~attributes:Rdk.Fuse_reduce.Average_numeric
      |> Sop.clip ~keep:Rdk.Plane_clip.Above ~fill:true ~distance:0.25
           ~clipped_edge_group:"clip_edges" ~cap_group:"cap"
           ~origin:Vec3.zero ~normal:Vec3.unit_y
  in
  check (Node.version clip_node = 5
      && contains (Node.parameters clip_node) "clip_attribute=P"
      && contains (Node.parameters clip_node) "distance=4598175219545276416"
      && contains (Node.parameters clip_node) "selection=all"
      && contains (Node.parameters clip_node) "replace_existing_groups=true"
      && contains (Node.parameters clip_node) "clipped_edge_group=clip_edges")
    "procedural Clip extended parameter identity";
  let clipped = cook_ok evaluator current clip_node in
  let clipped_bounds = Rdk.Analysis.bounds clipped.geometry |> Option.get in
  check (abs_float (clipped_bounds.min.y -. 0.25) < 1e-12
      && abs_float (clipped_bounds.max.y -. 1.) < 1e-12)
    "procedural filled clip bounds";
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "cap"
      clipped.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 1)
       "procedural clip cap group"
   | None -> fail "procedural clip cap group missing");
  (match Rdk.Geometry.find_edge_group "clip_edges" clipped.geometry with
   | Some group -> check (Rdk.Edge_group.cardinality group > 0)
       "procedural clipped edge group"
   | None -> fail "procedural clipped edge group missing");
  let selected_clip = Sop.box ~size:(Vec3.create 2. 2. 2.) ()
      |> Sop.fuse ~tolerance:0. ~attributes:Rdk.Fuse_reduce.Average_numeric
      |> Sop.group ~name:"clip_all" Select.all_primitives
      |> Sop.clip ~selection:(Sop.Primitive_group "clip_all")
           ~origin:Vec3.zero ~normal:Vec3.unit_y in
  check (contains (Node.parameters selected_clip) "selection=primitive:clip_all")
    "procedural Clip selection parameter identity";
  let selected_clip = cook_ok evaluator current selected_clip in
  check (abs_float ((Rdk.Analysis.bounds selected_clip.geometry
      |> Option.get).min.y) < 1e-12)
    "procedural selected Clip result";
  let missing_clip = Sop.box ~size:(Vec3.create 1. 1. 1.) ()
      |> Sop.clip ~selection:(Sop.Edge_group "missing")
           ~origin:Vec3.zero ~normal:Vec3.unit_x in
  (match Session.cook evaluator ~context:current missing_clip with
   | Error error -> check (error.code = "missing_group")
       "procedural Clip missing-selection diagnostic"
   | Ok _ -> fail "procedural Clip accepted a missing selection group");
  let promoted = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"weight" 3.
      |> Sop.promote_attributes ~source:Rdk.Attribute.Point
           ~destination:Rdk.Attribute.Primitive ~pattern:"weight"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "weight"
      promoted.geometry = None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "weight"
         promoted.geometry <> None)
    "procedural attribute promotion ownership";
  let promoted_pattern = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"weight" 3.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"skip" 7.
      |> Sop.promote_attributes ~delete_source:false
           ~source:Rdk.Attribute.Point ~destination:Rdk.Attribute.Primitive
           ~pattern:"* ^skip"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "weight"
      promoted_pattern.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "skip"
         promoted_pattern.geometry = None)
    "procedural pattern attribute promotion";
  let renamed_promotions = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"weight_a" 3.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"weight_b" 7.
      |> Sop.promote_attributes ~method_:Rdk.Attribute_ops.First
           ~source:Rdk.Attribute.Point
           ~destination:Rdk.Attribute.Primitive ~pattern:"weight_*"
           ~into_pattern:"reduced_*" ~index_pattern:"source_*"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "weight_a"
      renamed_promotions.geometry = None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "reduced_a"
         renamed_promotions.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "reduced_b"
         renamed_promotions.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "source_a"
         renamed_promotions.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "source_b"
         renamed_promotions.geometry <> None)
    "procedural pattern promotion capture rename";
  let multi_promotion = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"a_weight" 3.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"b_weight" 7.
      |> Sop.promote_attributes ~method_:Rdk.Attribute_ops.First
           ~source:Rdk.Attribute.Point ~destination:Rdk.Attribute.Detail
           ~pattern:"a_* b_*" ~into_pattern:"left_* right_*"
           ~index_pattern:"left_source_* right_source_*" in
  check (Node.version multi_promotion = 5)
    "procedural multi-term promotion version";
  let multi_promotion = cook_ok evaluator current multi_promotion in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Detail "left_weight"
      multi_promotion.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Detail "right_weight"
         multi_promotion.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Detail
           "left_source_weight" multi_promotion.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Detail
           "right_source_weight" multi_promotion.geometry <> None)
    "procedural multi-term promotion capture rename";
  (match (try Some (Sop.grid ~columns:1 ~rows:1 ~size:1. ()
        |> Sop.promote_attributes ~source:Rdk.Attribute.Point
             ~destination:Rdk.Attribute.Detail ~pattern:"weight*"
             ~index_pattern:"source*") with Invalid_argument _ -> None) with
   | None -> ()
   | Some _ -> fail "procedural average promotion accepted source-index output");
  let piece_geometry = Rdk.Line_geometry.points
      [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.); (3., 0., 0.)|] in
  let piece_values = Rdk.Attribute.create_owned ~name:"value"
      ~owner:Rdk.Attribute.Point (Rdk.Attribute.Int [|8; 2; 8; 2|]) |> get_ok
  and piece_ids = Rdk.Attribute.create_owned ~name:"piece"
      ~owner:Rdk.Attribute.Point (Rdk.Attribute.Int [|1; 1; 1; 1|]) |> get_ok in
  let piece_geometry = piece_geometry
      |> Rdk.Geometry.with_attribute piece_values |> get_ok
      |> Rdk.Geometry.with_attribute piece_ids |> get_ok in
  let piece_promoted = Sop.snapshot piece_geometry
      |> Sop.promote_attributes ~method_:Rdk.Attribute_ops.Mode
           ~piece_attribute:"piece" ~into_pattern:"piece_mode"
           ~delete_source:false ~index_pattern:"piece_source"
           ~source:Rdk.Attribute.Point ~destination:Rdk.Attribute.Point
           ~pattern:"value"
      |> cook_ok evaluator current in
  let piece_modes = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point
      "piece_mode" piece_promoted.geometry |> Option.get
      |> Rdk.Attribute.get (Rdk.Attribute.key ~name:"piece_mode"
        ~owner:Rdk.Attribute.Point Rdk.Attribute.int) |> Option.get
  and piece_sources = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point
      "piece_source" piece_promoted.geometry |> Option.get
      |> Rdk.Attribute.get (Rdk.Attribute.key ~name:"piece_source"
        ~owner:Rdk.Attribute.Point Rdk.Attribute.int) |> Option.get in
  check (piece_modes = [|2; 2; 2; 2|]
      && piece_sources = [|1; 1; 1; 1|])
    "procedural piece attribute mode/index promotion";
  let transfer_source = Sop.points [|(-1., -1., 0.); (1., 1., 0.)|]
      |> Sop.color_by_height ~low:Color.blue ~high:Color.red in
  let transferred = Sop.attribute_transfer ~pattern:"C*"
      ~mode:(Rdk.Attribute_ops.Inverse_distance { neighbors = 2; power = 1. })
      ~max_distance:3. ~source:transfer_source
      ~target:(Sop.points [|(0., 0., 0.)|]) ()
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "Cd"
      transferred.geometry with
   | Some attribute ->
       (match Rdk.Attribute.storage attribute with
        | Rdk.Attribute.Float4 values ->
            let values = Rdk.Packed.Float4.Private.view values in
            check (values.x.(0) = 0.5 && values.z.(0) = 0.5)
              "procedural weighted attribute transfer"
        | _ -> fail "procedural transfer Cd storage")
   | None -> fail "procedural attribute transfer missing Cd");
  let kernel_transfer = Sop.attribute_transfer ~pattern:"C*"
      ~mode:(Rdk.Attribute_ops.Kernel {
        neighbors=2; radius=3.; kernel=Rdk.Attribute_ops.Hart })
      ~max_distance:3. ~source:transfer_source
      ~target:(Sop.points [|(0., 0., 0.)|]) () in
  check (Node.version kernel_transfer = 6
      && contains (Node.parameters kernel_transfer) "mode=kernel:2:"
      && contains (Node.parameters kernel_transfer) ":hart")
    "procedural kernel transfer identity";
  let kernel_transferred = cook_ok evaluator current kernel_transfer in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "Cd"
      kernel_transferred.geometry with
   | Some attribute ->
       (match Rdk.Attribute.storage attribute with
        | Rdk.Attribute.Float4 values ->
            let values = Rdk.Packed.Float4.Private.view values in
            check (values.x.(0) = 0.5 && values.z.(0) = 0.5)
              "procedural kernel attribute transfer"
        | _ -> fail "procedural kernel transfer Cd storage")
   | None -> fail "procedural kernel transfer missing Cd");
  let grouped_source = Rdk.Line_geometry.points
      [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.)|] in
  let grouped_weight = Rdk.Attribute.create_owned ~name:"weight"
      ~owner:Rdk.Attribute.Point (Rdk.Attribute.Float [|10.; 20.; 30.|])
      |> Result.get_ok
  and source_left = Rdk.Group.init ~owner:Rdk.Group.Point ~name:"source_left" 3
      (fun point -> point = 0)
  and source_right = Rdk.Group.init ~owner:Rdk.Group.Point ~name:"source_right" 3
      (fun point -> point = 2) in
  let grouped_source = grouped_source
      |> Rdk.Geometry.with_attribute grouped_weight |> Result.get_ok
      |> Rdk.Geometry.with_group source_left |> Result.get_ok
      |> Rdk.Geometry.with_group source_right |> Result.get_ok in
  let grouped_target = Rdk.Line_geometry.points
      [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.)|] in
  let target_weight = Rdk.Attribute.create_owned ~name:"weight"
      ~owner:Rdk.Attribute.Point (Rdk.Attribute.Float [|100.; 100.; 100.|])
      |> Result.get_ok
  and target_left = Rdk.Group.init ~owner:Rdk.Group.Point ~name:"target_left" 3
      (fun point -> point = 0)
  and target_right = Rdk.Group.init ~owner:Rdk.Group.Point ~name:"target_right" 3
      (fun point -> point = 2) in
  let grouped_target = grouped_target
      |> Rdk.Geometry.with_attribute target_weight |> Result.get_ok
      |> Rdk.Geometry.with_group target_left |> Result.get_ok
      |> Rdk.Geometry.with_group target_right |> Result.get_ok in
  let directly_copied = Sop.attribute_copy ~group_owner:Rdk.Group.Point
      ~source_group_pattern:"source_*" ~target_group_pattern:"target_*"
      ~rules:[Rdk.Attribute_ops.copy_rule ~owner:Rdk.Attribute.Point "weight"]
      ~source:(Sop.snapshot grouped_source) ~target:(Sop.snapshot grouped_target) ()
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "weight"
      directly_copied.geometry with
   | Some attribute ->
       (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Float values -> check (values = [|10.; 100.; 30.|])
            "procedural Attribute Copy group-pattern union"
        | _ -> fail "procedural Attribute Copy storage")
   | None -> fail "procedural Attribute Copy missing weight");
  (match (try Some (Sop.attribute_copy ~group_owner:Rdk.Group.Point ~rules:[]
      ~source:(Sop.snapshot grouped_source) ~target:(Sop.snapshot grouped_target) ())
    with Invalid_argument _ -> None) with
   | None -> ()
   | Some _ -> fail "procedural Attribute Copy accepted no rules");
  let interpolation_source = Rdk.Plane_generators.grid ~columns:1 ~rows:1 ~size:2. ()
      |> Result.get_ok in
  let source_weight = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"weight" (Rdk.Attribute.Float [|0.;10.;20.;30.|])
      |> Result.get_ok in
  let interpolation_source = Rdk.Geometry.with_attribute source_weight
      interpolation_source |> Result.get_ok in
  let hot = Rdk.Group.ordered ~owner:Rdk.Group.Point ~name:"hot"
      ~length:(Rdk.Geometry.point_count interpolation_source) [|2|]
      |> Result.get_ok in
  let interpolation_source = Rdk.Geometry.with_group hot interpolation_source
      |> Result.get_ok in
  let interpolation_target = Rdk.Line_geometry.points
      [|(0.,0.,0.); (0.,0.,0.); (0.,0.,0.)|] in
  let primitive_driver = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"source_primitive" (Rdk.Attribute.Int [|0;0;0|])
      |> Result.get_ok
  and uvw_driver = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"source_uvw" (Rdk.Attribute.Float3
        (Rdk.Packed.Float3.Private.of_owned_exn
          ~x:[|0.;0.25;1.|] ~y:[|0.;0.25;0.|] ~z:[|0.;0.;0.|]))
      |> Result.get_ok
  and interpolation_group = Rdk.Group.ordered ~owner:Rdk.Group.Point
      ~name:"interpolate_selected" ~length:3 [|0;2|] |> Result.get_ok in
  let interpolation_target = interpolation_target
      |> Rdk.Geometry.with_attribute primitive_driver |> Result.get_ok
      |> Rdk.Geometry.with_attribute uvw_driver |> Result.get_ok
      |> Rdk.Geometry.with_group interpolation_group |> Result.get_ok in
  let interpolated = Sop.attribute_interpolate
      ~group_pattern:"interpolate_*" ~target_owner:Rdk.Attribute.Point
      ~compute_weights:{
        Rdk.Attribute_ops.computed_owner=Rdk.Attribute.Point;
        computed_numbers_attribute="computed_points";
        computed_weights_attribute="computed_weights" }
      ~attributes:[Rdk.Attribute_ops.interpolate_attribute
        ~owner:Rdk.Attribute.Point "weight"]
      ~source:(Sop.snapshot interpolation_source)
      ~target:(Sop.snapshot interpolation_target) ()
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "weight"
      interpolated.geometry with
   | Some attribute ->
       (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Float values -> check (values = [|0.;0.;20.|])
            "procedural Attribute Interpolate group-pattern cook"
        | _ -> fail "procedural Attribute Interpolate storage")
   | None -> fail "procedural Attribute Interpolate missing output");
  let weighted = Sop.attribute_interpolate
      ~group_pattern:"interpolate_*" ~target_owner:Rdk.Attribute.Point
      ~driver:(Rdk.Attribute_ops.Point_weights {
        numbers_attribute="computed_points";
        weights_attribute="computed_weights" })
      ~point_pattern:"weight hot" ~match_groups:true ~attributes:[]
      ~source:(Sop.snapshot interpolation_source)
      ~target:(Sop.snapshot interpolated.geometry) ()
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "weight"
      weighted.geometry with
   | Some attribute ->
       (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Float values -> check (values = [|0.;0.;20.|])
            "procedural weighted Attribute Interpolate cook"
        | _ -> fail "procedural weighted Attribute Interpolate storage")
   | None -> fail "procedural weighted Attribute Interpolate missing output");
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "hot" weighted.geometry with
   | Some group -> check
       (Array.init 3 (fun point -> Rdk.Group.mem point group)
          = [|false;false;true|])
       "procedural weighted Attribute Interpolate group matching"
   | None -> fail "procedural weighted Attribute Interpolate missing group");
  (match (try Some (Sop.attribute_interpolate
      ~group:"interpolate_selected" ~group_pattern:"interpolate_*"
      ~target_owner:Rdk.Attribute.Point ~attributes:[]
      ~source:(Sop.snapshot interpolation_source)
      ~target:(Sop.snapshot interpolation_target) ())
    with Invalid_argument _ -> None) with
   | None -> ()
   | Some _ -> fail
       "procedural Attribute Interpolate accepted conflicting groups");
  let patterned = Sop.attribute_transfer ~names:["weight"]
      ~source_group_pattern:"source_*" ~target_group_pattern:"target_*"
      ~source:(Sop.snapshot grouped_source) ~target:(Sop.snapshot grouped_target) ()
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "weight"
      patterned.geometry with
   | Some attribute ->
       (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Float values -> check (values = [|10.; 100.; 30.|])
            "procedural Attribute Transfer group-pattern union"
        | _ -> fail "procedural patterned transfer storage")
   | None -> fail "procedural patterned transfer missing weight");
  (match (try Some (Sop.attribute_transfer ~source_group:"source_left"
      ~source_group_pattern:"source_*" ~source:(Sop.snapshot grouped_source)
      ~target:(Sop.snapshot grouped_target) ()) with Invalid_argument _ -> None) with
   | None -> ()
   | Some _ -> fail "procedural transfer accepted exact and patterned source groups");
  (match (try Some (Sop.attribute_transfer ~source_group_pattern:"bad["
      ~source:(Sop.snapshot grouped_source) ~target:(Sop.snapshot grouped_target) ())
    with Invalid_argument _ -> None) with
   | None -> ()
   | Some _ -> fail "procedural transfer accepted malformed group pattern");
  let multi_source = Sop.grid ~columns:1 ~rows:1 ~size:2. ()
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"point_value" 10.
      |> Sop.set_float ~owner:Rdk.Attribute.Vertex ~name:"vertex_value" 20.
      |> Sop.set_float ~owner:Rdk.Attribute.Primitive ~name:"primitive_value" 30.
      |> Sop.set_int ~owner:Rdk.Attribute.Detail ~name:"detail_value" 40 in
  let multi = Sop.attribute_transfer_all ~point_pattern:"point_*"
      ~vertex_pattern:"vertex_*" ~primitive_pattern:"primitive_*"
      ~detail_pattern:"detail_*" ~source:multi_source
      ~target:(Sop.grid ~columns:1 ~rows:1 ~size:2. ()) ()
      |> cook_ok evaluator current in
  List.iter (fun (owner, name) ->
    check (Rdk.Geometry.find_attribute ~owner name multi.geometry <> None)
      ("procedural multi-owner transfer missing " ^ name))
    [Rdk.Attribute.Point, "point_value";
     Rdk.Attribute.Vertex, "vertex_value";
     Rdk.Attribute.Primitive, "primitive_value";
     Rdk.Attribute.Detail, "detail_value"];
  (match (try Some (Sop.attribute_transfer_all ~source:multi_source
      ~target:multi_source ()) with Invalid_argument _ -> None) with
   | None -> ()
   | Some _ -> fail "procedural multi-owner transfer accepted no owner patterns");
  let custom = Sop.custom ~label:"custom-shift" ~operation:"custom_shift"
      ~version:3 ~parameters:"x=2" [Sop.points [|(0., 0., 0.)|]]
      (fun ~context:_ inputs -> Ok (Rdk.Transform_ops.transform
        (Mat4.translation (Vec3.create 2. 0. 0.)) inputs.(0))) in
  let custom_output = cook_ok evaluator current custom in
  let custom_x, _, _ = Rdk.Packed.Float3.get
      (Rdk.Geometry.positions custom_output.geometry) 0 in
  check (custom_x = 2. && Node.version custom = 3
      && Node.parameters custom = "x=2")
    "inspectable custom RDK node";
  let renamed = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.group ~name:"old" Select.all_points
      |> Sop.group ~name:"old" Select.all_primitives
      |> Sop.group_rename ~rules:[{
           Rdk.Group_ops.rename_owner = Some Rdk.Group_ops.Group_points;
           rename_pattern = "old"; rename_replacement = "new";
           rename_conflict = Rdk.Group_ops.Rename_error }]
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_group ~owner:Rdk.Group.Point "old" renamed.geometry = None
      && Rdk.Geometry.find_group ~owner:Rdk.Group.Point "new" renamed.geometry <> None
      && Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "old"
         renamed.geometry <> None)
    "owner-scoped group rename";
  let expanded_groups = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.group ~name:"seed_face" (Select.primitive_indices [|0|])
      |> Sop.group_expand ~name:"component" ~flood:true
           ~step_attribute:"group_step"
           ~primitive_connectivity:Rdk.Group_ops.Primitive_share_edges
           ~owner:Rdk.Group_ops.Group_primitives ~group:"seed_face"
      |> Sop.group_promotions [Rdk.Group_ops.promotion_rule
           ~new_name:"component_points" ~keep_original:true
           ~source:Rdk.Group_ops.Group_primitives
           ~destination:Rdk.Group_ops.Group_points ~pattern:"component" ()]
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "component"
      expanded_groups.geometry,
      Rdk.Geometry.find_group ~owner:Rdk.Group.Point "component_points"
        expanded_groups.geometry with
   | Some primitives, Some points ->
       check (Rdk.Group.cardinality primitives = 4
           && Rdk.Group.cardinality points = 6
           && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive
              "group_step" expanded_groups.geometry <> None)
         "procedural Group Expand/Promote topology component"
   | _ -> fail "procedural Group Expand/Promote dropped an output group");
  let constrained_geometry = Rdk.Plane_generators.grid ~connectivity:Rdk.Plane_generators.Grid_quads
      ~columns:3 ~rows:1 ~size:3. () |> get_ok in
  let region = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Primitive
      ~name:"region" (Rdk.Attribute.Int [|0;0;1|]) |> get_ok in
  let constrained_geometry = Rdk.Geometry.with_attribute region constrained_geometry
      |> get_ok in
  let seed = Rdk.Group.init ~grain:1 ~owner:Rdk.Group.Primitive
      ~name:"seed_face" 3 (fun primitive -> primitive = 0) in
  let constrained_geometry = Rdk.Geometry.with_group seed constrained_geometry
      |> get_ok in
  let constrained_node = Sop.snapshot constrained_geometry
      |> Sop.group_expand ~flood:true ~step_attribute:"constraint_step"
           ~primitive_connectivity:Rdk.Group_ops.Primitive_share_edges
           ~normal_spread:0.1
           ~connectivity_attributes:[{
             Rdk.Group_ops.boundary_attribute_owner = Rdk.Attribute.Primitive;
             boundary_attribute_pattern = "region" }]
           ~owner:Rdk.Group_ops.Group_primitives ~group:"seed_face" in
  check (Node.version constrained_node = 2
      && contains (Node.parameters constrained_node) "normal_spread="
      && contains (Node.parameters constrained_node)
           "connectivity_attributes=primitive:\"region\""
      && contains (Node.parameters constrained_node)
           "primitive_connectivity=share_edges")
    "procedural constrained Group Expand cache identity";
  let constrained_output = cook_ok evaluator current constrained_node in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "seed_face"
      constrained_output.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 2
         && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive
              "constraint_step" constrained_output.geometry <> None)
       "procedural constrained Group Expand behavior"
   | None -> fail "procedural constrained Group Expand dropped output");
  (match try Some (Sop.snapshot constrained_geometry
      |> Sop.group_expand ~connectivity_attributes:[{
           Rdk.Group_ops.boundary_attribute_owner = Rdk.Attribute.Primitive;
           boundary_attribute_pattern = "region" }]
           ~owner:Rdk.Group_ops.Group_primitives ~group:"seed_face")
    with Invalid_argument _ -> None with
   | None -> ()
   | Some _ -> fail
       "procedural Group Expand accepted constrained point-sharing primitives");
  let missing_collision = Sop.snapshot constrained_geometry
      |> Sop.group_expand ~primitive_connectivity:Rdk.Group_ops.Primitive_share_edges
           ~collision:{
             Rdk.Group_ops.expand_collision_owner = Rdk.Group_ops.Group_primitives;
             expand_collision_group = "missing";
             expand_collision_contain = false;
             expand_collision_allow_boundary = false }
           ~owner:Rdk.Group_ops.Group_primitives ~group:"seed_face" in
  (match Session.cook evaluator ~context:current missing_collision with
   | Error error -> check (error.code = "invalid_group")
       "procedural Group Expand missing-collision diagnostic"
   | Ok _ -> fail "procedural Group Expand cooked a missing collision group");
  let promoted_mask = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.group ~name:"seed" (Select.point_indices [|0; 1|])
      |> Sop.group_promotions [Rdk.Group_ops.promotion_rule
           ~new_name:"face_mask" ~output_as_attribute:true
           ~source:Rdk.Group_ops.Group_points
           ~destination:Rdk.Group_ops.Group_primitives ~pattern:"seed" ()]
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive
      "face_mask" promoted_mask.geometry <> None
      && Rdk.Geometry.find_group ~owner:Rdk.Group.Point "seed"
         promoted_mask.geometry = None)
    "procedural Group Promote integer-mask output";
  let promoted_boundary = Sop.grid ~columns:1 ~rows:1 ~size:2. ()
      |> Sop.group ~name:"first_face" (Select.primitive_indices [|0|])
      |> Sop.group_promote_boundary ~keep_original:true ~name:"outline"
           ~source:Rdk.Group_ops.Group_primitives
           ~destination:Rdk.Group_ops.Group_edges ~group:"first_face"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_edge_group "outline" promoted_boundary.geometry with
   | Some group -> check (Rdk.Edge_group.cardinality group = 1)
       "procedural Group Promote Boundary"
   | None -> fail "procedural Group Promote Boundary dropped output");
  let promotion_source = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.group ~name:"region_a" (Select.primitive_indices [|0|])
      |> Sop.group ~name:"region_b" (Select.primitive_indices [|1|]) in
  let promotion_rules = [
    Rdk.Group_ops.promotion_rule ~new_name:"points_*" ~keep_original:true
      ~source:Rdk.Group_ops.Group_primitives ~destination:Rdk.Group_ops.Group_points
      ~pattern:"region_*" ();
    Rdk.Group_ops.boundary_promotion_rule ~new_name:"outline_*"
      ~keep_original:true ~source:Rdk.Group_ops.Group_primitives
      ~destination:Rdk.Group_ops.Group_edges ~pattern:"region_*" ();
  ] in
  let promotions_node = Sop.group_promotions promotion_rules promotion_source in
  check (Node.operation promotions_node = "group_promotions"
      && Node.version promotions_node = 1
      && contains (Node.parameters promotions_node) "count=2"
      && contains (Node.parameters promotions_node) "pattern=\"region_*\""
      && contains (Node.parameters promotions_node) "boundary")
    "procedural Group Promotions cache identity";
  let disabled_promotions = Sop.group_promotions [
      Rdk.Group_ops.promotion_rule ~source:Rdk.Group_ops.Group_points
        ~destination:Rdk.Group_ops.Group_edges ~pattern:" " ()] promotion_source in
  check (disabled_promotions == promotion_source)
    "procedural Group Promotions disabled rules lost node identity";
  let promotions = cook_ok evaluator current promotions_node in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "points_a"
      promotions.geometry,
      Rdk.Geometry.find_group ~owner:Rdk.Group.Point "points_b"
        promotions.geometry,
      Rdk.Geometry.find_edge_group "outline_a" promotions.geometry,
      Rdk.Geometry.find_edge_group "outline_b" promotions.geometry with
   | Some points_a, Some points_b, Some outline_a, Some outline_b ->
       check (Rdk.Group.cardinality points_a > 0
           && Rdk.Group.cardinality points_b > 0
           && Rdk.Edge_group.cardinality outline_a > 0
           && Rdk.Edge_group.cardinality outline_b > 0)
         "procedural ordered wildcard Group Promotions"
   | _ -> fail "procedural Group Promotions dropped wildcard outputs");
  let edge_expansion = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.group_edges ~name:"boundary" ~incidence:Rdk.Group_mesh.Boundary_edge
      |> Sop.group_expand ~name:"edge_ring" ~steps:1
           ~owner:Rdk.Group_ops.Group_edges ~group:"boundary"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_edge_group "boundary" edge_expansion.geometry,
      Rdk.Geometry.find_edge_group "edge_ring" edge_expansion.geometry with
   | Some boundary, Some expanded ->
       check (Rdk.Edge_group.cardinality expanded
           > Rdk.Edge_group.cardinality boundary)
         "procedural native edge Group Expand"
   | _ -> fail "procedural edge Group Expand dropped source/output");
  let edge_depth = Sop.grid ~columns:4 ~rows:3 ~size:2. ()
      |> Sop.group ~name:"depth_seed" (Select.point_indices [|0|])
      |> Sop.group_edge_depth ~depth:2 ~point_group:"depth_seed"
           ~name:"depth_points"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "depth_seed"
      edge_depth.geometry,
      Rdk.Geometry.find_group ~owner:Rdk.Group.Point "depth_points"
        edge_depth.geometry with
   | Some seed, Some grown ->
       check (Rdk.Group.cardinality seed = 1
           && Rdk.Group.cardinality grown > Rdk.Group.cardinality seed)
         "procedural Group Edge Depth"
   | _ -> fail "procedural Group Edge Depth dropped seed/output");
  let boundaries = Sop.grid ~columns:3 ~rows:2 ~size:2. ()
      |> Sop.group_unshared ~owner:Rdk.Group_ops.Group_edges ~name:"outer_edges"
      |> Sop.group_unshared ~owner:Rdk.Group_ops.Group_points ~name:"outer_points"
      |> Sop.group_boundary_components ~prefix:"border"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_edge_group "outer_edges" boundaries.geometry,
      Rdk.Geometry.find_group ~owner:Rdk.Group.Point "outer_points"
        boundaries.geometry,
      Rdk.Geometry.find_group ~owner:Rdk.Group.Point "border__0"
        boundaries.geometry with
   | Some edges, Some points, Some component ->
       check (Rdk.Edge_group.cardinality edges = 10
           && Rdk.Group.cardinality points = 10
           && Rdk.Group.cardinality component = 10)
         "procedural unshared/boundary component groups"
   | _ -> fail "procedural unshared/boundary output missing");
  let incident_edges = Sop.polyline
      [|(-1., 0., 0.); (0., 0., 0.); (0., 1., 0.)|]
      |> Sop.group_edges ~name:"right_angle"
           ~angle_basis:Rdk.Group_mesh.Incident_edges
           ~min_angle:(Float.pi /. 2.) ~max_angle:(Float.pi /. 2.)
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_edge_group "right_angle" incident_edges.geometry with
   | Some group -> check (Rdk.Edge_group.cardinality group = 2)
       "procedural incident-edge angle selection"
   | None -> fail "procedural incident-edge angle group missing");
  let missing_group_promote = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.group_promotions [Rdk.Group_ops.promotion_rule
           ~source:Rdk.Group_ops.Group_points
           ~destination:Rdk.Group_ops.Group_primitives ~pattern:"missing" ()]
      |> cook_ok evaluator current in
  check (Rdk.Geometry.groups missing_group_promote.geometry = [])
    "Group Promotions unmatched pattern changed groups";
  let group_catalog = Sop.points (Array.init 10 (fun point ->
      float_of_int point, 0., 0.))
      |> Sop.group ~name:"ends" (Select.point_indices [|0; 9|])
      |> Sop.group_range ~owner:Rdk.Group_ops.Group_points ~name:"middle"
           (Rdk.Group_ops.Range_start_end { start = 2; end_ = 7 })
      |> Sop.group_combine ~owner:Rdk.Group_ops.Group_points ~name:"selected"
           ~base:{ Rdk.Group_ops.pattern = "ends"; inverted = false }
           ~steps:[{ Rdk.Group_ops.operation = Rdk.Group_ops.Group_union;
             operand = { pattern = "middle"; inverted = false } }]
      |> Sop.group_invert ~owner:Rdk.Group_ops.Group_points ~pattern:"selected"
           ~new_name:"outside"
      |> Sop.group_rename ~rules:[
           { Rdk.Group_ops.rename_owner = Some Rdk.Group_ops.Group_points;
             rename_pattern = "outside"; rename_replacement = "kept";
             rename_conflict = Rdk.Group_ops.Rename_error }]
      |> Sop.group_delete ~rules:[
           { Rdk.Group_ops.delete_owner = Some Rdk.Group_ops.Group_points;
             delete_pattern = "ends middle" }]
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "kept"
      group_catalog.geometry with
   | Some group ->
       check (Rdk.Group.cardinality group = 2
           && Rdk.Group.mem 1 group && Rdk.Group.mem 8 group
           && List.map Rdk.Group.name (Rdk.Geometry.groups group_catalog.geometry)
              = ["kept"])
         "procedural Group Range/Combine/Invert/Rename/Delete pipeline"
   | None -> fail "procedural group catalog pipeline dropped output");
  let connected_range = Sop.merge [
      Sop.polyline [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.);
        (3., 0., 0.)|];
      Sop.polyline [|(10., 0., 0.); (11., 0., 0.); (12., 0., 0.)|]
    ]
      |> Sop.group_range ~owner:Rdk.Group_ops.Group_points ~name:"local_second"
           ~connectivity:(Rdk.Group_ops.Range_disconnected { region = None })
           (Rdk.Group_ops.Range_start_end { start = 1; end_ = 1 })
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "local_second"
      connected_range.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 2
         && Rdk.Group.mem 1 group && Rdk.Group.mem 5 group)
       "procedural disconnected Group Range"
   | None -> fail "procedural disconnected Group Range dropped output");
  let collision = {
    Rdk.Group_ops.collision_owner = Rdk.Group_ops.Group_points;
    collision_pattern = "cut_side";
    keep_boundary = true;
  } in
  let advanced_range_node = Sop.polyline [|
      (0., 0., 0.); (1., 0., 0.); (2., 0., 0.); (3., 0., 0.)
    |]
      |> Sop.group ~name:"cut_side" (Select.point_indices [|0; 1|])
      |> Sop.group_range ~owner:Rdk.Group_ops.Group_points ~name:"piece_first"
           ~connectivity:(Rdk.Group_ops.Range_connected {
             connectivity_attributes = None;
             connectivity_tolerance = 1e-6;
             collision = Some collision;
             region = None;
             remove_other_regions = false })
           (Rdk.Group_ops.Range_start_end { start = 0; end_ = 0 }) in
  check (Node.version advanced_range_node = 3
      && contains (Node.parameters advanced_range_node)
           "connected:none:0:point:\"cut_side\":true"
      && contains (Node.parameters advanced_range_node) ":all:true")
    "procedural Group Range advanced cache identity";
  let equivalent_range_node = Sop.polyline [|
      (0., 0., 0.); (1., 0., 0.); (2., 0., 0.); (3., 0., 0.)
    |]
      |> Sop.group ~name:"cut_side" (Select.point_indices [|0; 1|])
      |> Sop.group_range ~owner:Rdk.Group_ops.Group_points ~name:"piece_first"
           ~connectivity:(Rdk.Group_ops.Range_connected {
             connectivity_attributes = Some "  ";
             connectivity_tolerance = 99.;
             collision = Some collision;
             region = None;
             remove_other_regions = true })
           (Rdk.Group_ops.Range_start_end { start = 0; end_ = 0 }) in
  check (Node.parameters equivalent_range_node
      = Node.parameters advanced_range_node)
    "procedural Group Range retained semantically irrelevant cache parameters";
  let changed_range_node = Sop.polyline [|
      (0., 0., 0.); (1., 0., 0.); (2., 0., 0.); (3., 0., 0.)
    |]
      |> Sop.group ~name:"cut_side" (Select.point_indices [|0; 1|])
      |> Sop.group_range ~owner:Rdk.Group_ops.Group_points ~name:"piece_first"
           ~connectivity:(Rdk.Group_ops.Range_connected {
             connectivity_attributes = Some "P";
             connectivity_tolerance = 0.25;
             collision = Some { collision with keep_boundary = false };
             region = Some 0;
             remove_other_regions = false })
           (Rdk.Group_ops.Range_start_end { start = 0; end_ = 0 }) in
  check (Node.parameters changed_range_node
      <> Node.parameters advanced_range_node
      && contains (Node.parameters changed_range_node) "\"P\":0.25"
      && contains (Node.parameters changed_range_node) ":false:0:false")
    "procedural Group Range omitted meaningful advanced cache parameters";
  let advanced_range = cook_ok evaluator current advanced_range_node in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "piece_first"
      advanced_range.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 2
         && Rdk.Group.mem 0 group && Rdk.Group.mem 2 group)
       "procedural collision-connected Group Range"
   | None -> fail "procedural advanced Group Range dropped output");
  let multi_source = Sop.points (Array.init 10 (fun point ->
      float_of_int point, 0., 0.)) in
  let multi_rules = [
    Rdk.Group_ops.range_rule ~owner:Rdk.Group_ops.Group_points ~name:"first"
      (Rdk.Group_ops.Range_start_end { start = 0; end_ = 4 });
    Rdk.Group_ops.range_rule ~base:"first" ~owner:Rdk.Group_ops.Group_points
      ~name:"middle" (Rdk.Group_ops.Range_start_end { start = 2; end_ = 3 });
    Rdk.Group_ops.range_rule ~owner:Rdk.Group_ops.Group_points ~name:" "
      (Rdk.Group_ops.Range_start_end { start = 99; end_ = 99 });
  ] in
  let multi_node = Sop.group_ranges multi_rules multi_source in
  check (Node.operation multi_node = "group_ranges"
      && Node.version multi_node = 1
      && contains (Node.parameters multi_node) "count=2"
      && not (contains (Node.parameters multi_node) "start_end:99:99"))
    "procedural Group Ranges cache identity retained a disabled slot";
  let no_op_multi = Sop.group_ranges [List.nth multi_rules 2] multi_source in
  check (no_op_multi == multi_source)
    "procedural Group Ranges all-disabled node lost graph identity";
  let multi = cook_ok evaluator current multi_node in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "first" multi.geometry,
      Rdk.Geometry.find_group ~owner:Rdk.Group.Point "middle" multi.geometry with
   | Some first, Some middle ->
       check (Rdk.Group.cardinality first = 5
           && Rdk.Group.cardinality middle = 2
           && Rdk.Group.mem 2 middle && Rdk.Group.mem 3 middle)
         "procedural ordered Group Ranges output"
   | _ -> fail "procedural Group Ranges dropped output");
  let random_points = Sop.points (Array.init 64 (fun point ->
      float_of_int point, 0., 0.))
      |> Sop.group_random ~seed:73 ~probability:0.37
           ~owner:Rdk.Group_ops.Group_points ~name:"random"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "random"
      random_points.geometry with
   | Some group ->
       let seed = Rand.seed 73 in
       for point = 0 to 63 do
         check (Rdk.Group.mem point group
             = (Rand.float_at seed ~index:point < 0.37))
           "procedural Group Random indexed membership"
       done
   | None -> fail "Group Random dropped its procedural output");
  let missing_random_base = Sop.points [|(0., 0., 0.)|]
      |> Sop.group_random ~base:"missing" ~probability:0.5
           ~owner:Rdk.Group_ops.Group_points ~name:"random" in
  (match Session.cook evaluator ~context:current missing_random_base with
   | Error error -> check (error.code = "invalid_group")
       "Group Random missing-base diagnostic"
   | Ok _ -> fail "Group Random accepted a missing base group");
  let bounded_points = Sop.points
      [|(-2., 0., 0.); (-1., 0., 0.); (0., 0., 0.); (1., 0., 0.);
        (2., 0., 0.)|]
      |> Sop.group_bounds (Rdk.Group_ops.Bounds_sphere {
           center = Vec3.zero; radius = 1. })
           ~owner:Rdk.Group_ops.Group_points ~name:"bounded"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "bounded"
      bounded_points.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 3
         && Rdk.Group.mem 1 group && Rdk.Group.mem 2 group
         && Rdk.Group.mem 3 group)
       "procedural Group Bounds inclusive sphere"
   | None -> fail "Group Bounds dropped its procedural output");
  let upward = Sop.box ~size:(Vec3.create 2. 2. 2.) ()
      |> Sop.group_normal ~direction:Vec3.unit_y ~spread_angle:0.
           ~owner:Rdk.Group_ops.Group_primitives ~name:"upward"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "upward"
      upward.geometry with
   | Some group -> check (Rdk.Group.cardinality group > 0
         && Rdk.Group.cardinality group < Rdk.Geometry.primitive_count upward.geometry)
       "procedural Group Normal primitive selection"
   | None -> fail "Group Normal dropped its procedural output");
  let positions = Rdk.Packed.Float3.Builder.create 4 in
  Rdk.Packed.Float3.Builder.set positions 0 0. 0. 0.;
  Rdk.Packed.Float3.Builder.set positions 1 1. 0. 0.;
  Rdk.Packed.Float3.Builder.set positions 2 1. 0.2 1.;
  Rdk.Packed.Float3.Builder.set positions 3 0. 0. 1.;
  let topology = Rdk.Topology.Builder.create ~point_count:4 () in
  Rdk.Topology.Builder.add_polygon topology [|0; 1; 2; 3|];
  let warped_geometry = Rdk.Geometry.create
      ~positions:(Rdk.Packed.Float3.Builder.freeze positions)
      ~topology:(Rdk.Topology.Builder.freeze topology) () |> Result.get_ok in
  let non_planar = Sop.snapshot warped_geometry
      |> Sop.group_non_planar ~tolerance:0.01 ~name:"warped"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "warped"
      non_planar.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 1)
       "procedural Group Non-Planar selection"
   | None -> fail "Group Non-Planar dropped its procedural output");
  let visible = Sop.box ~size:(Vec3.create 2. 2. 2.) ()
      |> Sop.group ~name:"visible" Select.all_primitives
      |> Sop.group_backface ~merge:Rdk.Group_ops.Group_subtract
           ~viewpoint:(Vec3.create 0. 0. 5.) ~name:"visible"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "visible"
      visible.geometry with
   | Some group -> check (Rdk.Group.cardinality group > 0
         && Rdk.Group.cardinality group < Rdk.Geometry.primitive_count visible.geometry)
       "procedural Group Backface subtraction"
   | None -> fail "Group Backface dropped its procedural output");
  let copied_groups = Sop.group_copy
      ~rules:[{ Rdk.Group_ops.copy_owner = Rdk.Group_ops.Group_points;
        copy_pattern = "picked"; copy_prefix = "source_";
        match_attribute = None }]
      ~source:(Sop.points [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
        |> Sop.group ~name:"picked" (Select.point_indices [|1|]))
      ~target:(Sop.points [|(0.,1.,0.); (1.,1.,0.); (2.,1.,0.)|]) ()
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "source_picked"
      copied_groups.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 1
         && Rdk.Group.mem 1 group) "procedural Group Copy two-input mapping"
   | None -> fail "procedural Group Copy dropped output");
  let transferred_groups = Sop.group_transfer ~distance:0.2
      ~rules:[{ Rdk.Group_ops.transfer_owner = Rdk.Group_ops.Group_points;
        transfer_pattern = "picked"; transfer_prefix = "near_" }]
      ~source:(Sop.points [|(0.,0.,0.); (10.,0.,0.)|]
        |> Sop.group ~name:"picked" (Select.point_indices [|0|]))
      ~target:(Sop.points [|(0.1,0.,0.); (9.9,0.,0.)|]) ()
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "near_picked"
      transferred_groups.geometry with
   | Some group -> check (Rdk.Group.cardinality group = 1
         && Rdk.Group.mem 0 group) "procedural Group Transfer proximity"
   | None -> fail "procedural Group Transfer dropped output");
  let invalid_transfer = Sop.group_transfer ~distance:(-1.)
      ~source:(Sop.points [|(0.,0.,0.)|]
        |> Sop.group ~name:"picked" (Select.point_indices [|0|]))
      ~target:(Sop.points [|(0.,0.,0.)|]) () in
  (match Session.cook evaluator ~context:current invalid_transfer with
   | Error error -> check (error.code = "invalid_group")
       "Group Transfer invalid-distance diagnostic"
   | Ok _ -> fail "procedural Group Transfer accepted negative distance");
  let waypoints = [|0; 8|] in
  let path_source = Sop.grid ~columns:2 ~rows:2 ~size:2. ()
      |> Sop.ordered_group ~owner:Rdk.Group.Point ~name:"waypoints" waypoints in
  waypoints.(0) <- 4;
  let path_output = path_source
      |> Sop.group_find_path ~base_group:"waypoints" ~name:"path"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "path"
      path_output.geometry with
   | Some group ->
       let order = Rdk.Group.ordered_elements group |> Option.get in
       check (Array.length order >= 2 && order.(0) = 0
           && order.(Array.length order - 1) = 8)
         "procedural Group Find Path ordered endpoints"
   | None -> fail "procedural Group Find Path dropped output");
  let primitive_path = Sop.grid ~columns:2 ~rows:2 ~size:2. ()
      |> Sop.ordered_group ~owner:Rdk.Group.Primitive ~name:"face_waypoints"
           [|0; 7|]
      |> Sop.group_find_path ~owner:Rdk.Group.Primitive
           ~base_group:"face_waypoints" ~name:"face_path"
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "face_path"
      primitive_path.geometry with
   | Some group ->
       let order = Rdk.Group.ordered_elements group |> Option.get in
       check (Array.length order >= 2 && order.(0) = 0
           && order.(Array.length order - 1) = 7)
         "procedural primitive Group Find Path ordered endpoints"
   | None -> fail "procedural primitive Group Find Path dropped output");
  let missing_path = Sop.grid ~columns:2 ~rows:2 ~size:2. ()
      |> Sop.group_find_path ~base_group:"missing" ~name:"path" in
  (match Session.cook evaluator ~context:current missing_path with
   | Error error -> check (error.code = "missing_group")
       "Group Find Path missing-base diagnostic"
   | Ok _ -> fail "procedural Group Find Path accepted a missing base");
  let wrong_owner_path = Sop.grid ~columns:2 ~rows:2 ~size:2. ()
      |> Sop.ordered_group ~owner:Rdk.Group.Point ~name:"waypoints" [|0; 8|]
      |> Sop.group_find_path ~owner:Rdk.Group.Primitive
           ~base_group:"waypoints" ~name:"path" in
  (match Session.cook evaluator ~context:current wrong_owner_path with
   | Error error -> check (error.code = "missing_group")
       "Group Find Path owner-specific base diagnostic"
   | Ok _ -> fail "procedural Group Find Path accepted a wrong-owner base");
  let duplicate_order = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.ordered_group ~owner:Rdk.Group.Point ~name:"bad" [|0; 0|] in
  (match Session.cook evaluator ~context:current duplicate_order with
   | Error error -> check (error.code = "ordered_group_failed")
       "ordered group duplicate diagnostic"
   | Ok _ -> fail "procedural ordered group accepted duplicate elements");
  let attributes = Sop.points [|(0.,0.,0.); (2.,0.,0.)|]
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"pscale" 2.
      |> Sop.set_vector ~owner:Rdk.Attribute.Point ~name:"scale"
           (Vec3.create 1. 2. 1.)
      |> Sop.set_orient (Quat.axis_angle ~axis:Vec3.unit_y 0.5)
      |> Sop.set_color ~owner:Rdk.Attribute.Point (Color.hex_exn "#f97316")
      |> Sop.rename_attributes ~rules:[{
           Rdk.Attribute_ops.rename_attribute_owner = Some Rdk.Attribute.Point;
           rename_attribute_pattern = "Cd";
           rename_attribute_replacement = "tint";
           rename_attribute_conflict = Rdk.Attribute_ops.Attribute_rename_error }]
      |> Sop.delete_attributes ~point_pattern:"tint"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "pscale"
      attributes.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "scale"
         attributes.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "orient"
         attributes.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "tint"
         attributes.geometry = None) "typed constant attribute SOPs";
  let lifecycle_reference = Sop.points [|(0.,0.,0.); (1.,0.,0.)|]
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"bar" 1.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"foo" 2. in
  let lifecycle = Sop.points [|(0.,0.,0.); (1.,0.,0.)|]
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"bar" 1.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"foo" 2.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"score" 3.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"temporary_width" 4.
      |> Sop.set_int ~owner:Rdk.Attribute.Detail ~name:"metadata" 7
      |> Sop.delete_attributes ~reference:lifecycle_reference
           ~point_pattern:"^bar score"
      |> Sop.rename_attributes ~rules:[{
          Rdk.Attribute_ops.rename_attribute_owner = None;
          rename_attribute_pattern = "temporary_*";
          rename_attribute_replacement = "final_*";
          rename_attribute_conflict =
            Rdk.Attribute_ops.Attribute_rename_error;
        }; {
          rename_attribute_owner = Some Rdk.Attribute.Detail;
          rename_attribute_pattern = "metadata";
          rename_attribute_replacement = "info";
          rename_attribute_conflict =
            Rdk.Attribute_ops.Attribute_rename_error;
        }]
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "bar"
      lifecycle.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "foo"
         lifecycle.geometry = None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "score"
         lifecycle.geometry = None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "final_width"
         lifecycle.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Detail "info"
         lifecycle.geometry <> None)
    "pattern Attribute Delete/Rename SOPs";
  let swap_graph = Sop.points [|(1.,2.,3.); (4.,5.,6.)|]
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"left_weight" 2.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"right_weight" 7.
      |> Sop.swap_attributes ~rules:[
          { Rdk.Attribute_ops.swap_attribute_owner = Rdk.Attribute.Point;
            swap_attribute_source = "left_*";
            swap_attribute_destination = "right_*";
            swap_attribute_method = Rdk.Attribute_ops.Attribute_swap };
          { swap_attribute_owner = Rdk.Attribute.Point;
            swap_attribute_source = "P";
            swap_attribute_destination = "rest";
            swap_attribute_method = Rdk.Attribute_ops.Attribute_copy }]
  in
  check (Node.version swap_graph = 1
      && contains (Node.parameters swap_graph) "point:left_*:right_*:swap"
      && contains (Node.parameters swap_graph) "point:P:rest:copy")
    "Attribute Swap node identity";
  let swap_result = cook_ok evaluator current swap_graph in
  let left = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point
      "left_weight" swap_result.geometry |> Option.get
  and right = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point
      "right_weight" swap_result.geometry |> Option.get in
  (match Rdk.Attribute.Private.storage left,
      Rdk.Attribute.Private.storage right,
      Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "rest"
        swap_result.geometry with
   | Rdk.Attribute.Float left, Rdk.Attribute.Float right, Some rest ->
       check (left = [|7.; 7.|] && right = [|2.; 2.|])
         "procedural Attribute Swap values";
       (match Rdk.Attribute.Private.storage rest with
        | Rdk.Attribute.Float3 positions ->
            check (Rdk.Packed.Float3.get positions 0 = (1.,2.,3.))
              "procedural Attribute Swap P copy"
        | _ -> fail "procedural Attribute Swap rest kind")
   | _ -> fail "procedural Attribute Swap output kinds");
  let invalid_swap_pattern =
    try
      ignore (Sop.points [|(0.,0.,0.)|]
        |> Sop.swap_attributes ~rules:[{
            Rdk.Attribute_ops.swap_attribute_owner = Rdk.Attribute.Point;
            swap_attribute_source = "source_*";
            swap_attribute_destination = "fixed";
            swap_attribute_method = Rdk.Attribute_ops.Attribute_copy }]);
      false
    with Invalid_argument _ -> true in
  check invalid_swap_pattern "Attribute Swap node accepted malformed patterns";
  let lifecycle_conflict = Sop.points [|(0.,0.,0.)|]
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"source" 1.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"target" 2.
      |> Sop.rename_attributes ~rules:[{
          Rdk.Attribute_ops.rename_attribute_owner = Some Rdk.Attribute.Point;
          rename_attribute_pattern = "source";
          rename_attribute_replacement = "target";
          rename_attribute_conflict =
            Rdk.Attribute_ops.Attribute_rename_error;
        }] in
  (match Session.cook evaluator ~context:current lifecycle_conflict with
   | Error error -> check (error.code = "invalid_attribute")
       "Attribute Rename SOP conflict diagnostic"
   | Ok _ -> fail "Attribute Rename SOP accepted an error conflict");
  let copies_node = Sop.copy_to_points ~source:(Sop.box ())
      ~targets:(Sop.points [|(0.,0.,0.); (2.,0.,0.)|]
        |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"pscale" 0.5) () in
  let copies = cook_ok evaluator current copies_node in
  check (Node.version copies_node = 8
      && Rdk.Geometry.point_count copies.geometry = 48)
    "copy-to-points graph with target attributes";
  let restricted_copy_node = Sop.copy_to_points ~source_group:"second"
      ~target_group:"outer"
      ~source:(Sop.merge [
        Sop.polyline [|(0.,0.,0.); (1.,0.,0.)|];
        Sop.polyline [|(10.,0.,0.); (12.,0.,0.)|]]
        |> Sop.group ~name:"second" (Select.primitive_indices [|1|]))
      ~targets:(Sop.points [|(0.,0.,0.); (0.,10.,0.); (0.,20.,0.)|]
        |> Sop.group ~name:"outer" (Select.point_indices [|0;2|])) () in
  check (contains (Node.parameters restricted_copy_node) "source_group=\"second\""
      && contains (Node.parameters restricted_copy_node) "target_group=\"outer\"")
    "restricted Copy to Points cache identity";
  let restricted_copy = cook_ok evaluator current restricted_copy_node in
  check (Rdk.Geometry.point_count restricted_copy.geometry = 4
      && Rdk.Geometry.primitive_count restricted_copy.geometry = 2)
    "procedural restricted Copy to Points";
  let piece_copy_node = Sop.copy_to_points ~piece_attribute:"variant"
      ~source:(Sop.merge [
        Sop.polyline [|(0.,0.,0.); (1.,0.,0.)|]
        |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"variant" 10;
        Sop.polyline [|(0.,0.,0.); (2.,0.,0.)|]
        |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"variant" 20])
      ~targets:(Sop.merge [
        Sop.points [|(0.,0.,0.); (0.,2.,0.)|]
        |> Sop.set_int ~owner:Rdk.Attribute.Point ~name:"variant" 20;
        Sop.points [|(0.,4.,0.)|]
        |> Sop.set_int ~owner:Rdk.Attribute.Point ~name:"variant" 10]) () in
  check (contains (Node.parameters piece_copy_node) "piece_attribute=\"variant\"")
    "piece-matched Copy to Points cache identity";
  let piece_copy = cook_ok evaluator current piece_copy_node in
  let piece_ids = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive
      "variant" piece_copy.geometry |> Option.get
      |> Rdk.Attribute.get (Rdk.Attribute.key ~name:"variant"
           ~owner:Rdk.Attribute.Primitive Rdk.Attribute.int) |> Option.get in
  check (Rdk.Geometry.point_count piece_copy.geometry = 6
      && piece_ids = [|20;20;10|])
    "procedural piece-matched Copy to Points";
  let transfer_copy_node = Sop.copy_to_points
      ~target_attributes:Rdk.Instance_copy.[{
        copy_target_pattern = "weight";
        copy_target_owner = Copy_target_points;
        copy_target_operation = Copy_target_add;
      }; {
        copy_target_pattern = "disabled";
        copy_target_owner = Copy_target_points;
        copy_target_operation = Copy_target_nothing;
      }]
      ~source:(Sop.points [|(0.,0.,0.)|]
        |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"weight" 10.)
      ~targets:(Sop.points [|(0.,0.,0.); (1.,0.,0.)|]
        |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"weight" 3.) () in
  check (contains (Node.parameters transfer_copy_node)
      "target_attributes=\"weight\":points:add,\"disabled\":points:nothing")
    "Copy to Points target transfer cache identity";
  let transfer_copy = cook_ok evaluator current transfer_copy_node in
  let transfer_weights = Rdk.Geometry.find_attribute
      ~owner:Rdk.Attribute.Point "weight" transfer_copy.geometry |> Option.get
      |> Rdk.Attribute.get (Rdk.Attribute.key ~name:"weight"
           ~owner:Rdk.Attribute.Point Rdk.Attribute.float) |> Option.get in
  check (transfer_weights = [|13.;13.|])
    "procedural Copy to Points target attribute transfer";
  let missing_copy_group = Sop.copy_to_points ~source_group:"missing"
      ~source:(Sop.polyline [|(0.,0.,0.); (1.,0.,0.)|])
      ~targets:(Sop.points [|(0.,0.,0.)|]) () in
  (match Session.cook evaluator ~context:current missing_copy_group with
   | Error error -> check (error.code = "missing_group")
       "Copy to Points missing source group diagnostic"
   | Ok _ -> fail "Copy to Points accepted a missing source group");
  let matrix_copy = Sop.copy_to_points
      ~source:(Sop.points [|(1.,0.,0.)|])
      ~targets:(Sop.points [|(2.,0.,0.)|]
        |> Sop.set_transform (Mat4.rotation_z (Float.pi /. 2.))) ()
      |> cook_ok evaluator current in
  let matrix_copy_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions matrix_copy.geometry) in
  check (abs_float (matrix_copy_positions.x.(0) -. 2.) <= 1e-12
      && abs_float (matrix_copy_positions.y.(0) -. 1.) <= 1e-12
      && abs_float matrix_copy_positions.z.(0) <= 1e-12)
    "procedural Copy to Points affine transform override";
  let uv_mapped = Sop.box ()
      |> Sop.group ~name:"uv_faces" Select.all_primitives
      |> Sop.uv_project ~group:"uv_faces"
           (Rdk.Uv_ops.Planar { origin = Vec3.zero;
             u_axis = Vec3.create 2. 0. 0.;
             v_axis = Vec3.create 0. 2. 0. })
      |> Sop.uv_transform ~scale:(Vec2.create 2. 2.)
           ~translate:(Vec2.create 0.1 0.2)
      |> Sop.uv_auto_seam ~angle:(Float.pi /. 4.) ~existing_uv:"uv"
           ~island_attribute:"uv_island"
      |> Sop.uv_unitize ~seams:"uv_seams" Rdk.Uv_ops.Islands
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "uv"
      uv_mapped.geometry <> None
      && Rdk.Geometry.find_group ~owner:Rdk.Group.Vertex "uv_seams"
         uv_mapped.geometry <> None
      && Rdk.Geometry.find_edge_group "uv_seams" uv_mapped.geometry <> None
      && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "uv_island"
         uv_mapped.geometry <> None)
    "procedural UV projection/transform/seam/unitize";
  let flattened = Sop.grid ~columns:4 ~rows:4 ~size:2. ()
      |> Sop.uv_flatten ~iterations:500 ~tolerance:1e-12
      |> Sop.uv_relax ~iterations:50 ~tolerance:1e-12
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "uv"
      flattened.geometry <> None)
    "procedural UV flatten/relax";
  let missing_uv_group = Sop.box ()
      |> Sop.uv_project ~group:"missing"
           (Rdk.Uv_ops.Planar { origin = Vec3.zero;
             u_axis = Vec3.unit_x; v_axis = Vec3.unit_y }) in
  (match Session.cook evaluator ~context:current missing_uv_group with
   | Error error -> check (error.code = "missing_group")
       "UV Project missing-group diagnostic"
   | Ok _ -> fail "UV Project accepted a missing primitive group");
  let missing_seams = Sop.box ()
      |> Sop.uv_project
           (Rdk.Uv_ops.Planar { origin = Vec3.zero;
             u_axis = Vec3.unit_x; v_axis = Vec3.unit_y })
      |> Sop.uv_unitize ~seams:"missing" Rdk.Uv_ops.Islands in
  (match Session.cook evaluator ~context:current missing_seams with
   | Error error -> check (error.code = "missing_group")
       "UV Unitize missing-seam diagnostic"
   | Ok _ -> fail "UV Unitize accepted a missing seam group");
  let missing_flatten_seams = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.uv_flatten ~seams:"missing" in
  (match Session.cook evaluator ~context:current missing_flatten_seams with
   | Error error -> check (error.code = "missing_group")
       "UV Flatten missing-seam diagnostic"
   | Ok _ -> fail "UV Flatten accepted a missing seam group");
  let boundary_edges = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.group_edges ~name:"boundary" ~incidence:Rdk.Group_mesh.Boundary_edge
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_edge_group "boundary" boundary_edges.geometry with
   | Some group -> check (Rdk.Edge_group.cardinality group = 4)
       "procedural native boundary edge group"
   | None -> fail "Edge Group node did not create its native group");
  let attribute_boundary = Sop.grid ~columns:2 ~rows:1 ~size:2. ()
      |> Sop.enumerate ~owner:Rdk.Attribute.Primitive ~name:"face_id"
      |> Sop.group_from_attribute_boundary ~owner:Rdk.Group_ops.Group_edges
           ~name:"attribute_seams" ~attributes:[{
             Rdk.Group_ops.boundary_attribute_owner = Rdk.Attribute.Primitive;
             boundary_attribute_pattern = "face_id" }]
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_edge_group "attribute_seams"
      attribute_boundary.geometry with
   | Some group -> check (Rdk.Edge_group.cardinality group = 3)
       "procedural Group from Attribute Boundary cardinality"
   | None -> fail "Group from Attribute Boundary dropped its native group");
  let piece_source = Rdk.Line_geometry.points
      [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.); (3.,0.,0.); (4.,0.,0.)|] in
  let piece_attribute = Rdk.Attribute.create_owned
      ~owner:Rdk.Attribute.Point ~name:"piece"
      (Rdk.Attribute.Text [|"oak"; "pine"; "oak"; "oak"; "pine"|])
      |> Result.get_ok in
  let piece_source = Rdk.Geometry.with_attribute piece_attribute piece_source
      |> Result.get_ok in
  let piece_graph = Sop.snapshot piece_source
      |> Sop.enumerate ~piece_attribute:"piece"
           ~mode:Rdk.Attribute_ops.Enumerate_piece_elements
           ~owner:Rdk.Attribute.Point ~name:"piece_index"
      |> Sop.enumerate ~storage:(Rdk.Attribute_ops.Text { prefix = "class_" })
           ~piece_attribute:"piece" ~mode:Rdk.Attribute_ops.Enumerate_pieces
           ~owner:Rdk.Attribute.Point ~name:"piece_class" in
  check (Node.version piece_graph = 2
      && contains (Node.parameters piece_graph) "piece_attribute=piece"
      && contains (Node.parameters piece_graph) "mode=pieces")
    "piece Enumerate node identity";
  let piece_output = cook_ok evaluator current piece_graph in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "piece_index"
      piece_output.geometry,
      Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "piece_class"
        piece_output.geometry with
   | Some indices, Some classes ->
       (match Rdk.Attribute.Private.storage indices,
           Rdk.Attribute.Private.storage classes with
        | Rdk.Attribute.Int indices, Rdk.Attribute.Text classes ->
            check (indices = [|0;0;1;2;1|]
                && classes = [|"class_0";"class_1";"class_0";
                  "class_0";"class_1"|])
              "procedural piece Enumerate values"
        | _ -> fail "procedural piece Enumerate storage kinds")
   | _ -> fail "procedural piece Enumerate outputs missing");
  let missing_piece = Sop.snapshot piece_source
      |> Sop.enumerate ~piece_attribute:"missing"
           ~mode:Rdk.Attribute_ops.Enumerate_pieces
           ~owner:Rdk.Attribute.Point ~name:"class" in
  (match Session.cook evaluator ~context:current missing_piece with
   | Error error -> check (error.code = "invalid_enumeration")
       "procedural missing piece attribute diagnostic"
   | Ok _ -> fail "procedural Enumerate accepted a missing piece attribute");
  let named_source = Rdk.Line_geometry.points
      [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.); (3., 0., 0.)|] in
  let names = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"piece_name" (Rdk.Attribute.Text [|"left"; "right"; "left"; ""|])
      |> Result.get_ok in
  let named_source = Rdk.Geometry.with_attribute names named_source
      |> Result.get_ok in
  let named = Sop.snapshot named_source
      |> Sop.groups_from_name ~owner:Rdk.Attribute.Point
           ~attribute:"piece_name" |> cook_ok evaluator current in
  (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "left" named.geometry,
      Rdk.Geometry.find_group ~owner:Rdk.Group.Point "right" named.geometry with
   | Some left, Some right ->
       check (Rdk.Group.cardinality left = 2
           && Rdk.Group.mem 0 left && Rdk.Group.mem 2 left
           && Rdk.Group.cardinality right = 1 && Rdk.Group.mem 1 right)
         "procedural Groups from Name membership"
   | _ -> fail "Groups from Name dropped a procedural output group");
  let round_trip = Sop.snapshot named.geometry
      |> Sop.name_from_groups ~attribute:"round_trip" ~pattern:"left"
           ~delete_groups:true ~owner:Rdk.Attribute.Point
      |> cook_ok evaluator current in
  (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "round_trip"
      round_trip.geometry with
   | Some attribute ->
       (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Text values -> check
            (values = [|"left"; ""; "left"; ""|])
            "procedural Name from Groups values"
        | _ -> fail "Name from Groups produced non-text storage")
   | None -> fail "Name from Groups dropped its procedural attribute");
  check (Rdk.Geometry.find_group ~owner:Rdk.Group.Point "left"
      round_trip.geometry = None
      && Rdk.Geometry.find_group ~owner:Rdk.Group.Point "right"
         round_trip.geometry <> None)
    "procedural Name from Groups selected deletion";
  let bounded_names = Sop.snapshot named_source
      |> Sop.groups_from_name ~max_groups:1 ~owner:Rdk.Attribute.Point
           ~attribute:"piece_name" in
  (match Session.cook evaluator ~context:current bounded_names with
   | Error error -> check (error.code = "invalid_group")
       "Groups from Name bound diagnostic"
   | Ok _ -> fail "Groups from Name ignored its procedural group bound");
  let missing_boundary_attribute = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.group_from_attribute_boundary ~owner:Rdk.Group_ops.Group_edges
           ~name:"attribute_seams" ~attributes:[{
             Rdk.Group_ops.boundary_attribute_owner = Rdk.Attribute.Primitive;
             boundary_attribute_pattern = "missing" }] in
  (match Session.cook evaluator ~context:current missing_boundary_attribute with
   | Error error -> check (error.code = "invalid_group")
       "Group from Attribute Boundary missing-attribute diagnostic"
   | Ok _ -> fail "Group from Attribute Boundary accepted a missing attribute");
  let renamed_edges = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.group_edges ~name:"boundary" ~incidence:Rdk.Group_mesh.Boundary_edge
      |> Sop.rename_edge_group ~from:"boundary" ~into:"rim"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.find_edge_group "boundary" renamed_edges.geometry = None
      && Rdk.Geometry.find_edge_group "rim" renamed_edges.geometry <> None)
    "native edge group rename";
  let deleted_edges = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.group_edges ~name:"boundary" ~incidence:Rdk.Group_mesh.Boundary_edge
      |> Sop.delete_edge_group ~name:"boundary" |> cook_ok evaluator current in
  check (Rdk.Geometry.find_edge_group "boundary" deleted_edges.geometry = None)
    "native edge group delete";
  let missing_edge_selection = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.group_edges ~group:"missing" in
  (match Session.cook evaluator ~context:current missing_edge_selection with
   | Error error -> check (error.code = "missing_group")
       "Edge Group missing primitive-group diagnostic"
   | Ok _ -> fail "Edge Group accepted a missing primitive group");
  let filtered_points = Sop.points [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
      |> Sop.group ~name:"doomed" (Select.point_indices [|1|])
      |> Sop.blast ~owner:Rdk.Group.Point ~group:"doomed"
      |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count filtered_points.geometry = 2)
    "typed point-index Delete";
  let missing_blast = Sop.grid ~columns:1 ~rows:1 ~size:1. ()
      |> Sop.blast ~owner:Rdk.Group.Point ~group:"missing" in
  (match Session.cook evaluator ~context:current missing_blast with
   | Error error -> check (contains (Diagnostic.error_to_string error) "missing")
       "Blast missing-group diagnostic"
   | Ok _ -> fail "Blast accepted a missing named group");
  Session.close evaluator

let test_poly_fill_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let graph = Sop.tube ~connectivity:Rdk.Parametric_generators.Tube_quads ~end_caps:false
      ~rows:4 ~columns:8 ~top_radius:0.7 ~bottom_radius:1. ~height:2. ()
      |> Sop.poly_fill ~mode:Rdk.Poly_fill.Fill_triangle_fan ~unique_points:true
           ~patch_group:"patch" in
  let first = cook_ok evaluator current graph in
  let patch = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "patch"
      first.geometry |> Option.get in
  check (Rdk.Group.cardinality patch = 16)
    "procedural Poly Fill patch cardinality";
  let topology_index = Rdk.Topology_index.create
      (Rdk.Geometry.topology first.geometry) in
  check (Rdk.Topology_index.boundary_edge_count topology_index = 32)
    "procedural unique Poly Fill did not detach its two patches";
  let before = Session.stats evaluator in
  ignore (cook_ok evaluator current graph);
  let after = Session.stats evaluator in
  check (after.hits > before.hits) "procedural Poly Fill did not cache";
  let missing = Sop.tube ~end_caps:false ~top_radius:0.7 ~bottom_radius:1.
      ~height:2. () |> Sop.poly_fill ~boundary_group:"missing" in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Poly Fill missing-group diagnostic"
   | Ok _ -> fail "procedural Poly Fill accepted a missing boundary group");
  Session.close evaluator

let test_poly_path_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:3 () in
  let positions = Rdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;2.;10.;11.;10.5|]
      ~y:[|0.;0.;0.;1.;0.;0.;1.|] ~z:(Array.make 7 0.) in
  let topology = Rdk.Topology.create_owned ~point_count:7
      ~vertex_points:[|0;1;2; 2;3; 4;5;6|]
      ~primitive_offsets:[|0;3;5;8|]
      ~primitive_kinds:[|Rdk.Topology.Open_polyline;
        Rdk.Topology.Open_polyline; Rdk.Topology.Polygon|]
      |> Result.get_ok in
  let source = Rdk.Geometry.create ~positions ~topology () |> Result.get_ok in
  let graph = Sop.snapshot source
      |> Sop.poly_path ~make_isolated_loops_closed:true in
  check (Node.operation graph = "poly_path"
      && contains (Node.parameters graph) "make_isolated_loops_closed=true")
    "procedural PolyPath operation/cache identity";
  let first = cook_ok evaluator current graph in
  check (Rdk.Geometry.primitive_count first.geometry = 2
      && Rdk.Geometry.vertex_count first.geometry = 7
      && Rdk.Topology.primitive_kind (Rdk.Geometry.topology first.geometry) 1
         = Rdk.Topology.Polygon)
    "procedural PolyPath topology";
  let before = Session.stats evaluator in
  ignore (cook_ok evaluator current graph);
  let after = Session.stats evaluator in
  check (after.hits > before.hits) "procedural PolyPath did not cache";
  let invalid = Sop.snapshot source |> Sop.poly_path ~maximum_distance:Float.nan in
  (match Session.cook evaluator ~context:current invalid with
   | Error error -> check (error.code = "invalid_geometry")
       "procedural PolyPath invalid-distance diagnostic"
   | Ok _ -> fail "procedural PolyPath accepted a non-finite distance");
  Session.close evaluator

let test_revolve_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let profile = Sop.polyline [|(0., -1., 0.); (1., 0., 0.); (0., 1., 0.)|] in
  let make () = profile |> Sop.revolve ~label:"lathe"
      ~connectivity:Rdk.Plane_generators.Grid_alternating_triangles ~caps:true
      ~cap_group:"caps" ~uv_attribute:(Some "st") ~divisions:16
      ~origin:Vec3.zero ~axis:Vec3.unit_y in
  let graph = make () in
  check (Node.operation graph = "revolve"
      && contains (Node.parameters graph) "type=closed"
      && contains (Node.parameters graph) "connectivity=alternating_triangles"
      && contains (Node.parameters graph) "divisions=16")
    "procedural Revolve cache identity";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 18
      && Rdk.Geometry.primitive_count output.geometry = 32
      && Rdk.Geometry.vertex_count output.geometry = 96)
    "procedural Revolve pole topology";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "st"
      output.geometry <> None)
    "procedural Revolve dropped generated UVs";
  let caps = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "caps"
      output.geometry |> Option.get in
  check (Rdk.Group.cardinality caps = 0)
    "procedural Revolve emitted degenerate pole caps";
  let before = Session.stats evaluator in
  ignore (cook_ok evaluator current graph);
  check ((Session.stats evaluator).hits > before.hits)
    "procedural Revolve did not cache";
  let missing = profile |> Sop.revolve ~group:"missing" ~divisions:8
      ~origin:Vec3.zero ~axis:Vec3.unit_y in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Revolve missing-group diagnostic"
   | Ok _ -> fail "procedural Revolve accepted a missing group");
  Session.close evaluator

let test_sweep_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let backbone = Sop.polyline [|(0.,0.,0.); (0.,0.,2.)|]
  and cross_section = Sop.polyline ~closed:true
      [|(-1.,-1.,0.); (1.,-1.,0.); (1.,1.,0.); (-1.,1.,0.)|] in
  let make () = Sop.sweep ~label:"general-sweep"
      ~connectivity:Rdk.Plane_generators.Grid_alternating_triangles
      ~tangent:Rdk.Sweep_modeling.Sweep_central_difference ~twist:1.25 ~caps:true
      ~cap_group:"caps" ~uv_attribute:(Some "st") ~backbone ~cross_section () in
  let graph = make () in
  check (Node.operation graph = "sweep"
      && contains (Node.parameters graph) "tangent=central_difference"
      && contains (Node.parameters graph) "connectivity=alternating_triangles"
      && contains (Node.parameters graph) "twist=")
    "procedural Sweep cache identity";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 8
      && Rdk.Geometry.primitive_count output.geometry = 10
      && Rdk.Geometry.vertex_count output.geometry = 32)
    "procedural Sweep topology";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "st"
      output.geometry <> None)
    "procedural Sweep dropped generated UVs";
  let caps = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "caps"
      output.geometry |> Option.get in
  check (Rdk.Group.cardinality caps = 2) "procedural Sweep cap group";
  let before = Session.stats evaluator in
  ignore (cook_ok evaluator current graph);
  check ((Session.stats evaluator).hits > before.hits)
    "procedural Sweep did not cache";
  let missing = Sop.sweep ~backbone_group:"missing" ~backbone ~cross_section () in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Sweep missing-group diagnostic"
   | Ok _ -> fail "procedural Sweep accepted a missing group");
  Session.close evaluator

let test_local_subdivide_contract () =
  let base = Rdk.Plane_generators.grid ~columns:3 ~rows:2 ~size:2. () |> Result.get_ok in
  let source_primitives = Rdk.Geometry.primitive_count base in
  let selected = Rdk.Group.ordered ~owner:Rdk.Group.Primitive ~name:"left"
      ~length:source_primitives [|0|] |> Result.get_ok in
  let source = match Rdk.Geometry.with_group selected base with
    | Ok source -> source
    | Error error -> fail error in
  let graph = Sop.snapshot source |> Sop.subdivide ~group:"left"
      ~scheme:Rdk.Subdivide.Bilinear ~iterations:2 in
  check (Node.version graph = 13
      && contains (Node.parameters graph) "group=left"
      && contains (Node.parameters graph) "scheme=bilinear"
      && contains (Node.parameters graph) "boundary_interpolation=edge_only"
      && contains (Node.parameters graph) "face_varying_interpolation=all"
      && contains (Node.parameters graph) "triangle_policy=catmull_clark"
      && contains (Node.parameters graph) "creasing_method=uniform"
      && contains (Node.parameters graph) "recompute_point_normals=false")
    "procedural local Subdivide cache identity";
  let evaluator = session () and current = context ~domains:4 ~grain:1 () in
  let output = cook_ok evaluator current graph in
  let refined_primitives =
    Rdk.Topology.primitive_size (Rdk.Geometry.topology base) 0 * 4 in
  let output_primitives = Rdk.Geometry.primitive_count output.geometry
  and selected_primitives = Rdk.Group.cardinality
      (Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "left"
        output.geometry |> Option.get) in
  check (output_primitives = source_primitives - 1 + refined_primitives
      && selected_primitives = refined_primitives)
    (Printf.sprintf
      "procedural local Subdivide topology/group ancestry (%d/%d from %d)"
      output_primitives selected_primitives source_primitives);
  let pulled_graph = Sop.snapshot source |> Sop.subdivide ~group:"left"
      ~cracks:Rdk.Subdivide.Subdivide_pull_no_edge_division in
  check (contains (Node.parameters pulled_graph) "cracks=pull_no_edge_division")
    "procedural Pull Closed cache identity";
  let pulled = cook_ok evaluator current pulled_graph in
  let stitch_graph = Sop.snapshot source |> Sop.subdivide ~group:"left"
      ~cracks:Rdk.Subdivide.Subdivide_stitch_no_edge_division in
  check (contains (Node.parameters stitch_graph) "cracks=stitch_no_edge_division")
    "procedural Stitch cache identity";
  let stitched = cook_ok evaluator current stitch_graph in
  check (Rdk.Geometry.primitive_count stitched.geometry
      > Rdk.Geometry.primitive_count source)
    "procedural Stitch did not append bridge primitives";
  let divided_pull_graph = Sop.snapshot source |> Sop.subdivide ~group:"left"
      ~cracks:(Rdk.Subdivide.Subdivide_pull_divide_edges 0.75) in
  check (contains (Node.parameters divided_pull_graph)
      "cracks=pull_divide_edges:")
    "procedural Pull Divide bias/cache identity";
  let divided_pull = cook_ok evaluator current divided_pull_graph in
  check (Rdk.Geometry.vertex_count divided_pull.geometry
      > Rdk.Geometry.vertex_count pulled.geometry)
    "procedural Pull Divide did not divide a surrounding edge";
  let divided_stitch_graph = Sop.snapshot source |> Sop.subdivide ~group:"left"
      ~cracks:Rdk.Subdivide.Subdivide_stitch_divide_edges in
  check (contains (Node.parameters divided_stitch_graph)
      "cracks=stitch_divide_edges")
    "procedural Stitch Divide cache identity";
  let divided_stitch = cook_ok evaluator current divided_stitch_graph in
  check (Rdk.Geometry.primitive_count divided_stitch.geometry
      > Rdk.Geometry.primitive_count divided_pull.geometry)
    "procedural Stitch Divide did not append regular bridge primitives";
  let pull_tri_graph = Sop.snapshot source |> Sop.subdivide ~group:"left"
      ~cracks:(Rdk.Subdivide.Subdivide_pull_triangulate 0.75) in
  check (contains (Node.parameters pull_tri_graph) "cracks=pull_triangulate:")
    "procedural Pull Triangulate cache identity";
  let pull_tri = cook_ok evaluator current pull_tri_graph in
  check (Rdk.Geometry.primitive_count pull_tri.geometry
      > Rdk.Geometry.primitive_count divided_pull.geometry)
    "procedural Pull Triangulate did not triangulate surrounding polygons";
  let stitch_tri_graph = Sop.snapshot source |> Sop.subdivide ~group:"left"
      ~cracks:Rdk.Subdivide.Subdivide_stitch_triangulate in
  check (contains (Node.parameters stitch_tri_graph)
      "cracks=stitch_triangulate")
    "procedural Stitch Triangulate cache identity";
  ignore (cook_ok evaluator current stitch_tri_graph);
  let consistent_graph = Sop.snapshot source |> Sop.subdivide ~group:"left"
      ~consistent_topology:true
      ~cracks:Rdk.Subdivide.Subdivide_stitch_divide_edges in
  check (Node.version consistent_graph = 13
      && contains (Node.parameters consistent_graph) "consistent_topology=true"
      && Node.id consistent_graph <> Node.id divided_stitch_graph)
    "procedural consistent Subdivide cache identity";
  let consistent = cook_ok evaluator current consistent_graph in
  check (Rdk.Geometry.primitive_count consistent.geometry
      >= Rdk.Geometry.primitive_count divided_stitch.geometry)
    "procedural consistent Subdivide omitted topology-prescribed faces";
  let crease_input = Sop.polyline [|(99., 4., 7.); (-20., 8., 3.)|]
      |> Sop.group ~name:"crease_edges" Select.all_primitives in
  let crease_graph = Sop.snapshot source
      |> Sop.subdivide ~creases:crease_input ~crease_group:"crease_edges"
           ~crease_weight:2.5 ~resulting_crease_group:"remaining_creases" in
  check (Node.version crease_graph = 13
      && List.length (Node.inputs crease_graph) = 2
      && contains (Node.parameters crease_graph) "creases=true"
      && contains (Node.parameters crease_graph) "crease_group=crease_edges"
      && contains (Node.parameters crease_graph) "generate_resulting_creases=true")
    "procedural second-input Subdivide cache identity";
  let creased = cook_ok evaluator current crease_graph in
  check (match Rdk.Geometry.find_edge_group "remaining_creases" creased.geometry with
    | Some group -> Rdk.Edge_group.cardinality group > 0 | None -> false)
    "procedural second-input Subdivide omitted resulting crease group";
  let all_edge_graph = Sop.snapshot base
      |> Sop.subdivide ~iterations:2 ~crease_weight:3.
           ~resulting_crease_group:"all_edge_creases" in
  check (Node.version all_edge_graph = 13
      && List.length (Node.inputs all_edge_graph) = 1
      && contains (Node.parameters all_edge_graph) "creases=false"
      && contains (Node.parameters all_edge_graph) "crease_weight=")
    "procedural all-edge crease override cache identity";
  let all_edge_output = cook_ok evaluator current all_edge_graph in
  let all_edge_cardinality = match Rdk.Geometry.find_edge_group
      "all_edge_creases" all_edge_output.geometry with
    | Some group -> Rdk.Edge_group.cardinality group
    | None -> -1 in
  let source_edge_count = Array.length
      ((Rdk.Topology_index.create (Rdk.Geometry.topology base)
        |> Rdk.Topology_index.Private.view).edge_a) in
  let expected_all_edge_cardinality = source_edge_count * 4 in
  check (all_edge_cardinality = expected_all_edge_cardinality)
    (Printf.sprintf
      "procedural no-input crease override covered %d rather than %d edges"
      all_edge_cardinality expected_all_edge_cardinality);
  let before_all_edge_hit = Session.stats evaluator in
  ignore (cook_ok evaluator current all_edge_graph);
  let after_all_edge_hit = Session.stats evaluator in
  check (after_all_edge_hit.hits > before_all_edge_hit.hits)
    "procedural all-edge crease override did not cache";
  let invalid_all_edge = Sop.snapshot base |> Sop.subdivide
      ~crease_weight:Float.nan in
  (match Session.cook evaluator ~context:current invalid_all_edge with
   | Ok _ -> fail "procedural Subdivide accepted non-finite all-edge sharpness"
   | Error error -> check (error.code = "invalid_topology"
       && match error.cause with
         | Some cause -> contains cause "finite and non-negative"
         | None -> false)
       "procedural all-edge crease diagnostic");
  let chaikin_base = Rdk.Plane_generators.grid ~connectivity:Rdk.Plane_generators.Grid_quads
      ~columns:2 ~rows:2 ~size:2. () |> Result.get_ok in
  let chaikin_index = Rdk.Topology_index.create
      (Rdk.Geometry.topology chaikin_base) |> Rdk.Topology_index.Private.view in
  let chaikin_weights = Array.init (Rdk.Geometry.vertex_count chaikin_base)
      (fun vertex ->
        let edge = chaikin_index.edge_of_vertex.(vertex) in
        if edge < 0 then 0.
        else
          let a = chaikin_index.edge_a.(edge)
          and b = chaikin_index.edge_b.(edge) in
          let neighbor = if a = 4 then b else if b = 4 then a else -1 in
          if neighbor = 1 then 4. else if neighbor = 3 then 2.
          else if neighbor = 5 then 8. else if neighbor = 7 then 0.5 else 0.) in
  let chaikin_attribute = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Vertex
      ~name:"creaseweight" (Rdk.Attribute.Float chaikin_weights) |> Result.get_ok in
  let chaikin_source = Rdk.Geometry.with_attribute chaikin_attribute chaikin_base
      |> Result.get_ok in
  let chaikin_graph = Sop.snapshot chaikin_source
      |> Sop.subdivide ~creasing_method:Rdk.Subdivide.Subdivide_creasing_chaikin
           ~resulting_crease_group:"chaikin_remaining" in
  check (Node.version chaikin_graph = 13
      && contains (Node.parameters chaikin_graph) "creasing_method=chaikin")
    "procedural Chaikin creasing cache identity";
  let chaikin_output = cook_ok evaluator current chaikin_graph
  and uniform_output = Sop.snapshot chaikin_source
      |> Sop.subdivide ~creasing_method:Rdk.Subdivide.Subdivide_creasing_uniform
           ~resulting_crease_group:"chaikin_remaining"
      |> cook_ok evaluator current in
  let resulting_weights (output : Session.output) = match Rdk.Geometry.find_attribute
      ~owner:Rdk.Attribute.Vertex "creaseweight" output.geometry
      |> Option.get |> Rdk.Attribute.storage with
    | Rdk.Attribute.Float values -> values
    | _ -> fail "procedural resulting creaseweight storage changed" in
  check (resulting_weights chaikin_output <> resulting_weights uniform_output
      && match Rdk.Geometry.find_edge_group "chaikin_remaining"
          chaikin_output.geometry with
        | Some group -> Rdk.Edge_group.cardinality group = 7
        | None -> false)
    "procedural Chaikin cook did not preserve endpoint-dependent child creases";
  let missing_crease = Sop.snapshot source
      |> Sop.subdivide ~creases:crease_input ~crease_group:"missing"
           ~crease_weight:2. in
  (match Session.cook evaluator ~context:current missing_crease with
   | Error error -> check (error.code = "missing_group")
       "procedural Subdivide missing crease-group diagnostic"
   | Ok _ -> fail "procedural Subdivide accepted a missing crease group");
  let holes = Rdk.Group.ordered ~owner:Rdk.Group.Primitive ~name:"holes"
      ~length:source_primitives [|1|] |> Result.get_ok in
  let hole_source = Rdk.Geometry.with_group holes base |> Result.get_ok in
  let hole_graph = Sop.snapshot hole_source
      |> Sop.subdivide ~hole_group:"holes" ~iterations:2 in
  check (Node.version hole_graph = 13
      && contains (Node.parameters hole_graph) "hole_group=holes"
      && contains (Node.parameters hole_graph) "remove_holes=true")
    "procedural hole Subdivide cache identity";
  let holed = cook_ok evaluator current hole_graph in
  check (Rdk.Geometry.primitive_count holed.geometry
      = (source_primitives - 1)
        * Rdk.Topology.primitive_size (Rdk.Geometry.topology base) 1 * 4)
    "procedural recursive hole descendants were not removed at final depth";
  let retained_holes = Sop.snapshot hole_source
      |> Sop.subdivide ~hole_group:"holes" ~remove_holes:false
      |> cook_ok evaluator current in
  check (Rdk.Geometry.primitive_count retained_holes.geometry
      = source_primitives
        * Rdk.Topology.primitive_size (Rdk.Geometry.topology base) 0)
    "procedural Remove Holes off removed descendants";
  let boundary_base = Rdk.Plane_generators.grid ~connectivity:Rdk.Plane_generators.Grid_quads
      ~columns:3 ~rows:2 ~size:2. () |> Result.get_ok in
  let boundary_graph = Sop.snapshot boundary_base
      |> Sop.subdivide
           ~boundary_interpolation:Rdk.Subdivide.Subdivide_boundary_edge_and_corner in
  check (Node.version boundary_graph = 13
      && contains (Node.parameters boundary_graph)
           "boundary_interpolation=edge_and_corner")
    "procedural boundary interpolation cache identity";
  let boundary_output = cook_ok evaluator current boundary_graph in
  let source_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions boundary_base)
  and boundary_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions boundary_output.geometry) in
  check (boundary_positions.x.(0) = source_positions.x.(0)
      && boundary_positions.y.(0) = source_positions.y.(0)
      && boundary_positions.z.(0) = source_positions.z.(0))
    "procedural Edge and Corner did not pin the grid corner";
  let no_boundary_surface = Sop.snapshot boundary_base
      |> Sop.subdivide
           ~boundary_interpolation:Rdk.Subdivide.Subdivide_boundary_none
      |> cook_ok evaluator current in
  check (Rdk.Geometry.primitive_count no_boundary_surface.geometry = 0)
    "procedural None did not remove the fully boundary-incident grid";
  let boundary_topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology boundary_base) in
  let fvar_values = Array.map (fun point ->
    let value = float_of_int point in value *. value)
      boundary_topology.vertex_points in
  let fvar_attribute = Rdk.Attribute.create_owned
      ~owner:Rdk.Attribute.Vertex ~name:"fvar"
      (Rdk.Attribute.Float fvar_values) |> Result.get_ok in
  let fvar_source = Rdk.Geometry.with_attribute fvar_attribute boundary_base
      |> Result.get_ok in
  let fvar_graph = Sop.snapshot fvar_source
      |> Sop.subdivide
           ~face_varying_interpolation:Rdk.Subdivide.Subdivide_fvar_none in
  check (Node.version fvar_graph = 13
      && contains (Node.parameters fvar_graph)
           "face_varying_interpolation=none")
    "procedural face-varying interpolation cache identity";
  let fvar_output = cook_ok evaluator current fvar_graph in
  let output_values = match Rdk.Geometry.find_attribute
      ~owner:Rdk.Attribute.Vertex "fvar" fvar_output.geometry
      |> Option.get |> Rdk.Attribute.storage with
    | Rdk.Attribute.Float values -> values
    | _ -> fail "procedural face-varying storage changed" in
  check (output_values.(0) <> fvar_values.(0))
    "procedural FVar None did not smooth a continuous boundary value";
  let triangle_source = Rdk.Plane_generators.grid ~connectivity:Rdk.Plane_generators.Grid_triangles
      ~columns:3 ~rows:2 ~size:3. () |> Result.get_ok in
  let triangle_graph = Sop.snapshot triangle_source
      |> Sop.subdivide
           ~triangle_policy:Rdk.Subdivide.Subdivide_triangles_smooth in
  check (Node.version triangle_graph = 13
      && contains (Node.parameters triangle_graph) "triangle_policy=smooth")
    "procedural Smooth Triangles cache identity";
  let triangle_smooth = cook_ok evaluator current triangle_graph in
  let triangle_standard = Sop.snapshot triangle_source |> Sop.subdivide
      |> cook_ok evaluator current in
  let smooth_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions triangle_smooth.geometry)
  and standard_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions triangle_standard.geometry) in
  check (smooth_positions.x <> standard_positions.x
      || smooth_positions.y <> standard_positions.y
      || smooth_positions.z <> standard_positions.z)
    "procedural Smooth Triangles did not change Catmull-Clark edge positions";
  let add_detail name storage geometry =
    let attribute = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Detail
        ~name storage |> Result.get_ok in
    Rdk.Geometry.with_attribute attribute geometry |> Result.get_ok in
  let detail_source = triangle_source
      |> add_detail "osd_scheme" (Rdk.Attribute.Int [|0|])
      |> add_detail "osd_vtxboundaryinterpolation" (Rdk.Attribute.Int [|2|])
      |> add_detail "osd_fvarlinearinterpolation" (Rdk.Attribute.Int [|0|])
      |> add_detail "osd_creasingmethod" (Rdk.Attribute.Int [|1|])
      |> add_detail "osd_trianglesubdiv" (Rdk.Attribute.Int [|1|]) in
  let detail_graph = Sop.snapshot detail_source |> Sop.subdivide
      ~iterations:2 ~scheme:Rdk.Subdivide.Bilinear
      ~boundary_interpolation:Rdk.Subdivide.Subdivide_boundary_none
      ~face_varying_interpolation:Rdk.Subdivide.Subdivide_fvar_all
      ~creasing_method:Rdk.Subdivide.Subdivide_creasing_uniform
      ~triangle_policy:Rdk.Subdivide.Subdivide_triangles_catmull_clark in
  check (Node.version detail_graph = 13
      && contains (Node.parameters detail_graph) "scheme=bilinear"
      && contains (Node.parameters detail_graph) "triangle_policy=catmull_clark")
    "procedural detail-override Subdivide cache identity";
  let detail_output = cook_ok evaluator current detail_graph in
  let expected_detail = Sop.snapshot triangle_source |> Sop.subdivide
      ~iterations:2 ~scheme:Rdk.Subdivide.Catmull_clark
      ~boundary_interpolation:Rdk.Subdivide.Subdivide_boundary_edge_and_corner
      ~face_varying_interpolation:Rdk.Subdivide.Subdivide_fvar_none
      ~creasing_method:Rdk.Subdivide.Subdivide_creasing_chaikin
      ~triangle_policy:Rdk.Subdivide.Subdivide_triangles_smooth
      |> cook_ok evaluator current in
  check (equal_positions detail_output.geometry expected_detail.geometry)
    "procedural Subdivide did not honor input detail overrides";
  check (List.for_all (fun name ->
      Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Detail name
        detail_output.geometry <> None)
      ["osd_scheme"; "osd_vtxboundaryinterpolation";
       "osd_fvarlinearinterpolation"; "osd_creasingmethod";
       "osd_trianglesubdiv"])
    "procedural Subdivide dropped OpenSubdiv detail controls";
  let before_detail_hit = Session.stats evaluator in
  ignore (cook_ok evaluator current detail_graph);
  let after_detail_hit = Session.stats evaluator in
  check (after_detail_hit.hits > before_detail_hit.hits)
    "procedural detail-override Subdivide did not cache";
  let invalid_detail_source = triangle_source
      |> add_detail "osd_scheme" (Rdk.Attribute.Text [|"none"|]) in
  let invalid_detail = Sop.snapshot invalid_detail_source |> Sop.subdivide in
  (match Session.cook evaluator ~context:current invalid_detail with
   | Ok _ -> fail "procedural Subdivide accepted unsupported osd_scheme"
   | Error error -> check (error.code = "invalid_topology"
       && (match error.cause with
           | Some cause -> contains cause "osd_scheme"
           | None -> false)
       && List.exists (fun trace -> trace.Diagnostic.operation = "subdivide")
            error.trace)
       "procedural Subdivide detail-override diagnostic");
  let curve_positions = Rdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;4.|] ~y:[|0.;2.;0.|] ~z:[|0.;0.;0.|] in
  let curve_topology = Rdk.Topology.create_owned ~point_count:3
      ~vertex_points:[|0;1; 1;2|] ~primitive_offsets:[|0;2;4|]
      ~primitive_kinds:[|Rdk.Topology.Open_polyline;
        Rdk.Topology.Open_polyline|] |> Result.get_ok in
  let curve_n = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"N"
      (Rdk.Attribute.Float3 (Rdk.Packed.Float3.Private.of_owned_exn
        ~x:[|0.;0.;0.|] ~y:[|0.;0.;0.|] ~z:[|1.;1.;1.|]))
      |> Result.get_ok in
  let curve_source = Rdk.Geometry.create ~positions:curve_positions
      ~topology:curve_topology ~attributes:[curve_n] () |> Result.get_ok in
  let shared_curve_graph = Sop.snapshot curve_source |> Sop.subdivide in
  let independent_curve_graph = Sop.snapshot curve_source
      |> Sop.subdivide ~treat_curves_as_independent:true in
  let recomputed_curve_graph = Sop.snapshot curve_source
      |> Sop.subdivide ~recompute_point_normals:true in
  check (Node.version independent_curve_graph = 13
      && contains (Node.parameters shared_curve_graph)
           "treat_curves_as_independent=false"
      && contains (Node.parameters independent_curve_graph)
           "treat_curves_as_independent=true"
      && contains (Node.parameters recomputed_curve_graph)
           "recompute_point_normals=true"
      && Node.id shared_curve_graph <> Node.id independent_curve_graph
      && Node.id shared_curve_graph <> Node.id recomputed_curve_graph)
    "procedural polygon-curve Subdivide cache identity";
  let shared_curves = cook_ok evaluator current shared_curve_graph
  and independent_curves = cook_ok evaluator current independent_curve_graph in
  check (Rdk.Geometry.point_count shared_curves.geometry = 5
      && Rdk.Geometry.point_count independent_curves.geometry = 6)
    "procedural independent curve subdivision did not split shared points";
  let recomputed_curves = cook_ok evaluator current recomputed_curve_graph in
  let recomputed_n = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "N"
      recomputed_curves.geometry |> Option.get |> Rdk.Attribute.storage in
  check (match recomputed_n with
    | Rdk.Attribute.Float3 values ->
        let values = Rdk.Packed.Float3.Private.view values in
        Array.for_all (( = ) 0.) values.x
        && Array.for_all (( = ) 0.) values.y
        && Array.for_all (( = ) 0.) values.z
    | _ -> false)
    "procedural Subdivide did not forward normal recomputation";
  let before_curve_hit = Session.stats evaluator in
  ignore (cook_ok evaluator current independent_curve_graph);
  let after_curve_hit = Session.stats evaluator in
  check (after_curve_hit.hits > before_curve_hit.hits)
    "procedural polygon-curve Subdivide did not cache";
  let missing_hole = Sop.snapshot base |> Sop.subdivide ~hole_group:"missing" in
  (match Session.cook evaluator ~context:current missing_hole with
   | Error error -> check (error.code = "missing_group")
       "procedural Subdivide missing hole-group diagnostic"
   | Ok _ -> fail "procedural Subdivide accepted a missing hole group");
  let missing = Sop.snapshot base |> Sop.subdivide ~group:"missing" in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural local Subdivide missing-group diagnostic"
   | Ok _ -> fail "procedural local Subdivide accepted a missing group");
  Session.close evaluator

let test_edge_divide_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let source = Sop.grid ~connectivity:Rdk.Plane_generators.Grid_quads
      ~columns:8 ~rows:6 ~size:4. ()
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"weight" 0.75
      |> Sop.group_edges ~name:"all_edges" in
  let source_output = cook_ok evaluator current source in
  let shared_graph = source
      |> Sop.edge_divide ~label:"shared-refinement" ~group:"all_edges"
           ~divisions:3
  and unique_graph = source
      |> Sop.edge_divide ~group:"all_edges" ~divisions:3 ~share_points:false in
  check (Node.version shared_graph = 1
      && contains (Node.parameters shared_graph) "group=all_edges"
      && contains (Node.parameters shared_graph) "divisions=3"
      && contains (Node.parameters shared_graph) "share_points=true")
    "procedural Edge Divide cache identity";
  let shared = cook_ok evaluator current shared_graph
  and unique = cook_ok evaluator current unique_graph in
  check (Rdk.Geometry.primitive_count shared.geometry
         = Rdk.Geometry.primitive_count source_output.geometry
      && Rdk.Geometry.vertex_count shared.geometry
         = Rdk.Geometry.vertex_count unique.geometry
      && Rdk.Geometry.point_count unique.geometry
         > Rdk.Geometry.point_count shared.geometry)
    "procedural Edge Divide shared/unique topology";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "weight"
      shared.geometry <> None)
    "procedural Edge Divide dropped point payload";
  let no_group = source |> Sop.edge_divide ~divisions:4
      |> cook_ok evaluator current in
  check (no_group.geometry == source_output.geometry)
    "procedural Edge Divide empty group was not an identity";
  let missing = source |> Sop.edge_divide ~group:"absent" in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Divide missing-group diagnostic"
   | Ok _ -> fail "procedural Edge Divide accepted a missing group");
  check (try ignore (source |> Sop.edge_divide ~divisions:0); false
    with Invalid_argument _ -> true)
    "procedural Edge Divide accepted zero divisions";
  Session.close evaluator

let test_edge_collapse_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let source = Sop.polyline ~closed:true
      [|0.,0.,0.;1.,0.,0.;3.,2.,0.;0.,2.,0.|]
      |> Sop.set_int ~owner:Rdk.Attribute.Point ~name:"piece" 3
      |> Sop.group_edges ~name:"short_edge" ~min_length:1. ~max_length:1. in
  let source_output = cook_ok evaluator current source in
  let graph = source |> Sop.edge_collapse ~label:"collapse-short-edge"
      ~group:"short_edge" ~connectivity_attribute:"piece" in
  check (Node.version graph = 1
      && contains (Node.parameters graph) "group=short_edge"
      && contains (Node.parameters graph) "connectivity_attribute=piece"
      && contains (Node.parameters graph) "remove_degenerate_primitives=true"
      && contains (Node.parameters graph) "recompute_point_normals=true")
    "procedural Edge Collapse cache identity";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry = 3
      && Rdk.Geometry.vertex_count output.geometry = 3
      && Rdk.Geometry.primitive_count output.geometry = 1
      && Rdk.Geometry.point_count output.geometry
         < Rdk.Geometry.point_count source_output.geometry)
    "procedural Edge Collapse topology";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "piece"
      output.geometry <> None)
    "procedural Edge Collapse dropped point payload";
  let whole = source |> Sop.edge_collapse |> cook_ok evaluator current in
  check (Rdk.Geometry.point_count whole.geometry = 0
      && Rdk.Geometry.primitive_count whole.geometry = 0)
    "procedural Edge Collapse omitted group did not select all edges";
  let missing = source |> Sop.edge_collapse ~group:"absent" in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Collapse missing-group diagnostic"
   | Ok _ -> fail "procedural Edge Collapse accepted a missing group");
  let missing_attribute = source
      |> Sop.edge_collapse ~group:"short_edge"
           ~connectivity_attribute:"absent" in
  (match Session.cook evaluator ~context:current missing_attribute with
   | Error error -> check (error.code = "invalid_topology")
       "procedural Edge Collapse missing-attribute diagnostic"
   | Ok _ -> fail "procedural Edge Collapse accepted a missing attribute");
  check (try ignore (source |> Sop.edge_collapse ~group:" "); false
    with Invalid_argument _ -> true)
    "procedural Edge Collapse accepted an empty group";
  check (try ignore (source
      |> Sop.edge_collapse ~connectivity_attribute:" "); false
    with Invalid_argument _ -> true)
    "procedural Edge Collapse accepted an empty connectivity attribute";
  Session.close evaluator

let test_edge_flip_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let source = Sop.grid ~connectivity:Rdk.Plane_generators.Grid_triangles
      ~columns:1 ~rows:1 ~size:2. ()
      |> Sop.set_float ~owner:Rdk.Attribute.Vertex ~name:"uv_marker" 0.5
      |> Sop.group_edges ~name:"interior"
           ~incidence:Rdk.Group_mesh.Manifold_edge in
  let source_output = cook_ok evaluator current source in
  let graph = source |> Sop.edge_flip ~label:"rotate-diagonal"
      ~group:"interior" ~cycles:1 ~cycle_vertex_attributes:true in
  check (Node.version graph = 1
      && contains (Node.parameters graph) "group=interior"
      && contains (Node.parameters graph) "cycles=1"
      && contains (Node.parameters graph) "cycle_vertex_attributes=true"
      && contains (Node.parameters graph) "recompute_point_normals=false")
    "procedural Edge Flip cache identity";
  let output = cook_ok evaluator current graph in
  let source_topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology source_output.geometry)
  and output_topology = Rdk.Topology.Private.view
      (Rdk.Geometry.topology output.geometry) in
  check (Rdk.Geometry.point_count output.geometry = 4
      && Rdk.Geometry.vertex_count output.geometry = 6
      && Rdk.Geometry.primitive_count output.geometry = 2
      && source_topology.vertex_points <> output_topology.vertex_points)
    "procedural Edge Flip topology";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "uv_marker"
      output.geometry <> None
      && Rdk.Geometry.find_edge_group "interior" output.geometry <> None)
    "procedural Edge Flip payload ancestry";
  let no_group = source |> Sop.edge_flip |> cook_ok evaluator current in
  check (no_group.geometry == source_output.geometry)
    "procedural Edge Flip omitted group was not an identity";
  let missing = source |> Sop.edge_flip ~group:"absent" in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Flip missing-group diagnostic"
   | Ok _ -> fail "procedural Edge Flip accepted a missing group");
  check (try ignore (source |> Sop.edge_flip ~group:" "); false
    with Invalid_argument _ -> true)
    "procedural Edge Flip accepted an empty group";
  check (try ignore (source |> Sop.edge_flip ~cycles:(-1)); false
    with Invalid_argument _ -> true)
    "procedural Edge Flip accepted negative cycles";
  Session.close evaluator

let test_edge_cusp_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let source = Sop.grid ~connectivity:Rdk.Plane_generators.Grid_triangles
      ~columns:3 ~rows:2 ~size:2. ()
      |> Sop.set_int ~owner:Rdk.Attribute.Point ~name:"source_id" 7
      |> Sop.group_edges ~name:"cusp_path" in
  let source_output = cook_ok evaluator current source in
  let graph = source |> Sop.edge_cusp ~label:"split-fans"
      ~group:"cusp_path" ~update_point_normals:true in
  check (Node.version graph = 1
      && contains (Node.parameters graph) "group=cusp_path"
      && contains (Node.parameters graph) "update_point_normals=true")
    "procedural Edge Cusp cache identity";
  let output = cook_ok evaluator current graph in
  check (Rdk.Geometry.point_count output.geometry
         > Rdk.Geometry.point_count source_output.geometry
      && Rdk.Geometry.vertex_count output.geometry
         = Rdk.Geometry.vertex_count source_output.geometry
      && Rdk.Geometry.primitive_count output.geometry
         = Rdk.Geometry.primitive_count source_output.geometry)
    "procedural Edge Cusp topology";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "source_id"
      output.geometry <> None
      && Rdk.Geometry.find_edge_group "cusp_path" output.geometry <> None)
    "procedural Edge Cusp payload ancestry";
  let no_group = source |> Sop.edge_cusp |> cook_ok evaluator current in
  check (no_group.geometry == source_output.geometry)
    "procedural Edge Cusp omitted group was not an identity";
  let missing = source |> Sop.edge_cusp ~group:"absent" in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Cusp missing-group diagnostic"
   | Ok _ -> fail "procedural Edge Cusp accepted a missing group");
  check (try ignore (source |> Sop.edge_cusp ~group:" "); false
    with Invalid_argument _ -> true)
    "procedural Edge Cusp accepted an empty group";
  Session.close evaluator

let test_edge_straighten_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let source = Sop.polyline
      [|-1.,0.,0.; -0.5,0.8,0.; 0.,1.1,0.; 0.5,0.7,0.; 1.,0.,0.|]
      |> Sop.set_int ~owner:Rdk.Attribute.Point ~name:"source_id" 9
      |> Sop.group_edges ~name:"bend_edges" in
  let graph = source |> Sop.edge_straighten ~label:"fit-edge-line"
      ~group:"bend_edges" ~output_group:"straightened" in
  check (Node.version graph = 1
      && contains (Node.parameters graph) "group=bend_edges"
      && contains (Node.parameters graph) "output_group=straightened")
    "procedural Edge Straighten cache identity";
  let output = cook_ok evaluator current graph in
  let positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions output.geometry) in
  let last = Array.length positions.x - 1 in
  let dx = positions.x.(last) -. positions.x.(0)
  and dy = positions.y.(last) -. positions.y.(0)
  and dz = positions.z.(last) -. positions.z.(0) in
  check (Array.for_all Fun.id (Array.init (last + 1) (fun point ->
      let px = positions.x.(point) -. positions.x.(0)
      and py = positions.y.(point) -. positions.y.(0)
      and pz = positions.z.(point) -. positions.z.(0) in
      abs_float ((py *. dz) -. (pz *. dy)) < 1e-12
      && abs_float ((pz *. dx) -. (px *. dz)) < 1e-12
      && abs_float ((px *. dy) -. (py *. dx)) < 1e-12)))
    "procedural Edge Straighten did not produce a line";
  check (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "source_id"
      output.geometry <> None
      && (Rdk.Geometry.find_edge_group "straightened" output.geometry
          |> Option.get |> Rdk.Edge_group.cardinality) = 4)
    "procedural Edge Straighten payload/output group";
  let all = source |> Sop.edge_straighten |> cook_ok evaluator current in
  let all_positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions all.geometry) in
  check (all_positions.x = positions.x && all_positions.y = positions.y
      && all_positions.z = positions.z)
    "procedural Edge Straighten omitted group did not use all edges";
  let missing = source |> Sop.edge_straighten ~group:"absent" in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Straighten missing-group diagnostic"
   | Ok _ -> fail "procedural Edge Straighten accepted a missing group");
  check (try ignore (source |> Sop.edge_straighten ~group:" "); false
    with Invalid_argument _ -> true)
    "procedural Edge Straighten accepted an empty group";
  check (try ignore (source |> Sop.edge_straighten ~output_group:" "); false
    with Invalid_argument _ -> true)
    "procedural Edge Straighten accepted an empty output group";
  Session.close evaluator

let test_edge_equalize_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let source = Sop.polyline [|0.,0.,0.;1.,0.,0.;4.,0.,0.;6.,0.,0.|]
      |> Sop.group_edges ~name:"uneven" in
  let graph = source |> Sop.edge_equalize ~label:"even-spacing"
      ~group:"uneven" ~method_:Rdk.Edge_ops.Equalize_average ~iterations:80
      ~tolerance:1e-7 ~output_group:"equalized" in
  check (Node.version graph = 1
      && contains (Node.parameters graph) "group=uneven"
      && contains (Node.parameters graph) "method=average"
      && contains (Node.parameters graph) "iterations=80"
      && contains (Node.parameters graph) "output_group=equalized")
    "procedural Edge Equalize cache identity";
  let output = cook_ok evaluator current graph in
  let p = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions output.geometry) in
  check (abs_float ((p.x.(1) -. p.x.(0)) -. 2.) < 1e-6
      && abs_float ((p.x.(2) -. p.x.(1)) -. 2.) < 1e-6
      && abs_float ((p.x.(3) -. p.x.(2)) -. 2.) < 1e-6)
    "procedural Edge Equalize lengths";
  check ((Rdk.Geometry.find_edge_group "equalized" output.geometry
          |> Option.get |> Rdk.Edge_group.cardinality) = 3)
    "procedural Edge Equalize output group";
  let cached = cook_ok evaluator current graph in
  check (cached.geometry == output.geometry)
    "procedural Edge Equalize static cook was not cached";
  let missing = source |> Sop.edge_equalize ~group:"absent" in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Equalize missing-group diagnostic"
   | Ok _ -> fail "procedural Edge Equalize accepted a missing group");
  check (try ignore (source |> Sop.edge_equalize ~iterations:0); false
    with Invalid_argument _ -> true)
    "procedural Edge Equalize accepted zero iterations";
  check (try ignore (source |> Sop.edge_equalize ~tolerance:nan); false
    with Invalid_argument _ -> true)
    "procedural Edge Equalize accepted a non-finite tolerance";
  check (try ignore (source |> Sop.edge_equalize ~group:" "); false
    with Invalid_argument _ -> true)
    "procedural Edge Equalize accepted an empty group";
  Session.close evaluator

let test_edge_relax_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let source = Sop.polyline [|0.,0.,0.;1.,0.,0.;3.,0.,0.;6.,0.,0.|]
  and reference = Sop.polyline [|0.,0.,0.;2.,0.,0.;3.,0.,0.;7.,0.,0.|] in
  let graph = source |> Sop.edge_relax ~label:"match-reference"
      ~reference ~iterations:128 ~step_size:0.5
      ~target_mode:Rdk.Edge_relax.Individual_lengths ~only_shorten:false
      ~tolerance:1e-7 in
  check (Node.version graph = 1
      && contains (Node.parameters graph) "iterations=128"
      && contains (Node.parameters graph) "target_mode=individual"
      && contains (Node.parameters graph) "roles=source,reference")
    "procedural Edge Relax cache identity";
  let output = cook_ok evaluator current graph in
  let p = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions output.geometry) in
  check (abs_float ((p.x.(1) -. p.x.(0)) -. 2.) < 1e-6
      && abs_float ((p.x.(2) -. p.x.(1)) -. 1.) < 1e-6
      && abs_float ((p.x.(3) -. p.x.(2)) -. 4.) < 1e-6)
    (Printf.sprintf "procedural Edge Relax reference lengths: %.9g %.9g %.9g"
      (p.x.(1) -. p.x.(0)) (p.x.(2) -. p.x.(1))
      (p.x.(3) -. p.x.(2)));
  let cached = cook_ok evaluator current graph in
  check (cached.geometry == output.geometry)
    "procedural Edge Relax static cook was not cached";
  let missing = source |> Sop.edge_relax ~reference ~pin_group:"absent" in
  (match Session.cook evaluator ~context:current missing with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Relax missing-group diagnostic"
   | Ok _ -> fail "procedural Edge Relax accepted a missing group");
  check (try ignore (source |> Sop.edge_relax ~reference
      ~group:(Sop.Vertex_group "v")); false with Invalid_argument _ -> true)
    "procedural Edge Relax accepted a vertex group";
  check (try ignore (source |> Sop.edge_relax ~reference ~step_size:0.); false
    with Invalid_argument _ -> true)
    "procedural Edge Relax accepted zero step size";
  Session.close evaluator

let test_blend_shapes_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let source = Sop.points [|0.,0.,0.;1.,0.,0.;2.,0.,0.|]
  and first = Sop.points [|10.,0.,0.;11.,0.,0.;12.,0.,0.|]
  and second = Sop.points [|20.,0.,0.;21.,0.,0.;22.,0.,0.|] in
  let graph = source |> Sop.blend_shapes ~label:"morph"
      ~mode:Rdk.Blend_shapes.Blend_differencing ~attributes:"^*" ~shapes:[
        Sop.blend_shape ~weight:1.5 first;
        Sop.blend_shape ~weight:(-0.5) second] in
  check (Node.version graph = 1
      && contains (Node.parameters graph) "mode=differencing"
      && contains (Node.parameters graph) "shapes=0:{weight="
      && contains (Node.parameters graph) ",1:{weight="
      && contains (Node.parameters graph) "attributes=\"^*\"")
    "procedural Blend Shapes cache identity";
  let cooked = cook_ok evaluator current graph in
  let position = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions cooked.geometry) in
  check (position.x = [|5.;6.;7.|])
    "procedural Blend Shapes differencing result";
  let cached = cook_ok evaluator current graph in
  check (cached.geometry == cooked.geometry)
    "procedural Blend Shapes static cook was not cached";
  check (source |> Sop.blend_shapes ~shapes:[] == source)
    "procedural Blend Shapes empty shape list was not identity";
  let missing_group = source |> Sop.blend_shapes ~point_group:"absent"
      ~shapes:[Sop.blend_shape ~weight:1. first] in
  (match Session.cook evaluator ~context:current missing_group with
   | Error error -> check (error.code = "missing_group")
       "procedural Blend Shapes missing-group diagnostic"
   | Ok _ -> fail "procedural Blend Shapes accepted a missing point group");
  check (try ignore (Sop.blend_shape ~weight:nan first); false
    with Invalid_argument _ -> true)
    "procedural Blend Shapes accepted a non-finite weight";
  Session.close evaluator;

  let point_count = 100_000 in
  let make offset scale =
    let x = Array.init point_count (fun point ->
      offset +. scale *. float_of_int point *. 0.001) in
    Rdk.Geometry.create
      ~positions:(Rdk.Packed.Float3.Private.of_owned_exn ~x
        ~y:(Array.make point_count 0.) ~z:(Array.make point_count 0.))
      ~topology:(Rdk.Topology.empty ~point_count) () |> get_ok in
  let source_geometry = make 0. 1. and target_geometry = make 1. 1.5 in
  let exact = Sop.snapshot source_geometry |> Sop.blend_shapes
      ~shapes:[Sop.blend_shape ~weight:0.37 (Sop.snapshot target_geometry)] in
  let cook domains =
    let evaluator = session () in
    let result = cook_ok evaluator (context ~domains ~grain:127 ()) exact in
    Session.close evaluator;
    result.geometry in
  let one = cook 1 and four = cook 4 in
  check (Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions one)
      = Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions four))
    "procedural Blend Shapes differs across domain counts";
  check (Rdk.Geometry.topology one == Rdk.Geometry.topology source_geometry)
    "procedural Blend Shapes rebuilt topology"

let test_attribute_composite_contract () =
  let add_float name values geometry =
    Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name
      (Rdk.Attribute.Float values) |> Result.get_ok
    |> fun attribute -> Rdk.Geometry.with_attribute attribute geometry
      |> Result.get_ok in
  let make positions values alpha =
    Rdk.Line_geometry.points positions
    |> add_float "value" values
    |> add_float "alpha" alpha in
  let first_geometry = make [|0.,0.,0.;1.,0.,0.;2.,0.,0.|]
      [|2.;4.;6.|] [|1.;1.;0.|]
  and second_geometry = make [|10.,0.,0.;11.,0.,0.;12.,0.,0.|]
      [|10.;20.;30.|] [|1.;0.;1.|] in
  let first = Sop.snapshot first_geometry and second = Sop.snapshot second_geometry in
  let graph = first |> Sop.attribute_composite ~label:"composite"
      ~operation:Rdk.Attribute_composite.Composite_mean ~weight:1.
      ~detail_attributes:"^*" ~primitive_attributes:"^*"
      ~point_attributes:"P value" ~vertex_attributes:"^*"
      ~allow_position:true ~alpha_attribute:"alpha"
      ~inputs:[Sop.attribute_composite_input ~weight:1. second] in
  check (Node.version graph = 1
      && contains (Node.parameters graph) "operation=mean"
      && contains (Node.parameters graph) "point_attributes=\"P value\""
      && contains (Node.parameters graph) "allow_position=true"
      && contains (Node.parameters graph) "alpha_attribute=alpha"
      && contains (Node.parameters graph) "inputs=0:")
    "procedural Attribute Composite cache identity";
  let evaluator = session () and current = context ~domains:4 ~grain:2 () in
  let output = cook_ok evaluator current graph in
  let positions = Rdk.Packed.Float3.Private.view
      (Rdk.Geometry.positions output.geometry) in
  let values = match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point
      "value" output.geometry with
    | Some attribute -> (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Float values -> values
        | _ -> fail "procedural Attribute Composite changed scalar storage")
    | None -> fail "procedural Attribute Composite dropped value" in
  check (positions.x = [|5.;1.;12.|] && values = [|6.;4.;30.|])
    "procedural Attribute Composite result";
  let cached = cook_ok evaluator current graph in
  check (cached.geometry == output.geometry)
    "procedural Attribute Composite static cook was not cached";
  let scaled = first |> Sop.attribute_composite
      ~operation:Rdk.Attribute_composite.Composite_maximum ~weight:2.
      ~point_attributes:"value" ~detail_attributes:"^*"
      ~primitive_attributes:"^*" ~vertex_attributes:"^*" ~inputs:[]
    |> cook_ok evaluator current in
  let scaled_values = match Rdk.Geometry.find_attribute
      ~owner:Rdk.Attribute.Point "value" scaled.geometry with
    | Some attribute -> (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Float values -> values | _ -> assert false)
    | None -> assert false in
  check (scaled_values = [|4.;8.;12.|])
    "procedural Attribute Composite empty additional-input semantics";
  check (try ignore (Sop.attribute_composite_input ~weight:nan second); false
    with Invalid_argument _ -> true)
    "procedural Attribute Composite accepted a non-finite input weight";
  Session.close evaluator;

  let point_count = 100_000 in
  let make_large offset =
    let x = Array.init point_count (fun point ->
      offset +. float_of_int point *. 0.001) in
    Rdk.Geometry.create
      ~positions:(Rdk.Packed.Float3.Private.of_owned_exn ~x
        ~y:(Array.make point_count 0.) ~z:(Array.make point_count 0.))
      ~topology:(Rdk.Topology.empty ~point_count) () |> Result.get_ok
    |> add_float "value" (Array.init point_count (fun point ->
      offset +. float_of_int (point mod 97))) in
  let large_first = make_large 0. and large_second = make_large 7. in
  let exact = Sop.snapshot large_first |> Sop.attribute_composite
      ~operation:Rdk.Attribute_composite.Composite_over ~weight:0.25
      ~point_attributes:"P value" ~allow_position:true
      ~detail_attributes:"^*" ~primitive_attributes:"^*"
      ~vertex_attributes:"^*"
      ~inputs:[Sop.attribute_composite_input ~weight:0.75
        (Sop.snapshot large_second)] in
  let cook domains =
    let evaluator = session () in
    let output = cook_ok evaluator (context ~domains ~grain:127 ()) exact in
    Session.close evaluator;
    output.geometry in
  let one = cook 1 and four = cook 4 in
  check (Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions one)
      = Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions four))
    "procedural Attribute Composite positions differ across domain counts";
  let value geometry = match Rdk.Geometry.find_attribute
      ~owner:Rdk.Attribute.Point "value" geometry with
    | Some attribute -> (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Float values -> values | _ -> assert false)
    | None -> assert false in
  check (value one = value four
      && Rdk.Geometry.topology one == Rdk.Geometry.topology large_first)
    "procedural Attribute Composite payload differs across domain counts"

let test_edge_transport_contract () =
  let evaluator = session () and current = context ~domains:4 ~grain:7 () in
  let float_values owner name geometry =
    match Rdk.Geometry.find_attribute ~owner name geometry with
    | Some attribute -> (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Float values -> values
        | _ -> fail ("unexpected Edge Transport storage for " ^ name))
    | None -> fail ("missing Edge Transport attribute " ^ name) in
  let network = Sop.polyline [|0.,0.,0.;1.,0.,0.;3.,0.,0.|]
      |> Sop.group ~name:"tip" (Select.point_indices [|2|]) in
  let network_graph = network |> Sop.edge_transport ~label:"network-distance"
      ~root_group:"tip" ~operation:Rdk.Edge_transport.Transport_total
      ~integrate_constant:true ~scale_by_edge_length:true
      ~normalization:Rdk.Edge_transport.Transport_no_normalization ~attribute:"distance" in
  check (Node.version network_graph = 1
      && contains (Node.parameters network_graph) "roots=group"
      && contains (Node.parameters network_graph) "root_group=tip"
      && contains (Node.parameters network_graph) "scale_by_edge_length=true")
    "procedural Edge Transport network cache identity";
  let network_output = cook_ok evaluator current network_graph in
  check (float_values Rdk.Attribute.Point "distance" network_output.geometry
      = [|3.;2.;0.|]) "procedural Edge Transport rooted network distance";
  let cached = cook_ok evaluator current network_graph in
  check (cached.geometry == network_output.geometry)
    "procedural Edge Transport static cook was not cached";
  let backward_network = network
      |> Sop.edge_transport ~label:"network-backward"
           ~direction:Rdk.Edge_transport.Transport_backward
           ~operation:Rdk.Edge_transport.Transport_total ~integrate_constant:true
           ~merge:Rdk.Edge_transport.Transport_merge_maximum ~attribute:"depth" in
  check (contains (Node.parameters backward_network) "direction=backward"
      && contains (Node.parameters backward_network) "merge=maximum")
    "procedural Edge Transport backward cache identity";
  let backward_output = cook_ok evaluator current backward_network in
  check (float_values Rdk.Attribute.Point "depth" backward_output.geometry
      = [|2.;1.;0.|]) "procedural Edge Transport backward network";
  let missing_root = network |> Sop.edge_transport ~root_group:"absent"
      ~attribute:"distance" in
  (match Session.cook evaluator ~context:current missing_root with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Transport missing-root diagnostic"
   | Ok _ -> fail "procedural Edge Transport accepted a missing root group");
  check (try ignore (network |> Sop.edge_transport ~root_group:" "
      ~attribute:"distance"); false with Invalid_argument _ -> true)
    "procedural Edge Transport accepted an empty root group";

  let curves = Sop.merge [
      Sop.polyline [|0.,0.,0.;1.,0.,0.;3.,0.,0.|];
      Sop.polyline [|0.,2.,0.;2.,2.,0.;5.,2.,0.|];
    ] in
  let curve_graph = curves |> Sop.edge_transport_curves ~label:"curve-distance"
      ~operation:Rdk.Edge_transport.Transport_total ~integrate_constant:true
      ~scale_by_edge_length:true
      ~normalization:Rdk.Edge_transport.Transport_normalize_components
      ~attribute:"distance" in
  check (Node.version curve_graph = 1
      && contains (Node.parameters curve_graph) "owner=point"
      && contains (Node.parameters curve_graph) "direction=forward"
      && contains (Node.parameters curve_graph) "normalization=components")
    "procedural Edge Transport Each Curve cache identity";
  let curve_output = cook_ok evaluator current curve_graph in
  check (float_values Rdk.Attribute.Point "distance" curve_output.geometry
      = [|0.;1. /. 3.;1.;0.;0.4;1.|])
    "procedural Edge Transport Each Curve normalized distance";
  let restricted = curves
      |> Sop.group ~name:"first_curve" (Select.primitive_indices [|0|])
      |> Sop.edge_transport_curves ~primitive_group:"first_curve"
           ~operation:Rdk.Edge_transport.Transport_total ~integrate_constant:true
           ~attribute:"depth"
      |> cook_ok evaluator current in
  check (float_values Rdk.Attribute.Point "depth" restricted.geometry
      = [|0.;1.;2.;1.;1.;1.|])
    "procedural Edge Transport Each Curve primitive group";
  let missing_curve_group = curves
      |> Sop.edge_transport_curves ~primitive_group:"absent" ~attribute:"value" in
  (match Session.cook evaluator ~context:current missing_curve_group with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Transport curve-group diagnostic"
   | Ok _ -> fail "procedural Edge Transport accepted a missing curve group");
  check (try ignore (curves |> Sop.edge_transport_curves
      ~owner:Rdk.Attribute.Primitive ~attribute:"value"); false
    with Invalid_argument _ -> true)
    "procedural Edge Transport accepted a primitive attribute";

  let parent_positions = Rdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;0.;2.;1.;10.;14.|]
      ~y:[|0.;0.;2.;0.;3.;0.;0.|] ~z:(Array.make 7 0.) in
  let parent_attribute = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"parent" (Rdk.Attribute.Int [|0;0;0;1;1;5;5|]) |> get_ok in
  let parent_geometry = Rdk.Geometry.create ~positions:parent_positions
      ~topology:(Rdk.Topology.empty ~point_count:7)
      ~attributes:[parent_attribute] () |> get_ok in
  let parent_source = Sop.snapshot parent_geometry in
  let parent_graph = parent_source
      |> Sop.edge_transport_parent ~label:"parent-distance"
           ~operation:Rdk.Edge_transport.Transport_total ~integrate_constant:true
           ~scale_by_edge_length:true ~attribute:"distance" in
  check (Node.version parent_graph = 1
      && contains (Node.parameters parent_graph) "parent_attribute=\"parent\""
      && contains (Node.parameters parent_graph) "direction=forward"
      && contains (Node.parameters parent_graph) "merge=add")
    "procedural Edge Transport Parent cache identity";
  let parent_output = cook_ok evaluator current parent_graph in
  check (float_values Rdk.Attribute.Point "distance" parent_output.geometry
      = [|0.;1.;2.;2.;4.;0.;4.|])
    "procedural Edge Transport Parent distance";
  let backward_parent = parent_source
      |> Sop.edge_transport_parent ~direction:Rdk.Edge_transport.Transport_backward
           ~operation:Rdk.Edge_transport.Transport_total ~integrate_constant:true
           ~merge:Rdk.Edge_transport.Transport_merge_add ~attribute:"depth"
      |> cook_ok evaluator current in
  check (float_values Rdk.Attribute.Point "depth" backward_parent.geometry
      = [|4.;2.;0.;0.;0.;1.;0.|])
    "procedural Edge Transport Parent backward merge";
  let missing_parent = Sop.points [|0.,0.,0.|]
      |> Sop.edge_transport_parent ~operation:Rdk.Edge_transport.Transport_total
           ~integrate_constant:true ~attribute:"depth" in
  (match Session.cook evaluator ~context:current missing_parent with
   | Error error -> check (error.code = "invalid_edge_transport")
       "procedural Edge Transport missing-parent diagnostic"
   | Ok _ -> fail "procedural Edge Transport accepted a missing parent field");
  let missing_parent_group = parent_source
      |> Sop.edge_transport_parent ~point_group:"absent" ~attribute:"value" in
  (match Session.cook evaluator ~context:current missing_parent_group with
   | Error error -> check (error.code = "missing_group")
       "procedural Edge Transport parent-group diagnostic"
   | Ok _ -> fail "procedural Edge Transport accepted a missing parent group");
  check (try ignore (parent_source |> Sop.edge_transport_parent
      ~parent_attribute:" " ~attribute:"value"); false
    with Invalid_argument _ -> true)
    "procedural Edge Transport accepted an empty parent attribute";
  Session.close evaluator;

  let curve_size = 10 and curve_count = 10_000 in
  let point_count = curve_size * curve_count in
  let x = Array.init point_count (fun point ->
      float_of_int (point mod curve_size) *. 0.01)
  and y = Array.init point_count (fun point ->
      float_of_int (point / curve_size) *. 0.001)
  and z = Array.make point_count 0. in
  let topology = Rdk.Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (curve_count + 1)
        (fun curve -> curve * curve_size))
      ~primitive_kinds:(Array.make curve_count Rdk.Topology.Open_polyline)
      |> get_ok in
  let geometry = Rdk.Geometry.create
      ~positions:(Rdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z)
      ~topology () |> get_ok in
  let exact_graph = Sop.snapshot geometry |> Sop.edge_transport_curves
      ~operation:Rdk.Edge_transport.Transport_total ~integrate_constant:true
      ~scale_by_edge_length:true ~attribute:"distance" in
  let cook graph domains =
    let evaluator = session () in
    let result = cook_ok evaluator (context ~domains ~grain:127 ()) graph in
    Session.close evaluator;
    result.geometry in
  let one = cook exact_graph 1 and four = cook exact_graph 4 in
  check (float_values Rdk.Attribute.Point "distance" one
      = float_values Rdk.Attribute.Point "distance" four)
    "procedural Edge Transport Each Curve differs across domain counts";
  check (Rdk.Geometry.point_count one = point_count
      && Rdk.Geometry.primitive_count one = curve_count)
    "procedural Edge Transport Each Curve exact scale cardinality";
  let parents = Array.init point_count (fun point ->
      if point mod curve_size = 0 then point else point - 1) in
  let parent_attribute = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"parent" (Rdk.Attribute.Int parents) |> get_ok in
  let parent_geometry = Rdk.Geometry.with_attribute parent_attribute geometry
      |> get_ok in
  let parent_exact = Sop.snapshot parent_geometry
      |> Sop.edge_transport_parent ~operation:Rdk.Edge_transport.Transport_total
           ~integrate_constant:true ~scale_by_edge_length:true
           ~attribute:"distance" in
  let parent_one = cook parent_exact 1 and parent_four = cook parent_exact 4 in
  check (float_values Rdk.Attribute.Point "distance" parent_one
      = float_values Rdk.Attribute.Point "distance" parent_four)
    "procedural Edge Transport Parent differs across domain counts";
  check (Rdk.Geometry.topology parent_one == Rdk.Geometry.topology parent_geometry)
    "procedural Edge Transport Parent rebuilt topology"

(* A node reachable through many paths is evaluated once per cook. *)
let test_shared_input_memo () =
  let schema = Parameter.schema ~name:"pick_first" ~default:() [] in
  let pick previous = Custom.create ~operation:"pick_first" ~schema ~values:()
      [previous; previous] (fun ~parameters:() ~context:_ inputs -> Ok inputs.(0)) in
  let rec chain node count = if count = 0 then node else chain (pick node) (count - 1) in
  let graph = chain (Sop.grid ~columns:2 ~rows:2 ~size:1. ()) 30 in
  let evaluator = session () in
  ignore (cook_ok evaluator (context ()) graph);
  let stats = Session.stats evaluator in
  check (stats.misses = 31 && stats.hits = 0)
    "shared inputs were evaluated once per path instead of once per node";
  ignore (cook_ok evaluator (context ()) graph);
  let stats = Session.stats evaluator in
  check (stats.misses = 31 && stats.hits = 31)
    "shared inputs were looked up once per path on a warm cook";
  Session.close evaluator


(* Copy to Points with pack: the cook is the source once plus one transform
   per target; a consumer receives it materialized; recooking hits. *)
let test_packed_copy_contract () =
  let session = Session.create ~max_entries:16 ~max_payload_bytes:(1 lsl 24) |> Result.get_ok in
  let context = Context.create ~seed:1L ~domains:1 () |> Result.get_ok in
  let source = Sop.box ~size:(Vec3.create 1. 1. 1.) () in
  let targets = Sop.points [| 0., 0., 0.; 2., 0., 0.; 4., 0., 0. |] in
  let packed = Sop.copy_to_points ~pack:true ~source ~targets () in
  let output = Session.cook session ~context packed |> Result.get_ok in
  let box_points = Rdk.Geometry.point_count output.geometry in
  assert (match output.instances with
    | Some transforms -> Array.length transforms = 3
      && Vec3.nearly_equal (Mat4.transform_point transforms.(2) Vec3.zero)
           (Vec3.create 4. 0. 0.) ~eps:1e-12
    | None -> false);
  let consumer = Sop.null packed in
  let materialized = Session.cook session ~context consumer |> Result.get_ok in
  assert (materialized.instances = None
    && Rdk.Geometry.point_count materialized.geometry = 3 * box_points);
  let hits = (Session.stats session).hits in
  ignore (Session.cook session ~context consumer |> Result.get_ok);
  assert ((Session.stats session).hits > hits);
  Session.close session

(* A volatile node keeps one slot outside the LRU: it never evicts static
   entries, and a hit needs the same key. *)
let test_volatile_slots () =
  let evaluator = session ~entries:2 () in
  let static = Sop.points [|0., 0., 0.|] in
  let live_node x = Sop.custom ~operation:"volatile_test" ~version:1
    ~parameters:(Printf.sprintf "x=%g" x) [static] (fun ~context:_ inputs -> Ok inputs.(0)) in
  let first = live_node 0. in
  Session.set_volatile evaluator (fun id -> id = Node.id first);
  let c = context () in
  ignore (cook_ok evaluator c static);
  for step = 0 to 19 do
    let node = Node.Private.adopt_identity ~source:first (live_node (float step)) in
    ignore (cook_ok evaluator c node)
  done;
  let stats = Session.stats evaluator in
  check (stats.evictions = 0 && stats.retained_entries = 1 && stats.volatile_entries = 1
    && stats.volatile_misses = 20 && stats.volatile_hits = 0)
    "volatile node churned the LRU or kept more than one slot";
  ignore (cook_ok evaluator c static);
  let stats = Session.stats evaluator in
  check (stats.hits = 21 && stats.misses = 21) "the static entry was evicted by a volatile node";
  let same = Node.Private.adopt_identity ~source:first (live_node 19.) in
  ignore (cook_ok evaluator c same);
  check ((Session.stats evaluator).volatile_hits = 1) "the latest volatile entry did not hit";
  Session.set_volatile evaluator (fun _ -> false);
  check ((Session.stats evaluator).volatile_entries = 0) "set_volatile kept a stale slot";
  Session.close evaluator

(* E5: the volatile predicate travels with the cook request. Set while a cook
   is in flight, it is neither called nor installed off the worker's domain:
   the running cook keeps its slots and the next request applies it. *)
let test_async_volatile_on_worker () =
  let worker = Async_cook.create ~max_entries:4 ~max_payload_bytes:4_000_000 |> get_ok in
  let main = Domain.self () and off_worker = Atomic.make false in
  let release = Atomic.make true and entered = Atomic.make false in
  let node = Sop.custom ~operation:"async_volatile_test" ~version:1 ~parameters:""
      [Sop.points [|0., 0., 0.|]] (fun ~context:_ inputs ->
        Atomic.set entered true;
        while not (Atomic.get release) do Unix.sleepf 0.001 done;
        Ok inputs.(0)) in
  let again () = Node.Private.adopt_identity ~source:node
      (Sop.custom ~operation:"async_volatile_test" ~version:1 ~parameters:"again"
        [Sop.points [|0., 0., 0.|]] (fun ~context:_ inputs ->
          Atomic.set entered true;
          while not (Atomic.get release) do Unix.sleepf 0.001 done;
          Ok inputs.(0))) in
  let predicate answer id =
    if Domain.self () = main then Atomic.set off_worker true;
    answer && id = Node.id node in
  let prepare _ = Ok () in
  let cook node =
    ignore (Async_cook.submit worker ~context:(context ()) ~node ~prepare |> get_ok) in
  Async_cook.set_volatile worker (predicate true);
  cook node;
  ignore (Async_cook.await worker);
  check ((Async_cook.stats worker).volatile_entries = 1)
    "the request did not carry its volatile predicate";
  Atomic.set release false;
  Atomic.set entered false;
  cook (again ());
  ignore (wait_until (fun () -> if Atomic.get entered then Some () else None));
  Async_cook.set_volatile worker (predicate false);
  check (not (Atomic.get off_worker))
    "set_volatile ran the predicate on the caller's domain during a cook";
  Atomic.set release true;
  ignore (Async_cook.await worker);
  check ((Async_cook.stats worker).volatile_entries = 1)
    "set_volatile changed the session under the cook in flight";
  cook node;
  ignore (Async_cook.await worker);
  check ((Async_cook.stats worker).volatile_entries = 0 && not (Atomic.get off_worker))
    "the next request did not install the new volatile predicate on the worker";
  Async_cook.close worker

let test_async_await () =
  let worker = Async_cook.create ~max_entries:4 ~max_payload_bytes:4_000_000 |> get_ok in
  let node = Sop.points [|0., 0., 0.; 1., 0., 0.|] in
  let prepare output = Ok (Rdk.Geometry.point_count output.Session.geometry) in
  ignore (Async_cook.submit worker ~context:(context ()) ~node ~prepare |> get_ok);
  let completion = Async_cook.await worker in
  check (completion.result = Ok 2 && Async_cook.status worker = Idle
    && Async_cook.poll worker = None) "await did not return the submitted cook";
  check ((Async_cook.stats worker).misses = 1) "await: the session did not cook";
  check (match Async_cook.await worker with _ -> false | exception Invalid_argument _ -> true)
    "await without a request returned";
  (* optional nodes: cooked after the required ones, a failing one is [None] and fails nothing *)
  let failing = Sop.custom ~operation:"async_test_fail" ~version:1 [Sop.points [|0., 0., 0.|]]
      (fun ~context:_ _ -> Error "no geometry") in
  let other = Sop.points [|0., 0., 0.; 1., 0., 0.; 2., 0., 0.|] in
  Async_cook.close worker;
  let worker = Async_cook.create ~max_entries:4 ~max_payload_bytes:4_000_000 |> get_ok in
  ignore (Async_cook.submit_some worker ~context:(context ()) ~nodes:[node]
    ~optional:[failing; other]
    ~prepare:(fun outputs optional -> Ok (List.length outputs, List.map Option.is_some optional)) |> get_ok);
  check ((Async_cook.await worker).result = Ok (1, [false; true]))
    "a failing optional node failed the request or hid the others";
  Async_cook.close worker

let run () =
  test_volatile_slots ();
  test_async_await ();
  test_async_volatile_on_worker ();
  test_node_owned_parameters_and_graph_edit ();
  test_shared_input_memo ();
  test_encoded_parameter ();
  test_async_cook_latest_request ();
  test_static_context_cache ();
  test_grid_generator_contract ();
  test_circle_generator_contract ();
  test_box_generator_contract ();
  test_uv_sphere_generator_contract ();
  test_torus_generator_contract ();
  test_tube_generator_contract ();
  test_platonic_generator_contract ();
  test_spiral_generator_contract ();
  test_declared_seed_dependency ();
  test_labeled_random_identity ();
  test_switch_is_lazy ();
  test_lru_limits_and_lifetime ();
  test_shared_payload_accounting ();
  test_error_trace_and_cancellation ();
  test_inspection_sharing_and_bridge ();
  test_packed_instances ();
  test_snapshot_feedback_boundary ();
  test_parallel_geometry_exactness ();
  test_generators_selections_and_delete ();
  test_poly_fill_contract ();
  test_poly_path_contract ();
  test_revolve_contract ();
  test_sweep_contract ();
  test_local_subdivide_contract ();
  test_edge_divide_contract ();
  test_edge_collapse_contract ();
  test_edge_flip_contract ();
  test_edge_cusp_contract ();
  test_edge_straighten_contract ();
  test_edge_equalize_contract ();
  test_edge_relax_contract ();
  test_blend_shapes_contract ();
  test_attribute_composite_contract ();
  test_edge_transport_contract ();
  test_packed_copy_contract ();
  print_endline "procedural tests passed"
