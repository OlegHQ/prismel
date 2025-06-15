type state = {
  renderer : Tsdl.Sdl.renderer option;
  current_color : Color.t;
  transform_stack : Mat3.t Stack.t;
  current_transform : Mat3.t;
}
val graphics_state : state ref
val init : Tsdl.Sdl.renderer -> unit
val get_renderer : unit -> Tsdl.Sdl.renderer
val color_to_sdl : Color.t -> int * int * int * int
val transform_point : int * int -> int * int
val clear : Color.t -> unit
val set_color : Color.t -> unit
val get_color : ?color:Color.t -> unit -> Color.t
val point : x:int -> y:int -> ?color:Color.t -> unit -> unit
val line :
  x1:int -> y1:int -> x2:int -> y2:int -> ?color:Color.t -> unit -> unit
val rect :
  pos:int * int ->
  w:int -> h:int -> ?filled:bool -> ?color:Color.t -> unit -> unit
val circle :
  center:int * int ->
  radius:int -> ?filled:bool -> ?color:Color.t -> unit -> unit
val triangle :
  p1:int * int ->
  p2:int * int ->
  p3:int * int -> ?filled:bool -> ?color:Color.t -> unit -> unit
val polygon :
  points:(int * int) list -> ?filled:bool -> ?color:Color.t -> unit -> unit
val draw_image : Image.t -> pos:int * int -> unit
val draw_sub_image :
  Image.t ->
  src_rect:int * int * int * int -> dst_rect:int * int * int * int -> unit
val draw_image_ex :
  Image.t ->
  pos:int * int ->
  ?scale:float ->
  ?angle:float -> ?center:int * int -> ?flip:bool -> unit -> unit
val draw_text :
  Font.t -> pos:int * int -> text:string -> ?color:Color.t -> unit -> unit
val push_matrix : unit -> unit
val pop_matrix : unit -> unit
val translate : dx:int -> dy:int -> unit
val rotate : angle:float -> unit
val scale : sx:float -> sy:float -> unit
val reset_transform : unit -> unit
val polyline : points:(int * int) list -> ?color:Color.t -> unit -> unit
val ellipse :
  center:int * int ->
  rx:int -> ry:int -> ?filled:bool -> ?color:Color.t -> unit -> unit
val rounded_rect :
  pos:int * int ->
  w:int ->
  h:int -> radius:int -> ?filled:bool -> ?color:Color.t -> unit -> unit

(** {1 Advanced SDL2_gfx Drawing Functions} *)

(** [thick_line ~x1 ~y1 ~x2 ~y2 ~width ?color ()] draws a thick antialiased line *)
val thick_line :
  x1:int -> y1:int -> x2:int -> y2:int -> width:int -> ?color:Color.t -> unit -> unit

(** [arc ~center ~radius ~start_angle ~end_angle ?color ()] draws an arc *)
val arc :
  center:int * int ->
  radius:int ->
  start_angle:float ->
  end_angle:float -> ?color:Color.t -> unit -> unit

(** [pie ~center ~radius ~start_angle ~end_angle ?filled ?color ()] draws a pie slice *)
val pie :
  center:int * int ->
  radius:int ->
  start_angle:float ->
  end_angle:float -> ?filled:bool -> ?color:Color.t -> unit -> unit

(** [bezier ~points ~steps ?color ()] draws a smooth Bezier curve *)
val bezier :
  points:(int * int) list -> steps:int -> ?color:Color.t -> unit -> unit

(** [draw_gfx_text ~pos ~text ?color ()] draws text using SDL2_gfx built-in font *)
val draw_gfx_text :
  pos:int * int -> text:string -> ?color:Color.t -> unit -> unit

(** [set_gfx_font_rotation rotation] sets font rotation (0=0°, 1=90°, 2=180°, 3=270°) *)
val set_gfx_font_rotation : int -> unit
