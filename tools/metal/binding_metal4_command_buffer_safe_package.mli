type owned = { token : int; device : int; destroyed : bool }
type options
type t
type child
val callable_ids : string list
val create_options : available:bool -> (options, string) result
val set_log_state : device:int -> options -> owned option -> (unit, string) result
val log_state : options -> owned option
val destroy_options : options -> unit
val create : available:bool -> device:int -> t
val begin_buffer : t -> allocator:owned -> options:options -> (unit, string) result
val render_encoder : t -> descriptor:owned -> encoder_options:int -> native_token:int -> (child, string) result
val machine_learning_encoder : supported:bool -> t -> native_token:int -> (child, string) result
val end_child : child -> (unit, string) result
val child_token : child -> int
val add_completion_handler : t -> (unit -> unit) -> (unit, string) result
val end_buffer : t -> (unit, string) result
val complete : t -> unit
val retained_tokens : t -> int list
val callback_error_count : t -> int
val validate_handoff : unit -> unit
