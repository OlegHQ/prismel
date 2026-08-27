(** Backend-neutral paths, deterministic adaptive flattening, and fill tessellation. *)

type point = { x : float; y : float }

type command =
  | Move_to of point
  | Line_to of point
  | Quadratic_to of point * point
  | Cubic_to of point * point * point
  | Close

type t
type fill_rule = Even_odd | Non_zero
type mesh = { vertices : point array; indices : int array }

type error =
  | Empty_path
  | Invalid_tolerance of float
  | Non_finite_point of point
  | Missing_current_point
  | Open_contour
  | Complexity_limit

val of_commands : command array -> t
val commands : t -> command array
val flatten : tolerance:float -> t -> (point array array, error) result
val tessellate : tolerance:float -> fill_rule:fill_rule -> t -> (mesh, error) result
