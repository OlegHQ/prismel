(** Optional, domain-local edit instrumentation. The host supplies its clock;
    Flow acquires no platform dependency. Durations exclude nested phases. *)
type phase = Print | Parse | Check | Evaluate | Lower | Project | Layout | Reduce | Cook
type entry = { phase : phase; calls : int; seconds : float }
type t = { total : float; entries : entry list }
val phases : phase list
val name : phase -> string
val empty : t
val sample : clock:(unit -> float) -> (unit -> 'a) -> 'a * t
(** Nested samples contribute to the enclosing sample and return its cumulative
    entries. The outermost sample supplies the clock and restores instrumentation
    on exceptions. Backward clock readings are clamped. *)

val measure : phase -> (unit -> 'a) -> 'a
val calls : t -> phase -> int
val seconds : t -> phase -> float
val summary : t -> string
