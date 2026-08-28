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
  val register_image : t -> Prismel_next_resources.Image.t -> (int,error) result
  val register_text : t -> id:int -> Prismel_next_resources.Text.t -> (unit,error) result
  val register_canvas : t -> id:int -> Prismel_next_resources.Canvas.t -> (unit,error) result
  val remove_resource : t -> int -> unit
  val present : t -> Scene_command.Render_ir.t -> (bool,error) result
  val destroy : t -> (unit,error) result
  val exists : t -> bool
end

module Graphics : sig
  type color = int32
  type blend = Scene_command.Render_ir.blend
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
  val ellipse : t -> center:int*int -> rx:int -> ry:int -> ?filled:bool -> ?color:color -> unit -> (unit,error) result
  val rounded_rect : t -> pos:int*int -> w:int -> h:int -> radius:int -> ?filled:bool -> ?color:color -> unit -> (unit,error) result
  val thick_line : t -> x1:int -> y1:int -> x2:int -> y2:int -> width:int -> ?color:color -> unit -> (unit,error) result
  val arc : t -> center:int*int -> radius:int -> start_angle:float -> end_angle:float -> ?color:color -> unit -> (unit,error) result
  val pie : t -> center:int*int -> radius:int -> start_angle:float -> end_angle:float -> ?filled:bool -> ?color:color -> unit -> (unit,error) result
  val bezier : t -> points:(int*int) list -> steps:int -> ?color:color -> unit -> (unit,error) result
  val fill_contours : t -> (int*int) list list -> rule:Scene_command.Path.fill_rule -> color:color -> (unit,error) result
  val stroke_path : t -> Scene_command.Path.command array -> width:float -> cap:Scene_command.Path.cap -> join:Scene_command.Path.join -> ?color:color -> unit -> (unit,error) result
  val push_matrix : t -> (unit,error) result
  val pop_matrix : t -> (unit,error) result
  val translate : t -> dx:int -> dy:int -> unit
  val rotate : t -> angle:float -> unit
  val scale : t -> sx:float -> sy:float -> unit
  val reset_transform : t -> unit
  val get_clip : t -> (int*int*int*int) option
  val set_clip : t -> (int*int*int*int) option -> (unit,error) result
  val draw_image : t -> Prismel_next_resources.Image.t -> pos:int*int -> (unit,error) result
  val draw_sub_image : t -> Prismel_next_resources.Image.t -> src_rect:int*int*int*int -> dst_rect:int*int*int*int -> (unit,error) result
  val draw_image_ex : t -> Prismel_next_resources.Image.t -> pos:int*int -> ?scale:float -> ?angle:float -> ?center:int*int -> ?flip:bool -> unit -> (unit,error) result
  val draw_text : t -> Prismel_next_resources.Font.t -> pos:int*int -> text:string -> ?color:color -> unit -> (unit,error) result
  val draw_text_snapshot : t -> resource_id:int -> Prismel_next_resources.Text.t ->
    pos:int*int -> (unit,error) result
  val draw_canvas : t -> resource_id:int -> Prismel_next_resources.Canvas.t ->
    pos:int*int -> (unit,error) result
  val set_gfx_font_rotation : t -> int -> (unit,error) result
  val draw_gfx_text : t -> pos:int*int -> text:string -> ?color:color -> unit -> (unit,error) result
  val flush : t -> (Scene_command.Render_ir.t,error) result
  val command_count : t -> int
  val peak_commands : t -> int
  val destroy : t -> unit
end
