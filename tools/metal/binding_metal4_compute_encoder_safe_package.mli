type owned = { token : int; device : int; destroyed : bool }
type buffer = { owned : owned; length : int }
type buffer_range = { buffer : buffer; offset : int; length : int }
type acceleration_structure = { owned : owned }
type as_descriptor = { owned : owned; primitive_count : int }
type tensor = { owned : owned; dimensions : int array }
type t
val callable_ids : string list
val create : available:bool -> device:int -> (t, string) result
val build : t -> destination:acceleration_structure -> descriptor:as_descriptor -> scratch:buffer_range -> (unit, string) result
val refit : t -> source:acceleration_structure -> descriptor:as_descriptor -> destination:acceleration_structure option -> scratch:buffer_range -> options:int -> (unit, string) result
val write_compacted_size : t -> acceleration_structure -> buffer_range -> (unit, string) result
val copy_tensor : t -> source:tensor -> source_origin:int array -> source_dimensions:int array -> destination:tensor -> destination_origin:int array -> destination_dimensions:int array -> (unit, string) result
val retained_tokens : t -> int list
val end_encoding : t -> (unit, string) result
val complete : t -> unit
val destroy : t -> unit
val validate_handoff : unit -> unit
