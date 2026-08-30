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
  let control = Pxui.Camera2_control.create () in
  let ui = Pxui.create ~x:0 ~y:0 ~width:240 ()
    |> Pxui.Camera2_control.append control ~camera in
  let capped = Pxui.with_max_height (Some 120) ui in
  let _, capped, capped_camera, _, _ = Pxui.Camera2_control.update control
      ~ui:capped ~camera (frame ~mouse:(30, 56)
        ~mouse_buttons:[Input.LeftButton]
        ~events:[Event.MousePressed (Input.LeftButton, (30, 56))] ()) in
  let capped = Pxui.with_max_height (Some 120) capped in
  let _, capped, _, _, _ = Pxui.Camera2_control.update control ~ui:capped
      ~camera:capped_camera (frame ~mouse:(30, 56)
        ~events:[Event.MouseReleased (Input.LeftButton, (30, 56))] ()) in
  if Pxui.accordion_expanded capped "camera2.render-section" <> Some true then
    fail "2D camera frame fitting cancelled an externally capped accordion press";
  let control, ui, controlled, _, _ = Pxui.Camera2_control.update control
      ~ui ~camera (frame ~events:[Event.KeyPressed (Input.KeyChar 'c')] ()) in
  if Pxui.accordion_expanded ui "camera2.section" <> Some true
     || Easy_camera2.control_area controlled <> Some (248, 0, 392, 360)
  then fail "2D camera controls did not toggle or reserve the resized canvas";
  let _, ui, controlled, _, _ = Pxui.Camera2_control.update control ~ui
      ~camera:controlled (frame ~mouse:(400, 180)
        ~events:[Event.MouseScrolled (0, 2)] ()) in
  if Pxui.slider_value ui "camera2.zoom" <> Some (Easy_camera2.zoom controlled)
  then fail "2D camera control did not synchronize gesture-driven zoom";
  let hidden, hidden_ui, _, _, _ = Pxui.Camera2_control.update control ~ui
      ~camera:controlled
      (frame ~events:[Event.KeyPressed (Input.KeyChar 'h')] ()) in
  if Pxui.Camera2_control.ui_visible hidden
     || Pxui.Camera2_control.scene hidden hidden_ui <> Scene.empty
     || Pxui.Camera2_control.overlay hidden Scene.[text ~at:(0, 0) "label"]
        <> Scene.empty
  then fail "2D camera H shortcut did not hide controls and labels";
  let _, hidden_idle_ui, _, _, _ = Pxui.Camera2_control.update hidden
      ~ui:hidden_ui ~camera:controlled (frame ()) in
  if hidden_idle_ui != hidden_ui then
    fail "hidden 2D camera control rebuilt presentation state on an idle frame";
  let rotated = Easy_camera2.create ~viewport ~center:(Vec2.create 10. 20.)
      ~zoom:2. ~rotation:0.4 () in
  let projected = Easy_camera2.world_to_screen ~viewport rotated world in
  let restored = Easy_camera2.screen_to_world ~viewport rotated projected in
  if not (close restored.x world.x && close restored.y world.y) then
    fail "rotated 2D camera transform did not invert";
  print_endline "easy camera2 tests passed"
