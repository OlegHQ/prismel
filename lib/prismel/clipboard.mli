(** Native system clipboard text. Calls must run on the initial domain. *)

val set_text : string -> (unit, string) result
val get_text : unit -> (string, string) result
