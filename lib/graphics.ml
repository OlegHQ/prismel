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

(* Helper function to convert Color.t to SDL color *)
let color_to_sdl color =
  let (r, g, b, a) = Color.to_tuple color in
  (r, g, b, a)

(* Apply current transform to a point *)
let transform_point (x, y) =
  let (tx, ty) = Mat3.transform_point !graphics_state.current_transform (float_of_int x, float_of_int y) in
  (int_of_float tx, int_of_float ty)

(* Clear screen with given color *)
let clear color =
  let renderer = get_renderer () in
  let (r, g, b, a) = color_to_sdl color in
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

(* Draw a single point *)
let point ~x ~y ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_sdl c in
  let (tx, ty) = transform_point (x, y) in
  ignore (Sdl.set_render_draw_color renderer r g b a);
  ignore (Sdl.render_draw_point renderer tx ty)

(* Draw a line *)
let line ~x1 ~y1 ~x2 ~y2 ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_sdl c in
  let (tx1, ty1) = transform_point (x1, y1) in
  let (tx2, ty2) = transform_point (x2, y2) in
  ignore (Sdl.set_render_draw_color renderer r g b a);
  ignore (Sdl.render_draw_line renderer tx1 ty1 tx2 ty2)

(* Draw a rectangle *)
let rect ~pos:(x, y) ~w ~h ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_sdl c in
  
  if filled then
    (* For filled rectangles with transforms, draw as multiple lines *)
    (* let corners = [
      (x, y); (x + w, y); (x + w, y + h); (x, y + h)
    ] in
    let transformed_corners = List.map transform_point corners in *)
    
    (* Simple approach: draw filled rect by drawing horizontal lines *)
    let (tx, ty) = transform_point (x, y) in
    let (tw, th) = transform_point (x + w, y + h) in
    let rect = Sdl.Rect.create ~x:tx ~y:ty ~w:(tw - tx) ~h:(th - ty) in
    ignore (Sdl.set_render_draw_color renderer r g b a);
    ignore (Sdl.render_fill_rect renderer (Some rect))
  else
    (* Draw rectangle outline *)
    ignore (Sdl.set_render_draw_color renderer r g b a);
    let corners = [
      (x, y); (x + w, y); (x + w, y + h); (x, y + h); (x, y)
    ] in
    let rec draw_lines = function
      | [] | [_] -> ()
      | (x1, y1) :: ((x2, y2) :: _ as rest) ->
        let (tx1, ty1) = transform_point (x1, y1) in
        let (tx2, ty2) = transform_point (x2, y2) in
        ignore (Sdl.render_draw_line renderer tx1 ty1 tx2 ty2);
        draw_lines rest
    in
    draw_lines corners

(* Helper function to draw circle using midpoint circle algorithm *)
let circle ~center:(cx, cy) ~radius ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_sdl c in
  ignore (Sdl.set_render_draw_color renderer r g b a);
  let (tcx, tcy) = transform_point (cx, cy) in
  
  if filled then
    (* Draw filled circle by drawing horizontal lines *)
    for y = -radius to radius do
      let x_width = int_of_float (sqrt (float_of_int (radius * radius - y * y))) in
      for x = -x_width to x_width do
        ignore (Sdl.render_draw_point renderer (tcx + x) (tcy + y))
      done
    done
  else
    (* Draw circle outline using midpoint circle algorithm *)
    let  draw_circle_points x y =
      let points = [
        (tcx + x, tcy + y); (tcx - x, tcy + y); (tcx + x, tcy - y); (tcx - x, tcy - y);
        (tcx + y, tcy + x); (tcx - y, tcy + x); (tcx + y, tcy - x); (tcx - y, tcy - x)
      ] in
      List.iter (fun (px, py) -> ignore (Sdl.render_draw_point renderer px py)) points
    in
    
    let rec midpoint_circle x y p =
      if x <= y then begin
        draw_circle_points x y;
        if p < 0 then
          midpoint_circle (x + 1) y (p + 2 * x + 3)
        else
          midpoint_circle (x + 1) (y - 1) (p + 2 * (x - y) + 5)
      end
    in
    midpoint_circle 0 radius (1 - radius)

(* Draw a triangle *)
let triangle ~p1:(x1, y1) ~p2:(x2, y2) ~p3:(x3, y3) ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_sdl c in
  ignore (Sdl.set_render_draw_color renderer r g b a);
  let (tx1, ty1) = transform_point (x1, y1) in
  let (tx2, ty2) = transform_point (x2, y2) in
  let (tx3, ty3) = transform_point (x3, y3) in
  
  if filled then
    (* Simple triangle fill - draw lines between vertices *)
    (* This is a simplified approach, could be improved with proper scanline fill *)
    (ignore (Sdl.render_draw_line renderer tx1 ty1 tx2 ty2);
    ignore (Sdl.render_draw_line renderer tx2 ty2 tx3 ty3);
    ignore (Sdl.render_draw_line renderer tx3 ty3 tx1 ty1))
  else
    (* Draw triangle outline *)
    ignore (Sdl.render_draw_line renderer tx1 ty1 tx2 ty2);
    ignore (Sdl.render_draw_line renderer tx2 ty2 tx3 ty3);
    ignore (Sdl.render_draw_line renderer tx3 ty3 tx1 ty1)

(* Draw a polygon *)
let polygon ~points ?(filled=true) ?color () =
  match points with
  | [] | [_] -> () (* Need at least 2 points *)
  | _ ->
    let renderer = get_renderer () in
    let c = get_color ?color () in
    let (r, g, b, a) = color_to_sdl c in
    ignore (Sdl.set_render_draw_color renderer r g b a);
    
    let transformed_points = List.map transform_point points in
    
    if filled then
      (* Simple polygon fill - just draw outline for now *)
      (* Proper polygon filling would require triangulation *)
      let rec draw_edges = function
        | [] | [_] -> ()
        | (x1, y1) :: ((x2, y2) :: _ as rest) ->
          ignore (Sdl.render_draw_line renderer x1 y1 x2 y2);
          draw_edges rest
      in
      draw_edges transformed_points;
      (* Close the polygon *)
      match transformed_points with
      | first :: _ ->
        let last = List.fold_left (fun _ p -> p) first transformed_points in
        let (x1, y1) = last and (x2, y2) = first in
        ignore (Sdl.render_draw_line renderer x1 y1 x2 y2)
      | [] -> ()
    else
      (* Draw polygon outline *)
      let rec draw_edges = function
        | [] | [_] -> ()
        | (x1, y1) :: ((x2, y2) :: _ as rest) ->
          ignore (Sdl.render_draw_line renderer x1 y1 x2 y2);
          draw_edges rest
      in
      draw_edges transformed_points;
      (* Close the polygon *)
      match transformed_points with
      | first :: _ ->
        let last = List.fold_left (fun _ p -> p) first transformed_points in
        let (x1, y1) = last and (x2, y2) = first in
        ignore (Sdl.render_draw_line renderer x1 y1 x2 y2)
      | [] -> ()

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

(* Draw a polyline (connected lines) *)
let polyline ~points ?color () =
  match points with
  | [] | [_] -> () (* Need at least 2 points *)
  | _ ->
    let renderer = get_renderer () in
    let c = get_color ?color () in
    let (r, g, b, a) = color_to_sdl c in
    ignore (Sdl.set_render_draw_color renderer r g b a);
    
    let transformed_points = List.map transform_point points in
    let rec draw_lines = function
      | [] | [_] -> ()
      | (x1, y1) :: ((x2, y2) :: _ as rest) ->
        ignore (Sdl.render_draw_line renderer x1 y1 x2 y2);
        draw_lines rest
    in
    draw_lines transformed_points

(* Draw an ellipse (approximated using lines) *)
let ellipse ~center:(cx, cy) ~rx ~ry ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_sdl c in
  ignore (Sdl.set_render_draw_color renderer r g b a);
  
  let (tcx, tcy) = transform_point (cx, cy) in
  let segments = max 16 (rx + ry) in (* More segments for larger ellipses *)
  
  if filled then
    (* Draw filled ellipse by drawing horizontal lines *)
    for y = -ry to ry do
      let x_width = int_of_float (float_of_int rx *. sqrt (1.0 -. (float_of_int y /. float_of_int ry) ** 2.0)) in
      for x = -x_width to x_width do
        ignore (Sdl.render_draw_point renderer (tcx + x) (tcy + y))
      done
    done
  else
    (* Draw ellipse outline using parametric equations *)
    let points = ref [] in
    for i = 0 to segments do
      let angle = 2.0 *. Math.pi *. float_of_int i /. float_of_int segments in
      let x = tcx + int_of_float (float_of_int rx *. cos angle) in
      let y = tcy + int_of_float (float_of_int ry *. sin angle) in
      points := (x, y) :: !points
    done;
    let points = List.rev !points in
    let rec draw_lines = function
      | [] | [_] -> ()
      | (x1, y1) :: ((x2, y2) :: _ as rest) ->
        ignore (Sdl.render_draw_line renderer x1 y1 x2 y2);
        draw_lines rest
    in
    draw_lines points

(* Draw a rounded rectangle *)
let rounded_rect ~pos:(x, y) ~w ~h ~radius ?(filled=true) ?color () =
  let renderer = get_renderer () in
  let c = get_color ?color () in
  let (r, g, b, a) = color_to_sdl c in
  ignore (Sdl.set_render_draw_color renderer r g b a);
  
  let clamped_radius = min radius (min (w / 2) (h / 2)) in
  
  if filled then
    ((* Draw filled rounded rectangle *)
    (* Main rectangle *)
    rect ~pos:(x, y + clamped_radius) ~w ~h:(h - 2 * clamped_radius) ~filled:true ~color:c ();
    rect ~pos:(x + clamped_radius, y) ~w:(w - 2 * clamped_radius) ~h ~filled:true ~color:c ();
    
    (* Corner circles *)
    circle ~center:(x + clamped_radius, y + clamped_radius) ~radius:clamped_radius ~filled:true ~color:c ();
    circle ~center:(x + w - clamped_radius, y + clamped_radius) ~radius:clamped_radius ~filled:true ~color:c ();
    circle ~center:(x + clamped_radius, y + h - clamped_radius) ~radius:clamped_radius ~filled:true ~color:c ();
    circle ~center:(x + w - clamped_radius, y + h - clamped_radius) ~radius:clamped_radius ~filled:true ~color:c ())
  else
    (* Draw rounded rectangle outline *)
    (* Straight lines *)
    line ~x1:(x + clamped_radius) ~y1:y ~x2:(x + w - clamped_radius) ~y2:y ~color:c ();
    line ~x1:(x + w) ~y1:(y + clamped_radius) ~x2:(x + w) ~y2:(y + h - clamped_radius) ~color:c ();
    line ~x1:(x + w - clamped_radius) ~y1:(y + h) ~x2:(x + clamped_radius) ~y2:(y + h) ~color:c ();
    line ~x1:x ~y1:(y + h - clamped_radius) ~x2:x ~y2:(y + clamped_radius) ~color:c ();
    
    (* Corner circles *)
    circle ~center:(x + clamped_radius, y + clamped_radius) ~radius:clamped_radius ~filled:false ~color:c ();
    circle ~center:(x + w - clamped_radius, y + clamped_radius) ~radius:clamped_radius ~filled:false ~color:c ();
    circle ~center:(x + clamped_radius, y + h - clamped_radius) ~radius:clamped_radius ~filled:false ~color:c ();
    circle ~center:(x + w - clamped_radius, y + h - clamped_radius) ~radius:clamped_radius ~filled:false ~color:c ()
