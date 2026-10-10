(** Immutable paths for custom sketch geometry. *)

type t
type fill_rule = Even_odd | Non_zero
type command =
  | Move_to of float * float
  | Line_to of float * float
  | Quadratic_to of (float * float) * (float * float)
  | Cubic_to of (float * float) * (float * float) * (float * float)
  | Close

val empty : t
val move_to : float -> float -> t -> t
val line_to : float -> float -> t -> t
val close : t -> t

val points : ?steps:int -> t -> (int * int) list
(* Flatten curves into raster points. *)
(* Flatten curves without joining separate [move_to] contours. *)
val is_closed : t -> bool
