type queue_kind = Classic | Metal4
type queue = { token : int; device : int; kind : queue_kind; destroyed : bool }
type scope
val create : device:int -> queue:queue option -> label:string option -> (scope, string) result
val device : scope -> int
val label : scope -> string option
val command_queue : metal4_available:bool -> scope -> (queue option, string) result
val mtl4_command_queue : metal4_available:bool -> scope -> (queue option, string) result
val set_label : scope -> string option -> (scope, string) result
val begin_scope : native_ok:bool -> scope -> (scope, string) result
val end_scope : native_ok:bool -> scope -> (scope, string) result
val is_active : scope -> bool
val validate_handoff : unit -> unit
