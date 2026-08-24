type t
val callable_ids : string list
val create : available:bool -> native_label:string option -> (t, string) result
val label : t -> (string option, string) result
val refresh_label : t -> native_label:string option -> (unit, string) result
val begin_use : t -> (unit, string) result
val end_use : t -> (unit, string) result
val destroy : t -> (unit, string) result
val validate_handoff : unit -> unit
