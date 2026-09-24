type t = {
  position : Vec3.t;
  orientation : Quat.t;
  scale : Vec3.t;
  parent : t option;
}

let validate_scale scale =
  if scale.Vec3.x = 0. || scale.y = 0. || scale.z = 0.
     || not (Float.is_finite scale.x)
     || not (Float.is_finite scale.y)
     || not (Float.is_finite scale.z)
  then invalid_arg "Node3: scale components must be finite and non-zero"

let create ?(position = Vec3.zero) ?(orientation = Quat.identity)
    ?(scale = Vec3.create 1. 1. 1.) ?parent () =
  validate_scale scale;
  { position; orientation = Quat.normalize orientation; scale; parent }

let position node = node.position
let orientation node = node.orientation
let scale node = node.scale
let parent node = node.parent
let with_position position node = { node with position }
let with_orientation orientation node =
  { node with orientation = Quat.normalize orientation }
let with_scale scale node =
  validate_scale scale;
  { node with scale }

let local_transform node =
  Mat4.mul
    (Mat4.translation node.position)
    (Mat4.mul (Quat.to_mat4 node.orientation) (Mat4.scaling node.scale))

let rec global_transform node =
  match node.parent with
  | None -> local_transform node
  | Some parent -> Mat4.mul (global_transform parent) (local_transform node)

let global_position node =
  Mat4.transform_point (global_transform node) Vec3.zero

let rec global_orientation node =
  match node.parent with
  | None -> node.orientation
  | Some parent ->
      Quat.mul (global_orientation parent) node.orientation |> Quat.normalize

let rec global_scale node =
  match node.parent with
  | None -> node.scale
  | Some parent ->
      let parent_scale = global_scale parent in
      Vec3.create
        (parent_scale.x *. node.scale.x)
        (parent_scale.y *. node.scale.y)
        (parent_scale.z *. node.scale.z)

let euler node = Quat.to_euler node.orientation
let pitch node = (euler node).Vec3.x
let heading node = (euler node).Vec3.y
let roll_angle node = (euler node).Vec3.z

let decompose matrix parent =
  let position =
    Vec3.create
      (Mat4.get matrix ~row:0 ~column:3)
      (Mat4.get matrix ~row:1 ~column:3)
      (Mat4.get matrix ~row:2 ~column:3)
  in
  let column column =
    Vec3.create
      (Mat4.get matrix ~row:0 ~column)
      (Mat4.get matrix ~row:1 ~column)
      (Mat4.get matrix ~row:2 ~column)
  in
  let scale =
    Vec3.create
      (Vec3.length (column 0))
      (Vec3.length (column 1))
      (Vec3.length (column 2))
  in
  validate_scale scale;
  let rotation =
    Mat4.of_rows
      ( Mat4.get matrix ~row:0 ~column:0 /. scale.x,
        Mat4.get matrix ~row:0 ~column:1 /. scale.y,
        Mat4.get matrix ~row:0 ~column:2 /. scale.z,
        0. )
      ( Mat4.get matrix ~row:1 ~column:0 /. scale.x,
        Mat4.get matrix ~row:1 ~column:1 /. scale.y,
        Mat4.get matrix ~row:1 ~column:2 /. scale.z,
        0. )
      ( Mat4.get matrix ~row:2 ~column:0 /. scale.x,
        Mat4.get matrix ~row:2 ~column:1 /. scale.y,
        Mat4.get matrix ~row:2 ~column:2 /. scale.z,
        0. )
      (0., 0., 0., 1.)
  in
  {
    position;
    orientation = Quat.of_mat4 rotation;
    scale;
    parent;
  }

let reparent ~maintain_global parent node =
  if not maintain_global then { node with parent }
  else
    let global = global_transform node in
    let local =
      match parent with
      | None -> global
      | Some parent ->
          (match Mat4.inverse (global_transform parent) with
           | None -> invalid_arg "Node3: parent transform is singular"
           | Some inverse -> Mat4.mul inverse global)
    in
    decompose local parent

let with_parent ?(maintain_global = false) parent node =
  reparent ~maintain_global (Some parent) node

let clear_parent ?(maintain_global = false) node =
  reparent ~maintain_global None node

let x_axis node = Quat.rotate (global_orientation node) Vec3.unit_x
let y_axis node = Quat.rotate (global_orientation node) Vec3.unit_y
let z_axis node = Quat.rotate (global_orientation node) Vec3.unit_z
let look_direction node = Vec3.neg (z_axis node)

let set_global_position position node =
  match node.parent with
  | None -> { node with position }
  | Some parent ->
      (match Mat4.inverse (global_transform parent) with
       | None -> invalid_arg "Node3.set_global_position: parent is singular"
       | Some inverse ->
           { node with position = Mat4.transform_point inverse position })

let set_global_orientation orientation node =
  let orientation = Quat.normalize orientation in
  match node.parent with
  | None -> { node with orientation }
  | Some parent ->
      (match Quat.inverse (global_orientation parent) with
       | None ->
           invalid_arg
             "Node3.set_global_orientation: parent orientation is singular"
       | Some inverse ->
           {
             node with
             orientation = Quat.mul inverse orientation |> Quat.normalize;
           })

let move delta node =
  set_global_position (Vec3.add (global_position node) delta) node

let truck amount node = move (Vec3.scale (x_axis node) amount) node
let boom amount node = move (Vec3.scale (y_axis node) amount) node
let dolly amount node = move (Vec3.scale (look_direction node) amount) node

let rotate rotation node =
  {
    node with
    orientation = Quat.mul node.orientation rotation |> Quat.normalize;
  }

let rotate_axis ~axis angle node =
  rotate (Quat.axis_angle ~axis angle) node

let rotate_around ~point rotation node =
  let rotation = Quat.normalize rotation in
  let position =
    Vec3.sub (global_position node) point
    |> Quat.rotate rotation
    |> Vec3.add point
  and orientation =
    Quat.mul rotation (global_orientation node) |> Quat.normalize
  in
  node
  |> set_global_position position
  |> set_global_orientation orientation

let pan angle node = rotate_axis ~axis:Vec3.unit_y angle node
let tilt angle node = rotate_axis ~axis:Vec3.unit_x angle node
let roll angle node = rotate_axis ~axis:Vec3.unit_z angle node

let look_at ?(up = Vec3.unit_y) target node =
  let forward = Vec3.normalize (Vec3.sub target (global_position node)) in
  if Vec3.length_sq forward <= 1e-12 then
    invalid_arg "Node3.look_at: target must differ from the node position";
  let right = Vec3.normalize (Vec3.cross forward up) in
  if Vec3.length_sq right <= 1e-12 then
    invalid_arg "Node3.look_at: up must not be parallel to the view direction";
  let actual_up = Vec3.cross right forward in
  let global_rotation =
    Mat4.of_rows
      (right.x, actual_up.x, -.forward.x, 0.)
      (right.y, actual_up.y, -.forward.y, 0.)
      (right.z, actual_up.z, -.forward.z, 0.)
      (0., 0., 0., 1.)
    |> Quat.of_mat4
  in
  let orientation =
    match node.parent with
    | None -> global_rotation
    | Some parent ->
        (match Quat.inverse (global_orientation parent) with
         | None -> global_rotation
         | Some inverse -> Quat.mul inverse global_rotation)
  in
  { node with orientation = Quat.normalize orientation }

let orbit ~center ~azimuth ~elevation ~radius node =
  if not (Float.is_finite radius) || radius <= 0. then
    invalid_arg "Node3.orbit: radius must be finite and positive";
  let cosine = cos elevation in
  let position =
    Vec3.add center
      (Vec3.create
         (radius *. cosine *. sin azimuth)
         (radius *. sin elevation)
         (radius *. cosine *. cos azimuth))
  in
  set_global_position position node |> look_at center

let local_to_global_point node =
  Mat4.transform_point (global_transform node)

let global_to_local_point node point =
  Mat4.inverse (global_transform node)
  |> Option.map (fun inverse -> Mat4.transform_point inverse point)

let local_to_global_direction node direction =
  Mat4.transform_direction (global_transform node) direction

let global_to_local_direction node direction =
  Mat4.inverse (global_transform node)
  |> Option.map (fun inverse -> Mat4.transform_direction inverse direction)

let reset node =
  {
    node with
    position = Vec3.zero;
    orientation = Quat.identity;
    scale = Vec3.create 1. 1. 1.;
  }
