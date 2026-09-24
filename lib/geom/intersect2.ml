open Prismel

type hit = { point : Vec2.t; distance : float; normal : Vec2.t }

let cross left right =
  (left.Vec2.x *. right.Vec2.y) -. (left.y *. right.x)

let validate_epsilon epsilon =
  if not (Float.is_finite epsilon) || epsilon < 0. then
    invalid_arg "Intersect2: epsilon must be finite and non-negative"

let opposing_normal direction normal =
  if Vec2.dot direction normal > 0. then Vec2.neg normal else normal

let ray_segment ?(epsilon = 1e-9) (ray : Ray2.t) (segment : Segment2.t) =
  validate_epsilon epsilon;
  let edge = Vec2.sub segment.b segment.a in
  let denominator = cross ray.direction edge in
  if abs_float denominator <= epsilon then None
  else
    let delta = Vec2.sub segment.a ray.origin in
    let distance = cross delta edge /. denominator
    and along = cross delta ray.direction /. denominator in
    if distance < -.epsilon || along < -.epsilon || along > 1. +. epsilon then None
    else
      let point = Ray2.point_at ray (Float.max 0. distance) in
      let normal = Vec2.create (-.edge.y) edge.x |> Vec2.normalize
        |> opposing_normal ray.direction in
      Some { point; distance = Float.max 0. distance; normal }

let ray_circle ?(epsilon = 1e-9) (ray : Ray2.t) (circle : Circle2.t) =
  validate_epsilon epsilon;
  let offset = Vec2.sub ray.origin circle.center in
  let b = Vec2.dot offset ray.direction in
  let c = Vec2.length_sq offset -. (circle.radius *. circle.radius) in
  let discriminant = (b *. b) -. c in
  if discriminant < -.epsilon then []
  else
    let root = sqrt (Float.max 0. discriminant) in
    let distances =
      if root <= epsilon then [-.b]
      else [-.b -. root; -.b +. root]
    in
    distances
    |> List.filter (fun distance -> distance >= -.epsilon)
    |> List.map (fun distance ->
      let distance = Float.max 0. distance in
      let point = Ray2.point_at ray distance in
      let normal = Vec2.sub point circle.center |> Vec2.normalize
        |> opposing_normal ray.direction in
      { point; distance; normal })

let ray_bounds ?(epsilon = 1e-9) (ray : Ray2.t) (bounds : Bounds2.t) =
  validate_epsilon epsilon;
  let axis origin direction minimum maximum negative_normal positive_normal =
    if abs_float direction <= epsilon then
      if origin < minimum || origin > maximum then None
      else Some (neg_infinity, infinity, Vec2.zero, Vec2.zero)
    else
      let first = (minimum -. origin) /. direction
      and second = (maximum -. origin) /. direction in
      if first <= second then Some (first, second, negative_normal, positive_normal)
      else Some (second, first, positive_normal, negative_normal)
  in
  match
    axis ray.origin.x ray.direction.x bounds.min.x bounds.max.x
      (Vec2.create (-1.) 0.) (Vec2.create 1. 0.),
    axis ray.origin.y ray.direction.y bounds.min.y bounds.max.y
      (Vec2.create 0. (-1.)) (Vec2.create 0. 1.)
  with
  | Some (x0, x1, xn0, xn1), Some (y0, y1, yn0, yn1) ->
      let entry, entry_normal = if x0 > y0 then x0, xn0 else y0, yn0 in
      let exit, exit_normal = if x1 < y1 then x1, xn1 else y1, yn1 in
      if entry > exit +. epsilon || exit < -.epsilon then None
      else
        let distance, normal =
          if entry >= 0. then entry, entry_normal else exit, exit_normal
        in
        Some { point = Ray2.point_at ray distance; distance; normal }
  | _ -> None

let deduplicate_hits epsilon hits =
  List.fold_left
    (fun unique hit ->
      if List.exists (fun other -> Vec2.distance hit.point other.point <= epsilon) unique
      then unique else hit :: unique)
    [] hits |> List.rev

let ray_polygon ?(epsilon = 1e-9) ray polygon =
  Polygon2.edges polygon
  |> List.filter_map (ray_segment ~epsilon ray)
  |> List.sort (fun left right -> Float.compare left.distance right.distance)
  |> deduplicate_hits epsilon

let segment_circle ?(epsilon = 1e-9) (segment : Segment2.t) (circle : Circle2.t) =
  validate_epsilon epsilon;
  let direction = Segment2.direction segment in
  let offset = Vec2.sub segment.a circle.center in
  let a = Vec2.dot direction direction
  and b = 2. *. Vec2.dot offset direction
  and c = Vec2.dot offset offset -. (circle.radius *. circle.radius) in
  if a <= epsilon *. epsilon then []
  else
    let discriminant = (b *. b) -. (4. *. a *. c) in
    if discriminant < -.epsilon then []
    else
      let root = sqrt (Float.max 0. discriminant) in
      let values =
        if root <= epsilon then [(-.b) /. (2. *. a)]
        else [(-.b -. root) /. (2. *. a); (-.b +. root) /. (2. *. a)]
      in
      values |> List.filter (fun t -> t >= -.epsilon && t <= 1. +. epsilon)
      |> List.map (Segment2.point_at segment)

let segment_polygon ?(epsilon = 1e-9) segment polygon =
  Polygon2.edges polygon
  |> List.filter_map (fun edge ->
    match Segment2.intersect ~epsilon segment edge with
    | Segment2.Point { point; _ } -> Some point
    | _ -> None)
  |> List.fold_left (fun unique point ->
    if List.exists (fun other -> Vec2.distance point other <= epsilon) unique
    then unique else point :: unique) []
  |> List.rev

let circle_bounds (circle : Circle2.t) (bounds : Bounds2.t) =
  let x = Float.max bounds.min.x (Float.min bounds.max.x circle.center.x)
  and y = Float.max bounds.min.y (Float.min bounds.max.y circle.center.y) in
  Vec2.distance circle.center (Vec2.create x y) <= circle.radius

let circle_polygon ?(epsilon = 1e-9) (circle : Circle2.t) polygon =
  Polygon2.contains ~epsilon polygon circle.center
  || List.exists (fun edge -> Segment2.distance edge circle.center <= circle.radius +. epsilon) (Polygon2.edges polygon)

let polygon_polygon ?(epsilon = 1e-9) left right =
  let edge_hit =
    List.exists (fun a ->
      List.exists (fun b ->
        match Segment2.intersect ~epsilon a b with
        | Segment2.No_intersection | Segment2.Parallel -> false
        | Segment2.Coincident | Segment2.Point _ -> true)
        (Polygon2.edges right))
      (Polygon2.edges left)
  in
  edge_hit
  || (match Polygon2.vertices left with first :: _ -> Polygon2.contains ~epsilon right first | [] -> false)
  || (match Polygon2.vertices right with first :: _ -> Polygon2.contains ~epsilon left first | [] -> false)
