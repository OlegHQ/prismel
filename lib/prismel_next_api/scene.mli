type node type t=node list type blend=Replace|Alpha|Add|Multiply
val empty:t val one:node->t val group:t->node val clear:Color.t->node
val point : at:(int*int) -> ?color:Color.t -> unit -> node
val line : from_:(int*int) -> to_:(int*int) -> ?color:Color.t -> ?width:int -> unit -> node
val rect : at:(int*int) -> w:int -> h:int -> ?fill:Color.t -> ?stroke:Color.t -> unit -> node
val square : at:(int*int) -> size:int -> ?fill:Color.t -> ?stroke:Color.t -> unit -> node
val rounded_rect : at:(int*int) -> w:int -> h:int -> radius:int -> ?fill:Color.t -> ?stroke:Color.t -> unit -> node
val circle : at:(int*int) -> radius:int -> ?fill:Color.t -> ?stroke:Color.t -> unit -> node
val ellipse : at:(int*int) -> rx:int -> ry:int -> ?fill:Color.t -> ?stroke:Color.t -> unit -> node
val triangle : (int*int) -> (int*int) -> (int*int) -> ?fill:Color.t -> ?stroke:Color.t -> unit -> node
val quad : (int*int) -> (int*int) -> (int*int) -> (int*int) -> ?fill:Color.t -> ?stroke:Color.t -> unit -> node
val polygon : (int*int) list -> ?fill:Color.t -> ?stroke:Color.t -> unit -> node
val polyline : (int*int) list -> ?color:Color.t -> unit -> node
val arc : at:(int*int) -> radius:int -> from_:float -> to_:float -> ?color:Color.t -> unit -> node
val pie : at:(int*int) -> radius:int -> from_:float -> to_:float -> ?fill:Color.t -> ?stroke:Color.t -> unit -> node
val bezier : (int*int) list -> ?steps:int -> ?color:Color.t -> unit -> node
val path : ?steps:int -> ?fill_rule:Path.fill_rule -> ?fill:Color.t -> ?stroke:Color.t -> Path.t -> node
val text : at:(int*int) -> ?color:Color.t -> ?size:int -> string -> node
val debug_text : at:(int*int) -> ?color:Color.t -> string -> node
val font_text : Font.t -> at:(int*int) -> ?color:Color.t -> ?wrap:int -> ?align:Font.alignment -> string -> node
val image : Image.t -> at:(int*int) -> ?scale:float -> ?angle:float -> ?center:(int*int) -> ?flip_x:bool -> unit -> node
val view3d : ?viewport:(int*int*int*int) -> camera:Camera.t -> Scene3.t -> node
val text_input_region : at:(int*int) -> w:int -> h:int -> ?focused:bool -> unit -> node
val translate : int -> int -> t -> node
val rotate : float -> t -> node
val scale : float -> float -> t -> node
val clip : at:(int*int) -> w:int -> h:int -> t -> node
val blend : blend -> t -> node
val render : t -> unit
module Private : sig
  type staged_native = {
    scene2 : Raster2.Render_ir.t;
    resources : (int * Prismel_next_execution.resource) list;
    scene3 : Scene_execution.prepared_scene3 list;
  }
  val stage_native : width:int -> height:int -> t -> (staged_native,string) result
  val to_ir : t -> (Raster2.Render_ir.t,string) result
  val stage : width:int -> height:int -> t ->
    (Raster2.Render_ir.t * (int * Prismel_next_execution.resource) list, string) result
  val install_renderer : (t -> unit) -> unit
  val text_regions : t -> (int*int*int*int*bool) list
  val resources : t -> (int * Prismel_next_execution.resource) list
  val release : t -> unit
end
