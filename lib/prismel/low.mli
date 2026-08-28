(** SDL-free compatibility escape hatch. The nine legacy raw/native accessors
    are intentionally absent. *)

module Window : sig
  type config = Prismel_next_low.Window.config = {
    width:int; height:int; title:string; resizable:bool; fullscreen:bool;
    x:int option; y:int option; vsync:bool; highdpi:bool;
    multisampling:int option;
  }
  type t
  val default_config : config
  val current_window : t option ref
  val create : ?config:config -> unit -> t
  val get_current : unit -> t
  val width : unit -> int
  val height : unit -> int
  val size : unit -> int * int
  val drawable_size : unit -> int * int
  val pixel_scale : unit -> float * float
  val title : unit -> string
  val is_resizable : unit -> bool
  val is_fullscreen : unit -> bool
  val set_title : string -> unit
  val set_size : int -> int -> unit
  val set_position : int -> int -> unit
  val center : unit -> unit
  val set_fullscreen : bool -> unit
  val show : unit -> unit
  val hide : unit -> unit
  val minimize : unit -> unit
  val maximize : unit -> unit
  val restore : unit -> unit
  val update_dimensions : int -> int -> unit
  val destroy : unit -> unit
  val exists : unit -> bool
end

module Graphics : sig
  type state = {
    renderer : Window.t option;
    current_color : Color.t;
    transform_stack : Mat3.t Stack.t;
    current_transform : Mat3.t;
    current_clip : (int*int*int*int) option;
  }
  val graphics_state : state ref
  val init : Window.t -> unit
  val color_to_sdl : Color.t -> int * int * int * int
  val transform_point : int * int -> int * int
  val clear : Color.t -> unit
  val set_color : Color.t -> unit
  val get_color : ?color:Color.t -> unit -> Color.t
  val point : x:int -> y:int -> ?color:Color.t -> unit -> unit
  val line : x1:int -> y1:int -> x2:int -> y2:int -> ?color:Color.t -> unit -> unit
  val rect : pos:int*int -> w:int -> h:int -> ?filled:bool -> ?color:Color.t -> unit -> unit
  val circle : center:int*int -> radius:int -> ?filled:bool -> ?color:Color.t -> unit -> unit
  val triangle : p1:int*int -> p2:int*int -> p3:int*int -> ?filled:bool -> ?color:Color.t -> unit -> unit
  val polygon : points:(int*int) list -> ?filled:bool -> ?color:Color.t -> unit -> unit
  val fill_contours : (int*int) list list -> rule:Path.fill_rule -> color:Color.t -> unit
  val draw_image : Image.t -> pos:int*int -> unit
  val draw_sub_image : Image.t -> src_rect:int*int*int*int -> dst_rect:int*int*int*int -> unit
  val draw_image_ex : Image.t -> pos:int*int -> ?scale:float -> ?angle:float -> ?center:int*int -> ?flip:bool -> unit -> unit
  val draw_text : Font.t -> pos:int*int -> text:string -> ?color:Color.t -> ?wrap:int -> ?align:Font.alignment -> unit -> unit
  val push_matrix : unit -> unit
  val pop_matrix : unit -> unit
  val translate : dx:int -> dy:int -> unit
  val rotate : angle:float -> unit
  val scale : sx:float -> sy:float -> unit
  val reset_transform : unit -> unit
  val get_clip : unit -> (int*int*int*int) option
  val set_clip : (int*int*int*int) option -> unit
  val polyline : points:(int*int) list -> ?color:Color.t -> unit -> unit
  val ellipse : center:int*int -> rx:int -> ry:int -> ?filled:bool -> ?color:Color.t -> unit -> unit
  val rounded_rect : pos:int*int -> w:int -> h:int -> radius:int -> ?filled:bool -> ?color:Color.t -> unit -> unit
  val thick_line : x1:int -> y1:int -> x2:int -> y2:int -> width:int -> ?color:Color.t -> unit -> unit
  val arc : center:int*int -> radius:int -> start_angle:float -> end_angle:float -> ?color:Color.t -> unit -> unit
  val pie : center:int*int -> radius:int -> start_angle:float -> end_angle:float -> ?filled:bool -> ?color:Color.t -> unit -> unit
  val bezier : points:(int*int) list -> steps:int -> ?color:Color.t -> unit -> unit
  val draw_gfx_text : pos:int*int -> text:string -> ?color:Color.t -> unit -> unit
  val set_gfx_font_rotation : int -> unit
end

module App : sig
  type config = Window.config
  type 'a framework_state = { window:Window.t; running:bool; user_state:'a }
  val framework_running : bool ref
  val quit_requested : bool ref
  val request_quit : unit -> unit
  val is_running : unit -> bool
  val init_sdl : ?config:Window.config -> unit -> unit
  val cleanup_sdl : unit -> unit
  val cleanup_graphics : unit -> unit
  val process_frame : Window.t -> 'a -> ('a -> float -> 'a) -> ('a -> unit) -> ('a -> unit) option -> ('a -> Event.t -> 'a) option -> 'a framework_state
  val main_loop : 'a framework_state -> ('a -> float -> 'a) -> ('a -> unit) -> ('a -> unit) option -> ('a -> Event.t -> 'a) option -> 'a
  val run : ?config:Window.config -> init:(unit->'a) -> update:('a->float->'a) -> draw:('a->unit) -> ?after_draw:('a->unit) -> ?on_event:('a->Event.t->'a) -> ?on_stop:('a->unit) -> unit -> 'a
  val run_simple : ?width:int -> ?height:int -> ?title:string -> init:(unit->'a) -> update:('a->float->'a) -> draw:('a->unit) -> ?after_draw:('a->unit) -> ?on_event:('a->Event.t->'a) -> ?on_stop:('a->unit) -> unit -> 'a
  val get_window : unit -> Window.t
  val get_renderer : unit -> Window.t
  module Utils : sig
    val window_size : unit -> int*int
    val window_width : unit -> int
    val window_height : unit -> int
    val time : unit -> float
    val delta_time : unit -> float
    val frame_rate : unit -> float
    val set_frame_rate : int -> unit
    val set_vsync : bool -> unit
  end
end

module Backend : sig
  val is_displayless : unit -> bool
  val start : width:int -> height:int -> title:string -> resizable:bool -> (Window.t,string) result
  val stop : unit -> unit
  val present : Window.t -> logical_width:int -> logical_height:int -> (unit,string) result
end
