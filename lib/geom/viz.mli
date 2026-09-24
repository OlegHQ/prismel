(** Deterministic 2D visualization scales, layouts, and SVG adapters. *)

open Prismel

type scale
type axis = private {
  scale : scale;
  major : float list;
  minor : float list;
}

val domain : scale -> float * float
val range : scale -> float * float
val project : scale -> float -> float
val invert : scale -> float -> float
val linear_scale : domain:float * float -> range:float * float -> scale
val log_scale : ?base:float -> domain:float * float -> range:float * float -> unit -> scale
val lens_scale :
  focus:float -> strength:float -> domain:float * float -> range:float * float -> scale

val ticks : domain:float * float -> step:float -> float list
val linear_axis : ?major:float -> ?minor:float -> domain:float * float -> range:float * float -> unit -> axis
val log_axis : ?base:float -> domain:float * float -> range:float * float -> unit -> axis
val lens_axis : ?major:float -> ?minor:float -> focus:float -> strength:float -> domain:float * float -> range:float * float -> unit -> axis

val uniform_domain_points : domain:float * float -> float list -> (float * float) list
val map_points : x:scale -> y:scale -> (float * float) list -> Vec2.t list
val polar_projection : origin:Vec2.t -> angle:float -> radius:float -> Vec2.t

val line_plot : ?attrs:Svg.attr list -> x:scale -> y:scale -> (float * float) list -> Svg.element
val area_plot : ?attrs:Svg.attr list -> ?baseline:float -> x:scale -> y:scale -> (float * float) list -> Svg.element
val radar_plot : ?attrs:Svg.attr list -> origin:Vec2.t -> angle:scale -> radius:scale -> (float * float) list -> Svg.element
val scatter_plot : ?attrs:Svg.attr list -> ?radius:float -> x:scale -> y:scale -> (float * float) list -> Svg.element
val bar_plot : ?attrs:Svg.attr list -> ?baseline:float -> width:float -> x:scale -> y:scale -> (float * float) list -> Svg.element

val heatmap :
  ?attrs:Svg.attr list ->
  x:scale ->
  y:scale ->
  value_domain:float * float ->
  palette:Color.t list ->
  float array array ->
  Svg.element

val contour_plot :
  ?attrs:Svg.attr list ->
  x:scale ->
  y:scale ->
  levels:float list ->
  palette:Color.t list ->
  float array array ->
  (Svg.element, string) result

val stack_intervals : range:('a -> float * float) -> 'a list -> 'a list list
(** Assign overlapping closed intervals to separate rows, preserving stable
    start-position order. *)

val cartesian_grid : ?attrs:Svg.attr list -> x:axis -> y:axis -> unit -> Svg.element
val cartesian_axes : ?attrs:Svg.attr list -> x:axis -> y:axis -> unit -> Svg.element
val polar_grid : ?attrs:Svg.attr list -> origin:Vec2.t -> angle:axis -> radius:axis -> unit -> Svg.element
val polar_axes :
  ?attrs:Svg.attr list ->
  ?label_attrs:Svg.attr list ->
  origin:Vec2.t ->
  angle:axis ->
  radius:axis ->
  unit ->
  Svg.element
