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
val quadratic_to :
  control:float * float -> to_:float * float -> t -> t
val cubic_to :
  control1:float * float ->
  control2:float * float ->
  to_:float * float ->
  t -> t
val close : t -> t
val commands : t -> command list
(** Return commands in drawing order. *)

val points : ?steps:int -> t -> (int * int) list
(* Flatten curves into raster points. *)
val contours : ?steps:int -> t -> (int * int) list list
(* Flatten curves without joining separate [move_to] contours. *)
val is_closed : t -> bool
