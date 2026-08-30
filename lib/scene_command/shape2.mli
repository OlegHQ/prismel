(** Shared renderer-neutral tessellation for ordinary Scene2 and retained
    display-list producers. Coordinates are logical points. *)

val line : from_:int * int -> to_:int * int -> width:int -> color:int32 ->
  Render_ir.geometry
val polygon : (int * int) list -> fill:int32 option -> stroke:int32 option ->
  Render_ir.geometry array
val polyline : (int * int) list -> color:int32 -> Render_ir.geometry
val rect : x:int -> y:int -> width:int -> height:int -> fill:int32 option ->
  stroke:int32 option -> Render_ir.geometry array
val rounded_rect : width:int -> height:int -> radius:int ->
  fill:int32 option -> stroke:int32 option -> Render_ir.geometry array
val ellipse : center:int * int -> rx:int -> ry:int -> fill:int32 option ->
  stroke:int32 option -> Render_ir.geometry array
