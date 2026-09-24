open Prismel

type t = { origin : Vec2.t; direction : Vec2.t }

let make ~origin ~direction =
  let length = Vec2.length direction in
  if not (Float.is_finite length) || length <= 1e-15 then
    invalid_arg "Ray2.make: direction must be finite and non-zero";
  { origin; direction = Vec2.scale direction (1. /. length) }

let through ~origin point = make ~origin ~direction:(Vec2.sub point origin)
let point_at ray amount = Vec2.add ray.origin (Vec2.scale ray.direction amount)

let closest_parameter ray point =
  Vec2.dot (Vec2.sub point ray.origin) ray.direction |> Float.max 0.

let closest_point ray point = point_at ray (closest_parameter ray point)
let distance ray point = Vec2.distance point (closest_point ray point)

let transform affine ray =
  make ~origin:(Affine2.apply affine ray.origin)
    ~direction:(Affine2.apply_direction affine ray.direction)
