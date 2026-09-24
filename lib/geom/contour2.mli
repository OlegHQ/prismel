(** Deterministic marching-squares contour extraction. *)

val extract : iso:float -> float array array -> (Curve2.t list, string) result
(** Extract open and closed contour polylines in matrix index coordinates.
    Rows are Y and columns are X. *)
