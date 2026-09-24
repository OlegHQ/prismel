open Prismel

let round value = int_of_float (Float.round value)
let pair point = round point.Vec2.x, round point.y

let point ?(radius = 2) ?(color = Color.white) position =
  if radius < 0 then
    invalid_arg "Render2.point: radius must be non-negative";
  if radius = 0 then Scene.point ~at:(pair position) ~color ()
  else Scene.circle ~at:(pair position) ~radius ~fill:color ()

let points ?radius ?color values =
  List.map (point ?radius ?color) values |> Scene.group

let segment ?(width = 1) ?(color = Color.white)
    (value : Segment2.t) =
  if width <= 0 then
    invalid_arg "Render2.segment: width must be positive";
  Scene.line ~from_:(pair value.a) ~to_:(pair value.b)
    ~color ~width ()

let segments ?width ?color values =
  List.map (segment ?width ?color) values |> Scene.group

let circle ?fill ?stroke (value : Circle2.t) =
  Scene.circle ~at:(pair value.center) ~radius:(round value.radius)
    ?fill ?stroke ()

let polygon ?fill ?stroke value =
  Scene.polygon (Polygon2.vertices value |> List.map pair)
    ?fill ?stroke ()

let polygons ?fill ?stroke values =
  List.map (polygon ?fill ?stroke) values |> Scene.group

let curve ?width ?color value =
  segments ?width ?color (Curve2.segments value)

let triangle ?fill ?stroke value =
  let a, b, c = Delaunay2.vertices value in
  Scene.triangle (pair a) (pair b) (pair c) ?fill ?stroke ()

let triangles ?fill ?stroke values =
  List.map (triangle ?fill ?stroke) values |> Scene.group

let voronoi ?fill ?stroke ?(sites = false) ?(site_radius = 2)
    ?(site_color = Color.white) cells =
  if site_radius < 0 then
    invalid_arg "Render2.voronoi: site_radius must be non-negative";
  let polygons =
    List.map
      (fun (cell : Delaunay2.cell) ->
        polygon ?fill:(Option.map (fun color -> color cell) fill)
          ?stroke cell.polygon)
      cells
  in
  let sites =
    if sites then
      List.map
        (fun (cell : Delaunay2.cell) ->
          point ~radius:site_radius ~color:site_color cell.site)
        cells
    else []
  in
  Scene.group (polygons @ sites)

let path_of_points ~closed (points : Vec2.t list) =
  match points with
  | [] -> Path.empty
  | first :: rest ->
      let path =
        List.fold_left
          (fun path point ->
            Path.line_to point.Vec2.x point.y path)
          (Path.move_to first.x first.y Path.empty)
          rest
      in
      if closed then Path.close path else path

let path_of_polygon polygon =
  path_of_points ~closed:true (Polygon2.vertices polygon)

let path_of_curve curve =
  path_of_points ~closed:(Curve2.closed curve) (Curve2.points curve)
