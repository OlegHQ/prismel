open Prismel

type t = {
  points : Vec2.t array;
  closed : bool;
}

let equal_point left right =
  left.Vec2.x = right.Vec2.x && left.y = right.y

let normalize_points ~closed points =
  let points =
    List.fold_left
      (fun result point ->
        match result with
        | previous :: _ when equal_point previous point -> result
        | _ -> point :: result)
      [] points
    |> List.rev
  in
  if closed then
    match points, List.rev points with
    | first :: _, last :: rest when equal_point first last -> List.rev rest
    | _ -> points
  else points

let create ?(closed = false) points =
  let points = normalize_points ~closed points in
  let minimum = if closed then 3 else 2 in
  if List.length points < minimum then
    Error
      (Printf.sprintf
         "Curve2.create: a%s curve requires at least %d distinct points"
         (if closed then " closed" else "n open") minimum)
  else Ok { points = Array.of_list points; closed }

let create_exn ?closed points =
  match create ?closed points with
  | Ok curve -> curve
  | Error message -> invalid_arg message

let points curve = Array.to_list curve.points
let point_count curve = Array.length curve.points
let closed curve = curve.closed

let segment_count curve =
  if curve.closed then point_count curve else point_count curve - 1

let segments curve =
  List.init (segment_count curve) (fun index ->
    Segment2.make curve.points.(index)
      curve.points.((index + 1) mod point_count curve))

let length curve =
  List.fold_left
    (fun total segment -> total +. Segment2.length segment)
    0. (segments curve)

let positive_mod value modulus =
  let value = mod_float value modulus in
  if value < 0. then value +. modulus else value

let point_at curve amount =
  if not (Float.is_finite amount) then
    invalid_arg "Curve2.point_at: amount must be finite";
  let amount =
    if curve.closed then positive_mod amount 1.
    else Float.max 0. (Float.min 1. amount)
  in
  if not curve.closed && amount >= 1. then
    curve.points.(point_count curve - 1)
  else
    let total = length curve in
    if total <= 1e-15 then curve.points.(0)
    else
      let target = amount *. total in
      let rec locate remaining = function
        | [] ->
            if curve.closed then curve.points.(0)
            else curve.points.(point_count curve - 1)
        | segment :: rest ->
            let segment_length = Segment2.length segment in
            if remaining <= segment_length || rest = [] then
              Segment2.point_at segment
                (if segment_length <= 1e-15 then 0.
                 else remaining /. segment_length)
            else locate (remaining -. segment_length) rest
      in
      locate target (segments curve)

let sample_uniform ?include_last ~distance curve =
  if not (Float.is_finite distance) || distance <= 0. then
    invalid_arg
      "Curve2.sample_uniform: distance must be finite and positive";
  let include_last =
    Option.value include_last ~default:(not curve.closed)
  in
  let total = length curve in
  if total <= 1e-15 then [curve.points.(0)]
  else
    let span_count =
      max 1 (int_of_float (Float.ceil (total /. distance)))
    in
    let sample_count =
      if include_last then span_count + 1 else span_count
    in
    List.init sample_count (fun index ->
      point_at curve (float_of_int index /. float_of_int span_count))

let map transform curve =
  { curve with points = Array.map transform curve.points }

let transform affine = map (Affine2.apply affine)
let translate offset = transform (Affine2.translation offset)

let centroid curve =
  let total =
    Array.fold_left Vec2.add Vec2.zero curve.points
  in
  Vec2.scale total (1. /. float_of_int (point_count curve))

let around center local_transform curve =
  let affine =
    Affine2.compose (Affine2.translation center)
      (Affine2.compose local_transform
         (Affine2.translation (Vec2.neg center)))
  in
  transform affine curve

let rotate ?center angle curve =
  let center = Option.value center ~default:(centroid curve) in
  around center (Affine2.rotation angle) curve

let scale ?center amount curve =
  let center = Option.value center ~default:(centroid curve) in
  around center (Affine2.scaling amount) curve

let bounds curve =
  match Bounds2.of_points (points curve) with
  | Some bounds -> bounds
  | None -> assert false

let validate_iterations name iterations =
  if iterations < 0 then
    invalid_arg ("Curve2." ^ name ^ ": iterations must be non-negative")

let rec repeat count operation value =
  if count = 0 then value
  else repeat (count - 1) operation (operation value)

let chaikin_once ratio curve =
  let count = point_count curve in
  let result = ref [] in
  if not curve.closed then result := [curve.points.(0)];
  for index = 0 to segment_count curve - 1 do
    let current = curve.points.(index)
    and next = curve.points.((index + 1) mod count) in
    result := Vec2.lerp current next ratio :: !result;
    result := Vec2.lerp current next (1. -. ratio) :: !result
  done;
  if not curve.closed then
    result := curve.points.(count - 1) :: !result;
  create_exn ~closed:curve.closed (List.rev !result)

let chaikin ?(iterations = 1) ?(ratio = 0.25) curve =
  validate_iterations "chaikin" iterations;
  if not (Float.is_finite ratio) || ratio <= 0. || ratio >= 0.5 then
    invalid_arg
      "Curve2.chaikin: ratio must be finite and between zero and one half";
  repeat iterations (chaikin_once ratio) curve

let cubic_once curve =
  let count = point_count curve in
  if curve.closed then
    let result = ref [] in
    for index = 0 to count - 1 do
      let previous =
        curve.points.((index + count - 1) mod count)
      and current = curve.points.(index)
      and next = curve.points.((index + 1) mod count) in
      let smoothed =
        Vec2.add
          (Vec2.add previous (Vec2.scale current 6.))
          next
        |> Fun.flip Vec2.scale (1. /. 8.)
      in
      result := smoothed :: !result;
      result := Vec2.lerp current next 0.5 :: !result
    done;
    create_exn ~closed:true (List.rev !result)
  else
    let result = ref [curve.points.(0)] in
    for index = 0 to count - 2 do
      let current = curve.points.(index)
      and next = curve.points.(index + 1) in
      result := Vec2.lerp current next 0.5 :: !result;
      if index + 1 < count - 1 then begin
        let after = curve.points.(index + 2) in
        let smoothed =
          Vec2.add
            (Vec2.add current (Vec2.scale next 6.))
            after
          |> Fun.flip Vec2.scale (1. /. 8.)
        in
        result := smoothed :: !result
      end
    done;
    result := curve.points.(count - 1) :: !result;
    create_exn (List.rev !result)

let cubic_subdivide ?(iterations = 1) curve =
  validate_iterations "cubic_subdivide" iterations;
  repeat iterations cubic_once curve

let validate_resolution name minimum resolution =
  if resolution < minimum then
    invalid_arg
      (Printf.sprintf "Curve2.%s: resolution must be at least %d"
         name minimum)

let quadratic_bezier ?(resolution = 32) ~from_ ~control ~to_ () =
  validate_resolution "quadratic_bezier" 1 resolution;
  List.init (resolution + 1) (fun index ->
    let amount = float_of_int index /. float_of_int resolution in
    let inverse = 1. -. amount in
    Vec2.add
      (Vec2.add
         (Vec2.scale from_ (inverse *. inverse))
         (Vec2.scale control (2. *. inverse *. amount)))
      (Vec2.scale to_ (amount *. amount)))
  |> create_exn

let cubic_bezier ?(resolution = 32) ~from_ ~control1 ~control2 ~to_ () =
  validate_resolution "cubic_bezier" 1 resolution;
  List.init (resolution + 1) (fun index ->
    let amount = float_of_int index /. float_of_int resolution in
    let inverse = 1. -. amount in
    Vec2.add
      (Vec2.add
         (Vec2.scale from_ (inverse *. inverse *. inverse))
         (Vec2.scale control1
            (3. *. inverse *. inverse *. amount)))
      (Vec2.add
         (Vec2.scale control2
            (3. *. inverse *. amount *. amount))
         (Vec2.scale to_ (amount *. amount *. amount))))
  |> create_exn

let catmull_rom ?(closed = false) ?(tension = 0.)
    ?(resolution = 16) supplied =
  if not (Float.is_finite tension) then
    invalid_arg "Curve2.catmull_rom: tension must be finite";
  validate_resolution "catmull_rom" 1 resolution;
  let controls = Array.of_list (normalize_points ~closed supplied) in
  let count = Array.length controls in
  let minimum = if closed then 3 else 2 in
  if count < minimum then
    Error
      (Printf.sprintf
         "Curve2.catmull_rom: a%s spline requires at least %d points"
         (if closed then " closed" else "n open") minimum)
  else
    let span_count = if closed then count else count - 1 in
    let get index =
      if closed then
        controls.((index mod count + count) mod count)
      else
        controls.(max 0 (min (count - 1) index))
    in
    let tangent_scale = (1. -. tension) /. 2. in
    let samples = ref [] in
    for span = 0 to span_count - 1 do
      let p0 = get (span - 1)
      and p1 = get span
      and p2 = get (span + 1)
      and p3 = get (span + 2) in
      let m1 = Vec2.scale (Vec2.sub p2 p0) tangent_scale
      and m2 = Vec2.scale (Vec2.sub p3 p1) tangent_scale in
      for step = 0 to resolution - 1 do
        let t = float_of_int step /. float_of_int resolution in
        let t2 = t *. t and t3 = t *. t *. t in
        let h00 = (2. *. t3) -. (3. *. t2) +. 1.
        and h10 = t3 -. (2. *. t2) +. t
        and h01 = (-2. *. t3) +. (3. *. t2)
        and h11 = t3 -. t2 in
        let point =
          Vec2.add
            (Vec2.add (Vec2.scale p1 h00) (Vec2.scale m1 h10))
            (Vec2.add (Vec2.scale p2 h01) (Vec2.scale m2 h11))
        in
        samples := point :: !samples
      done
    done;
    if not closed then
      samples := controls.(count - 1) :: !samples;
    create ~closed (List.rev !samples)

let validate_finite name values =
  if not (List.for_all Float.is_finite values) then
    invalid_arg ("Curve2." ^ name ^ ": parameters must be finite")

let spiral ~center ~start_radius ~end_radius ~turns ~resolution () =
  validate_resolution "spiral" 1 resolution;
  validate_finite "spiral" [start_radius; end_radius; turns];
  List.init (resolution + 1) (fun index ->
    let amount = float_of_int index /. float_of_int resolution in
    let radius =
      start_radius +. ((end_radius -. start_radius) *. amount)
    and angle = amount *. turns *. 2. *. Float.pi in
    Vec2.add center
      (Vec2.create (radius *. cos angle) (radius *. sin angle)))
  |> create_exn

let rose ?(rotation = 0.) ~center ~radius ~petals ~resolution () =
  validate_resolution "rose" 3 resolution;
  validate_finite "rose" [rotation; radius];
  if radius <= 0. then
    invalid_arg "Curve2.rose: radius must be positive";
  if petals <= 0 then
    invalid_arg "Curve2.rose: petals must be positive";
  List.init resolution (fun index ->
    let angle =
      rotation
      +. (float_of_int index /. float_of_int resolution
          *. 2. *. Float.pi)
    in
    let radial = radius *. cos (float_of_int petals *. angle) in
    Vec2.add center
      (Vec2.create (radial *. cos angle) (radial *. sin angle)))
  |> create_exn ~closed:true

let superformula ?(rotation = 0.) ?(a = 1.) ?(b = 1.)
    ~center ~radius ~m ~n1 ~n2 ~n3 ~resolution () =
  validate_resolution "superformula" 3 resolution;
  validate_finite "superformula"
    [rotation; a; b; radius; m; n1; n2; n3];
  if radius <= 0. then
    invalid_arg "Curve2.superformula: radius must be positive";
  if a = 0. || b = 0. || n1 = 0. then
    invalid_arg "Curve2.superformula: a, b, and n1 must be non-zero";
  let point index =
    let angle =
      rotation
      +. (float_of_int index /. float_of_int resolution
          *. 2. *. Float.pi)
    in
    let quarter = m *. angle /. 4. in
    let cosine = abs_float (cos quarter /. a) ** n2
    and sine = abs_float (sin quarter /. b) ** n3 in
    let radial =
      let sum = cosine +. sine in
      if sum <= 1e-15 then 0. else sum ** (-1. /. n1)
    in
    Vec2.add center
      (Vec2.create
         (radius *. radial *. cos angle)
         (radius *. radial *. sin angle))
  in
  List.init resolution point |> create_exn ~closed:true
