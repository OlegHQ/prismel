(** Immutable deterministic random generators.

    Every sampling function returns the sampled value and the next generator.
    A generator can therefore be reproduced, stored in a model, or split for
    independent multicore work without shared mutation. *)

type t

val seed : int -> t
val seed64 : int64 -> t
val split : t -> t * t

val bits : t -> int64 * t
(* Uniform sample in [0, 1). *)
val float : t -> float * t
val range : min:float -> max:float -> t -> float * t
(* Uniform integer in [0, bound). *)
val int : bound:int -> t -> int * t
(* Uniform integer in the inclusive range. *)
val int_range : min:int -> max:int -> t -> int * t
val bool : t -> bool * t
val chance : float -> t -> bool * t

val choose : 'a list -> t -> ('a * t) option
val choose_exn : 'a list -> t -> 'a * t
val shuffle : 'a list -> t -> 'a list * t
val weighted : ('a * float) list -> t -> ('a * t) option
