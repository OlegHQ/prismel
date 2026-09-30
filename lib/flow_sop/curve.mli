(** The lowered [sop/curve]: a polyline whose [points] parameter is a
    text-encoded list, so a live list (Wave) is one driven parameter and the
    points are part of the cook identity. *)

val key : string
(** ["flow.curve"]. *)

val parameter : string
(** ["points"]. *)

val encode : (float * float * float) array -> string
(** Lossless (hexadecimal floats), deterministic. *)

val decode : string -> ((float * float * float) array, string) result
val factory : Procedural.Edit_graph.factory
