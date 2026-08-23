type item = { id : string; public_representation : string option }
val items : item list
val promotable_ids : string list
val blocked_ids : string list
val runtime_property_handoff : (string * string * string) list
val validate : unit -> unit
