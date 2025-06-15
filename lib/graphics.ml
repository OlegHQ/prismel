(* Graphics module - 2D Drawing API *)

open Tsdl

(* Global state for the graphics module *)
type state = {
  renderer: Sdl.renderer option;
  current_color: Color.t;
  transform_stack: Mat3.t Stack.t;
  current_transform: Mat3.t;
}

let graphics_state = ref {
  renderer = None;
  current_color = Color.white;
  transform_stack = Stack.create ();
  current_transform = Mat3.identity;
}

(* Initialize graphics with SDL renderer *)
let init renderer =
  graphics_state := { !graphics_state with renderer = Some renderer }

(* Helper function to get current renderer *)
let get_renderer () =
  match !graphics_state.renderer with
  | Some r -> r
  | None -> failwith "Graphics not initialized"

(* Convert Color.t to SDL RGBA components *)
let color_to_sdl color =
  Color.to_tuple color

(* Helper function to convert Color.t to RGBA components *)
let color_to_rgba color =
  let (r, g, b, a) = Color.to_tuple color in
  (r, g, b, a)



(* Apply current transform to a point *)
let transform_point (x, y) =
  let (tx, ty) = Mat3.transform_point !graphics_state.current_transform (float_of_int x, float_of_int y) in
  (int_of_float tx, int_of_float ty)

(* Clear screen with given color *)
let clear color =
  let renderer = get_renderer () in
  let (r, g, b, a) = color_to_rgba color in
  ignore (Sdl.set_render_draw_color renderer r g b a);
  ignore (Sdl.render_clear renderer)

(* Set current drawing color *)
let set_color color =
  graphics_state := { !graphics_state with current_color = color }

(* Get current color or use provided color *)
let get_color ?color () =
  match color with
  | Some c -> c
  | None -> !graphics_state.current_color

(* Draw a single point using tsdl_gfx *)
let point ~x ~y ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tx, ty) = transform_point (x, y) in
     ignore (Tsdl_gfx.Gfx.pixel_rgba (Obj.magic renderer) ~x:tx ~y:ty ~r ~g ~b ~a)

(* Draw an antialiased line using tsdl_gfx *)
let line ~x1 ~y1 ~x2 ~y2 ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tx1, ty1) = transform_point (x1, y1) in
  let (tx2, ty2) = transform_point (x2, y2) in
  ignore (Tsdl_gfx.Gfx.aaline_rgba renderer ~x1:tx1 ~y1:ty1 ~x2:tx2 ~y2:ty2 ~r ~g ~b ~a)

(* Draw a rectangle using tsdl_gfx optimized functions *)
let rect ~pos:(x, y) ~w ~h ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tx, ty) = transform_point (x, y) in
  let (tx2, ty2) = transform_point (x + w, y + h) in
  
  if filled then
    ignore (Tsdl_gfx.Gfx.box_rgba renderer ~x1:tx ~y1:ty ~x2:tx2 ~y2:ty2 ~r ~g ~b ~a)
  else
    ignore (Tsdl_gfx.Gfx.rectangle_rgba renderer ~x1:tx ~y1:ty ~x2:tx2 ~y2:ty2 ~r ~g ~b ~a)

(* Draw an antialiased circle using tsdl_gfx *)
let circle ~center:(cx, cy) ~radius ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tcx, tcy) = transform_point (cx, cy) in
  
  if filled then
    ignore (Tsdl_gfx.Gfx.filled_circle_rgba renderer ~x:tcx ~y:tcy ~rad:radius ~r ~g ~b ~a)
  else
    ignore (Tsdl_gfx.Gfx.aacircle_rgba renderer ~x:tcx ~y:tcy ~rad:radius ~r ~g ~b ~a)

(* Draw an antialiased triangle using tsdl_gfx *)
let triangle ~p1:(x1, y1) ~p2:(x2, y2) ~p3:(x3, y3) ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tx1, ty1) = transform_point (x1, y1) in
  let (tx2, ty2) = transform_point (x2, y2) in
  let (tx3, ty3) = transform_point (x3, y3) in
  
  if filled then
    ignore (Tsdl_gfx.Gfx.filled_trigon_rgba renderer ~x1:tx1 ~y1:ty1 ~x2:tx2 ~y2:ty2 ~x3:tx3 ~y3:ty3 ~r ~g ~b ~a)
  else
    ignore (Tsdl_gfx.Gfx.aatrigon_rgba renderer ~x1:tx1 ~y1:ty1 ~x2:tx2 ~y2:ty2 ~x3:tx3 ~y3:ty3 ~r ~g ~b ~a)

(* Draw an antialiased polygon using tsdl_gfx *)
let polygon ~points ?(filled=true) ?color () =
  match points with
  | [] | [_] -> () (* Need at least 2 points *)
  | _ ->
    let renderer = get_renderer () in
    let c = get_color ?color () in
    let (r, g, b, a) = color_to_rgba c in
    
    let transformed_points = List.map transform_point points in
    
    if filled then
        ignore (Tsdl_gfx.Gfx.filled_polygon_rgba renderer ~ps:transformed_points ~r ~g ~b ~a)
    else
      ignore (Tsdl_gfx.Gfx.aapolygon_rgba renderer ~ps:transformed_points ~r ~g ~b ~a)

(* Image drawing functions *)
let draw_image image ~pos:(x, y) =
  let renderer = get_renderer () in
  let w, h = Image.get_size image in
  let (tx, ty) = transform_point (x, y) in
  let dst_rect = Sdl.Rect.create ~x:tx ~y:ty ~w ~h in
  ignore (Sdl.render_copy ~dst:dst_rect renderer (Image.get_texture image))

let draw_sub_image image ~src_rect:(sx, sy, sw, sh) ~dst_rect:(dx, dy, dw, dh) =
  let renderer = get_renderer () in
  let src = Sdl.Rect.create ~x:sx ~y:sy ~w:sw ~h:sh in
  let (tdx, tdy) = transform_point (dx, dy) in
  let dst = Sdl.Rect.create ~x:tdx ~y:tdy ~w:dw ~h:dh in
  ignore (Sdl.render_copy ~src ~dst renderer (Image.get_texture image))

(* Extended image drawing with rotation, scaling, and flipping *)
let draw_image_ex image ~pos:(x, y) ?scale ?angle ?center ?flip () =
  let renderer = get_renderer () in
  let w, h = Image.get_size image in
  let (tx, ty) = transform_point (x, y) in
  
  let scale_factor = match scale with Some s -> s | None -> 1.0 in
  let scaled_w = int_of_float (float_of_int w *. scale_factor) in
  let scaled_h = int_of_float (float_of_int h *. scale_factor) in
  
  let dst_rect = Sdl.Rect.create ~x:tx ~y:ty ~w:scaled_w ~h:scaled_h in
  
  let center_point = match center with
    | Some (cx, cy) -> Some (Sdl.Point.create ~x:cx ~y:cy)
    | None -> Some (Sdl.Point.create ~x:(scaled_w / 2) ~y:(scaled_h / 2))
  in
  
  let angle_deg = match angle with Some a -> a | None -> 0.0 in
  let flip_mode = match flip with Some true -> Sdl.Flip.horizontal | _ -> Sdl.Flip.none in
  
  ignore (Sdl.render_copy_ex ~dst:dst_rect renderer (Image.get_texture image) angle_deg center_point flip_mode)

(* Text rendering *)
let draw_text font ~pos:(x, y) ~text ?color () =
  let c = get_color ?color () in
  match Font.render_text font text (Font.Blended c) with
  | Ok text_image -> draw_image text_image ~pos:(x, y)
  | Error _ -> () (* Silently ignore text rendering errors *)

(* Matrix transformation functions *)
let push_matrix () =
  Stack.push !graphics_state.current_transform !graphics_state.transform_stack

let pop_matrix () =
  if not (Stack.is_empty !graphics_state.transform_stack) then
    graphics_state := { !graphics_state with 
      current_transform = Stack.pop !graphics_state.transform_stack }

let translate ~dx ~dy =
  let translation = Mat3.translation (float_of_int dx) (float_of_int dy) in
  graphics_state := { !graphics_state with 
    current_transform = Mat3.mul !graphics_state.current_transform translation }

let rotate ~angle =
  let rotation = Mat3.rotation angle in
  graphics_state := { !graphics_state with 
    current_transform = Mat3.mul !graphics_state.current_transform rotation }

let scale ~sx ~sy =
  let scaling = Mat3.scale sx sy in
  graphics_state := { !graphics_state with 
    current_transform = Mat3.mul !graphics_state.current_transform scaling }

let reset_transform () =
  graphics_state := { !graphics_state with current_transform = Mat3.identity }

(* Advanced drawing functions *)

(* Draw an antialiased polyline using tsdl_gfx *)
let polyline ~points ?color () =
  match points with
  | [] | [_] -> () (* Need at least 2 points *)
  | _ ->
    let renderer = get_renderer () in
    let c = get_color ?color () in
    let (r, g, b, a) = color_to_rgba c in
    
    let transformed_points = List.map transform_point points in
    let rec draw_lines = function
      | [] | [_] -> ()
      | (x1, y1) :: ((x2, y2) :: _ as rest) ->
        ignore (Tsdl_gfx.Gfx.aaline_rgba renderer ~x1 ~y1 ~x2 ~y2 ~r ~g ~b ~a);
        draw_lines rest
    in
    draw_lines transformed_points

(* Draw an antialiased ellipse using tsdl_gfx *)
let ellipse ~center:(cx, cy) ~rx ~ry ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tcx, tcy) = transform_point (cx, cy) in
  
  if filled then
    ignore (Tsdl_gfx.Gfx.filled_ellipse_rgba renderer ~x:tcx ~y:tcy ~rx ~ry ~r ~g ~b ~a)
  else
    ignore (Tsdl_gfx.Gfx.aaellipse_rgba renderer ~x:tcx ~y:tcy ~rx ~ry ~r ~g ~b ~a)

(* Draw a rounded rectangle using tsdl_gfx *)
let rounded_rect ~pos:(x, y) ~w ~h ~radius ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tx, ty) = transform_point (x, y) in
  let (tx2, ty2) = transform_point (x + w, y + h) in
  let clamped_radius = min radius (min (w / 2) (h / 2)) in
  
  if filled then
    ignore (Tsdl_gfx.Gfx.rounded_box_rgba renderer ~x1:tx ~y1:ty ~x2:tx2 ~y2:ty2 ~rad:clamped_radius ~r ~g ~b ~a)
  else
    ignore (Tsdl_gfx.Gfx.rounded_rectangle_rgba renderer ~x1:tx ~y1:ty ~x2:tx2 ~y2:ty2 ~rad:clamped_radius ~r ~g ~b ~a)

(* Additional tsdl_gfx specific functions *)

(* Draw a thick antialiased line *)
let thick_line ~x1 ~y1 ~x2 ~y2 ~width ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tx1, ty1) = transform_point (x1, y1) in
  let (tx2, ty2) = transform_point (x2, y2) in
  ignore (Tsdl_gfx.Gfx.thick_line_rgba renderer ~x1:tx1 ~y1:ty1 ~x2:tx2 ~y2:ty2 ~width ~r ~g ~b ~a)

(* Draw an arc *)
let arc ~center:(cx, cy) ~radius ~start_angle ~end_angle ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tcx, tcy) = transform_point (cx, cy) in
  let start_deg = int_of_float (start_angle *. 180.0 /. Math.pi) in
  let end_deg = int_of_float (end_angle *. 180.0 /. Math.pi) in
  ignore (Tsdl_gfx.Gfx.arc_rgba renderer ~x:tcx ~y:tcy ~rad:radius ~start:start_deg ~end_:end_deg ~r ~g ~b ~a)

(* Draw a pie slice *)
let pie ~center:(cx, cy) ~radius ~start_angle ~end_angle ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tcx, tcy) = transform_point (cx, cy) in
  let start_deg = int_of_float (start_angle *. 180.0 /. Math.pi) in
  let end_deg = int_of_float (end_angle *. 180.0 /. Math.pi) in
  
  if filled then
    ignore (Tsdl_gfx.Gfx.filled_pie_rgba renderer ~x:tcx ~y:tcy ~rad:radius ~start:start_deg ~end_:end_deg ~r ~g ~b ~a)
  else
    ignore (Tsdl_gfx.Gfx.pie_rgba renderer ~x:tcx ~y:tcy ~rad:radius ~start:start_deg ~end_:end_deg ~r ~g ~b ~a)

(* Draw a Bezier curve *)
let bezier ~points ~steps ?color () =
  match points with
  | [] -> ()
  | _ ->
    let renderer = get_renderer () in
    let c = get_color ?color () in
    let (r, g, b, a) = color_to_rgba c in
    
    let transformed_points = List.map transform_point points in
    ignore (Tsdl_gfx.Gfx.bezier_rgba renderer ~ps:transformed_points ~s:steps ~r ~g ~b ~a)

(* Draw text using built-in font from tsdl_gfx *)
let draw_gfx_text ~pos:(x, y) ~text ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_rgba c in
  let (tx, ty) = transform_point (x, y) in
  ignore (Tsdl_gfx.Gfx.string_rgba renderer ~x:tx ~y:ty ~s:text ~r ~g ~b ~a)

(* Set font rotation for gfx text (0=0°, 1=90°, 2=180°, 3=270°) *)
let set_gfx_font_rotation rotation =
  Tsdl_gfx.Gfx.set_font_rotation ~rot:rotation
