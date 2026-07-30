(** Safe coarse-grained parallel computation for sketches.

    Functions passed here must not call SDL, [Graphics], [Scene.render], or
    mutate shared unprotected state. *)

val recommended_domains : unit -> int

val run : ?domains:int -> (unit -> 'a) -> 'a
(** Run a computation with a temporary work-stealing pool. Nested calls reuse
    the current pool. [domains] includes the calling domain. *)

val map : ?grain:int -> ('a -> 'b) -> 'a list -> 'b list
(** Parallel order-preserving map. Small lists run sequentially. *)

val for_ :
  ?chunk_size:int -> start:int -> finish:int -> (int -> unit) -> unit
(** Execute the inclusive integer range. *)

val both : (unit -> 'a) -> (unit -> 'b) -> 'a * 'b
(** Evaluate two sufficiently expensive computations in parallel. *)
