type point = { x : float; y : float }

type command =
  | Move_to of point
  | Line_to of point
  | Quadratic_to of point * point
  | Cubic_to of point * point * point
  | Close

type t = command array
type fill_rule = Even_odd | Non_zero
type mesh = { vertices : point array; indices : int array }

type error =
  | Empty_path
  | Invalid_tolerance of float
  | Non_finite_point of point
  | Missing_current_point
  | Open_contour
  | Complexity_limit

let of_commands commands = Array.copy commands
let commands path = Array.copy path
let finite p = Float.is_finite p.x && Float.is_finite p.y

module Points = struct
  type t = { mutable values : point array; mutable length : int }

  let create () = { values = Array.make 16 { x = 0.; y = 0. }; length = 0 }

  let add t value =
    if t.length = Array.length t.values then begin
      if t.length >= 1_048_576 then raise Exit;
      let values = Array.make (2 * t.length) value in
      Array.blit t.values 0 values 0 t.length;
      t.values <- values
    end;
    t.values.(t.length) <- value;
    t.length <- t.length + 1

  let array t = Array.sub t.values 0 t.length
end

let midpoint a b = { x = (a.x +. b.x) *. 0.5; y = (a.y +. b.y) *. 0.5 }

let distance_to_line_squared p a b =
  let dx = b.x -. a.x and dy = b.y -. a.y in
  let denominator = (dx *. dx) +. (dy *. dy) in
  if denominator = 0. then
    let x = p.x -. a.x and y = p.y -. a.y in
    (x *. x) +. (y *. y)
  else
    let cross = ((p.x -. a.x) *. dy) -. ((p.y -. a.y) *. dx) in
    (cross *. cross) /. denominator

let flatten ~tolerance path =
  if (not (Float.is_finite tolerance)) || tolerance <= 0. then
    Error (Invalid_tolerance tolerance)
  else if Array.length path = 0 then Error Empty_path
  else
    let tolerance_squared = tolerance *. tolerance in
    let contours = ref [] and current = ref None and start = ref None in
    let points = ref (Points.create ()) in
    let finish closed =
      let values = Points.array !points in
      if Array.length values > 0 then contours := (values, closed) :: !contours;
      points := Points.create ();
      current := None;
      start := None
    in
    let rec quadratic output depth a control b =
      if depth = 24 || distance_to_line_squared control a b <= tolerance_squared
      then Points.add output b
      else
        let ab = midpoint a control and bc = midpoint control b in
        let center = midpoint ab bc in
        quadratic output (depth + 1) a ab center;
        quadratic output (depth + 1) center bc b
    and cubic output depth a c1 c2 b =
      if depth = 24
         || max (distance_to_line_squared c1 a b)
              (distance_to_line_squared c2 a b)
            <= tolerance_squared
      then Points.add output b
      else
        let a1 = midpoint a c1 and c12 = midpoint c1 c2 and c2b = midpoint c2 b in
        let left = midpoint a1 c12 and right = midpoint c12 c2b in
        let center = midpoint left right in
        cubic output (depth + 1) a a1 left center;
        cubic output (depth + 1) center right c2b b
    in
    let bad = ref None in
    (try
       Array.iter
         (fun command ->
           let check p = if not (finite p) then (bad := Some p; raise Exit) in
           match command with
           | Move_to p ->
               check p;
               if !current <> None then finish false;
               Points.add !points p;
               current := Some p;
               start := Some p
           | Line_to p ->
               check p;
               (match !current with None -> raise Not_found | Some _ -> Points.add !points p);
               current := Some p
           | Quadratic_to (control, p) ->
               check control; check p;
               (match !current with None -> raise Not_found | Some a -> quadratic !points 0 a control p);
               current := Some p
           | Cubic_to (c1, c2, p) ->
               check c1; check c2; check p;
               (match !current with None -> raise Not_found | Some a -> cubic !points 0 a c1 c2 p);
               current := Some p
           | Close ->
               (match !current, !start with
               | Some last, Some first when last <> first -> Points.add !points first
               | Some _, Some _ -> ()
               | _ -> raise Not_found);
               finish true)
         path;
       if !current <> None then finish false;
       match List.find_opt (fun (_, closed) -> not closed) !contours with
       | Some _ -> Error Open_contour
       | None -> Ok (Array.of_list (List.rev_map fst !contours))
     with
    | Not_found -> Error Missing_current_point
    | Exit -> (match !bad with Some p -> Error (Non_finite_point p) | None -> Error Complexity_limit))

type crossing = { x0 : float; x1 : float; winding : int }

let tessellate ~tolerance ~fill_rule path =
  match flatten ~tolerance path with
  | Error _ as error -> error
  | Ok contours ->
      let ys =
        Array.concat (Array.to_list (Array.map (Array.map (fun p -> p.y)) contours))
      in
      Array.sort Float.compare ys;
      let unique = Points.create () in
      Array.iter
        (fun y ->
          if unique.length = 0 || unique.values.(unique.length - 1).y <> y then
            Points.add unique { x = 0.; y })
        ys;
      let vertices = Points.create () and triangles = ref [] in
      let add_quad left right y0 y1 =
        let base = vertices.length in
        Points.add vertices { x = left.x0; y = y0 };
        Points.add vertices { x = right.x0; y = y0 };
        Points.add vertices { x = right.x1; y = y1 };
        Points.add vertices { x = left.x1; y = y1 };
        triangles := base :: (base + 1) :: (base + 2) :: base :: (base + 2) :: (base + 3) :: !triangles
      in
      (try
         for band = 0 to unique.length - 2 do
           let y0 = unique.values.(band).y and y1 = unique.values.(band + 1).y in
           if y1 > y0 then begin
             let middle = (y0 +. y1) *. 0.5 and edges = ref [] in
             Array.iter
               (fun contour ->
                 for i = 0 to Array.length contour - 2 do
                   let a = contour.(i) and b = contour.(i + 1) in
                   let low = min a.y b.y and high = max a.y b.y in
                   if a.y <> b.y && middle >= low && middle < high then begin
                     let at y = a.x +. ((y -. a.y) *. (b.x -. a.x) /. (b.y -. a.y)) in
                     edges := { x0 = at y0; x1 = at y1; winding = if b.y > a.y then 1 else -1 } :: !edges
                   end
                 done)
               contours;
             let edges = Array.of_list !edges in
             Array.sort (fun a b -> Float.compare ((a.x0 +. a.x1) *. 0.5) ((b.x0 +. b.x1) *. 0.5)) edges;
             let inside = ref false and winding = ref 0 and left = ref None in
             Array.iter
               (fun edge ->
                 let was_inside = !inside in
                 (match fill_rule with
                 | Even_odd -> inside := not !inside
                 | Non_zero -> winding := !winding + edge.winding; inside := !winding <> 0);
                 if (not was_inside) && !inside then left := Some edge
                 else if was_inside && not !inside then
                   match !left with Some start -> add_quad start edge y0 y1 | None -> assert false)
               edges
           end
         done;
         Ok { vertices = Points.array vertices; indices = Array.of_list (List.rev !triangles) }
       with Exit -> Error Complexity_limit)
