open Prismel

let validate matrix =
  let height = Array.length matrix in
  if height < 2 then Error "Contour2.extract: matrix needs at least two rows"
  else
    let width = Array.length matrix.(0) in
    if width < 2 then Error "Contour2.extract: matrix needs at least two columns"
    else if Array.exists (fun row -> Array.length row <> width) matrix then
      Error "Contour2.extract: matrix rows must have equal lengths"
    else if Array.exists (Array.exists (fun value -> not (Float.is_finite value))) matrix then
      Error "Contour2.extract: matrix contains a non-finite value"
    else Ok (width, height)

let interpolate iso value_a value_b a b =
  let amount = if abs_float (value_b -. value_a) <= 1e-15 then 0.5
    else max 0. (min 1. ((iso -. value_a) /. (value_b -. value_a))) in
  Vec2.lerp a b amount

let edge_pairs = function
  | 0 | 15 -> []
  | 1 -> [3,0] | 2 -> [0,1] | 3 -> [3,1]
  | 4 -> [1,2] | 5 -> [3,2; 0,1] | 6 -> [0,2] | 7 -> [3,2]
  | 8 -> [2,3] | 9 -> [0,2] | 10 -> [0,3; 1,2] | 11 -> [1,2]
  | 12 -> [1,3] | 13 -> [0,1] | 14 -> [3,0]
  | _ -> assert false

module Key = struct
  type t = int * int
  let equal = ( = )
  let hash = Hashtbl.hash
end
module Key_table = Hashtbl.Make (Key)

let key point =
  int_of_float (Float.round (point.Vec2.x *. 1e9)),
  int_of_float (Float.round (point.y *. 1e9))

let stitch segments =
  let segments = Array.of_list segments in
  let adjacency = Key_table.create (Array.length segments * 2) in
  let add point edge =
    let id = key point in
    Key_table.replace adjacency id
      (edge :: Option.value ~default:[] (Key_table.find_opt adjacency id))
  in
  Array.iteri (fun edge (a,b) -> add a edge; add b edge) segments;
  let used = Array.make (Array.length segments) false in
  let walk start_edge start_point =
    let points = ref [start_point] and edge = ref start_edge and current = ref start_point in
    while !edge >= 0 do
      let index = !edge in
      used.(index) <- true;
      let a,b = segments.(index) in
      let next = if key a = key !current then b else a in
      points := next :: !points;
      current := next;
      edge := Key_table.find_opt adjacency (key next)
        |> Option.value ~default:[]
        |> List.find_opt (fun candidate -> not used.(candidate))
        |> Option.value ~default:(-1)
    done;
    List.rev !points
  in
  let curves = ref [] in
  let emit edge =
    if not used.(edge) then
      let a,b = segments.(edge) in
      let start = match Key_table.find_opt adjacency (key a) with
        | Some [_] -> a
        | _ -> (match Key_table.find_opt adjacency (key b) with Some [_] -> b | _ -> a) in
      let points = walk edge start in
      let closed = match points, List.rev points with
        | first :: _, last :: _ -> key first = key last
        | _ -> false in
      match Curve2.create ~closed points with
      | Ok curve -> curves := curve :: !curves
      | Error _ -> ()
  in
  Array.iteri (fun edge _ ->
    if not used.(edge) then
      let a,b = segments.(edge) in
      let degree point = Key_table.find_opt adjacency (key point)
          |> Option.fold ~none:0 ~some:List.length in
      if degree a = 1 || degree b = 1 then emit edge) segments;
  Array.iteri (fun edge _ -> emit edge) segments;
  List.rev !curves

let extract ~iso matrix =
  if not (Float.is_finite iso) then invalid_arg "Contour2.extract: iso must be finite";
  Result.map (fun (width,height) ->
    let segments = ref [] in
    for y = 0 to height - 2 do
      for x = 0 to width - 2 do
        let values = [|matrix.(y).(x); matrix.(y).(x+1);
          matrix.(y+1).(x+1); matrix.(y+1).(x)|] in
        let code = ref 0 in
        Array.iteri (fun index value -> if value >= iso then
          code := !code lor (1 lsl index)) values;
        let xf = float_of_int x and yf = float_of_int y in
        let corners = [|Vec2.create xf yf; Vec2.create (xf+.1.) yf;
          Vec2.create (xf+.1.) (yf+.1.); Vec2.create xf (yf+.1.)|] in
        let edge = function
          | 0 -> interpolate iso values.(0) values.(1) corners.(0) corners.(1)
          | 1 -> interpolate iso values.(1) values.(2) corners.(1) corners.(2)
          | 2 -> interpolate iso values.(2) values.(3) corners.(2) corners.(3)
          | 3 -> interpolate iso values.(3) values.(0) corners.(3) corners.(0)
          | _ -> assert false in
        List.iter (fun (left,right) -> segments := (edge left, edge right) :: !segments)
          (edge_pairs !code)
      done
    done;
    stitch (List.rev !segments)) (validate matrix)
