open Prismel_math

type cell = { site : Vec2.t; vertices : Vec2.t list }

let same_point (a : Vec2.t) (b : Vec2.t) = a.x = b.x && a.y = b.y

let near epsilon a b =
  Vec2.length_sq (Vec2.sub a b) <= epsilon *. epsilon

let normalize_sites ?cancel epsilon supplied =
  if epsilon = 0. then begin
    let seen = Hashtbl.create (List.length supplied) in
    List.filter (fun point ->
      Cancel.check_opt cancel;
      let key = point.Vec2.x, point.y in
      if Hashtbl.mem seen key then false
      else (Hashtbl.add seen key (); true)) supplied
  end else begin
    let buckets = Hashtbl.create (List.length supplied) in
    let result = ref [] in
    List.iter (fun point ->
      Cancel.check_opt cancel;
      let bx = floor (point.Vec2.x /. epsilon)
      and by = floor (point.y /. epsilon) in
      let duplicate = ref false and dx = ref (-1) in
      while !dx <= 1 && not !duplicate do
        let dy = ref (-1) in
        while !dy <= 1 && not !duplicate do
          let key = bx +. float_of_int !dx, by +. float_of_int !dy in
          (match Hashtbl.find_opt buckets key with
           | Some candidates when List.exists (near epsilon point) candidates ->
               duplicate := true
           | _ -> incr dy)
        done;
        incr dx
      done;
      if not !duplicate then begin
        let key = bx, by in
        let bucket = Option.value ~default:[] (Hashtbl.find_opt buckets key) in
        Hashtbl.replace buckets key (point :: bucket);
        result := point :: !result
      end) supplied;
    List.rev !result
  end

let clip_half_plane ~epsilon ~normal ~offset polygon =
  let inside point = Vec2.dot point normal <= offset +. epsilon in
  let intersect previous current =
    let direction = Vec2.sub current previous in
    let denominator = Vec2.dot direction normal in
    if abs_float denominator <= epsilon then previous
    else
      let amount = (offset -. Vec2.dot previous normal) /. denominator
        |> Float.max 0. |> Float.min 1. in
      Vec2.add previous (Vec2.scale direction amount) in
  match List.rev polygon with
  | [] -> []
  | previous :: _ ->
      let previous = ref previous and output = ref [] in
      List.iter (fun current ->
        let current_inside = inside current
        and previous_inside = inside !previous in
        if current_inside then begin
          if not previous_inside then
            output := intersect !previous current :: !output;
          output := current :: !output
        end else if previous_inside then
          output := intersect !previous current :: !output;
        previous := current) polygon;
      List.rev !output

let squared_length point =
  point.Vec2.x *. point.x +. point.y *. point.y

let normalize_vertices points =
  let points = List.fold_left (fun acc point -> match acc with
    | previous :: _ when same_point previous point -> acc
    | _ -> point :: acc) [] points |> List.rev in
  match points with
  | [] -> []
  | first :: _ ->
      (match List.rev points with
       | last :: rest when same_point first last -> List.rev rest
       | _ -> points)

(* ponytail: pairwise clipping is quadratic in sites; use Delaunay neighbors
   if dense Voronoi construction becomes a measured bottleneck. *)
let cells ?cancel ?(epsilon = 1e-9) ~bounds supplied =
  Error.guard ~operation:"voronoi_cells" ~code:"invalid_parameter" (fun () ->
    if not (Float.is_finite epsilon) || epsilon < 0. then
      Error "epsilon must be finite and non-negative"
    else if List.exists (fun point ->
        not (Float.is_finite point.Vec2.x && Float.is_finite point.y)) supplied
    then Error "sites must be finite"
    else begin
      let sites = normalize_sites ?cancel epsilon supplied in
      let rectangle = Bounds2.corners bounds in
      let cells = List.filter_map (fun site ->
        Cancel.check_opt cancel;
        let vertices = List.fold_left (fun polygon other ->
          if polygon = [] || same_point site other then polygon
          else
            let normal = Vec2.sub other site in
            let offset = (squared_length other -. squared_length site) /. 2. in
            clip_half_plane ~epsilon ~normal ~offset polygon)
          rectangle sites |> normalize_vertices in
        if List.length vertices >= 3 then Some { site; vertices }
        else None) sites in
      Ok cells end)
