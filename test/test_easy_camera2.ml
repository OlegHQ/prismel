open Rays
open Test_support

let pointer (x, y) = float x, float y
let mouse_press (button, point) = Event.MousePressed (button, pointer point)
let mouse_release (button, point) = Event.MouseReleased (button, pointer point)
let mouse_move point = Event.MouseMoved (pointer point)

let frame ?(time = 0.) ?(dt = 1. /. 60.) ?(mouse = (320, 180))
    ?(keys = []) ?(mouse_buttons = []) ?(events = []) () : Frame.t = {
  width = 640; height = 360; size = 640, 360;
  drawable_width = 640; drawable_height = 360;
  drawable_size = 640, 360; pixel_scale = 1., 1.;
  time; dt; fps = 60.; count = 0;
  mouse = (float (fst mouse), float (snd mouse)); mouse_delta = 0., 0.;
  keys; mouse_buttons; events;
}

let close left right = abs_float (left -. right) < 1e-8

let run () =
  let viewport = 0, 0, 640, 360 in
  List.iter (fun modifier ->
    let events = [Event.KeyPressed modifier; mouse_press (Input.LeftButton, (320, 180));
      mouse_move (350, 180); Event.KeyReleased modifier;
      mouse_release (Input.LeftButton, (350, 180))] in
    let camera2 = Easy_camera2.create ~viewport ~translation_key:modifier ~inertia:false () in
    let panned = Easy_camera2.update camera2 (frame ~events ()) in
    if Easy_camera2.center panned = Vec2.zero then fail "ordered 2D translation-key tap did not pan";
    let camera3 = Easy_camera.create ~translation_key:modifier ~inertia:false () in
    let panned = Easy_camera.update camera3 (frame ~events ()) in
    if Camera.target (Easy_camera.camera panned) = Vec3.zero then
      fail "ordered 3D translation-key tap orbited instead of panning";
    let late = [mouse_press (Input.LeftButton, (320, 180)); Event.KeyPressed modifier;
      mouse_move (350, 180); mouse_release (Input.LeftButton, (350, 180))] in
    if Easy_camera2.center (Easy_camera2.update camera2 (frame ~keys:[modifier] ~events:late ())) <> Vec2.zero
      || Camera.target (Easy_camera.camera (Easy_camera.update camera3
          (frame ~keys:[modifier] ~events:late ()))) <> Vec3.zero then
      fail "a later camera key press changed the already captured interaction";
    let disabled2 = Easy_camera2.update camera2 (frame ~keys:[modifier] ())
      |> Easy_camera2.set_enabled false in
    let disabled3 = Easy_camera.update camera3 (frame ~keys:[modifier] ())
      |> Easy_camera.set_enabled false in
    let released = frame ~events:[Event.KeyReleased modifier] () in
    let resumed2 = Easy_camera2.update disabled2 released |> Easy_camera2.set_enabled true
    and resumed3 = Easy_camera.update disabled3 released |> Easy_camera.set_enabled true in
    if Easy_camera2.center (Easy_camera2.update resumed2 (frame ~keys:[modifier] ~events:late ())) <> Vec2.zero
      || Camera.target (Easy_camera.camera (Easy_camera.update resumed3
          (frame ~keys:[modifier] ~events:late ()))) <> Vec3.zero then
      fail "disabled camera input retained a stale translation key")
    [Input.Shift; Input.KeyChar 'p'];
  let camera = Easy_camera2.create ~viewport ~inertia:false () in
  let world = Vec2.create 42. (-17.) in
  let round_trip = Easy_camera2.world_to_screen ~viewport camera world
    |> Easy_camera2.screen_to_world ~viewport camera in
  if not (Vec2.nearly_equal world round_trip ~eps:1e-9) then
    fail "2D camera screen/world transforms did not round-trip";
  let right_panned = Easy_camera2.update camera (frame
      ~mouse:(350, 205) ~mouse_buttons:[Input.RightButton]
      ~events:[mouse_press (Input.RightButton, (320, 180));
        mouse_move (350, 205); mouse_release (Input.RightButton, (350, 205))]
      ()) in
  if Vec2.nearly_equal (Easy_camera2.center right_panned) Vec2.zero ~eps:1e-9
     || Easy_camera2.zoom right_panned <> 1.
  then fail "2D camera right-drag did not pan without changing zoom";
  let middle_panned = Easy_camera2.update right_panned (frame
      ~mouse:(365, 195) ~mouse_buttons:[Input.MiddleButton]
      ~events:[mouse_press (Input.MiddleButton, (350, 205));
        mouse_move (365, 195); mouse_release (Input.MiddleButton, (365, 195))]
      ()) in
  if Vec2.nearly_equal (Easy_camera2.center middle_panned)
      (Easy_camera2.center right_panned) ~eps:1e-9
  then fail "2D camera middle-drag did not pan";
  let pointer = 500, 100 in
  let before_anchor = Easy_camera2.screen_to_world ~viewport middle_panned
      (Vec2.of_pair pointer) in
  let zoomed = Easy_camera2.update middle_panned (frame ~mouse:pointer
      ~events:[Event.MouseScrolled (0., 2.)] ()) in
  let after_anchor = Easy_camera2.screen_to_world ~viewport zoomed
      (Vec2.of_pair pointer) in
  if Easy_camera2.zoom zoomed <= Easy_camera2.zoom middle_panned
     || not (Vec2.nearly_equal before_anchor after_anchor ~eps:1e-8)
  then fail "2D camera wheel zoom was not pointer anchored";
  let fractional = Easy_camera2.update middle_panned
      { (frame ~events:[Event.MouseScrolled (0., 0.3)] ()) with
        mouse = 500.25, 100.5 } in
  if Easy_camera2.zoom fractional <= Easy_camera2.zoom middle_panned then
    fail "2D camera ignored a fractional wheel delta";
  let horizontal = Easy_camera2.update zoomed (frame ~mouse:pointer
      ~events:[Event.MouseScrolled (3., 0.)] ()) in
  if Easy_camera2.zoom horizontal <> Easy_camera2.zoom zoomed
     || not (Vec2.nearly_equal (Easy_camera2.center horizontal)
        (Easy_camera2.center zoomed) ~eps:1e-9)
  then fail "2D camera reacted to horizontal trackpad scrolling";
  let captured = Easy_camera2.create ~viewport ~control_area:(0, 0, 100, 100)
      ~inertia:false ()
    |> Fun.flip Easy_camera2.update (frame ~mouse:(300, 250)
      ~events:[mouse_press (Input.RightButton, (50, 50));
        mouse_move (300, 250); mouse_release (Input.RightButton, (300, 250))]
      ()) in
  if Vec2.nearly_equal (Easy_camera2.center captured) Vec2.zero ~eps:1e-9 then
    fail "2D camera did not continue a captured pan outside its area";
  let outside = Easy_camera2.create ~viewport ~control_area:(0, 0, 40, 40)
      ~inertia:false ()
    |> Fun.flip Easy_camera2.update (frame
      ~events:[mouse_press (Input.RightButton, (50, 50));
        mouse_move (90, 90); mouse_release (Input.RightButton, (90, 90))] ()) in
  if not (Vec2.nearly_equal (Easy_camera2.center outside) Vec2.zero ~eps:1e-9)
  then fail "2D camera accepted a press outside its control area";
  let cancelled = Easy_camera2.create ~viewport ~inertia:false ()
    |> Fun.flip Easy_camera2.update (frame
      ~events:[mouse_press (Input.RightButton, (100, 100));
        Event.PointerCancelled Input.RightButton; mouse_move (180, 180)] ()) in
  if not (Vec2.nearly_equal (Easy_camera2.center cancelled) Vec2.zero ~eps:1e-9)
  then fail "2D camera pointer cancellation did not release capture";
  let rotated = Easy_camera2.create ~viewport ~center:(Vec2.create 10. 20.)
      ~zoom:2. ~rotation:0.4 () in
  let projected = Easy_camera2.world_to_screen ~viewport rotated world in
  let restored = Easy_camera2.screen_to_world ~viewport rotated projected in
  if not (close restored.x world.x && close restored.y world.y) then
    fail "rotated 2D camera transform did not invert";
  print_endline "easy camera2 tests passed"
