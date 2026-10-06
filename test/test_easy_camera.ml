open Rays

let fail message = raise (Failure message)
let pointer (x, y) = float x, float y
let mouse_press (button, point) = Event.MousePressed (button, pointer point)
let mouse_release (button, point) = Event.MouseReleased (button, pointer point)
let mouse_move point = Event.MouseMoved (pointer point)

let frame ?(keys = []) ?(events = []) () : Frame.t = {
  width = 640; height = 360; size = 640, 360;
  drawable_width = 640; drawable_height = 360;
  drawable_size = 640, 360; pixel_scale = 1., 1.;
  time = 0.; dt = 1. /. 60.; fps = 60.; count = 0;
  mouse = 320., 180.; mouse_delta = 0., 0.;
  keys; mouse_buttons = []; events;
}

let run () =
  List.iter (fun modifier ->
    let events = [Event.KeyPressed modifier; mouse_press (Input.LeftButton, (320, 180));
      mouse_move (350, 180); Event.KeyReleased modifier;
      mouse_release (Input.LeftButton, (350, 180))] in
    let camera = Easy_camera.create ~translation_key:modifier ~inertia:false () in
    let panned = Easy_camera.update camera (frame ~events ()) in
    if Camera.target (Easy_camera.camera panned) = Vec3.zero then
      fail "ordered 3D translation-key tap orbited instead of panning";
    let late = [mouse_press (Input.LeftButton, (320, 180)); Event.KeyPressed modifier;
      mouse_move (350, 180); mouse_release (Input.LeftButton, (350, 180))] in
    if Camera.target (Easy_camera.camera (Easy_camera.update camera
        (frame ~keys:[modifier] ~events:late ()))) <> Vec3.zero then
      fail "a later camera key press changed the already captured interaction";
    let disabled = Easy_camera.update camera (frame ~keys:[modifier] ())
      |> Easy_camera.set_enabled false in
    let released = frame ~events:[Event.KeyReleased modifier] () in
    let resumed = Easy_camera.update disabled released |> Easy_camera.set_enabled true in
    if Camera.target (Easy_camera.camera (Easy_camera.update resumed
        (frame ~keys:[modifier] ~events:late ()))) <> Vec3.zero then
      fail "disabled camera input retained a stale translation key")
    [Input.Shift; Input.KeyChar 'p'];
  print_endline "easy camera tests passed"
