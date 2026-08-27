type command =
  | Move_to of float * float
  | Line_to of float * float
  | Quadratic_to of (float * float) * (float * float)
  | Cubic_to of (float * float) * (float * float) * (float * float)
  | Close

type fill_rule = Even_odd | Non_zero
type t = command list

let empty = []
let add command path = command :: path
let move_to x y = add (Move_to (x, y))
let line_to x y = add (Line_to (x, y))
let quadratic_to ~control ~to_ = add (Quadratic_to (control, to_))
let cubic_to ~control1 ~control2 ~to_ =
  add (Cubic_to (control1, control2, to_))
let close = add Close
let commands path = List.rev path

let is_closed path =
  match path with Close :: _ -> true | _ -> false

let lerp a b amount = a +. ((b -. a) *. amount)
let pair (x, y) = int_of_float (Float.round x), int_of_float (Float.round y)

let contours ?(steps = 20) path =
  let steps = max 1 steps in
  let flush first points contours ~close =
    match points with
    | [] -> contours
    | _ ->
        let points =
          match close, first with
          | true, Some first when List.hd points <> first -> first :: points
          | _ -> points
        in
        List.rev_map pair points :: contours
  in
  let curve_samples evaluate =
    List.init steps (fun index ->
      let amount = float_of_int (index + 1) /. float_of_int steps in
      evaluate amount)
  in
  let rec loop current first points contours = function
    | [] -> List.rev (flush first points contours ~close:false)
    | Move_to (x, y) :: rest ->
        let point = x, y in
        let contours = flush first points contours ~close:false in
        loop (Some point) (Some point) [point] contours rest
    | Line_to (x, y) :: rest ->
        let point = x, y in
        let first = Option.value first ~default:point in
        loop (Some point) (Some first) (point :: points) contours rest
    | Quadratic_to (control, target) :: rest ->
        (match current with
         | None ->
             loop (Some target) (Some target) [target] contours rest
         | Some (x0, y0) ->
             let cx, cy = control and x1, y1 = target in
             let samples =
               curve_samples (fun amount ->
                 let xa = lerp x0 cx amount and ya = lerp y0 cy amount in
                 let xb = lerp cx x1 amount and yb = lerp cy y1 amount in
                 lerp xa xb amount, lerp ya yb amount)
             in
             loop (Some target) first
               (List.rev_append samples points) contours rest)
    | Cubic_to (control1, control2, target) :: rest ->
        (match current with
         | None ->
             loop (Some target) (Some target) [target] contours rest
         | Some (x0, y0) ->
             let x1, y1 = control1 in
             let x2, y2 = control2 in
             let x3, y3 = target in
             let samples =
               curve_samples (fun amount ->
                 let xa = lerp x0 x1 amount and ya = lerp y0 y1 amount in
                 let xb = lerp x1 x2 amount and yb = lerp y1 y2 amount in
                 let xc = lerp x2 x3 amount and yc = lerp y2 y3 amount in
                 let xm = lerp xa xb amount and ym = lerp ya yb amount in
                 let xn = lerp xb xc amount and yn = lerp yb yc amount in
                 lerp xm xn amount, lerp ym yn amount)
             in
             loop (Some target) first
               (List.rev_append samples points) contours rest)
    | Close :: rest ->
        let contours = flush first points contours ~close:true in
        loop None None [] contours rest
  in
  loop None None [] [] (List.rev path)

let points ?steps path = List.concat (contours ?steps path)
