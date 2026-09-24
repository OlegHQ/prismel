open Prismel

let fail message = raise (Failure message)

let frame ?(time = 0.) ?(dt = 1. /. 60.) ?(mouse = (320, 180))
    ?(keys = []) ?(mouse_buttons = []) ?(events = []) () : Frame.t = {
  width = 640; height = 360; size = 640, 360;
  drawable_width = 640; drawable_height = 360;
  drawable_size = 640, 360; pixel_scale = 1., 1.;
  time; dt; fps = 60.; count = 0; mouse; mouse_delta = 0, 0;
  keys; mouse_buttons; events;
}

let close left right = abs_float (left -. right) < 1e-8

let () =
  let viewport = 0, 0, 640, 360 in
  let camera = Easy_camera2.create ~viewport ~inertia:false () in
  let world = Vec2.create 42. (-17.) in
  let round_trip = Easy_camera2.world_to_screen ~viewport camera world
    |> Easy_camera2.screen_to_world ~viewport camera in
  if not (Vec2.nearly_equal world round_trip ~eps:1e-9) then
    fail "2D camera screen/world transforms did not round-trip";
  let right_panned = Easy_camera2.update camera (frame
      ~mouse:(350, 205) ~mouse_buttons:[Input.RightButton]
      ~events:[Event.MousePressed (Input.RightButton, (320, 180));
        MouseMoved (350, 205); MouseReleased (Input.RightButton, (350, 205))]
      ()) in
  if Vec2.nearly_equal (Easy_camera2.center right_panned) Vec2.zero ~eps:1e-9
     || Easy_camera2.zoom right_panned <> 1.
  then fail "2D camera right-drag did not pan without changing zoom";
  let middle_panned = Easy_camera2.update right_panned (frame
      ~mouse:(365, 195) ~mouse_buttons:[Input.MiddleButton]
      ~events:[Event.MousePressed (Input.MiddleButton, (350, 205));
        MouseMoved (365, 195); MouseReleased (Input.MiddleButton, (365, 195))]
      ()) in
  if Vec2.nearly_equal (Easy_camera2.center middle_panned)
      (Easy_camera2.center right_panned) ~eps:1e-9
  then fail "2D camera middle-drag did not pan";
  let pointer = 500, 100 in
  let before_anchor = Easy_camera2.screen_to_world ~viewport middle_panned
      (Vec2.of_pair pointer) in
  let zoomed = Easy_camera2.update middle_panned (frame ~mouse:pointer
      ~events:[Event.MouseScrolled (0, 2)] ()) in
  let after_anchor = Easy_camera2.screen_to_world ~viewport zoomed
      (Vec2.of_pair pointer) in
  if Easy_camera2.zoom zoomed <= Easy_camera2.zoom middle_panned
     || not (Vec2.nearly_equal before_anchor after_anchor ~eps:1e-8)
  then fail "2D camera wheel zoom was not pointer anchored";
  let horizontal = Easy_camera2.update zoomed (frame ~mouse:pointer
      ~events:[Event.MouseScrolled (3, 0)] ()) in
  if Easy_camera2.zoom horizontal <> Easy_camera2.zoom zoomed
     || not (Vec2.nearly_equal (Easy_camera2.center horizontal)
        (Easy_camera2.center zoomed) ~eps:1e-9)
  then fail "2D camera reacted to horizontal trackpad scrolling";
  let captured = Easy_camera2.create ~viewport ~control_area:(0, 0, 100, 100)
      ~inertia:false ()
    |> Fun.flip Easy_camera2.update (frame ~mouse:(300, 250)
      ~events:[Event.MousePressed (Input.RightButton, (50, 50));
        MouseMoved (300, 250); MouseReleased (Input.RightButton, (300, 250))]
      ()) in
  if Vec2.nearly_equal (Easy_camera2.center captured) Vec2.zero ~eps:1e-9 then
    fail "2D camera did not continue a captured pan outside its area";
  let outside = Easy_camera2.create ~viewport ~control_area:(0, 0, 40, 40)
      ~inertia:false ()
    |> Fun.flip Easy_camera2.update (frame
      ~events:[Event.MousePressed (Input.RightButton, (50, 50));
        MouseMoved (90, 90); MouseReleased (Input.RightButton, (90, 90))] ()) in
  if not (Vec2.nearly_equal (Easy_camera2.center outside) Vec2.zero ~eps:1e-9)
  then fail "2D camera accepted a press outside its control area";
  let cancelled = Easy_camera2.create ~viewport ~inertia:false ()
    |> Fun.flip Easy_camera2.update (frame
      ~events:[Event.MousePressed (Input.RightButton, (100, 100));
        Event.PointerCancelled Input.RightButton; MouseMoved (180, 180)] ()) in
  if not (Vec2.nearly_equal (Easy_camera2.center cancelled) Vec2.zero ~eps:1e-9)
  then fail "2D camera pointer cancellation did not release capture";
  let module Control = Pxui.Camera2_control in
  let ui = Pxui.Ui.create () in
  let run control camera (frame : Frame.t) =
    Pxui.Ui.frame ui frame (fun ui ->
      Control.panel ~x:0. ~y:0. ~width:240. control ui ~camera frame) in
  let click point = frame ~mouse:point ~events:[
      Event.MousePressed (Input.LeftButton, point);
      MouseReleased (Input.LeftButton, point)] () in
  let control = Control.create () in
  let control, _, _ = run control camera (frame ()) in
  (* Open Render (row 1), then press its save button (row 3). *)
  let control, _, _ = run control camera (click (30, 39)) in
  let control, _, _ = run control camera (frame ()) in
  let control, _, requests = run control camera (click (30, 87)) in
  if List.length requests <> 1 then
    fail "2D camera render section did not request a PNG";
  let control, controlled, _ = run (Control.open_camera control) camera (frame ()) in
  if Easy_camera2.control_area controlled <> Some (248, 0, 392, 360)
  then fail "2D camera controls did not reserve the area beside the panel";
  let control, zoomed, _ = run control controlled (frame ~mouse:(400, 180)
      ~events:[Event.MouseScrolled (0, 2)] ()) in
  let control, zoomed_idle, _ = run control zoomed (frame ~mouse:(400, 180) ()) in
  if Easy_camera2.zoom zoomed = Easy_camera2.zoom controlled
     || Easy_camera2.zoom zoomed_idle <> Easy_camera2.zoom zoomed
  then fail "2D camera control undid gesture-driven zoom";
  let hidden, _, _ = run (Control.toggle_ui control) zoomed_idle (frame ()) in
  if Control.ui_visible hidden || Pxui.Ui.scene ui <> []
     || Control.overlay hidden Scene.[text ~at:(0, 0) "label"] <> Scene.empty
  then fail "2D camera toggle_ui did not hide controls and labels";
  Pxui.Ui.destroy ui;
  let rotated = Easy_camera2.create ~viewport ~center:(Vec2.create 10. 20.)
      ~zoom:2. ~rotation:0.4 () in
  let projected = Easy_camera2.world_to_screen ~viewport rotated world in
  let restored = Easy_camera2.screen_to_world ~viewport rotated projected in
  if not (close restored.x world.x && close restored.y world.y) then
    fail "rotated 2D camera transform did not invert";
  print_endline "easy camera2 tests passed"
