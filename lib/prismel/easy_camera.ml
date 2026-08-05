type interaction = Orbit | Pan | Dolly

type binding = {
  button : Input.mouse_button;
  key : Input.key option;
  interaction : interaction;
}

type settings = {
  target : Vec3.t;
  distance : float;
  azimuth : float;
  elevation : float;
}

type motion = {
  interaction : interaction;
  dx : float;
  dy : float;
}

type t = {
  target : Vec3.t;
  distance : float;
  azimuth : float;
  elevation : float;
  fov_y : float;
  near : float;
  far : float;
  enabled : bool;
  control_area : (int * int * int * int) option;
  inertia : bool;
  drag_coefficient : float;
  rotation_sensitivity : Vec2.t;
  translation_sensitivity : Vec2.t;
  dolly_sensitivity : float;
  up_axis : Vec3.t;
  relative_y_axis : bool;
  middle_button_enabled : bool;
  translation_key : Input.key option;
  auto_distance : bool;
  auto_distance_pending : bool;
  interactions : binding list;
  drag : (Input.mouse_button * interaction * (int * int)) option;
  velocity : motion option;
  last_press : (Input.mouse_button * (int * int) * float) option;
  initial : settings;
}

let validate_distance distance =
  if not (Float.is_finite distance) || distance <= 0. then
    invalid_arg "Easy_camera: distance must be finite and positive"

let validate_nonnegative name value =
  if not (Float.is_finite value) || value < 0. then
    invalid_arg
      ("Easy_camera: " ^ name ^ " must be finite and non-negative")

let validate_sensitivity name value =
  validate_nonnegative (name ^ ".x") value.Vec2.x;
  validate_nonnegative (name ^ ".y") value.y

let validate_drag_coefficient value =
  if not (Float.is_finite value) || value < 0. || value >= 1. then
    invalid_arg
      "Easy_camera: drag coefficient must be finite and in [0, 1)"

let validate_up_axis axis =
  if Vec3.length_sq axis <= 1e-18 then
    invalid_arg "Easy_camera: up axis must be non-zero"

let validate_control_area = function
  | None -> ()
  | Some (_, _, width, height) ->
      if width < 0 || height < 0 then
        invalid_arg
          "Easy_camera: control-area dimensions must be non-negative"

let clamp_elevation elevation =
  let limit = (Float.pi /. 2.) -. 1e-4 in
  Float.max (-.limit) (Float.min limit elevation)

let default_interactions =
  [
    { button = Input.LeftButton; key = None; interaction = Orbit };
    { button = Input.MiddleButton; key = None; interaction = Pan };
    { button = Input.RightButton; key = None; interaction = Dolly };
  ]

let create ?(target = Vec3.zero) ?(distance = 10.) ?(azimuth = 0.)
    ?(elevation = 0.) ?(fov_y = Float.pi /. 3.) ?(near = 0.1)
    ?(far = 1000.) ?(enabled = true) ?control_area ?(inertia = true)
    ?(drag_coefficient = 0.9)
    ?(rotation_sensitivity = Vec2.create 0.01 0.01)
    ?(translation_sensitivity = Vec2.create 1. 1.)
    ?(dolly_sensitivity = 0.01) ?(up_axis = Vec3.unit_y)
    ?(relative_y_axis = true) ?(middle_button_enabled = true)
    ?translation_key ?(auto_distance = false) () =
  validate_distance distance;
  validate_control_area control_area;
  validate_drag_coefficient drag_coefficient;
  validate_sensitivity "rotation sensitivity" rotation_sensitivity;
  validate_sensitivity "translation sensitivity" translation_sensitivity;
  validate_nonnegative "dolly sensitivity" dolly_sensitivity;
  validate_up_axis up_axis;
  ignore
    (Camera.perspective ~fov_y ~near ~far
       ~at:(Vec3.create 0. 0. distance) ~target ());
  let elevation = clamp_elevation elevation in
  {
    target;
    distance;
    azimuth;
    elevation;
    fov_y;
    near;
    far;
    enabled;
    control_area;
    inertia;
    drag_coefficient;
    rotation_sensitivity;
    translation_sensitivity;
    dolly_sensitivity;
    up_axis = Vec3.normalize up_axis;
    relative_y_axis;
    middle_button_enabled;
    translation_key;
    auto_distance;
    auto_distance_pending = auto_distance;
    interactions = default_interactions;
    drag = None;
    velocity = None;
    last_press = None;
    initial = { target; distance; azimuth; elevation };
  }

let orbit_basis up =
  let candidate =
    if abs_float (Vec3.dot up Vec3.unit_z) < 0.999 then Vec3.unit_z
    else Vec3.unit_x
  in
  let forward =
    Vec3.sub candidate (Vec3.scale up (Vec3.dot candidate up))
    |> Vec3.normalize
  in
  let right = Vec3.cross up forward |> Vec3.normalize in
  right, forward

let camera value =
  let up = value.up_axis in
  let right, forward = orbit_basis up in
  let cosine = cos value.elevation in
  let horizontal =
    Vec3.add
      (Vec3.scale right (cosine *. sin value.azimuth))
      (Vec3.scale forward (cosine *. cos value.azimuth))
  in
  let offset =
    Vec3.add horizontal (Vec3.scale up (sin value.elevation))
    |> Fun.flip Vec3.scale value.distance
  in
  Camera.perspective ~fov_y:value.fov_y ~near:value.near ~far:value.far
    ~at:(Vec3.add value.target offset) ~target:value.target ()
  |> Camera.with_up up

let target value = value.target
let distance value = value.distance
let enabled value = value.enabled
let control_area value = value.control_area
let inertia value = value.inertia
let drag_coefficient value = value.drag_coefficient
let rotation_sensitivity value = value.rotation_sensitivity
let translation_sensitivity value = value.translation_sensitivity
let dolly_sensitivity value = value.dolly_sensitivity
let up_axis value = value.up_axis
let relative_y_axis value = value.relative_y_axis
let middle_button_enabled value = value.middle_button_enabled
let translation_key value = value.translation_key
let auto_distance value = value.auto_distance
let interactions value = value.interactions
let with_target target value = { value with target }

let with_distance distance value =
  validate_distance distance;
  { value with distance }

let set_enabled enabled value =
  {
    value with
    enabled;
    drag = if enabled then value.drag else None;
    velocity = if enabled then value.velocity else None;
  }

let with_control_area area value =
  validate_control_area area;
  { value with control_area = area; drag = None }

let with_inertia inertia value =
  { value with inertia; velocity = if inertia then value.velocity else None }

let with_drag_coefficient drag_coefficient value =
  validate_drag_coefficient drag_coefficient;
  { value with drag_coefficient }

let with_rotation_sensitivity rotation_sensitivity value =
  validate_sensitivity "rotation sensitivity" rotation_sensitivity;
  { value with rotation_sensitivity }

let with_translation_sensitivity translation_sensitivity value =
  validate_sensitivity "translation sensitivity" translation_sensitivity;
  { value with translation_sensitivity }

let with_dolly_sensitivity dolly_sensitivity value =
  validate_nonnegative "dolly sensitivity" dolly_sensitivity;
  { value with dolly_sensitivity }

let with_up_axis up_axis value =
  validate_up_axis up_axis;
  { value with up_axis = Vec3.normalize up_axis }

let with_relative_y_axis relative_y_axis value =
  { value with relative_y_axis }

let with_middle_button_enabled middle_button_enabled value =
  {
    value with
    middle_button_enabled;
    drag =
      (match value.drag with
       | Some (Input.MiddleButton, _, _) when not middle_button_enabled -> None
       | drag -> drag);
  }

let with_translation_key translation_key value =
  { value with translation_key }

let with_auto_distance auto_distance value =
  {
    value with
    auto_distance;
    auto_distance_pending = auto_distance;
  }

let same_binding button key binding =
  binding.button = button && binding.key = key

let add_interaction ?key ~button interaction value =
  {
    value with
    interactions =
      { button; key; interaction }
      :: List.filter
           (fun binding -> not (same_binding button key binding))
           value.interactions;
    drag = None;
  }

let remove_interaction ?key ~button value =
  {
    value with
    interactions =
      List.filter
        (fun binding -> not (same_binding button key binding))
        value.interactions;
    drag =
      (match value.drag with
       | Some (candidate, _, _) when candidate = button -> None
       | drag -> drag);
  }

let clear_interactions value =
  { value with interactions = []; drag = None; velocity = None }

let has_interaction ?key ~button interaction value =
  List.exists
    (fun binding ->
      same_binding button key binding && binding.interaction = interaction)
    value.interactions

let reset value =
  {
    value with
    target = value.initial.target;
    distance = value.initial.distance;
    azimuth = value.initial.azimuth;
    elevation = value.initial.elevation;
    drag = None;
    velocity = None;
    auto_distance_pending = value.auto_distance;
  }

let contains value (x, y) =
  match value.control_area with
  | None -> true
  | Some (left, top, width, height) ->
      x >= left && y >= top && x < left + width && y < top + height

let pan_axes value =
  let camera = camera value in
  let forward =
    Vec3.normalize (Vec3.sub (Camera.target camera) (Camera.position camera))
  in
  let up =
    if value.relative_y_axis then Camera.up camera else value.up_axis
  in
  let right = Vec3.normalize (Vec3.cross forward up) in
  let up = Vec3.normalize (Vec3.cross right forward) in
  right, up

let apply_delta frame value interaction dx dy =
  match interaction with
  | Orbit ->
      {
        value with
        azimuth =
          value.azimuth -. (dx *. value.rotation_sensitivity.Vec2.x);
        elevation =
          clamp_elevation
            (value.elevation +. (dy *. value.rotation_sensitivity.y));
      }
  | Pan ->
      let right, up = pan_axes value in
      let height = max 1 frame.Frame.height in
      let units_per_pixel =
        2. *. value.distance *. tan (value.fov_y /. 2.)
        /. float_of_int height
      in
      let delta =
        Vec3.add
          (Vec3.scale right
             (-.dx *. units_per_pixel *. value.translation_sensitivity.x))
          (Vec3.scale up
             (dy *. units_per_pixel *. value.translation_sensitivity.y))
      in
      { value with target = Vec3.add value.target delta }
  | Dolly ->
      let distance =
        value.distance *. exp (dy *. value.dolly_sensitivity)
      in
      { value with distance = Float.max 1e-4 distance }

let interaction_for_button value frame button =
  if button = Input.MiddleButton && not value.middle_button_enabled then None
  else
    match value.translation_key with
    | Some key when button = Input.LeftButton && Frame.key_down key frame ->
        Some Pan
    | _ ->
        let eligible binding =
          binding.button = button
          &&
          match binding.key with
          | None -> true
          | Some key -> Frame.key_down key frame
        in
        (match
           List.find_opt
             (fun binding -> Option.is_some binding.key && eligible binding)
             value.interactions
         with
         | Some binding -> Some binding.interaction
         | None ->
             List.find_opt eligible value.interactions
             |> Option.map (fun (binding : binding) -> binding.interaction))

let double_click value button point time =
  match value.last_press with
  | Some (previous_button, (previous_x, previous_y), previous_time) ->
      let x, y = point in
      previous_button = button
      && time >= previous_time
      && time -. previous_time <= 0.3
      && ((x - previous_x) * (x - previous_x))
         + ((y - previous_y) * (y - previous_y)) <= 25
  | None -> false

let apply_inertia frame value =
  match value.drag, value.velocity with
  | None, Some motion when value.inertia && frame.Frame.dt > 0. ->
      let frames = frame.dt *. 60. in
      let decay = value.drag_coefficient ** frames in
      let value =
        apply_delta frame value motion.interaction
          (motion.dx *. decay) (motion.dy *. decay)
      in
      if abs_float motion.dx *. decay < 1e-4
         && abs_float motion.dy *. decay < 1e-4
      then { value with velocity = None }
      else
        {
          value with
          velocity =
            Some { motion with dx = motion.dx *. decay; dy = motion.dy *. decay };
        }
  | None, Some _ -> { value with velocity = None }
  | _ -> value

let update value frame =
  if not value.enabled then value
  else
    let value =
      if value.auto_distance_pending then
        let height = float_of_int (max 1 frame.Frame.height) in
        {
          value with
          distance = height /. (2. *. tan (value.fov_y /. 2.));
          auto_distance_pending = false;
        }
      else value
    in
    let value =
      List.fold_left
        (fun value event ->
          match event with
          | Event.MousePressed (button, point) ->
              if not (contains value point) then value
              else if double_click value button point frame.Frame.time then
                let value = reset value in
                { value with last_press = Some (button, point, frame.time) }
              else
                (match interaction_for_button value frame button with
                 | None ->
                     { value with last_press = Some (button, point, frame.time) }
                 | Some interaction ->
                     {
                       value with
                       drag = Some (button, interaction, point);
                       velocity = None;
                       last_press = Some (button, point, frame.time);
                     })
          | MouseMoved ((x, y) as point) ->
              (match value.drag with
               | None -> value
               | Some (button, interaction, (previous_x, previous_y)) ->
                   let dx = float_of_int (x - previous_x)
                   and dy = float_of_int (y - previous_y) in
                   apply_delta frame value interaction dx dy
                   |> fun value ->
                   {
                     value with
                     drag = Some (button, interaction, point);
                     velocity = Some { interaction; dx; dy };
                   })
          | MouseReleased (button, _) ->
              (match value.drag with
               | Some (captured, _, _) when captured = button ->
                   {
                     value with
                     drag = None;
                     velocity = if value.inertia then value.velocity else None;
                   }
               | _ -> value)
          | MouseScrolled (_, vertical) when contains value frame.Frame.mouse ->
              {
                value with
                distance =
                  Float.max 1e-4
                    (value.distance
                     *. exp
                          (-.float_of_int vertical
                           *. value.dolly_sensitivity *. 12.));
                velocity = None;
              }
          | WindowFocusLost ->
              { value with drag = None; velocity = None; last_press = None }
          | _ -> value)
        value frame.events
    in
    apply_inertia frame value
