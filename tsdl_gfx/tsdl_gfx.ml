(** OCaml bindings for SDL2_gfx library *)

(* Use Tsdl types directly *)
open Tsdl

(** {1 Version information} *)

let version_major = 1
let version_minor = 0  
let version_micro = 4

(** {1 Framerate management} *)

(** Framerate manager structure *)
type fps_manager = {
  mutable framecount : int;
  mutable rateticks : float;
  mutable baseticks : int;
  mutable lastticks : int;
  mutable rate : int;
}

(** Framerate constants *)
let fps_upper_limit = 200
let fps_lower_limit = 1
let fps_default = 30

(** External C bindings for framerate management *)
external sdl_init_framerate : fps_manager -> unit = "caml_SDL_initFramerate"
external sdl_set_framerate : fps_manager -> int -> int = "caml_SDL_setFramerate"
external sdl_get_framerate : fps_manager -> int = "caml_SDL_getFramerate"
external sdl_get_framecount : fps_manager -> int = "caml_SDL_getFramecount"
external sdl_framerate_delay : fps_manager -> int = "caml_SDL_framerateDelay"

let init_framerate manager = sdl_init_framerate manager
let set_framerate manager rate = sdl_set_framerate manager rate
let get_framerate manager = sdl_get_framerate manager
let get_framecount manager = sdl_get_framecount manager
let framerate_delay manager = sdl_framerate_delay manager

let create_fps_manager () = {
  framecount = 0;
  rateticks = 0.0;
  baseticks = 0;
  lastticks = 0;
  rate = fps_default;
}

(** {1 Graphics Primitives} *)

(** {2 Pixel operations} *)

external sdl_pixel_color : Sdl.renderer -> int -> int -> int32 -> int = "caml_pixelColor"
external sdl_pixel_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int = "caml_pixelRGBA_byte" "caml_pixelRGBA"

let pixel_color renderer x y color = sdl_pixel_color renderer x y color
let pixel_rgba renderer x y r g b a = sdl_pixel_rgba renderer x y r g b a

(** {2 Line operations} *)

external sdl_hline_color : Sdl.renderer -> int -> int -> int -> int32 -> int = "caml_hlineColor"
external sdl_hline_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int = "caml_hlineRGBA_byte" "caml_hlineRGBA"
external sdl_vline_color : Sdl.renderer -> int -> int -> int -> int32 -> int = "caml_vlineColor"
external sdl_vline_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int = "caml_vlineRGBA_byte" "caml_vlineRGBA"
external sdl_line_color : Sdl.renderer -> int -> int -> int -> int -> int32 -> int = "caml_lineColor_bytecode" "caml_lineColor"
external sdl_line_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_lineRGBA_byte" "caml_lineRGBA"
external sdl_aaline_color : Sdl.renderer -> int -> int -> int -> int -> int32 -> int = "caml_aalineColor_bytecode" "caml_aalineColor"
external sdl_aaline_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_aalineRGBA_byte" "caml_aalineRGBA"
external sdl_thick_line_color : Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int = "caml_thickLineColor_byte" "caml_thickLineColor"
external sdl_thick_line_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_thickLineRGBA_byte" "caml_thickLineRGBA"

let hline_color renderer x1 x2 y color = sdl_hline_color renderer x1 x2 y color
let hline_rgba renderer x1 x2 y r g b a = sdl_hline_rgba renderer x1 x2 y r g b a
let vline_color renderer x y1 y2 color = sdl_vline_color renderer x y1 y2 color
let vline_rgba renderer x y1 y2 r g b a = sdl_vline_rgba renderer x y1 y2 r g b a
let line_color renderer x1 y1 x2 y2 color = sdl_line_color renderer x1 y1 x2 y2 color
let line_rgba renderer x1 y1 x2 y2 r g b a = sdl_line_rgba renderer x1 y1 x2 y2 r g b a
let aaline_color renderer x1 y1 x2 y2 color = sdl_aaline_color renderer x1 y1 x2 y2 color
let aaline_rgba renderer x1 y1 x2 y2 r g b a = sdl_aaline_rgba renderer x1 y1 x2 y2 r g b a
let thick_line_color renderer x1 y1 x2 y2 width color = sdl_thick_line_color renderer x1 y1 x2 y2 width color
let thick_line_rgba renderer x1 y1 x2 y2 width r g b a = sdl_thick_line_rgba renderer x1 y1 x2 y2 width r g b a

(** {2 Rectangle operations} *)

external sdl_rectangle_color : Sdl.renderer -> int -> int -> int -> int -> int32 -> int = "caml_rectangleColor_byte" "caml_rectangleColor"
external sdl_rectangle_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_rectangleRGBA_byte" "caml_rectangleRGBA"
external sdl_rounded_rectangle_color : Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int = "caml_roundedRectangleColor_byte" "caml_roundedRectangleColor"
external sdl_rounded_rectangle_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_roundedRectangleRGBA_byte" "caml_roundedRectangleRGBA"
external sdl_box_color : Sdl.renderer -> int -> int -> int -> int -> int32 -> int = "caml_boxColor_byte" "caml_boxColor"
external sdl_box_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_boxRGBA_byte" "caml_boxRGBA"
external sdl_rounded_box_color : Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int = "caml_roundedBoxColor_byte" "caml_roundedBoxColor"
external sdl_rounded_box_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_roundedBoxRGBA_byte" "caml_roundedBoxRGBA"

let rectangle_color renderer x1 y1 x2 y2 color = sdl_rectangle_color renderer x1 y1 x2 y2 color
let rectangle_rgba renderer x1 y1 x2 y2 r g b a = sdl_rectangle_rgba renderer x1 y1 x2 y2 r g b a
let rounded_rectangle_color renderer x1 y1 x2 y2 rad color = sdl_rounded_rectangle_color renderer x1 y1 x2 y2 rad color
let rounded_rectangle_rgba renderer x1 y1 x2 y2 rad r g b a = sdl_rounded_rectangle_rgba renderer x1 y1 x2 y2 rad r g b a
let box_color renderer x1 y1 x2 y2 color = sdl_box_color renderer x1 y1 x2 y2 color
let box_rgba renderer x1 y1 x2 y2 r g b a = sdl_box_rgba renderer x1 y1 x2 y2 r g b a
let rounded_box_color renderer x1 y1 x2 y2 rad color = sdl_rounded_box_color renderer x1 y1 x2 y2 rad color
let rounded_box_rgba renderer x1 y1 x2 y2 rad r g b a = sdl_rounded_box_rgba renderer x1 y1 x2 y2 rad r g b a

(** {2 Circle operations} *)

external sdl_circle_color : Sdl.renderer -> int -> int -> int -> int32 -> int = "caml_circleColor"
external sdl_circle_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int = "caml_circleRGBA_byte" "caml_circleRGBA"
external sdl_aacircle_color : Sdl.renderer -> int -> int -> int -> int32 -> int = "caml_aacircleColor"
external sdl_aacircle_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int = "caml_aacircleRGBA_byte" "caml_aacircleRGBA"
external sdl_filled_circle_color : Sdl.renderer -> int -> int -> int -> int32 -> int = "caml_filledCircleColor"
external sdl_filled_circle_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int = "caml_filledCircleRGBA_byte" "caml_filledCircleRGBA"

let circle_color renderer x y rad color = sdl_circle_color renderer x y rad color
let circle_rgba renderer x y rad r g b a = sdl_circle_rgba renderer x y rad r g b a
let aacircle_color renderer x y rad color = sdl_aacircle_color renderer x y rad color
let aacircle_rgba renderer x y rad r g b a = sdl_aacircle_rgba renderer x y rad r g b a
let filled_circle_color renderer x y rad color = sdl_filled_circle_color renderer x y rad color
let filled_circle_rgba renderer x y rad r g b a = sdl_filled_circle_rgba renderer x y rad r g b a

(** {2 Arc operations} *)

external sdl_arc_color : Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int = "caml_arcColor_byte" "caml_arcColor"
external sdl_arc_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_arcRGBA_byte" "caml_arcRGBA"

let arc_color renderer x y rad start end_ color = sdl_arc_color renderer x y rad start end_ color
let arc_rgba renderer x y rad start end_ r g b a = sdl_arc_rgba renderer x y rad start end_ r g b a

(** {2 Ellipse operations} *)

external sdl_ellipse_color : Sdl.renderer -> int -> int -> int -> int -> int32 -> int = "caml_ellipseColor_bytecode" "caml_ellipseColor"
external sdl_ellipse_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_ellipseRGBA_byte" "caml_ellipseRGBA"
external sdl_aaellipse_color : Sdl.renderer -> int -> int -> int -> int -> int32 -> int = "caml_aaellipseColor_bytecode" "caml_aaellipseColor"
external sdl_aaellipse_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_aaellipseRGBA_byte" "caml_aaellipseRGBA"
external sdl_filled_ellipse_color : Sdl.renderer -> int -> int -> int -> int -> int32 -> int = "caml_filledEllipseColor_bytecode" "caml_filledEllipseColor"
external sdl_filled_ellipse_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_filledEllipseRGBA_byte" "caml_filledEllipseRGBA"

let ellipse_color renderer x y rx ry color = sdl_ellipse_color renderer x y rx ry color
let ellipse_rgba renderer x y rx ry r g b a = sdl_ellipse_rgba renderer x y rx ry r g b a
let aaellipse_color renderer x y rx ry color = sdl_aaellipse_color renderer x y rx ry color
let aaellipse_rgba renderer x y rx ry r g b a = sdl_aaellipse_rgba renderer x y rx ry r g b a
let filled_ellipse_color renderer x y rx ry color = sdl_filled_ellipse_color renderer x y rx ry color
let filled_ellipse_rgba renderer x y rx ry r g b a = sdl_filled_ellipse_rgba renderer x y rx ry r g b a

(** {2 Pie operations} *)

external sdl_pie_color : Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int = "caml_pieColor_byte" "caml_pieColor"
external sdl_pie_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_pieRGBA_byte" "caml_pieRGBA"
external sdl_filled_pie_color : Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int = "caml_filledPieColor_byte" "caml_filledPieColor"
external sdl_filled_pie_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_filledPieRGBA_byte" "caml_filledPieRGBA"

let pie_color renderer x y rad start end_ color = sdl_pie_color renderer x y rad start end_ color
let pie_rgba renderer x y rad start end_ r g b a = sdl_pie_rgba renderer x y rad start end_ r g b a
let filled_pie_color renderer x y rad start end_ color = sdl_filled_pie_color renderer x y rad start end_ color
let filled_pie_rgba renderer x y rad start end_ r g b a = sdl_filled_pie_rgba renderer x y rad start end_ r g b a

(** {2 Triangle operations} *)

external sdl_trigon_color : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int32 -> int = "caml_trigonColor_byte" "caml_trigonColor"
external sdl_trigon_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_trigonRGBA_byte" "caml_trigonRGBA"
external sdl_aatrigon_color : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int32 -> int = "caml_aatrigonColor_byte" "caml_aatrigonColor"
external sdl_aatrigon_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_aatrigonRGBA_byte" "caml_aatrigonRGBA"
external sdl_filled_trigon_color : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int32 -> int = "caml_filledTrigonColor_byte" "caml_filledTrigonColor"
external sdl_filled_trigon_rgba : Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int = "caml_filledTrigonRGBA_byte" "caml_filledTrigonRGBA"

let trigon_color renderer x1 y1 x2 y2 x3 y3 color = sdl_trigon_color renderer x1 y1 x2 y2 x3 y3 color
let trigon_rgba renderer x1 y1 x2 y2 x3 y3 r g b a = sdl_trigon_rgba renderer x1 y1 x2 y2 x3 y3 r g b a
let aatrigon_color renderer x1 y1 x2 y2 x3 y3 color = sdl_aatrigon_color renderer x1 y1 x2 y2 x3 y3 color
let aatrigon_rgba renderer x1 y1 x2 y2 x3 y3 r g b a = sdl_aatrigon_rgba renderer x1 y1 x2 y2 x3 y3 r g b a
let filled_trigon_color renderer x1 y1 x2 y2 x3 y3 color = sdl_filled_trigon_color renderer x1 y1 x2 y2 x3 y3 color
let filled_trigon_rgba renderer x1 y1 x2 y2 x3 y3 r g b a = sdl_filled_trigon_rgba renderer x1 y1 x2 y2 x3 y3 r g b a

(** {2 Polygon operations} *)

external sdl_polygon_color : Sdl.renderer -> int array -> int array -> int -> int32 -> int = "caml_polygonColor"
external sdl_polygon_rgba : Sdl.renderer -> int array -> int array -> int -> int -> int -> int -> int -> int = "caml_polygonRGBA_byte" "caml_polygonRGBA"
external sdl_aapolygon_color : Sdl.renderer -> int array -> int array -> int -> int32 -> int = "caml_aapolygonColor"
external sdl_aapolygon_rgba : Sdl.renderer -> int array -> int array -> int -> int -> int -> int -> int -> int = "caml_aapolygonRGBA_byte" "caml_aapolygonRGBA"
external sdl_filled_polygon_color : Sdl.renderer -> int array -> int array -> int -> int32 -> int = "caml_filledPolygonColor"
external sdl_filled_polygon_rgba : Sdl.renderer -> int array -> int array -> int -> int -> int -> int -> int -> int = "caml_filledPolygonRGBA_byte" "caml_filledPolygonRGBA"
external sdl_textured_polygon : Sdl.renderer -> int array -> int array -> int -> Sdl.surface -> int -> int -> int = "caml_texturedPolygon_byte" "caml_texturedPolygon"

let polygon_color renderer vx vy color = 
  let n = Array.length vx in
  if Array.length vy <> n then failwith "polygon_color: vx and vy must have same length";
  sdl_polygon_color renderer vx vy n color

let polygon_rgba renderer vx vy r g b a = 
  let n = Array.length vx in
  if Array.length vy <> n then failwith "polygon_rgba: vx and vy must have same length";
  sdl_polygon_rgba renderer vx vy n r g b a

let aapolygon_color renderer vx vy color = 
  let n = Array.length vx in
  if Array.length vy <> n then failwith "aapolygon_color: vx and vy must have same length";
  sdl_aapolygon_color renderer vx vy n color

let aapolygon_rgba renderer vx vy r g b a = 
  let n = Array.length vx in
  if Array.length vy <> n then failwith "aapolygon_rgba: vx and vy must have same length";
  sdl_aapolygon_rgba renderer vx vy n r g b a

let filled_polygon_color renderer vx vy color = 
  let n = Array.length vx in
  if Array.length vy <> n then failwith "filled_polygon_color: vx and vy must have same length";
  sdl_filled_polygon_color renderer vx vy n color

let filled_polygon_rgba renderer vx vy r g b a = 
  let n = Array.length vx in
  if Array.length vy <> n then failwith "filled_polygon_rgba: vx and vy must have same length";
  sdl_filled_polygon_rgba renderer vx vy n r g b a

let textured_polygon renderer vx vy texture dx dy = 
  let n = Array.length vx in
  if Array.length vy <> n then failwith "textured_polygon: vx and vy must have same length";
  sdl_textured_polygon renderer vx vy n texture dx dy

(** {2 Bezier operations} *)

external sdl_bezier_color : Sdl.renderer -> int array -> int array -> int -> int -> int32 -> int = "caml_bezierColor_byte" "caml_bezierColor"
external sdl_bezier_rgba : Sdl.renderer -> int array -> int array -> int -> int -> int -> int -> int -> int -> int = "caml_bezierRGBA_byte" "caml_bezierRGBA"

let bezier_color renderer vx vy s color = 
  let n = Array.length vx in
  if Array.length vy <> n then failwith "bezier_color: vx and vy must have same length";
  sdl_bezier_color renderer vx vy n s color

let bezier_rgba renderer vx vy s r g b a = 
  let n = Array.length vx in
  if Array.length vy <> n then failwith "bezier_rgba: vx and vy must have same length";
  sdl_bezier_rgba renderer vx vy n s r g b a

(** {2 Text operations} *)

external sdl_gfx_primitives_set_font : bytes -> int -> int -> unit = "caml_gfxPrimitivesSetFont"
external sdl_gfx_primitives_set_font_rotation : int -> unit = "caml_gfxPrimitivesSetFontRotation"
external sdl_character_color : Sdl.renderer -> int -> int -> char -> int32 -> int = "caml_characterColor"
external sdl_character_rgba : Sdl.renderer -> int -> int -> char -> int -> int -> int -> int -> int = "caml_characterRGBA_byte" "caml_characterRGBA"
external sdl_string_color : Sdl.renderer -> int -> int -> string -> int32 -> int = "caml_stringColor"
external sdl_string_rgba : Sdl.renderer -> int -> int -> string -> int -> int -> int -> int -> int = "caml_stringRGBA_byte" "caml_stringRGBA"

let gfx_primitives_set_font fontdata cw ch = sdl_gfx_primitives_set_font fontdata cw ch
let gfx_primitives_set_font_rotation rotation = sdl_gfx_primitives_set_font_rotation rotation
let character_color renderer x y c color = sdl_character_color renderer x y c color
let character_rgba renderer x y c r g b a = sdl_character_rgba renderer x y c r g b a
let string_color renderer x y s color = sdl_string_color renderer x y s color
let string_rgba renderer x y s r g b a = sdl_string_rgba renderer x y s r g b a

(** {1 Image Filtering} *)

external sdl_imagefilter_mmx_detect : unit -> int = "caml_SDL_imageFilterMMXdetect"
external sdl_imagefilter_mmx_off : unit -> unit = "caml_SDL_imageFilterMMXoff"
external sdl_imagefilter_mmx_on : unit -> unit = "caml_SDL_imageFilterMMXon"

let imagefilter_mmx_detect () = sdl_imagefilter_mmx_detect ()
let imagefilter_mmx_off () = sdl_imagefilter_mmx_off ()
let imagefilter_mmx_on () = sdl_imagefilter_mmx_on ()

(* Image filter functions *)
external sdl_imagefilter_add : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterAdd"
external sdl_imagefilter_mean : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterMean"
external sdl_imagefilter_sub : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterSub"
external sdl_imagefilter_absdiff : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterAbsDiff"
external sdl_imagefilter_mult : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterMult"
external sdl_imagefilter_mult_nor : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterMultNor"
external sdl_imagefilter_mult_divby2 : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterMultDivby2"
external sdl_imagefilter_mult_divby4 : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterMultDivby4"
external sdl_imagefilter_bit_and : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterBitAnd"
external sdl_imagefilter_bit_or : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterBitOr"
external sdl_imagefilter_div : bytes -> bytes -> bytes -> int -> int = "caml_SDL_imageFilterDiv"
external sdl_imagefilter_bit_negation : bytes -> bytes -> int -> int = "caml_SDL_imageFilterBitNegation"
external sdl_imagefilter_add_byte : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterAddByte"
external sdl_imagefilter_add_uint : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterAddUint"
external sdl_imagefilter_add_byte_to_half : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterAddByteToHalf"
external sdl_imagefilter_sub_byte : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterSubByte"
external sdl_imagefilter_sub_uint : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterSubUint"
external sdl_imagefilter_shift_right : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterShiftRight"
external sdl_imagefilter_shift_right_uint : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterShiftRightUint"
external sdl_imagefilter_mult_by_byte : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterMultByByte"
external sdl_imagefilter_shift_right_and_mult_by_byte : bytes -> bytes -> int -> int -> int -> int = "caml_SDL_imageFilterShiftRightAndMultByByte_byte" "caml_SDL_imageFilterShiftRightAndMultByByte"
external sdl_imagefilter_shift_left_byte : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterShiftLeftByte"
external sdl_imagefilter_shift_left_uint : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterShiftLeftUint"
external sdl_imagefilter_shift_left : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterShiftLeft"
external sdl_imagefilter_binarize_using_threshold : bytes -> bytes -> int -> int -> int = "caml_SDL_imageFilterBinarizeUsingThreshold"
external sdl_imagefilter_clip_to_range : bytes -> bytes -> int -> int -> int -> int = "caml_SDL_imageFilterClipToRange_byte" "caml_SDL_imageFilterClipToRange"
external sdl_imagefilter_normalize_linear : bytes -> bytes -> int -> int -> int -> int -> int -> int = "caml_SDL_imageFilterNormalizeLinear_byte" "caml_SDL_imageFilterNormalizeLinear"

let imagefilter_add src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_add src1 src2 dest length

let imagefilter_mean src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_mean src1 src2 dest length

let imagefilter_sub src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_sub src1 src2 dest length

let imagefilter_absdiff src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_absdiff src1 src2 dest length

let imagefilter_mult src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_mult src1 src2 dest length

let imagefilter_mult_nor src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_mult_nor src1 src2 dest length

let imagefilter_mult_divby2 src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_mult_divby2 src1 src2 dest length

let imagefilter_mult_divby4 src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_mult_divby4 src1 src2 dest length

let imagefilter_bit_and src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_bit_and src1 src2 dest length

let imagefilter_bit_or src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_bit_or src1 src2 dest length

let imagefilter_div src1 src2 dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_div src1 src2 dest length

let imagefilter_bit_negation src dest = 
  let length = Bytes.length dest in
  sdl_imagefilter_bit_negation src dest length

let imagefilter_add_byte src dest c = 
  let length = Bytes.length dest in
  sdl_imagefilter_add_byte src dest length c

let imagefilter_add_uint src dest c = 
  let length = Bytes.length dest in
  sdl_imagefilter_add_uint src dest length c

let imagefilter_add_byte_to_half src dest c = 
  let length = Bytes.length dest in
  sdl_imagefilter_add_byte_to_half src dest length c

let imagefilter_sub_byte src dest c = 
  let length = Bytes.length dest in
  sdl_imagefilter_sub_byte src dest length c

let imagefilter_sub_uint src dest c = 
  let length = Bytes.length dest in
  sdl_imagefilter_sub_uint src dest length c

let imagefilter_shift_right src dest n = 
  let length = Bytes.length dest in
  sdl_imagefilter_shift_right src dest length n

let imagefilter_shift_right_uint src dest n = 
  let length = Bytes.length dest in
  sdl_imagefilter_shift_right_uint src dest length n

let imagefilter_mult_by_byte src dest c = 
  let length = Bytes.length dest in
  sdl_imagefilter_mult_by_byte src dest length c

let imagefilter_shift_right_and_mult_by_byte src dest n c = 
  let length = Bytes.length dest in
  sdl_imagefilter_shift_right_and_mult_by_byte src dest length n c

let imagefilter_shift_left_byte src dest n = 
  let length = Bytes.length dest in
  sdl_imagefilter_shift_left_byte src dest length n

let imagefilter_shift_left_uint src dest n = 
  let length = Bytes.length dest in
  sdl_imagefilter_shift_left_uint src dest length n

let imagefilter_shift_left src dest n = 
  let length = Bytes.length dest in
  sdl_imagefilter_shift_left src dest length n

let imagefilter_binarize_using_threshold src dest t = 
  let length = Bytes.length dest in
  sdl_imagefilter_binarize_using_threshold src dest length t

let imagefilter_clip_to_range src dest tmin tmax = 
  let length = Bytes.length dest in
  sdl_imagefilter_clip_to_range src dest length tmin tmax

let imagefilter_normalize_linear src dest cmin cmax nmin nmax = 
  let length = Bytes.length dest in
  sdl_imagefilter_normalize_linear src dest length cmin cmax nmin nmax

(** {1 Rotation and Zoom} *)

(** Smoothing constants *)
let smoothing_off = 0
let smoothing_on = 1

external sdl_rotozoom_surface : Sdl.surface -> float -> float -> int -> Sdl.surface option = "caml_rotozoomSurface"
external sdl_rotozoom_surface_xy : Sdl.surface -> float -> float -> float -> int -> Sdl.surface option = "caml_rotozoomSurfaceXY"
external sdl_rotozoom_surface_size : int -> int -> float -> float -> int * int = "caml_rotozoomSurfaceSize"
external sdl_rotozoom_surface_size_xy : int -> int -> float -> float -> float -> int * int = "caml_rotozoomSurfaceSizeXY"
external sdl_zoom_surface : Sdl.surface -> float -> float -> int -> Sdl.surface option = "caml_zoomSurface"
external sdl_zoom_surface_size : int -> int -> float -> float -> int * int = "caml_zoomSurfaceSize"
external sdl_shrink_surface : Sdl.surface -> int -> int -> Sdl.surface option = "caml_shrinkSurface"
external sdl_rotate_surface_90_degrees : Sdl.surface -> int -> Sdl.surface option = "caml_rotateSurface90Degrees"

let rotozoom_surface src angle zoom smooth = sdl_rotozoom_surface src angle zoom smooth
let rotozoom_surface_xy src angle zoomx zoomy smooth = sdl_rotozoom_surface_xy src angle zoomx zoomy smooth
let rotozoom_surface_size width height angle zoom = sdl_rotozoom_surface_size width height angle zoom
let rotozoom_surface_size_xy width height angle zoomx zoomy = sdl_rotozoom_surface_size_xy width height angle zoomx zoomy
let zoom_surface src zoomx zoomy smooth = sdl_zoom_surface src zoomx zoomy smooth
let zoom_surface_size width height zoomx zoomy = sdl_zoom_surface_size width height zoomx zoomy
let shrink_surface src factorx factory = sdl_shrink_surface src factorx factory
let rotate_surface_90_degrees src turns = sdl_rotate_surface_90_degrees src turns
