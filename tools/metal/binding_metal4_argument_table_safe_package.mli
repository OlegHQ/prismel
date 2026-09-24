type resource_kind = Buffer | Acceleration_structure | Texture | Sampler
type resource = { token : int; device : int; kind : resource_kind; destroyed : bool }
type t
val callable_ids : string list
val create : available:bool -> device:int -> slot_kinds:resource_kind array -> (t, string) result
val set_resource : t -> buffer_index:int -> resource -> (unit, string) result
val retained_tokens : t -> int list
val submit : t -> (unit, string) result
val complete : t -> unit
val destroy : t -> unit
val validate_handoff : unit -> unit
