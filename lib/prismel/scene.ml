type style = {
  fill : Color.t option;
  stroke : Color.t option;
}

type blend = Replace | Alpha | Add | Multiply

type node =
  | Clear of Color.t
  | Point of (int * int) * Color.t option
  | Line of (int * int) * (int * int) * Color.t option * int
  | Rect of (int * int) * int * int * int option * style
  | Circle of (int * int) * int * style
  | Ellipse of (int * int) * int * int * style
  | Triangle of (int * int) * (int * int) * (int * int) * style
  | Polygon of (int * int) list * style
  | Polyline of (int * int) list * Color.t option
  | Arc of (int * int) * int * float * float * Color.t option
  | Pie of (int * int) * int * float * float * style
  | Bezier of (int * int) list * int * Color.t option
  | Path of Path.t * int * Path.fill_rule * style
  | Text of (int * int) * string * Color.t option * int
  | Debug_text of (int * int) * string * Color.t option
  | Font_text of
      Font.t * (int * int) * string * Color.t option
      * int option * Font.alignment option
  | Image of
      Image.t * (int * int) * float option * float option
      * (int * int) option * bool option
  | View3d of Camera.t * Scene3.t * (int * int * int * int) option
  | Text_input_region of (int * int) * int * int * bool
  | Group of node list
  | Translate of int * int * node list
  | Rotate of float * node list
  | Scale of float * float * node list
  | Clip of (int * int) * int * int * node list
  | Blend of blend * node list

type t = node list

let empty = []
let one node = [node]
let group nodes = Group nodes
let clear color = Clear color
let point ~at ?color () = Point (at, color)
let line ~from_ ~to_ ?color ?(width = 1) () =
  Line (from_, to_, color, max 1 width)

let style ?fill ?stroke () =
  match fill, stroke with
  | None, None -> { fill = Some Color.white; stroke = None }
  | fill, stroke -> { fill; stroke }

let rect ~at ~w ~h ?fill ?stroke () =
  Rect (at, w, h, None, style ?fill ?stroke ())

let square ~at ~size ?fill ?stroke () =
  rect ~at ~w:size ~h:size ?fill ?stroke ()

let rounded_rect ~at ~w ~h ~radius ?fill ?stroke () =
  Rect (at, w, h, Some radius, style ?fill ?stroke ())

let circle ~at ~radius ?fill ?stroke () =
  Circle (at, radius, style ?fill ?stroke ())

let ellipse ~at ~rx ~ry ?fill ?stroke () =
  Ellipse (at, rx, ry, style ?fill ?stroke ())

let triangle p1 p2 p3 ?fill ?stroke () =
  Triangle (p1, p2, p3, style ?fill ?stroke ())

let quad p1 p2 p3 p4 ?fill ?stroke () =
  Polygon ([p1; p2; p3; p4], style ?fill ?stroke ())

let polygon points ?fill ?stroke () =
  Polygon (points, style ?fill ?stroke ())

let polyline points ?color () = Polyline (points, color)
let arc ~at ~radius ~from_ ~to_ ?color () =
  Arc (at, radius, from_, to_, color)

let pie ~at ~radius ~from_ ~to_ ?fill ?stroke () =
  Pie (at, radius, from_, to_, style ?fill ?stroke ())

let bezier points ?(steps = 24) ?color () =
  Bezier (points, max 1 steps, color)

let path ?(steps = 20) ?(fill_rule = Path.Even_odd) ?fill ?stroke value =
  Path (value, max 1 steps, fill_rule, style ?fill ?stroke ())

let text ~at ?color ?(size = 14) value =
  if size <= 0 then invalid_arg "Scene.text: size must be positive";
  Text (at, value, color, size)

let debug_text ~at ?color value = Debug_text (at, value, color)
let font_text font ~at ?color ?wrap ?align value =
  Font_text (font, at, value, color, wrap, align)
let image value ~at ?scale ?angle ?center ?flip_x () =
  Image (value, at, scale, angle, center, flip_x)
let view3d ?viewport ~camera scene = View3d (camera, scene, viewport)
let text_input_region ~at ~w ~h ?(focused = false) () =
  if w <= 0 || h <= 0 then
    invalid_arg "Scene.text_input_region: dimensions must be positive";
  Text_input_region (at, w, h, focused)
let translate x y nodes = Translate (x, y, nodes)
let rotate angle nodes = Rotate (angle, nodes)
let scale x y nodes = Scale (x, y, nodes)
let clip ~at ~w ~h nodes = Clip (at, w, h, nodes)
let blend mode nodes = Blend (mode, nodes)

let rec render_node = function
  | Clear color -> Graphics.clear color
  | Point ((x, y), color) -> Graphics.point ~x ~y ?color ()
  | Line ((x1, y1), (x2, y2), color, width) ->
      if width = 1 then Graphics.line ~x1 ~y1 ~x2 ~y2 ?color ()
      else Graphics.thick_line ~x1 ~y1 ~x2 ~y2 ~width ?color ()
  | Rect (at, w, h, radius, style) ->
      (match style.fill with
       | None -> ()
       | Some color ->
           (match radius with
            | None -> Graphics.rect ~pos:at ~w ~h ~filled:true ~color ()
            | Some radius ->
                Graphics.rounded_rect ~pos:at ~w ~h ~radius ~filled:true
                  ~color ()));
      (match style.stroke with
       | None -> ()
       | Some color ->
           (match radius with
            | None -> Graphics.rect ~pos:at ~w ~h ~filled:false ~color ()
            | Some radius ->
                Graphics.rounded_rect ~pos:at ~w ~h ~radius ~filled:false
                  ~color ()))
  | Circle (at, radius, style) ->
      (match style.fill with
       | None -> ()
       | Some color -> Graphics.circle ~center:at ~radius ~filled:true ~color ());
      (match style.stroke with
       | None -> ()
       | Some color -> Graphics.circle ~center:at ~radius ~filled:false ~color ())
  | Ellipse (at, rx, ry, style) ->
      (match style.fill with
       | None -> ()
       | Some color ->
           Graphics.ellipse ~center:at ~rx ~ry ~filled:true ~color ());
      (match style.stroke with
       | None -> ()
       | Some color ->
           Graphics.ellipse ~center:at ~rx ~ry ~filled:false ~color ())
  | Triangle (p1, p2, p3, style) ->
      (match style.fill with
       | None -> ()
       | Some color -> Graphics.triangle ~p1 ~p2 ~p3 ~filled:true ~color ());
      (match style.stroke with
       | None -> ()
       | Some color -> Graphics.triangle ~p1 ~p2 ~p3 ~filled:false ~color ())
  | Polygon (points, style) ->
      (match style.fill with
       | None -> ()
       | Some color -> Graphics.polygon ~points ~filled:true ~color ());
      (match style.stroke with
       | None -> ()
       | Some color -> Graphics.polygon ~points ~filled:false ~color ())
  | Polyline (points, color) -> Graphics.polyline ~points ?color ()
  | Arc (at, radius, from_, to_, color) ->
      Graphics.arc ~center:at ~radius ~start_angle:from_ ~end_angle:to_ ?color ()
  | Pie (at, radius, from_, to_, style) ->
      (match style.fill with
       | None -> ()
       | Some color ->
           Graphics.pie ~center:at ~radius ~start_angle:from_ ~end_angle:to_
             ~filled:true ~color ());
      (match style.stroke with
       | None -> ()
       | Some color ->
           Graphics.pie ~center:at ~radius ~start_angle:from_ ~end_angle:to_
             ~filled:false ~color ())
  | Bezier (points, steps, color) ->
      Graphics.bezier ~points ~steps ?color ()
  | Path (path, steps, fill_rule, style) ->
      let contours = Path.contours ~steps path in
      Option.iter
        (fun color -> Graphics.fill_contours contours ~rule:fill_rule ~color)
        style.fill;
      Option.iter
        (fun color ->
          List.iter (fun points -> Graphics.polyline ~points ~color ()) contours)
        style.stroke
  | Text (at, value, color, size) ->
      (match Font.system ~size () with
       | Ok font ->
           Graphics.draw_text font ~pos:at ~text:value ?color ()
       | Error _ ->
           Graphics.draw_gfx_text ~pos:at ~text:value ?color ())
  | Debug_text (at, value, color) ->
      Graphics.draw_gfx_text ~pos:at ~text:value ?color ()
  | Font_text (font, at, value, color, wrap, align) ->
      Graphics.draw_text font ~pos:at ~text:value ?color ?wrap ?align ()
  | Image (image, at, scale, angle, center, flip_x) ->
      Graphics.draw_image_ex image ~pos:at ?scale ?angle ?center ?flip:flip_x ()
  | View3d (camera, scene, viewport) ->
      Renderer3d.render ?viewport ~camera scene
  | Text_input_region ((x, y), width, height, focused) ->
      if Window.exists () && Graphics.get_renderer () == Window.get_renderer ()
      then begin
        let corners =
          [ Graphics.transform_point (x, y);
            Graphics.transform_point (x + width, y);
            Graphics.transform_point (x, y + height);
            Graphics.transform_point (x + width, y + height) ] in
        let xs = List.map fst corners and ys = List.map snd corners in
        let left = List.fold_left min max_int xs
        and right = List.fold_left max min_int xs
        and top = List.fold_left min max_int ys
        and bottom = List.fold_left max min_int ys in
        let left, top, right, bottom =
          match Graphics.get_clip () with
          | None -> left, top, right, bottom
          | Some (cx, cy, cw, ch) ->
              max left cx, max top cy,
              min right (cx + cw), min bottom (cy + ch)
        in
        Backend.add_web_text_input_region ~x:left ~y:top
          ~width:(max 0 (right - left)) ~height:(max 0 (bottom - top)) ~focused
      end
  | Group nodes -> List.iter render_node nodes
  | Translate (x, y, nodes) ->
      scoped (fun () -> Graphics.translate ~dx:x ~dy:y) nodes
  | Rotate (angle, nodes) ->
      scoped (fun () -> Graphics.rotate ~angle) nodes
  | Scale (x, y, nodes) ->
      scoped (fun () -> Graphics.scale ~sx:x ~sy:y) nodes
  | Clip ((x, y), width, height, nodes) ->
      let x1, y1 = Graphics.transform_point (x, y) in
      let x2, y2 = Graphics.transform_point (x + width, y + height) in
      let left = min x1 x2 and top = min y1 y2 in
      let clip = left, top, abs (x2 - x1), abs (y2 - y1) in
      scoped_clip clip nodes
  | Blend (mode, nodes) -> scoped_blend mode nodes

and scoped transform nodes =
  Graphics.push_matrix ();
  Fun.protect
    ~finally:Graphics.pop_matrix
    (fun () ->
      transform ();
      List.iter render_node nodes)

and scoped_clip (x, y, width, height) nodes =
  let previous = Graphics.get_clip () in
  let intersection =
    match previous with
    | None -> Some (x, y, width, height)
    | Some (px, py, pw, ph) ->
        let left = max x px and top = max y py in
        let right = min (x + width) (px + pw) in
        let bottom = min (y + height) (py + ph) in
        Some (left, top, max 0 (right - left), max 0 (bottom - top))
  in
  Graphics.set_clip intersection;
  Fun.protect
    ~finally:(fun () -> Graphics.set_clip previous)
    (fun () -> List.iter render_node nodes)

and scoped_blend mode nodes =
  let renderer = Graphics.get_renderer () in
  let previous =
    match Tsdl.Sdl.get_render_draw_blend_mode renderer with
    | Ok mode -> mode
    | Error (`Msg message) ->
        failwith ("Failed to query render blend mode: " ^ message)
  in
  let mode =
    match mode with
    | Replace -> Tsdl.Sdl.Blend.mode_none
    | Alpha -> Tsdl.Sdl.Blend.mode_blend
    | Add -> Tsdl.Sdl.Blend.mode_add
    | Multiply -> Tsdl.Sdl.Blend.mode_mod
  in
  (match Tsdl.Sdl.set_render_draw_blend_mode renderer mode with
   | Error (`Msg message) ->
       failwith ("Failed to set render blend mode: " ^ message)
   | Ok () -> ());
  Fun.protect
    ~finally:(fun () -> ignore (Tsdl.Sdl.set_render_draw_blend_mode renderer previous))
    (fun () -> List.iter render_node nodes)

let render scene =
  if not (Domain.is_main_domain ()) then
    invalid_arg "Scene.render must run on the main domain";
  List.iter render_node scene
