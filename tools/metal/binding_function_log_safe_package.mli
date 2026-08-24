type log_type = Validation
type location = { url : string option; function_name : string option; line : int; column : int }
type log = { log_type : log_type; encoder_label : string option; function_token : int option; location : location option }
type retained = { logs : log list; completed : bool }
val validate_location : location -> (location, string) result
val snapshot_log : log -> (log, string) result
val retain_until_completion : log list -> (retained, string) result
val complete : retained -> retained
val validate_handoff : unit -> unit
