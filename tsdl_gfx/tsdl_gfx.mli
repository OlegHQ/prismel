(** OCaml bindings for SDL2_gfx library *)

(** {1 Version information} *)

val version_major : int
val version_minor : int  
val version_micro : int

(** {1 Framerate management} *)

(** Framerate manager structure *)
type fps_manager

(** Framerate constants *)
val fps_upper_limit : int
val fps_lower_limit : int
val fps_default : int

(** [init_framerate manager] initializes the framerate manager *)
val init_framerate : fps_manager -> unit

(** [set_framerate manager rate] sets the target framerate. Returns 0 on success, -1 on error *)
val set_framerate : fps_manager -> int -> int

(** [get_framerate manager] gets the current framerate setting *)
val get_framerate : fps_manager -> int

(** [get_framecount manager] gets the current frame count *)
val get_framecount : fps_manager -> int

(** [framerate_delay manager] delays to maintain target framerate. Returns actual delay in ms *)
val framerate_delay : fps_manager -> int

(** [create_fps_manager ()] creates a new framerate manager *)
val create_fps_manager : unit -> fps_manager

(** {1 Graphics Primitives} *)

(** {2 Pixel operations} *)

(** [pixel_color renderer x y color] draws a pixel with RGBA color *)
val pixel_color : Tsdl.Sdl.renderer -> int -> int -> int32 -> int

(** [pixel_rgba renderer x y r g b a] draws a pixel with separate RGBA components *)
val pixel_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int ->  int

(** {2 Line operations} *)

(** [hline_color renderer x1 x2 y color] draws a horizontal line *)
val hline_color : Tsdl.Sdl.renderer -> int -> int -> int -> int32 -> int

(** [hline_rgba renderer x1 x2 y r g b a] draws a horizontal line with RGBA *)
val hline_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int

(** [vline_color renderer x y1 y2 color] draws a vertical line *)
val vline_color : Tsdl.Sdl.renderer -> int -> int -> int -> int32 -> int

(** [vline_rgba renderer x y1 y2 r g b a] draws a vertical line with RGBA *)
val vline_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int

(** [line_color renderer x1 y1 x2 y2 color] draws a line *)
val line_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int32 -> int

(** [line_rgba renderer x1 y1 x2 y2 r g b a] draws a line with RGBA *)
val line_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [aaline_color renderer x1 y1 x2 y2 color] draws an anti-aliased line *)
val aaline_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int32 -> int

(** [aaline_rgba renderer x1 y1 x2 y2 r g b a] draws an anti-aliased line with RGBA *)
val aaline_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [thick_line_color renderer x1 y1 x2 y2 width color] draws a thick line *)
val thick_line_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int

(** [thick_line_rgba renderer x1 y1 x2 y2 width r g b a] draws a thick line with RGBA *)
val thick_line_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** {2 Rectangle operations} *)

(** [rectangle_color renderer x1 y1 x2 y2 color] draws a rectangle outline *)
val rectangle_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int32 -> int

(** [rectangle_rgba renderer x1 y1 x2 y2 r g b a] draws a rectangle outline with RGBA *)
val rectangle_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [rounded_rectangle_color renderer x1 y1 x2 y2 rad color] draws a rounded rectangle outline *)
val rounded_rectangle_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int

(** [rounded_rectangle_rgba renderer x1 y1 x2 y2 rad r g b a] draws a rounded rectangle outline with RGBA *)
val rounded_rectangle_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [box_color renderer x1 y1 x2 y2 color] draws a filled rectangle *)
val box_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int32 -> int

(** [box_rgba renderer x1 y1 x2 y2 r g b a] draws a filled rectangle with RGBA *)
val box_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [rounded_box_color renderer x1 y1 x2 y2 rad color] draws a filled rounded rectangle *)
val rounded_box_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int

(** [rounded_box_rgba renderer x1 y1 x2 y2 rad r g b a] draws a filled rounded rectangle with RGBA *)
val rounded_box_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** {2 Circle operations} *)

(** [circle_color renderer x y rad color] draws a circle outline *)
val circle_color : Tsdl.Sdl.renderer -> int -> int -> int -> int32 -> int

(** [circle_rgba renderer x y rad r g b a] draws a circle outline with RGBA *)
val circle_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int

(** [aacircle_color renderer x y rad color] draws an anti-aliased circle outline *)
val aacircle_color : Tsdl.Sdl.renderer -> int -> int -> int -> int32 -> int

(** [aacircle_rgba renderer x y rad r g b a] draws an anti-aliased circle outline with RGBA *)
val aacircle_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int

(** [filled_circle_color renderer x y rad color] draws a filled circle *)
val filled_circle_color : Tsdl.Sdl.renderer -> int -> int -> int -> int32 -> int

(** [filled_circle_rgba renderer x y rad r g b a] draws a filled circle with RGBA *)
val filled_circle_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int

(** {2 Arc operations} *)

(** [arc_color renderer x y rad start end color] draws an arc *)
val arc_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int

(** [arc_rgba renderer x y rad start end r g b a] draws an arc with RGBA *)
val arc_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** {2 Ellipse operations} *)

(** [ellipse_color renderer x y rx ry color] draws an ellipse outline *)
val ellipse_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int32 -> int

(** [ellipse_rgba renderer x y rx ry r g b a] draws an ellipse outline with RGBA *)
val ellipse_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [aaellipse_color renderer x y rx ry color] draws an anti-aliased ellipse outline *)
val aaellipse_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int32 -> int

(** [aaellipse_rgba renderer x y rx ry r g b a] draws an anti-aliased ellipse outline with RGBA *)
val aaellipse_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [filled_ellipse_color renderer x y rx ry color] draws a filled ellipse *)
val filled_ellipse_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int32 -> int

(** [filled_ellipse_rgba renderer x y rx ry r g b a] draws a filled ellipse with RGBA *)
val filled_ellipse_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** {2 Pie operations} *)

(** [pie_color renderer x y rad start end color] draws a pie outline *)
val pie_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int

(** [pie_rgba renderer x y rad start end r g b a] draws a pie outline with RGBA *)
val pie_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [filled_pie_color renderer x y rad start end color] draws a filled pie *)
val filled_pie_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int32 -> int

(** [filled_pie_rgba renderer x y rad start end r g b a] draws a filled pie with RGBA *)
val filled_pie_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** {2 Triangle operations} *)

(** [trigon_color renderer x1 y1 x2 y2 x3 y3 color] draws a triangle outline *)
val trigon_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int32 -> int

(** [trigon_rgba renderer x1 y1 x2 y2 x3 y3 r g b a] draws a triangle outline with RGBA *)
val trigon_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [aatrigon_color renderer x1 y1 x2 y2 x3 y3 color] draws an anti-aliased triangle outline *)
val aatrigon_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int32 -> int

(** [aatrigon_rgba renderer x1 y1 x2 y2 x3 y3 r g b a] draws an anti-aliased triangle outline with RGBA *)
val aatrigon_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** [filled_trigon_color renderer x1 y1 x2 y2 x3 y3 color] draws a filled triangle *)
val filled_trigon_color : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int32 -> int

(** [filled_trigon_rgba renderer x1 y1 x2 y2 x3 y3 r g b a] draws a filled triangle with RGBA *)
val filled_trigon_rgba : Tsdl.Sdl.renderer -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int -> int

(** {2 Polygon operations} *)

(** [polygon_color renderer vx vy color] draws a polygon outline *)
val polygon_color : Tsdl.Sdl.renderer -> int array -> int array -> int32 -> int

(** [polygon_rgba renderer vx vy r g b a] draws a polygon outline with RGBA *)
val polygon_rgba : Tsdl.Sdl.renderer -> int array -> int array -> int -> int -> int -> int -> int

(** [aapolygon_color renderer vx vy color] draws an anti-aliased polygon outline *)
val aapolygon_color : Tsdl.Sdl.renderer -> int array -> int array -> int32 -> int

(** [aapolygon_rgba renderer vx vy r g b a] draws an anti-aliased polygon outline with RGBA *)
val aapolygon_rgba : Tsdl.Sdl.renderer -> int array -> int array -> int -> int -> int -> int -> int

(** [filled_polygon_color renderer vx vy color] draws a filled polygon *)
val filled_polygon_color : Tsdl.Sdl.renderer -> int array -> int array -> int32 -> int

(** [filled_polygon_rgba renderer vx vy r g b a] draws a filled polygon with RGBA *)
val filled_polygon_rgba : Tsdl.Sdl.renderer -> int array -> int array -> int -> int -> int -> int -> int

(** [textured_polygon renderer vx vy texture dx dy] draws a textured polygon *)
val textured_polygon : Tsdl.Sdl.renderer -> int array -> int array -> Tsdl.Sdl.surface -> int -> int -> int

(** {2 Bezier operations} *)

(** [bezier_color renderer vx vy s color] draws a Bezier curve *)
val bezier_color : Tsdl.Sdl.renderer -> int array -> int array -> int -> int32 -> int

(** [bezier_rgba renderer vx vy s r g b a] draws a Bezier curve with RGBA *)
val bezier_rgba : Tsdl.Sdl.renderer -> int array -> int array -> int -> int -> int -> int -> int -> int

(** {2 Text operations} *)

(** [gfx_primitives_set_font fontdata cw ch] sets the font for character rendering *)
val gfx_primitives_set_font : bytes -> int -> int -> unit

(** [gfx_primitives_set_font_rotation rotation] sets font rotation (0, 1, 2, 3 for 0°, 90°, 180°, 270°) *)
val gfx_primitives_set_font_rotation : int -> unit

(** [character_color renderer x y c color] draws a character *)
val character_color : Tsdl.Sdl.renderer -> int -> int -> char -> int32 -> int

(** [character_rgba renderer x y c r g b a] draws a character with RGBA *)
val character_rgba : Tsdl.Sdl.renderer -> int -> int -> char -> int -> int -> int -> int -> int

(** [string_color renderer x y s color] draws a string *)
val string_color : Tsdl.Sdl.renderer -> int -> int -> string -> int32 -> int

(** [string_rgba renderer x y s r g b a] draws a string with RGBA *)
val string_rgba : Tsdl.Sdl.renderer -> int -> int -> string -> int -> int -> int -> int -> int

(** {1 Image Filtering} *)

(** [imagefilter_mmx_detect ()] detects MMX capability *)
val imagefilter_mmx_detect : unit -> int

(** [imagefilter_mmx_off ()] disables MMX usage *)
val imagefilter_mmx_off : unit -> unit

(** [imagefilter_mmx_on ()] enables MMX usage *)
val imagefilter_mmx_on : unit -> unit

(** [imagefilter_add src1 src2 dest] adds two images: D = saturation255(S1 + S2) *)
val imagefilter_add : bytes -> bytes -> bytes -> int

(** [imagefilter_mean src1 src2 dest] computes mean: D = S1/2 + S2/2 *)
val imagefilter_mean : bytes -> bytes -> bytes -> int

(** [imagefilter_sub src1 src2 dest] subtracts images: D = saturation0(S1 - S2) *)
val imagefilter_sub : bytes -> bytes -> bytes -> int

(** [imagefilter_absdiff src1 src2 dest] absolute difference: D = |S1 - S2| *)
val imagefilter_absdiff : bytes -> bytes -> bytes -> int

(** [imagefilter_mult src1 src2 dest] multiplies images: D = saturation(S1 * S2) *)
val imagefilter_mult : bytes -> bytes -> bytes -> int

(** [imagefilter_mult_nor src1 src2 dest] multiplies without saturation: D = S1 * S2 *)
val imagefilter_mult_nor : bytes -> bytes -> bytes -> int

(** [imagefilter_mult_divby2 src1 src2 dest] multiply and divide: D = saturation255(S1/2 * S2) *)
val imagefilter_mult_divby2 : bytes -> bytes -> bytes -> int

(** [imagefilter_mult_divby4 src1 src2 dest] multiply and divide: D = saturation255(S1/2 * S2/2) *)
val imagefilter_mult_divby4 : bytes -> bytes -> bytes -> int

(** [imagefilter_bit_and src1 src2 dest] bitwise AND: D = S1 & S2 *)
val imagefilter_bit_and : bytes -> bytes -> bytes -> int

(** [imagefilter_bit_or src1 src2 dest] bitwise OR: D = S1 | S2 *)
val imagefilter_bit_or : bytes -> bytes -> bytes -> int

(** [imagefilter_div src1 src2 dest] division: D = S1 / S2 *)
val imagefilter_div : bytes -> bytes -> bytes -> int

(** [imagefilter_bit_negation src dest] bitwise negation: D = !S *)
val imagefilter_bit_negation : bytes -> bytes -> int

(** [imagefilter_add_byte src dest c] add constant: D = saturation255(S + C) *)
val imagefilter_add_byte : bytes -> bytes -> int -> int

(** [imagefilter_add_uint src dest c] add constant: D = saturation255(S + C) *)
val imagefilter_add_uint : bytes -> bytes -> int -> int

(** [imagefilter_add_byte_to_half src dest c] add to half: D = saturation255(S/2 + C) *)
val imagefilter_add_byte_to_half : bytes -> bytes -> int -> int

(** [imagefilter_sub_byte src dest c] subtract constant: D = saturation0(S - C) *)
val imagefilter_sub_byte : bytes -> bytes -> int -> int

(** [imagefilter_sub_uint src dest c] subtract constant: D = saturation0(S - C) *)
val imagefilter_sub_uint : bytes -> bytes -> int -> int

(** [imagefilter_shift_right src dest n] shift right: D = saturation0(S >> N) *)
val imagefilter_shift_right : bytes -> bytes -> int -> int

(** [imagefilter_shift_right_uint src dest n] shift right: D = saturation0((uint)S >> N) *)
val imagefilter_shift_right_uint : bytes -> bytes -> int -> int

(** [imagefilter_mult_by_byte src dest c] multiply by constant: D = saturation255(S * C) *)
val imagefilter_mult_by_byte : bytes -> bytes -> int -> int

(** [imagefilter_shift_right_and_mult_by_byte src dest n c] shift and multiply: D = saturation255((S >> N) * C) *)
val imagefilter_shift_right_and_mult_by_byte : bytes -> bytes -> int -> int -> int

(** [imagefilter_shift_left_byte src dest n] shift left: D = (S << N) *)
val imagefilter_shift_left_byte : bytes -> bytes -> int -> int

(** [imagefilter_shift_left_uint src dest n] shift left: D = ((uint)S << N) *)
val imagefilter_shift_left_uint : bytes -> bytes -> int -> int

(** [imagefilter_shift_left src dest n] shift left saturated: D = saturation255(S << N) *)
val imagefilter_shift_left : bytes -> bytes -> int -> int

(** [imagefilter_binarize_using_threshold src dest t] binarize: D = S >= T ? 255:0 *)
val imagefilter_binarize_using_threshold : bytes -> bytes -> int -> int

(** [imagefilter_clip_to_range src dest tmin tmax] clip to range: D = (S >= Tmin) & (S <= Tmax) ? 255:0 *)
val imagefilter_clip_to_range : bytes -> bytes -> int -> int -> int

(** [imagefilter_normalize_linear src dest cmin cmax nmin nmax] normalize linearly *)
val imagefilter_normalize_linear : bytes -> bytes -> int -> int -> int -> int -> int

(** {1 Rotation and Zoom} *)

(** Smoothing constants *)
val smoothing_off : int
val smoothing_on : int

(** [rotozoom_surface src angle zoom smooth] rotates and zooms a surface *)
val rotozoom_surface : Tsdl.Sdl.surface -> float -> float -> int -> Tsdl.Sdl.surface option

(** [rotozoom_surface_xy src angle zoomx zoomy smooth] rotates and zooms with different X/Y factors *)
val rotozoom_surface_xy : Tsdl.Sdl.surface -> float -> float -> float -> int -> Tsdl.Sdl.surface option

(** [rotozoom_surface_size width height angle zoom] calculates destination size for rotation/zoom *)
val rotozoom_surface_size : int -> int -> float -> float -> int * int

(** [rotozoom_surface_size_xy width height angle zoomx zoomy] calculates destination size for rotation/zoom XY *)
val rotozoom_surface_size_xy : int -> int -> float -> float -> float -> int * int

(** [zoom_surface src zoomx zoomy smooth] zooms a surface *)
val zoom_surface : Tsdl.Sdl.surface -> float -> float -> int -> Tsdl.Sdl.surface option

(** [zoom_surface_size width height zoomx zoomy] calculates destination size for zoom *)
val zoom_surface_size : int -> int -> float -> float -> int * int

(** [shrink_surface src factorx factory] shrinks a surface by integer factors *)
val shrink_surface : Tsdl.Sdl.surface -> int -> int -> Tsdl.Sdl.surface option

(** [rotate_surface_90_degrees src turns] rotates surface by 90-degree increments *)
val rotate_surface_90_degrees : Tsdl.Sdl.surface -> int -> Tsdl.Sdl.surface option
