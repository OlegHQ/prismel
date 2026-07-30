(* Graphics module - 2D Drawing API *)

open Tsdl

(* Global state for the graphics module *)
type state = {
  renderer: Sdl.renderer option;
  current_color: Color.t;
  transform_stack: Mat3.t Stack.t;
  current_transform: Mat3.t;
  current_clip: (int * int * int * int) option;
}

let graphics_state = ref {
  renderer = None;
  current_color = Color.white;
  transform_stack = Stack.create ();
  current_transform = Mat3.identity;
  current_clip = None;
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

let draw_transformed_polygon points ~filled color =
  match points with
  | [] | [_] -> ()
  | _ ->
      let renderer = get_renderer () in
      let r, g, b, a = color_to_rgba color in
      let points = List.map transform_point points in
      if filled then
        ignore (Tsdl_gfx.Gfx.filled_polygon_rgba renderer ~ps:points ~r ~g ~b ~a)
      else
        ignore (Tsdl_gfx.Gfx.aapolygon_rgba renderer ~ps:points ~r ~g ~b ~a)

let draw_transformed_polyline points color =
  let renderer = get_renderer () in
  let r, g, b, a = color_to_rgba color in
  let rec lines = function
    | first :: (second :: _ as rest) ->
        let x1, y1 = transform_point first in
        let x2, y2 = transform_point second in
        ignore (Tsdl_gfx.Gfx.aaline_rgba renderer
          ~x1 ~y1 ~x2 ~y2 ~r ~g ~b ~a);
        lines rest
    | _ -> ()
  in
  lines points

let ellipse_points ~center:(cx, cy) ~rx ~ry ~from_ ~to_ ~steps =
  List.init (steps + 1) (fun index ->
    let amount = float_of_int index /. float_of_int steps in
    let angle = from_ +. ((to_ -. from_) *. amount) in
    cx + int_of_float (cos angle *. float_of_int rx),
    cy + int_of_float (sin angle *. float_of_int ry))

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
  let c = get_color ?color () in
  draw_transformed_polygon
    [(x, y); (x + w, y); (x + w, y + h); (x, y + h)]
    ~filled c

(* Draw an antialiased circle using tsdl_gfx *)
let circle ~center:(cx, cy) ~radius ?(filled=true) ?color () =
  let c = get_color ?color () in
  let steps = max 24 (min 128 (radius * 2)) in
  let points =
    ellipse_points ~center:(cx, cy) ~rx:radius ~ry:radius
      ~from_:0. ~to_:(2. *. Float.pi) ~steps
  in
  draw_transformed_polygon points ~filled c

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
  draw_transformed_polygon points ~filled (get_color ?color ())

let fill_contours contours ~rule ~color =
  let renderer = get_renderer () in
  let contours = List.map (List.map transform_point) contours in
  let edges =
    List.concat_map
      (function
        | [] | [_] -> []
        | points ->
            let rec pairs = function
              | first :: (second :: _ as rest) ->
                  (first, second) :: pairs rest
              | _ -> []
            in
            let first = List.hd points and last = List.hd (List.rev points) in
            let edges = pairs points in
            if first = last then edges else (last, first) :: edges)
      contours
  in
  match edges with
  | [] -> ()
  | _ ->
      let min_y, max_y =
        List.fold_left
          (fun (low, high) ((_, y1), (_, y2)) ->
            min low (min y1 y2), max high (max y1 y2))
          (max_int, min_int) edges
      in
      let r, g, b, a = color_to_rgba color in
      let draw y left right =
        let left = int_of_float (Float.ceil left) in
        let right = int_of_float (Float.floor right) in
        if right >= left then
          ignore (Tsdl_gfx.Gfx.hline_rgba renderer
            ~x1:left ~x2:right ~y ~r ~g ~b ~a)
      in
      for y = min_y to max_y - 1 do
        let sample_y = float_of_int y +. 0.5 in
        let crossings =
          List.filter_map
            (fun ((x1, y1), (x2, y2)) ->
              let fy1 = float_of_int y1 and fy2 = float_of_int y2 in
              if (fy1 <= sample_y && sample_y < fy2)
                 || (fy2 <= sample_y && sample_y < fy1)
              then
                let amount = (sample_y -. fy1) /. (fy2 -. fy1) in
                Some
                  (float_of_int x1
                   +. amount *. float_of_int (x2 - x1),
                   if y2 > y1 then 1 else -1)
              else None)
            edges
          |> List.sort (fun (left, _) (right, _) -> Float.compare left right)
        in
        match rule with
        | Path.Even_odd ->
            let rec pairs = function
              | (left, _) :: (right, _) :: rest ->
                  draw y left right;
                  pairs rest
              | _ -> ()
            in
            pairs crossings
        | Path.Non_zero ->
            let rec spans winding previous = function
              | [] -> ()
              | (x, delta) :: rest ->
                  Option.iter
                    (fun left -> if winding <> 0 then draw y left x)
                    previous;
                  spans (winding + delta) (Some x) rest
            in
            spans 0 None crossings
      done

(* Image drawing functions *)
let draw_image image ~pos:(x, y) =
  let renderer = get_renderer () in
  let w, h = Image.get_size image in
  let (tx, ty) = transform_point (x, y) in
  let dst_rect = Sdl.Rect.create ~x:tx ~y:ty ~w ~h in
  ignore (Sdl.render_copy ~dst:dst_rect renderer (Image.Private.get_texture image))

let draw_sub_image image ~src_rect:(sx, sy, sw, sh) ~dst_rect:(dx, dy, dw, dh) =
  let renderer = get_renderer () in
  let src = Sdl.Rect.create ~x:sx ~y:sy ~w:sw ~h:sh in
  let (tdx, tdy) = transform_point (dx, dy) in
  let dst = Sdl.Rect.create ~x:tdx ~y:tdy ~w:dw ~h:dh in
  ignore (Sdl.render_copy ~src ~dst renderer (Image.Private.get_texture image))

(* Extended image drawing with rotation, scaling, and flipping *)
let draw_image_ex image ~pos:(x, y) ?scale ?angle ?center ?flip () =
  let renderer = get_renderer () in
  let w, h = Image.get_size image in
  let (tx, ty) = transform_point (x, y) in
  let matrix = !graphics_state.current_transform in
  let matrix_scale_x = Float.hypot matrix.m11 matrix.m21 in
  let matrix_scale_y = Float.hypot matrix.m12 matrix.m22 in
  let matrix_angle = atan2 matrix.m21 matrix.m11 in
  let scale_factor = match scale with Some s -> s | None -> 1.0 in
  let scaled_w =
    int_of_float (float_of_int w *. scale_factor *. matrix_scale_x)
  in
  let scaled_h =
    int_of_float (float_of_int h *. scale_factor *. matrix_scale_y)
  in
  
  let dst_rect = Sdl.Rect.create ~x:tx ~y:ty ~w:scaled_w ~h:scaled_h in
  
  let center_point = match center with
    | Some (cx, cy) -> Some (Sdl.Point.create ~x:cx ~y:cy)
    | None -> Some (Sdl.Point.create ~x:(scaled_w / 2) ~y:(scaled_h / 2))
  in
  
  let angle =
    matrix_angle +. Option.value ~default:0. angle
  in
  let angle_deg = angle *. 180. /. Float.pi in
  let flip_mode = match flip with Some true -> Sdl.Flip.horizontal | _ -> Sdl.Flip.none in
  
  ignore (Sdl.render_copy_ex ~dst:dst_rect renderer (Image.Private.get_texture image) angle_deg center_point flip_mode)

(* Text rendering *)
let draw_text font ~pos:(x, y) ~text ?color ?wrap ?align () =
  if text <> "" then begin
    let c = get_color ?color () in
    match Font.Private.cached_text ?wrap ?align font text (Font.Blended c) with
    | Ok text_image -> draw_image text_image ~pos:(x, y)
    | Error (`Msg message) -> failwith ("Failed to render text: " ^ message)
  end

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

let get_clip () = !graphics_state.current_clip

let set_clip clip =
  let renderer = get_renderer () in
  let rect =
    Option.map
      (fun (x, y, w, h) -> Sdl.Rect.create ~x ~y ~w:(max 0 w) ~h:(max 0 h))
      clip
  in
  match Sdl.render_set_clip_rect renderer rect with
  | Ok () -> graphics_state := { !graphics_state with current_clip = clip }
  | Error (`Msg message) -> failwith ("Failed to set render clip: " ^ message)

(* Advanced drawing functions *)

(* Draw an antialiased polyline using tsdl_gfx *)
let polyline ~points ?color () =
  draw_transformed_polyline points (get_color ?color ())

(* Draw an antialiased ellipse using tsdl_gfx *)
let ellipse ~center:(cx, cy) ~rx ~ry ?(filled=true) ?color () =
  let c = get_color ?color () in
  let steps = max 24 (min 128 (max rx ry * 2)) in
  let points =
    ellipse_points ~center:(cx, cy) ~rx ~ry
      ~from_:0. ~to_:(2. *. Float.pi) ~steps
  in
  draw_transformed_polygon points ~filled c

(* Draw a rounded rectangle using tsdl_gfx *)
let rounded_rect ~pos:(x, y) ~w ~h ~radius ?(filled=true) ?color () =
  let c = get_color ?color () in
  let clamped_radius = min radius (min (w / 2) (h / 2)) in
  let arc center from_ to_ =
    ellipse_points ~center ~rx:clamped_radius ~ry:clamped_radius
      ~from_ ~to_ ~steps:6
  in
  let points =
    arc (x + clamped_radius, y + clamped_radius) Float.pi
      (1.5 *. Float.pi)
    @ arc (x + w - clamped_radius, y + clamped_radius)
        (1.5 *. Float.pi) (2. *. Float.pi)
    @ arc (x + w - clamped_radius, y + h - clamped_radius)
        0. (0.5 *. Float.pi)
    @ arc (x + clamped_radius, y + h - clamped_radius)
        (0.5 *. Float.pi) Float.pi
  in
  draw_transformed_polygon points ~filled c

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
  let c = get_color ?color () in
  let span = abs_float (end_angle -. start_angle) in
  let steps = max 8 (int_of_float (span *. float_of_int radius /. 4.)) in
  ellipse_points ~center:(cx, cy) ~rx:radius ~ry:radius
    ~from_:start_angle ~to_:end_angle ~steps
  |> fun points -> draw_transformed_polyline points c

(* Draw a pie slice *)
let pie ~center:(cx, cy) ~radius ~start_angle ~end_angle ?(filled=true) ?color () =
  let c = get_color ?color () in
  let span = abs_float (end_angle -. start_angle) in
  let steps = max 8 (int_of_float (span *. float_of_int radius /. 4.)) in
  let points =
    (cx, cy)
    :: ellipse_points ~center:(cx, cy) ~rx:radius ~ry:radius
         ~from_:start_angle ~to_:end_angle ~steps
  in
  draw_transformed_polygon points ~filled c

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
