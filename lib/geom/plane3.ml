open Prismel

type t = { normal : Vec3.t; offset : float }

let make ~normal ~offset =
  let length = Vec3.length normal in
  if not (Float.is_finite length) || length <= 1e-15
     || not (Float.is_finite offset)
  then invalid_arg "Plane3.make: normal and offset must be finite; normal non-zero";
  { normal = Vec3.scale normal (1. /. length); offset = offset /. length }

let through ~normal ~point = make ~normal ~offset:(Vec3.dot normal point)

let through_three_points ?(epsilon = 1e-9) a b c =
  let normal = Vec3.cross (Vec3.sub b a) (Vec3.sub c a) in
  if Vec3.length_sq normal <= epsilon *. epsilon then None
  else Some (through ~normal ~point:a)

let signed_distance plane point = Vec3.dot plane.normal point -. plane.offset

let classify ?(epsilon = 1e-9) plane point =
  let distance = signed_distance plane point in
  if distance > epsilon then `Front
  else if distance < -.epsilon then `Back
  else `Coplanar

let project plane point =
  Vec3.sub point (Vec3.scale plane.normal (signed_distance plane point))

let reflect_point plane point =
  Vec3.sub point (Vec3.scale plane.normal (2. *. signed_distance plane point))

let flip plane = { normal = Vec3.neg plane.normal; offset = -.plane.offset }
