open Prismel

type t = {
  min : Vec2.t;
  max : Vec2.t;
}

let make ~(min : Vec2.t) ~(max : Vec2.t) =
  {
    min = Vec2.create (Float.min min.Vec2.x max.x) (Float.min min.y max.y);
    max = Vec2.create (Float.max min.x max.x) (Float.max min.y max.y);
  }

let empty =
  {
    min = Vec2.create infinity infinity;
    max = Vec2.create neg_infinity neg_infinity;
  }

let include_point (point : Vec2.t) bounds =
  {
    min =
      Vec2.create
        (Float.min bounds.min.x point.Vec2.x)
        (Float.min bounds.min.y point.y);
    max =
      Vec2.create
        (Float.max bounds.max.x point.x)
        (Float.max bounds.max.y point.y);
  }

let of_points = function
  | [] -> None
  | first :: rest ->
      Some
        (List.fold_left
           (Fun.flip include_point)
           (make ~min:first ~max:first)
           rest)

let width bounds = Float.max 0. (bounds.max.x -. bounds.min.x)
let height bounds = Float.max 0. (bounds.max.y -. bounds.min.y)
let size bounds = Vec2.create (width bounds) (height bounds)
let center bounds = Vec2.lerp bounds.min bounds.max 0.5
let area bounds = width bounds *. height bounds

let contains bounds (point : Vec2.t) =
  point.Vec2.x >= bounds.min.x && point.x <= bounds.max.x
  && point.y >= bounds.min.y && point.y <= bounds.max.y

let intersects left right =
  left.min.x <= right.max.x && right.min.x <= left.max.x
  && left.min.y <= right.max.y && right.min.y <= left.max.y

let closest_point bounds (point : Vec2.t) =
  Vec2.create
    (Float.max bounds.min.x (Float.min bounds.max.x point.x))
    (Float.max bounds.min.y (Float.min bounds.max.y point.y))

let distance_sq bounds point =
  let dx =
    if point.Vec2.x < bounds.min.x then bounds.min.x -. point.x
    else if point.x > bounds.max.x then point.x -. bounds.max.x
    else 0.
  and dy =
    if point.y < bounds.min.y then bounds.min.y -. point.y
    else if point.y > bounds.max.y then point.y -. bounds.max.y
    else 0. in
  (dx *. dx) +. (dy *. dy)

let union left right =
  {
    min =
      Vec2.create
        (Float.min left.min.x right.min.x)
        (Float.min left.min.y right.min.y);
    max =
      Vec2.create
        (Float.max left.max.x right.max.x)
        (Float.max left.max.y right.max.y);
  }

let expand amount bounds =
  if not (Float.is_finite amount) then
    invalid_arg "Bounds2.expand: amount must be finite";
  make
    ~min:(Vec2.create (bounds.min.x -. amount) (bounds.min.y -. amount))
    ~max:(Vec2.create (bounds.max.x +. amount) (bounds.max.y +. amount))

let corners bounds =
  [
    bounds.min;
    Vec2.create bounds.max.x bounds.min.y;
    bounds.max;
    Vec2.create bounds.min.x bounds.max.y;
  ]

let map_normalized bounds (point : Vec2.t) =
  let width = width bounds and height = height bounds in
  Vec2.create
    (if width <= 1e-15 then 0. else (point.Vec2.x -. bounds.min.x) /. width)
    (if height <= 1e-15 then 0. else (point.y -. bounds.min.y) /. height)

let unmap_normalized bounds (point : Vec2.t) =
  Vec2.create
    (bounds.min.x +. (point.Vec2.x *. width bounds))
    (bounds.min.y +. (point.y *. height bounds))
