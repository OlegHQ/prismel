type fn = { token : int; device : int; destroyed : bool }
type t
val callable_ids : string list
val create : device:int -> t
val set_binary_functions : t -> fn list option -> (unit, string) result
val set_private_functions : t -> fn list option -> (unit, string) result
val set_groups : t -> (string * fn list) list option -> (unit, string) result
val binary_functions : t -> (fn list option, string) result
val private_functions : t -> (fn list option, string) result
val groups : t -> ((string * fn list) list option, string) result
val retained_tokens : t -> int list
val destroy : t -> unit
val validate_handoff : unit -> unit
