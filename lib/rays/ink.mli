(** Painter-ordered packed 2D marks published as retained Scene segments.

    Marks land in one reusable vertex/index buffer and merge only with
    adjacent marks of the same color, so painter order matches the equivalent
    Scene rect/line nodes pixel for pixel. Use it when thousands of small marks
    per frame would otherwise be thousands of Scene nodes. *)

type t

val create : ?ids:int64 array -> ?version:int64 -> ?clip:int * int * int * int -> unit -> t
(** [ids] are stable segment ids, used in order by successive {!take}s; once
    exhausted, fresh ids are allocated. [version] tags every published
    segment. [clip] is [(x, y, w, h)] in logical points. *)

val rect : t -> int -> int -> int -> int -> Color.t -> unit

val take : t -> Scene.node option
(** Publishes pending marks as one Scene node and resets the buffer; [None]
    when nothing is pending. *)
