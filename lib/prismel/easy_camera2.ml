type settings = {
  center : Vec2.t;
  zoom : float;
  rotation : float;
}

type motion = {
  dx : float;
  dy : float;
}

type t = {
  center : Vec2.t;
  zoom : float;
  rotation : float;
  enabled : bool;
  viewport : (int * int * int * int) option;
  control_area : (int * int * int * int) option;
  inertia : bool;
  drag_coefficient : float;
  pan_sensitivity : float;
  zoom_sensitivity : float;
  translation_key : Input.key option;
  drag : (Input.mouse_button * (int * int)) option;
  velocity : motion option;
  last_press : (Input.mouse_button * (int * int) * float) option;
  initial : settings;
}

let validate_zoom zoom =
  if not (Float.is_finite zoom) || zoom <= 0. then
    invalid_arg "Easy_camera2: zoom must be finite and positive"

let validate_nonnegative name value =
  if not (Float.is_finite value) || value < 0. then
    invalid_arg
      ("Easy_camera2: " ^ name ^ " must be finite and non-negative")

let validate_drag_coefficient value =
  if not (Float.is_finite value) || value < 0. || value >= 1. then
    invalid_arg
      "Easy_camera2: drag coefficient must be finite and in [0, 1)"

let validate_area name = function
  | None -> ()
  | Some (_, _, width, height) ->
      if width < 0 || height < 0 then
        invalid_arg
          ("Easy_camera2: " ^ name ^ " dimensions must be non-negative")

let create ?(center = Vec2.zero) ?(zoom = 1.) ?(rotation = 0.)
    ?(enabled = true) ?viewport ?control_area ?(inertia = true)
    ?(drag_coefficient = 0.9) ?(pan_sensitivity = 1.)
    ?(zoom_sensitivity = 0.01) ?translation_key () =
  validate_zoom zoom;
  if not (Float.is_finite rotation) then
    invalid_arg "Easy_camera2: rotation must be finite";
  validate_area "viewport" viewport;
  validate_area "control-area" control_area;
  validate_drag_coefficient drag_coefficient;
  validate_nonnegative "pan sensitivity" pan_sensitivity;
  validate_nonnegative "zoom sensitivity" zoom_sensitivity;
  { center; zoom; rotation; enabled; viewport; control_area; inertia;
    drag_coefficient; pan_sensitivity; zoom_sensitivity; translation_key;
    drag = None; velocity = None; last_press = None;
    initial = { center; zoom; rotation } }

let center value = value.center
let zoom value = value.zoom
let rotation value = value.rotation
let enabled value = value.enabled
let viewport value = value.viewport
let control_area value = value.control_area
let inertia value = value.inertia
let drag_coefficient value = value.drag_coefficient
let pan_sensitivity value = value.pan_sensitivity
let zoom_sensitivity value = value.zoom_sensitivity
let translation_key value = value.translation_key

let with_center center value =
  if center = value.center then value else { value with center }

let with_zoom zoom value =
  validate_zoom zoom;
  if zoom = value.zoom then value else { value with zoom }

let with_rotation rotation value =
  if not (Float.is_finite rotation) then
    invalid_arg "Easy_camera2: rotation must be finite";
  if rotation = value.rotation then value else { value with rotation }

let set_enabled enabled value =
  { value with enabled;
    drag = if enabled then value.drag else None;
    velocity = if enabled then value.velocity else None }

let with_viewport viewport value =
  validate_area "viewport" viewport;
  if viewport = value.viewport then value else { value with viewport }

let with_control_area control_area value =
  validate_area "control-area" control_area;
  if control_area = value.control_area then value
  else { value with control_area; drag = None }

let with_inertia inertia value =
  if inertia = value.inertia then value
  else { value with inertia; velocity = if inertia then value.velocity else None }

let with_drag_coefficient drag_coefficient value =
  validate_drag_coefficient drag_coefficient;
  { value with drag_coefficient }

let with_pan_sensitivity pan_sensitivity value =
  validate_nonnegative "pan sensitivity" pan_sensitivity;
  { value with pan_sensitivity }

let with_zoom_sensitivity zoom_sensitivity value =
  validate_nonnegative "zoom sensitivity" zoom_sensitivity;
  { value with zoom_sensitivity }

let with_translation_key translation_key value =
  if translation_key = value.translation_key then value
  else { value with translation_key }

let reset value =
  { value with center = value.initial.center; zoom = value.initial.zoom;
    rotation = value.initial.rotation; drag = None; velocity = None }

let contains area (x, y) = match area with
  | None -> true
  | Some (left, top, width, height) ->
      x >= left && y >= top && x < left + width && y < top + height

let effective_viewport value frame = match value.viewport with
  | Some viewport -> viewport
  | None -> 0, 0, frame.Frame.width, frame.height

let viewport_center (x, y, width, height) =
  float_of_int x +. (float_of_int width /. 2.),
  float_of_int y +. (float_of_int height /. 2.)

let world_to_screen ~viewport value point =
  let screen_x, screen_y = viewport_center viewport in
  let local = Vec2.sub point value.center
    |> Fun.flip Vec2.scale value.zoom
    |> Fun.flip Vec2.rotate value.rotation in
  Vec2.create (screen_x +. local.x) (screen_y +. local.y)

let screen_to_world ~viewport value point =
  let screen_x, screen_y = viewport_center viewport in
  Vec2.sub point (Vec2.create screen_x screen_y)
  |> Fun.flip Vec2.rotate (-.value.rotation)
  |> Fun.flip Vec2.scale (1. /. value.zoom)
  |> Vec2.add value.center

let pan value dx dy =
  let delta = Vec2.create dx dy
    |> Fun.flip Vec2.rotate (-.value.rotation)
    |> Fun.flip Vec2.scale (value.pan_sensitivity /. value.zoom) in
  { value with center = Vec2.sub value.center delta }

let zoom_at value ~viewport point vertical =
  if vertical = 0 then value
  else
    let point = Vec2.of_pair point in
    let anchored_world = screen_to_world ~viewport value point in
    let zoom = Float.max 1e-6
        (value.zoom *. exp
          (float_of_int vertical *. value.zoom_sensitivity *. 12.)) in
    let zoomed = { value with zoom } in
    let after = screen_to_world ~viewport zoomed point in
    { zoomed with center = Vec2.add zoomed.center
        (Vec2.sub anchored_world after); velocity = None }

let pan_button value frame button =
  button = Input.MiddleButton || button = Input.RightButton
  || (button = Input.LeftButton
      && (match value.translation_key with
          | Some key -> Frame.key_down key frame
          | None -> false))

let double_click value button point time = match value.last_press with
  | Some (previous_button, (previous_x, previous_y), previous_time) ->
      let x, y = point in
      previous_button = button
      && time >= previous_time && time -. previous_time <= 0.3
      && ((x - previous_x) * (x - previous_x))
         + ((y - previous_y) * (y - previous_y)) <= 25
  | None -> false

let apply_inertia frame value = match value.drag, value.velocity with
  | None, Some motion when value.inertia && frame.Frame.dt > 0. ->
      let decay = value.drag_coefficient ** (frame.dt *. 60.) in
      let dx = motion.dx *. decay and dy = motion.dy *. decay in
      let value = pan value dx dy in
      if abs_float dx < 1e-4 && abs_float dy < 1e-4 then
        { value with velocity = None }
      else { value with velocity = Some { dx; dy } }
  | None, Some _ -> { value with velocity = None }
  | _ -> value

let update value frame =
  if not value.enabled then value
  else
    let viewport = effective_viewport value frame in
    let value = List.fold_left (fun value event -> match event with
      | Event.MousePressed (button, point) ->
          if not (contains value.control_area point) then value
          else if double_click value button point frame.Frame.time
                  && pan_button value frame button then
            let value = reset value in
            { value with last_press = Some (button, point, frame.time) }
          else if pan_button value frame button then
            { value with drag = Some (button, point); velocity = None;
              last_press = Some (button, point, frame.time) }
          else { value with last_press = Some (button, point, frame.time) }
      | MouseMoved (x, y) ->
          let point = x, y in
          (match value.drag with
           | None -> value
           | Some (button, (previous_x, previous_y)) ->
               let dx = float_of_int (x - previous_x)
               and dy = float_of_int (y - previous_y) in
               let value = pan value dx dy in
               { value with drag = Some (button, point);
                 velocity = Some { dx; dy } })
      | MouseReleased (button, _) ->
          (match value.drag with
           | Some (captured, _) when captured = button ->
               { value with drag = None;
                 velocity = if value.inertia then value.velocity else None }
           | _ -> value)
      | PointerCancelled button ->
          (match value.drag with
           | Some (captured, _) when captured = button ->
               { value with drag = None; velocity = None }
           | _ -> value)
      | MouseScrolled (horizontal, vertical)
          when contains value.control_area frame.Frame.mouse ->
          ignore horizontal;
          zoom_at value ~viewport frame.mouse vertical
      | WindowFocusLost ->
          { value with drag = None; velocity = None; last_press = None }
      | _ -> value) value frame.events in
    apply_inertia frame value

let scene ?viewport ?(pixel_scale = 1.) value world =
  if not (Float.is_finite pixel_scale) || pixel_scale <= 0. then
    invalid_arg "Easy_camera2.scene: pixel_scale must be finite and positive";
  let x, y, width, height = match viewport, value.viewport with
    | Some viewport, _ | None, Some viewport -> viewport
    | None, None -> invalid_arg
        "Easy_camera2.scene: viewport is required when the camera has none" in
  if width < 0 || height < 0 then
    invalid_arg "Easy_camera2.scene: viewport dimensions must be non-negative";
  let screen_x = x + (width / 2) and screen_y = y + (height / 2) in
  let center_x = int_of_float (Float.round value.center.Vec2.x)
  and center_y = int_of_float (Float.round value.center.y)
  and zoom = value.zoom *. pixel_scale in
  Scene.[clip ~at:(x, y) ~w:width ~h:height
    [translate screen_x screen_y
      [rotate value.rotation
        [scale zoom zoom
          [translate (-center_x) (-center_y) world]]]]]
