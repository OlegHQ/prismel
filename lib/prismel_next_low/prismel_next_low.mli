(** SDL2-free staging replacement for [Prismel.Low]. No native handles escape. *)

type error = Invalid_argument of string | Unavailable of string | Backend of string

module Window : sig
  type config = {
    width:int; height:int; title:string; resizable:bool; fullscreen:bool;
    x:int option; y:int option; vsync:bool; highdpi:bool;
    multisampling:int option;
  }
  type t
  val default_config : config
  val create : ?config:config -> unit -> (t,error) result
  val width : t -> int
  val height : t -> int
  val size : t -> int * int
  val drawable_size : t -> int * int
  val pixel_scale : t -> float * float
  val title : t -> string
  val is_resizable : t -> bool
  val is_fullscreen : t -> bool
  val set_title : t -> string -> (unit,error) result
  val set_size : t -> int -> int -> (unit,error) result
  val set_position : t -> int -> int -> (unit,error) result
  val center : t -> (unit,error) result
  val set_fullscreen : t -> bool -> (unit,error) result
  val show : t -> (unit,error) result
  val hide : t -> (unit,error) result
  val minimize : t -> (unit,error) result
  val maximize : t -> (unit,error) result
  val restore : t -> (unit,error) result
  val capture : t -> (bytes,error) result
  val present : t -> Raster2.Render_ir.t -> (bool,error) result
  val destroy : t -> (unit,error) result
  val exists : t -> bool
end

module Graphics : sig
  type color = int32
  type blend = Raster2.Composite.blend
  type t
  val create : ?capacity:int -> unit -> (t,error) result
  val clear : t -> color -> (unit,error) result
  val set_color : t -> color -> unit
  val get_color : t -> ?color:color -> unit -> color
  val set_blend : t -> blend -> (unit,error) result
  val point : t -> x:int -> y:int -> ?color:color -> unit -> (unit,error) result
  val line : t -> x1:int -> y1:int -> x2:int -> y2:int -> ?color:color -> unit -> (unit,error) result
  val rect : t -> pos:int*int -> w:int -> h:int -> ?filled:bool -> ?color:color -> unit -> (unit,error) result
  val circle : t -> center:int*int -> radius:int -> ?filled:bool -> ?color:color -> unit -> (unit,error) result
  val triangle : t -> p1:int*int -> p2:int*int -> p3:int*int -> ?filled:bool -> ?color:color -> unit -> (unit,error) result
  val polygon : t -> points:(int*int) list -> ?filled:bool -> ?color:color -> unit -> (unit,error) result
  val polyline : t -> points:(int*int) list -> ?color:color -> unit -> (unit,error) result
  val push_matrix : t -> (unit,error) result
  val pop_matrix : t -> (unit,error) result
  val translate : t -> dx:int -> dy:int -> unit
  val rotate : t -> angle:float -> unit
  val scale : t -> sx:float -> sy:float -> unit
  val reset_transform : t -> unit
  val get_clip : t -> (int*int*int*int) option
  val set_clip : t -> (int*int*int*int) option -> (unit,error) result
  val draw_image : t -> Prismel_next_resources.Image.t -> pos:int*int -> (unit,error) result
  val draw_text : t -> Prismel_next_resources.Font.t -> pos:int*int -> text:string -> ?color:color -> unit -> (unit,error) result
  val set_gfx_font_rotation : t -> int -> (unit,error) result
  val draw_gfx_text : t -> pos:int*int -> text:string -> ?color:color -> unit -> (unit,error) result
  val flush : t -> (Raster2.Render_ir.t,error) result
  val command_count : t -> int
  val peak_commands : t -> int
  val destroy : t -> unit
end
