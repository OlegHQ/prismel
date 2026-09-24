open Prismel

type t = { a : Vec3.t; b : Vec3.t }

let make a b = { a; b }
let direction segment = Vec3.sub segment.b segment.a
let length_sq segment = Vec3.length_sq (direction segment)
let length segment = sqrt (length_sq segment)
let midpoint segment = Vec3.lerp segment.a segment.b 0.5
let point_at segment amount = Vec3.lerp segment.a segment.b amount

let closest_parameter segment point =
  let edge = direction segment in
  let denominator = Vec3.length_sq edge in
  if denominator <= 1e-18 then 0.
  else max 0. (min 1. (Vec3.dot (Vec3.sub point segment.a) edge /. denominator))

let closest_point segment point = point_at segment (closest_parameter segment point)
let distance segment point = Vec3.distance point (closest_point segment point)
let bounds segment = Bounds3.make ~min:segment.a ~max:segment.b
let transform matrix segment =
  make (Mat4.transform_point matrix segment.a)
    (Mat4.transform_point matrix segment.b)
let reflect ~plane segment =
  make (Plane3.reflect_point plane segment.a) (Plane3.reflect_point plane segment.b)

let closest_between left right =
  (* Ericson, Real-Time Collision Detection, closest points of two segments. *)
  let d1 = direction left and d2 = direction right
  and offset = Vec3.sub left.a right.a in
  let a = Vec3.dot d1 d1 and e = Vec3.dot d2 d2
  and f = Vec3.dot d2 offset in
  let s, t =
    if a <= 1e-18 && e <= 1e-18 then 0., 0.
    else if a <= 1e-18 then 0., max 0. (min 1. (f /. e))
    else
      let c = Vec3.dot d1 offset in
      if e <= 1e-18 then max 0. (min 1. (-.c /. a)), 0.
      else
        let b = Vec3.dot d1 d2 in
        let denominator = a *. e -. b *. b in
        let s = if denominator <> 0. then
            max 0. (min 1. ((b *. f -. c *. e) /. denominator))
          else 0. in
        let t = (b *. s +. f) /. e in
        if t < 0. then max 0. (min 1. (-.c /. a)), 0.
        else if t > 1. then max 0. (min 1. ((b -. c) /. a)), 1.
        else s, t
  in
  point_at left s, point_at right t
