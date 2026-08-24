type level = Undefined | Debug | Info | Notice | Error | Fault
type descriptor = { level : level; buffer_size : int }
type state
type handler
val create_descriptor : max_buffer_size:int -> level:level -> buffer_size:int -> (descriptor, string) result
val create_state : max_handlers:int -> (state, string) result
val add_handler : state -> (level -> string option -> unit) -> (handler, string) result
val cancel : handler -> bool
val emit : state -> level -> string option -> unit
val rooted_handler_count : state -> int
val handler_error_count : state -> int
val cleanup : state -> unit
val validate_handoff : unit -> unit
