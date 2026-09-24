open Prismel

type token = Command of char | Number of float

let is_command = function
  | 'M' | 'm' | 'L' | 'l' | 'H' | 'h' | 'V' | 'v'
  | 'C' | 'c' | 'S' | 's' | 'Q' | 'q' | 'T' | 't'
  | 'A' | 'a' | 'Z' | 'z' -> true
  | _ -> false

let tokenize source =
  let length = String.length source in
  let rec skip index =
    if index < length &&
       (source.[index] = ' ' || source.[index] = '\t' ||
        source.[index] = '\r' || source.[index] = '\n' ||
        source.[index] = ',')
    then skip (index + 1)
    else index
  in
  let number_end start =
    let index = ref start in
    if !index < length && (source.[!index] = '+' || source.[!index] = '-') then
      incr index;
    let digits = ref false in
    while !index < length && source.[!index] >= '0' && source.[!index] <= '9' do
      digits := true; incr index
    done;
    if !index < length && source.[!index] = '.' then begin
      incr index;
      while !index < length && source.[!index] >= '0' && source.[!index] <= '9' do
        digits := true; incr index
      done
    end;
    if !digits && !index < length &&
       (source.[!index] = 'e' || source.[!index] = 'E') then begin
      let exponent = !index in
      incr index;
      if !index < length && (source.[!index] = '+' || source.[!index] = '-') then
        incr index;
      let exponent_start = !index in
      while !index < length && source.[!index] >= '0' && source.[!index] <= '9' do
        incr index
      done;
      if !index = exponent_start then index := exponent
    end;
    if !digits then Some !index else None
  in
  let rec loop index tokens =
    let index = skip index in
    if index = length then Ok (List.rev tokens)
    else if is_command source.[index] then
      loop (index + 1) (Command source.[index] :: tokens)
    else
      match number_end index with
      | None -> Error (Printf.sprintf "Svg_path.parse: unexpected character %C at byte %d" source.[index] index)
      | Some end_ ->
          let literal = String.sub source index (end_ - index) in
          (match float_of_string_opt literal with
           | Some value when Float.is_finite value ->
               loop end_ (Number value :: tokens)
           | _ -> Error (Printf.sprintf "Svg_path.parse: invalid number %S" literal))
  in
  loop 0 []

let point relative current x y =
  if relative then Vec2.add current (Vec2.create x y) else Vec2.create x y

let reflected current = function
  | None -> current
  | Some control -> Vec2.sub (Vec2.scale current 2.) control

let arc_to_cubics ~from_ ~to_ ~rx ~ry ~rotation ~large_arc ~sweep =
  if Vec2.nearly_equal from_ to_ ~eps:1e-12 then []
  else if abs_float rx <= 1e-12 || abs_float ry <= 1e-12 then []
  else
    let rx = ref (abs_float rx) and ry = ref (abs_float ry) in
    let phi = rotation *. Float.pi /. 180. in
    let cosine = cos phi and sine = sin phi in
    let dx = (from_.x -. to_.x) /. 2.
    and dy = (from_.y -. to_.y) /. 2. in
    let x1 = cosine *. dx +. sine *. dy
    and y1 = -.sine *. dx +. cosine *. dy in
    let scale = (x1 *. x1 /. (!rx *. !rx)) +.
                (y1 *. y1 /. (!ry *. !ry)) in
    if scale > 1. then begin
      let factor = sqrt scale in rx := !rx *. factor; ry := !ry *. factor
    end;
    let rx2 = !rx *. !rx and ry2 = !ry *. !ry in
    let numerator = max 0.
        ((rx2 *. ry2 -. rx2 *. y1 *. y1 -. ry2 *. x1 *. x1) /.
         (rx2 *. y1 *. y1 +. ry2 *. x1 *. x1)) in
    let sign = if large_arc = sweep then -1. else 1. in
    let factor = sign *. sqrt numerator in
    let cx1 = factor *. (!rx *. y1 /. !ry)
    and cy1 = factor *. (-. !ry *. x1 /. !rx) in
    let cx = cosine *. cx1 -. sine *. cy1 +. (from_.x +. to_.x) /. 2.
    and cy = sine *. cx1 +. cosine *. cy1 +. (from_.y +. to_.y) /. 2. in
    let angle ux uy vx vy = atan2 (ux *. vy -. uy *. vx) (ux *. vx +. uy *. vy) in
    let ux = (x1 -. cx1) /. !rx and uy = (y1 -. cy1) /. !ry
    and vx = (-.x1 -. cx1) /. !rx and vy = (-.y1 -. cy1) /. !ry in
    let start = atan2 uy ux in
    let delta = ref (angle ux uy vx vy) in
    if not sweep && !delta > 0. then delta := !delta -. 2. *. Float.pi;
    if sweep && !delta < 0. then delta := !delta +. 2. *. Float.pi;
    let count = max 1 (int_of_float (ceil (abs_float !delta /. (Float.pi /. 2.)))) in
    let step = !delta /. float_of_int count in
    let map x y = Vec2.create
        (cx +. cosine *. !rx *. x -. sine *. !ry *. y)
        (cy +. sine *. !rx *. x +. cosine *. !ry *. y) in
    List.init count (fun index ->
      let a = start +. float_of_int index *. step in
      let b = a +. step in
      let alpha = 4. /. 3. *. tan ((b -. a) /. 4.) in
      let c1 = map (cos a -. alpha *. sin a) (sin a +. alpha *. cos a)
      and c2 = map (cos b +. alpha *. sin b) (sin b -. alpha *. cos b)
      and target = map (cos b) (sin b) in
      c1, c2, target)

let parse source =
  let ( let* ) = Result.bind in
  let* tokens = tokenize source in
  let tokens = Array.of_list tokens in
  let length = Array.length tokens in
  let number index =
    if index < length then match tokens.(index) with Number value -> Some value | _ -> None
    else None
  in
  let rec take_numbers index count values =
    if count = 0 then Some (List.rev values, index)
    else match number index with
      | Some value -> take_numbers (index + 1) (count - 1) (value :: values)
      | None -> None
  in
  let rec loop index command current start last_cubic last_quad path =
    if index >= length then Ok path
    else
      let command, index = match tokens.(index) with
        | Command command -> Some command, index + 1
        | Number _ -> command, index
      in
      match command with
      | None -> Error "Svg_path.parse: path data must begin with a command"
      | Some command ->
          let relative = Char.lowercase_ascii command = command in
          let upper = Char.uppercase_ascii command in
          let next groups consume =
            match take_numbers index groups [] with
            | None -> Error (Printf.sprintf "Svg_path.parse: command %c has incomplete arguments" command)
            | Some (values, next_index) -> consume values next_index
          in
          match upper with
          | 'Z' ->
              let current = Option.value start ~default:current in
              loop index None current None None None (Path.close path)
          | 'M' -> next 2 (fun values next_index ->
              let x, y = match values with [x; y] -> x, y | _ -> assert false in
              let target = point relative current x y in
              let path = Path.move_to target.x target.y path in
              let repeated = if relative then 'l' else 'L' in
              loop next_index (Some repeated) target (Some target) None None path)
          | 'L' -> next 2 (fun values next_index ->
              let x, y = match values with [x; y] -> x, y | _ -> assert false in
              let target = point relative current x y in
              loop next_index (Some command) target start None None
                (Path.line_to target.x target.y path))
          | 'H' -> next 1 (fun values next_index ->
              let x = match values with [x] -> x | _ -> assert false in
              let target = Vec2.create (if relative then current.x +. x else x) current.y in
              loop next_index (Some command) target start None None
                (Path.line_to target.x target.y path))
          | 'V' -> next 1 (fun values next_index ->
              let y = match values with [y] -> y | _ -> assert false in
              let target = Vec2.create current.x (if relative then current.y +. y else y) in
              loop next_index (Some command) target start None None
                (Path.line_to target.x target.y path))
          | 'C' -> next 6 (fun values next_index ->
              let x1,y1,x2,y2,x,y = match values with
                | [x1;y1;x2;y2;x;y] -> x1,y1,x2,y2,x,y | _ -> assert false in
              let c1 = point relative current x1 y1
              and c2 = point relative current x2 y2
              and target = point relative current x y in
              loop next_index (Some command) target start (Some c2) None
                (Path.cubic_to ~control1:(c1.x,c1.y) ~control2:(c2.x,c2.y)
                   ~to_:(target.x,target.y) path))
          | 'S' -> next 4 (fun values next_index ->
              let x2,y2,x,y = match values with
                | [x2;y2;x;y] -> x2,y2,x,y | _ -> assert false in
              let c1 = reflected current last_cubic
              and c2 = point relative current x2 y2
              and target = point relative current x y in
              loop next_index (Some command) target start (Some c2) None
                (Path.cubic_to ~control1:(c1.x,c1.y) ~control2:(c2.x,c2.y)
                   ~to_:(target.x,target.y) path))
          | 'Q' -> next 4 (fun values next_index ->
              let x1,y1,x,y = match values with
                | [x1;y1;x;y] -> x1,y1,x,y | _ -> assert false in
              let control = point relative current x1 y1
              and target = point relative current x y in
              loop next_index (Some command) target start None (Some control)
                (Path.quadratic_to ~control:(control.x,control.y)
                   ~to_:(target.x,target.y) path))
          | 'T' -> next 2 (fun values next_index ->
              let x,y = match values with [x;y] -> x,y | _ -> assert false in
              let control = reflected current last_quad
              and target = point relative current x y in
              loop next_index (Some command) target start None (Some control)
                (Path.quadratic_to ~control:(control.x,control.y)
                   ~to_:(target.x,target.y) path))
          | 'A' -> next 7 (fun values next_index ->
              let rx,ry,rotation,large,sweep,x,y = match values with
                | [rx;ry;rotation;large;sweep;x;y] -> rx,ry,rotation,large,sweep,x,y
                | _ -> assert false in
              if (large <> 0. && large <> 1.) || (sweep <> 0. && sweep <> 1.) then
                Error "Svg_path.parse: arc flags must be zero or one"
              else
                let target = point relative current x y in
                let cubics = arc_to_cubics ~from_:current ~to_:target ~rx ~ry
                    ~rotation ~large_arc:(large = 1.) ~sweep:(sweep = 1.) in
                let path = match cubics with
                  | [] when not (Vec2.nearly_equal current target ~eps:1e-12) ->
                      Path.line_to target.x target.y path
                  | _ -> List.fold_left (fun path
                      ((c1 : Vec2.t), (c2 : Vec2.t), (target : Vec2.t)) ->
                      Path.cubic_to ~control1:(c1.x,c1.y) ~control2:(c2.x,c2.y)
                        ~to_:(target.x,target.y) path) path cubics in
                let last = match List.rev cubics with [] -> None | (_,c2,_)::_ -> Some c2 in
                loop next_index (Some command) target start last None path)
          | _ -> Error (Printf.sprintf "Svg_path.parse: unsupported command %c" command)
  in
  if length = 0 then Ok Path.empty
  else loop 0 None Vec2.zero None None None Path.empty

let number precision value =
  let text = Printf.sprintf "%.*f" precision value in
  let rec trim index =
    if index > 0 && text.[index - 1] = '0' then trim (index - 1)
    else if index > 0 && text.[index - 1] = '.' then index - 1
    else index
  in
  let length = trim (String.length text) in
  if length = 0 || (length = 2 && String.sub text 0 2 = "-0") then "0"
  else String.sub text 0 length

let to_string ?(precision = 6) path =
  if precision < 0 then invalid_arg "Svg_path.to_string: precision must be non-negative";
  let n = number precision in
  Path.commands path |> List.map (function
    | Path.Move_to (x,y) -> Printf.sprintf "M%s %s" (n x) (n y)
    | Path.Line_to (x,y) -> Printf.sprintf "L%s %s" (n x) (n y)
    | Path.Quadratic_to ((x1,y1),(x,y)) ->
        Printf.sprintf "Q%s %s %s %s" (n x1) (n y1) (n x) (n y)
    | Path.Cubic_to ((x1,y1),(x2,y2),(x,y)) ->
        Printf.sprintf "C%s %s %s %s %s %s"
          (n x1) (n y1) (n x2) (n y2) (n x) (n y)
    | Path.Close -> "Z")
  |> String.concat " "
