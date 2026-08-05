open Prismel

type triangle = {
  a : Vec2.t;
  b : Vec2.t;
  c : Vec2.t;
}

type cell = {
  site : Vec2.t;
  polygon : Polygon2.t;
}

let validate_epsilon name epsilon =
  if not (Float.is_finite epsilon) || epsilon < 0. then
    invalid_arg
      ("Delaunay2." ^ name ^ ": epsilon must be finite and non-negative")

let point_finite point =
  Float.is_finite point.Vec2.x && Float.is_finite point.y

let cross (a : Vec2.t) (b : Vec2.t) (c : Vec2.t) =
  ((b.x -. a.x) *. (c.y -. a.y))
  -. ((b.y -. a.y) *. (c.x -. a.x))

let make_triangle ?(epsilon = 1e-12) a b c =
  let signed = cross a b c in
  if abs_float signed <= epsilon then None
  else if signed > 0. then Some { a; b; c }
  else Some { a; b = c; c = b }

let vertices triangle = triangle.a, triangle.b, triangle.c

let edges triangle =
  [
    Segment2.make triangle.a triangle.b;
    Segment2.make triangle.b triangle.c;
    Segment2.make triangle.c triangle.a;
  ]

let area triangle = cross triangle.a triangle.b triangle.c /. 2.

let centroid triangle =
  Vec2.scale
    (Vec2.add triangle.a (Vec2.add triangle.b triangle.c))
    (1. /. 3.)

let circumcenter ?(epsilon = 1e-9) triangle =
  Circle2.through_three_points ~epsilon
    triangle.a triangle.b triangle.c
  |> Option.map (fun circle -> circle.Circle2.center)

let contains ?(epsilon = 1e-9) triangle point =
  validate_epsilon "contains" epsilon;
  let ab = cross triangle.a triangle.b point
  and bc = cross triangle.b triangle.c point
  and ca = cross triangle.c triangle.a point in
  ab >= -.epsilon && bc >= -.epsilon && ca >= -.epsilon

let point_compare left right =
  match Float.compare left.Vec2.x right.Vec2.x with
  | 0 -> Float.compare left.y right.y
  | order -> order

let edge_key a b =
  if point_compare a b <= 0 then a, b else b, a

let near epsilon left right =
  Vec2.length_sq (Vec2.sub left right) <= epsilon *. epsilon

let normalize_points epsilon points =
  if List.exists (fun point -> not (point_finite point)) points then
    invalid_arg "Delaunay2.triangulate: points must be finite";
  if epsilon = 0. then begin
    let seen = Hashtbl.create (List.length points) in
    List.filter
      (fun point ->
        let key = point.Vec2.x, point.y in
        if Hashtbl.mem seen key then false
        else begin Hashtbl.add seen key (); true end)
      points
  end else begin
    let buckets = Hashtbl.create (List.length points) in
    let result = ref [] in
    let bucket point =
      floor (point.Vec2.x /. epsilon), floor (point.y /. epsilon) in
    List.iter
      (fun point ->
        let bx, by = bucket point in
        let duplicate = ref false in
        let dx = ref (-1) in
        while !dx <= 1 && not !duplicate do
          let dy = ref (-1) in
          while !dy <= 1 && not !duplicate do
            let key = bx +. float_of_int !dx, by +. float_of_int !dy in
            match Hashtbl.find_opt buckets key with
            | Some candidates when List.exists (near epsilon point) candidates ->
                duplicate := true
            | _ -> incr dy
          done;
          incr dx
        done;
        if not !duplicate then begin
          let key = bx, by in
          let bucket = Option.value ~default:[] (Hashtbl.find_opt buckets key) in
          Hashtbl.replace buckets key (point :: bucket);
          result := point :: !result
        end)
      points;
    List.rev !result
  end

let same_point left right =
  left.Vec2.x = right.Vec2.x && left.y = right.y

module Point_edge = struct
  type t = Vec2.t * Vec2.t
  let equal (a0, b0) (a1, b1) =
    same_point a0 a1 && same_point b0 b1
  let hash = Hashtbl.hash
end

module Point_edge_table = Hashtbl.Make (Point_edge)

let edge_counts triangles =
  let counts = Point_edge_table.create (max 16 (List.length triangles * 2)) in
  let order = ref [] in
  let add a b =
    let key = edge_key a b in
    match Point_edge_table.find_opt counts key with
    | None -> Point_edge_table.add counts key 1; order := key :: !order
    | Some count -> Point_edge_table.replace counts key (count + 1)
  in
  List.iter (fun triangle ->
    add triangle.a triangle.b;
    add triangle.b triangle.c;
    add triangle.c triangle.a) triangles;
  List.rev_map (fun key -> key, Point_edge_table.find counts key) !order

type work_triangle = {
  ia : int;
  ib : int;
  ic : int;
  circum_x : float;
  circum_y : float;
  circum_radius_sq : float;
}

type triangle_buffer = {
  mutable data : work_triangle array;
  mutable length : int;
}

let buffer_create initial = { data = Array.make 16 initial; length = 0 }

let buffer_push buffer triangle =
  if buffer.length = Array.length buffer.data then begin
    let data = Array.make (buffer.length * 2) triangle in
    Array.blit buffer.data 0 data 0 buffer.length;
    buffer.data <- data
  end;
  buffer.data.(buffer.length) <- triangle;
  buffer.length <- buffer.length + 1

let make_work_triangle ~epsilon points ia ib ic =
  let a = points.(ia) and b = points.(ib) and c = points.(ic) in
  let signed = cross a b c in
  if abs_float signed <= epsilon then None
  else
    let ib, ic, b, c = if signed > 0. then ib, ic, b, c else ic, ib, c, b in
    let ax = a.Vec2.x and ay = a.y
    and bx = b.Vec2.x and by = b.y
    and cx = c.Vec2.x and cy = c.y in
    let denominator =
      2. *. ((ax *. (by -. cy)) +. (bx *. (cy -. ay))
             +. (cx *. (ay -. by))) in
    if abs_float denominator <= epsilon then None
    else
      let aa = (ax *. ax) +. (ay *. ay)
      and bb = (bx *. bx) +. (by *. by)
      and cc = (cx *. cx) +. (cy *. cy) in
      let circum_x =
        ((aa *. (by -. cy)) +. (bb *. (cy -. ay))
         +. (cc *. (ay -. by))) /. denominator
      and circum_y =
        ((aa *. (cx -. bx)) +. (bb *. (ax -. cx))
         +. (cc *. (bx -. ax))) /. denominator in
      let dx = circum_x -. ax and dy = circum_y -. ay in
      Some { ia; ib; ic; circum_x; circum_y;
             circum_radius_sq = (dx *. dx) +. (dy *. dy) }

let work_contains epsilon triangle point =
  let dx = point.Vec2.x -. triangle.circum_x
  and dy = point.y -. triangle.circum_y in
  (dx *. dx) +. (dy *. dy)
  <= triangle.circum_radius_sq
     +. (epsilon *. Float.max 1. triangle.circum_radius_sq)

module Index_edge = struct
  type t = int * int
  let equal (a0, b0) (a1, b1) = a0 = a1 && b0 = b1
  let hash (a, b) = ((a * 65599) lxor b) land max_int
end

module Index_edge_table = Hashtbl.Make (Index_edge)

let super_triangle points =
  match Bounds2.of_points points with
  | None -> assert false
  | Some bounds ->
      let center = Bounds2.center bounds in
      let span = Float.max (Bounds2.width bounds) (Bounds2.height bounds) in
      let radius = Float.max 1. span *. 32. in
      let a = Vec2.create (center.x -. (2. *. radius)) (center.y -. radius)
      and b = Vec2.create center.x (center.y +. (2. *. radius))
      and c = Vec2.create (center.x +. (2. *. radius)) (center.y -. radius) in
      match make_triangle a b c with
      | Some triangle -> triangle
      | None -> assert false

let triangulate ?(epsilon = 1e-9) supplied =
  validate_epsilon "triangulate" epsilon;
  let points = normalize_points epsilon supplied in
  let point_count = List.length points in
  if point_count < 3 then []
  else
    let enclosing = super_triangle points in
    let supplied_points = Array.of_list points in
    let points = Array.init (point_count + 3) (fun index ->
      if index < point_count then supplied_points.(index)
      else if index = point_count then enclosing.a
      else if index = point_count + 1 then enclosing.b
      else enclosing.c) in
    let initial =
      match make_work_triangle ~epsilon points point_count
          (point_count + 1) (point_count + 2) with
      | Some triangle -> triangle
      | None -> assert false in
    let current = ref (buffer_create initial)
    and next = ref (buffer_create initial) in
    buffer_push !current initial;
    for point_index = 0 to point_count - 1 do
      (!next).length <- 0;
      let boundary = Index_edge_table.create 32 in
      let boundary_order = ref [] in
      let add_edge a b =
        let key = if a <= b then a, b else b, a in
        match Index_edge_table.find_opt boundary key with
        | None ->
            Index_edge_table.add boundary key (1, a, b);
            boundary_order := key :: !boundary_order
        | Some (count, original_a, original_b) ->
            Index_edge_table.replace boundary key
              (count + 1, original_a, original_b) in
      for triangle_index = 0 to (!current).length - 1 do
        let triangle = (!current).data.(triangle_index) in
        if work_contains epsilon triangle points.(point_index) then begin
          add_edge triangle.ia triangle.ib;
          add_edge triangle.ib triangle.ic;
          add_edge triangle.ic triangle.ia
        end else buffer_push !next triangle
      done;
      List.iter
        (fun key ->
          match Index_edge_table.find boundary key with
          | 1, a, b ->
              (match make_work_triangle ~epsilon points a b point_index with
               | Some triangle -> buffer_push !next triangle
               | None -> ())
          | _ -> ())
        (List.rev !boundary_order);
      let previous = !current in
      current := !next;
      next := previous
    done;
    let output = ref [] in
    for index = 0 to (!current).length - 1 do
      let triangle = (!current).data.(index) in
      if triangle.ia < point_count
         && triangle.ib < point_count
         && triangle.ic < point_count
      then output := {
          a = points.(triangle.ia);
          b = points.(triangle.ib);
          c = points.(triangle.ic);
        } :: !output
    done;
    List.sort
      (fun left right ->
        let lx = left.a.x +. left.b.x +. left.c.x
        and rx = right.a.x +. right.b.x +. right.c.x in
        match Float.compare lx rx with
        | 0 -> Float.compare
                 (left.a.y +. left.b.y +. left.c.y)
                 (right.a.y +. right.b.y +. right.c.y)
        | order -> order)
      !output

let counted_edges triangles = edge_counts triangles

let unique_edges triangles =
  counted_edges triangles
  |> List.map (fun ((a, b), _) -> Segment2.make a b)

let boundary_edges triangles =
  counted_edges triangles
  |> List.filter_map (fun ((a, b), count) ->
    if count = 1 then Some (Segment2.make a b) else None)

let clip_half_plane ~epsilon ~normal ~offset polygon =
  let inside point =
    Vec2.dot point normal <= offset +. epsilon
  in
  let intersect previous current =
    let direction = Vec2.sub current previous in
    let denominator = Vec2.dot direction normal in
    if abs_float denominator <= epsilon then previous
    else
      let amount =
        (offset -. Vec2.dot previous normal) /. denominator
        |> Float.max 0. |> Float.min 1.
      in
      Vec2.add previous (Vec2.scale direction amount)
  in
  match List.rev polygon with
  | [] -> []
  | previous :: _ ->
      let previous = ref previous and output = ref [] in
      List.iter
        (fun current ->
          let current_inside = inside current
          and previous_inside = inside !previous in
          if current_inside then begin
            if not previous_inside then
              output := intersect !previous current :: !output;
            output := current :: !output
          end
          else if previous_inside then
            output := intersect !previous current :: !output;
          previous := current)
        polygon;
      List.rev !output

let squared_length point =
  (point.Vec2.x *. point.x) +. (point.y *. point.y)

let voronoi_cells ?(epsilon = 1e-9) ~bounds supplied =
  validate_epsilon "voronoi_cells" epsilon;
  let sites = normalize_points epsilon supplied in
  let rectangle = Bounds2.corners bounds in
  List.filter_map
    (fun site ->
      let vertices =
        List.fold_left
          (fun polygon other ->
            if polygon = [] || same_point site other then polygon
            else
              let normal = Vec2.sub other site in
              let offset =
                (squared_length other -. squared_length site) /. 2.
              in
              clip_half_plane ~epsilon ~normal ~offset polygon)
          rectangle sites
      in
      match Polygon2.create vertices with
      | Ok polygon -> Some { site; polygon }
      | Error _ -> None)
    sites
