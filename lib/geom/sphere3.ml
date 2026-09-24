open Prismel

type t = { center : Vec3.t; radius : float }

let make ~center ~radius =
  if not (Float.is_finite radius) || radius < 0. then
    invalid_arg "Sphere3.make: radius must be finite and non-negative";
  { center; radius }

let surface_area sphere = 4. *. Float.pi *. sphere.radius *. sphere.radius
let volume sphere = 4. /. 3. *. Float.pi *. sphere.radius ** 3.
let contains sphere point = Vec3.distance sphere.center point <= sphere.radius

let bounds sphere =
  let radius = Vec3.create sphere.radius sphere.radius sphere.radius in
  Bounds3.make ~min:(Vec3.sub sphere.center radius)
    ~max:(Vec3.add sphere.center radius)

let signed_distance sphere point = Vec3.distance sphere.center point -. sphere.radius

let closest_point sphere point =
  let delta = Vec3.sub point sphere.center in
  let length = Vec3.length delta in
  if length <= 1e-15 then Vec3.add sphere.center (Vec3.create sphere.radius 0. 0.)
  else Vec3.add sphere.center (Vec3.scale delta (sphere.radius /. length))

let transform matrix sphere =
  let center = Mat4.transform_point matrix sphere.center in
  let scale direction =
    Mat4.transform_direction matrix direction |> Vec3.length
  in
  let x = scale (Vec3.create sphere.radius 0. 0.)
  and y = scale (Vec3.create 0. sphere.radius 0.)
  and z = scale (Vec3.create 0. 0. sphere.radius) in
  let maximum = Float.max x (Float.max y z) in
  let minimum = Float.min x (Float.min y z) in
  if maximum -. minimum > 1e-9 *. Float.max 1. maximum then
    Error "Sphere3.transform: non-uniform transform produces an ellipsoid"
  else Ok (make ~center ~radius:((x +. y +. z) /. 3.))
