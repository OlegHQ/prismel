let fail message = raise (Failure message)
let pointer (x, y) = float x, float y
let mouse_press (button, point) = Prismel.Event.MousePressed (button, pointer point)
let mouse_release (button, point) = Prismel.Event.MouseReleased (button, pointer point)
let mouse_move point = Prismel.Event.MouseMoved (pointer point)

let run_1 () =
  if not Prismel.Sketch.default_config.resizable then
    fail "high-level sketch windows are not resizable by default";
  Prismel.Input.reset ~mouse:(10., 10.);
  Prismel.Input.begin_frame ();
  Prismel.Input.update_mouse_pos 13. 14.;
  Prismel.Input.update_mouse_pos 20. 25.;
  if Prismel.Input.mouse_pos () <> (20., 25.)
     || Prismel.Input.mouse_delta () <> (10., 15.)
  then fail "mouse delta did not accumulate every event in the frame";
  Prismel.Input.begin_frame ();
  if Prismel.Input.mouse_delta () <> (0., 0.) then
    fail "mouse delta remained stale on an idle frame";
  let squares = Prismel.Parallel.map ~grain:1 (fun x -> x * x) [1; 2; 3; 4] in
  if squares <> [1; 4; 9; 16] then
    fail "parallel map did not preserve order";
  let initialized = Prismel.Parallel.init_array ~grain:1 10_000
      (fun index -> index * index) in
  if initialized.(0) <> 0 || initialized.(9_999) <> 99_980_001 then
    fail "parallel array initialization returned incorrect values";
  let mapped = Prismel.Parallel.map_array ~grain:1
      (fun value -> value + 1) initialized in
  if mapped.(5_000) <> 25_000_001 then
    fail "parallel array map returned incorrect values";
  let nested = Prismel.Parallel.map_array ~grain:1 (fun value ->
      Prismel.Parallel.map_array ~grain:1 (( + ) value) [|1;2;3|])
      [|10;20|] in
  if nested <> [|[|11;12;13|]; [|21;22;23|]|] then
    fail "nested parallel array map returned incorrect values";
  let left, right =
    Prismel.Parallel.run ~domains:2 (fun () ->
      Prismel.Parallel.both (fun () -> 20 + 1) (fun () -> 6 * 7))
  in
  if left <> 21 || right <> 42 then
    fail "parallel computations returned incorrect values";
  let calling_domain = Domain.self () in
  let sequential_domains =
    Prismel.Parallel.run ~domains:1 (fun () ->
      Prismel.Parallel.init_array ~grain:1 10_000 (fun _ -> Domain.self ()))
  in
  if not (Array.for_all (( = ) calling_domain) sequential_domains) then
    fail "Parallel.run ~domains:1 allowed nested work onto another domain";
  let cutoff_domains, cutoff_for_domain =
    Prismel.Parallel.run ~domains:2 (fun () ->
      let values = Prismel.Parallel.init_array ~grain:64 8
          (fun _ -> Domain.self ()) in
      let observed = ref (Domain.self ()) in
      Prismel.Parallel.for_ ~chunk_size:64 ~start:0 ~finish:7
        (fun _ -> observed := Domain.self ());
      values, !observed)
  in
  if not (Array.for_all (( = ) calling_domain) cutoff_domains)
     || cutoff_for_domain <> calling_domain
  then fail "nested parallel work ignored its sequential grain cutoff";
  if not (Prismel.Color.equal
      (Prismel.Color.hsv 0. 1. 1.) Prismel.Color.red) then
    fail "HSV red conversion is incorrect";
  if not (Prismel.Color.equal
      (Prismel.Color.hsl 180. 1. 0.5) Prismel.Color.cyan) then
    fail "HSL cyan conversion is incorrect";
  (match Prismel.Color.hex "#369c" with
   | Ok { r = 0x33; g = 0x66; b = 0x99; a = 0xcc } -> ()
   | _ -> fail "short RGBA hex parsing is incorrect");
  let samples generator =
    let a, generator = Prismel.Rand.int ~bound:10_000 generator in
    let b, generator = Prismel.Rand.float generator in
    let c, _ = Prismel.Rand.bool generator in
    a, b, c
  in
  if samples (Prismel.Rand.seed 42) <> samples (Prismel.Rand.seed 42) then
    fail "equal random seeds were not reproducible";
  let indexed = Prismel.Rand.seed64 0x7eed_1234_5678_9abcL in
  let indexed_values = Array.init 10_000 (fun index ->
      Prismel.Rand.float_at indexed ~index) in
  if indexed_values <> Array.init 10_000 (fun index ->
      Prismel.Rand.float_at indexed ~index)
      || Array.exists (fun value -> value < 0. || value >= 1.) indexed_values
      || indexed_values.(17) = indexed_values.(18) then
    fail "indexed random sampling is not stable or escaped [0, 1)";
  let noise_a = Prismel.Noise.create 17 in
  let noise_b = Prismel.Noise.create 17 in
  let sample_a = Prismel.Noise.fbm2 noise_a ~x:1.25 ~y:(-3.5) in
  let sample_b = Prismel.Noise.fbm2 noise_b ~x:1.25 ~y:(-3.5) in
  if sample_a <> sample_b then fail "equal noise seeds were not reproducible";
  if sample_a < 0. || sample_a > 1. then fail "noise sample escaped 0..1";
  let nearby = Prismel.Noise.sample2 noise_a ~x:1.251 ~y:(-3.5) in
  let base = Prismel.Noise.sample2 noise_a ~x:1.25 ~y:(-3.5) in
  if abs_float (nearby -. base) > 0.05 then
    fail "coherent noise was discontinuous for nearby inputs";
  let path =
    Prismel.Path.empty
    |> Prismel.Path.move_to 0. 0.
    |> Prismel.Path.line_to 10. 0.
    |> Prismel.Path.quadratic_to ~control:(15., 5.) ~to_:(10., 10.)
    |> Prismel.Path.cubic_to
         ~control1:(5., 15.) ~control2:(0., 15.) ~to_:(0., 10.)
    |> Prismel.Path.close
  in
  let points = Prismel.Path.points ~steps:4 path in
  if List.hd points <> (0, 0)
     || List.hd (List.rev points) <> (0, 0)
     || List.length points <> 11 then
    fail "path flattening did not preserve endpoints and samples";
  let multi =
    path
    |> Prismel.Path.move_to 3. 3.
    |> Prismel.Path.line_to 4. 3.
    |> Prismel.Path.line_to 4. 4.
    |> Prismel.Path.close
  in
  (match Prismel.Path.contours ~steps:4 multi with
   | [outer; inner]
     when List.length outer = 11 && List.length inner = 4 -> ()
   | _ -> fail "path flattening joined separate contours");
  let open Prismel in
  let transform =
    Mat4.mul
      (Mat4.translation (Vec3.create 3. (-2.) 5.))
      (Mat4.mul
         (Mat4.rotation_y 0.7)
         (Mat4.scaling (Vec3.create 2. 3. 4.)))
  in
  let inverse =
    match Mat4.inverse transform with
    | Some inverse -> inverse
    | None -> fail "invertible 3D transform was reported singular"
  in
  let point = Vec3.create 1.25 (-0.5) 3. in
  let round_trip =
    Mat4.transform_point inverse (Mat4.transform_point transform point)
  in
  if not (Vec3.nearly_equal point round_trip ~eps:1e-9) then
    fail "Mat4 inverse did not restore a transformed point";
  let camera =
    Camera.perspective ~at:(Vec3.create 0. 0. 5.) ~target:Vec3.zero ()
  in
  let linear_fog =
    Fog3.linear ~color:(Color.gray 128) ~start:2. ~end_:6.
  and exponential_fog =
    Fog3.exponential ~color:(Color.gray 128) ~density:0.5
  and squared_fog =
    Fog3.exponential_squared ~color:(Color.gray 128) ~density:0.5
  in
  if Fog3.Private.visibility linear_fog ~distance:0. <> 1.
     || Fog3.Private.visibility linear_fog ~distance:4. <> 0.5
     || Fog3.Private.visibility linear_fog ~distance:8. <> 0.
     || abs_float
          (Fog3.Private.visibility exponential_fog ~distance:2. -. exp (-1.))
        > 1e-12
     || abs_float
          (Fog3.Private.visibility squared_fog ~distance:2. -. exp (-1.))
        > 1e-12
  then fail "standard 3D fog visibility equations are incorrect";
  let viewport = 0, 0, 640, 360 in
  let screen =
    match Camera.world_to_screen ~viewport camera Vec3.zero with
    | Some point -> point
    | None -> fail "camera rejected a visible world point"
  in
  if abs_float (screen.x -. 320.) > 1e-6
     || abs_float (screen.y -. 180.) > 1e-6
  then fail "perspective camera did not project the origin to viewport center";
  let restored =
    match Camera.screen_to_world ~viewport camera screen with
    | Some point -> point
    | None -> fail "camera could not unproject its own screen point"
  in
  if not (Vec3.nearly_equal restored Vec3.zero ~eps:1e-8) then
    fail "camera screen/world round trip changed a visible point";
  let camera_point = Camera.world_to_camera camera (Vec3.create 1. 2. 0.) in
  let world_point =
    match Camera.camera_to_world camera camera_point with
    | Some point -> point
    | None -> fail "camera view matrix was unexpectedly singular"
  in
  if not (Vec3.nearly_equal world_point (Vec3.create 1. 2. 0.) ~eps:1e-9)
  then fail "world/camera coordinate conversion did not round-trip";
  let above =
    match
      Camera.world_to_screen ~viewport camera (Vec3.create 0. 1. 0.)
    with
    | Some point -> point
    | None -> fail "camera rejected a visible point above its target"
  in
  let flipped_above =
    match
      Camera.world_to_screen ~viewport
        (Camera.with_v_flip true camera)
        (Vec3.create 0. 1. 0.)
    with
    | Some point -> point
    | None -> fail "V-flipped camera rejected a visible world point"
  in
  if above.y >= 180. || flipped_above.y <= 180. then
    fail "Camera V-flip did not mirror projected screen Y";
  let portal_camera =
    Camera.off_axis_portal
      ~eye:(Vec3.create 0. 0. 5.)
      ~top_left:(Vec3.create (-2.) 1. 0.)
      ~bottom_left:(Vec3.create (-2.) (-1.) 0.)
      ~bottom_right:(Vec3.create 2. (-1.) 0.)
      ()
  in
  let portal_center =
    match Camera.world_to_screen ~viewport portal_camera Vec3.zero with
    | Some point -> point
    | None -> fail "off-axis portal camera rejected the portal center"
  in
  if abs_float (portal_center.x -. 320.) > 1e-6
     || abs_float (portal_center.y -. 180.) > 1e-6
  then fail "off-axis portal center did not project to viewport center";
  let asymmetric_camera =
    Camera.off_axis_portal
      ~eye:(Vec3.create 1. 0. 5.)
      ~top_left:(Vec3.create (-2.) 1. 0.)
      ~bottom_left:(Vec3.create (-2.) (-1.) 0.)
      ~bottom_right:(Vec3.create 2. (-1.) 0.)
      ()
  in
  let asymmetric_center =
    match Camera.world_to_screen ~viewport asymmetric_camera Vec3.zero with
    | Some point -> point
    | None -> fail "asymmetric portal camera rejected the portal center"
  in
  if abs_float (asymmetric_center.x -. 320.) > 1e-6
     || abs_float (asymmetric_center.y -. 180.) > 1e-6
  then fail "off-axis portal projection did not compensate for eye position";
  let frustum = Camera.frustum_mesh ~viewport asymmetric_camera in
  if Mesh.mode frustum <> Mesh.Lines || Mesh.vertex_count frustum <> 24 then
    fail "camera frustum diagnostic mesh did not contain twelve line edges";
  let forced =
    Camera.with_forced_aspect (Some 1.) camera
    |> Camera.move (Vec3.create 1. 0. 0.)
  in
  if Camera.aspect_ratio ~viewport forced <> 1.
     || Camera.forced_aspect forced <> Some 1.
     || Camera.image_plane_distance ~viewport forced
        <> Some (360. /. (2. *. tan (Float.pi /. 6.)))
  then fail "camera forced aspect or image-plane distance was not preserved";
  let easy = Easy_camera.create ~distance:5. () in
  let frame : Frame.t = {
    width = 640;
    height = 360;
    size = 640, 360;
    drawable_width = 640;
    drawable_height = 360;
    drawable_size = 640, 360;
    pixel_scale = 1., 1.;
    time = 0.;
    dt = 1. /. 60.;
    fps = 60.;
    count = 0;
    mouse = 130., 80.;
    mouse_delta = 30., 30.;
    keys = [];
    mouse_buttons = [Input.LeftButton];
    events = [
      mouse_press (Input.LeftButton, (100, 50));
      mouse_move (130, 80);
      mouse_release (Input.LeftButton, (130, 80));
    ];
  } in
  if Easy_camera.camera easy != Easy_camera.camera easy then
    fail "easy camera did not retain an unchanged derived camera";
  if Easy_camera.camera (Easy_camera.with_distance 6. easy)
      == Easy_camera.camera easy then
    fail "easy camera reused a derived camera after a parameter change";
  (* The camera panel is built inside a UI frame; a settle frame lays it out
     before each press. *)
  let module Camera_control = Pxui.Camera_control in
  let camera_ui = Pxui.Ui.create () in
  let run control camera (frame : Frame.t) =
    let control, camera, requests = Pxui.Ui.frame camera_ui frame (fun ui ->
      if Camera_control.ui_visible control then
        Pxui.Ui.panel ui ~x:0. ~y:0. ~width:240. "camera-panel"
          (fun () -> Camera_control.widgets control ui ~camera)
      else control, camera, []) in
    let area = if Camera_control.ui_visible control then 248, 0, 392, 360
      else 0, 0, frame.width, frame.height in
    control, Camera_control.navigate ~control_area:area control camera frame,
    requests in
  let idle = { frame with mouse_buttons = []; events = [] } in
  let click point = { frame with mouse = pointer point; mouse_buttons = [];
    events = [mouse_press (Input.LeftButton, point);
      mouse_release (Input.LeftButton, point)] } in
  let camera_control = Camera_control.create () in
  let camera_control, _, _ = run camera_control easy idle in
  (* Rows: Camera, Render; opening Render adds Output and the save button. *)
  let camera_control, _, _ = run camera_control easy (click (30, 39)) in
  let camera_control, _, _ = run camera_control easy idle in
  let camera_control, _, requests = run camera_control easy (click (30, 87)) in
  if List.map (fun (request : Camera_control.render_request) -> request.filename)
      requests <> ["_out/prismel-render.png"]
  then fail "camera render section did not request a PNG";
  let camera_control, controlled, _ =
    run (Camera_control.open_camera camera_control) easy idle in
  if Easy_camera.control_area controlled <> Some (248, 0, 392, 360)
  then fail "camera control did not reserve the gesture area beside its panel";
  let camera_control, _, _ = run camera_control controlled idle in
  (* The Camera section is open: its FOV slider is the second row. *)
  let fov_frame = { idle with mouse = 200., 39.;
    events = [mouse_press (Input.LeftButton, (200, 39));
      mouse_release (Input.LeftButton, (200, 39))] } in
  let camera_control, widened, _ = run camera_control controlled fov_frame in
  if Easy_camera.fov_y widened = Easy_camera.fov_y controlled
  then fail "camera control open_camera did not open its FOV slider";
  let scroll_frame = { idle with mouse = 320., 100.;
    events = [Event.MouseScrolled (0., 2.)] } in
  let camera_control, zoomed, _ = run camera_control controlled scroll_frame in
  let _, fractional_zoom, _ = run camera_control controlled
      { scroll_frame with mouse = 320.25, 100.5;
        events = [Event.MouseScrolled (0., 0.3)] } in
  if Easy_camera.distance fractional_zoom = Easy_camera.distance controlled then
    fail "camera ignored a fractional wheel delta";
  let camera_control, zoomed_idle, _ = run camera_control zoomed
      { scroll_frame with events = [] } in
  if Easy_camera.distance zoomed = Easy_camera.distance controlled
     || Easy_camera.distance zoomed_idle <> Easy_camera.distance zoomed
  then fail "camera control undid or failed to apply trackpad zoom";
  let horizontal_scroll_frame = { idle with mouse = 320., 100.;
    events = [Event.MouseScrolled (2., 0.)] } in
  let camera_control, horizontal_ignored, _ =
    run camera_control zoomed_idle horizontal_scroll_frame in
  if not (Vec3.nearly_equal (Easy_camera.target horizontal_ignored)
      (Easy_camera.target zoomed_idle) ~eps:1e-9)
     || Easy_camera.distance horizontal_ignored <> Easy_camera.distance zoomed_idle
  then fail "horizontal trackpad scrolling unexpectedly moved the camera";
  let drag button = { frame with mouse = 330., 90.; mouse_buttons = [button];
    events = [mouse_press (button, (300, 60)); mouse_move (330, 90);
      mouse_release (button, (330, 90))] } in
  let camera_control, right_panned, _ =
    run camera_control horizontal_ignored (drag Input.RightButton) in
  if Vec3.nearly_equal (Easy_camera.target right_panned)
      (Easy_camera.target horizontal_ignored) ~eps:1e-9
     || Easy_camera.distance right_panned <> Easy_camera.distance horizontal_ignored
  then fail "camera control did not map right-drag to pan";
  let camera_control, panned, _ =
    run camera_control right_panned (drag Input.MiddleButton) in
  if Vec3.nearly_equal (Easy_camera.target panned)
      (Easy_camera.target right_panned) ~eps:1e-9
  then fail "camera control did not preserve default middle-drag pan";
  let hidden_control, _, _ = run (Camera_control.toggle_ui camera_control) panned idle in
  if Camera_control.ui_visible hidden_control
     || Pxui.Ui.scene camera_ui <> []
  then fail "camera control toggle_ui did not hide all UI";
  let shown_control, _, _ = run (Camera_control.open_camera hidden_control) panned idle in
  if not (Camera_control.ui_visible shown_control)
     || Pxui.Ui.scene camera_ui = []
  then fail "camera control open_camera did not reveal its UI";
  Pxui.Ui.destroy camera_ui;
  let easy = Easy_camera.update easy frame in
  if Vec3.nearly_equal
       (Camera.position (Easy_camera.camera easy))
       (Vec3.create 0. 0. 5.) ~eps:1e-6
  then fail "easy camera did not orbit after a captured pointer drag";
  let outside =
    Easy_camera.create ~distance:5. ~control_area:(0, 0, 50, 50) ()
    |> Fun.flip Easy_camera.update frame
  in
  if not
       (Vec3.nearly_equal
          (Camera.position (Easy_camera.camera outside))
          (Vec3.create 0. 0. 5.) ~eps:1e-9)
  then fail "easy camera accepted a press outside its control area";
  let panning =
    Easy_camera.create ~distance:5. ~inertia:false ()
    |> Easy_camera.clear_interactions
    |> Easy_camera.add_interaction ~button:Input.LeftButton Easy_camera.Pan
    |> Fun.flip Easy_camera.update frame
  in
  if Vec3.nearly_equal (Easy_camera.target panning) Vec3.zero ~eps:1e-9 then
    fail "easy camera custom interaction did not remap left drag to pan";
  if
    not
      (Easy_camera.has_interaction ~button:Input.LeftButton Easy_camera.Pan
         panning)
  then fail "easy camera did not report its custom interaction";
  let viewed = Easy_camera.of_view ~eye:(Vec3.create 3. 4. (-5.))
      ~target:(Vec3.create 1. 1. 1.) (Easy_camera.create ()) in
  if not (Vec3.nearly_equal (Camera.position (Easy_camera.camera viewed))
      (Vec3.create 3. 4. (-5.)) ~eps:1e-9)
     || Easy_camera.target viewed <> Vec3.create 1. 1. 1.
  then fail "easy camera of_view did not reproduce the requested eye";
  let framed = Easy_camera.frame_bounds ~min:(Vec3.create (-1.) (-1.) (-1.))
      ~max:(Vec3.create 3. 1. 1.) (Easy_camera.create ~fov_y:(Float.pi /. 2.) ()) in
  if not (Vec3.nearly_equal (Easy_camera.target framed) (Vec3.create 1. 0. 0.) ~eps:1e-12)
     || Float.abs (Easy_camera.distance framed -. (sqrt 6. *. 1.2)) > 1e-9
  then fail "easy camera frame_bounds did not target the center at radius/tan(fov/2)*1.2";
  (* One fly frame: W moves forward speed*dt; pointer motion right turns
     right; a wheel step scales the speed. *)
  let fly_start = Easy_camera.create ~distance:5. ~inertia:false () in
  let still = { frame with dt = 0.5; mouse_delta = (0., 0.); events = []; keys = [] } in
  let flown, speed = Easy_camera.fly ~speed:2. fly_start
      { still with keys = [Input.KeyChar 'w'] } in
  if not (Vec3.nearly_equal (Camera.position (Easy_camera.camera flown))
      (Vec3.create 0. 0. 4.) ~eps:1e-9) || speed <> 2.
  then fail "fly W did not move forward by speed * dt";
  let turned, _ = Easy_camera.fly ~speed:2. fly_start
      { still with mouse_delta = (100., 0.) } in
  let look camera = let view = Easy_camera.camera camera in
    Vec3.sub (Camera.target view) (Camera.position view) in
  if (look turned).x <= 0.
     || not (Vec3.nearly_equal (Camera.position (Easy_camera.camera turned))
       (Vec3.create 0. 0. 5.) ~eps:1e-9)
  then fail "fly pointer motion did not yaw right in place";
  let _, faster = Easy_camera.fly ~speed:2. fly_start
      { still with events = [Event.MouseScrolled (0., 1.)] } in
  if Float.abs (faster -. 2.4) > 1e-12 then fail "fly wheel did not scale speed";
  let translated_frame = { frame with keys = [Input.Space] } in
  let translated =
    Easy_camera.create ~distance:5. ~inertia:false
      ~translation_key:Input.Space ()
    |> Fun.flip Easy_camera.update translated_frame
  in
  if Vec3.nearly_equal (Easy_camera.target translated) Vec3.zero ~eps:1e-9 then
    fail "easy camera translation key did not switch orbit to pan";
  let auto_distance =
    Easy_camera.create ~distance:5. ~auto_distance:true ()
    |> Fun.flip Easy_camera.update { frame with events = [] }
  in
  let expected_distance =
    360. /. (2. *. tan (Float.pi /. 6.))
  in
  if abs_float (Easy_camera.distance auto_distance -. expected_distance) > 1e-9
  then fail "easy camera auto-distance did not fit the logical viewport";
  let reset_frame =
    {
      frame with
      time = 1.;
      mouse = 130., 80.;
      mouse_buttons = [];
      events = [
        mouse_press (Input.LeftButton, (130, 80));
        mouse_release (Input.LeftButton, (130, 80));
        mouse_press (Input.LeftButton, (130, 80));
        mouse_release (Input.LeftButton, (130, 80));
      ];
    }
  in
  let easy = Easy_camera.update easy reset_frame in
  if not
       (Vec3.nearly_equal
          (Camera.position (Easy_camera.camera easy))
          (Vec3.create 0. 0. 5.) ~eps:1e-9)
  then fail "easy camera double-click did not reset its initial view";
  let drag_frame =
    {
      frame with
      time = 2.;
      events = [
        mouse_press (Input.LeftButton, (100, 50));
        mouse_move (120, 50);
      ];
    }
  in
  let release_frame =
    {
      frame with
      time = 2. +. (1. /. 60.);
      mouse = 120., 50.;
      mouse_delta = 0., 0.;
      mouse_buttons = [];
      events = [mouse_release (Input.LeftButton, (120, 50))];
    }
  in
  let inertial = Easy_camera.create ~distance:5. () in
  let dragging = Easy_camera.update inertial drag_frame in
  let released = Easy_camera.update dragging release_frame in
  if Vec3.nearly_equal
       (Camera.position (Easy_camera.camera dragging))
       (Camera.position (Easy_camera.camera released)) ~eps:1e-9
  then fail "easy camera inertia did not continue after pointer release";
  let up_camera =
    Easy_camera.create ~distance:5. ~up_axis:Vec3.unit_z ()
    |> Easy_camera.camera
  in
  if not (Vec3.nearly_equal (Camera.up up_camera) Vec3.unit_z ~eps:1e-9) then
    fail "easy camera did not preserve its configured up axis";
  let parent =
    Node3.create ~position:(Vec3.create 2. 0. 0.)
      ~orientation:(Quat.axis_angle ~axis:Vec3.unit_y (Float.pi /. 2.)) ()
  in
  let child =
    Node3.create ~position:(Vec3.create 0. 0. (-1.)) ~parent ()
  in
  if not
       (Vec3.nearly_equal (Node3.global_position child)
          (Vec3.create 1. 0. 0.) ~eps:1e-9)
  then fail "hierarchical Node3 transform did not include its parent";
  let detached = Node3.clear_parent ~maintain_global:true child in
  if not
       (Vec3.nearly_equal (Node3.global_position detached)
          (Node3.global_position child) ~eps:1e-9)
  then fail "Node3 lost its global transform while clearing its parent";
  let euler = Vec3.create 0.2 (-0.4) 0.3 in
  let euler_node =
    Node3.create
      ~orientation:
        (Quat.of_euler ~pitch:euler.x ~yaw:euler.y ~roll:euler.z)
      ()
  in
  if not (Vec3.nearly_equal (Node3.euler euler_node) euler ~eps:1e-9) then
    fail "Node3 Euler-angle query did not invert quaternion construction";
  let desired_global =
    Quat.axis_angle ~axis:Vec3.unit_z (Float.pi /. 4.)
  in
  let oriented_child = Node3.set_global_orientation desired_global child in
  if not
       (Quat.nearly_equal (Node3.global_orientation oriented_child)
          desired_global ~eps:1e-9)
  then fail "Node3 global-orientation setter ignored its parent";
  let around =
    Node3.create ~position:Vec3.unit_x ()
    |> Node3.rotate_around ~point:Vec3.zero
         (Quat.axis_angle ~axis:Vec3.unit_z (Float.pi /. 2.))
  in
  if not
       (Vec3.nearly_equal (Node3.global_position around) Vec3.unit_y
          ~eps:1e-9)
  then fail "Node3.rotate_around did not rotate the global position";
  let local = Vec3.create 0.25 0.5 (-0.75) in
  let global = Node3.local_to_global_point child local in
  (match Node3.global_to_local_point child global with
   | Some recovered when Vec3.nearly_equal recovered local ~eps:1e-9 -> ()
   | _ -> fail "Node3 local/global point conversion did not round-trip");
  let facing =
    Node3.create ~position:(Vec3.create 0. 0. 2.) ()
    |> Node3.look_at Vec3.zero
  in
  if not
       (Vec3.nearly_equal (Node3.look_direction facing)
          (Vec3.create 0. 0. (-1.)) ~eps:1e-9)
  then fail "Node3.look_at did not orient local negative Z at its target";
  let box = Mesh.box ~width:2. ~height:3. ~depth:4. () in
  if Mesh.vertex_count box <> 24
     || Mesh.index_count box <> 36
     || not (Mesh.has_normals box)
     || not (Mesh.has_tex_coords box)
  then fail "box primitive did not preserve six independently shaded faces";
  let positive_x =
    Mesh.box_side ~side:Mesh.Positive_x
      ~width:2. ~height:3. ~depth:4. ()
  in
  if Mesh.vertex_count positive_x <> 4
     || not
          (List.for_all
             (fun normal ->
               Vec3.nearly_equal normal Vec3.unit_x ~eps:1e-9)
             (Mesh.normals positive_x))
  then fail "box side extraction returned the wrong face orientation";
  let first_view = Mesh.Private.packed_view box
  and second_view = Mesh.Private.packed_view box in
  if first_view.vertices.x != second_view.vertices.x
     || first_view.vertices.y != second_view.vertices.y
     || first_view.vertices.z != second_view.vertices.z
     || first_view.indices != second_view.indices
  then fail "renderer packed mesh views copied persistent geometry buffers";
  let replacement = Vec3.create 9. 8. 7. in
  let edited_box =
    match Mesh.with_vertex 0 replacement box with
    | Ok mesh -> mesh
    | Error message -> fail message
  in
  if Mesh.vertex 0 edited_box <> Some replacement
     || Mesh.vertex 0 box = Some replacement
     || Mesh.vertex (-1) box <> None
  then fail "immutable per-vertex mesh editing mutated or misread its source";
  let box_faces = Mesh.faces box in
  if List.length box_faces <> 12
     || List.exists
          (fun face ->
            abs_float (Vec3.length face.Mesh.face_normal -. 1.) > 1e-9
            || Option.is_none face.vertex_normals
            || Option.is_none face.vertex_tex_coords)
          box_faces
  then fail "mesh face extraction lost triangle attributes or face normals";
  if Mesh.face 0 box <> List.nth_opt box_faces 0
     || Mesh.face 12 box <> None
     || Mesh.face_normals box <> List.map (fun face -> face.Mesh.face_normal) box_faces
  then fail "mesh indexed face/normal queries diverged from face extraction";
  let box_centroid =
    match Mesh.centroid box with
    | Some centroid -> centroid
    | None -> fail "non-empty mesh did not have a centroid"
  in
  if not (Vec3.nearly_equal box_centroid Vec3.zero ~eps:1e-9)
     || Mesh.centroid (Mesh.clear box) <> None
  then fail "mesh centroid did not average all vertices";
  let duplicate_points =
    Mesh.create_exn ~mode:Mesh.Points
      [Vec3.zero; Vec3.unit_x; Vec3.zero]
    |> Mesh.merge_duplicate_vertices
  in
  if Mesh.vertex_count duplicate_points <> 2
     || Mesh.indices duplicate_points <> [0; 1; 0]
  then fail "duplicate-vertex merging did not remap indices deterministically";
  let tolerant_duplicates =
    Mesh.create_exn ~mode:Mesh.Points
      [ Vec3.create 0. 0. 0.; Vec3.create 0.15 0. 0.;
        Vec3.create 0.075 0. 0. ]
    |> Mesh.merge_duplicate_vertices ~epsilon:0.1
  in
  if Mesh.vertex_count tolerant_duplicates <> 2
     || Mesh.indices tolerant_duplicates <> [0; 1; 0]
  then
    fail
      "tolerant duplicate merging missed an adjacent cell or earliest source";
  let seam_vertices =
    let point = Vec3.create 2. 3. 4. in
    Mesh.create_exn ~mode:Mesh.Points
      ~normals:[Vec3.unit_x; Vec3.unit_y; Vec3.unit_x; Vec3.unit_x]
      ~colors:[Color.red; Color.red; Color.green; Color.red]
      ~tex_coords:
        [ Vec2.zero; Vec2.zero; Vec2.zero; Vec2.create 0.25 0. ]
      [point; point; point; point]
    |> Mesh.merge_duplicate_vertices ~epsilon:0.1
  in
  if Mesh.vertex_count seam_vertices <> 4 then
    fail "duplicate merging collapsed a normal, color, or texture seam";
  let huge_duplicates =
    Mesh.create_exn ~mode:Mesh.Points
      [ Vec3.create 1e300 0. 0.; Vec3.create 1e300 5e-301 0. ]
    |> Mesh.merge_duplicate_vertices ~epsilon:1e-300
  in
  if Mesh.vertex_count huge_duplicates <> 1
     || Mesh.indices huge_duplicates <> [0; 0]
  then fail "duplicate merging overflowed its spatial cell coordinates";
  let removable =
    Mesh.create_exn ~mode:Mesh.Lines ~indices:[0; 1]
      [Vec3.zero; Vec3.unit_x; Vec3.unit_y]
  in
  let removable =
    match Mesh.remove_vertex 2 removable with
    | Ok mesh -> mesh
    | Error message -> fail message
  in
  if Mesh.vertex_count removable <> 2
     || Result.is_ok (Mesh.remove_vertex 0 removable)
  then fail "safe mesh vertex removal allowed a dangling index";
  let recolored =
    match Mesh.with_color_for_indices ~first:0 ~count:2 Color.magenta removable with
    | Ok mesh -> mesh
    | Error message -> fail message
  in
  if Mesh.colors recolored <> [Color.magenta; Color.magenta] then
    fail "mesh index-range coloring did not color referenced vertices";
  let remapped_plane =
    match
      Mesh.plane ~width:2. ~height:2. ()
      |> Mesh.remap_tex_coords ~u1:0.25 ~v1:0.5 ~u2:0.75 ~v2:1.
    with
    | Ok mesh -> mesh
    | Error message -> fail message
  in
  if
    List.exists
      (fun uv ->
        uv.Vec2.x < 0.25 || uv.x > 0.75 || uv.y < 0.5 || uv.y > 1.)
      (Mesh.tex_coords remapped_plane)
  then fail "mesh texture-coordinate remapping escaped its target rectangle";
  let crease =
    Mesh.create_exn ~indices:[0; 1; 2; 0; 2; 3]
      [Vec3.zero; Vec3.unit_x; Vec3.unit_y; Vec3.unit_z]
  in
  let sharp = Mesh.smooth_normals ~angle:0. crease
  and smooth = Mesh.smooth_normals ~angle:Float.pi crease in
  if Mesh.vertex_count sharp <> 6 || Mesh.vertex_count smooth <> 4 then
    fail "angle-aware smooth normals did not split/preserve a hard crease";
  if Mesh.vertex_count (Mesh.normal_lines ~length:1. box) <> 48
     || Mesh.vertex_count
          (Mesh.normal_lines ~face_normals:true ~length:1. box) <> 24
     || Mesh.vertex_count (Mesh.icosahedron ~radius:1.) <> 12
  then fail "mesh normal diagnostics or icosahedron geometry are incomplete";
  let box_side =
    match Mesh.submesh ~first:0 ~count:6 box with
    | Ok mesh -> mesh
    | Error message -> fail message
  in
  if Mesh.index_count box_side <> 6
     || Mesh.vertex_count box_side <> 4
     || not (Mesh.has_normals box_side)
     || not (Mesh.has_tex_coords box_side)
  then fail "compact mesh subrange extraction lost indexed attributes";
  let flat_sphere = Mesh.flat_shaded (Mesh.sphere ~segments:8 ~rings:4 ~radius:2. ()) in
  if Mesh.vertex_count flat_sphere <> Mesh.index_count flat_sphere
     || not (Mesh.has_normals flat_sphere)
  then fail "flat shading did not split shared triangle vertices";
  let sphere = Mesh.sphere ~segments:8 ~rings:4 ~radius:2. () in
  if Mesh.vertex_count sphere <> 45
     || Mesh.index_count sphere <> 192
     || not (List.for_all
       (fun normal -> abs_float (Vec3.length normal -. 1.) < 1e-9)
       (Mesh.normals sphere))
  then fail "UV sphere topology or normals are incorrect";
  let strip =
    Mesh.create_exn ~mode:Mesh.Triangle_strip
      [ Vec3.create 0. 0. 0.; Vec3.create 1. 0. 0.;
        Vec3.create 0. 1. 0.; Vec3.create 1. 1. 0. ]
  in
  if Mesh.triangles strip <> [0, 1, 2; 2, 1, 3] then
    fail "triangle strip winding did not alternate";
  if Mesh.vertex_count (Mesh.axis ~size:2.) <> 6
     || Mesh.vertex_count (Mesh.grid ~divisions:4 ~size:10. ()) <> 20
     || List.exists
          (fun vertex -> abs_float vertex.Vec3.z > 1e-9)
          (Mesh.vertices
             (Mesh.grid_plane ~divisions:4 ~plane:Mesh.XY ~size:10. ()))
     || Mesh.vertex_count (Mesh.rotation_axes ~segments:8 ~radius:2. ()) <> 48
     || Mesh.vertex_count
          (Mesh.arrow ~from_:Vec3.zero ~to_:(Vec3.create 0. 3. 0.)
             ~head_size:0.75)
        = 0
  then fail "3D axis, grid, or arrow geometry was empty";
  let coarse_caps =
    Mesh.cylinder ~segments:8 ~cap_segments:1 ~radius:1. ~height:2. ()
  and fine_caps =
    Mesh.cylinder ~segments:8 ~cap_segments:3 ~radius:1. ~height:2. ()
  in
  if Mesh.vertex_count fine_caps <= Mesh.vertex_count coarse_caps then
    fail "cylinder cap resolution did not add concentric geometry";
  let instance_scene =
    Scene3.create [
      Scene3.instances (Mesh.box ~width:1. ~height:1. ~depth:1. ())
        [ Mat4.identity;
          Mat4.translation (Vec3.create 2. 0. 0.);
          Mat4.translation (Vec3.create (-2.) 0. 0.);
        ];
    ]
  in
  if List.length (Scene3.Private.drawings instance_scene) <> 3 then
    fail "Scene3 instances did not preserve every transform";
  let instance_transforms = [|Mat4.identity;
    Mat4.translation (Vec3.create 3. 0. 0.)|] in
  let array_instance_scene = Scene3.create [Scene3.translate
      (Vec3.create 1. 0. 0.) [
      Scene3.instances_array (Mesh.box ~width:1. ~height:1. ~depth:1. ())
        instance_transforms]] in
  instance_transforms.(1) <- Mat4.identity;
  let streamed = ref 0 and translated = ref false in
  Scene3.Private.iter_drawings (fun drawing ->
    incr streamed;
    if abs_float (Mat4.get drawing.transform ~row:0 ~column:3 -. 4.) < 1e-12
    then translated := true) array_instance_scene;
  if !streamed <> 2 || not !translated then
    fail "Scene3 array instances were not copied/streamed in order";
  let batches = ref 0 and batch_instances = ref 0 and parent_x = ref nan in
  Scene3.Private.iter_batches (fun drawing instances ->
    incr batches;
    parent_x := Mat4.get drawing.transform ~row:0 ~column:3;
    batch_instances := Option.fold ~none:0 ~some:Array.length instances)
    array_instance_scene;
  if !batches <> 1 || !batch_instances <> 2
     || abs_float (!parent_x -. 1.) > 1e-12
  then fail "Scene3 instance batch traversal expanded or miscomposed a batch";
  let sampled_area =
    Light.area ~samples:16 ~at:(Vec3.create 0. 3. 0.)
      ~direction:(Vec3.create 0. (-1.) 0.)
      ~width:4. ~height:2. ()
  in
  (match sampled_area.kind with
   | Light.Area { samples = 16; _ } -> ()
   | _ -> fail "area light did not retain its deterministic sample count");
  let shadow_light =
    Light.directional ~direction:(Vec3.create 0. 0. (-1.)) ()
  and shadow_camera =
    Camera.orthographic ~height:2.
      ~at:(Vec3.create 0. 0. 1.) ~target:Vec3.zero ()
  in
  let shadow_depths = Array.make 9 1. in
  shadow_depths.(4) <- 0.;
  let hard_shadow =
    Shadow3.create ~filter:Shadow3.Hard ~bias:0. ~normal_bias:0.
      ~light:shadow_light ~camera:shadow_camera
      ~width:3 ~height:3 ~depths:shadow_depths ()
  and soft_shadow =
    Shadow3.create ~filter:Shadow3.Pcf_3x3 ~bias:0. ~normal_bias:0.
      ~light:shadow_light ~camera:shadow_camera
      ~width:3 ~height:3 ~depths:shadow_depths ()
  in
  let hard_visibility =
    Shadow3.Private.visibility hard_shadow
      ~world:Vec3.zero ~normal:Vec3.unit_z
  and soft_visibility =
    Shadow3.Private.visibility soft_shadow
      ~world:Vec3.zero ~normal:Vec3.unit_z
  in
  if hard_visibility <> 0.
     || abs_float (soft_visibility -. (8. /. 9.)) > 1e-12
  then fail "hard/PCF shadow-map depth comparisons are incorrect";
  let texture =
    Texture.create_exn ~width:2 ~height:2
      [Color.red; Color.green; Color.blue; Color.yellow]
  in
  let uniforms =
    Shader3.empty_uniforms
    |> Shader3.set_uniform "gain" (Shader3.Float 0.75)
    |> Shader3.set_uniform "direction"
         (Shader3.Vec3 (Vec3.create 1. 2. 3.))
    |> Shader3.set_uniform "image" (Shader3.Texture texture)
  in
  if Shader3.float_uniform "gain" uniforms <> Some 0.75
     || Shader3.vec3_uniform "direction" uniforms
        <> Some (Vec3.create 1. 2. 3.)
     || Shader3.texture_uniform "image" uniforms <> Some texture
     || Shader3.int_uniform "gain" uniforms <> None
  then fail "Shader3 typed uniform lookup changed or mis-typed a value";
  let feedback_shader =
    Shader3.create ~varying_count:1
      ~vertex:(fun (input : Shader3.vertex_input) ->
        let output = Shader3.default_vertex input in
        { output with varyings = [0.] })
      ~geometry:(fun (input : Shader3.geometry_input) ->
        match input.primitive with
        | Shader3.Point center ->
            let shifted dx =
              {
                center with
                world_position =
                  Vec3.add center.world_position
                    (Vec3.create dx 0. 0.);
                varyings = [dx];
              }
            in
            [
              Shader3.Triangle
                (shifted (-1.), shifted 0., shifted 1.);
            ]
        | _ -> [])
      ~fragment:Shader3.default_fragment
      ()
  in
  let feedback =
    Transform_feedback3.capture
      ~model:(Mat4.translation (Vec3.create 2. 0. 0.))
      ~viewport:(0, 0, 64, 64) ~camera
      ~shader:feedback_shader
      (Mesh.create_exn ~mode:Mesh.Points [Vec3.zero])
  in
  let feedback_meshes = Transform_feedback3.meshes feedback in
  if Transform_feedback3.primitive_count feedback <> 1
     || Transform_feedback3.vertex_count feedback <> 3
     || Transform_feedback3.varyings feedback <> [[-1.]; [0.]; [1.]]
     || (match feedback_meshes with
         | [mesh] ->
             Mesh.mode mesh <> Mesh.Triangles
             || Mesh.vertices mesh
                <> [ Vec3.create 1. 0. 0.;
                     Vec3.create 2. 0. 0.;
                     Vec3.create 3. 0. 0. ]
         | _ -> true)
  then fail "geometry-stage transform feedback lost outputs or varyings";
  let compute_uniforms =
    Shader3.set_uniform "scale" (Shader3.Int 3)
      Shader3.empty_uniforms
  in
  let dispatch () =
    Compute3.dispatch ~grain:1 ~uniforms:compute_uniforms
      ~groups:(2, 1, 1) ~local_size:(2, 2, 1)
      (fun (invocation : Compute3.invocation) ->
        let scale =
          Option.value ~default:1
            (Shader3.int_uniform "scale" invocation.uniforms)
        in
        let x, y, z = invocation.global_id in
        if invocation.linear_index = 7
           && (invocation.local_id <> (1, 1, 0)
               || invocation.group_id <> (1, 0, 0)
               || invocation.num_groups <> (2, 1, 1))
        then fail "Compute3 invocation IDs are inconsistent";
        (x + (4 * y) + (8 * z)) * scale)
  in
  let first_dispatch = dispatch () and second_dispatch = dispatch () in
  if first_dispatch <> [|0; 3; 6; 9; 12; 15; 18; 21|]
     || first_dispatch <> second_dispatch
  then fail "functional 3D compute dispatch was unordered or nondeterministic";
  let texture_right =
    Texture.subsection_exn ~x:1 ~y:0 ~width:1 ~height:2 texture
  in
  if Texture.size texture_right <> (1, 2)
     || Texture.pixels texture_right <> [Color.green; Color.yellow]
  then fail "texture subsection did not preserve the selected pixel rectangle";
  if not (Color.equal
      (Texture.sample ~filter:Texture.Nearest texture ~u:0.1 ~v:0.1)
      Color.red)
     || not (Color.equal
       (Texture.sample ~filter:Texture.Nearest ~wrap_u:Texture.Repeat
          texture ~u:1.75 ~v:0.1)
       Color.green)
  then fail "normalized texture sampling or repeat wrapping is incorrect";
  let mipmapped = Texture.generate_mipmaps texture in
  if not (Texture.has_mipmaps mipmapped)
     || Texture.mipmap_count mipmapped <> 2
     || not
          (Color.equal
             (Texture.sample_lod ~filter:Texture.Trilinear
                mipmapped ~lod:1. ~u:0.3 ~v:0.8)
             (Color.rgb 128 128 64))
  then fail "immutable texture mip generation or LOD sampling is incorrect";
  let obj_file = Filename.temp_file "prismel-mesh-" ".obj" in
  let ply_file = Filename.temp_file "prismel-mesh-" ".ply" in
  let little_ply_file = Filename.temp_file "prismel-mesh-little-" ".ply" in
  let big_ply_file = Filename.temp_file "prismel-mesh-big-" ".ply" in
  Fun.protect
    ~finally:(fun () ->
      if Sys.file_exists obj_file then Sys.remove obj_file;
      if Sys.file_exists ply_file then Sys.remove ply_file;
      if Sys.file_exists little_ply_file then Sys.remove little_ply_file;
      if Sys.file_exists big_ply_file then Sys.remove big_ply_file)
    (fun () ->
      let channel = open_out obj_file in
      Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
        output_string channel
          "v -1 -1 0\nv 1 -1 0\nv 1 1 0\nv -1 1 0\n";
        output_string channel "vt 0 1\nvt 1 1\nvt 1 0\nvt 0 0\n";
        output_string channel "vn 0 0 1\n";
        output_string channel "f 1/1/1 2/2/1 3/3/1 4/4/1 # quad\n");
      let loaded =
        match Mesh.load_obj obj_file with
        | Ok mesh -> mesh
        | Error message -> fail message
      in
      if Mesh.vertex_count loaded <> 4 || Mesh.index_count loaded <> 6
         || not (Mesh.has_normals loaded)
         || not (Mesh.has_tex_coords loaded)
      then fail "OBJ loader did not triangulate and preserve attributes";
      (match Mesh.save_ply loaded ply_file with
       | Ok () -> ()
       | Error message -> fail message);
      (match Mesh.load_ply ply_file with
       | Ok restored
         when Mesh.vertex_count restored = 4
              && Mesh.index_count restored = 6
              && Mesh.has_normals restored
              && Mesh.has_tex_coords restored -> ()
       | Ok _ -> fail "ASCII PLY round trip changed mesh topology or attributes"
       | Error message -> fail message);
      (match
         Mesh.save_ply ~format:Mesh.Ply_binary_little_endian
           loaded little_ply_file,
         Mesh.save_ply ~format:Mesh.Ply_binary_big_endian
           loaded big_ply_file
       with
       | Ok (), Ok () -> ()
       | Error message, _ | _, Error message -> fail message);
      let read filename =
        let channel = open_in_bin filename in
        Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
          really_input_string channel (in_channel_length channel))
      in
      let body contents =
        let marker = "end_header\n" in
        let marker_length = String.length marker in
        let rec find index =
          if index + marker_length > String.length contents then
            fail "binary PLY output had no end_header marker"
          else if String.sub contents index marker_length = marker then
            String.sub contents (index + marker_length)
              (String.length contents - index - marker_length)
          else find (index + 1)
        in
        find 0
      in
      let little = read little_ply_file |> body
      and big = read big_ply_file |> body in
      if String.length little <> String.length big
         || String.length little < 4
         || String.sub little 0 4 <> "\000\000\128\191"
         || String.sub big 0 4 <> "\191\128\000\000"
      then fail "binary PLY float output did not honor its declared endianness")

(* Runtime key names must reach the Input keys hosts match on. *)
let run_2 () =
  List.iter (fun (scancode, expected) ->
    let name = Runtime_input_sdl3.key_name ~scancode 0 in
    if Prismel.Event.Private.key_of_name name <> expected then
      fail ("runtime key " ^ name ^ " did not map to its Input key"))
    Prismel.Input.[ 79, ArrowRight; 80, ArrowLeft; 81, ArrowDown; 82, ArrowUp;
            40, Enter; 41, Escape; 224, Ctrl; 227, Meta; 75, PageUp ]

(* Every 2D constructor must lower to a valid Render_ir (triangle lists). *)
let run_3 () =
  let open Prismel in
  let open_path = Path.(empty |> move_to 0. 0. |> line_to 10. 5. |> line_to 20. 0.) in
  List.iter (fun (name, node) ->
    match Scene.Private.to_ir [node] with
    | Ok _ -> ()
    | Error message -> fail (name ^ " did not lower: " ^ message))
    [ "point", Scene.point ~at:(3, 4) ();
      "open path", Scene.path ~stroke:Color.white open_path;
      "closed path", Scene.path ~fill:Color.white Path.(close open_path);
      "arc", Scene.arc ~at:(20, 20) ~radius:8 ~from_:0. ~to_:3. ();
      "pie", Scene.pie ~at:(20, 20) ~radius:8 ~from_:0. ~to_:3. ~fill:Color.white () ]

(* Procedural triangle meshes often arrive without normals; lit faces derive them. *)
let run_4 () =
  let open Prismel in
  let mesh = Mesh.create_exn ~indices:[0; 1; 2]
      [Vec3.create 0. 0. 0.; Vec3.create 1. 0. 0.; Vec3.create 0. 1. 0.] in
  let camera = Camera.perspective ~at:(Vec3.create 0. 0. 5.) ~target:Vec3.zero () in
  match Scene.Private.stage_native ~width:64 ~height:64
      [Scene.view3d ~camera (Scene3.create [Scene3.mesh mesh])] with
  | Ok _ -> ()
  | Error message -> fail ("normal-less mesh did not stage: " ^ message)

(* Font metrics, measuring and alignment come from SDL_ttf, not placeholders. *)
let run_5 () =
  let open Prismel in
  let msg = function Ok v -> v | Error (`Msg m) -> fail m in
  let font = msg (Font.system ~size:20 ()) in
  if Font.get_ascent font <= 0 || Font.get_line_skip font < Font.get_ascent font
     || Font.get_descent font > 0 then fail "font vertical metrics are placeholders";
  let w, h = msg (Font.text_size font "Hello") in
  if w <= 0 || h <= 0 then fail "text_size measured nothing";
  ignore (msg (Font.text_size font "bad \xff utf-8"));
  let text = "short\na much longer second line" in
  let pixels align =
    let image = msg (Font.cached_text ~wrap:400 ~align font text (Font.Blended Color.white)) in
    match Image.Private.pixels image with Ok p -> p | Error m -> fail m in
  if Bytes.equal (pixels Font.Left) (pixels Font.Center) then
    fail "Font alignment is ignored";
  Font.destroy font

let run () =
  run_1 ();
  run_2 ();
  run_3 ();
  run_4 ();
  run_5 ()
