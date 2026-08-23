type status = Native_pending_safe | Awaiting_callback_bridge
val queue_feedback_ids : string list
val callback_ids : string list
val items : (string * status) list
val validate : unit -> unit
