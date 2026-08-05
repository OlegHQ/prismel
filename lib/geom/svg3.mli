(** Painter-sorted 3D mesh projection to SVG facets. *)

open Prismel

type facet = private {
  index : int;
  world : Triangle3.t;
  projected : Polygon2.t;
  normal : Vec3.t;
  center : Vec3.t;
  depth : float;
}

type shader = facet -> Color.t

val lambert : ?ambient:float -> light_direction:Vec3.t -> base:Color.t -> shader

val mesh :
  ?transform:Mat4.t ->
  ?cull_backfaces:bool ->
  ?stroke:Color.t ->
  ?stroke_width:float ->
  ?shader:shader ->
  viewport:int * int * int * int ->
  camera:Camera.t ->
  Mesh.t ->
  Svg.element
