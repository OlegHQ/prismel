open Prismel

type t = { a : Vec2.t; b : Vec2.t; c : Vec2.t }
type vertex = A | B | C

let make a b c = { a; b; c }

let equilateral ?(rotation = -.Float.pi /. 2.) ~center ~radius () =
  if not (Float.is_finite radius) || radius <= 0. then
    invalid_arg "Triangle2.equilateral: radius must be finite and positive";
  let point index =
    let angle = rotation +. (float_of_int index *. 2. *. Float.pi /. 3.) in
    Vec2.add center (Vec2.create (radius *. cos angle) (radius *. sin angle))
  in
  make (point 0) (point 1) (point 2)

let equilateral_on a b =
  let direction = Vec2.sub b a in
  let midpoint = Vec2.scale (Vec2.add a b) 0.5 in
  let normal = Vec2.normalize (Vec2.create (-.direction.y) direction.x) in
  make a b
    (Vec2.add midpoint
       (Vec2.scale normal (Vec2.length direction *. sqrt 3. /. 2.)))

let signed_area triangle =
  (((triangle.b.x -. triangle.a.x) *. (triangle.c.y -. triangle.a.y))
   -. ((triangle.b.y -. triangle.a.y) *. (triangle.c.x -. triangle.a.x))) /. 2.

let area triangle = abs_float (signed_area triangle)
let centroid triangle = Vec2.scale (Vec2.add triangle.a (Vec2.add triangle.b triangle.c)) (1. /. 3.)
let bounds triangle = Bounds2.of_points [triangle.a; triangle.b; triangle.c] |> Option.get

let barycentric ?(epsilon = 1e-12) triangle point =
  let v0 = Vec2.sub triangle.b triangle.a
  and v1 = Vec2.sub triangle.c triangle.a
  and v2 = Vec2.sub point triangle.a in
  let d00 = Vec2.dot v0 v0 and d01 = Vec2.dot v0 v1
  and d11 = Vec2.dot v1 v1 and d20 = Vec2.dot v2 v0
  and d21 = Vec2.dot v2 v1 in
  let denominator = (d00 *. d11) -. (d01 *. d01) in
  if abs_float denominator <= epsilon then None
  else
    let v = ((d11 *. d20) -. (d01 *. d21)) /. denominator in
    let w = ((d00 *. d21) -. (d01 *. d20)) /. denominator in
    Some (1. -. v -. w, v, w)

let contains ?(epsilon = 1e-9) triangle point =
  match barycentric ~epsilon triangle point with
  | None -> false
  | Some (u, v, w) -> u >= -.epsilon && v >= -.epsilon && w >= -.epsilon

let closest_point triangle point =
  if contains triangle point then point
  else
    let edges = [Segment2.make triangle.a triangle.b; Segment2.make triangle.b triangle.c; Segment2.make triangle.c triangle.a] in
    match edges with
    | [] -> assert false
    | first :: rest ->
        List.fold_left
          (fun closest edge ->
            let candidate = Segment2.closest_point edge point in
            if Vec2.distance candidate point < Vec2.distance closest point
            then candidate else closest)
          (Segment2.closest_point first point) rest

let altitude vertex triangle =
  let opposite, apex = match vertex with
    | A -> Segment2.make triangle.b triangle.c, triangle.a
    | B -> Segment2.make triangle.a triangle.c, triangle.b
    | C -> Segment2.make triangle.a triangle.b, triangle.c
  in
  Segment2.make (Segment2.closest_point opposite apex) apex

let circumcircle ?epsilon triangle = Circle2.through_three_points ?epsilon triangle.a triangle.b triangle.c
let transform affine triangle = make (Affine2.apply affine triangle.a) (Affine2.apply affine triangle.b) (Affine2.apply affine triangle.c)
let to_polygon triangle = Polygon2.create_exn [triangle.a; triangle.b; triangle.c]
