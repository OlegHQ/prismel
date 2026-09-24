(** Pure adapters from geometry values to Prismel scene nodes and paths. *)

open Prismel

val point : ?radius:int -> ?color:Color.t -> Vec2.t -> Scene.node
val points : ?radius:int -> ?color:Color.t -> Vec2.t list -> Scene.node
val segment : ?width:int -> ?color:Color.t -> Segment2.t -> Scene.node
val segments :
  ?width:int -> ?color:Color.t -> Segment2.t list -> Scene.node
val circle :
  ?fill:Color.t -> ?stroke:Color.t -> Circle2.t -> Scene.node
val polygon :
  ?fill:Color.t -> ?stroke:Color.t -> Polygon2.t -> Scene.node
val polygons :
  ?fill:Color.t -> ?stroke:Color.t -> Polygon2.t list -> Scene.node
val curve : ?width:int -> ?color:Color.t -> Curve2.t -> Scene.node
val triangle :
  ?fill:Color.t ->
  ?stroke:Color.t ->
  Delaunay2.triangle ->
  Scene.node
val triangles :
  ?fill:Color.t ->
  ?stroke:Color.t ->
  Delaunay2.triangle list ->
  Scene.node

val voronoi :
  ?fill:(Delaunay2.cell -> Color.t) ->
  ?stroke:Color.t ->
  ?sites:bool ->
  ?site_radius:int ->
  ?site_color:Color.t ->
  Delaunay2.cell list ->
  Scene.node

val path_of_polygon : Polygon2.t -> Path.t
val path_of_curve : Curve2.t -> Path.t
