open Prismel

type t = { vertices : Vec2.t array }
type triangle = Vec2.t * Vec2.t * Vec2.t

let equal_point left right =
  left.Vec2.x = right.Vec2.x && left.y = right.y

let remove_consecutive_duplicates points =
  List.fold_left
    (fun acc point ->
      match acc with
      | previous :: _ when equal_point previous point -> acc
      | _ -> point :: acc)
    [] points
  |> List.rev

let normalize_points points =
  let points = remove_consecutive_duplicates points in
  match points with
  | [] -> []
  | first :: _ ->
      (match List.rev points with
       | last :: reversed when equal_point first last -> List.rev reversed
       | _ -> points)

let create points =
  let points = normalize_points points in
  if List.length points < 3 then
    Error "Polygon2.create: at least three distinct vertices are required"
  else Ok { vertices = Array.of_list points }

let create_exn points =
  match create points with
  | Ok polygon -> polygon
  | Error message -> invalid_arg message

let vertices polygon = Array.to_list polygon.vertices
let vertex_count polygon = Array.length polygon.vertices

let signed_area polygon =
  let count = vertex_count polygon in
  let sum = ref 0. in
  for index = 0 to count - 1 do
    let current = polygon.vertices.(index)
    and next = polygon.vertices.((index + 1) mod count) in
    sum :=
      !sum
      +. ((current.Vec2.x *. next.y) -. (current.y *. next.x))
  done;
  !sum /. 2.

let area polygon = abs_float (signed_area polygon)
let clockwise polygon = signed_area polygon < 0.

let edges polygon =
  List.init (vertex_count polygon) (fun index ->
    Segment2.make polygon.vertices.(index)
      polygon.vertices.((index + 1) mod vertex_count polygon))

let centroid polygon =
  let double_area = signed_area polygon *. 2. in
  if abs_float double_area <= 1e-15 then
    let sum =
      Array.fold_left Vec2.add Vec2.zero polygon.vertices
    in
    Vec2.scale sum (1. /. float_of_int (vertex_count polygon))
  else
    let x = ref 0. and y = ref 0. in
    for index = 0 to vertex_count polygon - 1 do
      let current = polygon.vertices.(index)
      and next =
        polygon.vertices.((index + 1) mod vertex_count polygon)
      in
      let cross =
        (current.Vec2.x *. next.y) -. (next.x *. current.y)
      in
      x := !x +. ((current.x +. next.x) *. cross);
      y := !y +. ((current.y +. next.y) *. cross)
    done;
    Vec2.create (!x /. (3. *. double_area)) (!y /. (3. *. double_area))

let perimeter polygon =
  List.fold_left
    (fun total edge -> total +. Segment2.length edge)
    0. (edges polygon)

let bounds polygon =
  match Bounds2.of_points (vertices polygon) with
  | Some bounds -> bounds
  | None -> assert false

let contains ?(epsilon = 1e-9) polygon point =
  if
    List.exists
      (fun edge -> Segment2.distance edge point <= epsilon)
      (edges polygon)
  then true
  else
    let inside = ref false in
    let count = vertex_count polygon in
    let previous = ref polygon.vertices.(count - 1) in
    for index = 0 to count - 1 do
      let current = polygon.vertices.(index) in
      if
        ((current.y > point.Vec2.y) <> ((!previous).y > point.y))
        &&
        point.x
        < (((!previous).x -. current.x)
           *. (point.y -. current.y)
           /. ((!previous).y -. current.y))
          +. current.x
      then inside := not !inside;
      previous := current
    done;
    !inside

let closest_point polygon point =
  match edges polygon with
  | [] -> assert false
  | first :: rest ->
      let closest = ref (Segment2.closest_point first point)
      and distance = ref (Segment2.distance first point) in
      List.iter
        (fun edge ->
          let candidate = Segment2.closest_point edge point in
          let candidate_distance = Vec2.distance candidate point in
          if candidate_distance < !distance then begin
            closest := candidate;
            distance := candidate_distance
          end)
        rest;
      !closest

let positive_mod value modulus =
  let value = mod_float value modulus in
  if value < 0. then value +. modulus else value

let point_at polygon amount =
  let total = perimeter polygon in
  if total <= 1e-15 then polygon.vertices.(0)
  else
    let target = positive_mod amount 1. *. total in
    let rec locate remaining = function
      | [] -> polygon.vertices.(0)
      | edge :: rest ->
          let length = Segment2.length edge in
          if remaining <= length || rest = [] then
            Segment2.point_at edge
              (if length <= 1e-15 then 0. else remaining /. length)
          else locate (remaining -. length) rest
    in
    locate target (edges polygon)

let sample_uniform ?(include_last = false) ~distance polygon =
  if not (Float.is_finite distance) || distance <= 0. then
    invalid_arg
      "Polygon2.sample_uniform: distance must be finite and positive";
  let length = perimeter polygon in
  if length <= 1e-15 then [polygon.vertices.(0)]
  else
    let segments = max 1 (int_of_float (Float.ceil (length /. distance))) in
    let count = if include_last then segments + 1 else segments in
    List.init count (fun index ->
      point_at polygon (float_of_int index /. float_of_int segments))

let map transform polygon =
  { vertices = Array.map transform polygon.vertices }

let transform affine = map (Affine2.apply affine)
let translate amount = transform (Affine2.translation amount)

let around center local_transform polygon =
  let affine =
    Affine2.compose (Affine2.translation center)
      (Affine2.compose local_transform
         (Affine2.translation (Vec2.neg center)))
  in
  transform affine polygon

let rotate ?center angle polygon =
  let center = Option.value center ~default:(centroid polygon) in
  around center (Affine2.rotation angle) polygon

let scale ?center amount polygon =
  let center = Option.value center ~default:(centroid polygon) in
  around center (Affine2.scaling amount) polygon

let reverse polygon =
  { vertices = Array.of_list (List.rev (vertices polygon)) }

let smooth ?iterations ?ratio polygon =
  Curve2.create_exn ~closed:true (vertices polygon)
  |> Curve2.chaikin ?iterations ?ratio

let cross (origin : Vec2.t) (a : Vec2.t) (b : Vec2.t) =
  ((a.Vec2.x -. origin.Vec2.x) *. (b.y -. origin.y))
  -. ((a.y -. origin.y) *. (b.x -. origin.x))

let convex_hull points =
  let points =
    List.sort_uniq
      (fun left right ->
        match Float.compare left.Vec2.x right.Vec2.x with
        | 0 -> Float.compare left.y right.y
        | order -> order)
      points
  in
  if List.length points < 3 then None
  else
    let half points =
      List.fold_left
        (fun hull point ->
          let rec remove = function
            | b :: a :: rest when cross a b point <= 0. ->
                remove (a :: rest)
            | hull -> hull
          in
          point :: remove hull)
        [] points
      |> List.rev
    in
    let lower = half points and upper = half (List.rev points) in
    let drop_last values =
      match List.rev values with
      | _ :: rest -> List.rev rest
      | [] -> []
    in
    create (drop_last lower @ drop_last upper) |> Result.to_option

let line_intersection p1 p2 q1 q2 =
  let r = Vec2.sub p2 p1 and s = Vec2.sub q2 q1 in
  let denominator =
    (r.Vec2.x *. s.Vec2.y) -. (r.y *. s.x)
  in
  if abs_float denominator <= 1e-15 then None
  else
    let delta = Vec2.sub q1 p1 in
    let amount =
      ((delta.Vec2.x *. s.y) -. (delta.y *. s.x)) /. denominator
    in
    Some (Vec2.add p1 (Vec2.scale r amount))

let clip_convex ~subject ~clip =
  let clip_vertices = clip.vertices in
  let clip_sign = if signed_area clip >= 0. then 1. else -1. in
  let inside a b point = clip_sign *. cross a b point >= -.1e-9 in
  let intersect a b p q =
    line_intersection p q a b |> Option.value ~default:q
  in
  let output = ref (vertices subject) in
  for index = 0 to Array.length clip_vertices - 1 do
    let a = clip_vertices.(index)
    and b = clip_vertices.((index + 1) mod Array.length clip_vertices) in
    let input = !output in
    output := [];
    (match List.rev input with
     | [] -> ()
     | previous :: _ ->
         let previous = ref previous in
         List.iter
           (fun current ->
             let current_inside = inside a b current
             and previous_inside = inside a b !previous in
             if current_inside then begin
               if not previous_inside then
                 output := intersect a b !previous current :: !output;
               output := current :: !output
             end
             else if previous_inside then
               output := intersect a b !previous current :: !output;
             previous := current)
           input;
         output := List.rev !output)
  done;
  create !output |> Result.to_option

let inset ~distance polygon =
  if not (Float.is_finite distance) then
    invalid_arg "Polygon2.inset: distance must be finite";
  let orientation = if signed_area polygon >= 0. then 1. else -1. in
  let offset_edge edge =
    let direction = Segment2.direction edge |> Vec2.normalize in
    let inward =
      Vec2.create
        (-.direction.y *. orientation)
        (direction.x *. orientation)
      |> Fun.flip Vec2.scale distance
    in
    Vec2.add edge.a inward, Vec2.add edge.b inward
  in
  let shifted = Array.of_list (List.map offset_edge (edges polygon)) in
  let result =
    Array.init (vertex_count polygon) (fun index ->
      let previous =
        shifted.((index + vertex_count polygon - 1) mod vertex_count polygon)
      and current = shifted.(index) in
      match
        line_intersection (fst previous) (snd previous)
          (fst current) (snd current)
      with
      | Some point -> point
      | None -> fst current)
    |> Array.to_list
  in
  match create result with
  | Error _ as error -> error
  | Ok result when area result <= 1e-12 ->
      Error "Polygon2.inset: distance collapsed the polygon"
  | Ok result -> Ok result

let point_in_triangle point a b c =
  let ab = cross a b point
  and bc = cross b c point
  and ca = cross c a point in
  let negative = ab < -.1e-10 || bc < -.1e-10 || ca < -.1e-10
  and positive = ab > 1e-10 || bc > 1e-10 || ca > 1e-10 in
  not (negative && positive)

let triangulate polygon =
  let count = vertex_count polygon in
  let indices =
    if signed_area polygon >= 0. then List.init count Fun.id
    else List.init count (fun index -> count - 1 - index)
  in
  let rec ears remaining budget triangles =
    match remaining with
    | [_; _] -> Ok (List.rev triangles)
    | _ when budget <= 0 ->
        Error
          "Polygon2.triangulate: polygon is self-intersecting or degenerate"
    | _ ->
        let array = Array.of_list remaining in
        let length = Array.length array in
        let rec find index =
          if index >= length then None
          else
            let previous = array.((index + length - 1) mod length)
            and current = array.(index)
            and next = array.((index + 1) mod length) in
            let a = polygon.vertices.(previous)
            and b = polygon.vertices.(current)
            and c = polygon.vertices.(next) in
            let convex = cross a b c > 1e-12 in
            let contains_other =
              Array.exists
                (fun candidate ->
                  candidate <> previous && candidate <> current
                  && candidate <> next
                  && point_in_triangle polygon.vertices.(candidate) a b c)
                array
            in
            if convex && not contains_other then
              Some (index, (a, b, c))
            else find (index + 1)
        in
        (match find 0 with
         | None -> ears remaining (budget - 1) triangles
         | Some (index, triangle) ->
             let remaining =
               List.mapi (fun position value -> position, value) remaining
               |> List.filter_map (fun (position, value) ->
                 if position = index then None else Some value)
             in
             ears remaining (count * count) (triangle :: triangles))
  in
  ears indices (count * count) []

let validate_radial name ~radius ~sides =
  if not (Float.is_finite radius) || radius <= 0. then
    invalid_arg ("Polygon2." ^ name ^ ": radius must be finite and positive");
  if sides < 3 then
    invalid_arg ("Polygon2." ^ name ^ ": at least three sides are required")

let regular ?(rotation = -.Float.pi /. 2.) ~center ~radius ~sides () =
  validate_radial "regular" ~radius ~sides;
  List.init sides (fun index ->
    let angle =
      rotation +. (float_of_int index /. float_of_int sides *. 2. *. Float.pi)
    in
    Vec2.add center (Vec2.create (radius *. cos angle) (radius *. sin angle)))
  |> create_exn

let star ?(rotation = -.Float.pi /. 2.) ~center ~inner_radius
    ~outer_radius ~points () =
  validate_radial "star" ~radius:outer_radius ~sides:points;
  if not (Float.is_finite inner_radius)
     || inner_radius <= 0. || inner_radius >= outer_radius
  then invalid_arg
      "Polygon2.star: inner radius must be positive and smaller than outer";
  List.init (points * 2) (fun index ->
    let radius = if index mod 2 = 0 then outer_radius else inner_radius in
    let angle =
      rotation
      +. (float_of_int index /. float_of_int (points * 2)
          *. 2. *. Float.pi)
    in
    Vec2.add center (Vec2.create (radius *. cos angle) (radius *. sin angle)))
  |> create_exn

let cog ?(rotation = -.Float.pi /. 2.) ~center ~radius ~teeth
    ~profile () =
  validate_radial "cog" ~radius ~sides:teeth;
  if profile = [] then invalid_arg "Polygon2.cog: profile must not be empty";
  if List.exists (fun value -> not (Float.is_finite value) || value <= 0.) profile
  then invalid_arg "Polygon2.cog: profile values must be finite and positive";
  let profile = Array.of_list profile in
  let count = teeth * Array.length profile in
  List.init count (fun index ->
    let scale = profile.(index mod Array.length profile) in
    let angle =
      rotation +. (float_of_int index /. float_of_int count *. 2. *. Float.pi)
    in
    let radius = radius *. scale in
    Vec2.add center (Vec2.create (radius *. cos angle) (radius *. sin angle)))
  |> create_exn
