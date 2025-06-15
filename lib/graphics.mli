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
