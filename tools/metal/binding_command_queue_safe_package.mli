type log_state = { token : int; device : int; destroyed : bool }
type descriptor = { max_command_buffer_count : int; log_state : log_state option }
type queue = { token : int; device : int; label : string option; capture_active : bool; destroyed : bool }
type command_buffer = { token : int; queue_token : int; retains_references : bool; ocaml_retained : bool }
val create_descriptor : max_command_buffer_count:int -> log_state:log_state option -> (descriptor, string) result
val replace_log_state : device:int -> descriptor -> log_state option -> (descriptor, string) result
val snapshot_label : queue -> string option -> (queue, string) result
val create_command_buffer : queue -> token:int -> retained_references:bool -> (command_buffer, string) result
val insert_capture_boundary : queue -> (unit, string) result
val validate_handoff : unit -> unit
