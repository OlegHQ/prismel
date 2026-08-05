open Prismel

type t = {
  center : Vec2.t;
  radius : float;
}

let make ~center ~radius =
  if not (Float.is_finite radius) || radius < 0. then
    invalid_arg "Circle2.make: radius must be finite and non-negative";
  { center; radius }

let area circle = Float.pi *. circle.radius *. circle.radius
let circumference circle = 2. *. Float.pi *. circle.radius
let contains circle point = Vec2.distance circle.center point <= circle.radius

let bounds circle =
  let radius = Vec2.create circle.radius circle.radius in
  Bounds2.make
    ~min:(Vec2.sub circle.center radius)
    ~max:(Vec2.add circle.center radius)

let point_at circle amount =
  let angle = amount *. 2. *. Float.pi in
  Vec2.add circle.center
    (Vec2.create (circle.radius *. cos angle) (circle.radius *. sin angle))

let sample ?(include_last = false) resolution circle =
  if resolution < 3 then
    invalid_arg "Circle2.sample: resolution must be at least 3";
  let count = if include_last then resolution + 1 else resolution in
  List.init count (fun index ->
    point_at circle (float_of_int index /. float_of_int resolution))

let transform affine circle =
  let center = Affine2.apply affine circle.center in
  let x =
    Affine2.apply_direction affine (Vec2.create circle.radius 0.)
    |> Vec2.length
  and y =
    Affine2.apply_direction affine (Vec2.create 0. circle.radius)
    |> Vec2.length
  in
  if abs_float (x -. y) > 1e-9 *. Float.max 1. (Float.max x y) then
    Error "Circle2.transform: non-uniform transform produces an ellipse"
  else Ok (make ~center ~radius:((x +. y) /. 2.))

let intersections ?(epsilon = 1e-9) left right =
  let delta = Vec2.sub right.center left.center in
  let distance = Vec2.length delta in
  if distance <= epsilon then []
  else if distance > left.radius +. right.radius +. epsilon
          || distance
             < abs_float (left.radius -. right.radius) -. epsilon
  then []
  else
    let along =
      ((left.radius *. left.radius) -. (right.radius *. right.radius)
       +. (distance *. distance))
      /. (2. *. distance)
    in
    let height_sq =
      Float.max 0. ((left.radius *. left.radius) -. (along *. along))
    in
    let direction = Vec2.scale delta (1. /. distance) in
    let base = Vec2.add left.center (Vec2.scale direction along) in
    if height_sq <= epsilon *. epsilon then [base]
    else
      let height = sqrt height_sq in
      let perpendicular =
        Vec2.create (-.direction.y) direction.x |> Fun.flip Vec2.scale height
      in
      [Vec2.add base perpendicular; Vec2.sub base perpendicular]

let tangent_points ?(epsilon = 1e-9) circle point =
  let delta = Vec2.sub point circle.center in
  let distance_sq = Vec2.length_sq delta
  and radius_sq = circle.radius *. circle.radius in
  if distance_sq < radius_sq -. epsilon then []
  else if abs_float (distance_sq -. radius_sq) <= epsilon then [point]
  else
    let base =
      Vec2.add circle.center (Vec2.scale delta (radius_sq /. distance_sq))
    in
    let height =
      circle.radius *. sqrt (distance_sq -. radius_sq) /. distance_sq
    in
    let offset = Vec2.scale (Vec2.create (-.delta.y) delta.x) height in
    [Vec2.add base offset; Vec2.sub base offset]

let through_three_points ?(epsilon = 1e-9) a b c =
  let ax = a.Vec2.x and ay = a.y
  and bx = b.Vec2.x and by = b.y
  and cx = c.Vec2.x and cy = c.y in
  let denominator =
    2. *. ((ax *. (by -. cy)) +. (bx *. (cy -. ay))
           +. (cx *. (ay -. by)))
  in
  if abs_float denominator <= epsilon then None
  else
    let aa = (ax *. ax) +. (ay *. ay)
    and bb = (bx *. bx) +. (by *. by)
    and cc = (cx *. cx) +. (cy *. cy) in
    let center =
      Vec2.create
        (((aa *. (by -. cy)) +. (bb *. (cy -. ay))
          +. (cc *. (ay -. by))) /. denominator)
        (((aa *. (cx -. bx)) +. (bb *. (ax -. cx))
          +. (cc *. (bx -. ax))) /. denominator)
    in
    Some (make ~center ~radius:(Vec2.distance center a))
