type status = Promotable | Native_pending_safe
val queue_feedback_ids : string list
val specialization_ids : string list
val promotable_ids : string list
val items : (string * status) list
val validate : unit -> unit
