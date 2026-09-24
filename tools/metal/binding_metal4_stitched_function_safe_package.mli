type fn = { token : int; device : int; destroyed : bool }
type graph = { token : int; device : int; functions : fn list; destroyed : bool }
type t
val callable_ids : string list
val create : device:int -> descriptors:fn list option -> graph:graph option -> (t, string) result
val set_pair : t -> descriptors:fn list option -> graph:graph option -> (unit, string) result
val function_graph : t -> graph option
val retained_tokens : t -> int list
val destroy : t -> unit
val validate_handoff : unit -> unit
