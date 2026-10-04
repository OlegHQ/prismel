type t = { x : float; y : float; z : float; w : float }

let create ~x ~y ~z ~w = { x; y; z; w }
let identity = { x = 0.; y = 0.; z = 0.; w = 1. }

let length_squared value =
  (value.x *. value.x) +. (value.y *. value.y)
  +. (value.z *. value.z) +. (value.w *. value.w)

let normalize value =
  let length = sqrt (length_squared value) in
  if length <= 1e-12 then identity
  else
    {
      x = value.x /. length;
      y = value.y /. length;
      z = value.z /. length;
      w = value.w /. length;
    }

let conjugate value =
  { x = -.value.x; y = -.value.y; z = -.value.z; w = value.w }

let inverse value =
  let length_squared = length_squared value in
  if length_squared <= 1e-12 then None
  else
    let conjugate = conjugate value in
    Some {
      x = conjugate.x /. length_squared;
      y = conjugate.y /. length_squared;
      z = conjugate.z /. length_squared;
      w = conjugate.w /. length_squared;
    }

let mul left right =
  {
    w =
      (left.w *. right.w) -. (left.x *. right.x)
      -. (left.y *. right.y) -. (left.z *. right.z);
    x =
      (left.w *. right.x) +. (left.x *. right.w)
      +. (left.y *. right.z) -. (left.z *. right.y);
    y =
      (left.w *. right.y) -. (left.x *. right.z)
      +. (left.y *. right.w) +. (left.z *. right.x);
    z =
      (left.w *. right.z) +. (left.x *. right.y)
      -. (left.y *. right.x) +. (left.z *. right.w);
  }

let axis_angle ~axis angle =
  if Vec3.length_sq axis <= 1e-12 then identity
  else
    let axis = Vec3.normalize axis in
    let half = angle /. 2. and sine = sin (angle /. 2.) in
    normalize {
      x = axis.x *. sine;
      y = axis.y *. sine;
      z = axis.z *. sine;
      w = cos half;
    }

let of_euler ~pitch ~yaw ~roll =
  mul (axis_angle ~axis:Vec3.unit_y yaw)
    (mul (axis_angle ~axis:Vec3.unit_x pitch)
       (axis_angle ~axis:Vec3.unit_z roll))
  |> normalize

let to_mat4 value =
  let value = normalize value in
  let xx = value.x *. value.x and yy = value.y *. value.y
  and zz = value.z *. value.z and xy = value.x *. value.y
  and xz = value.x *. value.z and yz = value.y *. value.z
  and wx = value.w *. value.x and wy = value.w *. value.y
  and wz = value.w *. value.z in
  Mat4.of_rows
    (1. -. (2. *. (yy +. zz)), 2. *. (xy -. wz),
     2. *. (xz +. wy), 0.)
    (2. *. (xy +. wz), 1. -. (2. *. (xx +. zz)),
     2. *. (yz -. wx), 0.)
    (2. *. (xz -. wy), 2. *. (yz +. wx),
     1. -. (2. *. (xx +. yy)), 0.)
    (0., 0., 0., 1.)

let to_euler value =
  let matrix = to_mat4 value in
  let sine_pitch =
    -.Mat4.get matrix ~row:1 ~column:2
    |> Float.max (-1.) |> Float.min 1.
  in
  let pitch = asin sine_pitch in
  let cosine_pitch = cos pitch in
  if abs_float cosine_pitch > 1e-8 then
    Vec3.create pitch
      (atan2
         (Mat4.get matrix ~row:0 ~column:2)
         (Mat4.get matrix ~row:2 ~column:2))
      (atan2
         (Mat4.get matrix ~row:1 ~column:0)
         (Mat4.get matrix ~row:1 ~column:1))
  else
    Vec3.create pitch
      (atan2
         (-.Mat4.get matrix ~row:2 ~column:0)
         (Mat4.get matrix ~row:0 ~column:0))
      0.

let of_mat4 matrix =
  let m00 = Mat4.get matrix ~row:0 ~column:0
  and m11 = Mat4.get matrix ~row:1 ~column:1
  and m22 = Mat4.get matrix ~row:2 ~column:2 in
  let trace = m00 +. m11 +. m22 in
  let value =
    if trace > 0. then
      let scale = sqrt (trace +. 1.) *. 2. in
      {
        w = 0.25 *. scale;
        x =
          (Mat4.get matrix ~row:2 ~column:1
           -. Mat4.get matrix ~row:1 ~column:2) /. scale;
        y =
          (Mat4.get matrix ~row:0 ~column:2
           -. Mat4.get matrix ~row:2 ~column:0) /. scale;
        z =
          (Mat4.get matrix ~row:1 ~column:0
           -. Mat4.get matrix ~row:0 ~column:1) /. scale;
      }
    else if m00 > m11 && m00 > m22 then
      let scale = sqrt (1. +. m00 -. m11 -. m22) *. 2. in
      {
        w =
          (Mat4.get matrix ~row:2 ~column:1
           -. Mat4.get matrix ~row:1 ~column:2) /. scale;
        x = 0.25 *. scale;
        y =
          (Mat4.get matrix ~row:0 ~column:1
           +. Mat4.get matrix ~row:1 ~column:0) /. scale;
        z =
          (Mat4.get matrix ~row:0 ~column:2
           +. Mat4.get matrix ~row:2 ~column:0) /. scale;
      }
    else if m11 > m22 then
      let scale = sqrt (1. +. m11 -. m00 -. m22) *. 2. in
      {
        w =
          (Mat4.get matrix ~row:0 ~column:2
           -. Mat4.get matrix ~row:2 ~column:0) /. scale;
        x =
          (Mat4.get matrix ~row:0 ~column:1
           +. Mat4.get matrix ~row:1 ~column:0) /. scale;
        y = 0.25 *. scale;
        z =
          (Mat4.get matrix ~row:1 ~column:2
           +. Mat4.get matrix ~row:2 ~column:1) /. scale;
      }
    else
      let scale = sqrt (1. +. m22 -. m00 -. m11) *. 2. in
      {
        w =
          (Mat4.get matrix ~row:1 ~column:0
           -. Mat4.get matrix ~row:0 ~column:1) /. scale;
        x =
          (Mat4.get matrix ~row:0 ~column:2
           +. Mat4.get matrix ~row:2 ~column:0) /. scale;
        y =
          (Mat4.get matrix ~row:1 ~column:2
           +. Mat4.get matrix ~row:2 ~column:1) /. scale;
        z = 0.25 *. scale;
      }
  in
  normalize value

let rotate orientation vector =
  Mat4.transform_direction (to_mat4 orientation) vector

let dot left right =
  (left.x *. right.x) +. (left.y *. right.y)
  +. (left.z *. right.z) +. (left.w *. right.w)

let negate value =
  { x = -.value.x; y = -.value.y; z = -.value.z; w = -.value.w }

let slerp left right amount =
  let left = normalize left and right = normalize right in
  let cosine = dot left right in
  let right, cosine =
    if cosine < 0. then negate right, -.cosine else right, cosine
  in
  if cosine > 0.9995 then
    normalize {
      x = left.x +. ((right.x -. left.x) *. amount);
      y = left.y +. ((right.y -. left.y) *. amount);
      z = left.z +. ((right.z -. left.z) *. amount);
      w = left.w +. ((right.w -. left.w) *. amount);
    }
  else
    let angle = acos (Float.max (-1.) (Float.min 1. cosine)) in
    let sine = sin angle in
    let left_weight = sin ((1. -. amount) *. angle) /. sine
    and right_weight = sin (amount *. angle) /. sine in
    {
      x = (left.x *. left_weight) +. (right.x *. right_weight);
      y = (left.y *. left_weight) +. (right.y *. right_weight);
      z = (left.z *. left_weight) +. (right.z *. right_weight);
      w = (left.w *. left_weight) +. (right.w *. right_weight);
    }
    |> normalize

let nearly_equal left right ~eps =
  let direct =
    abs_float (left.x -. right.x) <= eps
    && abs_float (left.y -. right.y) <= eps
    && abs_float (left.z -. right.z) <= eps
    && abs_float (left.w -. right.w) <= eps
  and negated =
    abs_float (left.x +. right.x) <= eps
    && abs_float (left.y +. right.y) <= eps
    && abs_float (left.z +. right.z) <= eps
    && abs_float (left.w +. right.w) <= eps
  in
  direct || negated
