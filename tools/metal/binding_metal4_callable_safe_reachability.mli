type status = Promotable | Blocked
val compute_ids : string list
val generic_ids : string list
val residency_ids : string list
val counter_ids : string list
val callable_ids : string list
val promotable_ids : string list
val blocked_ids : string list
val status : string -> status
val validate : unit -> unit
