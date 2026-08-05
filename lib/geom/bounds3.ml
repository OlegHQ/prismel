open Prismel

type t = { min : Vec3.t; max : Vec3.t }

let make ~(min : Vec3.t) ~(max : Vec3.t) =
  {
    min = Vec3.create (Float.min min.x max.x) (Float.min min.y max.y)
        (Float.min min.z max.z);
    max = Vec3.create (Float.max min.x max.x) (Float.max min.y max.y)
        (Float.max min.z max.z);
  }

let empty =
  {
    min = Vec3.create infinity infinity infinity;
    max = Vec3.create neg_infinity neg_infinity neg_infinity;
  }

let include_point (point : Vec3.t) bounds =
  {
    min = Vec3.create
        (Float.min bounds.min.x point.x)
        (Float.min bounds.min.y point.y)
        (Float.min bounds.min.z point.z);
    max = Vec3.create
        (Float.max bounds.max.x point.x)
        (Float.max bounds.max.y point.y)
        (Float.max bounds.max.z point.z);
  }

let of_points = function
  | [] -> None
  | first :: rest ->
      Some
        (List.fold_left (Fun.flip include_point)
           (make ~min:first ~max:first) rest)

let union left right =
  {
    min = Vec3.create
        (Float.min left.min.x right.min.x)
        (Float.min left.min.y right.min.y)
        (Float.min left.min.z right.min.z);
    max = Vec3.create
        (Float.max left.max.x right.max.x)
        (Float.max left.max.y right.max.y)
        (Float.max left.max.z right.max.z);
  }

let expand amount bounds =
  if not (Float.is_finite amount) then
    invalid_arg "Bounds3.expand: amount must be finite";
  let delta = Vec3.create amount amount amount in
  make ~min:(Vec3.sub bounds.min delta) ~max:(Vec3.add bounds.max delta)

let width bounds = Float.max 0. (bounds.max.x -. bounds.min.x)
let height bounds = Float.max 0. (bounds.max.y -. bounds.min.y)
let depth bounds = Float.max 0. (bounds.max.z -. bounds.min.z)
let size bounds = Vec3.create (width bounds) (height bounds) (depth bounds)
let center bounds = Vec3.lerp bounds.min bounds.max 0.5
let volume bounds = width bounds *. height bounds *. depth bounds

let surface_area bounds =
  let x = width bounds and y = height bounds and z = depth bounds in
  2. *. ((x *. y) +. (y *. z) +. (z *. x))

let contains bounds (point : Vec3.t) =
  point.x >= bounds.min.x && point.x <= bounds.max.x
  && point.y >= bounds.min.y && point.y <= bounds.max.y
  && point.z >= bounds.min.z && point.z <= bounds.max.z

let intersects left right =
  left.min.x <= right.max.x && right.min.x <= left.max.x
  && left.min.y <= right.max.y && right.min.y <= left.max.y
  && left.min.z <= right.max.z && right.min.z <= left.max.z

let clamp value minimum maximum = Float.max minimum (Float.min maximum value)

let closest_point bounds (point : Vec3.t) =
  Vec3.create
    (clamp point.x bounds.min.x bounds.max.x)
    (clamp point.y bounds.min.y bounds.max.y)
    (clamp point.z bounds.min.z bounds.max.z)

let distance_sq bounds point =
  let axis_distance value minimum maximum =
    if value < minimum then minimum -. value
    else if value > maximum then value -. maximum
    else 0. in
  let dx = axis_distance point.Vec3.x bounds.min.x bounds.max.x
  and dy = axis_distance point.y bounds.min.y bounds.max.y
  and dz = axis_distance point.z bounds.min.z bounds.max.z in
  (dx *. dx) +. (dy *. dy) +. (dz *. dz)

let corners bounds =
  let x0 = bounds.min.x and y0 = bounds.min.y and z0 = bounds.min.z
  and x1 = bounds.max.x and y1 = bounds.max.y and z1 = bounds.max.z in
  [
    Vec3.create x0 y0 z0; Vec3.create x1 y0 z0;
    Vec3.create x1 y1 z0; Vec3.create x0 y1 z0;
    Vec3.create x0 y0 z1; Vec3.create x1 y0 z1;
    Vec3.create x1 y1 z1; Vec3.create x0 y1 z1;
  ]

let map_normalized bounds (point : Vec3.t) =
  let x = width bounds and y = height bounds and z = depth bounds in
  Vec3.create
    (if x <= 1e-15 then 0. else (point.x -. bounds.min.x) /. x)
    (if y <= 1e-15 then 0. else (point.y -. bounds.min.y) /. y)
    (if z <= 1e-15 then 0. else (point.z -. bounds.min.z) /. z)

let unmap_normalized bounds (point : Vec3.t) =
  Vec3.create
    (bounds.min.x +. (point.x *. width bounds))
    (bounds.min.y +. (point.y *. height bounds))
    (bounds.min.z +. (point.z *. depth bounds))
