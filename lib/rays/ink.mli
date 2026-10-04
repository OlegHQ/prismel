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

val fresh_id : unit -> int64
(** A process-unique segment id for [create ~ids]. *)

val set_clip : t -> (int * int * int * int) option -> unit
(** Raises [Invalid_argument] while marks are pending; {!take} them first. *)

val set_ids : t -> int64 array -> unit
(** Replaces the segment ids and restarts at the first. Raises
    [Invalid_argument] while marks are pending. *)

val rect : t -> int -> int -> int -> int -> Color.t -> unit
val rectf : t -> float -> float -> float -> float -> Color.t -> unit
(** [rectf t x y w h color] fills without snapping; empty sizes are skipped. *)

val outline : t -> int -> int -> int -> int -> Color.t -> unit
val line : t -> int -> int -> int -> int -> Color.t -> unit
(** One-point-wide line matching [Scene.line]. *)

val linef : t -> float -> float -> float -> float -> Color.t -> unit
(** One-point-wide butt-capped stroke between fractional endpoints. *)

val take : t -> Scene.node option
(** Publishes pending marks as one Scene node and resets the buffer; [None]
    when nothing is pending. *)
