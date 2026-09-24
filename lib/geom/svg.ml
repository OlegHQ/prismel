open Prismel

type attr = string * string
type element = Node of string * attr list * element list | Text of string

let escape value =
  let buffer = Buffer.create (String.length value) in
  String.iter (function
    | '&' -> Buffer.add_string buffer "&amp;"
    | '<' -> Buffer.add_string buffer "&lt;"
    | '>' -> Buffer.add_string buffer "&gt;"
    | '"' -> Buffer.add_string buffer "&quot;"
    | '\'' -> Buffer.add_string buffer "&apos;"
    | character -> Buffer.add_char buffer character) value;
  Buffer.contents buffer

let number value =
  if not (Float.is_finite value) then invalid_arg "Svg: coordinates must be finite";
  let text = Printf.sprintf "%.6f" value in
  let index = ref (String.length text) in
  while !index > 0 && text.[!index - 1] = '0' do decr index done;
  if !index > 0 && text.[!index - 1] = '.' then decr index;
  let result = String.sub text 0 !index in
  if result = "-0" then "0" else result

let color value =
  if value.Color.a = 255 then
    Printf.sprintf "#%02x%02x%02x" value.r value.g value.b
  else
    Printf.sprintf "rgba(%d,%d,%d,%.6g)" value.r value.g value.b
      (float_of_int value.a /. 255.)

let style ?fill ?stroke ?stroke_width ?opacity () =
  let attributes = [] in
  let attributes = match fill with None -> attributes | Some value -> ("fill", color value) :: attributes in
  let attributes = match stroke with None -> attributes | Some value -> ("stroke", color value) :: attributes in
  let attributes = match stroke_width with None -> attributes | Some value -> ("stroke-width", number value) :: attributes in
  let attributes = match opacity with
    | None -> attributes
    | Some value ->
        if not (Float.is_finite value) || value < 0. || value > 1. then
          invalid_arg "Svg.style: opacity must be in zero to one";
        ("opacity", number value) :: attributes
  in
  List.rev attributes

let transform affine =
  let a,b,c,d,e,f = Affine2.coefficients affine in
  "transform", Printf.sprintf "matrix(%s %s %s %s %s %s)"
    (number a) (number b) (number c) (number d) (number e) (number f)

let valid_name name =
  String.length name > 0 && String.for_all (function
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '-' | ':' -> true
    | _ -> false) name

let element name ?(attrs = []) children =
  if not (valid_name name) then invalid_arg "Svg.element: invalid element name";
  List.iter (fun (name, _) -> if not (valid_name name) then
      invalid_arg "Svg.element: invalid attribute name") attrs;
  Node (name, attrs, children)

let point value = number value.Vec2.x ^ "," ^ number value.y
let points values = String.concat " " (List.map point values)

let text ?(attrs = []) ~at value =
  element "text" ~attrs:(("x", number at.Vec2.x) :: ("y", number at.y) :: attrs)
    [Text value]

let circle ?(attrs = []) value =
  element "circle" ~attrs:(("cx", number value.Circle2.center.x) ::
      ("cy", number value.center.y) :: ("r", number value.radius) :: attrs) []

let ellipse ?(attrs = []) ~center ~rx ~ry () =
  if rx < 0. || ry < 0. then invalid_arg "Svg.ellipse: radii must be non-negative";
  element "ellipse" ~attrs:(("cx", number center.Vec2.x) ::
      ("cy", number center.y) :: ("rx", number rx) :: ("ry", number ry) :: attrs) []

let rect ?(attrs = []) bounds =
  element "rect" ~attrs:(("x", number bounds.Bounds2.min.x) ::
      ("y", number bounds.min.y) :: ("width", number (Bounds2.width bounds)) ::
      ("height", number (Bounds2.height bounds)) :: attrs) []

let line ?(attrs = []) segment =
  element "line" ~attrs:(("x1", number segment.Segment2.a.x) ::
      ("y1", number segment.a.y) :: ("x2", number segment.b.x) ::
      ("y2", number segment.b.y) :: attrs) []

let polyline ?(attrs = []) values =
  element "polyline" ~attrs:(("points", points values) :: attrs) []

let polygon ?(attrs = []) value =
  element "polygon" ~attrs:(("points", points (Polygon2.vertices value)) :: attrs) []

let path ?(attrs = []) value =
  element "path" ~attrs:(("d", Svg_path.to_string value) :: attrs) []

let arc ?(attrs = []) ~center ~radius ~from_angle ~to_angle () =
  if radius.Vec2.x < 0. || radius.y < 0. then
    invalid_arg "Svg.arc: radii must be non-negative";
  let start = Vec2.add center (Vec2.create
      (radius.x *. cos from_angle) (radius.y *. sin from_angle))
  and target = Vec2.add center (Vec2.create
      (radius.x *. cos to_angle) (radius.y *. sin to_angle)) in
  let delta = to_angle -. from_angle in
  let large = if abs_float delta > Float.pi then 1 else 0
  and sweep = if delta >= 0. then 1 else 0 in
  let source = Printf.sprintf "M %.17g %.17g A %.17g %.17g 0 %d %d %.17g %.17g"
      start.x start.y radius.x radius.y large sweep target.x target.y in
  match Svg_path.parse source with
  | Ok value -> path ~attrs value
  | Error message -> invalid_arg message

let image ?(attrs = []) ~at ~width ~height ~href () =
  if width < 0. || height < 0. then invalid_arg "Svg.image: dimensions must be non-negative";
  element "image" ~attrs:(("x",number at.Vec2.x) :: ("y",number at.y) ::
    ("width",number width) :: ("height",number height) :: ("href",href) :: attrs) []

let use ?(attrs = []) ~href () = element "use" ~attrs:(("href",href) :: attrs) []

let group ?(attrs = []) children = element "g" ~attrs children
let defs children = element "defs" children

let stops values =
  List.map (fun (offset, value) ->
    if not (Float.is_finite offset) || offset < 0. || offset > 1. then
      invalid_arg "Svg gradient: stop offset must be in zero to one";
    element "stop" ~attrs:["offset", number (offset *. 100.) ^ "%";
      "stop-color", color value] []) values

let linear_gradient ~id ?(from_ = Vec2.zero) ?(to_ = Vec2.create 1. 0.) values =
  element "linearGradient" ~attrs:["id", id; "x1", number from_.x;
    "y1", number from_.y; "x2", number to_.x; "y2", number to_.y]
    (stops values)

let radial_gradient ~id ?(center = Vec2.create 0.5 0.5) ?(radius = 0.5) values =
  if radius < 0. then invalid_arg "Svg.radial_gradient: radius must be non-negative";
  element "radialGradient" ~attrs:["id", id; "cx", number center.x;
    "cy", number center.y; "r", number radius] (stops values)

let rec serialize buffer = function
  | Text value -> Buffer.add_string buffer (escape value)
  | Node (name, attrs, children) ->
      Buffer.add_char buffer '<'; Buffer.add_string buffer name;
      List.iter (fun (key, value) ->
        Buffer.add_char buffer ' '; Buffer.add_string buffer key;
        Buffer.add_string buffer "=\""; Buffer.add_string buffer (escape value);
        Buffer.add_char buffer '"') attrs;
      if children = [] then Buffer.add_string buffer "/>"
      else begin
        Buffer.add_char buffer '>';
        List.iter (serialize buffer) children;
        Buffer.add_string buffer "</"; Buffer.add_string buffer name;
        Buffer.add_char buffer '>'
      end

let document ?view_box ~width ~height children =
  if width <= 0. || height <= 0. then
    invalid_arg "Svg.document: dimensions must be positive";
  let attrs = ["xmlns", "http://www.w3.org/2000/svg";
    "version", "1.1"; "width", number width; "height", number height] in
  let attrs = match view_box with
    | None -> attrs
    | Some bounds ->
        ("viewBox", String.concat " " [number bounds.Bounds2.min.x;
          number bounds.min.y; number (Bounds2.width bounds);
          number (Bounds2.height bounds)]) :: attrs
  in
  let buffer = Buffer.create 1024 in
  Buffer.add_string buffer "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  serialize buffer (element "svg" ~attrs children);
  Buffer.add_char buffer '\n';
  Buffer.contents buffer

let save ?view_box ~width ~height filename children =
  try
    let channel = open_out_bin filename in
    Fun.protect
      ~finally:(fun () -> close_out_noerr channel)
      (fun () -> output_string channel (document ?view_box ~width ~height children));
    Ok ()
  with Sys_error message -> Error ("Svg.save: " ^ message)
