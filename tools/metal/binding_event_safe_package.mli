type queue = { token : int; destroyed : bool }
type listener
type shared_event
type shared_handle = { event_token : int; device : int; label : string option }
type notification
val create_listener : max_pending:int -> queue option -> (listener, string) result
val destroy_listener : listener -> unit
val listener_queue : listener -> queue option
val create_event : token:int -> device:int -> label:string option -> shared_event
val event_device : shared_event -> int
val export_handle : shared_event -> shared_handle
val notify_at : shared_event -> listener -> value:int64 -> (unit -> unit) -> (notification, string) result
val cancel : notification -> bool
val signal : shared_event -> int64 -> unit
val retained_callback_count : listener -> int
val callback_error_count : listener -> int
val validate_handoff : unit -> unit
