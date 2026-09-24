open Prismel

type visibility = {
  prefix : string;
  ui_visible : bool;
  filename : string;
  open_camera : bool option;
}

let make prefix =
  if prefix = "" then invalid_arg "Pxui camera control: prefix is empty";
  { prefix; ui_visible = true; filename = "prismel-render.png"; open_camera = None }

let toggle_ui control = { control with ui_visible = not control.ui_visible }

(* Show the UI and toggle the Camera section, or open it if the UI was hidden. *)
let open_camera control =
  { control with ui_visible = true; open_camera = Some (not control.ui_visible) }

let render_section control ui =
  let filename, save = Option.value ~default:(control.filename, false)
      (Ui.accordion ui "Render" (fun () ->
        let filename = Ui.text_field ui "Output" control.filename in
        filename, Ui.button ui "Render / save PNG")) in
  { control with filename },
  if save then [filename] else []

(* [open_camera] opens the section explicitly while hidden, otherwise it
   toggles. *)
let camera_section control ui build =
  let set_expanded = match control.open_camera with
    | None -> None
    | Some true -> Some true
    | Some false -> Some (not (Option.value ~default:false (Ui.expanded ui "Camera"))) in
  Ui.accordion ui ?set_expanded "Camera" build

(* Navigate on the larger side beside the panel. *)
let camera_area (panel_x, panel_width) (frame : Frame.t) =
  let left_width = max 0 (panel_x - 8) and right_x = panel_x + panel_width + 8 in
  let right_width = max 0 (frame.width - right_x) in
  if right_width >= left_width then right_x, 0, right_width, frame.height
  else 0, 0, left_width, frame.height

let fitted_panel ui ~x ~y ~width (frame : Frame.t) build =
  let row = float (Ui.row_height ui) in
  Ui.panel ui ~x ~y ~width
    ~max_height:(Float.max (row +. 6.) (float frame.height -. y -. 8.))
    "camera-panel" build


module Camera_control = struct
  type t = visibility
  type render_request = { filename : string }

  let create ?(prefix = "camera") () = make prefix
  let toggle_ui = toggle_ui
  let open_camera = open_camera

  let widgets control ui ~camera =
    Ui.scope ui control.prefix (fun () ->
      let camera = Option.value ~default:camera (camera_section control ui (fun () ->
        let degrees = Easy_camera.fov_y camera *. 180. /. Float.pi in
        let edited = Ui.slider ui "FOV" ~range:(15., 120.) degrees in
        let fov = if edited = degrees then Easy_camera.fov_y camera
          else edited *. Float.pi /. 180. in
        let distance = Ui.slider ui "Distance" ~range:(0.1, 100.)
            (Easy_camera.distance camera) in
        let near = Ui.slider ui "Near clip" ~range:(0.01, 10.) (Easy_camera.near camera) in
        let far = Ui.slider ui "Far clip" ~range:(10., 5000.) (Easy_camera.far camera) in
        let inertia = Ui.toggle ui "Inertia" (Easy_camera.inertia camera) in
        let reset = Ui.button ui "Reset camera" in
        let current = Easy_camera.fov_y camera in
        let fov = if fov > 0. && fov < Float.pi then fov else current in
        let distance = if distance > 0. then distance else Easy_camera.distance camera in
        let near = if near > 0. then near else Easy_camera.near camera in
        let far = Float.max (near +. 0.01) far in
        let camera = camera
          |> Easy_camera.with_fov_y fov |> Easy_camera.with_distance distance
          |> Easy_camera.with_clip ~near ~far |> Easy_camera.with_inertia inertia in
        if reset then Easy_camera.reset camera else camera)) in
      let control, saves = render_section { control with open_camera = None } ui in
      control, camera, List.map (fun filename -> { filename }) saves)

  let navigate ?control_area (_ : t) camera (frame : Frame.t) =
    let area = Option.value control_area ~default:(0, 0, frame.width, frame.height) in
    camera
    |> Easy_camera.with_control_area (Some area)
    |> Fun.flip Easy_camera.update frame

  let panel ?(x = 12.) ?(y = 12.) ?(width = 280.) control ui ~camera frame =
    let control, camera, requests =
      if control.ui_visible then
        fitted_panel ui ~x ~y ~width frame (fun () -> widgets control ui ~camera)
      else { control with open_camera = None }, camera, [] in
    let area = if control.ui_visible
      then camera_area (int_of_float x, int_of_float (Float.max 180. width)) frame
      else 0, 0, frame.width, frame.height in
    control, navigate ~control_area:area control camera frame, requests

  let ui_visible (control : t) = control.ui_visible
  let overlay (control : t) scene = if control.ui_visible then scene else Scene.empty
  let save request = Canvas.save_screen_png request.filename

end

module Camera2_control = struct
  type t = visibility
  type render_request = { filename : string }

  let create ?(prefix = "camera2") () = make prefix
  let toggle_ui = toggle_ui
  let open_camera = open_camera

  let widgets control ui ~camera =
    Ui.scope ui control.prefix (fun () ->
      let camera = Option.value ~default:camera (camera_section control ui (fun () ->
        let center = Easy_camera2.center camera in
        let x = Ui.slider ui "Center X" ~range:(-1000., 1000.) center.Vec2.x in
        let y = Ui.slider ui "Center Y" ~range:(-1000., 1000.) center.y in
        let zoom = Ui.slider ui "Zoom" ~range:(0.05, 20.) (Easy_camera2.zoom camera) in
        let degrees = Easy_camera2.rotation camera *. 180. /. Float.pi in
        let edited = Ui.slider ui "Rotation" ~range:(-180., 180.) degrees in
        let rotation = if edited = degrees then Easy_camera2.rotation camera
          else edited *. Float.pi /. 180. in
        let inertia = Ui.toggle ui "Inertia" (Easy_camera2.inertia camera) in
        let reset = Ui.button ui "Reset camera" in
        let zoom = if zoom > 0. then zoom else Easy_camera2.zoom camera in
        let camera = camera
          |> Easy_camera2.with_center (Vec2.create x y)
          |> Easy_camera2.with_zoom zoom
          |> Easy_camera2.with_rotation rotation
          |> Easy_camera2.with_inertia inertia in
        if reset then Easy_camera2.reset camera else camera)) in
      let control, saves = render_section { control with open_camera = None } ui in
      control, camera, List.map (fun filename -> { filename }) saves)

  let navigate ?control_area ?viewport (_ : t) camera (frame : Frame.t) =
    let full = 0, 0, frame.width, frame.height in
    let area = Option.value control_area ~default:full in
    camera
    |> Easy_camera2.with_viewport (Some (Option.value viewport ~default:full))
    |> Easy_camera2.with_control_area (Some area)
    |> Fun.flip Easy_camera2.update frame

  let panel ?(x = 12.) ?(y = 12.) ?(width = 280.) ?viewport control ui ~camera frame =
    let control, camera, requests =
      if control.ui_visible then
        fitted_panel ui ~x ~y ~width frame (fun () -> widgets control ui ~camera)
      else { control with open_camera = None }, camera, [] in
    let area = if control.ui_visible
      then camera_area (int_of_float x, int_of_float (Float.max 180. width)) frame
      else 0, 0, frame.width, frame.height in
    control, navigate ~control_area:area ?viewport control camera frame, requests

  let ui_visible (control : t) = control.ui_visible
  let overlay (control : t) scene = if control.ui_visible then scene else Scene.empty
  let save request = Canvas.save_screen_png request.filename
end
