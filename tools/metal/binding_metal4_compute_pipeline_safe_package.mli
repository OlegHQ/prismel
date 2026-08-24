type descriptor
val callable_ids : string list
val create : available:bool -> (descriptor, string) result
val configure : descriptor -> function_token:int -> linked_functions_token:int option -> max_threads:int -> threadgroup_multiple:bool -> (unit, string) result
val snapshot : descriptor -> ((int * int option * int * bool) option, string) result
val retained_tokens : descriptor -> int list
val reset : descriptor -> (unit, string) result
val destroy : descriptor -> unit
val validate_handoff : unit -> unit
