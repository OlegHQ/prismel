(** Versioned persistence for values a sketch keeps in its model.

    The format is PXUI's original [PXUI1] text file, so settings saved by
    earlier sketches load unchanged: one tab-separated, hex-escaped entry per
    line. *)

type value =
  | Bool of bool
  | Float of float
  | Int of int
  | Text of string
  | Choice of string
  | Pair of float * float

type t = (string * value) list

val encode : t -> string
val decode : string -> (t, string) result
(** Malformed lines are errors; later duplicates replace earlier ones. *)

(** Creates missing parent directories before writing. *)
val save : string -> t -> (unit, string) result
val load : string -> (t, string) result

(** Typed lookups; [None] when the name is absent or holds another type. *)

val bool : t -> string -> bool option
val float : t -> string -> float option
val int : t -> string -> int option
val text : t -> string -> string option
val choice : t -> string -> string option
val pair : t -> string -> (float * float) option
