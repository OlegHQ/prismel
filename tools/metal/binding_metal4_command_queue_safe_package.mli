type resource = { token : int; device : int; destroyed : bool }
type buffer = { resource : resource; length : int }
type texture = { resource : resource; width : int; height : int; levels : int; slices : int }
type buffer_copy = { source_offset : int; length : int; destination_offset : int }
type texture_copy = { source_level : int; source_slice : int; x : int; y : int; width : int; height : int; destination_level : int; destination_slice : int }
type queue
val callable_ids : string list
val create : available:bool -> device:int -> (queue, string) result
val add_residency_set : queue -> resource -> (unit, string) result
val copy_buffer_mappings : queue -> source:buffer -> destination:buffer -> buffer_copy list -> (unit, string) result
val copy_texture_mappings : queue -> source:texture -> destination:texture -> texture_copy list -> (unit, string) result
val signal_drawable : queue -> resource -> (unit, string) result
val wait_for_drawable : queue -> resource -> (unit, string) result
val wait_for_event : queue -> resource -> value:int64 -> (unit, string) result
val retained_tokens : queue -> int list
val complete : queue -> unit
val destroy : queue -> unit
val validate_handoff : unit -> unit
