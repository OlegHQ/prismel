type counter_buffer = { token : int; device : int; sample_count : int; destroyed : bool }
type attachment = { buffer : counter_buffer option; start_index : int; end_index : int }
type t
val callable_ids : string list
val dont_sample : int
val create : device:int -> max_attachments:int -> attachment option array -> (t, string) result
val attachment : t -> index:int -> (attachment option, string) result
val set_attachment : t -> index:int -> attachment option -> (unit, string) result
val sample_buffer : attachment -> counter_buffer option
val retained_tokens : t -> int list
val reset : t -> unit
val validate_handoff : unit -> unit
