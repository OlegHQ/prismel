open Prismel

module CC2 = Pxui.Camera2_control

type camera = Easy_camera2.t
type control = CC2.t
type rendered = Scene.t
type request = CC2.render_request
type extra = unit
type view = Easy_camera2.t

let keymap = Leader.keymap
let scene_level = false
let default_camera () = Easy_camera2.create ()
let seed_scene ?lens:_ _ _ scene = scene

(* One geometry object; 2D pieces are placed as drawn. *)
let compose ~scene:_ ~world:_ pieces = List.concat_map (fun (_, _, scene) -> scene) pieces
let init core _ = core, ()
let create_control () = CC2.create ()
let ui_visible = CC2.ui_visible
let toggle_ui = CC2.toggle_ui
let open_camera = CC2.open_camera
let begin_frame () frame = (), frame

let panel ui ~control ~camera ~extra:() ~inspector =
  let control, camera, requests = CC2.widgets control ui ~camera in
  control, camera, requests, (), inspector ui

let section camera () = Editor_core.Store.Viewport.encode2 camera
let restore camera () json = Editor_core.Store.Viewport.decode2 camera json, ()
let apply_action _ () _ = (), None
let on_doc ~previous:_ core _ = core

let navigate ~area control camera () _core ~raw_frame:_ ~input =
  CC2.navigate ~control_area:area ~viewport:area control camera input, ()

let frame_bounds ~viewport:(_, _, width, height) ~min ~max camera =
  let span_x = max.Vec3.x -. min.Vec3.x
  and span_y = max.Vec3.y -. min.Vec3.y in
  let zoom = Float.min
      (float_of_int (Int.max 1 (width - 76)) /. Float.max 1. span_x)
      (float_of_int (Int.max 1 (height - 76)) /. Float.max 1. span_y) in
  camera
  |> Easy_camera2.with_center
       (Vec2.create ((min.x +. max.x) *. 0.5) ((min.y +. max.y) *. 0.5))
  |> Easy_camera2.with_zoom zoom

let on_view core ~previous:_ ~key:_ camera () ~time:_ = core, camera, ()
let view_camera camera () ~key:_ ~pending:_ = camera
let film () ~key:_ viewport = viewport
let render () ~pixel_scale:_ ~focus:_ _ = ()
let caption () ~key:_ = None
let render_status () = None
let paint () ~key:_ viewport camera rendered = Easy_camera2.scene ~viewport camera rendered
let guides ~scene:_ ~selected:_ ~space:_ _ () ~bounds:_ = []
(* A click on the drawing is a ray straight down onto the plane the geometry lies in. *)
let pick_ray ~viewport camera (x, y) =
  let point = Easy_camera2.screen_to_world ~viewport camera (Vec2.create x y) in
  Some (Vec3.create point.Vec2.x point.y 1., Vec3.create 0. 0. (-1.))
let handles _ ~selected:_ ~scene:_ ~space:_ _ () ~bounds:_ = [], false, None
let save = CC2.save
let filename request = request.CC2.filename
let close () = ()
