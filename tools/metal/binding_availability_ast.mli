(** Exact source sites at which Clang expanded direct
    [AvailabilityAttr] children of a declaration. *)
type site =
  { file : string
  ; line : int
  }

exception Error of string

(** [sites declaration] returns the distinct availability expansion sites of
    [declaration], sorted by file and then line.

    Explicit [expansionLoc] values take precedence over direct locations and
    [spellingLoc] values in [loc], [range.begin], and [range.end]. Every
    selected location must contain one non-empty file and one positive line.
    Ambiguous, malformed, or internal-only availability locations raise
    [Error] instead of being guessed. Only direct children are inspected. *)
val sites : Yojson.Safe.t -> site list

(** Run representative parser checks for current Clang location shapes and
    fail with [Failure] if an invariant regresses. This has no side effects on
    success and is intended for a focused generator test harness. *)
val self_test : unit -> unit
