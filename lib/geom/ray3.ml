open Prismel

type t = { origin : Vec3.t; direction : Vec3.t }

let make ~origin ~direction =
  let length = Vec3.length direction in
  if not (Float.is_finite length) || length <= 1e-15 then
    invalid_arg "Ray3.make: direction must be finite and non-zero";
  { origin; direction = Vec3.scale direction (1. /. length) }

let through ~origin point = make ~origin ~direction:(Vec3.sub point origin)
let point_at ray amount = Vec3.add ray.origin (Vec3.scale ray.direction amount)

let closest_parameter ray point =
  Vec3.dot (Vec3.sub point ray.origin) ray.direction |> Float.max 0.

let closest_point ray point = point_at ray (closest_parameter ray point)
let distance ray point = Vec3.distance point (closest_point ray point)

let transform matrix ray =
  make ~origin:(Mat4.transform_point matrix ray.origin)
    ~direction:(Mat4.transform_direction matrix ray.direction)
