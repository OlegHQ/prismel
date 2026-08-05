open Prismel

type scale = {
  domain : float * float;
  range : float * float;
  project : float -> float;
  invert : float -> float;
}

type axis = { scale : scale; major : float list; minor : float list }

let domain scale = scale.domain
let range scale = scale.range
let project scale value = scale.project value
let invert scale value = scale.invert value

let validate_interval name (left, right) =
  if not (Float.is_finite left && Float.is_finite right) || left = right then
    invalid_arg (name ^ ": interval endpoints must be finite and distinct")

let map_interval (a,b) (c,d) value = c +. (value -. a) /. (b -. a) *. (d -. c)

let linear_scale ~domain ~range =
  validate_interval "Viz.linear_scale domain" domain;
  validate_interval "Viz.linear_scale range" range;
  { domain; range; project = map_interval domain range;
    invert = map_interval range domain }

let signed_log base value =
  if value > 0. then log value /. log base
  else if value < 0. then -. (log (-. value) /. log base)
  else 0.

let log_scale ?(base = 10.) ~domain ~range () =
  if not (Float.is_finite base) || base <= 0. || base = 1. then
    invalid_arg "Viz.log_scale: base must be positive and not one";
  validate_interval "Viz.log_scale domain" domain;
  validate_interval "Viz.log_scale range" range;
  if fst domain = 0. || snd domain = 0. ||
     Float.sign_bit (fst domain) <> Float.sign_bit (snd domain) then
    invalid_arg "Viz.log_scale: domain must be wholly positive or wholly negative";
  let transformed = signed_log base (fst domain), signed_log base (snd domain) in
  validate_interval "Viz.log_scale transformed domain" transformed;
  { domain; range;
    project = (fun value -> map_interval transformed range (signed_log base value));
    invert = (fun value ->
      let exponent = map_interval range transformed value in
      if fst domain > 0. then base ** exponent else -. (base ** (-. exponent))) }

let lens_unit focus strength value =
  if strength = 0. then value
  else
    let exponent = exp (-. strength *. 2.) in
    if value <= focus then
      if focus <= 1e-12 then 0.
      else focus *. ((value /. focus) ** exponent)
    else if focus >= 1. -. 1e-12 then 1.
    else 1. -. (1. -. focus) *.
                (((1. -. value) /. (1. -. focus)) ** exponent)

let lens_scale ~focus ~strength ~domain ~range =
  validate_interval "Viz.lens_scale domain" domain;
  validate_interval "Viz.lens_scale range" range;
  if not (Float.is_finite focus) || not (Float.is_finite strength) ||
     strength < -1. || strength > 1. then
    invalid_arg "Viz.lens_scale: focus must be finite and strength in minus one to one";
  let focus_unit = map_interval domain (0.,1.) focus in
  if focus_unit < 0. || focus_unit > 1. then
    invalid_arg "Viz.lens_scale: focus must lie in the domain";
  let forward value =
    map_interval (0.,1.) range
      (lens_unit focus_unit strength (map_interval domain (0.,1.) value))
  in
  let inverse value =
    let target = map_interval range (0.,1.) value in
    let low = ref 0. and high = ref 1. in
    for _ = 1 to 56 do
      let middle = (!low +. !high) /. 2. in
      if lens_unit focus_unit strength middle < target then low := middle
      else high := middle
    done;
    map_interval (0.,1.) domain ((!low +. !high) /. 2.)
  in
  { domain; range; project = forward; invert = inverse }

let ticks ~domain:(left,right) ~step =
  if not (Float.is_finite step) || step <= 0. then
    invalid_arg "Viz.ticks: step must be finite and positive";
  let low = min left right and high = max left right in
  let start = ceil (low /. step) *. step in
  let count = max 0 (int_of_float (floor ((high -. start) /. step)) + 1) in
  let values = List.init count (fun index -> start +. float_of_int index *. step) in
  if left <= right then values else List.rev values

let remove_major major minor =
  List.filter (fun value ->
    not (List.exists (fun other -> abs_float (value -. other) <= 1e-10) major)) minor

let make_axis scale major minor = { scale; major; minor = remove_major major minor }

let linear_axis ?major ?minor ~domain ~range () =
  let scale = linear_scale ~domain ~range in
  make_axis scale
    (Option.fold ~none:[] ~some:(fun step -> ticks ~domain ~step) major)
    (Option.fold ~none:[] ~some:(fun step -> ticks ~domain ~step) minor)

let integer_range left right =
  if left > right then [] else List.init (right-left+1) (fun index -> left+index)

let log_axis ?(base = 10.) ~domain ~range () =
  let scale = log_scale ~base ~domain ~range () in
  let low = min (fst domain) (snd domain) and high = max (fst domain) (snd domain) in
  let log_value = signed_log base in
  let transformed_low = min (log_value low) (log_value high)
  and transformed_high = max (log_value low) (log_value high) in
  let first = int_of_float (floor transformed_low)
  and last = int_of_float (ceil transformed_high) in
  let in_domain value = value >= low && value <= high in
  let power exponent =
    if low > 0. then base ** float_of_int exponent
    else -. (base ** (-. float_of_int exponent)) in
  let major = integer_range first last
      |> List.map power
      |> List.filter in_domain in
  let base_int = int_of_float (Float.round base) in
  let minor = if base_int < 3 || abs_float (base -. float_of_int base_int) > 1e-10
    then []
    else integer_range first last |> List.concat_map (fun exponent ->
      integer_range 2 (base_int - 1) |> List.map (fun multiplier ->
        float_of_int multiplier *. power exponent))
      |> List.filter in_domain in
  make_axis scale major minor

let lens_axis ?major ?minor ~focus ~strength ~domain ~range () =
  let scale = lens_scale ~focus ~strength ~domain ~range in
  make_axis scale
    (Option.fold ~none:[] ~some:(fun step -> ticks ~domain ~step) major)
    (Option.fold ~none:[] ~some:(fun step -> ticks ~domain ~step) minor)

let uniform_domain_points ~domain:(left,right) values =
  match values with
  | [] -> []
  | [_] as values -> List.map (fun value -> left, value) values
  | _ ->
      let denominator = float_of_int (List.length values - 1) in
      List.mapi (fun index value ->
        left +. (right -. left) *. float_of_int index /. denominator, value) values

let inside (a,b) value = value >= min a b && value <= max a b

let map_points ~x ~y values =
  values |> List.filter (fun (px,py) -> inside x.domain px && inside y.domain py)
  |> List.sort (fun (a,_) (b,_) -> Float.compare a b)
  |> List.map (fun (px,py) -> Vec2.create (x.project px) (y.project py))

let polar_projection ~origin ~angle ~radius =
  Vec2.add origin (Vec2.create (cos angle *. radius) (sin angle *. radius))

let line_plot ?(attrs = []) ~x ~y values = Svg.polyline ~attrs (map_points ~x ~y values)

let area_plot ?(attrs = []) ?baseline ~x ~y values =
  let points = map_points ~x ~y values in
  match points with
  | [] -> Svg.group []
  | first :: _ ->
      let last = List.hd (List.rev points) in
      let baseline = y.project (Option.value baseline ~default:(fst y.domain)) in
      let polygon = Polygon2.create_exn
          (points @ [Vec2.create last.x baseline; Vec2.create first.x baseline]) in
      Svg.polygon ~attrs polygon

let radar_plot ?(attrs = []) ~origin ~angle ~radius values =
  let points = values
    |> List.filter (fun (a,r) -> inside angle.domain a && inside radius.domain r)
    |> List.sort (fun (a,_) (b,_) -> Float.compare a b)
    |> List.map (fun (a,r) -> polar_projection ~origin
        ~angle:(angle.project a) ~radius:(radius.project r)) in
  match Polygon2.create points with Ok polygon -> Svg.polygon ~attrs polygon
  | Error _ -> Svg.group []

let scatter_plot ?(attrs = []) ?(radius = 3.) ~x ~y values =
  Svg.group ~attrs (map_points ~x ~y values |> List.map (fun center ->
    Svg.circle (Circle2.make ~center ~radius)))

let bar_plot ?(attrs = []) ?baseline ~width ~x ~y values =
  if width < 0. then invalid_arg "Viz.bar_plot: width must be non-negative";
  let baseline = y.project (Option.value baseline ~default:(fst y.domain)) in
  let bars = values |> List.filter (fun (px,py) -> inside x.domain px && inside y.domain py)
    |> List.map (fun (px,py) ->
      let center = x.project px and value = y.project py in
      let bounds = Bounds2.make
          ~min:(Vec2.create (center -. width /. 2.) (min baseline value))
          ~max:(Vec2.create (center +. width /. 2.) (max baseline value)) in
      Svg.rect bounds) in
  Svg.group ~attrs bars

let heatmap ?(attrs = []) ~x ~y ~value_domain:(low,high) ~palette matrix =
  if palette = [] then invalid_arg "Viz.heatmap: palette cannot be empty";
  if Array.length matrix > 0 then begin
    let width = Array.length matrix.(0) in
    if Array.exists (fun row -> Array.length row <> width) matrix then
      invalid_arg "Viz.heatmap: matrix rows must have equal lengths"
  end;
  let colors = Array.of_list palette in
  let color value =
    let amount = max 0. (min 1. ((value -. low) /. (high -. low))) in
    colors.(min (Array.length colors - 1)
      (int_of_float (floor (amount *. float_of_int (Array.length colors)))))
  in
  let cells = Array.to_list matrix |> List.mapi (fun row values ->
    Array.to_list values |> List.mapi (fun column value ->
      let x1 = x.project (float_of_int column)
      and x2 = x.project (float_of_int (column + 1))
      and y1 = y.project (float_of_int row)
      and y2 = y.project (float_of_int (row + 1)) in
      Svg.rect ~attrs:(Svg.style ~fill:(color value) ())
        (Bounds2.make ~min:(Vec2.create (min x1 x2) (min y1 y2))
           ~max:(Vec2.create (max x1 x2) (max y1 y2))))
    ) |> List.concat in
  Svg.group ~attrs cells

let contour_plot ?(attrs = []) ~x ~y ~levels ~palette matrix =
  if palette = [] then invalid_arg "Viz.contour_plot: palette cannot be empty";
  let colors = Array.of_list palette in
  let rec build index elements = function
    | [] -> Ok (Svg.group ~attrs (List.rev elements))
    | level :: rest ->
        Result.bind (Contour2.extract ~iso:level matrix) (fun curves ->
          let color = colors.(min (Array.length colors - 1) index) in
          let paths = List.map (fun curve ->
            let points = Curve2.points curve |> List.map (fun point ->
              Vec2.create (x.project point.Vec2.x) (y.project point.y)) in
            Svg.polyline ~attrs:(Svg.style ~fill:Color.transparent ~stroke:color ()) points)
              curves in
          build (index + 1) (List.rev_append paths elements) rest)
  in
  build 0 [] levels

let overlap (a,b) (c,d) = min a b <= max c d && max a b >= min c d

let stack_intervals ~range values =
  let values = List.sort (fun left right ->
    Float.compare (fst (range left)) (fst (range right))) values in
  let add rows value =
    let interval = range value in
    let rec place before = function
      | [] -> List.rev_append before [[value]]
      | row :: rest ->
          if List.exists (fun other -> overlap interval (range other)) row then
            place (row :: before) rest
          else List.rev_append before ((row @ [value]) :: rest)
    in place [] rows
  in
  List.fold_left add [] values

let axis_lines ?(attrs = []) ~grid x y =
  let x1,x2 = x.scale.range and y1,y2 = y.scale.range in
  let x_ticks = x.major @ (if grid then x.minor else [])
  and y_ticks = y.major @ (if grid then y.minor else []) in
  let lines =
    (List.map (fun value -> let px = x.scale.project value in
       Svg.line (Segment2.make (Vec2.create px y1) (Vec2.create px y2))) x_ticks) @
    (List.map (fun value -> let py = y.scale.project value in
       Svg.line (Segment2.make (Vec2.create x1 py) (Vec2.create x2 py))) y_ticks)
  in Svg.group ~attrs lines

let cartesian_grid ?(attrs = ["stroke", "#cccccc"; "stroke-dasharray", "1 1"])
    ~x ~y () = axis_lines ~attrs ~grid:true x y

let cartesian_axes ?(attrs = ["stroke", "#000000"]) ~x ~y () =
  let x1,x2 = x.scale.range and y1,y2 = y.scale.range in
  Svg.group ~attrs [
    Svg.line (Segment2.make (Vec2.create x1 y1) (Vec2.create x2 y1));
    Svg.line (Segment2.make (Vec2.create x1 y1) (Vec2.create x1 y2));
    axis_lines ~grid:false x y;
  ]

let polar_grid ?(attrs = ["stroke", "#cccccc"; "stroke-dasharray", "1 1"])
    ~origin ~angle ~radius () =
  let inner, outer = radius.scale.range in
  let spokes = angle.major @ angle.minor |> List.map (fun value ->
    let value = angle.scale.project value in
    Svg.line (Segment2.make
      (polar_projection ~origin ~angle:value ~radius:inner)
      (polar_projection ~origin ~angle:value ~radius:outer))) in
  let circles = radius.major @ radius.minor |> List.map (fun value ->
    Svg.circle (Circle2.make ~center:origin ~radius:(abs_float (radius.scale.project value)))) in
  Svg.group ~attrs (spokes @ circles)

let polar_axes ?(attrs = ["stroke", "#000000"; "fill", "none"])
    ?(label_attrs = ["fill", "#000000"; "stroke", "none";
      "font-family", "sans-serif"; "font-size", "10"])
    ~origin ~angle ~radius () =
  let _, outer = radius.scale.range in
  let start_angle, _ = angle.scale.range in
  let baseline = Svg.line (Segment2.make origin
      (polar_projection ~origin ~angle:start_angle ~radius:outer)) in
  let outer_circle = Svg.circle (Circle2.make ~center:origin ~radius:(abs_float outer)) in
  let labels values scale position = List.map (fun value ->
    Svg.text ~attrs:label_attrs ~at:(position (scale.project value))
      (Printf.sprintf "%.6g" value)) values in
  let angle_labels = labels angle.major angle.scale (fun radians ->
    polar_projection ~origin ~angle:radians ~radius:(outer +. 12.)) in
  let radius_labels = labels radius.major radius.scale (fun radial ->
    polar_projection ~origin ~angle:start_angle ~radius:radial) in
  Svg.group ~attrs (baseline :: outer_circle :: angle_labels @ radius_labels)
