(** Pure SVG construction plus explicit string/file serialization. *)

open Prismel

type attr = string * string
type element

val color : Color.t -> string
val style :
  ?fill:Color.t ->
  ?stroke:Color.t ->
  ?stroke_width:float ->
  ?opacity:float ->
  unit -> attr list
val transform : Affine2.t -> attr

val element : string -> ?attrs:attr list -> element list -> element
val text : ?attrs:attr list -> at:Vec2.t -> string -> element
val circle : ?attrs:attr list -> Circle2.t -> element
val ellipse : ?attrs:attr list -> center:Vec2.t -> rx:float -> ry:float -> unit -> element
val rect : ?attrs:attr list -> Bounds2.t -> element
val line : ?attrs:attr list -> Segment2.t -> element
val polyline : ?attrs:attr list -> Vec2.t list -> element
val polygon : ?attrs:attr list -> Polygon2.t -> element
val path : ?attrs:attr list -> Path.t -> element
val arc :
  ?attrs:attr list ->
  center:Vec2.t ->
  radius:Vec2.t ->
  from_angle:float ->
  to_angle:float ->
  unit ->
  element
val image : ?attrs:attr list -> at:Vec2.t -> width:float -> height:float -> href:string -> unit -> element
val use : ?attrs:attr list -> href:string -> unit -> element
val group : ?attrs:attr list -> element list -> element
val defs : element list -> element

val linear_gradient :
  id:string ->
  ?from_:Vec2.t ->
  ?to_:Vec2.t ->
  (float * Color.t) list ->
  element
val radial_gradient :
  id:string ->
  ?center:Vec2.t ->
  ?radius:float ->
  (float * Color.t) list ->
  element

val document :
  ?view_box:Bounds2.t ->
  width:float ->
  height:float ->
  element list ->
  string
val save :
  ?view_box:Bounds2.t ->
  width:float ->
  height:float ->
  string ->
  element list ->
  (unit, string) result
