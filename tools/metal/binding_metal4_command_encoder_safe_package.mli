type fence = { token : int; device : int; value : int64; destroyed : bool }
type t
val callable_ids : string list
val create : available:bool -> device:int -> (t, string) result
val wait_for_fence : t -> fence -> before_stages:int64 -> (unit, string) result
val retained_fence_tokens : t -> int list
val end_encoding : t -> (unit, string) result
val complete : t -> unit
val destroy : t -> unit
val validate_handoff : unit -> unit
