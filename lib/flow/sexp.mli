type position = { line : int; col : int }
type atom = Symbol of string | Keyword of string | Number of string | String of string
type t = { node : node; span : Diagnostic.span; position : position }
and node = Atom of atom | List of t list | Vector of t list | Meta of string * t

val parse : string -> (t list, Diagnostic.t) result
(** Read all forms with 1-based positions and half-open byte spans. *)

val position_of_offset : string -> int -> position
(** Locate a diagnostic byte offset in the original source. *)
