type projection =
  | Perspective of {
      fov_y : float;
      near : float;
      far : float;
      lens_offset : Vec2.t;
    }
  | Orthographic of {
      height : float;
      near : float;
      far : float;
    }
  | Frustum of {
      left : float;
      right : float;
      bottom : float;
      top : float;
      near : float;
      far : float;
    }

type t = {
  position : Vec3.t;
  target : Vec3.t;
  up : Vec3.t;
  projection : projection;
  v_flip : bool;
  forced_aspect : float option;
}

let validate_view position target up =
  if Vec3.length_sq (Vec3.sub target position) = 0. then
    invalid_arg "Camera: position and target must differ";
  if Vec3.length_sq up = 0. then invalid_arg "Camera: up must be non-zero"

let create ~position ~target ~up ~projection ~v_flip =
  validate_view position target up;
  {
    position;
    target;
    up = Vec3.normalize up;
    projection;
    v_flip;
    forced_aspect = None;
  }

let perspective ?(fov_y = Float.pi /. 3.) ?(near = 0.1) ?(far = 1000.)
    ?(lens_offset = Vec2.zero) ?(v_flip = false) ~at ~target () =
  ignore (Mat4.perspective ~fov_y ~aspect:1. ~near ~far);
  create ~position:at ~target ~up:Vec3.unit_y
    ~projection:(Perspective { fov_y; near; far; lens_offset }) ~v_flip

let orthographic ?(near = 0.1) ?(far = 1000.) ?(v_flip = false)
    ~height ~at ~target () =
  if not (Float.is_finite height) || height <= 0. then
    invalid_arg "Camera.orthographic: height must be finite and positive";
  if near = far then invalid_arg "Camera.orthographic: near and far must differ";
  create ~position:at ~target ~up:Vec3.unit_y
    ~projection:(Orthographic { height; near; far }) ~v_flip

let frustum ~left ~right ~bottom ~top ~near ~far ?(v_flip = false)
    ~at ~target () =
  ignore (Mat4.frustum ~left ~right ~bottom ~top ~near ~far);
  create ~position:at ~target ~up:Vec3.unit_y
    ~projection:(Frustum { left; right; bottom; top; near; far }) ~v_flip

let off_axis_portal ?(near = 0.1) ?(far = 1000.) ?(v_flip = false)
    ~eye ~top_left ~bottom_left ~bottom_right () =
  let right_axis = Vec3.normalize (Vec3.sub bottom_right bottom_left)
  and up_axis = Vec3.normalize (Vec3.sub top_left bottom_left) in
  if Vec3.length_sq right_axis <= 1e-12
     || Vec3.length_sq up_axis <= 1e-12
  then invalid_arg "Camera.off_axis_portal: portal edges must be non-zero";
  let normal = Vec3.normalize (Vec3.cross right_axis up_axis) in
  if Vec3.length_sq normal <= 1e-12 then
    invalid_arg "Camera.off_axis_portal: portal edges must not be parallel";
  let to_bottom_left = Vec3.sub bottom_left eye
  and to_bottom_right = Vec3.sub bottom_right eye
  and to_top_left = Vec3.sub top_left eye in
  let distance = -.Vec3.dot to_bottom_left normal in
  if distance <= 1e-9 then
    invalid_arg "Camera.off_axis_portal: eye must face the portal front";
  let scale = near /. distance in
  let left = Vec3.dot right_axis to_bottom_left *. scale
  and right = Vec3.dot right_axis to_bottom_right *. scale
  and bottom = Vec3.dot up_axis to_bottom_left *. scale
  and top = Vec3.dot up_axis to_top_left *. scale in
  create ~position:eye ~target:(Vec3.sub eye normal) ~up:up_axis
    ~projection:(Frustum { left; right; bottom; top; near; far }) ~v_flip

let position camera = camera.position
let target camera = camera.target
let up camera = camera.up
let projection camera = camera.projection
let v_flip camera = camera.v_flip
let forced_aspect camera = camera.forced_aspect

let with_position position camera =
  validate_view position camera.target camera.up;
  { camera with position }

let with_target target camera =
  validate_view camera.position target camera.up;
  { camera with target }

let with_up up camera =
  validate_view camera.position camera.target up;
  { camera with up = Vec3.normalize up }

let look_at = with_target

let with_projection projection camera =
  { camera with projection }

let with_v_flip v_flip camera = { camera with v_flip }

let with_forced_aspect forced_aspect camera =
  Option.iter
    (fun aspect ->
      if not (Float.is_finite aspect) || aspect <= 0. then
        invalid_arg
          "Camera.with_forced_aspect: aspect must be finite and positive")
    forced_aspect;
  { camera with forced_aspect }

let axes camera =
  let forward = Vec3.normalize (Vec3.sub camera.target camera.position) in
  let right = Vec3.normalize (Vec3.cross forward camera.up) in
  let up = Vec3.normalize (Vec3.cross right forward) in
  right, up, forward

let move delta camera =
  {
    camera with
    position = Vec3.add camera.position delta;
    target = Vec3.add camera.target delta;
  }

let truck amount camera =
  let right, _, _ = axes camera in
  move (Vec3.scale right amount) camera

let boom amount camera =
  let _, up, _ = axes camera in
  move (Vec3.scale up amount) camera

let dolly amount camera =
  let _, _, forward = axes camera in
  move (Vec3.scale forward amount) camera

let orbit ~center ~azimuth ~elevation ~radius camera =
  if not (Float.is_finite radius) || radius <= 0. then
    invalid_arg "Camera.orbit: radius must be finite and positive";
  let cosine = cos elevation in
  let offset =
    Vec3.create
      (radius *. cosine *. sin azimuth)
      (radius *. sin elevation)
      (radius *. cosine *. cos azimuth)
  in
  {
    camera with
    position = Vec3.add center offset;
    target = center;
    up = Vec3.unit_y;
  }

let rotate_view axis angle camera =
  let direction = Vec3.sub camera.target camera.position in
  let rotation = Mat4.rotation ~axis angle in
  let direction = Mat4.transform_direction rotation direction in
  let up = Mat4.transform_direction rotation camera.up |> Vec3.normalize in
  { camera with target = Vec3.add camera.position direction; up }

let pan angle camera =
  let _, up, _ = axes camera in
  rotate_view up angle camera

let tilt angle camera =
  let right, _, _ = axes camera in
  rotate_view right angle camera

let roll angle camera =
  let _, _, forward = axes camera in
  rotate_view forward angle camera

let viewport_size (_, _, width, height) =
  if width <= 0 || height <= 0 then
    invalid_arg "Camera: viewport dimensions must be positive";
  float_of_int width, float_of_int height

let view_matrix camera =
  Mat4.look_at ~eye:camera.position ~target:camera.target ~up:camera.up

let aspect_ratio ~viewport camera =
  let width, height = viewport_size viewport in
  Option.value camera.forced_aspect ~default:(width /. height)

let image_plane_distance ~viewport camera =
  let _, height = viewport_size viewport in
  match camera.projection with
  | Perspective { fov_y; _ } -> Some (height /. (2. *. tan (fov_y /. 2.)))
  | Orthographic _ | Frustum _ -> None

let projection_matrix ~viewport camera =
  ignore (viewport_size viewport);
  let aspect = aspect_ratio ~viewport camera in
  let projection =
    match camera.projection with
    | Perspective { fov_y; near; far; lens_offset } ->
        let base = Mat4.perspective ~fov_y ~aspect ~near ~far in
        let offset =
          Mat4.translation (Vec3.create lens_offset.x lens_offset.y 0.)
        in
        Mat4.mul offset base
    | Orthographic { height; near; far } ->
        let half_height = height /. 2. in
        let half_width = half_height *. aspect in
        Mat4.orthographic
          ~left:(-.half_width) ~right:half_width
          ~bottom:(-.half_height) ~top:half_height ~near ~far
    | Frustum { left; right; bottom; top; near; far } ->
        Mat4.frustum ~left ~right ~bottom ~top ~near ~far
  in
  if camera.v_flip then
    Mat4.mul (Mat4.scaling (Vec3.create 1. (-1.) 1.)) projection
  else projection

let view_projection_matrix ~viewport camera =
  Mat4.mul
    (projection_matrix ~viewport camera)
    (view_matrix camera)

let world_to_screen ~viewport:((vx, vy, _, _) as viewport) camera point =
  let width, height = viewport_size viewport in
  let matrix = view_projection_matrix ~viewport camera in
  let x, y, z, w =
    Mat4.transform matrix (point.Vec3.x, point.y, point.z, 1.)
  in
  if w <= 1e-12 then None
  else
    let ndc_x = x /. w and ndc_y = y /. w and ndc_z = z /. w in
    Some
      (Vec3.create
         (float_of_int vx +. ((ndc_x +. 1.) *. 0.5 *. width))
         (float_of_int vy +. ((1. -. ndc_y) *. 0.5 *. height))
         ((ndc_z +. 1.) *. 0.5))

let screen_to_world ~viewport:((vx, vy, _, _) as viewport) camera point =
  let width, height = viewport_size viewport in
  match Mat4.inverse (view_projection_matrix ~viewport camera) with
  | None -> None
  | Some inverse ->
      let ndc_x =
        (2. *. (point.Vec3.x -. float_of_int vx) /. width) -. 1.
      in
      let ndc_y =
        1. -. (2. *. (point.y -. float_of_int vy) /. height)
      in
      let ndc_z = (2. *. point.z) -. 1. in
      let x, y, z, w =
        Mat4.transform inverse (ndc_x, ndc_y, ndc_z, 1.)
      in
      if abs_float w <= 1e-12 then None
      else Some (Vec3.create (x /. w) (y /. w) (z /. w))

let world_to_camera camera point =
  Mat4.transform_point (view_matrix camera) point

let camera_to_world camera point =
  Mat4.inverse (view_matrix camera)
  |> Option.map (fun inverse -> Mat4.transform_point inverse point)

let screen_ray ~viewport camera ~at:(x, y) =
  match
    screen_to_world ~viewport camera (Vec3.create x y 0.),
    screen_to_world ~viewport camera (Vec3.create x y 1.)
  with
  | Some near, Some far ->
      Some (near, Vec3.normalize (Vec3.sub far near))
  | _ -> None

let frustum_mesh ~viewport:((x, y, width, height) as viewport) camera =
  let point screen_x screen_y depth =
    match
      screen_to_world ~viewport camera
        (Vec3.create (float_of_int screen_x) (float_of_int screen_y) depth)
    with
    | Some point -> point
    | None -> invalid_arg "Camera.frustum_mesh: camera matrix is singular"
  in
  let near =
    [|
      point x y 0.;
      point (x + width) y 0.;
      point (x + width) (y + height) 0.;
      point x (y + height) 0.;
    |]
  and far =
    [|
      point x y 1.;
      point (x + width) y 1.;
      point (x + width) (y + height) 1.;
      point x (y + height) 1.;
    |]
  in
  let vertices = ref [] in
  let line left right = vertices := right :: left :: !vertices in
  for index = 0 to 3 do
    let next = (index + 1) mod 4 in
    line near.(index) near.(next);
    line far.(index) far.(next);
    line near.(index) far.(index)
  done;
  Mesh.create_exn ~mode:Mesh.Lines (List.rev !vertices)
