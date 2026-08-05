open Prismel

type t = {
  a : Vec2.t;
  b : Vec2.t;
}

type intersection =
  | No_intersection
  | Parallel
  | Coincident
  | Point of {
      point : Vec2.t;
      along_self : float;
      along_other : float;
    }

let make a b = { a; b }
let direction segment = Vec2.sub segment.b segment.a
let length_sq segment = Vec2.length_sq (direction segment)
let length segment = sqrt (length_sq segment)
let midpoint segment = Vec2.lerp segment.a segment.b 0.5
let point_at segment amount = Vec2.lerp segment.a segment.b amount

let closest_parameter segment point =
  let delta = direction segment in
  let denominator = Vec2.length_sq delta in
  if denominator <= 1e-18 then 0.
  else
    Vec2.dot (Vec2.sub point segment.a) delta /. denominator
    |> Float.max 0. |> Float.min 1.

let closest_point segment point =
  point_at segment (closest_parameter segment point)

let distance segment point = Vec2.distance point (closest_point segment point)

let cross left right =
  (left.Vec2.x *. right.Vec2.y) -. (left.y *. right.x)

let side segment point =
  cross (direction segment) (Vec2.sub point segment.a)

let bounds segment =
  Bounds2.make ~min:segment.a ~max:segment.b

let transform affine segment =
  { a = Affine2.apply affine segment.a; b = Affine2.apply affine segment.b }

let reflect_point point segment =
  let edge = direction segment in
  let denominator = Vec2.length_sq edge in
  let projection =
    if denominator <= 1e-18 then segment.a
    else
      let amount = Vec2.dot (Vec2.sub point segment.a) edge /. denominator in
      Vec2.add segment.a (Vec2.scale edge amount)
  in
  Vec2.sub (Vec2.scale projection 2.) point

let reflect ~mirror segment =
  make (reflect_point segment.a mirror) (reflect_point segment.b mirror)

let intersect ?(epsilon = 1e-9) left right =
  if not (Float.is_finite epsilon) || epsilon < 0. then
    invalid_arg "Segment2.intersect: epsilon must be finite and non-negative";
  let r = direction left and s = direction right in
  let denominator = cross r s in
  let delta = Vec2.sub right.a left.a in
  let numerator_t = cross delta s and numerator_u = cross delta r in
  if abs_float denominator <= epsilon then
    if abs_float numerator_t <= epsilon && abs_float numerator_u <= epsilon
    then Coincident
    else Parallel
  else
    let t = numerator_t /. denominator
    and u = numerator_u /. denominator in
    if t >= -.epsilon && t <= 1. +. epsilon
       && u >= -.epsilon && u <= 1. +. epsilon
    then
      Point {
        point = point_at left t;
        along_self = t;
        along_other = u;
      }
    else No_intersection
