open Prismel

type t = { points : Vec3.t array; closed : bool }

let equal (left : Vec3.t) (right : Vec3.t) =
  left.x = right.x && left.y = right.y && left.z = right.z
let normalize_points ~closed points =
  let points = List.fold_left (fun result point -> match result with
    | previous :: _ when equal previous point -> result | _ -> point :: result)
      [] points |> List.rev in
  if closed then match points, List.rev points with
    | first :: _, last :: rest when equal first last -> List.rev rest
    | _ -> points
  else points

let create ?(closed = false) points =
  let points = normalize_points ~closed points in
  let minimum = if closed then 3 else 2 in
  if List.length points < minimum then Error
      (Printf.sprintf "Curve3.create: a%s curve requires at least %d distinct points"
         (if closed then " closed" else "n open") minimum)
  else Ok { points = Array.of_list points; closed }

let create_exn ?closed points = match create ?closed points with
  | Ok curve -> curve | Error message -> invalid_arg message
let points curve = Array.to_list curve.points
let point_count curve = Array.length curve.points
let closed curve = curve.closed
let segment_count curve = if curve.closed then point_count curve else point_count curve - 1
let segments curve = List.init (segment_count curve) (fun index ->
  Segment3.make curve.points.(index) curve.points.((index+1) mod point_count curve))
let length curve = List.fold_left (fun total segment -> total +. Segment3.length segment) 0. (segments curve)

let point_at curve amount =
  if not (Float.is_finite amount) then invalid_arg "Curve3.point_at: amount must be finite";
  let amount = if curve.closed then
      let value = mod_float amount 1. in if value < 0. then value +. 1. else value
    else max 0. (min 1. amount) in
  if not curve.closed && amount >= 1. then curve.points.(point_count curve - 1)
  else
    let total = length curve in
    if total <= 1e-15 then curve.points.(0)
    else
      let rec locate remaining = function
        | [] -> curve.points.(0)
        | segment :: rest ->
            let span = Segment3.length segment in
            if remaining <= span || rest = [] then Segment3.point_at segment
                (if span <= 1e-15 then 0. else remaining /. span)
            else locate (remaining -. span) rest
      in locate (amount *. total) (segments curve)

let sample_uniform ?include_last ~distance curve =
  if not (Float.is_finite distance) || distance <= 0. then
    invalid_arg "Curve3.sample_uniform: distance must be finite and positive";
  let include_last = Option.value include_last ~default:(not curve.closed) in
  let total = length curve in
  let spans = max 1 (int_of_float (ceil (total /. distance))) in
  let count = if include_last then spans + 1 else spans in
  List.init count (fun index -> point_at curve (float_of_int index /. float_of_int spans))

let map operation curve = { curve with points = Array.map operation curve.points }
let transform matrix = map (Mat4.transform_point matrix)
let translate offset = map (Vec3.add offset)
let centroid curve = Array.fold_left Vec3.add Vec3.zero curve.points
    |> fun total -> Vec3.scale total (1. /. float_of_int (point_count curve))
let bounds curve = Bounds3.of_points (points curve) |> Option.get

let rec repeat count operation value = if count = 0 then value else repeat (count-1) operation (operation value)
let validate_iterations name count = if count < 0 then invalid_arg ("Curve3." ^ name ^ ": iterations must be non-negative")
let chaikin_once ratio curve =
  let result = ref [] and count = point_count curve in
  if not curve.closed then result := [curve.points.(0)];
  for index = 0 to segment_count curve - 1 do
    let left = curve.points.(index) and right = curve.points.((index+1) mod count) in
    result := Vec3.lerp left right (1. -. ratio) ::
      Vec3.lerp left right ratio :: !result
  done;
  if not curve.closed then result := curve.points.(count-1) :: !result;
  create_exn ~closed:curve.closed (List.rev !result)
let chaikin ?(iterations = 1) ?(ratio = 0.25) curve =
  validate_iterations "chaikin" iterations;
  if ratio <= 0. || ratio >= 0.5 then invalid_arg "Curve3.chaikin: ratio must be between zero and one half";
  repeat iterations (chaikin_once ratio) curve

let cubic_once curve =
  let count = point_count curve in
  let value index = curve.points.((index + count) mod count) in
  let output = ref [] in
  if not curve.closed then output := [curve.points.(0)];
  for index = 0 to segment_count curve - 1 do
    let current = value index and next = value (index+1) in
    if curve.closed || index + 1 < count - 1 then
      let previous = if curve.closed then value index else current
      and after = value (index+2) in
      output := Vec3.scale (Vec3.add previous
          (Vec3.add (Vec3.scale next 6.) after)) (1. /. 8.) :: !output;
    output := Vec3.lerp current next 0.5 :: !output
  done;
  if not curve.closed then output := curve.points.(count-1) :: !output;
  create_exn ~closed:curve.closed (List.rev !output)
let cubic_subdivide ?(iterations = 1) curve =
  validate_iterations "cubic_subdivide" iterations; repeat iterations cubic_once curve

let validate_resolution name resolution = if resolution < 1 then
    invalid_arg ("Curve3." ^ name ^ ": resolution must be positive")
let quadratic_bezier ?(resolution = 32) ~from_ ~control ~to_ () =
  validate_resolution "quadratic_bezier" resolution;
  List.init (resolution+1) (fun index ->
    let t = float_of_int index /. float_of_int resolution in
    let u = 1. -. t in
    Vec3.add (Vec3.add (Vec3.scale from_ (u*.u))
      (Vec3.scale control (2.*.u*.t))) (Vec3.scale to_ (t*.t))) |> create_exn
let cubic_bezier ?(resolution = 32) ~from_ ~control1 ~control2 ~to_ () =
  validate_resolution "cubic_bezier" resolution;
  List.init (resolution+1) (fun index ->
    let t = float_of_int index /. float_of_int resolution in
    let u = 1. -. t in
    Vec3.add (Vec3.add (Vec3.scale from_ (u*.u*.u))
      (Vec3.scale control1 (3.*.u*.u*.t)))
      (Vec3.add (Vec3.scale control2 (3.*.u*.t*.t))
        (Vec3.scale to_ (t*.t*.t)))) |> create_exn

let catmull_rom ?(closed = false) ?(tension = 0.) ?(resolution = 16) supplied =
  validate_resolution "catmull_rom" resolution;
  let controls = Array.of_list (normalize_points ~closed supplied) in
  let count = Array.length controls and minimum = if closed then 3 else 2 in
  if count < minimum then Error "Curve3.catmull_rom: insufficient distinct controls"
  else
    let get index = if closed then controls.((index mod count + count) mod count)
      else controls.(max 0 (min (count-1) index)) in
    let spans = if closed then count else count-1 and output = ref [] in
    for span = 0 to spans-1 do
      let p0=get(span-1) and p1=get span and p2=get(span+1) and p3=get(span+2) in
      let m1=Vec3.scale (Vec3.sub p2 p0) ((1.-.tension)/.2.)
      and m2=Vec3.scale (Vec3.sub p3 p1) ((1.-.tension)/.2.) in
      for step=0 to resolution-1 do
        let t=float_of_int step/.float_of_int resolution in
        let t2=t*.t and t3=t*.t*.t in
        output := Vec3.add (Vec3.add (Vec3.scale p1 (2.*.t3-.3.*.t2+.1.))
          (Vec3.scale m1 (t3-.2.*.t2+.t)))
          (Vec3.add (Vec3.scale p2 (-.2.*.t3+.3.*.t2))
            (Vec3.scale m2 (t3-.t2))) :: !output
      done
    done;
    if not closed then output := controls.(count-1) :: !output;
    create ~closed (List.rev !output)
