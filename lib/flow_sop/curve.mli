(** The lowered [sop/curve]: a polyline whose [points] parameter is a
    text-encoded list, so a live list (Wave) is one driven parameter and the
    points are part of the cook identity; [closed] joins the last point to the
    first. *)

val parameter : string
(** ["points"]. *)

val closed_parameter : string
(** ["closed"]. *)

val encode : (float * float * float) array -> string
(** Lossless (hexadecimal floats), deterministic. *)

val factory : Sop.Edit_graph.factory
